// packages/next_dart_server/test/cache_test.dart
//
// TDD tests for F9: ISR / advanced caching + not-modified frames.
// Run with: dart test test/cache_test.dart

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  final secret = SecretKey(List.filled(32, 7));

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
  });

  Future<EnvelopeContent> decodeBody(Response r) async {
    final bytes = await r.read().expand((x) => x).toList();
    return decodeEnvelope(
      bytes,
      secretKey: secret,
      signingPublicKey: signingPub,
      clientVersion: '1.0.0',
    );
  }

  Future<Response> getPage(Handler h, String route, {String? kv}) async {
    final params = <String, String>{'route': route};
    if (kv != null) params['kv'] = kv;
    return await h(Request('GET', Uri.parse('http://x/__page').replace(queryParameters: params)));
  }

  // ── RevalidatePolicy.afterSeconds ─────────────────────────────────────────

  group('RevalidatePolicy.afterSeconds', () {
    test('two requests within TTL invoke builder once and return same contentVersion', () async {
      var buildCount = 0;
      var fakeNow = 1000000; // arbitrary epoch ms

      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
        nowMillis: () => fakeNow,
      );
      app.page(
        '/cached',
        (ctx) {
          buildCount++;
          return ndColumn([ndText('v$buildCount')]);
        },
        revalidate: RevalidatePolicy.afterSeconds(60),
      );

      final h = app.handler;

      final r1 = await getPage(h, '/cached');
      expect(r1.statusCode, 200);
      final c1 = await decodeBody(r1);
      final v1 = c1.data['contentVersion'] as int;

      // Advance time by 30 s (still within TTL of 60 s)
      fakeNow += 30000;

      final r2 = await getPage(h, '/cached');
      expect(r2.statusCode, 200);
      final c2 = await decodeBody(r2);
      final v2 = c2.data['contentVersion'] as int;

      expect(buildCount, 1, reason: 'builder must be called only once within TTL');
      expect(v1, v2, reason: 'cached response must carry the same contentVersion');
    });

    test('advancing past TTL triggers a rebuild with a new contentVersion', () async {
      var buildCount = 0;
      var fakeNow = 1000000;

      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
        nowMillis: () => fakeNow,
      );
      app.page(
        '/cached',
        (ctx) {
          buildCount++;
          return ndColumn([ndText('v$buildCount')]);
        },
        revalidate: RevalidatePolicy.afterSeconds(60),
      );

      final h = app.handler;

      final r1 = await getPage(h, '/cached');
      final c1 = await decodeBody(r1);
      final v1 = c1.data['contentVersion'] as int;

      // Advance past TTL
      fakeNow += 61000;

      final r2 = await getPage(h, '/cached');
      final c2 = await decodeBody(r2);
      final v2 = c2.data['contentVersion'] as int;

      expect(buildCount, 2, reason: 'builder must be called again after TTL expires');
      expect(v2, greaterThan(v1), reason: 'new contentVersion must be strictly higher');
    });

    test('cache is keyed per (route, params): /item/1 and /item/2 are separate entries', () async {
      var buildCount = 0;

      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      app.page(
        '/item/:id',
        (ctx) {
          buildCount++;
          return ndColumn([ndText('item-${ctx.params['id']}')]);
        },
        revalidate: RevalidatePolicy.afterSeconds(60),
      );

      final h = app.handler;

      await getPage(h, '/item/1');
      await getPage(h, '/item/2');
      // A third request to /item/1 should reuse the cache (still build count 2)
      await getPage(h, '/item/1');

      expect(buildCount, 2, reason: '/item/1 and /item/2 must have separate cache entries');
    });
  });

  // ── RevalidatePolicy.never ─────────────────────────────────────────────────

  group('RevalidatePolicy.never', () {
    test('never expires — builder called exactly once regardless of time', () async {
      var buildCount = 0;
      var fakeNow = 1000000;

      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
        nowMillis: () => fakeNow,
      );
      app.page(
        '/static',
        (ctx) {
          buildCount++;
          return ndColumn([ndText('static')]);
        },
        revalidate: RevalidatePolicy.never(),
      );

      final h = app.handler;

      await getPage(h, '/static');
      fakeNow += 999999999; // far future
      await getPage(h, '/static');

      expect(buildCount, 1, reason: 'RevalidatePolicy.never must never rebuild');
    });
  });

  // ── RevalidatePolicy.onDemand ──────────────────────────────────────────────

  group('RevalidatePolicy.onDemand', () {
    test('fresh until app.revalidate(route) is called; then rebuilds once', () async {
      var buildCount = 0;

      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      app.page(
        '/demand',
        (ctx) {
          buildCount++;
          return ndColumn([ndText('gen$buildCount')]);
        },
        revalidate: RevalidatePolicy.onDemand(),
      );

      final h = app.handler;

      await getPage(h, '/demand');
      await getPage(h, '/demand'); // still cached
      expect(buildCount, 1);

      app.revalidate('/demand');

      await getPage(h, '/demand'); // must rebuild
      expect(buildCount, 2);

      await getPage(h, '/demand'); // cached again
      expect(buildCount, 2);
    });
  });

  // ── No revalidate policy (default) ─────────────────────────────────────────

  group('no revalidate policy (default)', () {
    test('every request invokes the builder (existing behaviour preserved)', () async {
      var buildCount = 0;

      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      app.page(
        '/',
        (ctx) {
          buildCount++;
          return ndColumn([ndText('n$buildCount')]);
        },
        // no revalidate — default is no caching
      );

      final h = app.handler;

      await getPage(h, '/');
      await getPage(h, '/');
      await getPage(h, '/');

      expect(buildCount, 3, reason: 'without a revalidate policy every request must rebuild');
    });
  });

  // ── Not-modified frame ─────────────────────────────────────────────────────

  group('not-modified frame', () {
    test('kv matching current contentVersion returns notModified=true frame', () async {
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      app.page(
        '/nm',
        (ctx) => ndColumn([ndText('hello')]),
        revalidate: RevalidatePolicy.never(),
      );

      final h = app.handler;

      // First request — get the real envelope and read contentVersion from data
      final r1 = await getPage(h, '/nm');
      final c1 = await decodeBody(r1);
      final cv = c1.data['contentVersion'] as int;

      // Second request with kv=<currentVersion>
      final r2 = await getPage(h, '/nm', kv: cv.toString());
      expect(r2.statusCode, 200);
      final c2 = await decodeBody(r2);
      expect(c2.data['notModified'], true);
      expect(c2.data['contentVersion'], cv);
    });

    test('kv not matching (stale) returns full tree with data[contentVersion]', () async {
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      app.page(
        '/nm2',
        (ctx) => ndColumn([ndText('world')]),
        revalidate: RevalidatePolicy.never(),
      );

      final h = app.handler;

      // First request — populate cache
      await getPage(h, '/nm2');

      // Second request with a wrong kv
      final r2 = await getPage(h, '/nm2', kv: '0');
      expect(r2.statusCode, 200);
      final c2 = await decodeBody(r2);
      expect(c2.data['notModified'], isNot(true));
      expect(c2.data['contentVersion'], isA<int>());
      expect(c2.root.children[0].props['text'], 'world');
    });

    test('not-modified frame is authenticated (signed+encrypted under session key)', () async {
      // The not-modified response must go through encodeEnvelope — verifiable by decodeEnvelope.
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      app.page(
        '/nm3',
        (ctx) => ndColumn([ndText('auth')]),
        revalidate: RevalidatePolicy.never(),
      );

      final h = app.handler;

      final r1 = await getPage(h, '/nm3');
      final c1 = await decodeBody(r1);
      final cv = c1.data['contentVersion'] as int;

      final r2 = await getPage(h, '/nm3', kv: cv.toString());
      // decodeBody performs full sig verify + AES-GCM decrypt — if this throws, the test fails.
      final c2 = await decodeBody(r2);
      expect(c2.data['notModified'], true);
    });

    test('kv without caching policy: still returns full tree (no notModified)', () async {
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      // no revalidate — uncached page
      app.page('/uncached', (ctx) => ndColumn([ndText('dyn')]));

      final h = app.handler;

      // Even if the client sends kv, an uncached page always rebuilds and returns full tree
      final r = await getPage(h, '/uncached', kv: '99');
      expect(r.statusCode, 200);
      final c = await decodeBody(r);
      expect(c.data['notModified'], isNot(true));
    });
  });
}
