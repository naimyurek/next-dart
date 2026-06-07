# next-dart — Design Specification (Phase 1 / MVP)

- **Status:** Approved in brainstorming — 2026-06-07
- **Scope:** Phase 1 (MVP). Later phases are listed in the Roadmap and are explicitly out of scope for the first implementation plan.
- **Working directory:** `D:\dev\flutter-ssr`

---

## 1. Summary

next-dart is a **Server-Driven UI (SDUI)** framework for Flutter, modeled on the mental model of **Next.js**. A pure-Dart backend defines an application's UI and behavior and serves it to a Flutter client as an **encrypted, signed, versioned** payload that describes a **declarative widget tree**. The client renders that tree through a **pluggable render engine**.

Changing the backend updates the running app instantly, with **no app-store release**. Only the introduction of a genuinely **new native widget/capability** requires a client update. **No executable code is ever shipped to the client** — the UI is fully declarative and interpreted, which keeps the approach App Store / Play Store safe.

## 2. Goals

1. **Backend-driven UI** — change the server, the app updates; no store submission for content, layout, flow, or logic changes.
2. **Client update only for new native widgets** — everything else is server-driven.
3. **Store-safe** — no downloaded/executed code; declarative UI only.
4. **Secure by default** — TLS + certificate pinning, signed payloads (authenticity/integrity), encrypted payloads (confidentiality), and a versioned protocol.
5. **AI-friendly** — declarative pure-Dart authoring, a published JSON Schema for the wire tree, and a concise agent guide so an AI can author a working page with minimal context.
6. **Render-engine–agnostic core** — `rfw` is the *default adapter*, never a core dependency; the engine is fully swappable.

## 3. Non-goals (Phase 1)

- Shipping or executing arbitrary Dart or any scripting language on the client.
- File-based routing, UI streaming, hot-reload, and a CLI (Phase 2).
- ECDH handshake and key rotation, ISR/advanced caching, pub.dev release, multi-platform polish (Phase 3).
- A dependency-free built-in reference renderer (possible Phase 2; the rfw adapter is sufficient for the MVP).

## 4. Conceptual model — the Next.js mapping

next-dart deliberately reuses Next.js's core insight: the server sends a **serialized description of a rendered component tree** (Next.js's RSC payload), while the client holds the **component implementations**. The one structural difference: in next-dart the interactive widgets are **pre-bundled in the client binary** (not downloaded as code), because we never ship executable code.

| Next.js | next-dart (interpreted Flutter UI) |
|---|---|
| File-based routing | Server route → page builder (explicit routing in Phase 1; file-based in Phase 2) |
| Server Component (no JS shipped) | Server builds a **declarative widget tree** (data); only the *description* travels |
| RSC payload | **Encrypted + signed + versioned** envelope (rfw-binary default, JSON debug) |
| Client Component (JS downloaded) | **Pre-bundled native widget catalog** in the app binary — never downloaded |
| Server Action (auto RPC) | **Action system**: `onPressed: action('inc')` → event → server Dart handler → new tree/patch |
| Streaming / Suspense | Partial tree + placeholders (Phase 2) |
| Hydration / fast paint | Client caches the last tree, shows it instantly, then refreshes |

## 5. Architecture

Monorepo with **four packages** (one optional). The decoupling of the render engine from the core is a hard requirement.

```
next-dart/
├── packages/
│   ├── next_dart_protocol/   # Pure Dart. Wire types, schema, versioning, crypto. NO Flutter, NO rfw.
│   ├── next_dart_server/     # Pure Dart. Authoring DSL → serialize → sign → encrypt → serve (shelf). NO rfw.
│   ├── next_dart_client/     # Flutter CORE. fetch → verify → decrypt → dispatch → cache.
│   │                         #   Defines NextDartRenderer + WidgetCatalog. *** NO rfw dependency ***
│   └── next_dart_rfw/        # OPTIONAL adapter. Implements NextDartRenderer using rfw.
│                             #   The ONLY package that depends on rfw.
├── examples/
│   └── counter_app/          # Dart server + Flutter app using next_dart_client + next_dart_rfw.
├── docs/                     # Architecture, protocol schema, AI_GUIDE.md.
└── README.md
```

**Dependency rules (enforced):**

