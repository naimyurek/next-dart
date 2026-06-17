# next_dart_rfw

The rfw render engine for [next-dart](https://github.com/naimyurek/next-dart) — a server-driven UI framework for Flutter.

Implements `NextRenderer` using Flutter's `package:rfw` (remote_flutter_widgets), enabling declarative remote widget trees that can be hot-swapped without a full rebuild. This is the only next-dart package that depends on rfw.

## Install

```yaml
dependencies:
  next_dart_rfw: ^0.1.0
```

## Usage

```dart
import 'package:next_dart_client/next_dart_client.dart';
import 'package:next_dart_rfw/next_dart_rfw.dart';

final client = NextClient(
  baseUrl: 'http://localhost:8080',
  renderer: RfwRenderer(),
);

await client.navigate('/home');
```

## Links

- [Repository](https://github.com/naimyurek/next-dart)
- [Issue tracker](https://github.com/naimyurek/next-dart/issues)
- [Changelog](CHANGELOG.md)
