// packages/next_dart_server/lib/src/session.dart
import 'package:cryptography/cryptography.dart';

/// One live session: its derived AES-256-GCM key and wall-clock expiry.
class _Session {
  final SecretKey key;
  final int expiresAtMillis;
  const _Session(this.key, this.expiresAtMillis);
}

/// In-memory store of per-session keys, keyed by a server-allocated `keyId`.
///
/// F8: each successful handshake derives a fresh session key and registers it
/// here under a fresh, monotonically-increasing keyId. Subsequent client
/// requests carry that `kid`; the server looks the key up by id (rejecting
/// missing/expired sessions, which triggers a re-handshake).
///
/// Time is always passed in explicitly ([keyFor]/[prune] take `nowMillis`) so
/// the store itself is deterministic and testable; the caller (the server app)
/// owns the real clock.
class SessionStore {
  final Map<String, _Session> _sessions = {};
  int _counter = 0;

  /// Register [key] expiring at [expiresAtMillis]; returns its fresh keyId.
  ///
  /// The id is a monotonic counter with a short random suffix so ids are not
  /// guessable across restarts and never collide within a process.
  String newSession(SecretKey key, int expiresAtMillis) {
    final id = allocateId();
    store(id, key, expiresAtMillis);
    return id;
  }

  /// Reserve a fresh, unique keyId WITHOUT yet associating a key. Used by the
  /// handshake, where the id must be known (it is signed and used as the HKDF
  /// salt) before the session key is derived. Pair with [store].
  String allocateId() => 's${_counter++}-${_randomSuffix()}';

  /// Associate [key]/[expiresAtMillis] with a previously [allocateId]'d [keyId]
  /// (or overwrite an existing one).
  void store(String keyId, SecretKey key, int expiresAtMillis) {
    _sessions[keyId] = _Session(key, expiresAtMillis);
  }

  /// The live key for [keyId], or null if unknown or expired at [nowMillis].
  ///
  /// Expiry is an exclusive upper bound: a session expiring at T is already
  /// invalid at T.
  SecretKey? keyFor(String keyId, int nowMillis) {
    final s = _sessions[keyId];
    if (s == null) return null;
    if (nowMillis >= s.expiresAtMillis) return null;
    return s.key;
  }

  /// Drop every session whose expiry is at or before [nowMillis]. Cheap to call
  /// opportunistically (e.g. on each new handshake) to bound memory growth.
  void prune(int nowMillis) {
    _sessions.removeWhere((_, s) => nowMillis >= s.expiresAtMillis);
  }

  /// Number of currently-stored sessions (live or not). Exposed for tests.
  int get length => _sessions.length;

  // A short non-cryptographic-strength uniqueness suffix. The keyId is NOT a
  // secret — security comes from the Ed25519-signed handshake and the session
  // key itself, not from id unpredictability — but a suffix avoids any chance
  // of cross-restart id reuse colliding with a stale client guess.
  static int _seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  String _randomSuffix() {
    // xorshift — deterministic-free, no need for crypto RNG here.
    _seed ^= _seed << 13;
    _seed ^= _seed >> 17;
    _seed ^= _seed << 5;
    return (_seed & 0xffffff).toRadixString(16).padLeft(6, '0');
  }
}
