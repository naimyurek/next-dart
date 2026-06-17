import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/next_dart_server.dart';
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

  test('unknown action returns 404', () async {
    final handler = buildApp().handler;
    final res = await handler(Request('POST', Uri.parse('http://x/__action'),
        body: jsonEncode({'action': 'nope', 'route': '/'})));
    expect(res.statusCode, 404);
  });

  test('malformed JSON body returns 400', () async {
    final handler = buildApp().handler;
    final res = await handler(Request('POST', Uri.parse('http://x/__action'),
        body: 'not json'));
    expect(res.statusCode, 400);
  });

  test('missing action field returns 400', () async {
    final handler = buildApp().handler;
    final res = await handler(Request('POST', Uri.parse('http://x/__action'),
        body: jsonEncode({'route': '/'})));
    expect(res.statusCode, 400);
  });

  // ── F2: routing with path parameters ────────────────────────────────────

  NextDartApp buildParamApp() {
    final app = NextDartApp(
      signingKeyPair: signingKp,
      secretKey: secret,
      keyId: 'k1',
    );
    // Dynamic route: /item/:id
    app.page('/item/:id', (ctx) {
      return ndColumn([ndText('item-${ctx.params['id']}')]);
    });
    // Static route: /item/new — should beat the dynamic one above
    app.page('/item/new', (ctx) {
      return ndColumn([ndText('create-new-item')]);
    });
    // Action that echoes the param
    app.action('echo-id', (ctx) {
      // side-effect: store the param so we can assert on the returned page tree
      ctx.state.set('last-id', ctx.params['id'] ?? 'none');
    });
    return app;
  }

  test('GET /__page resolves dynamic route and exposes param in page tree',
      () async {
    final handler = buildParamApp().handler;
    final res = await handler(
        Request('GET', Uri.parse('http://x/__page?route=/item/7')));
    expect(res.statusCode, 200);
    final content = await decodeBody(res);
    expect(content.root.children[0].props['text'], 'item-7');
  });

  test('GET /__page resolves static route over dynamic when both match',
      () async {
    final handler = buildParamApp().handler;
    final res = await handler(
        Request('GET', Uri.parse('http://x/__page?route=/item/new')));
    expect(res.statusCode, 200);
    final content = await decodeBody(res);
    expect(content.root.children[0].props['text'], 'create-new-item');
  });

  test('POST /__action exposes path params to action handler', () async {
    final app = buildParamApp();
    final handler = app.handler;
    final res = await handler(Request(
      'POST',
      Uri.parse('http://x/__action'),
      body: jsonEncode({'action': 'echo-id', 'args': {}, 'route': '/item/42'}),
    ));
    expect(res.statusCode, 200);
    // The action stored the param; the re-rendered page confirms it
    expect(app.state.get<Object?>('last-id', null), '42');
    // Also verify the returned page tree used the correct param
    final content = await decodeBody(res);
    expect(content.root.children[0].props['text'], 'item-42');
  });

  test('dynamic route with no-match returns 404', () async {
    final handler = buildParamApp().handler;
    // /item/:id requires exactly two segments — /item alone should 404
    final res = await handler(
        Request('GET', Uri.parse('http://x/__page?route=/item')));
    expect(res.statusCode, 404);
  });
}
