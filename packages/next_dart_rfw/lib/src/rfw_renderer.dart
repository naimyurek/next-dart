// packages/next_dart_rfw/lib/src/rfw_renderer.dart
import 'package:flutter/widgets.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:rfw/rfw.dart';
// parseLibraryFile is intentionally hidden by package:rfw/rfw.dart (to
// discourage client-side text parsing); it is only exported by
// package:rfw/formats.dart. We `show` just that one symbol so the rest of the
// rfw runtime surface keeps coming from package:rfw/rfw.dart without conflicts.
import 'package:rfw/formats.dart' show parseLibraryFile;
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
      NdActionDispatcher dispatch) {
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
