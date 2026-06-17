// packages/next_dart_protocol/lib/src/component.dart
import 'node.dart';

/// A server-defined reusable component, composed from catalog primitives.
/// Shipped as data; the client renderer resolves it. Params are referenced in
/// [body] via [NdArgRef].
///
/// [library] and [libraryVersion] are optional; when present they carry the
/// originating library's identity on the wire. Absent fields are omitted from
/// JSON to stay back-compatible with pre-F3 clients.
class NdComponentDef {
  final String name;
  final List<String> params;
  final NdNode body;
  final String? library;
  final String? libraryVersion;

  const NdComponentDef({
    required this.name,
    required this.params,
    required this.body,
    this.library,
    this.libraryVersion,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'params': params,
        'body': body.toJson(),
        if (library != null) 'library': library,
        if (libraryVersion != null) 'libraryVersion': libraryVersion,
      };

  static NdComponentDef fromJson(Map<String, Object?> json) => NdComponentDef(
        name: json['name'] as String,
        params: (json['params'] as List).cast<String>(),
        body: NdNode.fromJson((json['body'] as Map).cast<String, Object?>()),
        library: json['library'] as String?,
        libraryVersion: json['libraryVersion'] as String?,
      );
}
