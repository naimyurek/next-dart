// packages/next_dart_server/lib/src/app.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'context.dart';

typedef PageBuilder = NdNode Function(PageContext ctx);
typedef ActionHandler = void Function(ActionContext ctx);

/// A next-dart backend: routes, actions, shared components, and signing keys.
class NextDartApp {
  final SimpleKeyPair signingKeyPair;
  final SecretKey secretKey;
  final String keyId;
  final String minClientVersion;
  final List<NdComponentDef> components;
  final ServerState state = ServerState();

  final Map<String, PageBuilder> _pages = {};
  final Map<String, ActionHandler> _actions = {};
  int _contentVersion = 0;

  NextDartApp({
    required this.signingKeyPair,
    required this.secretKey,
    required this.keyId,
    this.minClientVersion = '1.0.0',
    this.components = const [],
  });

  void page(String route, PageBuilder builder) => _pages[route] = builder;
  void action(String id, ActionHandler handler) => _actions[id] = handler;

  Future<List<int>> _envelopeFor(String route) {
    final builder = _pages[route]!;
    final root = builder(PageContext(state));
    return encodeEnvelope(
      content: EnvelopeContent(root: root, components: components),
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
      if (!_pages.containsKey(route)) {
        return Response.notFound('no such route: $route');
      }
      final bytes = await _envelopeFor(route);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    router.post('/__action', (Request req) async {
      final body = (jsonDecode(await req.readAsString()) as Map).cast<String, Object?>();
      final id = body['action'] as String;
      final route = body['route'] as String? ?? '/';
      final args = (body['args'] as Map?)?.cast<String, Object?>() ?? const {};
      final h = _actions[id];
      if (h == null) return Response.notFound('no such action: $id');
      h(ActionContext(state, args));
      if (!_pages.containsKey(route)) {
        return Response.notFound('no such route: $route');
      }
      final bytes = await _envelopeFor(route);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    return router.call;
  }
}
