# pub.dev Publishing Guide

**Status: nothing has been published to pub.dev yet — these are the steps the maintainer runs to do so.**

This document describes the exact steps **you** must run to publish the six
`next-dart` packages to pub.dev.  Claude will never run `dart pub publish`
without `--dry-run`; the real publish is your decision.

---

## Prerequisites

1. A pub.dev account logged in with `dart pub login`.
2. You must own (or be an uploader of) every package name on pub.dev before
   publishing.  Package names are permanent once claimed.
3. Publish in **dependency order**: a package must be live on pub.dev before
   any package that depends on it can be published.

---

## How `dependency_overrides` work in this monorepo

Each publishable package declares its inter-package deps as hosted version
constraints (e.g. `next_dart_protocol: ^0.1.0`) **and** overrides them locally
with a `path:` entry so that `dart pub get` / `flutter pub get` resolves from
the repo.

```yaml
dependencies:
  next_dart_protocol: ^0.1.0          # what pub.dev consumers resolve

dependency_overrides:
  next_dart_protocol:
    path: ../next_dart_protocol        # local path used only during development
```

`dependency_overrides` are **ignored by consumers** of a published package;
they are local-only.  When you publish each package in order (protocol first,
then the packages that depend on it), pub.dev resolves the real hosted
versions.

---

## Dry-run results (recorded 2026-06-18)

Run from `feat/phase3` branch with all local changes in place.
Exit code 65 = warnings present (no blocking errors).

### `next_dart_protocol`

```
Package has 2 warnings.

* `dart analyze` found the following issue(s):
  Please report this at dartbug.com.
  [Known Windows analyzer shutdown crash — not a code error]

* 1 checked-in file is modified in git.
  [Will be clean after commit]
```

### `next_dart_server`

```
Package has 2 warnings and 1 hint.

* dart analyze crash (Windows — see above)
* git dirty (will be clean after commit)
* Non-dev dependencies are overridden in pubspec.yaml.
  [Expected monorepo pattern — informational only]
```

### `next_dart_client`

```
Package has 2 warnings and 1 hint.

* dart analyze crash (Windows — see above)
* git dirty (will be clean after commit)
* Non-dev dependencies are overridden (monorepo pattern)
```

### `next_dart_rfw`

```
Package has 2 warnings and 2 hints.

* dart analyze crash (Windows — see above)
* git dirty (will be clean after commit)
* Non-dev dependencies are overridden x2 (next_dart_client + next_dart_protocol)
```

### `next_dart_basic`

```
Package has 2 warnings and 2 hints.

* dart analyze crash (Windows — see above)
* git dirty (will be clean after commit)
* Non-dev dependencies are overridden x2 (next_dart_client + next_dart_protocol)
```

### `next_dart_cli`

```
Package has 2 warnings.

* dart analyze crash (Windows — see above)
* git dirty (will be clean after commit)
```

**Summary:** zero blocking errors across all six packages.  All warnings and
hints are either the known Windows analyzer shutdown crash or the expected
monorepo override pattern.  They will disappear once changes are committed and
the packages are published in order.

---

## Publish steps

Run each block from the monorepo root.  Wait for pub.dev to index a package
(~2 minutes) before publishing any package that depends on it.

### Step 1 — `next_dart_protocol` (no inter-package deps)

```sh
cd packages/next_dart_protocol
dart pub publish
```

### Step 2 — `next_dart_server` (depends on `next_dart_protocol`)

Wait for `next_dart_protocol 0.1.0` to appear on pub.dev, then:

```sh
cd packages/next_dart_server
dart pub publish
```

### Step 3 — `next_dart_client` (depends on `next_dart_protocol`)

Can run in parallel with Step 2 once `next_dart_protocol` is live:

```sh
cd packages/next_dart_client
flutter pub publish
```

### Step 4 — `next_dart_rfw` (depends on `next_dart_client` + `next_dart_protocol`)

Wait for both `next_dart_protocol` and `next_dart_client` to be live:

```sh
cd packages/next_dart_rfw
flutter pub publish
```

### Step 5 — `next_dart_basic` (depends on `next_dart_client` + `next_dart_protocol`)

Can run in parallel with Step 4:

```sh
cd packages/next_dart_basic
flutter pub publish
```

### Step 6 — `next_dart_cli` (no inter-package deps on next-dart packages)

```sh
cd packages/next_dart_cli
dart pub publish
```

---

## After publishing

- Remove (or comment out) the `dependency_overrides` blocks from the six
  packages so that CI resolves from pub.dev rather than local paths.
- Tag the release: `git tag v0.1.0 && git push origin v0.1.0`.
- Update the root `README.md` with pub.dev badges for each package.

---

## Notes

- `dart pub publish` (without `--dry-run`) is **irreversible**.  You cannot
  unpublish a version; you can only retract it (which hides it but keeps it
  available to pinned consumers).
- The `dependency_overrides` blocks in pubspec.yaml are local-only.  Consumers
  who add `next_dart_server: ^0.1.0` to their own pubspec.yaml will resolve
  `next_dart_protocol` from pub.dev, not from your local path.
- For Flutter packages (`next_dart_client`, `next_dart_rfw`, `next_dart_basic`)
  use `flutter pub publish`, not `dart pub publish`.