| Package | May depend on | Must NOT depend on |
|---|---|---|
| `next_dart_protocol` | `cryptography` | Flutter, rfw, server |
| `next_dart_server` | `next_dart_protocol`, `shelf` | Flutter, rfw |
| `next_dart_client` (core) | `next_dart_protocol`, Flutter | **rfw**, any concrete engine |
| `next_dart_rfw` | `next_dart_client`, `rfw`, Flutter | server |

**Consequence:** if `rfw` were deleted entirely, the protocol, server, and client core still build and run — you simply plug in another renderer.

**Why these boundaries:** `protocol` is shared and must stay Flutter-free so the server (a plain Dart process) can use it. Each package has one clear purpose and is independently testable.

## 6. Wire protocol (`next_dart_protocol`)

A **versioned envelope** carries the UI payload:

```
Envelope {
  protocolVersion   : semver    // wire/protocol compatibility
  contentVersion    : int|hash  // which version of this page's UI
  minClientVersion  : semver    // server requires client >= this
  route             : string    // e.g. "/dashboard"
  payloadFormat     : enum { rfwBinary, json }   // default rfwBinary; json = debug / AI-readable
  payload           : bytes     // declarative widget tree (encrypted)
  data              : bytes     // initial state / DynamicContent (encrypted)
  alg               : enum      // signature + AEAD algorithm identifiers
  keyId             : string    // which signing/encryption key
  nonce             : bytes     // AEAD nonce
  signature         : bytes     // Ed25519 over the canonical serialization of all fields above
}
```

- **Authoring → wire:** the developer writes Dart on the server using a builder DSL; the framework **lowers** that tree to the rfw format. The default wire encoding is rfw **binary** (compact). A **`json`** mode produces a human/AI-readable tree for debugging and AI inspection.
- **Versioning & negotiation:** the client sends its `protocolVersion` and catalog capabilities; the server responds with a payload it knows the client can render, or a typed `UpdateRequired` envelope. `minClientVersion` lets the server refuse clients too old to render a page **cleanly**, instead of crashing.
- **Canonicalization:** signing operates over a deterministic, canonical byte serialization of the envelope (stable field order) so signatures are reproducible across server/client.

## 7. Server authoring DSL (`next_dart_server`)

A **page** is a Dart unit (function or class) that returns a declarative tree built from `Nd*` constructs and serves as the "Server Component."

```dart
// pages/counter.dart  (illustrative — final names settled in the plan)
NdNode counterPage(NdContext ctx) {
  final count = ctx.state.int('count', 0);
  return NdColumn(children: [
    NdText('Count: $count'),
    NdButton(
      label: 'Increment',
      onPressed: action('inc'),           // server action reference
    ),
  ]);
}

// actions
void inc(ActionContext ctx) {
  ctx.state.update('count', (n) => (n as int) + 1);
  ctx.rerender();                          // returns a patch or a fresh tree
}
```

The server exposes two HTTP endpoints (via `shelf`):

- `GET /__page?route=/counter` → returns a signed+encrypted `Envelope`.
- `POST /__action` → `{ actionId, args, stateToken }` (signed) → runs the handler → returns an `Envelope` (full tree) or a `Patch`.

## 8. Security model ("closed to outside interference")

Four layers; the MVP keeps key management simple with a clean upgrade path.

| Layer | Mechanism | Defends against | Phase 1 | Later |
|---|---|---|---|---|
| Transport | HTTPS/TLS + **certificate pinning** in the client | Network MITM, rogue CAs | Pinned cert/public-key | — |
| Authenticity/Integrity | **Ed25519** signature over the canonical envelope; client verifies with a pinned public key | Payload tampering / UI injection | ✅ | — |
| Confidentiality | **AES-256-GCM** (AEAD) over `payload` + `data` | Eavesdropping; defense-in-depth if TLS is broken | Provisioned symmetric key + per-message nonce | **X25519 (ECDH) handshake + key rotation** |
| Version safety | `minClientVersion` + capability negotiation | Rendering a widget the client lacks → crash | ✅ typed `UpdateRequired` | — |

**Core guarantee:** signature verification is the anti-tamper foundation — even if TLS is defeated, an attacker cannot forge a valid UI envelope without the server's signing key. Pinning blocks MITM; AEAD provides confidentiality; versioning prevents render-time crashes.

> MVP simplification: signing/encryption keys are **provisioned** (signing public key + a symmetric key pinned/provisioned in the client build). The envelope already carries `keyId`/`alg`, so moving to an ECDH handshake and key rotation in Phase 3 is additive, not a rewrite.

