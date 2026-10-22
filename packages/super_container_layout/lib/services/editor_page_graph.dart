import 'package:shortid/shortid.dart';

import '../models/native_component_config.dart';
import '../models/registry.dart';
import '../models/scaffold_page_config.dart';
import '../models/super_layout_config.dart';
import '../models/super_value_config.dart';
import '../models/super_list_view_config.dart';
import '../theme/appearance.dart';
import '../theme/container_style.dart';

/// Result of [EditorPageGraph.removal].
class EditorPageRemoval {
  EditorPageRemoval({
    required this.appearance,
    required Set<EditorConfigRef> removed,
    required Set<EditorConfigRef> preserved,
    required List<String> limitations,
  }) : removed = Set.unmodifiable(removed),
       preserved = Set.unmodifiable(preserved),
       limitations = List.unmodifiable(limitations);

  final Appearance appearance;

  /// Configurations exclusively owned by the page, now deleted.
  final Set<EditorConfigRef> removed;

  /// Configurations reachable from the page but kept because they are shared
  /// with another page or with configurations outside the page.
  final Set<EditorConfigRef> preserved;

  /// Data whose ownership is unknown and was therefore kept.
  final List<String> limitations;
}

/// Ownership and traversal of the persisted design graph of an editor page.
///
/// The root of a page is `nativeComponents[pageId]` (and its legacy
/// `scaffoldPages[pageId]`). Its placements are followed through native
/// components and layouts (placements, hidden regions/zones, grids, labels and
/// sizes) into the configurations declared by each component's
/// [ComponentDuplicationContract]. Runtime controllers are never read.
abstract final class EditorPageGraph {
  static List<EditorConfigRef> _roots(String pageId) => [
    EditorConfigRef.nativeComponent(pageId),
    EditorConfigRef.scaffoldPage(pageId),
  ];

  /// Copies the graph of [sourcePageId] under [targetPageId] with new,
  /// unique instance IDs. The page catalog is left unchanged.
  ///
  /// Throws a [FormatException] without changing anything when the graph
  /// contains a component without duplication contract, an unknown
  /// component, a cycle, or when [targetPageId] already has configurations.
  static Appearance duplicate({
    required Appearance appearance,
    required Registry registry,
    required String sourcePageId,
    required String targetPageId,
    String Function()? generateId,
  }) {
    if (sourcePageId.trim().isEmpty || targetPageId.trim().isEmpty) {
      throw const FormatException('Identifiant de page vide.');
    }
    if (sourcePageId == targetPageId) {
      throw const FormatException(
        'La copie doit avoir un identifiant different de la page source.',
      );
    }
    if (_roots(targetPageId).any((ref) => _read(appearance, ref) != null)) {
      throw FormatException(
        'Impossible de dupliquer la page : « $targetPageId » a deja une configuration.',
      );
    }
    final graph = _Graph.build(appearance, registry, _roots(sourcePageId));
    if (graph.cycles.isNotEmpty) {
      throw FormatException(
        'Impossible de dupliquer la page : la disposition contient un cycle '
        '(${graph.cycles.first}).',
      );
    }
    for (final instance in graph.instances.values) {
      if (instance.types.length > 1) {
        throw FormatException(
          'Impossible de dupliquer la page : l\'instance « ${instance.id} » '
          'a plusieurs types (${instance.types.join(', ')}).',
        );
      }
      final message = switch (instance.status) {
        _Status.unknown =>
          'le composant « ${instance.label} » est introuvable dans le registre',
        _Status.unsupported =>
          'le composant personnalise « ${instance.label} » ne fournit pas de '
              'contrat de duplication',
        _ => null,
      };
      if (message != null) {
        throw FormatException('Impossible de dupliquer la page : $message.');
      }
    }

    final next = generateId ?? () => shortid.generate();
    final used = _usedIds(appearance)..add(targetPageId);
    final ids = <String, String>{sourcePageId: targetPageId};
    final refs = <EditorConfigRef, EditorConfigRef>{
      for (final root in _roots(sourcePageId))
        root: EditorConfigRef(root.kind, targetPageId),
    };
    void map(String from, String to) {
      final previous = ids[from];
      if (previous != null && previous != to) {
        throw FormatException(
          'Impossible de dupliquer la page : l\'identifiant « $from » est '
          'utilise par plusieurs instances.',
        );
      }
      ids[from] = to;
    }

    for (final instance in graph.instances.values) {
      final contract = instance.contract;
      if (contract == null) continue;
      final source = contract.ownedConfigs(instance.id);
      for (var attempt = 0; ; attempt++) {
        if (attempt == 1000) {
          throw StateError('Unable to generate a unique component ID.');
        }
        final id = next();
        if (id.trim().isEmpty || used.contains(id)) continue;
        final target = contract.ownedConfigs(id);
        if (target.length != source.length ||
            [
              for (var i = 0; i < source.length; i++)
                target[i].kind != source[i].kind,
            ].any((different) => different)) {
          throw FormatException(
            'Contrat de duplication invalide pour « ${instance.label} ».',
          );
        }
        if (target.any(
          (ref) =>
              _read(appearance, ref) != null ||
              (ref.id != id && used.contains(ref.id)),
        )) {
          continue;
        }
        map(instance.id, id);
        used.add(id);
        for (var i = 0; i < source.length; i++) {
          if (source[i].id != instance.id) map(source[i].id, target[i].id);
          refs[source[i]] = target[i];
          used.add(target[i].id);
        }
        break;
      }
    }

    String remap(String id) => ids[id] ?? id;
    final owned = {
      for (final entry in ids.entries)
        if (entry.key != entry.value) entry.key,
    };
    final copies = <EditorConfigRef, Object>{};
    for (final ref in graph.configs) {
      final value = _read(appearance, ref)!;
      final copier = graph.owners[ref]
          ?.map((id) => graph.instances[id]!.contract?.copyConfig)
          .whereType<EditorConfigCopier>()
          .firstOrNull;
      final copy = copier == null
          ? _copy(value, remap)
          : copier(ref, value, remap);
      if (!_hasKind(copy, ref.kind)) {
        throw FormatException(
          'Copie invalide de la configuration ${ref.kind.name} « ${ref.id} ».',
        );
      }
      final leaked = _slots(ref.kind, copy).keys.where(owned.contains);
      if (leaked.isNotEmpty) {
        throw FormatException(
          'Copie invalide : « ${ref.id} » reference encore « ${leaked.first} ».',
        );
      }
      copies[refs[ref]!] = copy;
    }
    return _write(appearance, copies: copies);
  }

