import 'package:flutter/widgets.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'source.dart';

/// A render engine maps decoded protocol content to a Flutter widget.
/// The core ships only this interface — concrete engines (e.g. rfw) are separate
/// packages, so the core never depends on any specific renderer.
abstract class NextDartRenderer {
  Widget render(
    BuildContext context,
    EnvelopeContent content,
    NdActionDispatcher dispatch,
  );
}
