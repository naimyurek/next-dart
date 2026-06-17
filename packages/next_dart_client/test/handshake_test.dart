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
}
