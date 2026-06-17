# Changelog

## 0.1.0

Initial public release.

- `NextClient` — HTTP client that performs the handshake, fetches, decrypts, and verifies `NextEnvelope` payloads
- `NextSession` — manages ephemeral session keys and automatic retry on key expiry
- `NextRenderer` abstract interface — plug in any Flutter render engine (rfw, basic, custom)
- Exponential back-off retry with configurable max attempts
- Depends on `next_dart_protocol`; no renderer is bundled (bring your own)
