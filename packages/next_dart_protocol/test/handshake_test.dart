// packages/next_dart_protocol/test/handshake_test.dart
//
// TDD for F8 — authenticated X25519 ECDH handshake with HKDF session-key
// derivation. These tests exercise the protocol-level helpers end to end:
//   * a full round-trip in which the server builds a signed response for the
//     client's ephemeral public key, the client verifies + derives, and BOTH
//     sides end up with a byte-identical session key (proven by encrypting on
//     one side and decrypting on the other);
//   * adversarial cases — a MITM that swaps the server's ephemeral X25519 key,
//     a response signed by the wrong Ed25519 key, channel-binding to the wrong
//     client pubC, and tampering with the signed keyId / expiresAtMillis
//     fields — each of which must throw HandshakeError.
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/src/crypto.dart';
import 'package:next_dart_protocol/src/errors.dart';
import 'package:next_dart_protocol/src/handshake.dart';
import 'package:test/test.dart';

void main() {
  final x = X25519();

  // Long-term server identity key (the one the client pins).
  late SimpleKeyPair serverEd25519;
  late SimplePublicKey serverEd25519Pub;

  // Fresh client ephemeral keypair per test.
  late SimpleKeyPair clientKp;
  late List<int> clientPubBytes;

  const keyId = 's-1';
  const expiresAtMillis = 1750000000000;

  setUp(() async {
    serverEd25519 = await Ed25519().newKeyPair();
    serverEd25519Pub = await serverEd25519.extractPublicKey();

    clientKp = await x.newKeyPair();
    final clientPub = await clientKp.extractPublicKey();
    clientPubBytes = clientPub.bytes;
  });

  Future<ServerHandshakeResult> serverSide() => buildHandshakeResponse(
        clientPubBytes: clientPubBytes,
        serverEd25519: serverEd25519,
        keyId: keyId,
        expiresAtMillis: expiresAtMillis,
      );

  test('round-trip: both sides derive a byte-identical session key', () async {
    final server = await serverSide();
    final resp = server.response;

    // The response is well-formed.
    expect(resp.keyId, keyId);
    expect(resp.expiresAtMillis, expiresAtMillis);
    expect(resp.x25519Pub, isNotEmpty);
    expect(resp.signature, isNotEmpty);

    // Client verifies the pinned signature and derives its session key.
    final clientKey = await verifyAndDeriveClientSession(
      response: resp,
      clientKeyPair: clientKp,
      clientPubBytes: clientPubBytes,
      pinnedServerEd25519Pub: serverEd25519Pub,
    );

    // Both derived keys must be byte-identical.
    final clientBytes = await clientKey.extractBytes();
    final serverBytes = await server.sessionKey.extractBytes();
    expect(clientBytes, equals(serverBytes),
        reason: 'client and server must derive identical session keys');

    // End-to-end AEAD: encrypt with the server key, decrypt with the client
    // key (and vice-versa) — proving the keys are interchangeable.
    final cipher = NdCipher();
    final s2c = await cipher.encrypt(
        utf8.encode('server -> client'), server.sessionKey);
    expect(
      utf8.decode(
          await cipher.decrypt(s2c.cipherText, s2c.nonce, s2c.mac, clientKey)),
      'server -> client',
    );
    final c2s =
        await cipher.encrypt(utf8.encode('client -> server'), clientKey);
    expect(
      utf8.decode(await cipher.decrypt(
          c2s.cipherText, c2s.nonce, c2s.mac, server.sessionKey)),
      'client -> server',
    );
  });

  test('MITM swapping the server ephemeral X25519 key fails HandshakeError',
      () async {
    final resp = (await serverSide()).response;

    // Attacker substitutes a DIFFERENT X25519 public key (their own), hoping
    // the client will derive a shared secret with the attacker instead of the
    // real server. The signature no longer matches the swapped key.
    final attackerKp = await x.newKeyPair();
    final attackerPub = await attackerKp.extractPublicKey();
    final tampered = HandshakeResponse(
      x25519Pub: base64.encode(attackerPub.bytes),
      keyId: resp.keyId,
      expiresAtMillis: resp.expiresAtMillis,
      signature: resp.signature, // stale signature over the REAL server key
    );

    expect(
      () => verifyAndDeriveClientSession(
        response: tampered,
        clientKeyPair: clientKp,
        clientPubBytes: clientPubBytes,
        pinnedServerEd25519Pub: serverEd25519Pub,
      ),
      throwsA(isA<HandshakeError>()),
    );
  });

  test('response signed by the WRONG Ed25519 key fails HandshakeError',
      () async {
    final wrongServer = await Ed25519().newKeyPair();
    final resp = (await buildHandshakeResponse(
      clientPubBytes: clientPubBytes,
      serverEd25519: wrongServer, // signs with the attacker's identity key
      keyId: keyId,
      expiresAtMillis: expiresAtMillis,
    ))
        .response;

    // Client pins the REAL server key, so verification must fail.
    expect(
      () => verifyAndDeriveClientSession(
        response: resp,
        clientKeyPair: clientKp,
        clientPubBytes: clientPubBytes,
        pinnedServerEd25519Pub: serverEd25519Pub,
      ),
      throwsA(isA<HandshakeError>()),
    );
  });

  test('tampering with signed keyId fails HandshakeError', () async {
    final resp = (await serverSide()).response;
    final tampered = HandshakeResponse(
      x25519Pub: resp.x25519Pub,
      keyId: 'forged-key-id', // signed field changed
      expiresAtMillis: resp.expiresAtMillis,
      signature: resp.signature,
    );
    expect(
      () => verifyAndDeriveClientSession(
        response: tampered,
        clientKeyPair: clientKp,
        clientPubBytes: clientPubBytes,
        pinnedServerEd25519Pub: serverEd25519Pub,
      ),
      throwsA(isA<HandshakeError>()),
    );
  });

  test('tampering with signed expiresAtMillis fails HandshakeError', () async {
    final resp = (await serverSide()).response;
    final tampered = HandshakeResponse(
      x25519Pub: resp.x25519Pub,
      keyId: resp.keyId,
      expiresAtMillis: resp.expiresAtMillis + 99999999, // extend lifetime
      signature: resp.signature,
    );
    expect(
      () => verifyAndDeriveClientSession(
        response: tampered,
        clientKeyPair: clientKp,
        clientPubBytes: clientPubBytes,
        pinnedServerEd25519Pub: serverEd25519Pub,
      ),
      throwsA(isA<HandshakeError>()),
    );
  });

  test('binding: a response for a DIFFERENT clientPubC fails for this client',
      () async {
    // The server builds a perfectly valid, correctly-signed response — but for
    // some OTHER client's ephemeral public key. If a MITM replays it to us, the
    // signed pubC will not match our pubC, so verification must fail. This is
    // the channel-binding property.
    final otherClientKp = await x.newKeyPair();
    final otherClientPub = await otherClientKp.extractPublicKey();
    final respForOther = (await buildHandshakeResponse(
      clientPubBytes: otherClientPub.bytes,
      serverEd25519: serverEd25519,
      keyId: keyId,
      expiresAtMillis: expiresAtMillis,
    ))
        .response;

    expect(
      () => verifyAndDeriveClientSession(
        response: respForOther,
        clientKeyPair: clientKp,
        clientPubBytes: clientPubBytes, // OUR pubC, not the signed one
        pinnedServerEd25519Pub: serverEd25519Pub,
      ),
      throwsA(isA<HandshakeError>()),
    );
  });

  test('HandshakeRequest/Response JSON round-trips', () async {
    final req = HandshakeRequest(x25519Pub: base64.encode(clientPubBytes));
    final req2 = HandshakeRequest.fromJson(req.toJson());
    expect(req2.x25519Pub, req.x25519Pub);

    final resp = (await serverSide()).response;
    final resp2 = HandshakeResponse.fromJson(resp.toJson());
    expect(resp2.x25519Pub, resp.x25519Pub);
    expect(resp2.keyId, resp.keyId);
    expect(resp2.expiresAtMillis, resp.expiresAtMillis);
    expect(resp2.signature, resp.signature);
  });

  test('deriveSessionKey is deterministic for the same shared secret+keyId',
      () async {
    // Two independent derivations from the same shared secret and keyId must
    // produce identical key bytes (HKDF determinism + salt-from-keyId).
    final shared = SecretKey(List<int>.filled(32, 7));
    final k1 = await deriveSessionKey(sharedSecret: shared, keyId: keyId);
    final k2 = await deriveSessionKey(sharedSecret: shared, keyId: keyId);
    expect(await k1.extractBytes(), equals(await k2.extractBytes()));
    expect((await k1.extractBytes()).length, 32);

    // A different keyId (salt) yields a different key.
    final k3 =
        await deriveSessionKey(sharedSecret: shared, keyId: 'different');
    expect(await k3.extractBytes(), isNot(equals(await k1.extractBytes())));
  });
}
