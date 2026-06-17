import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'patch.dart';
import 'renderer.dart';
import 'source.dart';

/// Streaming counterpart to `NextDartView` (Next.js Suspense analogue).
///
/// Subscribes to [NextDartSource.streamPage], renders the **initial** frame's
/// tree immediately (slots show their fallbacks), then applies each **patch**
/// frame by swapping the matching `Slot`'s content via [applyPatch] and
/// re-rendering through [renderer].
///
/// Frames that are neither an initial nor a recognised patch are ignored. A
/// stream error is surfaced through [errorBuilder] (default: a plain message).
class NextDartStreamView extends StatefulWidget {
  final NextDartSource source;
  final String route;
  final NextDartRenderer renderer;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final Widget Function(BuildContext)? loadingBuilder;

  const NextDartStreamView({
    super.key,
    required this.source,
    required this.route,
    required this.renderer,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<NextDartStreamView> createState() => _NextDartStreamViewState();
}

class _NextDartStreamViewState extends State<NextDartStreamView> {
  EnvelopeContent? _content;
  Object? _error;
  StreamSubscription<EnvelopeContent>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sub = widget.source.streamPage(widget.route).listen(
          _onFrame,
          onError: (Object e) {
            if (mounted) setState(() => _error = e);
          },
        );
  }

  void _onFrame(EnvelopeContent frame) {
    if (!mounted) return;
    final kind = frameKind(frame.data);
    if (kind == kFramePatch) {
      final slot = frameSlot(frame.data);
      final current = _content;
      // A patch with no current tree or unknown slot id is ignored.
      if (slot == null || current == null) return;
      setState(() => _content = applyPatch(current, slot, frame.root));
    } else {
      // Initial frame (or any non-patch frame) establishes the tree.
      setState(() => _content = frame);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!);
      }
      return _fallbackText('Error: $_error');
    }
    final content = _content;
    if (content == null) {
      return widget.loadingBuilder?.call(context) ?? _fallbackText('Loading…');
    }
    // Streaming view has no server actions of its own; dispatch is a no-op.
    return widget.renderer.render(context, content, (_, __) async {});
  }

  Widget _fallbackText(String s) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text(s)),
      );
}
