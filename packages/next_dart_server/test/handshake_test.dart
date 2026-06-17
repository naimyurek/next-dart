// packages/next_dart_server/test/handshake_test.dart
//
// TDD for F8 server side: SessionStore key rotation/expiry/pruning, the
// POST /__handshake endpoint, kid-threaded envelope encryption on /__page and
// /__action, the 409 re-handshake signal for missing/expired sessions, and the
// preserved provisioned-key path (no kid).
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  // ── SessionStore unit tests ───────────────────────────────────────────────
  group('SessionStore', () {
    test('newSession returns distinct ids and keyFor resolves live keys', () {
      final store = SessionStore();
      final k1 = SecretKey(List.filled(32, 1));
      final k2 = SecretKey(List.filled(32, 2));
      final id1 = store.newSession(k1, 1000);
      final id2 = store.newSession(k2, 1000);
      expect(id1, isNot(equals(id2)));
      expect(store.keyFor(id1, 500), same(k1));
      expect(store.keyFor(id2, 500), same(k2));
    });

    test('keyFor returns null for unknown id', () {
      final store = SessionStore();
      expect(store.keyFor('nope', 0), isNull);
    });

    test('keyFor returns null at/after expiry (exclusive upper bound)', () {
      final store = SessionStore();
      final key = SecretKey(List.filled(32, 3));
      final id = store.newSession(key, 1000); // expires at 1000ms
      expect(store.keyFor(id, 999), same(key));
      expect(store.keyFor(id, 1000), isNull); // expired exactly at boundary
      expect(store.keyFor(id, 2000), isNull);
    });

    test('prune drops expired entries', () {
      final store = SessionStore();
      final live = SecretKey(List.filled(32, 4));
      final dead = SecretKey(List.filled(32, 5));
      final liveId = store.newSession(live, 5000);
      final deadId = store.newSession(dead, 1000);
      store.prune(2000); // now=2000: deadId expired, liveId still good
      expect(store.keyFor(deadId, 2000), isNull);
      expect(store.keyFor(liveId, 2000), same(live));
    });
  });

  // ── App-level handshake + endpoint tests ─────────────────────────────────
  group('app handshake endpoints', () {
    late SimpleKeyPair signingKp;
    late SimplePublicKey signingPub;
    final provisioned = SecretKey(List.filled(32, 9));

    // A mutable clock the app reads so the expiry test is deterministic.
    int now = 1000000;

    NextDartApp buildApp({Duration sessionTtl = const Duration(minutes: 30)}) {
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: provisioned,
        keyId: 'provisioned',
        sessionTtl: sessionTtl,
        nowMillis: () => now,
      );
      app.page('/', (ctx) {
        final c = ctx.state.get<int>('count', 0);
        return ndColumn([ndText('Count: $c')]);
      });
      app.action('inc', (ctx) {
        ctx.state.update<int>('count', 0, (n) => n + 1);
      });
      return app;
    }

    setUp(() async {
      now = 1000000;
      signingKp = await Ed25519().newKeyPair();
      signingPub = await signingKp.extractPublicKey();
    });

    // Perform a full client-side handshake against the handler, returning the
    // derived session key and its keyId.
    Future<({SecretKey key, String keyId})> doHandshake(Handler handler) async {
      final x = X25519();
      final clientKp = await x.newKeyPair();
      final clientPub = await clientKp.extractPublicKey();

      final req = Request(
        'POST',
        Uri.parse('http://x/__handshake'),
        body: jsonEncode(
            HandshakeRequest(x25519Pub: base64.encode(clientPub.bytes))
                .toJson()),
      );
      final res = await handler(req);
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      final resp = HandshakeResponse.fromJson(body);

      final key = await verifyAndDeriveClientSession(
        response: resp,
        clientKeyPair: clientKp,
        clientPubBytes: clientPub.bytes,
        pinnedServerEd25519Pub: signingPub,
      );
      return (key: key, keyId: resp.keyId);
    }

    test('POST /__handshake returns a response signed by the pinned key',
        () async {
      final handler = buildApp().handler;
      final session = await doHandshake(handler);
      // verifyAndDeriveClientSession inside doHandshake already asserts the
      // signature; reaching here means it verified.
      expect(session.keyId, isNotEmpty);
      final bytes = await session.key.extractBytes();
      expect(bytes.length, 32);
    });

    test('after handshake, GET /__page?kid=<id> decrypts with session key',
        () async {
      final handler = buildApp().handler;
      final session = await doHandshake(handler);

      final res = await handler(Request(
          'GET',
          Uri.parse(
              'http://x/__page?route=/&kid=${Uri.encodeComponent(session.keyId)}')));
      expect(res.statusCode, 200);
      final bytes = await res.read().expand((x) => x).toList();
      // Decrypts ONLY with the derived session key.
      final content = await decodeEnvelope(bytes,
          secretKey: session.key,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.children[0].props['text'], 'Count: 0');
    });

    test('after handshake, POST /__action with kid decrypts with session key',
        () async {
      final handler = buildApp().handler;
      final session = await doHandshake(handler);

      final res = await handler(Request(
        'POST',
        Uri.parse('http://x/__action'),
        body: jsonEncode({
          'action': 'inc',
          'args': {},
          'route': '/',
          'kid': session.keyId,
        }),
      ));
      expect(res.statusCode, 200);
      final bytes = await res.read().expand((x) => x).toList();
      final content = await decodeEnvelope(bytes,
          secretKey: session.key,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.children[0].props['text'], 'Count: 1');
    });

    test('GET /__page with an UNKNOWN kid returns 409 rehandshake', () async {
      final handler = buildApp().handler;
      final res = await handler(Request(
          'GET', Uri.parse('http://x/__page?route=/&kid=does-not-exist')));
      expect(res.statusCode, 409);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      expect(body['error'], 'rehandshake');
    });

    test('GET /__page with an EXPIRED kid returns 409 rehandshake', () async {
      final app = buildApp(sessionTtl: const Duration(minutes: 30));
      final handler = app.handler;
      final session = await doHandshake(handler);

      // Advance the clock beyond the TTL so the session has expired.
      now += const Duration(minutes: 31).inMilliseconds;

      final res = await handler(Request(
          'GET',
          Uri.parse(
              'http://x/__page?route=/&kid=${Uri.encodeComponent(session.keyId)}')));
      expect(res.statusCode, 409);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      expect(body['error'], 'rehandshake');
    });

    test('POST /__action with an unknown kid returns 409 rehandshake',
        () async {
      final handler = buildApp().handler;
      final res = await handler(Request(
        'POST',
        Uri.parse('http://x/__action'),
        body: jsonEncode({
          'action': 'inc',
          'args': {},
          'route': '/',
          'kid': 'ghost',
        }),
      ));
      expect(res.statusCode, 409);
    });

    test('provisioned path: GET /__page with NO kid uses the provisioned key',
        () async {
      final handler = buildApp().handler;
      final res = await handler(
          Request('GET', Uri.parse('http://x/__page?route=/')));
      expect(res.statusCode, 200);
      final bytes = await res.read().expand((x) => x).toList();
      // Decrypts with the PROVISIONED key (Phase 1/2 behaviour unchanged).
      final content = await decodeEnvelope(bytes,
          secretKey: provisioned,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.children[0].props['text'], 'Count: 0');
    });

    test('provisioned path: POST /__action with NO kid uses provisioned key',
        () async {
      final handler = buildApp().handler;
      final res = await handler(Request(
        'POST',
        Uri.parse('http://x/__action'),
        body: jsonEncode({'action': 'inc', 'args': {}, 'route': '/'}),
      ));
      expect(res.statusCode, 200);
      final bytes = await res.read().expand((x) => x).toList();
      final content = await decodeEnvelope(bytes,
          secretKey: provisioned,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.children[0].props['text'], 'Count: 1');
    });

    test('issued session expiresAtMillis = now + ttl', () async {
      final handler =
          buildApp(sessionTtl: const Duration(minutes: 10)).handler;
      final x = X25519();
      final clientKp = await x.newKeyPair();
      final clientPub = await clientKp.extractPublicKey();
      final res = await handler(Request(
        'POST',
        Uri.parse('http://x/__handshake'),
        body: jsonEncode(
            HandshakeRequest(x25519Pub: base64.encode(clientPub.bytes))
                .toJson()),
      ));
      final resp = HandshakeResponse.fromJson(
          jsonDecode(await res.readAsString()) as Map<String, Object?>);
      expect(resp.expiresAtMillis,
          now + const Duration(minutes: 10).inMilliseconds);
    });

    test('malformed handshake body returns 400', () async {
      final handler = buildApp().handler;
      final res = await handler(Request('POST',
          Uri.parse('http://x/__handshake'),
          body: 'not json'));
      expect(res.statusCode, 400);
    });
  });

  // ── Fix 1: requireHandshake gate ──────────────────────────────────────────
  group('requireHandshake gate', () {
    late SimpleKeyPair signingKp;
    late SimplePublicKey signingPub;
    final provisioned = SecretKey(List.filled(32, 9));
    int now = 1000000;

    NextDartApp buildGatedApp({bool requireHandshake = false}) {
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: provisioned,
        keyId: 'provisioned',
        requireHandshake: requireHandshake,
        nowMillis: () => now,
      );
      app.page('/', (ctx) => ndColumn([ndText('ok')]));
      app.action('noop', (ctx) {});
      return app;
    }

    Future<({SecretKey key, String keyId})> doHandshake(Handler handler) async {
      final x = X25519();
      final clientKp = await x.newKeyPair();
      final clientPub = await clientKp.extractPublicKey();
      final req = Request('POST', Uri.parse('http://x/__handshake'),
          body: jsonEncode(
              HandshakeRequest(x25519Pub: base64.encode(clientPub.bytes))
                  .toJson()));
      final res = await handler(req);
      final body =
          jsonDecode(await res.readAsString()) as Map<String, Object?>;
      final resp = HandshakeResponse.fromJson(body);
      final key = await verifyAndDeriveClientSession(
        response: resp,
        clientKeyPair: clientKp,
        clientPubBytes: clientPub.bytes,
        pinnedServerEd25519Pub: signingPub,
      );
      return (key: key, keyId: resp.keyId);
    }

    setUp(() async {
      now = 1000000;
      signingKp = await Ed25519().newKeyPair();
      signingPub = await signingKp.extractPublicKey();
    });

    // Fix 1 — /__page
    test('requireHandshake=true: /__page with no kid → 409', () async {
      final handler = buildGatedApp(requireHandshake: true).handler;
      final res = await handler(
          Request('GET', Uri.parse('http://x/__page?route=/')));
      expect(res.statusCode, 409);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      expect(body['error'], 'rehandshake');
    });

    test(
        'requireHandshake=true: /__page with valid post-handshake kid → 200 '
        'decryptable under session key', () async {
      final handler = buildGatedApp(requireHandshake: true).handler;
      final session = await doHandshake(handler);
      final res = await handler(Request('GET',
          Uri.parse(
              'http://x/__page?route=/&kid=${Uri.encodeComponent(session.keyId)}')));
      expect(res.statusCode, 200);
      final bytes = await res.read().expand((x) => x).toList();
      final content = await decodeEnvelope(bytes,
          secretKey: session.key,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.type, 'Column');
    });

    test('requireHandshake=false (default): /__page with no kid → 200 '
        'under provisioned key', () async {
      final handler = buildGatedApp(requireHandshake: false).handler;
      final res = await handler(
          Request('GET', Uri.parse('http://x/__page?route=/')));
      expect(res.statusCode, 200);
      final bytes = await res.read().expand((x) => x).toList();
      final content = await decodeEnvelope(bytes,
          secretKey: provisioned,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.type, 'Column');
    });

    // Fix 1 — /__action
    test('requireHandshake=true: /__action with no kid → 409', () async {
      final handler = buildGatedApp(requireHandshake: true).handler;
      final res = await handler(Request('POST', Uri.parse('http://x/__action'),
          body: jsonEncode({'action': 'noop', 'args': {}, 'route': '/'})));
      expect(res.statusCode, 409);
    });

    // Fix 3 — /__stream
    test('requireHandshake=true: /__stream with no kid → 409', () async {
      final handler = buildGatedApp(requireHandshake: true).handler;
      final res = await handler(
          Request('GET', Uri.parse('http://x/__stream?route=/')));
      expect(res.statusCode, 409);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      expect(body['error'], 'rehandshake');
    });

    test(
        'requireHandshake=true: /__stream with valid kid → 200 with frames '
        'decryptable under session key', () async {
      final handler = buildGatedApp(requireHandshake: true).handler;
      final session = await doHandshake(handler);
      final res = await handler(Request('GET',
          Uri.parse(
              'http://x/__stream?route=/&kid=${Uri.encodeComponent(session.keyId)}')));
      expect(res.statusCode, 200);
      final raw = await res.readAsString();
      // At least one non-empty line (the initial frame).
      final lines =
          raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines, isNotEmpty);
      final frameBytes = base64.decode(lines.first);
      final content = await decodeEnvelope(frameBytes,
          secretKey: session.key,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.type, 'Column');
    });

    test('requireHandshake=false: /__stream with no kid → 200 under '
        'provisioned key', () async {
      final handler = buildGatedApp(requireHandshake: false).handler;
      final res = await handler(
          Request('GET', Uri.parse('http://x/__stream?route=/')));
      expect(res.statusCode, 200);
      final raw = await res.readAsString();
      final lines =
          raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines, isNotEmpty);
      final frameBytes = base64.decode(lines.first);
      final content = await decodeEnvelope(frameBytes,
          secretKey: provisioned,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
      expect(content.root.type, 'Column');
    });
  });
}
