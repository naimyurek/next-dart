# next-dart Phase 3 Implementation Plan

> Built on Phases 1–2. TDD-first, committed per feature, architecture invariant
> intact (`rfw` only in `next_dart_rfw`). Reference spec:
> `docs/superpowers/specs/2026-06-07-next-dart-design.md` (§9 security, §16/§17).

**Goal:** Deliver the Phase-3 roadmap — an X25519 ECDH handshake with session-key
rotation (replacing the provisioned symmetric key), ISR/advanced caching,
pub.dev release preparation (dry-run only — never publish without the user), and
multi-platform polish (CI + platform support).

**Order:** F8 ECDH handshake → F9 ISR/caching → F10 pub.dev prep → F11 CI/polish.

---

## F8 — X25519 ECDH handshake + session-key rotation (protocol + server + client)

**Clean layering (key insight):** the envelope's `encodeEnvelope`/`decodeEnvelope`
ALREADY take a `SecretKey` + `keyId`. F8 does NOT change envelope crypto. It adds a
handshake that *derives* a per-session `SecretKey` via ECDH (instead of provisioning
one), keyed by a rotating `keyId`. Server keeps a `keyId → sessionKey` store.

**Design:**
- Protocol `lib/src/handshake.dart`: helpers over `package:cryptography`:
  - `X25519` for ECDH; `Hkdf(hmac: Hmac.sha256())` to derive a 32-byte session key from the shared secret (+ a fixed info/salt).
  - `HandshakeRequest { x25519PublicKey }`, `HandshakeResponse { x25519PublicKey, keyId, expiresAtMillis, signature }`. The server signs (Ed25519, its long-term key) the canonical bytes of `(serverEphemeralPub ‖ clientEphemeralPub ‖ keyId ‖ expiresAt)` so the client can AUTHENTICATE the server's ephemeral key and defeat MITM. Client verifies with the pinned Ed25519 public key.
  - `deriveSessionKey(localPrivate, remotePublic)` → `SecretKey` (X25519 → HKDF).
- Server `lib/src/session.dart` + `app.dart`: a `SessionStore` mapping `keyId → (SecretKey, expiresAt)`; `POST /__handshake` runs the agreement, stores the session key under a fresh `keyId` (monotonic + expiry), returns the signed response. `_envelopeFor` uses the session key for that request's `keyId` (the client sends its `keyId` on `/__page`/`/__action`; if missing/expired → `UpdateRequired`-style "re-handshake" signal). Expired sessions are pruned. `bumpContent`/rotation can force a new `keyId`.
- Client `lib/src/client.dart`: `Future<void> handshake()` generates an ephemeral X25519 pair, POSTs `/__handshake`, verifies the signed response, derives + stores the session `SecretKey` + `keyId`; `fetchPage`/`dispatch` lazily handshake if no live session and attach the `keyId`; on a "re-handshake" response they transparently re-handshake once and retry. A `provisionedKey` constructor stays for back-compat/tests.

**Tests:** ECDH round-trip (both sides derive the same key); a tampered/forged server ephemeral key fails Ed25519 verification → handshake rejected; an envelope encrypted under a session key decrypts after handshake; expired `keyId` → re-handshake path; back-compat provisioned-key path unchanged. Adversarial: MITM swapping the server ephemeral key is detected.

**Acceptance:** new handshake tests pass; existing envelope/server/client tests green; the example can still run (provisioned-key path remains for the demo, or the demo upgrades to handshake — keep the demo working).

---

## F9 — ISR / advanced caching (server + client)

**Goal:** Cache rendered envelopes and avoid recompute; let clients skip unchanged content.

**Design:**
- Server: a per-route cache in `NextDartApp` keyed by `(route, params)` storing the last built body + its `contentVersion`, with **revalidation** modes: `RevalidatePolicy { never | afterSeconds(n) | onDemand }`. `app.page(pattern, builder, revalidate: ...)`. A page response carries the `contentVersion`; an unchanged cached body is reused until its TTL elapses or `app.revalidate(route)` is called (ISR-style on-demand). Cache stores the *built tree* (pre-encrypt), so it composes with F8 per-session encryption (encrypt per request, cache the plaintext body).
- Client: `NextDartClient` sends an `If-None-Match`-style `knownVersion` (the `contentVersion` it last rendered) on `/__page`; the server replies `304`-style "not modified" (a tiny signed frame) when the version matches, and the client keeps its cached tree. A small client-side `Map<route, EnvelopeContent>` cache backs this.

**Tests:** server reuses a cached body within TTL (builder invoked once); `revalidate(route)` forces a rebuild; client `knownVersion` match → not-modified path (builder/encrypt skipped or a not-modified marker returned) and the client keeps its tree; cache is per-(route,params).

**Acceptance:** caching tests pass; existing tests green.

---

## F10 — pub.dev release preparation (all packages) — DRY-RUN ONLY

**Goal:** Make every publishable package pub.dev-ready and prove it with `dart pub publish --dry-run`. **Do NOT actually publish** — publishing is irreversible and requires the user's explicit go-ahead.

**Design (per package: protocol, server, client, rfw, basic, cli):**
- Real `description` (60–180 chars), `repository`/`homepage`/`issue_tracker` pointing at the GitHub repo, `topics`. Remove `publish_to: none` from the packages intended for pub.dev (keep it on the example apps).
- A `CHANGELOG.md` (0.1.0 entry) and a per-package `LICENSE` (or a top-level reference) — pub.dev wants a LICENSE in each package; add an MIT `LICENSE` file per package (or a license link). 
- A short per-package `README.md`.
- Resolve any path-only dependencies for publish: document that inter-package deps need version constraints for a real publish (for the dry-run, hosted-vs-path may warn — capture and document the exact remaining steps).
- Run `dart pub publish --dry-run` in each and capture output; fix what's fixable; document anything that genuinely requires the user (e.g. first-time package-name claim on pub.dev).

**Acceptance:** each package's `--dry-run` reports as close to clean as possible; a `docs/PUBLISHING.md` records the exact remaining manual `dart pub publish` steps and the order (protocol first, then dependents). **No package is actually published in this phase.**

---

## F11 — Multi-platform polish + CI

**Goal:** Confidence the project builds/tests across platforms, and automated CI.

**Design:**
- `.github/workflows/ci.yml`: on push/PR, set up Dart + Flutter, run `dart test` in the pure-Dart packages and `flutter test` in the Flutter packages (matrix or sequential), and `dart analyze` (tolerant of the known Windows-only shutdown quirk — CI runs on Linux where it's clean). 
- README badges (CI status, license).
- Ensure the example app declares the platforms it supports; document running on web/desktop/mobile. Add a brief `docs/PLATFORMS.md` if useful.
- A root `dart pub get` helper / melos-free dev note documenting how to run all suites.

**Acceptance:** CI workflow is valid YAML and runs the suites; README shows badges; docs updated. Then update the spec to mark Phase 3 delivered.

---

## Done criteria for Phase 3
All suites green; rfw-isolation verified; each feature committed; branch merged to
`main` and pushed; spec roadmap marks Phases 1–3 delivered; `docs/PUBLISHING.md`
lists the exact (user-run) pub.dev steps. Publishing itself is left to the user.
