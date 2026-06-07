// examples/counter_app/server/lib/app.dart
// Exports buildApp() so it can be imported by both bin/server.dart and the
// integration test (package:counter_server/app.dart).
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'keys.dart';

/// Build and configure the counter demo application.
/// Returns a [NextDartApp] ready to serve requests.
Future<NextDartApp> buildApp() async {
  final kp = await Ed25519().newKeyPairFromSeed(base64.decode(signingSeedB64));
  final secret = SecretKey(base64.decode(secretKeyB64));

  // Composite component: a reusable fragment composed from primitives, defined on
  // the server and shipped as data — adding/changing one needs no app rebuild.
  final productCard = ndComponent('ProductCard', ['title', 'price', 'id'], (a) {
    return ndCard(
      child: ndColumn([
        ndText(a('title')),
        ndText(a('price')),
        ndButton(label: 'Buy', onPressed: action('buy', {'id': a('id')})),
      ]),
    );
  });

  final app = NextDartApp(
    signingKeyPair: kp,
    secretKey: secret,
    keyId: 'demo',
    components: [productCard],
  );

  // A page is a route → render function. It reads session state and returns an nd* tree.
  app.page('/', (ctx) {
    final count = ctx.state.get<int>('count', 0);
    final lastBought = ctx.state.get<String>('bought', '—');
    return ndColumn([
      ndText('Count: $count'),
      ndButton(label: 'Increment', onPressed: action('inc')),
      ndUse('ProductCard', {'title': 'Running Shoe', 'price': r'$79', 'id': 7}),
      ndText('Last bought id: $lastBought'),
    ]);
  });

  // Actions run on the server in response to a client event (e.g. a button tap).
  // They mutate session state; the page is re-rendered and re-sent automatically.
  app.action('inc', (ctx) {
    ctx.state.update<int>('count', 0, (n) => n + 1);
  });
  app.action('buy', (ctx) {
    ctx.state.set('bought', '${ctx.args['id']}');
  });

  return app;
}
