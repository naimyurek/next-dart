// packages/next_dart_server/lib/src/cache.dart
//
// ISR / advanced caching support (F9).

import 'package:next_dart_protocol/next_dart_protocol.dart';

// ── RevalidatePolicy ─────────────────────────────────────────────────────────

/// Controls how long a server-cached page body remains fresh.
///
/// - [RevalidatePolicy.never]         — cache never expires (true SSG).
/// - [RevalidatePolicy.afterSeconds]  — stale after [ttlSeconds] seconds.
/// - [RevalidatePolicy.onDemand]      — fresh until [NextDartApp.revalidate] is
///   called for the route; then the next request rebuilds and re-caches.
///
/// When no policy is given to [NextDartApp.page], the route is NOT cached and
/// every request calls the builder (the Phase 1/2 default behaviour).
abstract class RevalidatePolicy {
  const RevalidatePolicy._();

  /// Cache is perpetually fresh — the builder is called exactly once.
  const factory RevalidatePolicy.never() = _NeverPolicy;

  /// Cache is fresh for [seconds] seconds from the last build time.
  const factory RevalidatePolicy.afterSeconds(int seconds) = _AfterSecondsPolicy;

  /// Cache is fresh until [NextDartApp.revalidate] explicitly invalidates it.
  const factory RevalidatePolicy.onDemand() = _OnDemandPolicy;

  /// Returns true when the entry is still fresh given [builtAtMillis] and the
  /// current time [nowMillis]. For on-demand policies [stale] carries the
  /// externally-set staleness flag.
  bool isFresh({
    required int builtAtMillis,
    required int nowMillis,
    required bool stale,
  });
}

class _NeverPolicy extends RevalidatePolicy {
  const _NeverPolicy() : super._();

  @override
  bool isFresh({required int builtAtMillis, required int nowMillis, required bool stale}) =>
      true; // never expires
}

class _AfterSecondsPolicy extends RevalidatePolicy {
  final int ttlSeconds;
  const _AfterSecondsPolicy(this.ttlSeconds) : super._();

  @override
  bool isFresh({required int builtAtMillis, required int nowMillis, required bool stale}) =>
      (nowMillis - builtAtMillis) < ttlSeconds * 1000;
}

class _OnDemandPolicy extends RevalidatePolicy {
  const _OnDemandPolicy() : super._();

  @override
  bool isFresh({required int builtAtMillis, required int nowMillis, required bool stale}) =>
      !stale; // stale flag is set by app.revalidate()
}

// ── CacheEntry ───────────────────────────────────────────────────────────────

/// A single cached page body together with its stable content version and the
/// wall-clock milliseconds at which it was built.
class CacheEntry {
  final EnvelopeContent content;
  final int contentVersion;
  final int builtAtMillis;

  /// Set to true by [PageCache.invalidate]; cleared when the entry is rebuilt.
  bool stale;

  CacheEntry({
    required this.content,
    required this.contentVersion,
    required this.builtAtMillis,
    this.stale = false,
  });
}

// ── PageCache ─────────────────────────────────────────────────────────────────

/// The server-side ISR cache.
///
/// Keyed by a *cache key* formed from the resolved route path and its sorted
/// query-style parameters string (e.g. `"/item/42?"`). Each entry stores the
/// built [EnvelopeContent], its stable [contentVersion], and the time it was
/// built.
class PageCache {
  final _entries = <String, CacheEntry>{};

  /// Build a canonical cache key from a route and its resolved params map.
  ///
  /// Params are sorted by key so that `{b:2, a:1}` and `{a:1, b:2}` produce
  /// the same key. The route and the serialised params are joined with `?`.
  static String cacheKey(String route, Map<String, String> params) {
    if (params.isEmpty) return '$route?';
    final sorted = (params.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return '$route?$sorted';
  }

  /// Look up the entry for [key]. Returns null if no entry exists.
  CacheEntry? get(String key) => _entries[key];

  /// Store (or overwrite) the entry for [key].
  void put(String key, CacheEntry entry) => _entries[key] = entry;

  /// Mark the entry for [key] as stale (triggers rebuild on next request).
  /// Also invalidates any entries whose key starts with the route prefix —
  /// because [revalidate] is keyed by route pattern (not by params), we must
  /// invalidate ALL param variants.
  void invalidateRoute(String route) {
    // The cache key is "<route>?" or "<route>?<params>", so we match on prefix.
    final prefix = '$route?';
    for (final k in _entries.keys.toList()) {
      if (k == prefix || k.startsWith(prefix)) {
        _entries[k]?.stale = true;
      }
    }
  }
}
