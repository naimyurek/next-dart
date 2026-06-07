# next-dart MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase-1 MVP of next-dart — a server-driven UI framework for Flutter where a pure-Dart backend serves an encrypted, signed, versioned neutral declarative tree that a Flutter client renders through a pluggable engine (rfw adapter), with a working counter + composite-component example.

**Architecture:** Four packages in dependency order — `next_dart_protocol` (pure Dart: neutral tree model, crypto envelope, version negotiation), `next_dart_server` (pure Dart: authoring DSL + shelf endpoints), `next_dart_client` (Flutter core: fetch/verify/decrypt + `NextDartRenderer` interface, **no rfw**), `next_dart_rfw` (Flutter: rfw-backed renderer — the only package depending on rfw). The wire format is next-dart's neutral JSON tree; rfw appears only in the client adapter.

**Tech Stack:** Dart 3.12, Flutter 3.44, `cryptography` 2.9.0 (Ed25519 + AES-GCM), `shelf` 1.4.2 / `shelf_router` 1.1.4, `rfw` 1.1.3, `test` 1.31.1, `http`.

**Reference spec:** `docs/superpowers/specs/2026-06-07-next-dart-design.md`

---

## File Structure

```
D:\dev\flutter-ssr\
├── .gitignore
├── README.md
├── packages\
│   ├── next_dart_protocol\        # pure Dart lib
│   │   ├── pubspec.yaml
│   │   ├── lib\
│   │   │   ├── next_dart_protocol.dart     # public exports
│   │   │   └── src\
│   │   │       ├── version.dart            # kProtocolVersion, semver compare
│   │   │       ├── node.dart               # NdNode, NdActionRef, NdArgRef
│   │   │       ├── component.dart          # NdComponentDef
│   │   │       ├── canonical.dart          # canonicalJsonBytes
│   │   │       ├── crypto.dart             # NdSigner, NdCipher
│   │   │       ├── errors.dart             # SignatureError, UpdateRequiredError, DecodeError
│   │   │       └── envelope.dart           # EnvelopeContent, encodeEnvelope, decodeEnvelope
│   │   └── test\
│   │       ├── node_test.dart
│   │       ├── canonical_test.dart
│   │       ├── crypto_test.dart
│   │       └── envelope_test.dart
│   ├── next_dart_server\          # pure Dart lib + dev server
│   │   ├── pubspec.yaml
│   │   ├── lib\
│   │   │   ├── next_dart_server.dart
│   │   │   └── src\
│   │   │       ├── dsl.dart                 # ndText/ndColumn/ndButton/ndCard/ndImage/ndPadding/ndArg/action
│   │   │       ├── component_dsl.dart       # ndComponent helper
│   │   │       ├── context.dart            # PageContext, ActionContext, server state
│   │   │       └── app.dart                # NextDartApp (routes/actions/keys) + shelf handler
│   │   └── test\
│   │       ├── dsl_test.dart
│   │       └── app_test.dart
│   ├── next_dart_client\          # Flutter core (NO rfw)
│   │   ├── pubspec.yaml
│   │   ├── lib\
│   │   │   ├── next_dart_client.dart
│   │   │   └── src\
│   │   │       ├── client.dart             # NextDartClient (http, verify, decrypt)
│   │   │       ├── renderer.dart           # NextDartRenderer interface, ActionDispatcher typedef
│   │   │       ├── catalog.dart            # WidgetCatalog (registration interface)
│   │   │       └── view.dart               # NextDartView widget
│   │   └── test\
│   │       └── client_test.dart
│   └── next_dart_rfw\             # Flutter rfw adapter (ONLY rfw dep)
│       ├── pubspec.yaml
│       ├── lib\
│       │   ├── next_dart_rfw.dart
│       │   └── src\
│       │       ├── rfw_codegen.dart        # NdNode/NdComponentDef -> rfw text
│       │       ├── catalog_widgets.dart    # LocalWidgetLibrary (Text/Column/Button/Card/Image/Padding)
│       │       └── rfw_renderer.dart       # RfwRenderer implements NextDartRenderer
│       └── test\
│           ├── codegen_test.dart
│           └── renderer_test.dart
├── examples\
│   └── counter_app\
│       ├── server\
│       │   ├── pubspec.yaml
│       │   ├── tool\gen_keys.dart           # prints base64 keys (run once)
│       │   ├── lib\keys.dart               # shared key constants (generated)
│       │   └── bin\server.dart             # the demo backend
│       ├── app\
│       │   ├── pubspec.yaml
│       │   ├── lib\keys.dart               # same constants as server
│       │   └── lib\main.dart               # Flutter app using NextDartView + RfwRenderer
│       └── test\
│           └── integration_test.dart        # in-process server + client loop
└── docs\
    ├── AI_GUIDE.md
    └── next_dart_tree.schema.json           # JSON Schema for the neutral tree
```

**Conventions used throughout this plan:**
- Pure-Dart packages (`protocol`, `server`) run tests with `dart test`. Flutter packages (`client`, `rfw`) run tests with `flutter test`.
- Inter-package deps use `path:` references (no melos in MVP).
- All shell commands assume the working directory `D:\dev\flutter-ssr` unless a `cd` is shown. Commands are shown in PowerShell-compatible form.
- Every commit message ends with the `Co-Authored-By` trailer used in the repo's existing commits.

---

## Milestone 0 — Workspace bootstrap

### Task 0.1: Repo hygiene files

**Files:**
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Dart/Flutter
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
pubspec.lock
*.iml
.idea/
.vscode/
# OS
Thumbs.db
.DS_Store
```

- [ ] **Step 2: Create `README.md`**

```markdown
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
```

- [ ] **Step 3: Commit**

```powershell
git add .gitignore README.md
git commit -m "chore: add gitignore and README

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Milestone A — `next_dart_protocol` (pure Dart core)

### Task A.1: Package scaffold

**Files:**
- Create: `packages/next_dart_protocol/pubspec.yaml`
- Create: `packages/next_dart_protocol/lib/next_dart_protocol.dart`

- [ ] **Step 1: Create `pubspec.yaml`**

```yaml
name: next_dart_protocol
description: Neutral declarative tree, signed/encrypted envelope, and versioning for next-dart.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  cryptography: ^2.9.0
dev_dependencies:
  test: ^1.31.1
```

- [ ] **Step 2: Create empty public export file**

```dart
// packages/next_dart_protocol/lib/next_dart_protocol.dart
library next_dart_protocol;
```

- [ ] **Step 3: Fetch deps**

Run: `cd packages/next_dart_protocol; dart pub get`
Expected: "Got dependencies!" (or "Changed N dependencies!")

- [ ] **Step 4: Commit**

