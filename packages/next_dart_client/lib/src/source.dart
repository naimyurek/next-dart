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
}
