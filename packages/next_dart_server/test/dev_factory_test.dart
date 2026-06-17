// packages/next_dart_server/test/dev_factory_test.dart
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('NextDartApp.dev()', () {
    test('returns a usable NextDartApp with devMode enabled', () async {
      final app = await NextDartApp.dev();
      expect(app.devMode, isTrue);
    });

    test('handler serves /__page after a page is registered', () async {
      final app = await NextDartApp.dev();
      app.page('/', (ctx) => ndColumn([ndText('Hello from next-dart')]));

      final res = await app.handler(
        Request('GET', Uri.parse('http://localhost/__page?route=/')),
      );
      expect(res.statusCode, 200);
    });

    test('page() and action() work on the returned instance', () async {
      final app = await NextDartApp.dev();

      app.page('/', (ctx) {
        final n = ctx.state.get<int>('n', 0);
        return ndColumn([ndText('n=$n')]);
      });
      app.action('inc', (ctx) {
        ctx.state.update<int>('n', 0, (v) => v + 1);
      });

      // Page is reachable
      final res = await app.handler(
        Request('GET', Uri.parse('http://localhost/__page?route=/')),
      );
      expect(res.statusCode, 200);
    });

    test('two dev() calls produce independent instances', () async {
      final a = await NextDartApp.dev();
      final b = await NextDartApp.dev();
      // They are distinct objects (different ephemeral keys).
      expect(identical(a, b), isFalse);
    });
  });
}
