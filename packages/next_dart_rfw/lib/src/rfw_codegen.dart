// packages/next_dart_rfw/lib/src/rfw_codegen.dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

const String kCatalogImport = 'catalog';

/// Generate an rfw remote-widget-library text from decoded protocol content.
String generateRfwText(EnvelopeContent content) {
  final buf = StringBuffer()..writeln('import $kCatalogImport;');
  for (final c in content.components) {
    buf.writeln('widget ${_ident(c.name)} = ${_node(c.body)};');
  }
  buf.writeln('widget root = ${_node(content.root)};');
  return buf.toString();
}

String _node(NdNode n) {
  final args = <String>[];
  // Single-child widgets use `child:`; Column uses `children:`.
  if (n.type == 'Column') {
    args.add('children: [${n.children.map(_node).join(', ')}]');
  } else if (n.children.isNotEmpty) {
    assert(n.children.length == 1,
        'next-dart: "${n.type}" has ${n.children.length} children but only single child: is supported (use Column)');
    args.add('child: ${_node(n.children.first)}');
  }
  n.props.forEach((k, v) => args.add('${_ident(k)}: ${_value(v)}'));
  n.events.forEach((k, ref) => args.add('${_ident(k)}: ${_event(ref)}'));
  return '${_ident(n.type)}(${args.join(', ')})';
}

String _event(NdActionRef ref) {
  final pairs =
      ref.args.entries.map((e) => '${_ident(e.key)}: ${_value(e.value)}').join(', ');
  return 'event ${_string(ref.action)} { $pairs }';
}

// MVP constraint: prop/arg values are scalars (String, num, bool) or NdArgRef.
// Richer value types (maps, lists) are out of scope and are excluded from the
// published JSON Schema. Extend this function if/when they are added.
String _value(Object? v) {
  if (v is NdArgRef) return 'args.${_ident(v.name)}';
  if (v is num || v is bool) return '$v';
  return _string('$v');
}

String _string(String s) {
  final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

/// Validates that [s] is a valid rfw identifier (used at identifier positions —
/// widget names, arg keys, arg.x selectors). Throws [StateError] if not.
String _ident(String s) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(s)) {
    throw StateError(
        'next-dart: "$s" is not a valid identifier for rfw codegen');
  }
  return s;
}
