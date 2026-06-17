// packages/next_dart_protocol/lib/src/handshake.dart
//
// F8 — authenticated X25519 ECDH handshake with HKDF session-key derivation.
//
// Goal: derive a fresh per-session AES-256-GCM key over an UNTRUSTED channel,
// such that (a) a passive eavesdropper learns nothing (ECDH), (b) the session
// key changes every handshake (forward secrecy: ephemeral keys are discarded),
// and (c) an active MITM cannot impersonate the server (the server's ephemeral
// X25519 public key is SIGNED by its long-term Ed25519 identity key, which the
// client pins).
//
// Flow:
//   1. Client makes an ephemeral X25519 keypair (privC, pubC), sends pubC.
//   2. Server makes an ephemeral X25519 keypair (privS, pubS), computes
//      shared = X25519(privS, pubC), derives sessionKey = HKDF(shared), and
//      SIGNS canonical bytes of {pubS, pubC, keyId, expiresAtMillis} with its
//      long-term Ed25519 key. It returns {pubS, keyId, expiresAtMillis, sig}.
//   3. Client verifies the signature with the PINNED Ed25519 key over the SAME
//      canonical bytes — using ITS OWN pubC. Because pubC and pubS are both in
//      the signed message, a valid signature proves: this response was produced
//      by the real server, for THIS client's pubC, binding THIS keyId/expiry.
//      The client then computes shared = X25519(privC, pubS) and derives the
//      identical sessionKey.
//
// KDF parameters (MUST be identical on both sides):
//   * info = utf8('next-dart/x25519-aesgcm/v1')  — fixed domain separator.
//   * salt = utf8(keyId)                          — binds the derived key to the
//     rotating keyId. keyId is one of the signed fields, so both sides agree on
//     it and a tampered keyId both breaks the signature AND changes the salt.
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'canonical.dart';
import 'crypto.dart';
import 'errors.dart';

/// Fixed HKDF `info` (domain separation). Bump the version suffix if the
/// handshake construction ever changes.
final List<int> kHandshakeInfo = utf8.encode('next-dart/x25519-aesgcm/v1');

final X25519 _x25519 = X25519();
final NdSigner _signer = NdSigner();

/// The client's `POST /__handshake` request body: just its ephemeral X25519
/// public key, base64-encoded.
class HandshakeRequest {
  /// base64 of the client's ephemeral X25519 public key bytes.
  final String x25519Pub;
  const HandshakeRequest({required this.x25519Pub});

  Map<String, Object?> toJson() => {'x25519Pub': x25519Pub};

  factory HandshakeRequest.fromJson(Map<String, Object?> json) {
    final pub = json['x25519Pub'];
    if (pub is! String) {
      throw HandshakeError('handshake request missing string x25519Pub');
    }
    return HandshakeRequest(x25519Pub: pub);
  }
}

/// The server's `POST /__handshake` response body. Everything except the bare
/// signature is part of the signed message.
class HandshakeResponse {
  /// base64 of the server's ephemeral X25519 public key bytes.
  final String x25519Pub;

  /// The session key id the client must attach (`kid`) to subsequent requests.
  final String keyId;

  /// Wall-clock expiry of the session, in epoch milliseconds.
  final int expiresAtMillis;

  /// base64 of the server's Ed25519 signature over the canonical signing bytes
  /// of {pubS, pubC, keyId, expiresAtMillis}.
  final String signature;

  const HandshakeResponse({
    required this.x25519Pub,
    required this.keyId,
    required this.expiresAtMillis,
    required this.signature,
  });

  Map<String, Object?> toJson() => {
        'x25519Pub': x25519Pub,
        'keyId': keyId,
        'expiresAtMillis': expiresAtMillis,
        'signature': signature,
      };

  factory HandshakeResponse.fromJson(Map<String, Object?> json) {
    final pub = json['x25519Pub'];
    final keyId = json['keyId'];
    final expires = json['expiresAtMillis'];
    final sig = json['signature'];
    if (pub is! String ||
        keyId is! String ||
        expires is! int ||
        sig is! String) {
      throw HandshakeError('handshake response is missing or has malformed '
          'fields (x25519Pub, keyId, expiresAtMillis, signature)');
    }
    return HandshakeResponse(
      x25519Pub: pub,
      keyId: keyId,
      expiresAtMillis: expires,
      signature: sig,
    );
  }
}

/// What [buildHandshakeResponse] returns to the server: the wire [response] to
/// send back, plus the derived [sessionKey] the server must store under
/// `response.keyId` so it can decrypt subsequent requests bearing that `kid`.
class ServerHandshakeResult {
  final HandshakeResponse response;
  final SecretKey sessionKey;
  const ServerHandshakeResult(this.response, this.sessionKey);
}

