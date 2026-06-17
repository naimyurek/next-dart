# next-dart

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
Phase 1 (MVP) and Phase 2 delivered. See the design spec
(`docs/superpowers/specs/2026-06-07-next-dart-design.md`) and the
Phase 2 plan (`docs/superpowers/plans/2026-06-18-next-dart-phase2.md`).
Phase 2 adds: routing with params, named/versioned component libraries, a
compact `ndBinary` codec, a dependency-free renderer, UI streaming, dev
hot-reload, and a CLI.
