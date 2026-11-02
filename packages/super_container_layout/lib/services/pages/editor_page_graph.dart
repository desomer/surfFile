/// Graphe de dépendances des composants et styles ([EditorPageGraph]) d'une page.
///
/// Parcourt récursivement les placements pour collecter les identifiants possédés,
/// dupliquer profondément un sous-graphe ou supprimer un composant sans laisser d'orphelins.
library;

import 'package:shortid/shortid.dart';

import '../../models/component_config.dart';
import '../../models/editor_page_config.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_value_config.dart';
import '../../models/super_action_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';
import '../../theme/appearance.dart';
import '../../theme/container_style.dart';

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
  /// Extrait un composant ou le contenu exact d'une zone, avec une page racine.
  ///
  /// L'instantane ne modifie aucun controleur et reste importable comme une
  /// apparence normale. Les repositories externes ne sont pas copies.
  static Appearance fragment({
    required Appearance appearance,
    required Registry registry,
    required String componentId,
    String? zoneId,
    String? registryType,
  }) {
    final snapshot = registry.appearanceSnapshot(appearance);
    final config = snapshot.components[componentId];
    if (config == null && !snapshot.styles.containsKey(componentId)) {
      throw FormatException('Composant introuvable : $componentId.');
    }
    final page = snapshot.pageCatalog.pages
        .where((page) => page.id == componentId)
        .firstOrNull;
    final isPage =
        page != null ||
        registryType == 'Page' ||
        config is ScaffoldPageConfig ||
        (componentId == 'root' && config is NativeComponentConfig);
    String? type;
    for (final ref in _allRefs(snapshot)) {
      type ??= _slots(ref.kind, _read(snapshot, ref)!)[componentId];
    }
    if (type == null && registry.registry.containsKey(registryType)) {
      type = 'registry:$registryType';
    }
    type ??= switch (config) {
      SuperLayoutConfig() => 'registry:Layout',
      SuperValueConfig() => 'registry:Value',
      SuperActionConfig() => 'registry:Action',
      SuperListViewConfig() => 'registry:ListView',
      SuperTabConfig() => 'registry:Tab',
      SuperTreeViewConfig() => 'registry:TreeView',
      SuperTableConfig() => 'registry:Table',
      _ =>
        registry.registry.keys
            .where(
              (key) => key.toLowerCase() == config?.componentType.toLowerCase(),
            )
            .map((key) => 'registry:$key')
            .firstOrNull,
    };
    final roots = <EditorConfigRef>[];
    final selected = <String, String>{};
    var kind = EditorConfigKind.layout;
    if (zoneId != null) {
      final ids = switch (config) {
        SuperLayoutConfig() =>
          zoneId == 'grid'
              ? config.grid?.items.keys.toList() ?? <String>[]
              : config.placements.entries
                    .where((entry) => entry.key.name == zoneId)
                    .expand((entry) => entry.value)
                    .toList(),
        SuperListViewConfig() =>
          config.template.placements.entries
              .where((entry) => entry.key.name == zoneId)
              .expand((entry) => entry.value)
              .toList(),
        NativeComponentConfig() => config.placements[zoneId],
        ScaffoldPageConfig() => config.native.placements[zoneId],
        SuperTabConfig() => config.placements[zoneId],
        SuperTreeViewConfig() => config.placements[zoneId],
        SuperTableConfig() => config.placements[zoneId],
        _ => null,
      };
      if (ids == null) {
        throw FormatException('Zone introuvable : $componentId / $zoneId.');
      }
      kind = config is SuperLayoutConfig || config is SuperListViewConfig
          ? EditorConfigKind.layout
          : EditorConfigKind.nativeComponent;
      final slots = _slots(kind, config!);
      for (final id in ids) {
        selected[id] = slots[id] ?? id;
      }
    } else if (isPage) {
      roots.addAll(_roots(componentId));
    } else if (type != null) {
      selected[componentId] = type;
    } else {
      throw FormatException(
        'Le type de $componentId ne peut pas etre reconstruit. '
        'Enregistrez son constructeur et son contrat dans le registre.',
      );
    }
    for (final entry in selected.entries) {
      final resolved = _resolve(registry, entry.value, kind);
      if (resolved.contract == null) {
        throw FormatException('Composant non exportable : ${entry.value}.');
      }
      roots.addAll(resolved.contract!.ownedConfigs(entry.key));
    }
    final graph = _Graph.build(snapshot, registry, roots);
    if (graph.cycles.isNotEmpty) {
      throw FormatException('Cycle dans le contenu : ${graph.cycles.first}.');
    }
    for (final instance in graph.instances.values) {
      if (instance.contract == null) {
        throw FormatException('Composant non exportable : ${instance.label}.');
      }
    }
    final ids = {
      ...selected.keys,
      ...graph.instances.keys,
      for (final ref in graph.configs) ref.id,
      if (isPage && zoneId == null) componentId,
    };
    final auxiliary = <String>{
      for (final id in ids) ...['$id:item', '$id:layout'],
      for (final id in ids)
        if (snapshot.components[id] case final SuperListViewConfig list)
          ?list.itemId,
      for (final id in ids)
        if (snapshot.components[id] case final SuperTreeViewConfig tree)
          ?tree.itemId,
      for (final id in ids)
        if (snapshot.components[id] case final SuperTableConfig table)
          ?table.itemId,
    };
    final used = _usedIds(snapshot);
    var rootId = '__export_root';
    while (used.contains(rootId)) {
      rootId = '${rootId}_';
    }
    final components = <String, ComponentConfig>{
      for (final entry in snapshot.components.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    };
    if (zoneId != null || !isPage) {
      components[rootId] = ScaffoldPageConfig(
        placements: {ScaffoldPageRegion.body: selected.keys.toList()},
        slotTypes: selected,
      );
    } else {
      rootId = componentId;
    }
    return snapshot.copyWith(
      components: components,
      styles: {
        if (isPage && zoneId == null && snapshot.styles['background'] != null)
          'background': snapshot.styles['background']!,
        for (final entry in snapshot.styles.entries)
          if (ids.contains(entry.key) || auxiliary.contains(entry.key))
            entry.key: entry.value,
      },
      behaviors: {
        for (final entry in snapshot.behaviors.entries)
          if (ids.contains(entry.key) || auxiliary.contains(entry.key))
            entry.key: entry.value,
      },
      pageCatalog: EditorPageCatalog(
        homePageId: rootId,
        pages: [
          EditorPageConfig(
            id: rootId,
            name: page?.name ?? componentId,
            path: page?.path ?? '/export',
          ),
        ],
      ),
    );
  }

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
  EditorConfigKind.component => appearance.components[ref.id],
  EditorConfigKind.nativeComponent =>
    appearance.tryComponent<NativeComponentConfig>(ref.id),
  EditorConfigKind.scaffoldPage => appearance.tryComponent<ScaffoldPageConfig>(
    ref.id,
  ),
  EditorConfigKind.value => appearance.tryComponent<SuperValueConfig>(ref.id),
  EditorConfigKind.action => appearance.tryComponent<SuperActionConfig>(ref.id),
  EditorConfigKind.list => appearance.tryComponent<SuperListViewConfig>(ref.id),
  EditorConfigKind.tab => appearance.tryComponent<SuperTabConfig>(ref.id),
  EditorConfigKind.treeView => appearance.tryComponent<SuperTreeViewConfig>(
    ref.id,
  ),
  EditorConfigKind.table => appearance.tryComponent<SuperTableConfig>(ref.id),
};

