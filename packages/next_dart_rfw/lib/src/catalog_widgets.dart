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
      // Streaming placeholder: a passthrough of its single child. The codegen
      // emits a Slot's one child as `child:` (it is a non-Column single-child
      // node), so the fallback — or patched content — renders directly.
      'Slot': (context, source) => source.child(['child']),
      'Image': (context, source) {
        final src = source.v<String>(['src']) ?? '';
        return src.isEmpty ? const SizedBox.shrink() : Image.network(src);
      },
      'Button': (context, source) => ElevatedButton(
            onPressed: source.voidHandler(['onPressed']),
            child: Text(source.v<String>(['label']) ?? ''),
          ),
    });
