# Changelog

## 0.1.0

Initial public release.

- `NextApp` builder with a fluent authoring DSL for composing server-driven UI trees
- `NextRouter` — a `package:shelf` router that serves signed/encrypted `NextEnvelope` responses
- Session-key handshake endpoint (`/handshake`) for client key exchange
- Built-in support for typed route handlers and middleware hooks
- Depends on `next_dart_protocol` for the neutral tree and envelope format
