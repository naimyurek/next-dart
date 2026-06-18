# Changelog

## 0.1.0

Initial public release.

- `next_dart new <name> [--output <dir>]` — scaffolds a new next-dart project with a Shelf server package and a Flutter app package
- `next_dart dev [--dir <serverDir>] [--port <n>]` — starts the project's dev server by shelling out to `dart run bin/server.dart` in the server directory (no built-in hot-reload)
- `next_dart doctor` — checks that `dart` and `flutter` are on PATH and that the workspace contains the expected next-dart package directories
- Built on `package:args` with rich `--help` output for every sub-command
- Installable as a global Dart tool: `dart pub global activate next_dart_cli`