```powershell
git add packages/next_dart_protocol
git commit -m "feat(protocol): scaffold next_dart_protocol package

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.2: Version + semver compare

**Files:**
- Create: `packages/next_dart_protocol/lib/src/version.dart`
- Test: `packages/next_dart_protocol/test/canonical_test.dart` (version cases added later in A.3 file; here a dedicated test)

- [ ] **Step 1: Write the failing test**

Create `packages/next_dart_protocol/test/version_test.dart`:

```dart
import 'package:next_dart_protocol/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('kProtocolVersion is set', () {
    expect(kProtocolVersion, '1.0.0');
  });

  test('semverLt compares correctly', () {
    expect(semverLt('1.0.0', '1.0.1'), isTrue);
    expect(semverLt('1.2.0', '1.10.0'), isTrue);
    expect(semverLt('2.0.0', '1.9.9'), isFalse);
    expect(semverLt('1.0.0', '1.0.0'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/next_dart_protocol; dart test test/version_test.dart`
Expected: FAIL — `version.dart` / `semverLt` not found.

- [ ] **Step 3: Write minimal implementation**

Create `packages/next_dart_protocol/lib/src/version.dart`:

```dart
/// The wire/protocol version this build speaks.
const String kProtocolVersion = '1.0.0';

/// Returns true if semver string [a] is strictly less than [b].
/// Accepts simple "x.y.z" forms (no pre-release handling in MVP).
bool semverLt(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i];
  }
  return false;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/version_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_protocol/lib/src/version.dart packages/next_dart_protocol/test/version_test.dart
git commit -m "feat(protocol): protocol version constant and semver compare

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.3: Neutral tree model (NdNode / NdActionRef / NdArgRef)

**Files:**
- Create: `packages/next_dart_protocol/lib/src/node.dart`
- Test: `packages/next_dart_protocol/test/node_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:next_dart_protocol/src/node.dart';
import 'package:test/test.dart';

void main() {
  test('NdNode round-trips through JSON', () {
    final node = NdNode(
      type: 'Column',
      children: [
        NdNode(type: 'Text', props: {'text': 'Count: 0'}),
        NdNode(
          type: 'Button',
          props: {'label': 'Increment'},
          events: {'onPressed': NdActionRef('inc')},
        ),
      ],
    );
    final json = node.toJson();
    final back = NdNode.fromJson(json);
    expect(back.toJson(), json);
    expect(back.children[1].events['onPressed']!.action, 'inc');
  });

  test('NdArgRef serializes to {\$arg: name}', () {
    final n = NdNode(type: 'Text', props: {'text': NdArgRef('title')});
    expect(n.toJson()['props'], {'text': {r'$arg': 'title'}});
    final back = NdNode.fromJson(n.toJson());
    expect(back.props['text'], isA<NdArgRef>());
    expect((back.props['text'] as NdArgRef).name, 'title');
  });

  test('NdActionRef carries args, including NdArgRef values', () {
    final a = NdActionRef('buy', {'id': NdArgRef('id')});
    final back = NdActionRef.fromJson(a.toJson());
    expect(back.action, 'buy');
    expect((back.args['id'] as NdArgRef).name, 'id');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/node_test.dart`
Expected: FAIL — `node.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_protocol/lib/src/node.dart

/// A reference to a composite-component argument, used inside a component body.
/// Serializes as `{"$arg": "<name>"}`.
class NdArgRef {
  final String name;
  const NdArgRef(this.name);
  Map<String, Object?> toJson() => {r'$arg': name};
}

/// A reference from an event to a server/client action, with optional args.
class NdActionRef {
  final String action;
  final Map<String, Object?> args;
  const NdActionRef(this.action, [this.args = const {}]);

  Map<String, Object?> toJson() => {
        'action': action,
        if (args.isNotEmpty) 'args': args.map((k, v) => MapEntry(k, encodeValue(v))),
      };

  static NdActionRef fromJson(Map<String, Object?> json) => NdActionRef(
        json['action'] as String,
        ((json['args'] as Map?)?.cast<String, Object?>() ?? const {})
            .map((k, v) => MapEntry(k, decodeValue(v))),
      );
}

/// A node in the neutral declarative tree.
class NdNode {
  final String type;
  final Map<String, Object?> props;
  final List<NdNode> children;
  final Map<String, NdActionRef> events;

  const NdNode({
    required this.type,
    this.props = const {},
    this.children = const [],
    this.events = const {},
  });

  Map<String, Object?> toJson() => {
        'type': type,
        if (props.isNotEmpty)
          'props': props.map((k, v) => MapEntry(k, encodeValue(v))),
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
        if (events.isNotEmpty)
          'events': events.map((k, v) => MapEntry(k, v.toJson())),
      };

  static NdNode fromJson(Map<String, Object?> json) => NdNode(
        type: json['type'] as String,
        props: ((json['props'] as Map?)?.cast<String, Object?>() ?? const {})
            .map((k, v) => MapEntry(k, decodeValue(v))),
        children: ((json['children'] as List?) ?? const [])
            .map((e) => NdNode.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        events: ((json['events'] as Map?)?.cast<String, Object?>() ?? const {})
            .map((k, v) => MapEntry(
                k, NdActionRef.fromJson((v as Map).cast<String, Object?>()))),
      );
}

/// Encode a prop/arg value: passes through JSON scalars, lowers NdArgRef.
Object? encodeValue(Object? v) => v is NdArgRef ? v.toJson() : v;

/// Decode a prop/arg value: recognizes the `{"$arg": ...}` shape.
Object? decodeValue(Object? v) {
  if (v is Map && v.length == 1 && v.containsKey(r'$arg')) {
    return NdArgRef(v[r'$arg'] as String);
  }
  return v;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/node_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_protocol/lib/src/node.dart packages/next_dart_protocol/test/node_test.dart
git commit -m "feat(protocol): neutral tree model (NdNode/NdActionRef/NdArgRef)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.4: Composite component model (NdComponentDef)

**Files:**
- Create: `packages/next_dart_protocol/lib/src/component.dart`
- Test: `packages/next_dart_protocol/test/component_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:next_dart_protocol/src/node.dart';
import 'package:next_dart_protocol/src/component.dart';
import 'package:test/test.dart';

void main() {
  test('NdComponentDef round-trips through JSON', () {
    final def = NdComponentDef(
      name: 'ProductCard',
      params: ['title', 'price', 'id'],
      body: NdNode(type: 'Card', children: [
        NdNode(type: 'Text', props: {'text': NdArgRef('title')}),
      ]),
    );
    final back = NdComponentDef.fromJson(def.toJson());
    expect(back.name, 'ProductCard');
    expect(back.params, ['title', 'price', 'id']);
    expect((back.body.children[0].props['text'] as NdArgRef).name, 'title');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/component_test.dart`
Expected: FAIL — `component.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_protocol/lib/src/component.dart
import 'node.dart';

/// A server-defined reusable component, composed from catalog primitives.
/// Shipped as data; the client renderer resolves it. Params are referenced in
/// [body] via [NdArgRef].
class NdComponentDef {
  final String name;
  final List<String> params;
  final NdNode body;
  const NdComponentDef({
    required this.name,
    required this.params,
    required this.body,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'params': params,
        'body': body.toJson(),
      };

  static NdComponentDef fromJson(Map<String, Object?> json) => NdComponentDef(
        name: json['name'] as String,
        params: (json['params'] as List).cast<String>(),
        body: NdNode.fromJson((json['body'] as Map).cast<String, Object?>()),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/component_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_protocol/lib/src/component.dart packages/next_dart_protocol/test/component_test.dart
git commit -m "feat(protocol): composite component model (NdComponentDef)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.5: Canonical JSON for signing

**Files:**
- Create: `packages/next_dart_protocol/lib/src/canonical.dart`
- Test: `packages/next_dart_protocol/test/canonical_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:next_dart_protocol/src/canonical.dart';
import 'package:test/test.dart';

void main() {
  test('canonicalJsonBytes sorts keys deterministically', () {
    final a = canonicalJsonBytes({'b': 1, 'a': 2});
    final b = canonicalJsonBytes({'a': 2, 'b': 1});
    expect(a, b);
    expect(utf8.decode(a), '{"a":2,"b":1}');
  });

  test('canonicalJsonBytes recurses into nested maps and lists', () {
    final s = utf8.decode(canonicalJsonBytes({
      'z': [
        {'y': 1, 'x': 2}
      ]
    }));
    expect(s, '{"z":[{"x":2,"y":1}]}');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/canonical_test.dart`
Expected: FAIL — `canonical.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_protocol/lib/src/canonical.dart
import 'dart:convert';

/// Deterministic JSON byte serialization (recursively sorted map keys) used as
/// the message that signatures are computed over. Both server and client must
/// produce identical bytes for the same logical value.
List<int> canonicalJsonBytes(Object? value) => utf8.encode(_canonical(value));

String _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(v[k])}').join(',')}}';
  }
  if (v is List) {
    return '[${v.map(_canonical).join(',')}]';
  }
  return jsonEncode(v);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/canonical_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_protocol/lib/src/canonical.dart packages/next_dart_protocol/test/canonical_test.dart
git commit -m "feat(protocol): canonical JSON serialization for signing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.6: Crypto wrappers (Ed25519 sign/verify, AES-GCM encrypt/decrypt)

**Files:**
- Create: `packages/next_dart_protocol/lib/src/crypto.dart`
- Test: `packages/next_dart_protocol/test/crypto_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/src/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('sign then verify succeeds; tamper fails', () async {
    final signer = NdSigner();
    final kp = await Ed25519().newKeyPair();
    final pub = await kp.extractPublicKey();
    final msg = [1, 2, 3, 4];
    final sig = await signer.sign(msg, kp);
    expect(await signer.verify(msg, sig, pub), isTrue);
    expect(await signer.verify([9, 9, 9, 9], sig, pub), isFalse);
  });

  test('encrypt then decrypt round-trips', () async {
    final cipher = NdCipher();
    final key = SecretKey(List.filled(32, 7));
    final clear = [10, 20, 30];
    final box = await cipher.encrypt(clear, key);
    final back = await cipher.decrypt(box.cipherText, box.nonce, box.mac, key);
    expect(back, clear);
  });

  test('decrypt with wrong key throws', () async {
    final cipher = NdCipher();
    final box = await cipher.encrypt([1, 2, 3], SecretKey(List.filled(32, 1)));
    expect(
      () => cipher.decrypt(box.cipherText, box.nonce, box.mac, SecretKey(List.filled(32, 2))),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/crypto_test.dart`
Expected: FAIL — `crypto.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_protocol/lib/src/crypto.dart
import 'package:cryptography/cryptography.dart';

/// Ed25519 signing/verification wrapper.
class NdSigner {
  final Ed25519 _algo = Ed25519();

  Future<List<int>> sign(List<int> message, SimpleKeyPair keyPair) async {
    final sig = await _algo.sign(message, keyPair: keyPair);
    return sig.bytes;
  }

  Future<bool> verify(
      List<int> message, List<int> signatureBytes, SimplePublicKey publicKey) {
    return _algo.verify(message,
        signature: Signature(signatureBytes, publicKey: publicKey));
  }
}

/// Output of an AES-GCM encryption.
class NdSealed {
  final List<int> cipherText;
  final List<int> nonce;
  final List<int> mac;
  const NdSealed(this.cipherText, this.nonce, this.mac);
}

/// AES-256-GCM authenticated encryption wrapper.
class NdCipher {
  final AesGcm _algo = AesGcm.with256bits();

  Future<NdSealed> encrypt(List<int> clear, SecretKey key) async {
    final nonce = _algo.newNonce();
    final box = await _algo.encrypt(clear, secretKey: key, nonce: nonce);
    return NdSealed(box.cipherText, box.nonce, box.mac.bytes);
  }

  Future<List<int>> decrypt(
      List<int> cipherText, List<int> nonce, List<int> mac, SecretKey key) {
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    return _algo.decrypt(box, secretKey: key);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/crypto_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_protocol/lib/src/crypto.dart packages/next_dart_protocol/test/crypto_test.dart
git commit -m "feat(protocol): Ed25519 + AES-GCM crypto wrappers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.7: Errors

**Files:**
- Create: `packages/next_dart_protocol/lib/src/errors.dart`

- [ ] **Step 1: Write minimal implementation (no separate test; exercised by envelope tests)**

```dart
// packages/next_dart_protocol/lib/src/errors.dart

/// Thrown when an envelope's signature does not verify against the pinned key.
class SignatureError implements Exception {
  @override
  String toString() => 'SignatureError: envelope signature is invalid';
}

/// Thrown when the client is older than the server's required minClientVersion.
class UpdateRequiredError implements Exception {
  final String minClientVersion;
  UpdateRequiredError(this.minClientVersion);
  @override
  String toString() =>
      'UpdateRequiredError: client must be >= $minClientVersion';
}

/// Thrown when wire bytes cannot be parsed into an envelope.
class DecodeError implements Exception {
  final String message;
  DecodeError(this.message);
  @override
  String toString() => 'DecodeError: $message';
}
```

- [ ] **Step 2: Commit**

```powershell
git add packages/next_dart_protocol/lib/src/errors.dart
git commit -m "feat(protocol): typed protocol errors

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.8: Envelope encode/decode (the heart of the protocol)

**Files:**
- Create: `packages/next_dart_protocol/lib/src/envelope.dart`
- Test: `packages/next_dart_protocol/test/envelope_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/src/node.dart';
import 'package:next_dart_protocol/src/component.dart';
import 'package:next_dart_protocol/src/envelope.dart';
import 'package:next_dart_protocol/src/errors.dart';
import 'package:test/test.dart';

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  final secret = SecretKey(List.filled(32, 3));

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
  });

  EnvelopeContent sample() => EnvelopeContent(
        root: NdNode(type: 'Text', props: {'text': 'hi'}),
        components: [
          NdComponentDef(
              name: 'C', params: ['x'], body: NdNode(type: 'Text', props: {'text': NdArgRef('x')})),
        ],
        data: const {},
      );

  test('encode then decode returns equivalent content', () async {
    final wire = await encodeEnvelope(
      content: sample(),
      route: '/',
      contentVersion: 1,
      minClientVersion: '1.0.0',
      keyId: 'k1',
      secretKey: secret,
      signingKeyPair: signingKp,
    );
    final out = await decodeEnvelope(
      wire,
      secretKey: secret,
      signingPublicKey: signingPub,
      clientVersion: '1.0.0',
    );
    expect(out.root.props['text'], 'hi');
    expect(out.components.single.name, 'C');
  });

  test('tampered ciphertext fails signature verification', () async {
    final wire = await encodeEnvelope(
      content: sample(),
      route: '/',
      contentVersion: 1,
      minClientVersion: '1.0.0',
      keyId: 'k1',
      secretKey: secret,
      signingKeyPair: signingKp,
    );
    final map = jsonDecode(utf8.decode(wire)) as Map<String, Object?>;
    map['cipherText'] = base64.encode([0, 0, 0, 0]); // tamper
    final tampered = utf8.encode(jsonEncode(map));
    expect(
      () => decodeEnvelope(tampered,
          secretKey: secret, signingPublicKey: signingPub, clientVersion: '1.0.0'),
      throwsA(isA<SignatureError>()),
    );
  });

  test('client older than minClientVersion is rejected', () async {
    final wire = await encodeEnvelope(
      content: sample(),
      route: '/',
      contentVersion: 1,
      minClientVersion: '2.0.0',
      keyId: 'k1',
      secretKey: secret,
      signingKeyPair: signingKp,
    );
    expect(
      () => decodeEnvelope(wire,
          secretKey: secret, signingPublicKey: signingPub, clientVersion: '1.0.0'),
      throwsA(isA<UpdateRequiredError>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/envelope_test.dart`
Expected: FAIL — `envelope.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_protocol/lib/src/envelope.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'canonical.dart';
import 'component.dart';
import 'crypto.dart';
import 'errors.dart';
import 'node.dart';
import 'version.dart';

const String kAlg = 'ed25519+aesgcm256';

/// The decrypted payload of an envelope.
class EnvelopeContent {
  final NdNode root;
  final List<NdComponentDef> components;
  final Map<String, Object?> data;
  const EnvelopeContent({
    required this.root,
    this.components = const [],
    this.data = const {},
  });
}

/// Build a signed + encrypted wire envelope (UTF-8 JSON bytes).
Future<List<int>> encodeEnvelope({
  required EnvelopeContent content,
  required String route,
  required int contentVersion,
  required String minClientVersion,
  required String keyId,
  required SecretKey secretKey,
  required SimpleKeyPair signingKeyPair,
}) async {
  final plain = utf8.encode(jsonEncode({
    'root': content.root.toJson(),
    'components': content.components.map((c) => c.toJson()).toList(),
    'data': content.data,
  }));
  final sealed = await NdCipher().encrypt(plain, secretKey);
  final header = <String, Object?>{
    'protocolVersion': kProtocolVersion,
    'contentVersion': contentVersion,
    'minClientVersion': minClientVersion,
    'route': route,
    'payloadFormat': 'json',
    'alg': kAlg,
    'keyId': keyId,
    'nonce': base64.encode(sealed.nonce),
    'cipherText': base64.encode(sealed.cipherText),
    'mac': base64.encode(sealed.mac),
  };
  final sig = await NdSigner().sign(canonicalJsonBytes(header), signingKeyPair);
  final wire = <String, Object?>{...header, 'signature': base64.encode(sig)};
  return utf8.encode(jsonEncode(wire));
}

/// Verify, version-check, and decrypt a wire envelope.
Future<EnvelopeContent> decodeEnvelope(
  List<int> bytes, {
  required SecretKey secretKey,
  required SimplePublicKey signingPublicKey,
  required String clientVersion,
}) async {
  late final Map<String, Object?> wire;
  try {
    wire = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
  } catch (e) {
    throw DecodeError('not valid envelope JSON: $e');
  }
  final sigB64 = wire['signature'];
  if (sigB64 is! String) throw DecodeError('missing signature');
  final header = Map<String, Object?>.from(wire)..remove('signature');

  final ok = await NdSigner().verify(
    canonicalJsonBytes(header),
    base64.decode(sigB64),
    signingPublicKey,
  );
  if (!ok) throw SignatureError();

  final minClient = header['minClientVersion'] as String;
  if (semverLt(clientVersion, minClient)) {
    throw UpdateRequiredError(minClient);
  }

  final plain = await NdCipher().decrypt(
    base64.decode(header['cipherText'] as String),
    base64.decode(header['nonce'] as String),
    base64.decode(header['mac'] as String),
    secretKey,
  );
  final body = (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
  return EnvelopeContent(
    root: NdNode.fromJson((body['root'] as Map).cast<String, Object?>()),
    components: ((body['components'] as List?) ?? const [])
        .map((e) => NdComponentDef.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    data: ((body['data'] as Map?)?.cast<String, Object?>()) ?? const {},
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/envelope_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_protocol/lib/src/envelope.dart packages/next_dart_protocol/test/envelope_test.dart
git commit -m "feat(protocol): signed+encrypted versioned envelope encode/decode

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A.9: Public exports + full suite

**Files:**
- Modify: `packages/next_dart_protocol/lib/next_dart_protocol.dart`

- [ ] **Step 1: Replace the export file**

```dart
// packages/next_dart_protocol/lib/next_dart_protocol.dart
library next_dart_protocol;

export 'src/version.dart';
export 'src/node.dart';
export 'src/component.dart';
export 'src/canonical.dart';
export 'src/crypto.dart';
export 'src/errors.dart';
export 'src/envelope.dart';
```

- [ ] **Step 2: Run the whole package suite**

Run: `dart test`
Expected: PASS — all tests across version/node/component/canonical/crypto/envelope green.

- [ ] **Step 3: Analyze**

Run: `dart analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```powershell
git add packages/next_dart_protocol/lib/next_dart_protocol.dart
git commit -m "feat(protocol): public exports; full suite green

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Milestone B — `next_dart_server` (pure Dart)

### Task B.1: Package scaffold

**Files:**
- Create: `packages/next_dart_server/pubspec.yaml`
- Create: `packages/next_dart_server/lib/next_dart_server.dart`

- [ ] **Step 1: Create `pubspec.yaml`**

```yaml
name: next_dart_server
description: Authoring DSL and HTTP endpoints for next-dart backends.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  next_dart_protocol:
    path: ../next_dart_protocol
  cryptography: ^2.9.0
  shelf: ^1.4.2
  shelf_router: ^1.1.4
dev_dependencies:
  test: ^1.31.1
```

- [ ] **Step 2: Create export stub**

```dart
// packages/next_dart_server/lib/next_dart_server.dart
library next_dart_server;
```

- [ ] **Step 3: Fetch deps**

Run: `cd packages/next_dart_server; dart pub get`
Expected: "Got dependencies!"

- [ ] **Step 4: Commit**

```powershell
git add packages/next_dart_server
git commit -m "feat(server): scaffold next_dart_server package

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B.2: Authoring DSL

**Files:**
- Create: `packages/next_dart_server/lib/src/dsl.dart`
- Create: `packages/next_dart_server/lib/src/component_dsl.dart`
- Test: `packages/next_dart_server/test/dsl_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/src/dsl.dart';
import 'package:next_dart_server/src/component_dsl.dart';
import 'package:test/test.dart';

void main() {
  test('primitive builders produce the expected nodes', () {
    final n = ndColumn([
      ndText('Count: 0'),
      ndButton(label: 'Increment', onPressed: action('inc')),
    ]);
    expect(n.type, 'Column');
    expect(n.children[0].props['text'], 'Count: 0');
    expect(n.children[1].events['onPressed']!.action, 'inc');
  });

  test('ndText accepts an arg ref for component bodies', () {
    final n = ndText(ndArg('title'));
    expect((n.props['text'] as NdArgRef).name, 'title');
  });

  test('ndComponent builds a NdComponentDef from a param-aware builder', () {
    final def = ndComponent('ProductCard', ['title', 'price', 'id'], (a) {
      return ndCard(
        child: ndColumn([
          ndText(a('title')),
          ndText(a('price')),
          ndButton(label: 'Buy', onPressed: action('buy', {'id': a('id')})),
        ]),
      );
    });
    expect(def.name, 'ProductCard');
    expect(def.params, ['title', 'price', 'id']);
    expect((def.body.children[0].props['text'] as NdArgRef).name, 'title');
    expect((def.body.children[2].events['onPressed']!.args['id'] as NdArgRef).name, 'id');
  });

  test('ndUse instantiates a component by name with props', () {
    final n = ndUse('ProductCard', {'title': 'Shoe', 'price': r'$10', 'id': 7});
    expect(n.type, 'ProductCard');
    expect(n.props['title'], 'Shoe');
    expect(n.props['id'], 7);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/next_dart_server; dart test test/dsl_test.dart`
Expected: FAIL — `dsl.dart` not found.

- [ ] **Step 3: Write minimal implementation**

Create `packages/next_dart_server/lib/src/dsl.dart`:

```dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Text widget. [text] is a String literal or an [NdArgRef] (in component bodies).
NdNode ndText(Object text) => NdNode(type: 'Text', props: {'text': text});

/// Vertical layout.
NdNode ndColumn(List<NdNode> children) => NdNode(type: 'Column', children: children);

/// Single-child card.
NdNode ndCard({required NdNode child}) => NdNode(type: 'Card', children: [child]);

/// Single-child padding (uniform).
NdNode ndPadding({required double all, required NdNode child}) =>
    NdNode(type: 'Padding', props: {'all': all}, children: [child]);

/// Network image.
NdNode ndImage(Object src) => NdNode(type: 'Image', props: {'src': src});

/// Button with a single tap action.
NdNode ndButton({required Object label, required NdActionRef onPressed}) =>
    NdNode(type: 'Button', props: {'label': label}, events: {'onPressed': onPressed});

/// Reference a server/client action with optional args.
NdActionRef action(String id, [Map<String, Object?> args = const {}]) =>
    NdActionRef(id, args);

/// Reference a composite-component parameter (only valid inside a component body).
NdArgRef ndArg(String name) => NdArgRef(name);

/// Instantiate a composite component [name] with literal [props].
NdNode ndUse(String name, Map<String, Object?> props) =>
    NdNode(type: name, props: props);
```

Create `packages/next_dart_server/lib/src/component_dsl.dart`:

```dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Build a composite component. The builder receives an `a` function that
/// produces an [NdArgRef] for a declared param, e.g. `a('title')`.
NdComponentDef ndComponent(
  String name,
  List<String> params,
  NdNode Function(NdArgRef Function(String)) build,
) {
  return NdComponentDef(
    name: name,
    params: params,
    body: build((p) {
      assert(params.contains(p), 'unknown param "$p" in component "$name"');
      return NdArgRef(p);
    }),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/dsl_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_server/lib/src/dsl.dart packages/next_dart_server/lib/src/component_dsl.dart packages/next_dart_server/test/dsl_test.dart
git commit -m "feat(server): authoring DSL (primitives, components, actions)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B.3: Context (server state, page + action contexts)

**Files:**
- Create: `packages/next_dart_server/lib/src/context.dart`
- Test: covered indirectly by `app_test.dart` in B.4 (no dedicated test — this is a small data holder)

- [ ] **Step 1: Write minimal implementation**

```dart
// packages/next_dart_server/lib/src/context.dart

/// Per-process mutable state for the MVP (single logical session).
/// Phase 2 will key this by client/session token.
class ServerState {
  final Map<String, Object?> _values = {};

  T get<T>(String key, T fallback) => (_values[key] as T?) ?? fallback;
  void set(String key, Object? value) => _values[key] = value;
  void update<T>(String key, T fallback, T Function(T) fn) =>
      _values[key] = fn(get<T>(key, fallback));
}

/// Passed to page builders.
class PageContext {
  final ServerState state;
  PageContext(this.state);
}

/// Passed to action handlers.
class ActionContext {
  final ServerState state;
  final Map<String, Object?> args;
  ActionContext(this.state, this.args);
}
```

- [ ] **Step 2: Commit**

```powershell
git add packages/next_dart_server/lib/src/context.dart
git commit -m "feat(server): server state and page/action contexts

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B.4: NextDartApp + shelf handler

**Files:**
- Create: `packages/next_dart_server/lib/src/app.dart`
- Test: `packages/next_dart_server/test/app_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/src/app.dart';
import 'package:next_dart_server/src/context.dart';
import 'package:next_dart_server/src/dsl.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  final secret = SecretKey(List.filled(32, 5));

  NextDartApp buildApp() {
    final app = NextDartApp(
      signingKeyPair: signingKp,
      secretKey: secret,
      keyId: 'k1',
    );
    app.page('/', (ctx) {
      final c = ctx.state.get<int>('count', 0);
      return ndColumn([ndText('Count: $c')]);
    });
    app.action('inc', (ctx) {
      ctx.state.update<int>('count', 0, (n) => n + 1);
    });
    return app;
  }

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
  });

  Future<EnvelopeContent> decodeBody(Response r) async {
    final bytes = await r.read().expand((x) => x).toList();
    return decodeEnvelope(bytes,
        secretKey: secret, signingPublicKey: signingPub, clientVersion: '1.0.0');
  }

  test('GET /__page returns a signed envelope with the page tree', () async {
    final handler = buildApp().handler;
    final res = await handler(Request('GET', Uri.parse('http://x/__page?route=/')));
    expect(res.statusCode, 200);
    final content = await decodeBody(res);
    expect(content.root.children[0].props['text'], 'Count: 0');
  });

  test('POST /__action runs the handler and returns the updated tree', () async {
    final app = buildApp();
    final handler = app.handler;
    final res = await handler(Request(
      'POST',
      Uri.parse('http://x/__action'),
      body: jsonEncode({'action': 'inc', 'args': {}, 'route': '/'}),
    ));
    expect(res.statusCode, 200);
    final content = await decodeBody(res);
    expect(content.root.children[0].props['text'], 'Count: 1');
  });

  test('unknown route returns 404', () async {
    final handler = buildApp().handler;
    final res =
        await handler(Request('GET', Uri.parse('http://x/__page?route=/nope')));
    expect(res.statusCode, 404);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/app_test.dart`
Expected: FAIL — `app.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_server/lib/src/app.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'context.dart';

typedef PageBuilder = NdNode Function(PageContext ctx);
typedef ActionHandler = void Function(ActionContext ctx);

/// A next-dart backend: routes, actions, shared components, and signing keys.
class NextDartApp {
  final SimpleKeyPair signingKeyPair;
  final SecretKey secretKey;
  final String keyId;
  final String minClientVersion;
  final List<NdComponentDef> components;
  final ServerState state = ServerState();

  final Map<String, PageBuilder> _pages = {};
  final Map<String, ActionHandler> _actions = {};
  int _contentVersion = 0;

  NextDartApp({
    required this.signingKeyPair,
    required this.secretKey,
    required this.keyId,
    this.minClientVersion = '1.0.0',
    this.components = const [],
  });

  void page(String route, PageBuilder builder) => _pages[route] = builder;
  void action(String id, ActionHandler handler) => _actions[id] = handler;

  Future<List<int>> _envelopeFor(String route) {
    final builder = _pages[route]!;
    final root = builder(PageContext(state));
    return encodeEnvelope(
      content: EnvelopeContent(root: root, components: components),
      route: route,
      contentVersion: ++_contentVersion,
      minClientVersion: minClientVersion,
      keyId: keyId,
      secretKey: secretKey,
      signingKeyPair: signingKeyPair,
    );
  }

  Handler get handler {
    final router = Router();

    router.get('/__page', (Request req) async {
      final route = req.url.queryParameters['route'] ?? '/';
      if (!_pages.containsKey(route)) {
        return Response.notFound('no such route: $route');
      }
      final bytes = await _envelopeFor(route);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    router.post('/__action', (Request req) async {
      final body = (jsonDecode(await req.readAsString()) as Map).cast<String, Object?>();
      final id = body['action'] as String;
      final route = body['route'] as String? ?? '/';
      final args = (body['args'] as Map?)?.cast<String, Object?>() ?? const {};
      final h = _actions[id];
      if (h == null) return Response.notFound('no such action: $id');
      h(ActionContext(state, args));
      if (!_pages.containsKey(route)) {
        return Response.notFound('no such route: $route');
      }
      final bytes = await _envelopeFor(route);
      return Response.ok(bytes,
          headers: {'content-type': 'application/octet-stream'});
    });

    return router.call;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/app_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_server/lib/src/app.dart packages/next_dart_server/test/app_test.dart
git commit -m "feat(server): NextDartApp with /__page and /__action endpoints

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B.5: Public exports + suite

**Files:**
- Modify: `packages/next_dart_server/lib/next_dart_server.dart`

- [ ] **Step 1: Replace the export file**

```dart
// packages/next_dart_server/lib/next_dart_server.dart
library next_dart_server;

export 'src/dsl.dart';
export 'src/component_dsl.dart';
export 'src/context.dart';
export 'src/app.dart';
```

- [ ] **Step 2: Run suite + analyze**

Run: `dart test`
Expected: PASS (all server tests).
Run: `dart analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```powershell
git add packages/next_dart_server/lib/next_dart_server.dart
git commit -m "feat(server): public exports; suite green

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Milestone C — `next_dart_client` (Flutter core, NO rfw)

### Task C.1: Package scaffold

**Files:**
- Create: `packages/next_dart_client/pubspec.yaml`
- Create: `packages/next_dart_client/lib/next_dart_client.dart`

- [ ] **Step 1: Create `pubspec.yaml`**

```yaml
name: next_dart_client
description: Flutter core for next-dart — fetch, verify, decrypt, and a pluggable renderer interface.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.12.0
  flutter: ">=3.44.0"
dependencies:
  flutter:
    sdk: flutter
  next_dart_protocol:
    path: ../next_dart_protocol
  cryptography: ^2.9.0
  http: ^1.2.0
dev_dependencies:
  flutter_test:
    sdk: flutter
```

- [ ] **Step 2: Create export stub**

```dart
// packages/next_dart_client/lib/next_dart_client.dart
library next_dart_client;
```

- [ ] **Step 3: Fetch deps**

Run: `cd packages/next_dart_client; flutter pub get`
Expected: "Got dependencies!"

- [ ] **Step 4: Commit**

```powershell
git add packages/next_dart_client
git commit -m "feat(client): scaffold next_dart_client package

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C.2: Renderer interface + ActionDispatcher

**Files:**
- Create: `packages/next_dart_client/lib/src/renderer.dart`
- Create: `packages/next_dart_client/lib/src/catalog.dart`

- [ ] **Step 1: Write minimal implementation (interfaces; behavior tested via rfw adapter in Milestone D)**

`packages/next_dart_client/lib/src/renderer.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Called when a rendered widget fires an action. Implementations post to the
/// server (server action) or run a pre-bundled client-local action.
typedef ActionDispatcher = Future<void> Function(
    String action, Map<String, Object?> args);

/// A render engine maps decoded protocol content to a Flutter widget.
/// The core ships only this interface — concrete engines (e.g. rfw) are separate
/// packages, so the core never depends on any specific renderer.
abstract class NextDartRenderer {
  Widget render(
    BuildContext context,
    EnvelopeContent content,
    ActionDispatcher dispatch,
  );
}
```

`packages/next_dart_client/lib/src/catalog.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Builds a native widget for a catalog entry. [resolveChild]/[resolveChildren]
/// let a builder embed already-rendered child widgets; [fire] triggers a named
/// event with args. A concrete renderer supplies these callbacks.
typedef CatalogBuilder = Widget Function(CatalogNode node);

/// What a [CatalogBuilder] receives. Renderer-agnostic so apps can register
/// widgets without referencing rfw.
abstract class CatalogNode {
  T? prop<T>(String key);
  Widget? child(String key);
  List<Widget> children(String key);
  VoidCallback? event(String key);
}

/// A registry of custom native widgets, keyed by node type. A renderer consults
/// this before falling back to its built-in catalog, so apps extend the UI
/// vocabulary without forking the renderer.
class WidgetCatalog {
  final Map<String, CatalogBuilder> _builders = {};
  void register(String type, CatalogBuilder builder) => _builders[type] = builder;
  CatalogBuilder? operator [](String type) => _builders[type];
  Iterable<String> get types => _builders.keys;
}
```

- [ ] **Step 2: Analyze**

Run: `cd packages/next_dart_client; flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```powershell
git add packages/next_dart_client/lib/src/renderer.dart packages/next_dart_client/lib/src/catalog.dart
git commit -m "feat(client): renderer interface and widget catalog registration

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C.3: NextDartClient (fetch/verify/decrypt)

**Files:**
- Create: `packages/next_dart_client/lib/src/client.dart`
- Test: `packages/next_dart_client/test/client_test.dart`

- [ ] **Step 1: Write the failing test**

This test wires the client to an in-memory `http` MockClient that runs a real `NextDartApp` handler, proving end-to-end verify+decrypt without a socket. Add `http` `MockClient` usage.

```dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/client.dart';

void main() {
  test('fetchPage verifies, decrypts, and returns the tree', () async {
    final signingKp = await Ed25519().newKeyPair();
    final signingPub = await signingKp.extractPublicKey();
    final secret = SecretKey(List.filled(32, 9));

    Future<List<int>> envelope(int count) => encodeEnvelope(
          content: EnvelopeContent(
              root: NdNode(type: 'Text', props: {'text': 'Count: $count'})),
          route: '/',
          contentVersion: 1,
          minClientVersion: '1.0.0',
          keyId: 'k1',
          secretKey: secret,
          signingKeyPair: signingKp,
        );

    final mock = MockClient((req) async {
      if (req.url.path == '/__page') {
        return http.Response.bytes(await envelope(0), 200);
      }
      if (req.url.path == '/__action') {
        return http.Response.bytes(await envelope(1), 200);
      }
      return http.Response('not found', 404);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );

    final page = await client.fetchPage('/');
    expect(page.root.props['text'], 'Count: 0');

    final after = await client.dispatch('inc', const {}, route: '/');
    expect(after.root.props['text'], 'Count: 1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/client_test.dart`
Expected: FAIL — `client.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_client/lib/src/client.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Talks to a next-dart backend: fetches pages and dispatches actions, verifying
/// each envelope's signature and decrypting its payload.
class NextDartClient {
  final Uri baseUrl;
  final SimplePublicKey signingPublicKey;
  final SecretKey secretKey;
  final String clientVersion;
  final http.Client _http;

  NextDartClient({
    required this.baseUrl,
    required this.signingPublicKey,
    required this.secretKey,
    this.clientVersion = '1.0.0',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Future<EnvelopeContent> fetchPage(String route) async {
    final res = await _http.get(
        baseUrl.replace(path: '/__page', queryParameters: {'route': route}));
    return _decode(res);
  }

  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
      {required String route}) async {
    final res = await _http.post(
      baseUrl.replace(path: '/__action'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'action': action, 'args': args, 'route': route}),
    );
    return _decode(res);
  }

  Future<EnvelopeContent> _decode(http.Response res) {
    if (res.statusCode != 200) {
      throw DecodeError('server returned ${res.statusCode}: ${res.body}');
    }
    return decodeEnvelope(
      res.bodyBytes,
      secretKey: secretKey,
      signingPublicKey: signingPublicKey,
      clientVersion: clientVersion,
    );
  }

  void close() => _http.close();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/client_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_client/lib/src/client.dart packages/next_dart_client/test/client_test.dart
git commit -m "feat(client): NextDartClient fetch/dispatch with verify+decrypt

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C.4: NextDartView widget

**Files:**
- Create: `packages/next_dart_client/lib/src/view.dart`
- Test: `packages/next_dart_client/test/view_test.dart`

- [ ] **Step 1: Write the failing test**

Uses a fake renderer (no rfw) to prove the fetch→render→dispatch→re-render loop in the core.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/renderer.dart';
import 'package:next_dart_client/src/view.dart';

class _FakeRenderer extends NextDartRenderer {
  @override
  Widget render(BuildContext context, EnvelopeContent content, ActionDispatcher dispatch) {
    final label = content.root.props['text'] as String;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        onTap: () => dispatch('inc', const {}),
        child: Text(label),
      ),
    );
  }
}

class _FakeSource extends NextDartSource {
  int count = 0;
  @override
  Future<EnvelopeContent> fetchPage(String route) async =>
      EnvelopeContent(root: NdNode(type: 'Text', props: {'text': 'Count: $count'}));
  @override
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args, {required String route}) async {
    count++;
    return EnvelopeContent(root: NdNode(type: 'Text', props: {'text': 'Count: $count'}));
  }
}

void main() {
  testWidgets('view renders page then re-renders after an action', (tester) async {
    await tester.pumpWidget(NextDartView(
      source: _FakeSource(),
      route: '/',
      renderer: _FakeRenderer(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.text('Count: 0'));
    await tester.pumpAndSettle();
    expect(find.text('Count: 1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/view_test.dart`
Expected: FAIL — `view.dart` / `NextDartSource` not found.

- [ ] **Step 3: Write minimal implementation**

Introduce a small `NextDartSource` interface so `NextDartView` is testable without HTTP, and have `NextDartClient` implement it.

Append to `packages/next_dart_client/lib/src/client.dart` (add `implements NextDartSource` and the import):

```dart
// at top of client.dart add:
import 'source.dart';
// change class declaration to:
class NextDartClient implements NextDartSource {
```

Create `packages/next_dart_client/lib/src/source.dart`:

```dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// The data source a [NextDartView] reads from. Implemented by [NextDartClient];
/// fakeable in tests.
abstract class NextDartSource {
  Future<EnvelopeContent> fetchPage(String route);
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
      {required String route});
}
```

Create `packages/next_dart_client/lib/src/view.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'renderer.dart';
import 'source.dart';

/// Fetches a route's tree, renders it via [renderer], and re-renders when an
/// action dispatched by the rendered UI returns a new tree.
class NextDartView extends StatefulWidget {
  final NextDartSource source;
  final String route;
  final NextDartRenderer renderer;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final Widget Function(BuildContext)? loadingBuilder;

  const NextDartView({
    super.key,
    required this.source,
    required this.route,
    required this.renderer,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<NextDartView> createState() => _NextDartViewState();
}

class _NextDartViewState extends State<NextDartView> {
  EnvelopeContent? _content;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.source.fetchPage(widget.route);
      if (mounted) setState(() => _content = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _dispatch(String action, Map<String, Object?> args) async {
    try {
      final c = await widget.source
          .dispatch(action, args, route: widget.route);
      if (mounted) setState(() => _content = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          _fallbackText('Error: $_error');
    }
    final content = _content;
    if (content == null) {
      return widget.loadingBuilder?.call(context) ??
          _fallbackText('Loading…');
    }
    return widget.renderer.render(context, content, _dispatch);
  }

  Widget _fallbackText(String s) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text(s)),
      );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/view_test.dart test/client_test.dart`
Expected: PASS (both files).

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_client/lib/src/source.dart packages/next_dart_client/lib/src/view.dart packages/next_dart_client/lib/src/client.dart packages/next_dart_client/test/view_test.dart
git commit -m "feat(client): NextDartView render loop + NextDartSource interface

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C.5: Public exports + suite

**Files:**
- Modify: `packages/next_dart_client/lib/next_dart_client.dart`

- [ ] **Step 1: Replace the export file**

```dart
// packages/next_dart_client/lib/next_dart_client.dart
library next_dart_client;

export 'package:next_dart_protocol/next_dart_protocol.dart'
    show EnvelopeContent, NdNode, NdActionRef, NdArgRef, NdComponentDef;
export 'src/renderer.dart';
export 'src/catalog.dart';
export 'src/source.dart';
export 'src/client.dart';
export 'src/view.dart';
```

- [ ] **Step 2: Run suite + analyze**

Run: `flutter test`
Expected: PASS.
Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```powershell
git add packages/next_dart_client/lib/next_dart_client.dart
git commit -m "feat(client): public exports; suite green

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Milestone D — `next_dart_rfw` (Flutter rfw adapter; ONLY rfw dep)

### Task D.1: Package scaffold

**Files:**
- Create: `packages/next_dart_rfw/pubspec.yaml`
- Create: `packages/next_dart_rfw/lib/next_dart_rfw.dart`

- [ ] **Step 1: Create `pubspec.yaml`**

```yaml
name: next_dart_rfw
description: rfw-backed render engine for next-dart (the only package depending on rfw).
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.12.0
  flutter: ">=3.44.0"
dependencies:
  flutter:
    sdk: flutter
  next_dart_client:
    path: ../next_dart_client
  next_dart_protocol:
    path: ../next_dart_protocol
  rfw: ^1.1.3
dev_dependencies:
  flutter_test:
    sdk: flutter
```

- [ ] **Step 2: Create export stub**

```dart
// packages/next_dart_rfw/lib/next_dart_rfw.dart
library next_dart_rfw;
```

- [ ] **Step 3: Fetch deps**

Run: `cd packages/next_dart_rfw; flutter pub get`
Expected: "Got dependencies!"

- [ ] **Step 4: Commit**

```powershell
git add packages/next_dart_rfw
git commit -m "feat(rfw): scaffold next_dart_rfw adapter package

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task D.2: Neutral tree → rfw text codegen

**Files:**
- Create: `packages/next_dart_rfw/lib/src/rfw_codegen.dart`
- Test: `packages/next_dart_rfw/test/codegen_test.dart`

The generator emits an rfw remote-widget-library text that `import`s our `catalog` local library, declares one `widget` per composite component, and a `widget root`. Values: String → quoted; num/bool → literal; `NdArgRef` → `args.<name>`. Events → `onPressed: event "<action>" { ...args... }`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_rfw/src/rfw_codegen.dart';
import 'package:rfw/rfw.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated text parses as a valid rfw library', () {
    final content = EnvelopeContent(
      root: NdNode(type: 'Column', children: [
        NdNode(type: 'Text', props: {'text': 'Count: 0'}),
        NdNode(
          type: 'Button',
          props: {'label': 'Increment'},
          events: {'onPressed': NdActionRef('inc')},
        ),
        NdNode(type: 'ProductCard',
            props: {'title': 'Shoe', 'price': r'$10', 'id': 7}),
      ]),
      components: [
        NdComponentDef(name: 'ProductCard', params: ['title', 'price', 'id'],
          body: NdNode(type: 'Card', children: [
            NdNode(type: 'Column', children: [
              NdNode(type: 'Text', props: {'text': NdArgRef('title')}),
              NdNode(type: 'Text', props: {'text': NdArgRef('price')}),
              NdNode(type: 'Button', props: {'label': 'Buy'},
                events: {'onPressed': NdActionRef('buy', {'id': NdArgRef('id')})}),
            ]),
          ]),
        ),
      ],
    );
    final text = generateRfwText(content);
    // Must parse without throwing.
    final lib = parseLibraryFile(text);
    expect(lib.widgets.map((w) => w.name), contains('root'));
    expect(lib.widgets.map((w) => w.name), contains('ProductCard'));
  });

  test('strings are escaped and arg refs become args.x', () {
    final content = EnvelopeContent(
      root: NdNode(type: 'Text', props: {'text': r'a"b'}),
      components: [
        NdComponentDef(name: 'C', params: ['t'],
            body: NdNode(type: 'Text', props: {'text': NdArgRef('t')})),
      ],
    );
    final text = generateRfwText(content);
    expect(text, contains(r'args.t'));
    // The escaped quote survives parsing.
    expect(() => parseLibraryFile(text), returnsNormally);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/next_dart_rfw; flutter test test/codegen_test.dart`
Expected: FAIL — `rfw_codegen.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_rfw/lib/src/rfw_codegen.dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

const String kCatalogImport = 'catalog';

/// Generate an rfw remote-widget-library text from decoded protocol content.
String generateRfwText(EnvelopeContent content) {
  final buf = StringBuffer()..writeln('import $kCatalogImport;');
  for (final c in content.components) {
    buf.writeln('widget ${c.name} = ${_node(c.body)};');
  }
  buf.writeln('widget root = ${_node(content.root)};');
  return buf.toString();
}

String _node(NdNode n) {
  final args = <String>[];
  // Single-child widgets use `child:`; Column uses `children:`.
  if (n.type == 'Column') {
    args.add('children: [${n.children.map(_node).join(', ')}]');
  } else if (n.children.length == 1) {
    args.add('child: ${_node(n.children.single)}');
  }
  n.props.forEach((k, v) => args.add('$k: ${_value(v)}'));
  n.events.forEach((k, ref) => args.add('$k: ${_event(ref)}'));
  return '${n.type}(${args.join(', ')})';
}

String _event(NdActionRef ref) {
  final pairs = ref.args.entries.map((e) => '${e.key}: ${_value(e.value)}').join(', ');
  return 'event "${ref.action}" { $pairs }';
}

String _value(Object? v) {
  if (v is NdArgRef) return 'args.${v.name}';
  if (v is num || v is bool) return '$v';
  return _string('$v');
}

String _string(String s) {
  final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/codegen_test.dart`
Expected: PASS (2 tests).

> If `parseLibraryFile` rejects the `event "name" { }` form with empty braces, change `_event` to omit the braces when there are no args (emit `event "name" {}` vs `event "name" { k: v }`). The test will tell you.

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_rfw/lib/src/rfw_codegen.dart packages/next_dart_rfw/test/codegen_test.dart
git commit -m "feat(rfw): neutral tree to rfw text code generation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task D.3: Catalog widgets (LocalWidgetLibrary)

**Files:**
- Create: `packages/next_dart_rfw/lib/src/catalog_widgets.dart`
- Test: covered by the renderer test in D.4 (rendering exercises every catalog widget).

- [ ] **Step 1: Write minimal implementation**

```dart
// packages/next_dart_rfw/lib/src/catalog_widgets.dart
import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart';

/// The built-in next-dart widget catalog as an rfw local widget library.
/// Each builder wires `onPressed` to the rfw event mechanism via voidHandler,
/// so taps surface through RemoteWidget.onEvent.
LocalWidgetLibrary ndCatalog() => LocalWidgetLibrary(<String, LocalWidgetBuilder>{
      'Text': (context, source) => Text(
            source.v<String>(['text']) ?? '',
          ),
      'Column': (context, source) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: source.childList(['children']),
          ),
      'Padding': (context, source) => Padding(
            padding: EdgeInsets.all(source.v<double>(['all']) ?? 0),
            child: source.child(['child']),
          ),
      'Card': (context, source) => Card(child: source.child(['child'])),
      'Image': (context, source) => Image.network(source.v<String>(['src']) ?? ''),
      'Button': (context, source) => ElevatedButton(
            onPressed: source.voidHandler(['onPressed']),
            child: Text(source.v<String>(['label']) ?? ''),
          ),
    });
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```powershell
git add packages/next_dart_rfw/lib/src/catalog_widgets.dart
git commit -m "feat(rfw): built-in widget catalog as an rfw local library

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task D.4: RfwRenderer

**Files:**
- Create: `packages/next_dart_rfw/lib/src/rfw_renderer.dart`
- Test: `packages/next_dart_rfw/test/renderer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:next_dart_rfw/src/rfw_renderer.dart';

void main() {
  testWidgets('renders catalog widgets and fires actions', (tester) async {
    final captured = <String>[];
    final content = EnvelopeContent(
      root: NdNode(type: 'Column', children: [
        NdNode(type: 'Text', props: {'text': 'Count: 0'}),
        NdNode(type: 'Button', props: {'label': 'Increment'},
            events: {'onPressed': NdActionRef('inc')}),
      ]),
    );

    final renderer = RfwRenderer();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => renderer.render(context, content,
              (action, args) async => captured.add(action)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Count: 0'), findsOneWidget);
    expect(find.text('Increment'), findsOneWidget);

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(captured, ['inc']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/renderer_test.dart`
Expected: FAIL — `rfw_renderer.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// packages/next_dart_rfw/lib/src/rfw_renderer.dart
import 'package:flutter/widgets.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:rfw/rfw.dart';
import 'catalog_widgets.dart';
import 'rfw_codegen.dart';

/// The default next-dart render engine, backed by rfw. It is the ONLY place rfw
/// is referenced; swap it by implementing [NextDartRenderer] yourself.
class RfwRenderer extends NextDartRenderer {
  final Runtime _runtime = Runtime();
  final DynamicContent _data = DynamicContent();
  bool _catalogReady = false;

  static const LibraryName _main = LibraryName(['main']);
  static const LibraryName _catalog = LibraryName(['catalog']);

  void _ensureCatalog() {
    if (_catalogReady) return;
    _runtime.update(_catalog, ndCatalog());
    _catalogReady = true;
  }

  @override
  Widget render(BuildContext context, EnvelopeContent content,
      ActionDispatcher dispatch) {
    _ensureCatalog();
    final text = generateRfwText(content);
    _runtime.update(_main, parseLibraryFile(text));
    return RemoteWidget(
      runtime: _runtime,
      data: _data,
      widget: const FullyQualifiedWidgetName(_main, 'root'),
      onEvent: (name, arguments) {
        dispatch(name, Map<String, Object?>.from(arguments));
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/renderer_test.dart`
Expected: PASS (1 test).

> The remote text's `import catalog;` must match the registered `LibraryName(['catalog'])` and the `kCatalogImport` constant. If rfw reports an unresolved widget library, confirm those three names agree.

- [ ] **Step 5: Commit**

```powershell
git add packages/next_dart_rfw/lib/src/rfw_renderer.dart packages/next_dart_rfw/test/renderer_test.dart
git commit -m "feat(rfw): RfwRenderer implementing NextDartRenderer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task D.5: Public exports + suite

**Files:**
- Modify: `packages/next_dart_rfw/lib/next_dart_rfw.dart`

- [ ] **Step 1: Replace the export file**

```dart
// packages/next_dart_rfw/lib/next_dart_rfw.dart
library next_dart_rfw;

export 'src/rfw_renderer.dart';
export 'src/catalog_widgets.dart' show ndCatalog;
export 'src/rfw_codegen.dart' show generateRfwText;
```

- [ ] **Step 2: Run suite + analyze**

Run: `flutter test`
Expected: PASS.
Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```powershell
git add packages/next_dart_rfw/lib/next_dart_rfw.dart
git commit -m "feat(rfw): public exports; suite green

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Milestone E — Example app + integration

### Task E.1: Key generation tool + shared keys

**Files:**
- Create: `examples/counter_app/server/pubspec.yaml`
- Create: `examples/counter_app/server/tool/gen_keys.dart`
- Create: `examples/counter_app/server/lib/keys.dart`

- [ ] **Step 1: Create the server package pubspec**

```yaml
# examples/counter_app/server/pubspec.yaml
name: counter_server
description: Demo backend for the next-dart counter example.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  next_dart_server:
    path: ../../../packages/next_dart_server
  next_dart_protocol:
    path: ../../../packages/next_dart_protocol
  cryptography: ^2.9.0
  shelf: ^1.4.2
```

- [ ] **Step 2: Create `tool/gen_keys.dart`**

```dart
// examples/counter_app/server/tool/gen_keys.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Run once: `dart run tool/gen_keys.dart`. Paste the printed constants into
/// BOTH server/lib/keys.dart and app/lib/keys.dart so the client can verify and
/// decrypt what the server signs and encrypts.
Future<void> main() async {
  final kp = await Ed25519().newKeyPair();
  final seed = await kp.extractPrivateKeyBytes(); // 32-byte Ed25519 seed
  final pub = await kp.extractPublicKey();
  final secret = List<int>.generate(32, (i) => (i * 7 + 13) % 256);
  print("const signingSeedB64 = '${base64.encode(seed)}';");
  print("const signingPublicKeyB64 = '${base64.encode(pub.bytes)}';");
  print("const secretKeyB64 = '${base64.encode(secret)}';");
}
```

- [ ] **Step 3: Fetch deps and generate keys**

Run:
```powershell
cd examples/counter_app/server
dart pub get
dart run tool/gen_keys.dart
```
Expected: three `const ... = '...';` lines printed.

- [ ] **Step 4: Create `server/lib/keys.dart` from the printed output**

Paste the three printed lines into:

```dart
// examples/counter_app/server/lib/keys.dart
// Generated by tool/gen_keys.dart — keep identical to app/lib/keys.dart.
const signingSeedB64 = 'PASTE_FROM_GEN_KEYS';
const signingPublicKeyB64 = 'PASTE_FROM_GEN_KEYS';
const secretKeyB64 = 'PASTE_FROM_GEN_KEYS';
```

- [ ] **Step 5: Commit**

```powershell
git add examples/counter_app/server/pubspec.yaml examples/counter_app/server/tool/gen_keys.dart examples/counter_app/server/lib/keys.dart
git commit -m "feat(example): key generation tool and shared demo keys

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task E.2: Demo backend

**Files:**
- Create: `examples/counter_app/server/bin/server.dart`

- [ ] **Step 1: Write the backend**

```dart
// examples/counter_app/server/bin/server.dart
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'package:shelf/shelf_io.dart' as io;
import '../lib/keys.dart';

Future<NextDartApp> buildApp() async {
  final kp = await Ed25519().newKeyPairFromSeed(base64.decode(signingSeedB64));
  final secret = SecretKey(base64.decode(secretKeyB64));

  final productCard = ndComponent('ProductCard', ['title', 'price', 'id'], (a) {
    return ndCard(
      child: ndColumn([
        ndText(a('title')),
        ndText(a('price')),
        ndButton(label: 'Buy', onPressed: action('buy', {'id': a('id')})),
      ]),
    );
  });

  final app = NextDartApp(
    signingKeyPair: kp,
    secretKey: secret,
    keyId: 'demo',
    components: [productCard],
  );

  app.page('/', (ctx) {
    final count = ctx.state.get<int>('count', 0);
    final lastBought = ctx.state.get<String>('bought', '—');
    return ndColumn([
      ndText('Count: $count'),
      ndButton(label: 'Increment', onPressed: action('inc')),
      ndUse('ProductCard', {'title': 'Running Shoe', 'price': r'$79', 'id': 7}),
      ndText('Last bought id: $lastBought'),
    ]);
  });

  app.action('inc', (ctx) {
    ctx.state.update<int>('count', 0, (n) => n + 1);
  });
  app.action('buy', (ctx) {
    ctx.state.set('bought', '${ctx.args['id']}');
  });

  return app;
}

Future<void> main() async {
  final app = await buildApp();
  final server = await io.serve(app.handler, InternetAddress.anyIPv4, 8080);
  stdout.writeln('next-dart demo on http://${server.address.host}:${server.port}');
}
```

- [ ] **Step 2: Smoke-run the server**

Run: `dart run bin/server.dart` (then Ctrl+C)
Expected: prints "next-dart demo on http://0.0.0.0:8080" with no exceptions.

- [ ] **Step 3: Commit**

```powershell
git add examples/counter_app/server/bin/server.dart
git commit -m "feat(example): demo backend with counter + ProductCard composite

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task E.3: Integration test (in-process server + client loop)

**Files:**
- Create: `examples/counter_app/server/test/integration_test.dart`
- Modify: `examples/counter_app/server/pubspec.yaml` (add dev_dependencies)

- [ ] **Step 1: Add dev deps to `server/pubspec.yaml`**

Append:

```yaml
dev_dependencies:
  test: ^1.31.1
  http: ^1.2.0
  shelf: ^1.4.2
  next_dart_client:
    path: ../../../packages/next_dart_client
```

> Note: `next_dart_client` is a Flutter package, but its protocol-facing API used here (`NextDartClient`) only needs `dart:` + `http` + `cryptography`. If `dart test` fails to resolve the Flutter SDK dependency, instead place this integration test under `examples/counter_app/app/test/` and run it with `flutter test` (the app package already depends on both). Prefer that location if resolution complains.

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:test/test.dart';
import '../bin/server.dart' as backend;
import '../lib/keys.dart';

void main() {
  test('fetch page, increment, and buy through the real handler', () async {
    final app = await backend.buildApp();
    final handler = app.handler;

    // Bridge http -> shelf handler in-process.
    final mock = MockClient((req) async {
      final shelfReq = _toShelf(req);
      final res = await handler(shelfReq);
      final bytes = await res.read().expand((x) => x).toList();
      return http.Response.bytes(bytes, res.statusCode);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://demo'),
      signingPublicKey: SimplePublicKey(
          base64.decode(signingPublicKeyB64), type: KeyPairType.ed25519),
      secretKey: SecretKey(base64.decode(secretKeyB64)),
      httpClient: mock,
    );

    final page = await client.fetchPage('/');
    expect(page.root.children[0].props['text'], 'Count: 0');

    final afterInc = await client.dispatch('inc', const {}, route: '/');
    expect(afterInc.root.children[0].props['text'], 'Count: 1');

    final afterBuy =
        await client.dispatch('buy', const {'id': 7}, route: '/');
    expect(afterBuy.root.children[3].props['text'], 'Last bought id: 7');
  });
}

// Minimal http.Request -> shelf.Request bridge for the in-process test.
dynamic _toShelf(http.Request req) {
  // Imported lazily to avoid a top-level shelf import clash in the example.
  // ignore: implementation_imports
  return _shelfRequest(req.method, req.url, req.bodyBytes);
}
```

> The bridge needs a real `shelf.Request`. Replace the `_toShelf`/`_shelfRequest` placeholder with a direct construction at the top of the file:
>
> ```dart
> import 'package:shelf/shelf.dart' as shelf;
> shelf.Request _shelfRequest(String method, Uri url, List<int> body) =>
>     shelf.Request(method, url, body: body);
> ```
>
> and simplify `_toShelf` to `final shelfReq = _shelfRequest(req.method, req.url, req.bodyBytes);` inline. (Kept explicit here so the engineer wires the import.)

- [ ] **Step 3: Finalize the test imports and bridge**

Rewrite the top of the test to the clean form:

```dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import '../bin/server.dart' as backend;
import '../lib/keys.dart';

void main() {
  test('fetch page, increment, and buy through the real handler', () async {
    final app = await backend.buildApp();
    final handler = app.handler;

    final mock = MockClient((req) async {
      final shelfReq = shelf.Request(req.method, req.url, body: req.bodyBytes);
      final res = await handler(shelfReq);
      final bytes = await res.read().expand((x) => x).toList();
      return http.Response.bytes(bytes, res.statusCode);
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://demo'),
      signingPublicKey: SimplePublicKey(
          base64.decode(signingPublicKeyB64), type: KeyPairType.ed25519),
      secretKey: SecretKey(base64.decode(secretKeyB64)),
      httpClient: mock,
    );

    final page = await client.fetchPage('/');
    expect(page.root.children[0].props['text'], 'Count: 0');

    final afterInc = await client.dispatch('inc', const {}, route: '/');
    expect(afterInc.root.children[0].props['text'], 'Count: 1');

    final afterBuy = await client.dispatch('buy', const {'id': 7}, route: '/');
    expect(afterBuy.root.children[3].props['text'], 'Last bought id: 7');
  });
}
```

- [ ] **Step 4: Run the test**

Run: `cd examples/counter_app/server; dart pub get; dart test test/integration_test.dart`
Expected: PASS. (If Flutter-SDK resolution fails, move the file to `examples/counter_app/app/test/` per the note and run `flutter test`.)

- [ ] **Step 5: Commit**

```powershell
git add examples/counter_app/server/pubspec.yaml examples/counter_app/server/test/integration_test.dart
git commit -m "test(example): in-process integration loop (page/inc/buy)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task E.4: Flutter app

**Files:**
- Create: `examples/counter_app/app/pubspec.yaml`
- Create: `examples/counter_app/app/lib/keys.dart`
- Create: `examples/counter_app/app/lib/main.dart`

- [ ] **Step 1: Create the Flutter app scaffold**

Run:
```powershell
cd examples/counter_app
flutter create app
```
Expected: a Flutter app created under `app/`.

- [ ] **Step 2: Replace `app/pubspec.yaml` dependencies block**

Set the dependencies (keep the generated `name`, `environment`, `flutter:` asset section):

```yaml
dependencies:
  flutter:
    sdk: flutter
  next_dart_client:
    path: ../../../packages/next_dart_client
  next_dart_rfw:
    path: ../../../packages/next_dart_rfw
  cryptography: ^2.9.0
```

- [ ] **Step 3: Create `app/lib/keys.dart`**

Copy the SAME three constants generated in Task E.1:

```dart
// examples/counter_app/app/lib/keys.dart — identical to server/lib/keys.dart
const signingPublicKeyB64 = 'PASTE_SAME_AS_SERVER';
const secretKeyB64 = 'PASTE_SAME_AS_SERVER';
```

- [ ] **Step 4: Write `app/lib/main.dart`**

```dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:next_dart_rfw/next_dart_rfw.dart';
import 'keys.dart';

void main() {
  // For Android emulator use 10.0.2.2; for desktop/web/iOS-sim use localhost.
  final client = NextDartClient(
    baseUrl: Uri.parse('http://localhost:8080'),
    signingPublicKey: SimplePublicKey(
        base64.decode(signingPublicKeyB64), type: KeyPairType.ed25519),
    secretKey: SecretKey(base64.decode(secretKeyB64)),
  );
  runApp(MyApp(client: client));
}

class MyApp extends StatelessWidget {
  final NextDartClient client;
  const MyApp({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'next-dart demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('next-dart demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: NextDartView(
            source: client,
            route: '/',
            renderer: RfwRenderer(),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Analyze the app**

Run: `cd app; flutter pub get; flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Manual run instructions (verification, not automated)**

In one terminal: `cd examples/counter_app/server; dart run bin/server.dart`
In another: `cd examples/counter_app/app; flutter run -d windows` (or chrome).
Expected: the app shows "Count: 0", an Increment button (incrementing updates the number from the backend), a ProductCard with a Buy button, and "Last bought id: —" → "7" after Buy.

- [ ] **Step 7: Commit**

```powershell
git add examples/counter_app/app/pubspec.yaml examples/counter_app/app/lib/keys.dart examples/counter_app/app/lib/main.dart
git commit -m "feat(example): Flutter app rendering the server-driven UI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Milestone F — Docs (AI-friendliness)

### Task F.1: JSON Schema for the neutral tree

**Files:**
- Create: `docs/next_dart_tree.schema.json`

- [ ] **Step 1: Write the schema**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "next-dart neutral tree node",
  "$ref": "#/definitions/node",
  "definitions": {
    "node": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": { "type": "string", "description": "Catalog widget or composite name" },
        "props": { "type": "object" },
        "children": { "type": "array", "items": { "$ref": "#/definitions/node" } },
        "events": {
          "type": "object",
          "additionalProperties": { "$ref": "#/definitions/actionRef" }
        }
      },
      "additionalProperties": false
    },
    "actionRef": {
      "type": "object",
      "required": ["action"],
      "properties": {
        "action": { "type": "string" },
        "args": { "type": "object" }
      },
      "additionalProperties": false
    },
    "argRef": {
      "type": "object",
      "required": ["$arg"],
      "properties": { "$arg": { "type": "string" } },
      "additionalProperties": false
    }
  }
}
```

- [ ] **Step 2: Commit**

```powershell
git add docs/next_dart_tree.schema.json
git commit -m "docs: JSON Schema for the neutral tree

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task F.2: AI authoring guide

**Files:**
- Create: `docs/AI_GUIDE.md`

- [ ] **Step 1: Write the guide**

```markdown
# Authoring next-dart pages (for AI agents)

A page is a Dart function on the backend that returns a widget tree built from
the DSL in `package:next_dart_server`. The framework signs, encrypts, versions,
and serves it; the Flutter client renders it. You only write backend Dart.

## Primitives
- `ndText(String|argRef)` — text
- `ndColumn([children])` — vertical layout
- `ndCard(child: node)` — card container
- `ndPadding(all: double, child: node)` — uniform padding
- `ndImage(String|argRef src)` — network image
- `ndButton(label: String, onPressed: action('id', {args}))` — button

## Actions
`action('inc')` references a server action. Register it with
`app.action('inc', (ctx) { ctx.state.update<int>('count', 0, (n) => n + 1); });`
After an action runs, the page is rebuilt and re-sent automatically.

## Composite components (new component, backend-only — no client update)
```dart
final productCard = ndComponent('ProductCard', ['title', 'price', 'id'], (a) {
  return ndCard(child: ndColumn([
    ndText(a('title')),
    ndText(a('price')),
    ndButton(label: 'Buy', onPressed: action('buy', {'id': a('id')})),
  ]));
});
// register: NextDartApp(..., components: [productCard])
// use in a page: ndUse('ProductCard', {'title': 'Shoe', 'price': r'$10', 'id': 7})
```

## Rules
- Only widgets in the client catalog (the primitives above) or composites made
  from them can be used. A genuinely new *native* widget requires a client update.
- `argRef` (`a('x')`) is only valid inside a component body.
- Wire payloads are validated against `docs/next_dart_tree.schema.json`.
```

- [ ] **Step 2: Commit**

```powershell
git add docs/AI_GUIDE.md
git commit -m "docs: AI authoring guide

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

### Task G.1: Whole-repo green

- [ ] **Step 1: Run every package's tests**

Run:
```powershell
cd packages/next_dart_protocol; dart test
cd ../next_dart_server; dart test
cd ../next_dart_client; flutter test
cd ../next_dart_rfw; flutter test
cd ../../examples/counter_app/server; dart test
```
Expected: PASS in every package.

- [ ] **Step 2: Analyze every package**

Run the analyzer in each package directory (`dart analyze` for pure-Dart, `flutter analyze` for Flutter).
Expected: "No issues found!" everywhere.

- [ ] **Step 3: Confirm the rfw isolation invariant**

Run: `Select-String -Path packages/next_dart_protocol/**/*.dart, packages/next_dart_server/**/*.dart, packages/next_dart_client/**/*.dart -Pattern "package:rfw"`
Expected: NO matches (rfw appears only in `packages/next_dart_rfw`).

- [ ] **Step 4: Final commit / tag**

```powershell
git add -A
git commit -m "chore: Phase 1 MVP complete — all packages green

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git tag v0.1.0-mvp
```

---

## Self-Review (completed by plan author)

**1. Spec coverage:**
- §2 Goals → backend-driven UI (Milestone B), client-update-only-for-native (catalog + components D.2/D.3, AI guide F.2), store-safe (no code shipped — neutral tree A.3), secure-by-default (A.6/A.8), AI-friendly (F.1/F.2), render-agnostic core (C.2 interface, rfw isolated in D). ✓
- §5 Architecture & dependency rules → enforced by pubspecs (A.1/B.1/C.1/D.1) and verified in G.1 step 3. ✓
- §6 Wire protocol → A.8 envelope; payloadFormat 'json'; version negotiation (A.2 + A.8). ✓
- §7 Authoring DSL → B.2. ✓
- §8 Composite components → B.2 (`ndComponent`/`ndUse`), codegen D.2, example E.2. ✓
- §9 Security model → A.6/A.8 (Ed25519 sign+verify, AES-GCM, minClientVersion). TLS/cert-pinning is deployment-level; the MVP runs over plain http for localhost and the README/app note where pinning attaches (documented limitation, consistent with spec's "MVP simplification"). ✓
- §10 Action & data flow → server returns full updated tree (B.4); client re-renders (C.4 view). Patch/DynamicContent intentionally deferred (spec lists it as an option). ✓
- §11 Pluggable engine → C.2 interface; D RfwRenderer; G.1 isolation check. ✓
- §12 AI-friendliness → F.1/F.2. ✓
- §13 Example → E. §14 Testing → tests in every milestone. ✓

**Known intentional MVP scope notes (consistent with spec):** certificate pinning is wired at deployment (documented, not coded in MVP); state is per-process (single session); actions return full trees (no patches); `data`/DynamicContent reserved but empty. All match the spec's Phase-1 simplifications.

**2. Placeholder scan:** The only `PASTE_*` markers are in `keys.dart`, which are filled by running `tool/gen_keys.dart` in Task E.1 step 3 (concrete command + output shown). No code-step placeholders.

**3. Type consistency:** `EnvelopeContent`, `NdNode`, `NdActionRef`, `NdArgRef`, `NdComponentDef`, `encodeEnvelope`/`decodeEnvelope`, `NextDartClient.fetchPage/dispatch`, `NextDartSource`, `NextDartRenderer.render`, `ActionDispatcher`, `RfwRenderer`, `generateRfwText`, `ndCatalog`, DSL builders — names are used identically across producing and consuming tasks. `LibraryName(['catalog'])` ↔ `import catalog;` ↔ `kCatalogImport` agreement is called out in D.4.
