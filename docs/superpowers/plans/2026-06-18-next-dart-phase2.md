# next-dart Phase 2 Implementation Plan

> Built on the Phase-1 MVP. Each feature is implemented TDD-first, committed
> independently, and must keep the architecture invariant intact: **`rfw` only
> ever appears in `next_dart_rfw`; protocol/server/client-core stay rfw-free.**
> Reference: `docs/superpowers/specs/2026-06-07-next-dart-design.md`.

**Goal:** Deliver the Phase-2 roadmap — routing with params, named/versioned component libraries, a compact `ndBinary` wire codec, a dependency-free reference renderer, UI streaming, dev hot-reload, and a CLI.

**Order (dependency-aware):** F1 ndBinary → F2 routing → F3 component libraries → F4 basic renderer → F5 streaming → F6 hot-reload → F7 CLI.

---

## F1 — Compact `ndBinary` wire codec (`next_dart_protocol`)

**Goal:** A compact binary encoding of the neutral tree, selectable as `payloadFormat: ndBinary`, as an alternative to JSON. Same logical content, smaller bytes.

**Design:**
- New `lib/src/binary_codec.dart`: `Uint8List encodeTreeBinary(EnvelopeBody body)` / `EnvelopeBody decodeTreeBinary(Uint8List)` using `dart:typed_data`. Tag-length-value scheme: varint-length-prefixed UTF-8 strings; a 1-byte type tag for values (0=string,1=int,2=double,3=bool,4=argRef,5=null); nodes as `type, props(count+entries), children(count+nodes), events(count+entries)`; component defs as `name, params(count+strings), body(node)`. Deterministic.
- Introduce a small shared `EnvelopeBody { NdNode root; List<NdComponentDef> components; Map data }` type (refactor the inline `{root,components,data}` used in `envelope.dart`) so JSON and binary codecs share one shape.
- `encodeEnvelope(..., NdPayloadFormat format = NdPayloadFormat.json)`: when `ndBinary`, the encrypted plaintext is the binary blob and the header `payloadFormat='ndBinary'`. `decodeEnvelope` dispatches on `payloadFormat`.

**Tests:** binary round-trips a representative tree+components+args; envelope round-trips with `ndBinary`; the binary blob is smaller than the JSON for the sample; an unknown `payloadFormat` → `DecodeError`.

**Acceptance:** all existing protocol tests stay green; new binary + envelope-ndBinary tests pass.

---

## F2 — Routing with path parameters (`next_dart_server`)

**Goal:** Dynamic route matching with path params (`/product/:id`) plus a documented file-organization convention (the "file-based" ergonomics; true codegen routing is noted as future).

**Design:**
- New `lib/src/router.dart`: `RoutePattern.parse('/product/:id')` → matcher that returns `null` or a `Map<String,String> params`. Static segments beat dynamic ones; trailing/empty handled.
- `NextDartApp.page(pattern, builder)` registers patterns; on `/__page?route=` and `/__action`, match the concrete path, extract params, expose them via `PageContext.params` / `ActionContext.params`. Exact routes keep working (a pattern with no `:` is exact).
- Doc: a short "organize pages by folder, register them in one place" convention section in the example/README (no build_runner codegen in this phase).

**Tests:** exact match; `:param` extraction; multiple params; static-vs-dynamic precedence; no-match → 404; params reach the page/action builder.

**Acceptance:** existing server tests green; new routing tests pass.

---

## F3 — Named & versioned component libraries (`next_dart_protocol` + `next_dart_server`)

**Goal:** Group composite components into named, versioned libraries; register and reuse across pages; carry library identity on the wire.

**Design:**
- Protocol: `NdComponentDef` gains optional `library` (String?) and `libraryVersion` (String?) fields (back-compat: absent → null; JSON omits when null). 
- Server: `ComponentLibrary({required name, required version, required List<NdComponentDef> components})`; `NextDartApp(componentLibraries: [...])` merges them into the served `components` (deduped by name; conflicting names across libraries → throw at startup). A `ComponentRegistry` collects/looks up by name.
- Negotiation: reuse the existing `minClientVersion` gate; additionally the envelope already ships the component defs themselves, so a client always has what it needs to render the current payload (no missing-library risk in this phase).

**Tests:** library merge + dedupe; duplicate-name across libraries throws; `library`/`libraryVersion` round-trip through the envelope; a page using a library component renders (server-side lowering produces the def).

**Acceptance:** protocol + server suites green; new tests pass.

---

## F4 — Dependency-free reference renderer (`next_dart_basic`, new Flutter package)

**Goal:** A second `NextDartRenderer` implementation built on plain Flutter widgets (NO rfw), proving the core is not rfw-locked and giving rfw-averse users an option.

