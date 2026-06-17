import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Apply a streaming patch: find the `Slot` node whose id is [slotId] in
/// [current]'s tree and replace its children with `[replacement]`, returning a
/// new [EnvelopeContent]. Components and data are carried through unchanged.
///
/// Pure and immutable — the input tree is not mutated. If no slot matches, the
/// tree is returned structurally unchanged.
EnvelopeContent applyPatch(
    EnvelopeContent current, String slotId, NdNode replacement) {
  return EnvelopeContent(
    root: _replace(current.root, slotId, replacement),
    components: current.components,
    data: current.data,
  );
}

NdNode _replace(NdNode node, String slotId, NdNode replacement) {
  if (node.type == kSlotType && node.props[kFrameSlot] == slotId) {
    return NdNode(
      type: node.type,
      props: node.props,
      children: [replacement],
      events: node.events,
    );
  }
  if (node.children.isEmpty) return node;
  return NdNode(
    type: node.type,
    props: node.props,
    children: node.children.map((c) => _replace(c, slotId, replacement)).toList(),
    events: node.events,
  );
}