  /// Removes the configurations exclusively owned by [pageId].
  static Appearance remove({
    required Appearance appearance,
    required Registry registry,
    required String pageId,
  }) => removal(
    appearance: appearance,
    registry: registry,
    pageId: pageId,
  ).appearance;

  /// Same as [remove], with the list of deleted and preserved data.
  ///
  /// A configuration is deleted only when every container placing its owner
  /// is itself deleted and no other page of `appearance.pageCatalog` reaches
  /// it. Data of components without contract is never guessed nor deleted.
  static EditorPageRemoval removal({
    required Appearance appearance,
    required Registry registry,
    required String pageId,
  }) {
    final graph = _Graph.build(appearance, registry, _roots(pageId));
    final protected = _Graph.build(appearance, registry, [
      for (final page in appearance.pageCatalog.pages)
        if (page.id != pageId) ..._roots(page.id),
    ]).configs;
    final candidates = _exclusive(
      appearance,
      registry,
      {...graph.configs}..removeAll(protected),
    );
    final limitations = [
      for (final instance in graph.instances.values)
        if (instance.status == _Status.unsupported ||
            instance.status == _Status.unknown)
          'Donnees eventuelles du composant « ${instance.label} » '
              '(instance « ${instance.id} ») conservees : '
              'propriete inconnue.',
    ];
    return EditorPageRemoval(
      appearance: _write(appearance, removed: candidates),
      removed: candidates,
      preserved: {...graph.configs}..removeAll(candidates),
      limitations: limitations,
    );
  }

