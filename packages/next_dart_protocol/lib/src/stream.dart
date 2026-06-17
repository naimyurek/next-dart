// packages/next_dart_protocol/lib/src/stream.dart
//
// UI streaming convention (Phase 2, F5) — a thin layer over the existing
// envelope machinery. A "frame" is an ordinary signed + encrypted Envelope; the
// frame KIND rides in [EnvelopeContent.data]. No crypto or envelope changes.
//
//   Initial frame: data = {'kind': 'initial'}, root = page tree (may hold Slots).
//   Patch  frame: data = {'kind': 'patch', 'slot': '<id>'}, root = replacement.
//
// A Slot is the convention node:
//   NdNode(type: 'Slot', props: {'slot': '<id>'}, children: [<fallback>])

/// The node `type` that marks a streaming placeholder slot.
const String kSlotType = 'Slot';

/// `data` key naming the frame kind.
const String kFrameKind = 'kind';

/// Frame kind value for the initial page tree.
const String kFrameInitial = 'initial';

/// Frame kind value for a slot-replacement patch.
const String kFramePatch = 'patch';

/// `data`/`props` key naming a slot id.
const String kFrameSlot = 'slot';

/// Frame [EnvelopeContent.data] for the initial page tree.
Map<String, Object?> initialFrameData() => {kFrameKind: kFrameInitial};

/// Frame [EnvelopeContent.data] for a patch replacing the slot [slotId].
Map<String, Object?> patchFrameData(String slotId) =>
    {kFrameKind: kFramePatch, kFrameSlot: slotId};

/// The frame kind in [data], or null if absent / not a String.
String? frameKind(Map<Object?, Object?> data) {
  final v = data[kFrameKind];
  return v is String ? v : null;
}

/// The slot id in [data], or null if absent / not a String.
String? frameSlot(Map<Object?, Object?> data) {
  final v = data[kFrameSlot];
  return v is String ? v : null;
}