## 9. Action & data flow

**Render cycle:**
1. Client requests a route → server builds the tree → signs + encrypts → returns the envelope.
2. Client verifies the signature → decrypts → decodes → renders via the active `NextDartRenderer`.

**Action cycle (the "Server Actions" equivalent):**
1. A widget's `onPressed` carries `action('removeItem', {id: 42})`.
2. Client `POST /__action` with the action id, args, and a signed state token.
3. Server runs the Dart handler (DB / business logic) → returns either a **full new tree** or a **patch / new DynamicContent** (state update without re-sending the whole tree).
4. Client applies it; the UI updates.

**Two interactivity tiers** (mirroring Next.js server vs client components):
- **Server actions** — round-trip to the backend for data and mutations.
- **Client-local actions** — predefined, pre-bundled behaviors (toggle, navigate, form-field update) that run *without* a round-trip for snappy UX. They live in the client catalog.

The developer never writes a manual REST API; the action system is the RPC.

## 10. Pluggable render engine

```dart
abstract class NextDartRenderer {
  Widget render(BuildContext context, DecodedPayload payload, ActionDispatcher dispatch);
}
```

- **Core (`next_dart_client`)** ships only the abstraction and plumbing: `NextDartRenderer`, `WidgetCatalog`, decode, dispatch, cache. **No concrete engine lives in core.**
- **`next_dart_rfw`** is the official rfw-backed implementation (separate, opt-in package). The rfw dependency exists **only here**.
- **Customize without forking:** apps register custom native widgets through the `WidgetCatalog` API (mapped onto rfw's local widget libraries in the adapter).
- **Replace entirely:** implement `NextDartRenderer` and plug it in — core untouched.
- **Future option:** a dependency-free reference renderer (`next_dart_basic`) so core users are never forced onto rfw (Phase 2, YAGNI for MVP).

## 11. AI-friendliness

- **Pure-Dart declarative DSL** with predictable, well-named constructs — the format LLMs know best.
- **Published JSON Schema** for the `json` wire tree → an AI can generate and validate UI as plain JSON.
- **Single-file page convention** + concise, example-first docs → minimal context to produce a working page.
- **`docs/AI_GUIDE.md`** — a short "how to author a next-dart page" document an agent can read and immediately be productive with.

## 12. Example app (proof of the full loop)

A **counter / mini-login** example: a Dart server defines the page; the Flutter client renders it; tapping a button hits a server action; the server returns updated UI — all signed, encrypted, and versioned end-to-end. The README demonstrates: *change the server, restart it, and the app updates with no client rebuild.*

## 13. Testing strategy

- **`next_dart_protocol`** — encode/decode round-trip; signature verification (tamper → reject); encrypt/decrypt; version negotiation.
- **`next_dart_server`** — DSL lowers to the expected payload; action dispatch returns the expected tree/patch.
- **`next_dart_client`** — a known payload renders the expected widgets; a tampered payload is rejected; an action round-trip updates the UI (against a fake server).
- **`next_dart_rfw`** — adapter renders a representative tree to the expected rfw widgets.
- **Example integration test** — local server + client through one full action loop.

## 14. Tech choices & dependencies

| Concern | Choice | Notes |
|---|---|---|
| Server HTTP | `shelf` | Minimal, standard, low-dependency. `dart_frog` considered for file-based routing in Phase 2. |
| Crypto | `cryptography` | Pure-Dart Ed25519 / X25519 / AES-GCM. |
| Render (adapter only) | `rfw` | Official Remote Flutter Widgets; isolated in `next_dart_rfw`. |
| Monorepo tooling | `melos` (optional) | Can start without it. |

Exact versions are verified against pub.dev during the planning step.

## 15. Open items (to confirm before pushing)

1. Target **GitHub account/org** for the public repo.
2. **pub.dev name** availability for `next_dart_*`; whether to publish now or in a later phase.
3. Spec/docs **language** (written in English by default for the public, AI-friendly repo).

## 16. Roadmap

- **Phase 1 (this spec):** end-to-end core loop — protocol + security, server DSL + actions, client core + rfw adapter, counter/login example, tests, AI guide.
- **Phase 2:** file-based routing, UI streaming, hot-reload, CLI, optional dependency-free reference renderer.
- **Phase 3:** ECDH handshake + key rotation, ISR/advanced caching, pub.dev release, multi-platform polish.