  /// Deletes, recursively, the configurations owned by the slot instance
  /// [instanceId] of [type] once it has been unplaced from its container of
  /// [containerKind] in [appearance].
  ///
  /// Nothing is deleted while the instance is still placed somewhere, nor for
  /// components without [ComponentDuplicationContract]. Descendant
  /// configurations shared with remaining containers or reachable from a page
  /// of the catalog are kept.
  static Appearance removeInstance({
    required Appearance appearance,
    required Registry registry,
    required String instanceId,
    required String type,
    required EditorConfigKind containerKind,
  }) {
    final placed = _allRefs(appearance).any(
      (ref) =>
          _slots(ref.kind, _read(appearance, ref)!).containsKey(instanceId),
    );
    if (placed) return appearance;
    final contract = _resolve(registry, type, containerKind).contract;
    if (contract == null) return appearance;
    final graph = _Graph.build(
      appearance,
      registry,
      contract.ownedConfigs(instanceId),
    );
    final protected = _Graph.build(appearance, registry, [
      for (final page in appearance.pageCatalog.pages) ..._roots(page.id),
    ]).configs;
    final candidates = _exclusive(
      appearance,
      registry,
      {...graph.configs}..removeAll(protected),
    );
    if (candidates.isEmpty) return appearance;
    return _write(appearance, removed: candidates);
  }

  /// Keeps only the [candidates] whose owners are placed exclusively inside
  /// other candidates.
  static Set<EditorConfigRef> _exclusive(
    Appearance appearance,
    Registry registry,
    Set<EditorConfigRef> candidates,
  ) {
    final containers = <String, Set<EditorConfigRef>>{};
    final owners = <EditorConfigRef, Set<String>>{};
    for (final ref in _allRefs(appearance)) {
      final value = _read(appearance, ref)!;
      for (final MapEntry(key: id, value: type) in _slots(
        ref.kind,
        value,
      ).entries) {
        containers.putIfAbsent(id, () => {}).add(ref);
        final contract = _resolve(registry, type, ref.kind).contract;
        for (final owned in contract?.ownedConfigs(id) ?? const []) {
          owners.putIfAbsent(owned, () => {}).add(id);
        }
      }
    }
    for (var changed = true; changed;) {
      changed = false;
      for (final ref in candidates.toList()) {
        final shared = (owners[ref] ?? const <String>{}).any(
          (id) => (containers[id] ?? const <EditorConfigRef>{}).any(
            (ref) => !candidates.contains(ref),
          ),
        );
        if (shared) changed = candidates.remove(ref);
      }
    }
    return candidates;
  }
}

enum _Status { supplied, contract, unsupported, unknown }

class _Instance {
  _Instance(this.id, this.label, this.status, this.contract);

  final String id;
  final String label;
  final _Status status;
  final ComponentDuplicationContract? contract;
  final types = <String>{};
}

class _Graph {
  final configs = <EditorConfigRef>{};
  final instances = <String, _Instance>{};
  final owners = <EditorConfigRef, Set<String>>{};
  final cycles = <String>[];

  static _Graph build(
    Appearance appearance,
    Registry registry,
    Iterable<EditorConfigRef> roots,
  ) {
    final graph = _Graph();
    final stack = <EditorConfigRef>[];
    void visit(EditorConfigRef ref) {
      final value = _read(appearance, ref);
      if (value == null) return;
      if (stack.contains(ref)) {
        graph.cycles.add([...stack, ref].join(' > '));
        return;
      }
      if (!graph.configs.add(ref)) return;
      stack.add(ref);
      for (final MapEntry(key: id, value: type) in _slots(
        ref.kind,
        value,
      ).entries) {
        final resolved = _resolve(registry, type, ref.kind);
        final instance = graph.instances.putIfAbsent(
          id,
          () =>
              _Instance(id, resolved.label, resolved.status, resolved.contract),
        )..types.add(type);
        for (final owned in instance.contract?.ownedConfigs(id) ?? const []) {
          if (_read(appearance, owned) == null) continue;
          graph.owners.putIfAbsent(owned, () => {}).add(id);
          visit(owned);
        }
      }
      stack.removeLast();
    }

    roots.forEach(visit);
    return graph;
  }
}

typedef _Resolution = ({
  String label,
  _Status status,
  ComponentDuplicationContract? contract,
});

