// packages/next_dart_server/lib/src/component_library.dart
import 'package:next_dart_protocol/next_dart_protocol.dart';

/// A named, versioned group of composite components.
///
/// All [components] in a library are stamped with [name] and [version] when
/// registered into a [ComponentRegistry], producing new [NdComponentDef]
/// instances — the originals are never mutated.
class ComponentLibrary {
  final String name;
  final String version;
  final List<NdComponentDef> components;

  const ComponentLibrary({
    required this.name,
    required this.version,
    required this.components,
  });
}

/// Merges flat components and named [ComponentLibrary] instances into a
/// single, deduplicated lookup table.
///
/// Rules:
/// - Components from a [ComponentLibrary] are re-wrapped with that library's
///   [library] and [libraryVersion] set (originals are not mutated).
/// - Components in [flatComponents] carry no library identity (library == null).
/// - If any two components share the same [NdComponentDef.name] — across flat
///   components or any library — a [StateError] is thrown at construction time.
class ComponentRegistry {
  final Map<String, NdComponentDef> _byName = {};

  ComponentRegistry({
    List<NdComponentDef> flatComponents = const [],
    List<ComponentLibrary> libraries = const [],
  }) {
    // Register flat (unnamed) components first.
    for (final def in flatComponents) {
      _register(def);
    }
    // Register library components, stamping library identity.
    for (final lib in libraries) {
      for (final def in lib.components) {
        final stamped = NdComponentDef(
          name: def.name,
          params: def.params,
          body: def.body,
          library: lib.name,
          libraryVersion: lib.version,
        );
        _register(stamped);
      }
    }
  }

  void _register(NdComponentDef def) {
    if (_byName.containsKey(def.name)) {
      throw StateError(
        'Duplicate component name "${def.name}": '
        'each component name must be unique across all registered components '
        'and libraries.',
      );
    }
    _byName[def.name] = def;
  }

  /// Returns the [NdComponentDef] registered under [name], or null.
  NdComponentDef? lookup(String name) => _byName[name];

  /// Returns all registered component definitions in registration order.
  List<NdComponentDef> all() => List.unmodifiable(_byName.values);
}
