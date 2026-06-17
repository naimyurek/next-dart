# Changelog

## 0.1.0

Initial public release.

- `RfwRenderer` — implements `NextRenderer` using Flutter's `package:rfw` (remote_flutter_widgets)
- Translates `NextNode` trees into rfw `RemoteWidget` declarations at runtime
- Full widget catalogue: `Text`, `Column`, `Row`, `Container`, `Padding`, `Button`, and more
- Hot-swap support — the widget tree updates without a full rebuild when the server pushes a new tree
- Depends on `next_dart_client` and `next_dart_protocol`
