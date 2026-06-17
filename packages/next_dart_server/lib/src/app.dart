// packages/next_dart_server/lib/src/app.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'component_library.dart';
import 'context.dart';
import 'router.dart';

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
  /// Flat component list kept for back-compat.  Prefer [componentLibraries].
  final List<NdComponentDef> components;
  final List<ComponentLibrary> componentLibraries;
  final ServerState state = ServerState();

  /// Merged, deduplicated, library-stamped registry built at construction.
  late final ComponentRegistry _registry;

  final RouteTable<PageBuilder> _pages = RouteTable();
  final Map<String, ActionHandler> _actions = {};
  // Slot resolvers keyed by route, then by slot id. Insertion order is the
  // patch-frame emission order for that route.
  final Map<String, Map<String, SlotResolver>> _slotResolvers = {};
  // Increments on every response (page load or action). Phase 2 (multi-session) will scope this per client.
  int _contentVersion = 0;

  NextDartApp({
    required this.signingKeyPair,
    required this.secretKey,
    required this.keyId,
    this.minClientVersion = '1.0.0',
    this.components = const [],
    this.componentLibraries = const [],
  }) {
    // Throws StateError immediately on duplicate names — fails fast at startup.
    _registry = ComponentRegistry(
      flatComponents: components,
      libraries: componentLibraries,
    );
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
      String route, PageBuilder builder, Map<String, String> params) {
    final root = builder(PageContext(state, params: params));
    return encodeEnvelope(
      content: EnvelopeContent(root: root, components: _registry.all()),
      route: route,
      contentVersion: ++_contentVersion,
      minClientVersion: minClientVersion,
      keyId: keyId,
      secretKey: secretKey,
      signingKeyPair: signingKeyPair,
    );
  }

  /// Encode one streaming frame as a wire envelope, reusing [encodeEnvelope]
  /// unchanged. The frame kind/slot ride in [content.data].
  Future<List<int>> _frameFor(String route, EnvelopeContent content) =>
      encodeEnvelope(
        content: content,
        route: route,
        contentVersion: ++_contentVersion,
        minClientVersion: minClientVersion,
        keyId: keyId,
        secretKey: secretKey,
        signingKeyPair: signingKeyPair,
      );

  /// Stream a route as newline-delimited base64 envelope frames:
  ///   1. an initial frame carrying the page tree (which may hold Slot nodes);
  ///   2. one patch frame per registered [slotResolver] for the route, in
  ///      registration order, emitted as each resolver completes.
  ///
  /// Each yielded chunk is the UTF-8 bytes of `"<base64-envelope>\n"`. Base64
  /// guarantees the envelope bytes never contain a raw newline, so consumers
  /// can split the response on '\n'. Throws [StateError] if [route] has no page.
  Stream<List<int>> stream(String route) async* {
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
    );
    yield _line(initial);

    final resolvers = _slotResolvers[route];
    if (resolvers != null) {
      for (final entry in resolvers.entries) {
        final resolved = await entry.value();
        final patch = await _frameFor(
          route,
          EnvelopeContent(root: resolved, data: patchFrameData(entry.key)),
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

    router.get('/__page', (Request req) async {
      final route = req.url.queryParameters['route'] ?? '/';
      final match = _pages.resolve(route);
      if (match == null) {
        return Response.notFound('no such route: $route');
      }
      final bytes = await _envelopeFor(route, match.value, match.params);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    router.get('/__stream', (Request req) async {
      final route = req.url.queryParameters['route'] ?? '/';
      if (_pages.resolve(route) == null) {
        return Response.notFound('no such route: $route');
      }
      // Build the full newline-delimited base64 body. Streaming the bytes
      // straight through is equally valid; buffering keeps it simple/testable.
      final body = <int>[];
      await for (final chunk in stream(route)) {
        body.addAll(chunk);
      }
      return Response.ok(body, headers: {'content-type': 'text/plain; charset=utf-8'});
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
      h(ActionContext(state, args, params: pageMatch.params));
      final bytes =
          await _envelopeFor(route, pageMatch.value, pageMatch.params);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    return router.call;
  }
}
