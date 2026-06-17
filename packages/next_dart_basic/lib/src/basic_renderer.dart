// packages/next_dart_basic/lib/src/basic_renderer.dart
import 'package:flutter/material.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'expander.dart';

/// A plain-Flutter render engine for next-dart — no rfw dependency.
///
/// Walks the neutral [NdNode] tree directly and returns standard Flutter
/// widgets. Composite components (whose type name matches an entry in
/// [EnvelopeContent.components]) are expanded client-side via [expand].
///
/// Unknown node types produce a visible red-bordered fallback widget rather
/// than throwing, so a single unrecognised node never crashes the whole page.
class BasicRenderer extends NextDartRenderer {
  @override
  Widget render(
    BuildContext context,
    EnvelopeContent content,
    NdActionDispatcher dispatch,
  ) {
    final byName = {
      for (final def in content.components) def.name: def,
    };

    return _renderNode(expand(content.root, byName), byName, dispatch);
  }

  Widget _renderNode(
    NdNode node,
    Map<String, NdComponentDef> byName,
    NdActionDispatcher dispatch,
  ) {
    switch (node.type) {
      case 'Text':
        return Text(node.props['text'] as String? ?? '');

      case 'Column':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: node.children
              .map((c) => _renderNode(c, byName, dispatch))
              .toList(),
        );

      case 'Card':
        final child = node.children.isNotEmpty
            ? _renderNode(node.children.first, byName, dispatch)
            : const SizedBox.shrink();
        return Card(child: child);

      case 'Padding':
        final amount = (node.props['all'] as num?)?.toDouble() ?? 0.0;
        final child = node.children.isNotEmpty
            ? _renderNode(node.children.first, byName, dispatch)
            : const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.all(amount),
          child: child,
        );

      case 'Image':
        final src = node.props['src'] as String? ?? '';
        return src.isEmpty ? const SizedBox.shrink() : Image.network(src);

      case 'Button':
        final label = node.props['label'] as String? ?? '';
        final actionRef = node.events['onPressed'];
        return ElevatedButton(
          onPressed: actionRef == null
              ? null
              : () => dispatch(actionRef.action, actionRef.args),
          child: Text(label),
        );

      default:
        // Visible fallback — never throws.
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFF0000)),
          ),
          padding: const EdgeInsets.all(4),
          child: Text('Unknown widget: ${node.type}'),
        );
    }
  }
}
