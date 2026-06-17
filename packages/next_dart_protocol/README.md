# next_dart_protocol

The shared protocol layer for [next-dart](https://github.com/naimyurek/next-dart) — a server-driven UI framework for Flutter.

This package defines the **neutral declarative tree** (`NextNode`), the **signed/encrypted envelope** (`NextEnvelope`), versioning types, and the `CryptoService` used by both server and client packages. It has zero Flutter dependencies and can be used in pure-Dart servers and clients alike.

## Install

```yaml
dependencies:
  next_dart_protocol: ^0.1.0
```

## Usage

```dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

// Build a simple UI tree
final tree = NextNode(
  type: 'Column',
  children: [
    NextNode(type: 'Text', props: {'value': 'Hello, world!'}),
  ],
);

// Sign and encrypt into an envelope
final crypto = CryptoService();
final keyPair = await crypto.generateKeyPair();
final envelope = await crypto.seal(tree, keyPair);
```

## Links

- [Repository](https://github.com/naimyurek/next-dart)
- [Issue tracker](https://github.com/naimyurek/next-dart/issues)
- [Changelog](CHANGELOG.md)