/// The canonical message bytes that the server signs and the client verifies.
///
/// Binding ALL of {pubS, pubC, keyId, expiresAtMillis} into one signed message
/// is what makes the handshake safe:
///   * pubS — authenticates the server's ephemeral key (defeats MITM key swap);
///   * pubC — binds the response to THIS client's ephemeral key (defeats replay
///     of a response captured from another client's handshake);
///   * keyId / expiresAtMillis — prevents an attacker from re-pointing the
///     session to a different id or extending its lifetime.
///
/// Uses [canonicalJsonBytes] so server and client deterministically agree on
/// the exact bytes regardless of map ordering.
List<int> handshakeSigningBytes({
  required List<int> serverPubBytes,
  required List<int> clientPubBytes,
  required String keyId,
  required int expiresAtMillis,
}) =>
    canonicalJsonBytes(<String, Object?>{
      'pubS': base64.encode(serverPubBytes),
      'pubC': base64.encode(clientPubBytes),
      'keyId': keyId,
      'expiresAtMillis': expiresAtMillis,
    });

/// Derive the 32-byte AES-256-GCM session key from an ECDH [sharedSecret].
///
/// salt = utf8(keyId), info = [kHandshakeInfo]. Deterministic: identical inputs
/// always yield identical key bytes, so both sides converge.
Future<SecretKey> deriveSessionKey({
  required SecretKey sharedSecret,
  required String keyId,
}) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  return hkdf.deriveKey(
    secretKey: sharedSecret,
    nonce: utf8.encode(keyId), // HKDF "salt"
    info: kHandshakeInfo,
  );
}

/// SERVER side. Given the client's ephemeral X25519 public key bytes and the
/// allocated [keyId]/[expiresAtMillis], generate a server ephemeral keypair,
/// run ECDH, derive the session key, and sign the binding message with the
/// server's long-term Ed25519 key.
///
/// Returns the wire [HandshakeResponse] plus the derived session key for the
/// server's session store.
Future<ServerHandshakeResult> buildHandshakeResponse({
  required List<int> clientPubBytes,
  required SimpleKeyPair serverEd25519,
  required String keyId,
  required int expiresAtMillis,
}) async {
  // Fresh ephemeral X25519 keypair — discarded after this call, giving forward
  // secrecy: compromising the long-term Ed25519 key later does NOT reveal past
  // session keys, because the X25519 private keys are gone.
  final serverEphemeral = await _x25519.newKeyPair();
  final serverPub = await serverEphemeral.extractPublicKey();

  final clientPub =
      SimplePublicKey(clientPubBytes, type: KeyPairType.x25519);
  final shared = await _x25519.sharedSecretKey(
    keyPair: serverEphemeral,
    remotePublicKey: clientPub,
  );
  final sessionKey = await deriveSessionKey(sharedSecret: shared, keyId: keyId);

  final signingBytes = handshakeSigningBytes(
    serverPubBytes: serverPub.bytes,
    clientPubBytes: clientPubBytes,
    keyId: keyId,
    expiresAtMillis: expiresAtMillis,
  );
  final sig = await _signer.sign(signingBytes, serverEd25519);

  final response = HandshakeResponse(
    x25519Pub: base64.encode(serverPub.bytes),
    keyId: keyId,
    expiresAtMillis: expiresAtMillis,
    signature: base64.encode(sig),
  );
  return ServerHandshakeResult(response, sessionKey);
}

/// CLIENT side. Verify [response]'s signature against the PINNED server Ed25519
/// key over the binding message built from the server's pubS, THIS client's
/// [clientPubBytes], and the response's keyId/expiresAt. On success, run ECDH
/// with the client's ephemeral keypair and derive the identical session key.
///
/// Throws [HandshakeError] if the signature does not verify (bad/forged
/// signature, swapped server ephemeral key, tampered keyId/expiresAt, or a
/// response minted for a different client's pubC).
Future<SecretKey> verifyAndDeriveClientSession({
  required HandshakeResponse response,
  required SimpleKeyPair clientKeyPair,
  required List<int> clientPubBytes,
  required SimplePublicKey pinnedServerEd25519Pub,
}) async {
  final List<int> serverPubBytes;
  final List<int> sigBytes;
  try {
    serverPubBytes = base64.decode(response.x25519Pub);
    sigBytes = base64.decode(response.signature);
  } catch (e) {
    throw HandshakeError('handshake response has malformed base64: $e');
  }

  // Reconstruct the EXACT bytes the server should have signed, using OUR pubC.
  final signingBytes = handshakeSigningBytes(
    serverPubBytes: serverPubBytes,
    clientPubBytes: clientPubBytes,
    keyId: response.keyId,
    expiresAtMillis: response.expiresAtMillis,
  );

  final bool ok;
  try {
    ok = await _signer.verify(signingBytes, sigBytes, pinnedServerEd25519Pub);
  } catch (e) {
    throw HandshakeError('signature verification errored: $e');
  }
  if (!ok) {
    throw HandshakeError(
        'server handshake signature did not verify against the pinned key '
        '(possible MITM, replay, or tampered keyId/expiresAt)');
  }

  // Signature valid → pubS is authentic and bound to our pubC. Complete ECDH.
  final serverPub =
      SimplePublicKey(serverPubBytes, type: KeyPairType.x25519);
  final shared = await _x25519.sharedSecretKey(
    keyPair: clientKeyPair,
    remotePublicKey: serverPub,
  );
  return deriveSessionKey(sharedSecret: shared, keyId: response.keyId);
}
