import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Called when a rendered widget fires an action. Implementations post to the
/// server (server action) or run a pre-bundled client-local action.
typedef NdActionDispatcher = Future<void> Function(
    String action, Map<String, Object?> args);

/// The data source a [NextDartView] reads from. Implemented by [NextDartClient];
/// fakeable in tests.
abstract class NextDartSource {
  Future<EnvelopeContent> fetchPage(String route);
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
      {required String route});

  /// Stream a route's frames: the initial frame (page tree, possibly holding
  /// `Slot` nodes) followed by a patch frame per slot as async work resolves.
  /// Consumed by [NextDartStreamView]. The default throws — only sources that
  /// support UI streaming (e.g. [NextDartClient]) override it.
  Stream<EnvelopeContent> streamPage(String route) =>
      throw UnsupportedError('this source does not support streamPage');

  /// Subscribe to dev hot-reload events from the server's `/__events` SSE
  /// endpoint. Yields `'reload'` for each reload push. The default returns
  /// [Stream.empty] so existing fakes and non-dev sources are unaffected.
  Stream<String> events() => Stream.empty();
}