**Design:**
- New package `packages/next_dart_basic` (Flutter; depends on `next_dart_client` + `next_dart_protocol`; **must NOT depend on rfw**).
- `BasicRenderer implements NextDartRenderer`: walks the `EnvelopeContent` tree directly to Flutter widgets, resolving composite components by inlining their bodies with arg substitution (a small client-side expander, since there's no rfw remote-widget engine here). Catalog parity: Text/Column/Card/Padding/Image/Button, events → `NdActionDispatcher`. Unknown type → a visible fallback widget (not a crash).
- Arg substitution: when expanding a composite instantiation `NdNode(type: ComponentName, props:{...})`, look up the def, deep-copy its body replacing `NdArgRef(name)` with the instantiation's prop value, and replace event arg `NdArgRef`s too.

**Tests:** renders each primitive; a Button tap dispatches; a composite (`ProductCard`) expands and renders its inner Text/Button; unknown widget shows the fallback; grep proves zero `package:rfw`.

**Acceptance:** widget tests green; rfw-isolation invariant holds (now proven by a real alternative renderer).

---

## F5 — UI streaming (`next_dart_protocol` + `next_dart_server` + `next_dart_client`)

**Goal:** Server sends an initial tree containing placeholder nodes, then streams replacements; the client shows placeholders immediately and patches them as they arrive (Next.js Suspense analogue).

**Design:**
- Protocol: a `Patch { String slotId; NdNode replacement }` type + a `Placeholder` node convention (`NdNode(type:'Slot', props:{'slot': id}, children:[fallback])`). Each streamed message is a signed+encrypted envelope-like frame: an initial `Envelope` then N `PatchFrame`s, newline-delimited.
- Server: `/__stream?route=` returns `text/plain` newline-delimited frames: first the full envelope (with slots), then patch frames as each async section resolves. A page can mark a section as `ndSlot(id, fallback, () async => subtree)`.
- Client: `NextDartClient.stream(route)` yields decoded frames; `NextDartView` (a streaming mode flag) renders the initial tree, then replaces slot `id` content with each patch. Each frame independently signature-verified + decrypted.

**Tests:** server emits initial + patches for a 1-slot page (fake async); client applies a patch to replace a slot's content; a tampered patch frame is rejected; non-streaming path unaffected.

**Acceptance:** new streaming tests pass; existing tests green. (Scope: HTTP newline-delimited frames, not WebSocket.)

---

## F6 — Dev hot-reload (`next_dart_server` + `next_dart_client`)

**Goal:** In dev mode, when the served content changes, the app refetches automatically — no manual reload.

**Design:**
- Server: an SSE endpoint `/__events` (`text/event-stream`) that emits a `reload` event whenever `contentVersion` advances (or a dev file-watch bumps it). A `NextDartApp.devMode` flag enables it; `app.bumpContent()` triggers an event (and a dev file-watcher on the pages dir can call it — optional, behind a `watch` helper).
- Client: `NextDartView(hotReload: true)` subscribes to `/__events` via the `http` streaming API and calls its internal `_load()` on `reload`. Gracefully no-ops if the endpoint is unavailable.

**Tests:** server emits a `reload` SSE line when content is bumped (consume the stream in-test); client refetches on a fake `reload` event (inject a fake event stream); production mode (hotReload:false) does not subscribe.

**Acceptance:** new hot-reload tests pass; existing tests green. (Scope: SSE push + version-bump trigger; an opt-in file-watcher helper, documented.)

---

## F7 — CLI (`next_dart_cli`, new Dart package)

**Goal:** A `next_dart` command-line tool to scaffold and run projects.

**Design:**
- New pure-Dart package `packages/next_dart_cli` with `bin/next_dart.dart`, using `package:args`. Commands:
  - `next_dart new <name>` — scaffold a minimal server+app pair (templated from the example).
  - `next_dart dev` — run the dev server (delegates to the project's `bin/server.dart`) with `devMode`/hot-reload on.
  - `next_dart doctor` — check Dart/Flutter presence + that the four packages resolve.
- A `CommandRunner` with subcommands; pure logic (path/template building) factored into `lib/` so it's unit-testable without spawning processes.

**Tests:** arg parsing for each command; `new` writes the expected files into a temp dir; `doctor` reports structured results (mock the environment checks); unknown command → usage error.

**Acceptance:** CLI unit tests pass; `dart run bin/next_dart.dart --help` lists the commands.

---

## Done criteria for Phase 2
All package suites green; rfw-isolation invariant verified (grep); each feature committed; branch merged to `main` and pushed. Then update the spec's roadmap to mark Phase 2 delivered and proceed to Phase 3.
