// packages/next_dart_protocol/lib/src/component.dart
import 'node.dart';

/// A server-defined reusable component, composed from catalog primitives.
/// Shipped as data; the client renderer resolves it. Params are referenced in
/// [body] via [NdArgRef].
class NdComponentDef {
  final String name;
  final List<String> params;
  final NdNode body;
  const NdComponentDef({
    required this.name,
    required this.params,
    required this.body,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'params': params,
        'body': body.toJson(),
      };

  static NdComponentDef fromJson(Map<String, Object?> json) => NdComponentDef(
        name: json['name'] as String,
        params: (json['params'] as List).cast<String>(),
        body: NdNode.fromJson((json['body'] as Map).cast<String, Object?>()),
      );
}
