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

## Status
Phase 1 (MVP). See `docs/superpowers/specs/2026-06-07-next-dart-design.md`.