_Resolution _resolve(Registry registry, String type, EditorConfigKind kind) {
  _Resolution found(String label, ComponentDuplicationContract? contract) => (
    label: label,
    status: contract == null ? _Status.unsupported : _Status.contract,
    contract: contract,
  );
  String? decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return null;
    }
  }

  const registryPrefix = 'registry:';
  if (kind == EditorConfigKind.layout) {
    // Same lookup order as SuperLayout: factories, then registered components.
    var rest = type;
    while (rest.startsWith(registryPrefix)) {
      rest = rest.substring(registryPrefix.length);
    }
    final key = type.startsWith('factory:')
        ? type.substring('factory:'.length)
        : rest == type
        ? null
        : decode(rest);
    if (registry.registry[key] case final factory?) {
      return found(key!, factory.duplication);
    }
    for (final entry in registry.components.entries) {
      final component = entry.value;
      if (component.slotId == type ||
          type == 'component:${component.slotId ?? entry.key}' ||
          key == entry.key) {
        return found(component.label, component.duplication);
      }
    }
    return key == null && !type.startsWith('component:')
        ? (label: type, status: _Status.supplied, contract: null)
        : (label: key ?? type, status: _Status.unknown, contract: null);
  }
  // Same lookup order as NativeComponentEditor.
  for (final entry in registry.components.entries) {
    final component = entry.value;
    if (type == 'component:${component.slotId ?? entry.key}' ||
        type == component.slotId ||
        type == '$registryPrefix${Uri.encodeComponent(entry.key)}') {
      return found(component.label, component.duplication);
    }
  }
  final key = type.startsWith('factory:')
      ? type.substring('factory:'.length)
      : type.startsWith(registryPrefix)
      ? decode(type.substring(registryPrefix.length))
      : null;
  if (registry.registry[key] case final factory?) {
    return found(key!, factory.duplication);
  }
  if (key != null || type.startsWith('component:')) {
    return (label: key ?? type, status: _Status.unknown, contract: null);
  }
  return (label: type, status: _Status.supplied, contract: null);
}

Object? _read(Appearance appearance, EditorConfigRef ref) => switch (ref.kind) {
  EditorConfigKind.layout => appearance.layouts[ref.id],
  EditorConfigKind.style => appearance.styles[ref.id],
  EditorConfigKind.nativeComponent => appearance.nativeComponents[ref.id],
  EditorConfigKind.scaffoldPage => appearance.scaffoldPages[ref.id],
  EditorConfigKind.value => appearance.valueComponents[ref.id],
  EditorConfigKind.list => appearance.listComponents[ref.id],
};

bool _hasKind(Object value, EditorConfigKind kind) => switch (kind) {
  EditorConfigKind.layout => value is SuperLayoutConfig,
  EditorConfigKind.style => value is ContainerStyle,
  EditorConfigKind.nativeComponent => value is NativeComponentConfig,
  EditorConfigKind.scaffoldPage => value is ScaffoldPageConfig,
  EditorConfigKind.value => value is SuperValueConfig,
  EditorConfigKind.list => value is SuperListViewConfig,
};

Iterable<EditorConfigRef> _allRefs(Appearance appearance) => [
  for (final id in appearance.layouts.keys) EditorConfigRef.layout(id),
  for (final id in appearance.styles.keys) EditorConfigRef.style(id),
  for (final id in appearance.nativeComponents.keys)
    EditorConfigRef.nativeComponent(id),
  for (final id in appearance.scaffoldPages.keys)
    EditorConfigRef.scaffoldPage(id),
  for (final id in appearance.valueComponents.keys) EditorConfigRef.value(id),
  for (final id in appearance.listComponents.keys) EditorConfigRef.list(id),
];

Set<String> _usedIds(Appearance appearance) => {
  for (final ref in _allRefs(appearance)) ...[
    ref.id,
    ..._slots(ref.kind, _read(appearance, ref)!).keys,
  ],
  for (final page in appearance.pageCatalog.pages) page.id,
};

/// Every slot instance ID of a container (placed, hidden or only sized) with
/// its type; empty for non-container values.
Map<String, String> _slots(EditorConfigKind kind, Object value) {
  if (value is ScaffoldPageConfig) return _slots(kind, value.native);
  if (value is NativeComponentConfig) {
    return {
      for (final id in {
        ...value.placements.values.expand((ids) => ids),
        ...value.slotTypes.keys,
        ...value.slotPreferredSizes.keys,
        ...value.slotSizeConstraints.keys,
        ...value.slotLabels.keys,
      })
        id: value.slotTypeOf(id),
    };
  }
  if (value is SuperLayoutConfig) {
    return {
      for (final id in {
        ...value.placements.values.expand((ids) => ids),
        ...value.slotTypes.keys,
        ...value.slotPreferredSizes.keys,
        ...value.slotSizeConstraints.keys,
        ...value.slotLabels.keys,
        ...?value.grid?.items.keys,
      })
        id: value.slotTypeOf(id),
    };
  }
  return const {};
}

