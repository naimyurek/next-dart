import 'package:flutter/widgets.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Called when a rendered widget fires an action. Implementations post to the
/// server (server action) or run a pre-bundled client-local action.
typedef ActionDispatcher = Future<void> Function(
    String action, Map<String, Object?> args);

/// A render engine maps decoded protocol content to a Flutter widget.
/// The core ships only this interface — concrete engines (e.g. rfw) are separate
/// packages, so the core never depends on any specific renderer.
abstract class NextDartRenderer {
  Widget render(
    BuildContext context,
    EnvelopeContent content,
    ActionDispatcher dispatch,
  );
}
