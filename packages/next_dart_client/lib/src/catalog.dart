import 'package:flutter/widgets.dart';

/// Builds a native widget for a catalog entry. [resolveChild]/[resolveChildren]
/// let a builder embed already-rendered child widgets; [fire] triggers a named
/// event with args. A concrete renderer supplies these callbacks.
typedef CatalogBuilder = Widget Function(CatalogNode node);

/// What a [CatalogBuilder] receives. Renderer-agnostic so apps can register
/// widgets without referencing rfw.
abstract class CatalogNode {
  T? prop<T>(String key);
  Widget? child(String key);
  List<Widget> children(String key);
  VoidCallback? event(String key);
}

/// A registry of custom native widgets, keyed by node type. A renderer consults
/// this before falling back to its built-in catalog, so apps extend the UI
/// vocabulary without forking the renderer.
class WidgetCatalog {
  final Map<String, CatalogBuilder> _builders = {};
  void register(String type, CatalogBuilder builder) => _builders[type] = builder;
  CatalogBuilder? operator [](String type) => _builders[type];
  Iterable<String> get types => _builders.keys;
}
