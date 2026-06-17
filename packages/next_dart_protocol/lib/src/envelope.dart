// packages/next_dart_protocol/lib/src/envelope.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'binary_codec.dart';
import 'canonical.dart';
import 'component.dart';
import 'crypto.dart';
import 'envelope_body.dart';
import 'errors.dart';
import 'node.dart';
import 'version.dart';

export 'envelope_body.dart' show EnvelopeBody;

const String kAlg = 'ed25519+aesgcm256';

/// Selects the payload encoding used inside the AEAD ciphertext.
///
/// The value names match the `payloadFormat` header field values on the wire.
enum NdPayloadFormat {
  /// Plaintext is UTF-8 JSON `{root, components, data}` (default; back-compat).
  json,

  /// Plaintext is a compact binary blob produced by [encodeTreeBinary].
  ndBinary,
}

/// The decrypted payload of an envelope (public API type; same shape as
/// [EnvelopeBody] for convenience).
class EnvelopeContent {
  final NdNode root;
  final List<NdComponentDef> components;
  final Map<String, Object?> data;
  const EnvelopeContent({
    required this.root,
    this.components = const [],
    this.data = const {},
  });
}

// ---------------------------------------------------------------------------
// Conversion helpers between EnvelopeContent and EnvelopeBody
// ---------------------------------------------------------------------------

EnvelopeBody _contentToBody(EnvelopeContent c) =>
    EnvelopeBody(root: c.root, components: c.components, data: c.data);

EnvelopeContent _bodyToContent(EnvelopeBody b) =>
    EnvelopeContent(root: b.root, components: b.components, data: b.data);

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

/// Build a signed + encrypted wire envelope (UTF-8 JSON bytes).
///
/// [format] selects the plaintext encoding inside the AEAD ciphertext.
/// Defaults to [NdPayloadFormat.json] for backward compatibility.
Future<List<int>> encodeEnvelope({
  required EnvelopeContent content,
  required String route,
  required int contentVersion,
  required String minClientVersion,
  required String keyId,
  required SecretKey secretKey,
  required SimpleKeyPair signingKeyPair,
  NdPayloadFormat format = NdPayloadFormat.json,
}) async {
  final body = _contentToBody(content);

  final List<int> plain;
  final String payloadFormatHeader;

  switch (format) {
    case NdPayloadFormat.json:
      plain = utf8.encode(jsonEncode({
        'root': body.root.toJson(),
        'components': body.components.map((c) => c.toJson()).toList(),
        'data': body.data,
      }));
      payloadFormatHeader = 'json';
    case NdPayloadFormat.ndBinary:
      plain = encodeTreeBinary(body);
      payloadFormatHeader = 'ndBinary';
  }

  final sealed = await NdCipher().encrypt(plain, secretKey);
  final header = <String, Object?>{
    'protocolVersion': kProtocolVersion,
    'contentVersion': contentVersion,
    'minClientVersion': minClientVersion,
    'route': route,
    'payloadFormat': payloadFormatHeader,
    'alg': kAlg,
    'keyId': keyId,
    'nonce': base64.encode(sealed.nonce),
    'cipherText': base64.encode(sealed.cipherText),
    'mac': base64.encode(sealed.mac),
  };
  final sig =
      await NdSigner().sign(canonicalJsonBytes(header), signingKeyPair);
  final wire = <String, Object?>{...header, 'signature': base64.encode(sig)};
  return utf8.encode(jsonEncode(wire));
}

// ---------------------------------------------------------------------------
// Header-only read (no crypto)
// ---------------------------------------------------------------------------

/// Extract the `keyId` field from a signed+encrypted envelope WITHOUT performing
/// any cryptographic verification. Used by the client as a defence-in-depth
/// check: after [decodeEnvelope] succeeds (GCM + signature verified), compare
/// the returned keyId against the kid that was sent, to surface any mismatch
/// with a clear error rather than silently relying only on the GCM MAC.
///
/// Returns null if the bytes cannot be parsed as envelope JSON or if the
/// `keyId` field is absent / not a String — callers treat null as "unknown".
String? decodeEnvelopeKeyId(List<int> bytes) {
  try {
    final wire =
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    final v = wire['keyId'];
    return v is String ? v : null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

/// Verify, version-check, and decrypt a wire envelope.
Future<EnvelopeContent> decodeEnvelope(
  List<int> bytes, {
  required SecretKey secretKey,
  required SimplePublicKey signingPublicKey,
  required String clientVersion,
}) async {
  late final Map<String, Object?> wire;
  try {
    wire = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
  } catch (e) {
    throw DecodeError('not valid envelope JSON: $e');
  }
  final sigB64 = wire['signature'];
  if (sigB64 is! String) throw DecodeError('missing signature');
  final header = Map<String, Object?>.from(wire)..remove('signature');

  final ok = await NdSigner().verify(
    canonicalJsonBytes(header),
    base64.decode(sigB64),
    signingPublicKey,
  );
  if (!ok) throw SignatureError();

  // Guard version check: a malformed minClientVersion must surface as DecodeError.
  final minClientRaw = header['minClientVersion'];
  if (minClientRaw is! String) {
    throw DecodeError('missing or non-string minClientVersion');
  }
  try {
    if (semverLt(clientVersion, minClientRaw)) {
      throw UpdateRequiredError(minClientRaw);
    }
  } on UpdateRequiredError {
    rethrow;
  } on Exception catch (e) {
    throw DecodeError('malformed minClientVersion "$minClientRaw": $e');
  }

  // Post-signature field extraction + decrypt: any missing/malformed field
  // becomes a DecodeError.
  try {
    final cipherTextRaw = header['cipherText'];
    if (cipherTextRaw is! String) throw DecodeError('missing cipherText field');
    final nonceRaw = header['nonce'];
    if (nonceRaw is! String) throw DecodeError('missing nonce field');
    final macRaw = header['mac'];
    if (macRaw is! String) throw DecodeError('missing mac field');

    final plain = await NdCipher().decrypt(
      base64.decode(cipherTextRaw),
      base64.decode(nonceRaw),
      base64.decode(macRaw),
      secretKey,
    );

    // Dispatch on payloadFormat.
    final formatRaw = header['payloadFormat'];
    final EnvelopeBody body;
    switch (formatRaw) {
      case 'json':
      case null: // back-compat: absent header → assume json
        final map =
            (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
        body = EnvelopeBody(
          root:
              NdNode.fromJson((map['root'] as Map).cast<String, Object?>()),
          components: ((map['components'] as List?) ?? const [])
              .map((e) =>
                  NdComponentDef.fromJson((e as Map).cast<String, Object?>()))
              .toList(),
          data:
              ((map['data'] as Map?)?.cast<String, Object?>()) ?? const {},
        );
      case 'ndBinary':
        // plain is List<int> from NdCipher.decrypt; convert to Uint8List.
        final uint8 = plain is Uint8List
            ? plain
            : Uint8List.fromList(plain as List<int>);
        body = decodeTreeBinary(uint8);
      default:
        throw DecodeError('unknown payloadFormat: "$formatRaw"');
    }

    return _bodyToContent(body);
  } on SignatureError {
    rethrow;
  } on UpdateRequiredError {
    rethrow;
  } on DecodeError {
    rethrow;
  } on Exception catch (e) {
    throw DecodeError('malformed envelope: $e');
  }
}