Map<String, V> _remapKeys<V>(
  Map<String, V> map,
  String Function(String) remap,
) => Map.unmodifiable({
  for (final entry in map.entries) remap(entry.key): entry.value,
});

/// Explicit types for remapped IDs that were implicitly typed by their ID.
Map<String, String> _remapTypes(
  Map<String, String> slots,
  Map<String, String> types,
  String Function(String) remap,
) => Map.unmodifiable({
  ..._remapKeys(types, remap),
  for (final MapEntry(key: id, value: type) in slots.entries)
    if (remap(id) != type) remap(id): type,
});

Object _copy(Object value, String Function(String) remap) {
  if (value is ScaffoldPageConfig) {
    return ScaffoldPageConfig.fromNative(
      _copy(value.native, remap) as NativeComponentConfig,
    );
  }
  if (value is NativeComponentConfig) {
    return NativeComponentConfig(
      useDefaultNavigation: value.useDefaultNavigation,
      placements: {
        for (final entry in value.placements.entries)
          entry.key: [for (final id in entry.value) remap(id)],
      },
      slotTypes: _remapTypes(
        _slots(EditorConfigKind.nativeComponent, value),
        value.slotTypes,
        remap,
      ),
      regions: {...value.regions},
      slotPreferredSizes: _remapKeys(value.slotPreferredSizes, remap),
      slotSizeConstraints: _remapKeys(value.slotSizeConstraints, remap),
      slotLabels: _remapKeys(value.slotLabels, remap),
    );
  }
  if (value is SuperLayoutConfig) {
    final grid = value.grid;
    return value.copyWith(
      sideResizing: Map.unmodifiable({...value.sideResizing}),
      collapsedSides: Map.unmodifiable({...value.collapsedSides}),
      swaps: Set.unmodifiable({...value.swaps}),
      autoSides: Set.unmodifiable({...value.autoSides}),
      placements: Map.unmodifiable({
        for (final entry in value.placements.entries)
          entry.key: List<String>.unmodifiable(entry.value.map(remap)),
      }),
      slotTypes: _remapTypes(
        _slots(EditorConfigKind.layout, value),
        value.slotTypes,
        remap,
      ),
      slotPreferredSizes: _remapKeys(value.slotPreferredSizes, remap),
      slotSizeConstraints: _remapKeys(value.slotSizeConstraints, remap),
      zoneAxes: Map.unmodifiable({...value.zoneAxes}),
      slotLabels: _remapKeys(value.slotLabels, remap),
      grid: grid?.copyWith(items: _remapKeys(grid.items, remap)),
    );
  }
  // Immutable values; a SuperValue repository ID is external, not a component ID.
  return value;
}

Appearance _write(
  Appearance appearance, {
  Map<EditorConfigRef, Object> copies = const {},
  Set<EditorConfigRef> removed = const {},
}) {
  Map<String, V>? update<V>(EditorConfigKind kind, Map<String, V> source) {
    final drop = {
      for (final ref in removed)
        if (ref.kind == kind) ref.id,
    };
    final add = {
      for (final entry in copies.entries)
        if (entry.key.kind == kind) entry.key.id: entry.value as V,
    };
    if (drop.isEmpty && add.isEmpty) return null;
    return {...source, ...add}..removeWhere((id, _) => drop.contains(id));
  }

  return appearance.copyWith(
    layouts: update(EditorConfigKind.layout, appearance.layouts),
    styles: update(EditorConfigKind.style, appearance.styles),
    nativeComponents: update(
      EditorConfigKind.nativeComponent,
      appearance.nativeComponents,
    ),
    scaffoldPages: update(
      EditorConfigKind.scaffoldPage,
      appearance.scaffoldPages,
    ),
    valueComponents: update(EditorConfigKind.value, appearance.valueComponents),
    listComponents: update(EditorConfigKind.list, appearance.listComponents),
  );
}
