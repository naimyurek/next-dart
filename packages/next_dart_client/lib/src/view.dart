import 'package:flutter/widgets.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'renderer.dart';
import 'source.dart';

export 'source.dart' show ActionDispatcher, NextDartSource;

/// Fetches a route's tree, renders it via [renderer], and re-renders when an
/// action dispatched by the rendered UI returns a new tree.
class NextDartView extends StatefulWidget {
  final NextDartSource source;
  final String route;
  final NextDartRenderer renderer;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final Widget Function(BuildContext)? loadingBuilder;

  const NextDartView({
    super.key,
    required this.source,
    required this.route,
    required this.renderer,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<NextDartView> createState() => _NextDartViewState();
}

class _NextDartViewState extends State<NextDartView> {
  EnvelopeContent? _content;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.source.fetchPage(widget.route);
      if (mounted) setState(() => _content = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _dispatch(String action, Map<String, Object?> args) async {
    try {
      final c = await widget.source
          .dispatch(action, args, route: widget.route);
      if (mounted) setState(() => _content = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          _fallbackText('Error: $_error');
    }
    final content = _content;
    if (content == null) {
      return widget.loadingBuilder?.call(context) ??
          _fallbackText('Loading…');
    }
    return widget.renderer.render(context, content, _dispatch);
  }

  Widget _fallbackText(String s) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text(s)),
      );
}
