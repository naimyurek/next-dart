import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/src/app.dart';
import 'package:next_dart_server/src/context.dart';
import 'package:next_dart_server/src/dsl.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  final secret = SecretKey(List.filled(32, 5));

  NextDartApp buildApp() {
    final app = NextDartApp(
      signingKeyPair: signingKp,
      secretKey: secret,
      keyId: 'k1',
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
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
  });

  Future<EnvelopeContent> decodeBody(Response r) async {
    final bytes = await r.read().expand((x) => x).toList();
    return decodeEnvelope(bytes,
        secretKey: secret, signingPublicKey: signingPub, clientVersion: '1.0.0');
  }

  test('GET /__page returns a signed envelope with the page tree', () async {
    final handler = buildApp().handler;
    final res = await handler(Request('GET', Uri.parse('http://x/__page?route=/')));
    expect(res.statusCode, 200);
    final content = await decodeBody(res);
    expect(content.root.children[0].props['text'], 'Count: 0');
  });

  test('POST /__action runs the handler and returns the updated tree', () async {
    final app = buildApp();
    final handler = app.handler;
    final res = await handler(Request(
      'POST',
      Uri.parse('http://x/__action'),
      body: jsonEncode({'action': 'inc', 'args': {}, 'route': '/'}),
    ));
    expect(res.statusCode, 200);
    final content = await decodeBody(res);
    expect(content.root.children[0].props['text'], 'Count: 1');
  });

  test('unknown route returns 404', () async {
    final handler = buildApp().handler;
    final res =
        await handler(Request('GET', Uri.parse('http://x/__page?route=/nope')));
    expect(res.statusCode, 404);
  });
}
