import 'package:next_dart_server/next_dart_server.dart';
import 'package:test/test.dart';

void main() {
  group('RoutePattern.match — static routes', () {
    test('exact match returns empty params map', () {
      final p = RoutePattern.parse('/a/b');
      expect(p.match('/a/b'), equals(<String, String>{}));
    });

    test('non-matching path returns null', () {
      final p = RoutePattern.parse('/a/b');
      expect(p.match('/a/c'), isNull);
    });

    test('different segment count returns null', () {
      final p = RoutePattern.parse('/a/b');
      expect(p.match('/a'), isNull);
      expect(p.match('/a/b/c'), isNull);
    });

    test('root "/" matches exactly', () {
      final p = RoutePattern.parse('/');
      expect(p.match('/'), equals(<String, String>{}));
      expect(p.match('/x'), isNull);
    });

    test('isDynamic is false for static patterns', () {
      expect(RoutePattern.parse('/a/b').isDynamic, isFalse);
      expect(RoutePattern.parse('/').isDynamic, isFalse);
    });

    test('raw preserves original pattern string', () {
      expect(RoutePattern.parse('/a/b').raw, '/a/b');
    });
  });

  group('RoutePattern.match — dynamic routes', () {
    test('/product/:id matches /product/42 and extracts id', () {
      final p = RoutePattern.parse('/product/:id');
      expect(p.match('/product/42'), equals({'id': '42'}));
    });

    test('/product/:id does not match /product (missing segment)', () {
      final p = RoutePattern.parse('/product/:id');
      expect(p.match('/product'), isNull);
    });

    test('/product/:id does not match /product/42/x (extra segment)', () {
      final p = RoutePattern.parse('/product/:id');
      expect(p.match('/product/42/x'), isNull);
    });

    test('multiple params /u/:uid/post/:pid', () {
      final p = RoutePattern.parse('/u/:uid/post/:pid');
      expect(p.match('/u/alice/post/99'), equals({'uid': 'alice', 'pid': '99'}));
    });

    test('literal segment mismatch with param neighbour returns null', () {
      final p = RoutePattern.parse('/product/:id');
      expect(p.match('/wrong/42'), isNull);
    });

    test('isDynamic is true for dynamic patterns', () {
      expect(RoutePattern.parse('/product/:id').isDynamic, isTrue);
      expect(RoutePattern.parse('/u/:uid/post/:pid').isDynamic, isTrue);
    });
  });

  group('RouteTable — static-over-dynamic preference', () {
    test('registers and resolves a static route', () {
      final table = RouteTable<String>();
      table.register(RoutePattern.parse('/product/new'), 'static-new');
      final result = table.resolve('/product/new');
      expect(result, isNotNull);
      expect(result!.value, 'static-new');
      expect(result.params, isEmpty);
    });

    test('registers and resolves a dynamic route', () {
      final table = RouteTable<String>();
      table.register(RoutePattern.parse('/product/:id'), 'dynamic-id');
      final result = table.resolve('/product/42');
      expect(result, isNotNull);
      expect(result!.value, 'dynamic-id');
      expect(result.params, equals({'id': '42'}));
    });

    test('static route beats dynamic when both match', () {
      final table = RouteTable<String>();
      table.register(RoutePattern.parse('/product/:id'), 'dynamic-id');
      table.register(RoutePattern.parse('/product/new'), 'static-new');
      final result = table.resolve('/product/new');
      expect(result!.value, 'static-new');
      expect(result.params, isEmpty);
    });

    test('dynamic route is used when static does not match', () {
      final table = RouteTable<String>();
      table.register(RoutePattern.parse('/product/:id'), 'dynamic-id');
      table.register(RoutePattern.parse('/product/new'), 'static-new');
      final result = table.resolve('/product/123');
      expect(result!.value, 'dynamic-id');
      expect(result.params, equals({'id': '123'}));
    });

    test('unregistered path returns null', () {
      final table = RouteTable<String>();
      table.register(RoutePattern.parse('/product/:id'), 'dynamic-id');
      expect(table.resolve('/other/path'), isNull);
    });
  });
}
