// packages/next_dart_protocol/lib/src/canonical.dart
import 'dart:convert';

/// Deterministic JSON byte serialization (recursively sorted map keys) used as
/// the message that signatures are computed over. Both server and client must
/// produce identical bytes for the same logical value.
List<int> canonicalJsonBytes(Object? value) => utf8.encode(_canonical(value));

String _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(v[k])}').join(',')}}';
  }
  if (v is List) {
    return '[${v.map(_canonical).join(',')}]';
  }
  return jsonEncode(v);
}
