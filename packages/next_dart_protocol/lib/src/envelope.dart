// packages/next_dart_protocol/lib/src/envelope.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'canonical.dart';
import 'component.dart';
import 'crypto.dart';
import 'errors.dart';
import 'node.dart';
import 'version.dart';

const String kAlg = 'ed25519+aesgcm256';

/// The decrypted payload of an envelope.
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

/// Build a signed + encrypted wire envelope (UTF-8 JSON bytes).
Future<List<int>> encodeEnvelope({
  required EnvelopeContent content,
  required String route,
  required int contentVersion,
  required String minClientVersion,
  required String keyId,
  required SecretKey secretKey,
  required SimpleKeyPair signingKeyPair,
}) async {
  final plain = utf8.encode(jsonEncode({
    'root': content.root.toJson(),
    'components': content.components.map((c) => c.toJson()).toList(),
    'data': content.data,
  }));
  final sealed = await NdCipher().encrypt(plain, secretKey);
  final header = <String, Object?>{
    'protocolVersion': kProtocolVersion,
    'contentVersion': contentVersion,
    'minClientVersion': minClientVersion,
    'route': route,
    'payloadFormat': 'json',
    'alg': kAlg,
    'keyId': keyId,
    'nonce': base64.encode(sealed.nonce),
    'cipherText': base64.encode(sealed.cipherText),
    'mac': base64.encode(sealed.mac),
  };
  final sig = await NdSigner().sign(canonicalJsonBytes(header), signingKeyPair);
  final wire = <String, Object?>{...header, 'signature': base64.encode(sig)};
  return utf8.encode(jsonEncode(wire));
}

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

  final minClient = header['minClientVersion'] as String;
  if (semverLt(clientVersion, minClient)) {
    throw UpdateRequiredError(minClient);
  }

  final plain = await NdCipher().decrypt(
    base64.decode(header['cipherText'] as String),
    base64.decode(header['nonce'] as String),
    base64.decode(header['mac'] as String),
    secretKey,
  );
  final body = (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
  return EnvelopeContent(
    root: NdNode.fromJson((body['root'] as Map).cast<String, Object?>()),
    components: ((body['components'] as List?) ?? const [])
        .map((e) => NdComponentDef.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    data: ((body['data'] as Map?)?.cast<String, Object?>()) ?? const {},
  );
}
