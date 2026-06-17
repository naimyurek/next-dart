# Changelog

## 0.1.0

Initial public release.

- `BasicRenderer` — implements `NextRenderer` using plain Flutter widgets, no rfw dependency
- Minimal dependency footprint — only `flutter` SDK, `next_dart_client`, and `next_dart_protocol`
- Supports the core `NextNode` widget types: `Text`, `Column`, `Row`, `Container`, `Padding`, `Button`
- Easy to extend with custom node type handlers via a simple registry
- Good starting point before adopting the rfw engine
