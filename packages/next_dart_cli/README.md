# next_dart_cli

The CLI tool for [next-dart](https://github.com/naimyurek/next-dart) — a server-driven UI framework for Flutter.

Scaffold new projects, run the dev server, and check your environment — all from the command line.

## Install

```sh
dart pub global activate next_dart_cli
```

## Usage

```sh
# Scaffold a new project (creates server/ and app/ directories)
next_dart new my_app

# Scaffold into a specific directory
next_dart new my_app --output /path/to/output

# Start the dev server (shells out to `dart run bin/server.dart` in the server directory)
next_dart dev

# Point at a specific server directory and port
next_dart dev --dir path/to/server --port 9090

# Check that Dart/Flutter are on PATH and the workspace looks like a next-dart project
next_dart doctor
```

## Commands

### `next_dart new <name> [--output <dir>]`

Scaffolds a starter next-dart workspace containing a Shelf-based server package
and a Flutter app package. If `--output` is omitted the project is created in a
directory named after `<name>`.

### `next_dart dev [--dir <serverDir>] [--port <n>]`

Starts the project's dev server by running `dart run --define=PORT=<n> bin/server.dart`
inside `<serverDir>` (defaults to `.`). The Dart VM handles the process; next_dart_cli
does not itself implement hot-reload.

### `next_dart doctor`

Checks that `dart` and `flutter` are available on PATH, and that the expected
next-dart package directories exist in the current workspace.

## Links

- [Repository](https://github.com/naimyurek/next-dart)
- [Issue tracker](https://github.com/naimyurek/next-dart/issues)
- [Changelog](CHANGELOG.md)
