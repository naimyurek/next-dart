# next_dart_client

The Flutter core client for [next-dart](https://github.com/naimyurek/next-dart) — a server-driven UI framework for Flutter.

Handles the handshake, fetch, decrypt, verify cycle and exposes a `NextRenderer` interface so any render engine (rfw, basic, or custom) can be plugged in. Includes automatic session-key refresh and exponential back-off retry.

## Install

```yaml
dependencies:
  next_dart_client: ^0.1.0
```

## Usage

```dart
import 'package:next_dart_client/next_dart_client.dart';

final client = NextClient(
  baseUrl: 'http://localhost:8080',
  renderer: MyRenderer(), // implements NextRenderer
);

// Fetch and render the /home page
await client.navigate('/home');
```

## Links

- [Repository](https://github.com/naimyurek/next-dart)
- [Issue tracker](https://github.com/naimyurek/next-dart/issues)
- [Changelog](CHANGELOG.md)
