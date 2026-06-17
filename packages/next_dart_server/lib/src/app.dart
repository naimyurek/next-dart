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
