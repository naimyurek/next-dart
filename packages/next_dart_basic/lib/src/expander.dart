// packages/next_dart_basic/lib/src/expander.dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Resolves a [node] whose type matches a composite component name in [byName].
///
/// If the node is a primitive (type not in [byName]), it is returned unchanged
/// after recursively expanding its children.
///
/// For a composite node:
///  1. Grab the component definition from [byName].
///  2. Build a substitution map from the definition's param names → the
///     instantiation's prop values.
///  3. Deep-copy the definition body, replacing every [NdArgRef] with the
///     resolved value (including inside event action args).
///  4. Recursively expand the resulting node in case the body itself uses
///     other components.
NdNode expand(NdNode node, Map<String, NdComponentDef> byName) {
  final def = byName[node.type];
  if (def == null) {
    // Primitive node — still recurse into children.
    return NdNode(
      type: node.type,
      props: node.props,
      children: node.children.map((c) => expand(c, byName)).toList(),
      events: node.events,
    );
  }

  // Build substitution map: param name → caller's prop value (or null).
  final subs = <String, Object?>{
    for (final param in def.params) param: node.props[param],
  };

  // Expand the body with substitutions, then recurse for nested composites.
  final expanded = _substituteNode(def.body, subs);
  return expand(expanded, byName);
}

/// Recursively substitutes [NdArgRef]s in a node's props, event args, and
/// children with values from [subs].
NdNode _substituteNode(NdNode node, Map<String, Object?> subs) {
  return NdNode(
    type: node.type,
    props: node.props.map((k, v) => MapEntry(k, _substituteValue(v, subs))),
    children: node.children.map((c) => _substituteNode(c, subs)).toList(),
    events: node.events.map(
      (k, ref) => MapEntry(
        k,
        NdActionRef(
          ref.action,
          ref.args.map((ak, av) => MapEntry(ak, _substituteValue(av, subs))),
        ),
      ),
    ),
  );
}

/// Replaces an [NdArgRef] with the corresponding value from [subs].
/// Other values pass through unchanged.
Object? _substituteValue(Object? value, Map<String, Object?> subs) {
  if (value is NdArgRef) {
    return subs.containsKey(value.name) ? subs[value.name] : value;
  }
  return value;
}
