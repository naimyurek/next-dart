/// Pure helper — builds the argument list for `dart run bin/server.dart`.
/// No process spawning here; testable without side effects.

/// Returns the arguments to pass to `dart` when starting the dev server.
///
/// Example:
/// ```dart
/// // dart run --define=PORT=8080 bin/server.dart
/// devProcessArgs(dir: '.', port: 8080);
/// ```
List<String> devProcessArgs({required String dir, required int port}) {
  return [
    'run',
    '--define=PORT=$port',
    'bin/server.dart',
  ];
}
