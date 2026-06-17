// packages/next_dart_server/lib/src/app.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'component_library.dart';
import 'context.dart';
import 'router.dart';
import 'session.dart';

typedef PageBuilder = NdNode Function(PageContext ctx);
typedef ActionHandler = void Function(ActionContext ctx);

/// Resolves the replacement subtree for a streaming slot.
typedef SlotResolver = Future<NdNode> Function();

/// A next-dart backend: routes, actions, shared components, and signing keys.
class NextDartApp {
  final SimpleKeyPair signingKeyPair;
  final SecretKey secretKey;
  final String keyId;
  final String minClientVersion;

  /// When true, every `/__page`, `/__action`, and `/__stream` request MUST
  /// carry a valid post-handshake `kid`. A request with no `kid` (or an
  /// unknown/expired one) returns the 409 re-handshake signal instead of
  /// falling back to the provisioned key.
  ///
  /// Defaults to false, which preserves Phase 1/2 and demo behaviour: a
  /// missing `kid` silently falls back to the provisioned [secretKey].
  final bool requireHandshake;
  /// Flat component list kept for back-compat.  Prefer [componentLibraries].
  final List<NdComponentDef> components;
  final List<ComponentLibrary> componentLibraries;
  final ServerState state = ServerState();

  /// When true, the `/__events` SSE endpoint is active and [bumpContent] can
  /// be called to push a `reload` event to all connected clients.
  final bool devMode;

  /// How long a handshake-derived session key stays valid (F8). After this the
  /// client receives a 409 re-handshake signal and transparently renegotiates.
  final Duration sessionTtl;

  /// Wall-clock source in epoch milliseconds. Defaults to real time; injectable
  /// so session-expiry behaviour is deterministic in tests. (The server is a
  /// normal Dart process, so using the real clock by default is fine.)
  final int Function() nowMillis;

  /// F8 session-key store: keyId -> derived session key + expiry.
  final SessionStore _sessions = SessionStore();

  /// Merged, deduplicated, library-stamped registry built at construction.
  late final ComponentRegistry _registry;

  final RouteTable<PageBuilder> _pages = RouteTable();
  final Map<String, ActionHandler> _actions = {};
  // Slot resolvers keyed by route, then by slot id. Insertion order is the
  // patch-frame emission order for that route.
  final Map<String, Map<String, SlotResolver>> _slotResolvers = {};
  // Increments on every response (page load or action). Phase 2 (multi-session) will scope this per client.
  int _contentVersion = 0;

  // Dev-mode SSE broadcast channel. Only allocated when devMode is true.
  StreamController<String>? _devEvents;

  /// Exposes the raw dev-event stream for testing (non-null only when devMode
  /// is true). Tests can listen directly without going through HTTP.
  Stream<String>? get devEventStream => _devEvents?.stream;

