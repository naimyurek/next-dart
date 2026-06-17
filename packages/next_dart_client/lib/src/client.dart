// packages/next_dart_client/lib/src/client.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'source.dart';

/// Talks to a next-dart backend: fetches pages and dispatches actions, verifying
/// each envelope's signature and decrypting its payload.
///
/// F8: the client can perform an authenticated X25519 ECDH [handshake] to derive
/// a per-session AES-256-GCM key (rotated by `keyId`). Once a live session
/// exists, page/action requests attach its `kid` and are encrypted under the
/// derived key; otherwise they fall back to the provisioned [secretKey] (Phase
/// 1/2 back-compat). If the server reports the session is gone (HTTP 409
/// re-handshake), the client transparently handshakes once and retries.
class NextDartClient implements NextDartSource {
  final Uri baseUrl;

  /// Pinned server Ed25519 public key. Verifies BOTH envelope signatures and
  /// the handshake response signature (the server uses one identity key for
  /// both).
  final SimplePublicKey signingPublicKey;

  /// Provisioned symmetric key for the back-compat path (requests with no
  /// session / no `kid`). May be a placeholder if the app always handshakes.
  final SecretKey secretKey;
  final String clientVersion;
  final http.Client _http;

  // ── F8 session state ──────────────────────────────────────────────────────
  final X25519 _x25519 = X25519();
  SecretKey? _sessionKey;
  String? _sessionKeyId;
  int _expiresAtMillis = 0;

  NextDartClient({
    required this.baseUrl,
    required this.signingPublicKey,
    required this.secretKey,
    this.clientVersion = '1.0.0',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// The current session keyId, or null if no handshake has succeeded. Exposed
  /// for tests/diagnostics.
  String? get sessionKeyId => _sessionKey == null ? null : _sessionKeyId;

  /// Perform the authenticated ECDH handshake and install the derived session
  /// key. Generates a fresh ephemeral X25519 keypair, POSTs its public key to
  /// `/__handshake`, verifies the response against the pinned [signingPublicKey],
  /// and on success stores the derived session key + keyId + expiry.
  ///
  /// Throws [HandshakeError] if the response signature does not verify (the
  /// derived key is then NOT installed), or [DecodeError] on a non-200.
  Future<void> handshake() async {
    final clientKp = await _x25519.newKeyPair();
    final clientPub = await clientKp.extractPublicKey();

    final res = await _http.post(
      baseUrl.replace(path: '/__handshake'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(
          HandshakeRequest(x25519Pub: base64.encode(clientPub.bytes))
              .toJson()),
    );
    if (res.statusCode != 200) {
      throw DecodeError('handshake failed: server returned ${res.statusCode}');
    }
    final resp = HandshakeResponse.fromJson(
        (jsonDecode(res.body) as Map).cast<String, Object?>());
    // Throws HandshakeError on a bad/forged signature → session NOT installed.
    final key = await verifyAndDeriveClientSession(
      response: resp,
      clientKeyPair: clientKp,
      clientPubBytes: clientPub.bytes,
      pinnedServerEd25519Pub: signingPublicKey,
    );
    _sessionKey = key;
    _sessionKeyId = resp.keyId;
    _expiresAtMillis = resp.expiresAtMillis;
  }

  /// The live session key, or null if none / expired. Expiry uses the client
  /// wall clock (the server is authoritative and will 409 if it disagrees).
  SecretKey? get _liveSessionKey {
    if (_sessionKey == null) return null;
    if (DateTime.now().millisecondsSinceEpoch >= _expiresAtMillis) return null;
    return _sessionKey;
  }

  @override
  Future<EnvelopeContent> fetchPage(String route) =>
      _withRehandshake(() async {
        final session = _liveSessionKey;
        final params = {
          'route': route,
          if (session != null) 'kid': _sessionKeyId!,
        };
        final res = await _http
            .get(baseUrl.replace(path: '/__page', queryParameters: params));
        // Decode under the SAME key the request was sent with.
        return (res: res, key: session ?? secretKey);
      });

  @override
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
          {required String route}) =>
      _withRehandshake(() async {
        final session = _liveSessionKey;
        final res = await _http.post(
          baseUrl.replace(path: '/__action'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'action': action,
            'args': args,
            'route': route,
            if (session != null) 'kid': _sessionKeyId!,
          }),
        );
        return (res: res, key: session ?? secretKey);
      });

  /// Run [send] (which issues one HTTP request and reports the key it used),
  /// decode the response, and — if the server answers 409 (session
  /// unknown/expired) — transparently [handshake] ONCE and retry [send] a
  /// single time. A second 409 surfaces as a [DecodeError] rather than looping.
  ///
  /// Decoding always uses the key reported by [send] for THAT attempt, so the
  /// decryption key always matches the key the request was encrypted under
  /// (after a re-handshake the retry reports the freshly-derived session key).
  Future<EnvelopeContent> _withRehandshake(
      Future<({http.Response res, SecretKey key})> Function() send) async {
    var sent = await send();
    if (sent.res.statusCode == 409 && _isRehandshake(sent.res)) {
      await handshake();
      sent = await send();
    }
    return _decodeWith(sent.res, sent.key);
  }

  /// True if [res] is the typed re-handshake signal.
  bool _isRehandshake(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      return body is Map && body['error'] == 'rehandshake';
    } catch (_) {
      return false;
    }
  }

  /// Connects to `/__events` via SSE and yields `'reload'` for each reload
  /// push from the server. Comment lines (starting with `:`) are silently
  /// skipped. The stream ends when the HTTP connection closes.
  @override
  Stream<String> events() async* {
    final req = http.Request('GET', baseUrl.replace(path: '/__events'));
    final res = await _http.send(req);
    if (res.statusCode != 200) {
      return; // server not in dev mode — simply yield nothing
    }
    final lines = res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.startsWith(':')) continue; // SSE comment — skip
      if (line.startsWith('data: ')) {
        yield line.substring('data: '.length).trim();
      }
    }
  }

  @override
  Stream<EnvelopeContent> streamPage(String route) async* {
    final req = http.Request(
        'GET',
        baseUrl
            .replace(path: '/__stream', queryParameters: {'route': route}));
    final res = await _http.send(req);
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      final snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;
      throw DecodeError('server returned ${res.statusCode}: $snippet');
    }
    // One base64 envelope per line; decode (verify + decrypt) each frame.
    final lines = res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      yield await decodeEnvelope(
        base64.decode(line),
        secretKey: secretKey,
        signingPublicKey: signingPublicKey,
        clientVersion: clientVersion,
      );
    }
  }

  /// Verify + decrypt [res] under [key] (the key the request was sent with).
  Future<EnvelopeContent> _decodeWith(http.Response res, SecretKey key) {
    if (res.statusCode != 200) {
      final body = res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body;
      throw DecodeError('server returned ${res.statusCode}: $body');
    }
    return decodeEnvelope(
      res.bodyBytes,
      secretKey: key,
      signingPublicKey: signingPublicKey,
      clientVersion: clientVersion,
    );
  }

  /// The caller owns the client's lifecycle and should call [close] when done
  /// if they did not inject their own [http.Client].
  void close() => _http.close();
}
