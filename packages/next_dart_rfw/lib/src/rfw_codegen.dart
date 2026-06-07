// packages/next_dart_rfw/lib/src/rfw_codegen.dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

const String kCatalogImport = 'catalog';

/// Generate an rfw remote-widget-library text from decoded protocol content.
String generateRfwText(EnvelopeContent content) {
  final buf = StringBuffer()..writeln('import $kCatalogImport;');
  for (final c in content.components) {
    buf.writeln('widget ${c.name} = ${_node(c.body)};');
  }
  buf.writeln('widget root = ${_node(content.root)};');
  return buf.toString();
}

String _node(NdNode n) {
  final args = <String>[];
  // Single-child widgets use `child:`; Column uses `children:`.
  if (n.type == 'Column') {
    args.add('children: [${n.children.map(_node).join(', ')}]');
  } else if (n.children.length == 1) {
    args.add('child: ${_node(n.children.single)}');
  }
  n.props.forEach((k, v) => args.add('$k: ${_value(v)}'));
  n.events.forEach((k, ref) => args.add('$k: ${_event(ref)}'));
  return '${n.type}(${args.join(', ')})';
}

String _event(NdActionRef ref) {
  final pairs = ref.args.entries.map((e) => '${e.key}: ${_value(e.value)}').join(', ');
  return 'event "${ref.action}" { $pairs }';
}

String _value(Object? v) {
  if (v is NdArgRef) return 'args.${v.name}';
  if (v is num || v is bool) return '$v';
  return _string('$v');
}

String _string(String s) {
  final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}