  NextDartApp({
    required this.signingKeyPair,
    required this.secretKey,
    required this.keyId,
    this.minClientVersion = '1.0.0',
    this.components = const [],
    this.componentLibraries = const [],
    this.devMode = false,
    this.requireHandshake = false,
    this.sessionTtl = const Duration(minutes: 30),
    int Function()? nowMillis,
  }) : nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch) {
    // Throws StateError immediately on duplicate names — fails fast at startup.
    _registry = ComponentRegistry(
      flatComponents: components,
      libraries: componentLibraries,
    );
    if (devMode) {
      _devEvents = StreamController<String>.broadcast();
    }
  }

  /// Creates an app with freshly generated EPHEMERAL keys and devMode on.
  ///
  /// FOR LOCAL DEVELOPMENT ONLY — the keys are random per process and not
  /// shared with any client, so this is NOT secure and NOT for production.
  /// Use the real constructor with provisioned keys for anything real.
  static Future<NextDartApp> dev({
    List<NdComponentDef> components = const [],
    List<ComponentLibrary> componentLibraries = const [],
  }) async {
    final kp = await Ed25519().newKeyPair();
    final rng = Random.secure();
    final secret = SecretKey(List<int>.generate(32, (_) => rng.nextInt(256)));
    return NextDartApp(
      signingKeyPair: kp,
      secretKey: secret,
      keyId: 'dev',
      devMode: true,
      components: components,
      componentLibraries: componentLibraries,
    );
  }

  /// Increment the dev content counter and push a `reload` event to all
  /// connected `/__events` SSE clients. Only effective when [devMode] is true.
  void bumpContent() {
    if (!devMode) return;
    _contentVersion++;
    _devEvents?.add('reload');
  }

  void page(String pattern, PageBuilder builder) =>
      _pages.register(RoutePattern.parse(pattern), builder);

  void action(String id, ActionHandler handler) => _actions[id] = handler;

  /// Register the async [resolve] that produces the replacement subtree for
  /// slot [id] on [route]. Resolvers for a route are streamed (as patch frames)
  /// in registration order after the initial frame. See [stream].
  void slotResolver(String route, String id, SlotResolver resolve) =>
      (_slotResolvers[route] ??= {})[id] = resolve;

  Future<List<int>> _envelopeFor(
      String route, PageBuilder builder, Map<String, String> params,
      {required SecretKey sessionKey, required String sessionKeyId}) {
    final root = builder(PageContext(state, params: params));
    return encodeEnvelope(
      content: EnvelopeContent(root: root, components: _registry.all()),
      route: route,
      contentVersion: ++_contentVersion,
      minClientVersion: minClientVersion,
      keyId: sessionKeyId,
      secretKey: sessionKey,
      signingKeyPair: signingKeyPair,
    );
  }

  /// Encode one streaming frame as a wire envelope, reusing [encodeEnvelope]
  /// unchanged. The frame kind/slot ride in [content.data].
  ///
  /// [sessionKey] and [sessionKeyId] are resolved from the `kid` query param
  /// so all frames of a stream share the same encryption key.
  Future<List<int>> _frameFor(
    String route,
    EnvelopeContent content, {
    required SecretKey sessionKey,
    required String sessionKeyId,
  }) =>
      encodeEnvelope(
        content: content,
        route: route,
        contentVersion: ++_contentVersion,
        minClientVersion: minClientVersion,
        keyId: sessionKeyId,
        secretKey: sessionKey,
        signingKeyPair: signingKeyPair,
      );

  /// Outcome of resolving a request's `kid` to the key it should be encrypted
  /// under. Either a usable (key, keyId) pair, or a signal that the client must
  /// re-handshake because the named session is unknown/expired.
  ///
  /// When [requireHandshake] is false (default): no `kid` → the provisioned
  /// key (Phase 1/2 back-compat). When [requireHandshake] is true: no `kid`
  /// is treated exactly like an unknown session and returns null → 409.
  ({SecretKey key, String keyId})? _resolveSessionKey(String? kid) {
    if (kid == null || kid.isEmpty) {
      if (requireHandshake) return null; // no kid is not allowed → re-handshake
      // Back-compat: fall back to the provisioned key.
      return (key: secretKey, keyId: keyId);
    }
    final live = _sessions.keyFor(kid, nowMillis());
    if (live == null) return null; // unknown or expired -> re-handshake
    return (key: live, keyId: kid);
  }

  /// The 409 body the client recognizes as "your session is gone, handshake
  /// again". Small, typed, and JSON so both ends agree on the shape.
  static Response _rehandshake() => Response(
        409,
        body: jsonEncode({'error': 'rehandshake'}),
        headers: {'content-type': 'application/json'},
      );

  /// Build the signed handshake response for a client's ephemeral public key,
  /// allocate a fresh session keyId, and store the derived key. Exposed for
  /// tests; also used by the `POST /__handshake` route.
  Future<HandshakeResponse> handshake(List<int> clientPubBytes) async {
    final now = nowMillis();
    _sessions.prune(now); // opportunistic cleanup
    final expiresAt = now + sessionTtl.inMilliseconds;
    // Allocate the keyId first: it is bound into the signed message and used as
    // the HKDF salt on both sides, so it must be known before deriving.
    final sessionKeyId = _sessions.allocateId();
    final result = await buildHandshakeResponse(
      clientPubBytes: clientPubBytes,
      serverEd25519: signingKeyPair,
      keyId: sessionKeyId,
      expiresAtMillis: expiresAt,
    );
    _sessions.store(sessionKeyId, result.sessionKey, expiresAt);
    return result.response;
  }

  /// Stream a route as newline-delimited base64 envelope frames:
  ///   1. an initial frame carrying the page tree (which may hold Slot nodes);
  ///   2. one patch frame per registered [slotResolver] for the route, in
  ///      registration order, emitted as each resolver completes.
  ///
  /// Each yielded chunk is the UTF-8 bytes of `"<base64-envelope>\n"`. Base64
  /// guarantees the envelope bytes never contain a raw newline, so consumers
  /// can split the response on '\n'. Throws [StateError] if [route] has no page.
  ///
  /// [sessionKey] and [sessionKeyId] are the resolved encryption key (from the
  /// `kid` query param); all frames are encrypted under the same key.
  Stream<List<int>> stream(
    String route, {
    required SecretKey sessionKey,
    required String sessionKeyId,
  }) async* {
    final match = _pages.resolve(route);
    if (match == null) {
      throw StateError('no such route: $route');
    }
    final root = match.value(PageContext(state, params: match.params));
    final initial = await _frameFor(
      route,
      EnvelopeContent(
        root: root,
        components: _registry.all(),
        data: initialFrameData(),
      ),
      sessionKey: sessionKey,
      sessionKeyId: sessionKeyId,
    );
    yield _line(initial);

    final resolvers = _slotResolvers[route];
    if (resolvers != null) {
      for (final entry in resolvers.entries) {
        final resolved = await entry.value();
        final patch = await _frameFor(
          route,
          EnvelopeContent(root: resolved, data: patchFrameData(entry.key)),
          sessionKey: sessionKey,
          sessionKeyId: sessionKeyId,
        );
        yield _line(patch);
      }
    }
  }

  /// One base64-encoded envelope followed by a newline, as UTF-8 bytes.
  List<int> _line(List<int> envelopeBytes) =>
      utf8.encode('${base64.encode(envelopeBytes)}\n');

  Handler get handler {
    final router = Router();

    // SSE hot-reload endpoint — only active in dev mode.
    router.get('/__events', (Request req) {
      if (!devMode) {
        return Response.notFound('not found');
      }
      // Build the SSE body as a broadcast stream of UTF-8 encoded frames.
      final controller = StreamController<List<int>>();

      // Emit the initial `: connected\n\n` comment so clients can confirm
      // the stream opened before the first reload event arrives.
      controller.add(utf8.encode(': connected\n\n'));

      // Subscribe to reload events for as long as this request is alive.
      final sub = _devEvents!.stream.listen((event) {
        if (!controller.isClosed) {
          controller.add(utf8.encode('data: $event\n\n'));
        }
      });

      // When the client disconnects, clean up.
      controller.onCancel = () {
        sub.cancel();
      };

      return Response.ok(
        controller.stream,
        headers: {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
        },
      );
    });

    router.get('/__page', (Request req) async {
      final route = req.url.queryParameters['route'] ?? '/';
      final match = _pages.resolve(route);
      if (match == null) {
        return Response.notFound('no such route: $route');
      }
      // F8: resolve the encryption key from the request's `kid` (or the
      // provisioned key when absent). A named-but-dead session → 409.
      final session = _resolveSessionKey(req.url.queryParameters['kid']);
      if (session == null) return _rehandshake();
      final bytes = await _envelopeFor(route, match.value, match.params,
          sessionKey: session.key, sessionKeyId: session.keyId);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    router.get('/__stream', (Request req) async {
      final route = req.url.queryParameters['route'] ?? '/';
      if (_pages.resolve(route) == null) {
        return Response.notFound('no such route: $route');
      }
      // F8: resolve the encryption key from the request's `kid` exactly like
      // /__page. Under requireHandshake=true, a missing kid → 409.
      final session = _resolveSessionKey(req.url.queryParameters['kid']);
      if (session == null) return _rehandshake();
      // Build the full newline-delimited base64 body. Streaming the bytes
      // straight through is equally valid; buffering keeps it simple/testable.
      final body = <int>[];
      await for (final chunk in stream(route,
          sessionKey: session.key, sessionKeyId: session.keyId)) {
        body.addAll(chunk);
      }
      return Response.ok(body,
          headers: {'content-type': 'text/plain; charset=utf-8'});
    });

    router.post('/__action', (Request req) async {
      final raw = await req.readAsString();
      Map<String, Object?> body;
      try {
        body = (jsonDecode(raw) as Map).cast<String, Object?>();
      } catch (_) {
        return Response(400, body: 'invalid JSON body');
      }
      final id = body['action'];
      if (id is! String) {
        return Response(400, body: 'missing or non-string "action" field');
      }
      final route = body['route'] as String? ?? '/';
      final args = (body['args'] as Map?)?.cast<String, Object?>() ?? const {};
      final h = _actions[id];
      if (h == null) return Response.notFound('no such action: $id');
      final pageMatch = _pages.resolve(route);
      if (pageMatch == null) {
        return Response.notFound('no such route: $route');
      }
      // F8: resolve the session key BEFORE running the handler, so a stale
      // session is rejected (409) without causing an unobservable side effect.
      final session = _resolveSessionKey(body['kid'] as String?);
      if (session == null) return _rehandshake();
      h(ActionContext(state, args, params: pageMatch.params));
      final bytes = await _envelopeFor(route, pageMatch.value, pageMatch.params,
          sessionKey: session.key, sessionKeyId: session.keyId);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    router.post('/__handshake', (Request req) async {
      final raw = await req.readAsString();
      HandshakeRequest hsReq;
      try {
        final json = (jsonDecode(raw) as Map).cast<String, Object?>();
        hsReq = HandshakeRequest.fromJson(json);
      } catch (_) {
        return Response(400, body: 'invalid handshake request');
      }
      final List<int> clientPub;
      try {
        clientPub = base64.decode(hsReq.x25519Pub);
      } catch (_) {
        return Response(400, body: 'invalid x25519Pub base64');
      }
      final resp = await handshake(clientPub);
      return Response.ok(jsonEncode(resp.toJson()),
          headers: {'content-type': 'application/json'});
    });

    return router.call;
  }
}
