import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/client.dart';

void main() {
  test('fetchPage verifies, decrypts, and returns the tree', () async {
    final signingKp = await Ed25519().newKeyPair();
    final signingPub = await signingKp.extractPublicKey();
    final secret = SecretKey(List.filled(32, 9));

    Future<List<int>> envelope(int count) => encodeEnvelope(
          content: EnvelopeContent(
              root: NdNode(type: 'Text', props: {'text': 'Count: $count'})),
          route: '/',
          contentVersion: 1,
          minClientVersion: '1.0.0',
          keyId: 'k1',
          secretKey: secret,
          signingKeyPair: signingKp,
        );

    final mock = MockClient((req) async {
      if (req.url.path == '/__page') {
        return http.Response.bytes(await envelope(0), 200);
      }
      if (req.url.path == '/__action') {
        return http.Response.bytes(await envelope(1), 200);
      }
      return http.Response('not found', 404);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );

    final page = await client.fetchPage('/');
    expect(page.root.props['text'], 'Count: 0');

    final after = await client.dispatch('inc', const {}, route: '/');
    expect(after.root.props['text'], 'Count: 1');
  });
}
