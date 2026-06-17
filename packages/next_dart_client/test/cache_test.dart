// packages/next_dart_client/test/cache_test.dart
//
// TDD tests for F9 client-side caching: kv param, not-modified handling.
// Run with: flutter test test/cache_test.dart

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/client.dart';

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  late SecretKey secret;

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
    secret = SecretKey(List.filled(32, 11));
  });

  Future<List<int>> makeEnvelope({
    required NdNode root,
    required int contentVersion,
    Map<String, Object?> data = const {},
  }) =>
      encodeEnvelope(
        content: EnvelopeContent(root: root, data: data),
        route: '/p',
        contentVersion: contentVersion,
        minClientVersion: '1.0.0',
        keyId: 'k1',
        secretKey: secret,
        signingKeyPair: signingKp,
      );

  // ── Basic caching behaviour ───────────────────────────────────────────────

  test('first fetchPage stores version; second call sends kv param', () async {
    final requests = <http.Request>[];

    final mock = MockClient((req) async {
      requests.add(req);
      final body = await makeEnvelope(
        root: NdNode(type: 'Text', props: {'text': 'hi'}),
        contentVersion: 42,
        data: {'contentVersion': 42},
      );
      return http.Response.bytes(body, 200);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );

    await client.fetchPage('/p');
    expect(requests.last.url.queryParameters.containsKey('kv'), isFalse,
        reason: 'first request must not send kv — no cached version yet');

    await client.fetchPage('/p');
    expect(requests.last.url.queryParameters['kv'], '42',
        reason: 'second request must send the cached contentVersion as kv');

    client.close();
  });

  // ── not-modified response ─────────────────────────────────────────────────

  test('when server returns notModified=true, fetchPage returns the cached content', () async {
    late List<int> originalBytes;
    int requestCount = 0;

    final mock = MockClient((req) async {
      requestCount++;
      final kv = req.url.queryParameters['kv'];
      if (kv == '7') {
        // Return a not-modified envelope
        final nmBody = await makeEnvelope(
          root: NdNode(type: 'Column', props: {}, children: []),
          contentVersion: 7,
          data: {'notModified': true, 'contentVersion': 7},
        );
        return http.Response.bytes(nmBody, 200);
      }
      // First request — return the real page
      originalBytes = await makeEnvelope(
        root: NdNode(type: 'Text', props: {'text': 'original'}),
        contentVersion: 7,
        data: {'contentVersion': 7},
      );
      return http.Response.bytes(originalBytes, 200);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );

    final first = await client.fetchPage('/p');
    expect(first.root.props['text'], 'original');

    // Second fetch: server says not-modified
    final second = await client.fetchPage('/p');
    expect(second.root.props['text'], 'original',
        reason: 'not-modified response must return the previously-cached tree');
    expect(requestCount, 2);

    client.close();
  });

  // ── new-version response ──────────────────────────────────────────────────

  test('when server returns a new version, cache is updated', () async {
    int serverVersion = 1;

    final mock = MockClient((req) async {
      final kv = req.url.queryParameters['kv'];
      if (kv != null && int.parse(kv) == serverVersion) {
        // Not modified
        final nmBody = await makeEnvelope(
          root: NdNode(type: 'Column', props: {}),
          contentVersion: serverVersion,
          data: {'notModified': true, 'contentVersion': serverVersion},
        );
        return http.Response.bytes(nmBody, 200);
      }
      // Return current version
      final body = await makeEnvelope(
        root: NdNode(type: 'Text', props: {'text': 'v$serverVersion'}),
        contentVersion: serverVersion,
        data: {'contentVersion': serverVersion},
      );
      return http.Response.bytes(body, 200);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );

    // Fetch version 1
    final c1 = await client.fetchPage('/p');
    expect(c1.root.props['text'], 'v1');

    // Server bumps to version 2
    serverVersion = 2;

    // Client sends kv=1, server replies with full v2 response
    final c2 = await client.fetchPage('/p');
    expect(c2.root.props['text'], 'v2',
        reason: 'when server returns a new full tree, client must display it');

    // Now client should send kv=2
    serverVersion = 2; // still 2, so next request will get not-modified
    final c3 = await client.fetchPage('/p');
    expect(c3.root.props['text'], 'v2',
        reason: 'after cache update to v2, not-modified returns cached v2 tree');

    client.close();
  });

  // ── per-route isolation ───────────────────────────────────────────────────

  test('cache is per-route: /a and /b have independent version tracking', () async {
    final kvSent = <String, String?>{};

    final mock = MockClient((req) async {
      final route = req.url.queryParameters['route']!;
      kvSent[route] = req.url.queryParameters['kv'];
      final body = await makeEnvelope(
        root: NdNode(type: 'Text', props: {'text': route}),
        contentVersion: route == '/a' ? 10 : 20,
        data: {'contentVersion': route == '/a' ? 10 : 20},
      );
      return http.Response.bytes(body, 200);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );

    await client.fetchPage('/a');
    await client.fetchPage('/b');
    await client.fetchPage('/a'); // second fetch for /a must send kv=10
    await client.fetchPage('/b'); // second fetch for /b must send kv=20

    expect(kvSent['/a'], '10');
    expect(kvSent['/b'], '20');

    client.close();
  });
}
