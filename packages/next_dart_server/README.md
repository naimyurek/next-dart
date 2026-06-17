# next_dart_server

The server-side package for [next-dart](https://github.com/naimyurek/next-dart) — a server-driven UI framework for Flutter.

Provides an authoring DSL for building server-driven UI trees and a ready-made `package:shelf` router that serves signed/encrypted `NextEnvelope` responses to Flutter clients.

## Install

```yaml
dependencies:
  next_dart_server: ^0.1.0
```

## Usage

```dart
import 'package:next_dart_server/next_dart_server.dart';

void main() async {
  final app = NextApp(
    keyPair: await CryptoService().generateKeyPair(),
  );

  app.page('/home', (req) => NextNode(
    type: 'Column',
    children: [
      NextNode(type: 'Text', props: {'value': 'Welcome!'}),
    ],
  ));

  await app.serve(port: 8080);
}
```

## Links

- [Repository](https://github.com/naimyurek/next-dart)
- [Issue tracker](https://github.com/naimyurek/next-dart/issues)
- [Changelog](CHANGELOG.md)
