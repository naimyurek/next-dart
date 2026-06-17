# next-dart

[![CI](https://github.com/naimyurek/next-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/naimyurek/next-dart/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Server-Driven UI for Flutter, modeled on Next.js. A pure-Dart backend defines your
app's UI and behavior and serves it as an **encrypted, signed, versioned** neutral
declarative tree. The Flutter client renders it through a **pluggable engine**
(rfw adapter by default). Change the backend → the app updates with no store release.
Only a genuinely new *native* widget requires a client update. **No executable code is
ever shipped to the client.**

## Packages
| Package | What it is |
|---|---|
| `next_dart_protocol` | Pure Dart. Neutral tree, crypto envelope, versioning. |
| `next_dart_server` | Pure Dart. Authoring DSL + HTTP endpoints. |
| `next_dart_client` | Flutter core. Fetch/verify/decrypt + renderer interface. No rfw. |
| `next_dart_rfw` | Flutter. rfw-backed renderer (the only rfw dependency). |
| `next_dart_basic` | Flutter. Dependency-free reference renderer (no rfw). |
| `next_dart_cli` | Pure Dart. `next_dart` CLI — `new` / `dev` / `doctor`. |

## Try the example

A runnable counter + composite-component demo lives in
[`examples/counter_app`](examples/counter_app/). See its README for run steps —
the short version: start `examples/counter_app/server` with `dart run bin/server.dart`,
then `flutter run` in `examples/counter_app/app`.

## Status
Phase 1 (MVP), Phase 2, and Phase 3 delivered. See the design spec
(`docs/superpowers/specs/2026-06-07-next-dart-design.md`) and the
Phase 3 plan (`docs/superpowers/plans/2026-06-18-next-dart-phase3.md`).
Phase 3 adds: X25519 ECDH handshake with session-key rotation, ISR/advanced
caching, pub.dev release preparation, and multi-platform CI.

## Development

### Running tests locally

Pure-Dart packages use `dart test`; Flutter packages use `flutter test`.
Run each from the repo root:

```bash
# Pure-Dart packages
for pkg in packages/next_dart_protocol packages/next_dart_server packages/next_dart_cli; do
  dart pub get --directory "$pkg"
  dart test "$pkg"
done

# Flutter packages
for pkg in packages/next_dart_client packages/next_dart_rfw packages/next_dart_basic; do
  flutter pub get --directory "$pkg"
  flutter test "$pkg"
done

# Example app
flutter pub get --directory examples/counter_app/app
flutter test    examples/counter_app/app
```

### Static analysis

```bash
dart analyze packages/next_dart_protocol
dart analyze packages/next_dart_server
dart analyze packages/next_dart_cli
flutter analyze packages/next_dart_client
flutter analyze packages/next_dart_rfw
flutter analyze packages/next_dart_basic
```

> **Windows note:** `dart analyze` on Windows can exit with a non-zero
> code due to a Dart SDK analyzer shutdown crash that is unrelated to
> actual code issues. This is a known OS-level quirk. CI runs analyze
> on Ubuntu (Linux), where it gates on real errors while treating style
> infos/warnings as non-blocking (tests are the hard gate). On Windows,
> prefer running `dart test` to verify correctness; skip `dart analyze`
> in local scripts or ignore the shutdown exit code.

### Running the example

See [`examples/counter_app/README.md`](examples/counter_app/README.md)
for the full walkthrough. Short version:

```bash
# Terminal 1 — backend
cd examples/counter_app/server
dart pub get
dart run bin/server.dart

# Terminal 2 — Flutter app
cd examples/counter_app/app
flutter pub get
flutter run -d chrome          # or -d windows, -d android, etc.
```

### Platform support

See [`docs/PLATFORMS.md`](docs/PLATFORMS.md) for a full breakdown of
which packages run on which platforms and how to add new Flutter targets.
