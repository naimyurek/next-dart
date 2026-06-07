import 'dart:convert';
import 'package:next_dart_protocol/src/canonical.dart';
import 'package:test/test.dart';

void main() {
  test('canonicalJsonBytes sorts keys deterministically', () {
    final a = canonicalJsonBytes({'b': 1, 'a': 2});
    final b = canonicalJsonBytes({'a': 2, 'b': 1});
    expect(a, b);
    expect(utf8.decode(a), '{"a":2,"b":1}');
  });

  test('canonicalJsonBytes recurses into nested maps and lists', () {
    final s = utf8.decode(canonicalJsonBytes({
      'z': [
        {'y': 1, 'x': 2}
      ]
    }));
    expect(s, '{"z":[{"x":2,"y":1}]}');
  });
}
