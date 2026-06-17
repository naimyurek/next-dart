# next_dart_basic

The lightweight render engine for [next-dart](https://github.com/naimyurek/next-dart) — a server-driven UI framework for Flutter.

Implements `NextRenderer` using plain Flutter widgets with no rfw dependency. Ideal for projects that want a minimal dependency footprint or a simple starting point before adopting the rfw engine.

## Install

```yaml
dependencies:
  next_dart_basic: ^0.1.0
```

## Usage

```dart
import 'package:next_dart_client/next_dart_client.dart';
import 'package:next_dart_basic/next_dart_basic.dart';

final client = NextClient(
  baseUrl: 'http://localhost:8080',
  renderer: BasicRenderer(),
);

await client.navigate('/home');
```

## Links

- [Repository](https://github.com/naimyurek/next-dart)
- [Issue tracker](https://github.com/naimyurek/next-dart/issues)
- [Changelog](CHANGELOG.md)
