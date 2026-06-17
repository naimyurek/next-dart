# Changelog

## 0.1.0

Initial public release.

- Neutral declarative `NextNode` tree that is renderer-agnostic
- `NextEnvelope` with AEAD-encrypted, HMAC-signed payload and version tag
- `CryptoService` wrapping `package:cryptography` for key generation, signing, and verification
- `NextVersion` semver type with comparison helpers
- Zero Flutter dependencies — usable in pure-Dart servers and clients alike
