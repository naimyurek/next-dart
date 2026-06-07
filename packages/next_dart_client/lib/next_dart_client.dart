// packages/next_dart_client/lib/next_dart_client.dart
library next_dart_client;

export 'package:next_dart_protocol/next_dart_protocol.dart'
    show EnvelopeContent, NdNode, NdActionRef, NdArgRef, NdComponentDef;
export 'src/renderer.dart';
export 'src/catalog.dart';
export 'src/source.dart';
export 'src/client.dart';
// The hide only deduplicates these re-exported names; they remain public via src/source.dart.
export 'src/view.dart' hide NdActionDispatcher, NextDartSource;
