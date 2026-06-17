// packages/next_dart_protocol/lib/src/envelope_body.dart
//
// Shared logical body shape for both JSON and binary wire codecs.
import 'component.dart';
import 'node.dart';

/// The decrypted logical body shared by all payload formats (JSON, ndBinary…).
///
/// Both [encodeTreeBinary]/[decodeTreeBinary] and the JSON path in
/// [encodeEnvelope]/[decodeEnvelope] operate on this type, guaranteeing that
/// the two codecs are interchangeable at the envelope level.
class EnvelopeBody {
  final NdNode root;
  final List<NdComponentDef> components;
  final Map<String, Object?> data;

  const EnvelopeBody({
    required this.root,
    this.components = const [],
    this.data = const {},
  });
}