bool _hasKind(Object value, EditorConfigKind kind) => switch (kind) {
  EditorConfigKind.layout => value is SuperLayoutConfig,
  EditorConfigKind.style => value is ContainerStyle,
  EditorConfigKind.component => value is ComponentConfig,
  EditorConfigKind.nativeComponent => value is NativeComponentConfig,
  EditorConfigKind.scaffoldPage => value is ScaffoldPageConfig,
  EditorConfigKind.value => value is SuperValueConfig,
  EditorConfigKind.action => value is SuperActionConfig,
  EditorConfigKind.list => value is SuperListViewConfig,
  EditorConfigKind.tab => value is SuperTabConfig,
  EditorConfigKind.treeView => value is SuperTreeViewConfig,
  EditorConfigKind.table => value is SuperTableConfig,
};

Iterable<EditorConfigRef> _allRefs(Appearance appearance) => [
  for (final id in appearance.styles.keys) EditorConfigRef.style(id),
  for (final entry in appearance.components.entries)
    ...switch (entry.value) {
      SuperLayoutConfig() => [EditorConfigRef.layout(entry.key)],
      NativeComponentConfig() => [EditorConfigRef.nativeComponent(entry.key)],
      ScaffoldPageConfig() => [EditorConfigRef.scaffoldPage(entry.key)],
      SuperValueConfig() => [EditorConfigRef.value(entry.key)],
      SuperActionConfig() => [EditorConfigRef.action(entry.key)],
      SuperTabConfig() => [EditorConfigRef.tab(entry.key)],
      SuperTreeViewConfig() => [EditorConfigRef.treeView(entry.key)],
      SuperTableConfig() => [EditorConfigRef.table(entry.key)],
      SuperListViewConfig() => [
        EditorConfigRef.layout(entry.key),
        EditorConfigRef.list(entry.key),
      ],
      _ => [EditorConfigRef.component(entry.key)],
    },
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
  if (value is SuperTabConfig) {
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
  if (value is SuperTreeViewConfig) {
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
  if (value is SuperTableConfig) {
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
  if (value is ComponentConfig) {
    return value.childSlots;
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
    return value.copyWith(
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
  if (value is SuperTabConfig) {
    String remapZone(String zone) {
      final tabId = SuperTabConfig.tabSlotIdOfZone(zone);
      return tabId == null ? zone : SuperTabConfig.contentZoneFor(remap(tabId));
    }

    return value.copyWith(
      placements: {
        for (final entry in value.placements.entries)
          remapZone(entry.key): [for (final id in entry.value) remap(id)],
      },
      slotTypes: _remapTypes(
        _slots(EditorConfigKind.tab, value),
        value.slotTypes,
        remap,
      ),
      zoneAxes: {
        for (final entry in value.zoneAxes.entries)
          remapZone(entry.key): entry.value,
      },
      zoneFlows: {
        for (final entry in value.zoneFlows.entries)
          remapZone(entry.key): entry.value,
      },
      slotPreferredSizes: _remapKeys(value.slotPreferredSizes, remap),
      slotSizeConstraints: _remapKeys(value.slotSizeConstraints, remap),
      slotLabels: _remapKeys(value.slotLabels, remap),
    );
  }
  if (value is SuperTreeViewConfig) {
    return value.copyWith(
      placements: {
        for (final entry in value.placements.entries)
          entry.key: [for (final id in entry.value) remap(id)],
      },
      slotTypes: _remapTypes(
        _slots(EditorConfigKind.treeView, value),
        value.slotTypes,
        remap,
      ),
      slotPreferredSizes: _remapKeys(value.slotPreferredSizes, remap),
      slotSizeConstraints: _remapKeys(value.slotSizeConstraints, remap),
      slotLabels: _remapKeys(value.slotLabels, remap),
    );
  }
  if (value is SuperTableConfig) {
    return value.copyWith(
      placements: {
        for (final entry in value.placements.entries)
          entry.key: [for (final id in entry.value) remap(id)],
      },
      slotTypes: _remapTypes(
        _slots(EditorConfigKind.table, value),
        value.slotTypes,
        remap,
      ),
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
  if (value is ComponentConfig) {
    return value.copyWithRemappedSlots(remap);
  }
  // Immutable values; a SuperValue repository ID is external, not a component ID.
  return value;
}

Appearance _write(
  Appearance appearance, {
  Map<EditorConfigRef, Object> copies = const {},
  Set<EditorConfigRef> removed = const {},
}) {
  final styleDrop = {
    for (final ref in removed)
      if (ref.kind == EditorConfigKind.style) ref.id,
  };
  final styleAdd = {
    for (final entry in copies.entries)
      if (entry.key.kind == EditorConfigKind.style)
        entry.key.id: entry.value as ContainerStyle,
  };
  final nextStyles = (styleDrop.isEmpty && styleAdd.isEmpty)
      ? null
      : ({...appearance.styles, ...styleAdd}
          ..removeWhere((id, _) => styleDrop.contains(id)));

  final compDrop = {
    for (final ref in removed)
      if (ref.kind != EditorConfigKind.style) ref.id,
  };
  final hasCompChanges =
      compDrop.isNotEmpty ||
      copies.keys.any((ref) => ref.kind != EditorConfigKind.style);
  Map<String, ComponentConfig>? nextComponents;
  if (hasCompChanges) {
    nextComponents = {...appearance.components}
      ..removeWhere((id, _) => compDrop.contains(id));
    for (final entry in copies.entries) {
      if (entry.key.kind == EditorConfigKind.style) continue;
      final id = entry.key.id;
      final value = entry.value;
      final current = nextComponents[id];
      if (value is SuperLayoutConfig && current is SuperListViewConfig) {
        nextComponents[id] = current.copyWith(template: value);
      } else if (value is SuperListViewConfig && current is SuperLayoutConfig) {
        nextComponents[id] = value.copyWith(template: current);
      } else {
        nextComponents[id] = value as ComponentConfig;
      }
    }
  }

  return appearance.copyWith(styles: nextStyles, components: nextComponents);
}
