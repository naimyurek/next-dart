// packages/next_dart_server/lib/src/context.dart

/// Per-process mutable state for the MVP (single logical session).
/// Phase 2 will key this by client/session token.
class ServerState {
  final Map<String, Object?> _values = {};

  T get<T>(String key, T fallback) => (_values[key] as T?) ?? fallback;
  void set(String key, Object? value) => _values[key] = value;
  void update<T>(String key, T fallback, T Function(T) fn) =>
      _values[key] = fn(get<T>(key, fallback));
}

/// Passed to page builders.
class PageContext {
  final ServerState state;

  /// Path parameters extracted from a dynamic route, e.g. `{'id': '42'}` for
  /// a pattern like `/product/:id`. Empty for static (exact) routes.
  final Map<String, String> params;

  PageContext(this.state, {this.params = const {}});
}

/// Passed to action handlers.
class ActionContext {
  final ServerState state;
  final Map<String, Object?> args;

  /// Path parameters extracted from a dynamic route, e.g. `{'id': '42'}` for
  /// a pattern like `/product/:id`. Empty for static (exact) routes.
  final Map<String, String> params;

  ActionContext(this.state, this.args, {this.params = const {}});
}
