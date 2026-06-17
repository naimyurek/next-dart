/// Pure scaffold generator — returns file contents as a map, no disk I/O.
/// relativePath → fileContents

/// Generate a minimal next-dart server project scaffold.
///
/// Returns a [Map] of relative file path → file contents.
/// The caller is responsible for writing these to disk.
Map<String, String> generateScaffold(String projectName) {
  return {
    'pubspec.yaml': _pubspec(projectName),
    'bin/server.dart': _binServer(projectName),
    'lib/app.dart': _libApp(projectName),
    'README.md': _readme(projectName),
  };
}

String _pubspec(String name) => '''
name: $name
description: A next-dart server-driven UI project.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.12.0

dependencies:
  # Until next_dart_server is published to pub.dev, use a path or git dependency:
  #   path: ../next_dart_server
  #   git: { url: https://github.com/naimyurek/next-dart, path: packages/next_dart_server }
  next_dart_server:
    path: ../../packages/next_dart_server
  next_dart_protocol:
    path: ../../packages/next_dart_protocol
  shelf: ^1.4.2
''';

String _binServer(String name) => '''
// bin/server.dart — entrypoint for $name
import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:next_dart_server/next_dart_server.dart';

Future<void> main() async {
  // NextDartApp.dev() uses ephemeral keys — for local development only.
  // Replace with the real constructor (signingKeyPair, secretKey, keyId)
  // before deploying to production.
  final app = await NextDartApp.dev();

  app.page('/', (ctx) => ndColumn([ndText('Hello from next-dart')]));

  final port =
      int.tryParse(const String.fromEnvironment('PORT', defaultValue: '8080'))
          ?? 8080;
  final server =
      await shelf_io.serve(app.handler, InternetAddress.loopbackIPv4, port);
  stdout.writeln('$name listening on http://\${server.address.host}:\${server.port}');
}
''';

String _libApp(String name) => '''
// lib/app.dart — application definition for $name
// This file is provided as an optional extraction point.
// The entrypoint (bin/server.dart) already creates and configures the app
// inline via NextDartApp.dev(). Move the setup here and call buildApp()
// from main() if you prefer the separation.
import 'package:next_dart_server/next_dart_server.dart';

/// Build and configure the $name application.
/// For development only — uses ephemeral keys via NextDartApp.dev().
Future<NextDartApp> buildApp() async {
  final app = await NextDartApp.dev();

  app.page('/', (ctx) {
    return ndColumn([
      ndText('Welcome to $name!'),
    ]);
  });

  return app;
}
''';

String _readme(String name) => '''
# $name

A server-driven UI project built with [next-dart](https://github.com/naimyurek/next-dart).

## Run

```bash
dart pub get
dart run bin/server.dart
```

The server listens on `http://127.0.0.1:8080` by default.
Override the port: `dart run --define=PORT=9000 bin/server.dart`.
''';
