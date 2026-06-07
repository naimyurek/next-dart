// packages/next_dart_protocol/lib/src/node.dart

/// A reference to a composite-component argument, used inside a component body.
/// Serializes as `{"$arg": "<name>"}`.
class NdArgRef {
  final String name;
  const NdArgRef(this.name);
  Map<String, Object?> toJson() => {r'$arg': name};
}

/// A reference from an event to a server/client action, with optional args.
class NdActionRef {
  final String action;
  final Map<String, Object?> args;
  const NdActionRef(this.action, [this.args = const {}]);

  Map<String, Object?> toJson() => {
        'action': action,
        if (args.isNotEmpty) 'args': args.map((k, v) => MapEntry(k, encodeValue(v))),
      };

  static NdActionRef fromJson(Map<String, Object?> json) => NdActionRef(
        json['action'] as String,
        ((json['args'] as Map?)?.cast<String, Object?>() ?? const {})
            .map((k, v) => MapEntry(k, decodeValue(v))),
      );
}

/// A node in the neutral declarative tree.
class NdNode {
  final String type;
  final Map<String, Object?> props;
  final List<NdNode> children;
  final Map<String, NdActionRef> events;

  const NdNode({
    required this.type,
    this.props = const {},
    this.children = const [],
    this.events = const {},
  });

  Map<String, Object?> toJson() => {
        'type': type,
        if (props.isNotEmpty)
          'props': props.map((k, v) => MapEntry(k, encodeValue(v))),
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
        if (events.isNotEmpty)
          'events': events.map((k, v) => MapEntry(k, v.toJson())),
      };

  static NdNode fromJson(Map<String, Object?> json) => NdNode(
        type: json['type'] as String,
        props: ((json['props'] as Map?)?.cast<String, Object?>() ?? const {})
            .map((k, v) => MapEntry(k, decodeValue(v))),
        children: ((json['children'] as List?) ?? const [])
            .map((e) => NdNode.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        events: ((json['events'] as Map?)?.cast<String, Object?>() ?? const {})
            .map((k, v) => MapEntry(
                k, NdActionRef.fromJson((v as Map).cast<String, Object?>()))),
      );
}

/// Encode a prop/arg value: passes through JSON scalars, lowers NdArgRef.
Object? encodeValue(Object? v) => v is NdArgRef ? v.toJson() : v;

/// Decode a prop/arg value: recognizes the `{"$arg": ...}` shape.
Object? decodeValue(Object? v) {
  if (v is Map && v.length == 1 && v.containsKey(r'$arg')) {
    return NdArgRef(v[r'$arg'] as String);
  }
  return v;
}
