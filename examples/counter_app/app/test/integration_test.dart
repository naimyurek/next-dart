// Integration test: in-process server + client loop (fetch / inc / buy).
// Run with: flutter test test/integration_test.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:counter_server/app.dart';
import 'package:app/keys.dart';

void main() {
  test('fetch page, increment, and buy through the real handler', () async {
    // State accumulates across the steps below (same in-process session) — intentional.
    final app = await buildApp();
    final handler = app.handler;

    // Bridge http.MockClient -> shelf handler, fully in-process — no socket needed.
    final mock = MockClient((req) async {
      final shelfReq = shelf.Request(req.method, req.url, body: req.bodyBytes);
      final res = await handler(shelfReq);
      final bytes = await res.read().expand((x) => x).toList();
      return http.Response.bytes(bytes, res.statusCode);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://demo'),
      signingPublicKey: SimplePublicKey(
          base64.decode(signingPublicKeyB64), type: KeyPairType.ed25519),
      secretKey: SecretKey(base64.decode(secretKeyB64)),
      httpClient: mock,
    );

    // 1. Initial page: Count: 0
    final page = await client.fetchPage('/');
    expect(page.root.children[0].props['text'], 'Count: 0');

    // 2. Dispatch 'inc': Count: 1
    final afterInc = await client.dispatch('inc', const {}, route: '/');
    expect(afterInc.root.children[0].props['text'], 'Count: 1');

    // 3. Dispatch 'buy' with id:7 → last bought text updates
    final afterBuy = await client.dispatch('buy', const {'id': 7}, route: '/');
    expect(afterBuy.root.children[3].props['text'], 'Last bought id: 7');
  });
}
