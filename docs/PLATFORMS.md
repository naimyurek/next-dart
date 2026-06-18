# Platform support

## Pure-Dart packages

The following packages have **no Flutter dependency** and run anywhere Dart runs —
server processes, CLI tools, CI workers, and native apps:

| Package | Role |
|---|---|
| `next_dart_protocol` | Neutral tree, crypto envelope, versioning |
| `next_dart_server` | Authoring DSL + Shelf HTTP endpoints |
| `next_dart_cli` | `next_dart` CLI — `new` / `dev` / `doctor` |

These packages can be used in pure-Dart server deployments, Docker containers,
and CI pipelines without Flutter installed (though the CI workflow here uses
`flutter-action` so both `dart` and `flutter` are available in a single job).

## Flutter packages

The following packages depend on the Flutter SDK and run on every Flutter target:

| Package | Role | Flutter targets |
|---|---|---|
| `next_dart_client` | Fetch / verify / decrypt + renderer interface | Android, iOS, web, Windows, macOS, Linux |
| `next_dart_rfw` | rfw-backed renderer | Android, iOS, web, Windows, macOS, Linux |
| `next_dart_basic` | Dependency-free reference renderer | Android, iOS, web, Windows, macOS, Linux |

## Example app

The example app in `examples/counter_app/app` was scaffolded with **web and
Windows** platforms enabled. The currently committed platform directories are
`web/` and `windows/`.

To add another platform (e.g. macOS, Linux, Android, iOS), run Flutter's
platform-add command from the app directory:

```bash
cd examples/counter_app/app
flutter create --platforms=macos .   # adds macos/
flutter create --platforms=linux .   # adds linux/
flutter create --platforms=android . # adds android/
flutter create --platforms=ios .     # adds ios/
```

Then commit the generated platform directories and update this document.

## CI coverage note

The CI workflow (`flutter-action`) runs on **Linux only**. The table above lists
the Flutter targets each package *supports* based on its dependencies; those
targets are not individually exercised in CI.

## App Store / Play Store compliance

next-dart ships **no executable binary code** to the client device. The server
sends a signed, encrypted, versioned *declarative tree* (JSON or binary)
describing the UI. The Flutter app parses that tree at runtime using the `rfw`
package and renders it with a fixed set of native widgets that are already
bundled in the app binary reviewed by the store.

Because no executable binary ever crosses the network boundary — only a
declarative data format interpreted by native code — next-dart applications are
designed to remain compliant with Apple App Store Review Guidelines (§2.5.2 and
§4.7) and Google Play Developer Policy (no dynamic code loading). Adding a
widget that the store would flag still requires a client update and a new store
review, but changing layout, text, colors, component ordering, and behavior
defined entirely within the declarative tree does not.
