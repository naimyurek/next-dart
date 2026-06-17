/// Route pattern matching with named path parameters.
///
/// A pattern like `/product/:id` matches paths of the same segment count where
/// literal segments must equal their counterparts and `:name` segments capture
/// the corresponding path segment into a [Map<String,String>].
///
/// [RouteTable] holds a set of registered (pattern, value) pairs and resolves a
/// concrete path, **preferring static (no-param) patterns over dynamic ones**
/// when both would match.
library;

/// A compiled route pattern.
class RoutePattern {
  /// The original pattern string (e.g. `/product/:id`).
  final String raw;

  /// True when at least one segment is a named parameter.
  final bool isDynamic;

  final List<_Segment> _segments;

  RoutePattern._(this.raw, this._segments, this.isDynamic);

  /// Parse [pattern] into a [RoutePattern].
  ///
  /// Splitting is done on `/`. A leading slash produces an empty first segment
  /// that is ignored, so `/a/b` and `a/b` are treated identically. A bare `/`
  /// produces an empty segment list, matching only the root path `/`.
  factory RoutePattern.parse(String pattern) {
    final parts = pattern.split('/').where((s) => s.isNotEmpty).toList();
    bool dynamic = false;
    final segments = <_Segment>[];
    for (final p in parts) {
      if (p.startsWith(':')) {
        dynamic = true;
        segments.add(_ParamSegment(p.substring(1)));
      } else {
        segments.add(_LiteralSegment(p));
      }
    }
    return RoutePattern._(pattern, segments, dynamic);
  }

  /// Attempt to match [path] against this pattern.
  ///
  /// Returns a (possibly empty) [Map<String,String>] of captured parameters on
  /// success, or `null` if the path does not match.
  Map<String, String>? match(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length != _segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < _segments.length; i++) {
      final seg = _segments[i];
      if (seg is _LiteralSegment) {
        if (seg.value != parts[i]) return null;
      } else if (seg is _ParamSegment) {
        params[seg.name] = parts[i];
      }
    }
    return params;
  }
}

// ── Internal segment types ──────────────────────────────────────────────────

abstract class _Segment {}

class _LiteralSegment extends _Segment {
  final String value;
  _LiteralSegment(this.value);
}

class _ParamSegment extends _Segment {
  final String name;
  _ParamSegment(this.name);
}

// ── RouteTable ───────────────────────────────────────────────────────────────

/// The result of a successful [RouteTable.resolve] call.
class RouteMatch<T> {
  final T value;
  final Map<String, String> params;
  RouteMatch(this.value, this.params);
}

/// A registry of (pattern → value) pairs with static-over-dynamic precedence.
class RouteTable<T> {
  final _static = <RoutePattern, T>{};
  final _dynamic = <RoutePattern, T>{};

  /// Register [value] for [pattern].
  void register(RoutePattern pattern, T value) {
    if (pattern.isDynamic) {
      _dynamic[pattern] = value;
    } else {
      _static[pattern] = value;
    }
  }

  /// Resolve [path] to the best-matching registered entry, or `null`.
  ///
  /// Static (literal-only) patterns are tried before dynamic ones so that
  /// `/product/new` is preferred over `/product/:id` when both match.
  RouteMatch<T>? resolve(String path) {
    for (final entry in _static.entries) {
      final params = entry.key.match(path);
      if (params != null) return RouteMatch(entry.value, params);
    }
    for (final entry in _dynamic.entries) {
      final params = entry.key.match(path);
      if (params != null) return RouteMatch(entry.value, params);
    }
    return null;
  }
}
