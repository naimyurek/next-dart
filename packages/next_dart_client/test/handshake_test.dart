// packages/next_dart_client/test/handshake_test.dart
//
// TDD for F8 client side. A MockClient emulates the server's /__handshake,
// /__page and /__action endpoints (using the real protocol helpers to derive
// and sign), so we verify:
//   * the client handshakes, attaches its kid, fetches, and decrypts with the
//     derived session key;
//   * a 409 {"error":"rehandshake"} on the first fetch triggers a transparent
//     re-handshake + retry that succeeds;
//   * dispatch() carries the kid in the body and decrypts the response.
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/client.dart';

void main() {
  late SimpleKeyPair serverEd25519; // long-term identity (also signs envelopes)
  late SimplePublicKey serverEd25519Pub;
  // The provisioned key is only used by the back-compat fallback path; the
  // session path derives its own key, so this is deliberately a DIFFERENT key
  // to prove the client really switches to the derived session key.
  final provisioned = SecretKey(List.filled(32, 1));

  setUp(() async {
    serverEd25519 = await Ed25519().newKeyPair();
    serverEd25519Pub = await serverEd25519.extractPublicKey();
  });

  // A tiny in-memory "server": stores the session key derived during the
  // handshake and encrypts page/action envelopes under it.
  ({MockClient mock, void Function() reset, int Function() handshakeCount})
      buildServer({
    required int count,
    bool first409 = false,
  }) {
    SecretKey? sessionKey;
    String? sessionKeyId;
    var handshakes = 0;
    var sawFirstPage = false;

    Future<http.Response> page(SecretKey key, String kid, int c) async {
      final env = await encodeEnvelope(
        content: EnvelopeContent(
            root: NdNode(type: 'Text', props: {'text': 'Count: $c'})),
        route: '/',
        contentVersion: 1,
        minClientVersion: '1.0.0',
        keyId: kid,
        secretKey: key,
        signingKeyPair: serverEd25519,
      );
      return http.Response.bytes(env, 200);
    }

    final mock = MockClient((req) async {
      if (req.url.path == '/__handshake') {
        handshakes++;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final hsReq = HandshakeRequest.fromJson(body);
        final clientPub = base64.decode(hsReq.x25519Pub);
        final result = await buildHandshakeResponse(
          clientPubBytes: clientPub,
          serverEd25519: serverEd25519,
          keyId: 'sess-1',
          expiresAtMillis: 4102444800000, // far future
        );
        sessionKey = result.sessionKey;
        sessionKeyId = result.response.keyId;
        return http.Response(jsonEncode(result.response.toJson()), 200,
            headers: {'content-type': 'application/json'});
      }

      if (req.url.path == '/__page') {
        final kid = req.url.queryParameters['kid'];
        // Simulate a dead session on the very first page fetch.
        if (first409 && !sawFirstPage) {
          sawFirstPage = true;
          return http.Response(jsonEncode({'error': 'rehandshake'}), 409,
              headers: {'content-type': 'application/json'});
        }
        if (kid == null) {
          // Provisioned fallback path.
          return page(provisioned, 'provisioned', count);
        }
        if (kid != sessionKeyId || sessionKey == null) {
          return http.Response(jsonEncode({'error': 'rehandshake'}), 409,
              headers: {'content-type': 'application/json'});
        }
        return page(sessionKey!, kid, count);
      }

      if (req.url.path == '/__action') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final kid = body['kid'] as String?;
        if (kid == null) {
          return page(provisioned, 'provisioned', count + 1);
        }
        if (kid != sessionKeyId || sessionKey == null) {
          return http.Response(jsonEncode({'error': 'rehandshake'}), 409,
              headers: {'content-type': 'application/json'});
        }
        return page(sessionKey!, kid, count + 1);
      }

      return http.Response('not found', 404);
    });

    return (
      mock: mock,
      reset: () {
        sessionKey = null;
        sessionKeyId = null;
        sawFirstPage = false;
      },
      handshakeCount: () => handshakes,
    );
  }

  NextDartClient buildClient(MockClient mock) => NextDartClient(
        baseUrl: Uri.parse('http://test'),
        signingPublicKey: serverEd25519Pub,
        secretKey: provisioned,
        httpClient: mock,
      );

  test('handshake() then fetchPage attaches kid and decrypts session envelope',
      () async {
    final server = buildServer(count: 0);
    final client = buildClient(server.mock);

    await client.handshake();
    final page = await client.fetchPage('/');
    expect(page.root.props['text'], 'Count: 0');
    expect(server.handshakeCount(), 1);
  });

  test('dispatch carries kid and decrypts the action response', () async {
    final server = buildServer(count: 5);
    final client = buildClient(server.mock);

    await client.handshake();
    final after = await client.dispatch('inc', const {}, route: '/');
    expect(after.root.props['text'], 'Count: 6');
  });

  test('a 409 on the first fetch triggers transparent re-handshake + retry',
      () async {
    // No explicit handshake() up front: the client starts with no session, the
    // server answers the first /__page with 409, and the client must
    // transparently handshake once and retry, succeeding.
    final server = buildServer(count: 7, first409: true);
    final client = buildClient(server.mock);

    final page = await client.fetchPage('/');
    expect(page.root.props['text'], 'Count: 7');
    // Exactly one handshake was performed as part of the retry.
    expect(server.handshakeCount(), 1);
  });

  test('409 during dispatch triggers transparent re-handshake + retry',
      () async {
    final server = buildServer(count: 2);
    final client = buildClient(server.mock);

    // Establish a session, then nuke the server's session so the next request
    // with the (now stale) kid gets a 409 and must renegotiate.
    await client.handshake();
    server.reset();

    final after = await client.dispatch('inc', const {}, route: '/');
    expect(after.root.props['text'], 'Count: 3');
    expect(server.handshakeCount(), 2); // initial + the transparent retry
  });

  test('without handshake, fetchPage falls back to the provisioned key',
      () async {
    // The server here NEVER 409s a no-kid request; it serves the provisioned
    // path. This proves back-compat: a client that never calls handshake()
    // still works exactly as in Phase 1/2.
    final server = buildServer(count: 42);
    final client = buildClient(server.mock);

    final page = await client.fetchPage('/');
    expect(page.root.props['text'], 'Count: 42');
    expect(server.handshakeCount(), 0); // no handshake happened
  });

  // ── Fix 2: client checks envelope keyId matches the kid it sent ───────────
  group('Fix 2 — keyId mismatch check', () {
    // A fake server that returns an envelope whose header keyId deliberately
    // differs from the kid the client sent.
    MockClient buildMismatchServer(SimpleKeyPair serverEd) {
      SecretKey? sessionKey;
      String? sessionKeyId;

      return MockClient((req) async {
        if (req.url.path == '/__handshake') {
          final body = jsonDecode(req.body) as Map<String, Object?>;
          final hsReq = HandshakeRequest.fromJson(body);
          final clientPub = base64.decode(hsReq.x25519Pub);
          final result = await buildHandshakeResponse(
            clientPubBytes: clientPub,
            serverEd25519: serverEd,
            keyId: 'real-kid',
            expiresAtMillis: 4102444800000,
          );
          sessionKey = result.sessionKey;
          sessionKeyId = result.response.keyId;
          return http.Response(jsonEncode(result.response.toJson()), 200,
              headers: {'content-type': 'application/json'});
        }

        if (req.url.path == '/__page') {
          // Encrypt the envelope under the session key but stamp a DIFFERENT
          // keyId in the header — the client should reject this.
          final env = await encodeEnvelope(
            content: EnvelopeContent(
                root: NdNode(type: 'Text', props: {'text': 'ok'})),
            route: '/',
            contentVersion: 1,
            minClientVersion: '1.0.0',
            keyId: 'WRONG-kid', // ← deliberate mismatch
            secretKey: sessionKey!,
            signingKeyPair: serverEd,
          );
          return http.Response.bytes(env, 200);
        }

        return http.Response('not found', 404);
      });
    }

    test('envelope keyId mismatch throws DecodeError with clear message',
        () async {
      final mock = buildMismatchServer(serverEd25519);
      final client = NextDartClient(
        baseUrl: Uri.parse('http://test'),
        signingPublicKey: serverEd25519Pub,
        secretKey: provisioned,
        httpClient: mock,
      );

      await client.handshake(); // establishes session with kid='real-kid'
      expect(
        () => client.fetchPage('/'),
        throwsA(isA<DecodeError>().having(
          (e) => e.message,
          'message',
          contains('session key id mismatch'),
        )),
      );
    });
  });

  // ── Fix 3: streamPage threads kid ─────────────────────────────────────────
  group('Fix 3 — streamPage threads kid', () {
    // A minimal mock server that serves /__handshake and /__stream, encrypting
    // each frame under the session key.
    MockClient buildStreamServer(SimpleKeyPair serverEd, {int count = 0}) {
      SecretKey? sessionKey;
      String? sessionKeyId;

      return MockClient((req) async {
        if (req.url.path == '/__handshake') {
          final body = jsonDecode(req.body) as Map<String, Object?>;
          final hsReq = HandshakeRequest.fromJson(body);
          final clientPub = base64.decode(hsReq.x25519Pub);
          final result = await buildHandshakeResponse(
            clientPubBytes: clientPub,
            serverEd25519: serverEd,
            keyId: 'stream-kid',
            expiresAtMillis: 4102444800000,
          );
          sessionKey = result.sessionKey;
          sessionKeyId = result.response.keyId;
          return http.Response(jsonEncode(result.response.toJson()), 200,
              headers: {'content-type': 'application/json'});
        }

        if (req.url.path == '/__stream') {
          final kid = req.url.queryParameters['kid'];
          if (kid == null || kid != sessionKeyId || sessionKey == null) {
            return http.Response(
                jsonEncode({'error': 'rehandshake'}), 409,
                headers: {'content-type': 'application/json'});
          }
          // Produce two frames, both encrypted under the session key.
          final buf = StringBuffer();
          for (var i = 0; i < 2; i++) {
            final env = await encodeEnvelope(
              content: EnvelopeContent(
                  root: NdNode(
                      type: 'Text', props: {'text': 'frame$i:$count'})),
              route: '/',
              contentVersion: i,
              minClientVersion: '1.0.0',
              keyId: kid,
              secretKey: sessionKey!,
              signingKeyPair: serverEd,
            );
            buf.writeln(base64.encode(env));
          }
          return http.Response(buf.toString(), 200,
              headers: {'content-type': 'text/plain'});
        }

        return http.Response('not found', 404);
      });
    }

    test('after handshake, streamPage attaches kid and decrypts session frames',
        () async {
      final mock = buildStreamServer(serverEd25519, count: 5);
      final client = NextDartClient(
        baseUrl: Uri.parse('http://test'),
        signingPublicKey: serverEd25519Pub,
        secretKey: provisioned,
        httpClient: mock,
      );

      await client.handshake();
      final frames = await client.streamPage('/').toList();
      expect(frames.length, 2);
      expect(frames[0].root.props['text'], 'frame0:5');
      expect(frames[1].root.props['text'], 'frame1:5');
    });
  });

  // ── Fix 4: handshake-only client (no provisioned key) ─────────────────────
  group('Fix 4 — handshake-only client (null secretKey)', () {
    test('client with no secretKey auto-handshakes and fetches page', () async {
      final server = buildServer(count: 99);

      // Construct a client with NO provisioned key.
      final client = NextDartClient(
        baseUrl: Uri.parse('http://test'),
        signingPublicKey: serverEd25519Pub,
        // secretKey intentionally omitted → null
        httpClient: server.mock,
      );

      // The client has no secretKey and no session → it must handshake first
      // transparently, then fetch.
      final page = await client.fetchPage('/');
      expect(page.root.props['text'], 'Count: 99');
      expect(server.handshakeCount(), 1); // auto-handshake happened
    });

    test('client with no secretKey auto-handshakes on dispatch', () async {
      final server = buildServer(count: 3);
      final client = NextDartClient(
        baseUrl: Uri.parse('http://test'),
        signingPublicKey: serverEd25519Pub,
        httpClient: server.mock,
      );

      final after = await client.dispatch('inc', const {}, route: '/');
      expect(after.root.props['text'], 'Count: 4');
      expect(server.handshakeCount(), 1);
    });
  });
}
