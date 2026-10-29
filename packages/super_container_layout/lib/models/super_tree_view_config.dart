import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show Axis;

import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'super_layout_config.dart' show SlotSizeConstraints, ZoneFlowConfig;

/// Configuration persistée d'un composant [SuperTreeView] avec 2 zones
/// (`header` et `data`) lié à un repository JSON.
@immutable
class SuperTreeViewConfig extends ComponentConfig {
  SuperTreeViewConfig({
    this.binding,
    this.childrenKey = 'children',
    this.headerSize = 220.0,
    this.rowHeight = 32.0,
    this.indent = 20.0,
    this.initiallyExpanded = true,
    this.showConnectors = true,
    this.showCheckboxes = false,
    this.emptyText = 'Aucun élément',
    this.itemId,
    Map<String, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<String, Axis> zoneAxes = const {},
    Map<String, ZoneFlowConfig> zoneFlows = const {},
    Map<String, Size?> slotPreferredSizes = const {},
    Map<String, SlotSizeConstraints> slotSizeConstraints = const {},
    Map<String, String> slotLabels = const {},
  }) : placements = Map.unmodifiable({
         for (final entry in placements.entries)
           if (entry.value.isNotEmpty)
             entry.key: List<String>.unmodifiable(entry.value),
       }),
       slotTypes = Map.unmodifiable(slotTypes),
       zoneAxes = Map.unmodifiable(zoneAxes),
       zoneFlows = Map.unmodifiable({
         for (final entry in zoneFlows.entries)
           if (!entry.value.isDefault) entry.key: entry.value,
       }),
       slotPreferredSizes = Map.unmodifiable(slotPreferredSizes),
       slotSizeConstraints = Map.unmodifiable(slotSizeConstraints),
       slotLabels = Map.unmodifiable({
         for (final entry in slotLabels.entries)
           if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
       }) {
    final ids = placements.values.expand((value) => value).toList();
    if (ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length ||
        placements.keys.any((id) => id.trim().isEmpty) ||
        zoneAxes.keys.any((id) => id.trim().isEmpty) ||
        zoneFlows.keys.any((id) => id.trim().isEmpty) ||
        slotTypes.keys.any((id) => id.trim().isEmpty) ||
        slotTypes.values.any((type) => type.trim().isEmpty) ||
        slotPreferredSizes.keys.any((id) => id.trim().isEmpty) ||
        slotSizeConstraints.keys.any((id) => id.trim().isEmpty) ||
        slotLabels.keys.any((id) => id.trim().isEmpty) ||
        slotPreferredSizes.values.any(
          (size) =>
              size != null &&
              (size.width.isNaN ||
                  size.height.isNaN ||
                  size.width < 0 ||
                  size.height < 0),
        )) {
      throw ArgumentError('Invalid SuperTreeView configuration.');
    }
  }

  static const String headerZone = 'header';
  static const String dataZone = 'data';

  static const double minHeaderSize = 100.0;
  static const double maxHeaderSize = 2000.0;
  static const double minRowHeight = 16.0;
  static const double maxRowHeight = 400.0;
  static const double minIndent = 8.0;
  static const double maxIndent = 120.0;

  /// Tableau ou objet JSON racine de l'arbre dans le repository.
  final JsonTextBinding? binding;

  /// Nom de la propriété JSON contenant les nœuds enfants (par défaut `'children'`).
  final String childrenKey;

  /// Largeur initiale de la zone `header` en pixels.
  final double headerSize;

  /// Hauteur d'une ligne de l'arbre en pixels.
  final double rowHeight;

  /// Indentation horizontale par niveau de profondeur en pixels.
  final double indent;

  /// Indique si les nœuds sont dépliés par défaut.
  final bool initiallyExpanded;

  /// Affiche les traits de connexion hiérarchiques.
  final bool showConnectors;

  /// Affiche les cases à cocher de sélection en début de ligne.
  final bool showCheckboxes;

  /// Message affiché lorsque l'arbre est vide.
  final String emptyText;

  /// ID technique distinct pour l'[IterableContent] des lignes.
  final String? itemId;

  final Map<String, List<String>> placements;
  final Map<String, String> slotTypes;
  final Map<String, Axis> zoneAxes;
  final Map<String, ZoneFlowConfig> zoneFlows;
  final Map<String, Size?> slotPreferredSizes;
  final Map<String, SlotSizeConstraints> slotSizeConstraints;
  final Map<String, String> slotLabels;

  @override
  String get componentType => 'treeView';

  @override
  void validate() {
    binding?.validate();
    final key = childrenKey.trim();
    if (key.isEmpty || RegExp(r'[.\[\]\s?]').hasMatch(key)) {
      throw const FormatException('Clé des enfants JSON invalide.');
    }
    if (!headerSize.isFinite ||
        headerSize < minHeaderSize ||
        headerSize > maxHeaderSize) {
      throw const FormatException('Largeur de la zone Header invalide.');
    }
    if (!rowHeight.isFinite ||
        rowHeight < minRowHeight ||
        rowHeight > maxRowHeight) {
      throw const FormatException('Hauteur de ligne invalide.');
    }
    if (!indent.isFinite || indent < minIndent || indent > maxIndent) {
      throw const FormatException('Indentation invalide.');
    }
    for (final constraint in slotSizeConstraints.values) {
      SlotSizeConstraints.fromJson(constraint.toJson());
    }
  }

  List<String> slotsOf(String zone) => placements[zone] ?? const [];
  String slotTypeOf(String id) => slotTypes[id] ?? id;
  Axis? zoneAxisOf(String zone) => zoneAxes[zone];
  ZoneFlowConfig zoneFlowOf(String zone) =>
      zoneFlows[zone] ?? const ZoneFlowConfig();

  Set<String> get placedSlotIds => {
    for (final ids in placements.values) ...ids,
  };

  Set<String> slotsRemovedWith(String id) => <String>{id};

  SuperTreeViewConfig copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    String? childrenKey,
    double? headerSize,
    double? rowHeight,
    double? indent,
    bool? initiallyExpanded,
    bool? showConnectors,
    bool? showCheckboxes,
    String? emptyText,
    String? itemId,
    Map<String, List<String>>? placements,
    Map<String, String>? slotTypes,
    Map<String, Axis>? zoneAxes,
    Map<String, ZoneFlowConfig>? zoneFlows,
    Map<String, Size?>? slotPreferredSizes,
    Map<String, SlotSizeConstraints>? slotSizeConstraints,
    Map<String, String>? slotLabels,
  }) => SuperTreeViewConfig(
    binding: clearBinding ? null : binding ?? this.binding,
    childrenKey: childrenKey ?? this.childrenKey,
    headerSize: headerSize ?? this.headerSize,
    rowHeight: rowHeight ?? this.rowHeight,
    indent: indent ?? this.indent,
    initiallyExpanded: initiallyExpanded ?? this.initiallyExpanded,
    showConnectors: showConnectors ?? this.showConnectors,
    showCheckboxes: showCheckboxes ?? this.showCheckboxes,
    emptyText: emptyText ?? this.emptyText,
    itemId: itemId ?? this.itemId,
    placements: placements ?? this.placements,
    slotTypes: slotTypes ?? this.slotTypes,
    zoneAxes: zoneAxes ?? this.zoneAxes,
    zoneFlows: zoneFlows ?? this.zoneFlows,
    slotPreferredSizes: slotPreferredSizes ?? this.slotPreferredSizes,
    slotSizeConstraints: slotSizeConstraints ?? this.slotSizeConstraints,
    slotLabels: slotLabels ?? this.slotLabels,
  );

  SuperTreeViewConfig withSlotAdded(
    String id,
    String zone, {
    String? type,
    bool replace = false,
  }) {
    final next = <String, List<String>>{
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    };
    final replaced = replace ? next.remove(zone) ?? <String>[] : <String>[];
    next.putIfAbsent(zone, () => []).add(id);
    final types = {...slotTypes}
      ..removeWhere((key, _) => key == id || replaced.contains(key));
    if (type != null && type != id) types[id] = type;
    return copyWith(
      placements: next,
      slotTypes: types,
      slotPreferredSizes: {...slotPreferredSizes}
        ..removeWhere((key, _) => replaced.contains(key)),
      slotSizeConstraints: {...slotSizeConstraints}
        ..removeWhere((key, _) => replaced.contains(key)),
      slotLabels: {...slotLabels}
        ..removeWhere((key, _) => replaced.contains(key)),
    );
  }

  SuperTreeViewConfig withoutSlot(String id) {
    final removedIds = slotsRemovedWith(id);
    return copyWith(
      placements: {
        for (final entry in placements.entries)
          entry.key: entry.value
              .where((value) => !removedIds.contains(value))
              .toList(),
      },
      slotTypes: {...slotTypes}..removeWhere((k, _) => removedIds.contains(k)),
      slotPreferredSizes: {...slotPreferredSizes}
        ..removeWhere((k, _) => removedIds.contains(k)),
      slotSizeConstraints: {...slotSizeConstraints}
        ..removeWhere((k, _) => removedIds.contains(k)),
      slotLabels: {...slotLabels}
        ..removeWhere((k, _) => removedIds.contains(k)),
    );
  }

  SuperTreeViewConfig withZoneAxis(
    String zone,
    Axis? axis, {
    Axis? defaultAxis,
  }) {
    final next = {...zoneAxes};
    if (axis == null || axis == defaultAxis) {
      next.remove(zone);
    } else {
      next[zone] = axis;
    }
    return copyWith(zoneAxes: next);
  }

  SuperTreeViewConfig withZoneFlow(String zone, ZoneFlowConfig flow) {
    final next = {...zoneFlows};
    if (flow.isDefault) {
      next.remove(zone);
    } else {
      next[zone] = flow;
    }
    return copyWith(zoneFlows: next);
  }

  SuperTreeViewConfig withSlotSize(String id, Size? size) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes, id: size},
    slotSizeConstraints: {...slotSizeConstraints}..remove(id),
  );

  SuperTreeViewConfig withSlotSizeConstraints(
    String id,
    SlotSizeConstraints constraints,
  ) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints, id: constraints},
  );

  SuperTreeViewConfig withSlotLabel(String id, String? label) {
    if (!placedSlotIds.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown SuperTreeView slot.');
    }
    final next = {...slotLabels};
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      next.remove(id);
    } else {
      next[id] = trimmed;
    }
    return copyWith(slotLabels: next);
  }

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      if (binding != null) 'binding': binding!.toJson(),
      'childrenKey': childrenKey,
      'headerSize': headerSize,
      'rowHeight': rowHeight,
      'indent': indent,
      'initiallyExpanded': initiallyExpanded,
      'showConnectors': showConnectors,
      'showCheckboxes': showCheckboxes,
      'emptyText': emptyText,
      if (itemId != null) 'itemId': itemId,
      if (placements.isNotEmpty)
        'placements': {
          for (final entry in placements.entries)
            if (entry.value.isNotEmpty)
              entry.key: [
                for (final id in entry.value)
                  if (slotTypeOf(id) == id)
                    id
                  else
                    {
                      'id': id,
                      'type': JsonComponentType.shortName(slotTypeOf(id)),
                    },
              ],
        },
      if (zoneAxes.isNotEmpty)
        'zoneAxes': {
          for (final entry in zoneAxes.entries) entry.key: entry.value.name,
        },
      if (zoneFlows.isNotEmpty)
        'zoneFlows': {
          for (final entry in zoneFlows.entries)
            if (!entry.value.isDefault) entry.key: entry.value.toJson(),
        },
      if (slotPreferredSizes.isNotEmpty)
        'slotPreferredSizes': {
          for (final entry in slotPreferredSizes.entries)
            entry.key: entry.value == null
                ? null
                : [
                    entry.value!.width.isFinite ? entry.value!.width : null,
                    entry.value!.height.isFinite ? entry.value!.height : null,
                  ],
        },
      if (slotSizeConstraints.isNotEmpty)
        'slotSizeConstraints': {
          for (final entry in slotSizeConstraints.entries)
            entry.key: entry.value.toJson(),
        },
      if (slotLabels.isNotEmpty) 'slotLabels': slotLabels,
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    final d = SuperTreeViewConfig();
    return {
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (childrenKey != d.childrenKey) 'childrenKey': childrenKey,
      if (headerSize != d.headerSize) 'headerSize': headerSize,
      if (rowHeight != d.rowHeight) 'rowHeight': rowHeight,
      if (indent != d.indent) 'indent': indent,
      if (initiallyExpanded != d.initiallyExpanded)
        'initiallyExpanded': initiallyExpanded,
      if (showConnectors != d.showConnectors) 'showConnectors': showConnectors,
      if (showCheckboxes != d.showCheckboxes) 'showCheckboxes': showCheckboxes,
      if (emptyText != d.emptyText) 'emptyText': emptyText,
      if (itemId != null) 'itemId': itemId,
      if (placements.isNotEmpty)
        'placements': {
          for (final entry in placements.entries)
            if (entry.value.isNotEmpty)
              entry.key: [
                for (final id in entry.value)
                  {
                    'id': id,
                    'type': JsonComponentType.shortName(slotTypeOf(id)),
                  },
              ],
        },
      if (zoneAxes.isNotEmpty)
        'zoneAxes': {
          for (final entry in zoneAxes.entries) entry.key: entry.value.name,
        },
      if (zoneFlows.isNotEmpty)
        'zoneFlows': {
          for (final entry in zoneFlows.entries)
            if (!entry.value.isDefault) entry.key: entry.value.toJson(),
        },
      if (slotPreferredSizes.isNotEmpty)
        'slotPreferredSizes': {
          for (final entry in slotPreferredSizes.entries)
            entry.key: entry.value == null
                ? null
                : [
                    entry.value!.width.isFinite ? entry.value!.width : null,
                    entry.value!.height.isFinite ? entry.value!.height : null,
                  ],
        },
      if (slotSizeConstraints.isNotEmpty)
        'slotSizeConstraints': {
          for (final entry in slotSizeConstraints.entries)
            entry.key: JsonDimension.formatConstraintsCompact(entry.value),
        },
      if (slotLabels.isNotEmpty) 'slotLabels': slotLabels,
    };
  }

  @override
  SuperTreeViewConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperTreeViewConfig.fromJson({...toJson(), ...patch});

  factory SuperTreeViewConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Configuration de TreeView invalide.');
    }
    final binding = value.containsKey('binding') && value['binding'] != null
        ? JsonTextBinding.fromJson(value['binding'])
        : null;
    final childrenKey = value['childrenKey'] ?? 'children';
    final initiallyExpanded = value['initiallyExpanded'] ?? true;
    final showConnectors = value['showConnectors'] ?? true;
    final showCheckboxes = value['showCheckboxes'] ?? false;
    final emptyText = value['emptyText'] ?? 'Aucun élément';
    final itemId = value['itemId'];
    if (childrenKey is! String ||
        initiallyExpanded is! bool ||
        showConnectors is! bool ||
        showCheckboxes is! bool ||
        emptyText is! String ||
        (itemId != null && itemId is! String)) {
      throw const FormatException('Options de TreeView invalides.');
    }

    double readDouble(String key, double fallback) {
      final raw = value[key];
      if (raw == null) return fallback;
      if (raw is! num || !raw.isFinite) {
        throw FormatException('Valeur numérique invalide pour $key.');
      }
      return raw.toDouble();
    }

    final headerSize = readDouble('headerSize', 220.0);
    final rowHeight = readDouble('rowHeight', 32.0);
    final indent = readDouble('indent', 20.0);

    final rawPlacements = value['placements'] ?? const {};
    if (rawPlacements is! Map) {
      throw const FormatException('Placements de TreeView invalides.');
    }
    final placements = <String, List<String>>{};
    final types = <String, String>{};
    for (final entry in rawPlacements.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Zone de TreeView invalide.');
      }
      final ids = <String>[];
      for (final slot in entry.value as List) {
        if (slot is String && slot.trim().isNotEmpty) {
          ids.add(slot);
          types[slot] = JsonComponentType.normalize(slot, id: slot);
          continue;
        }
        if (slot is! Map || slot['id'] is! String || slot['type'] is! String) {
          throw const FormatException('Slot de TreeView invalide.');
        }
        final id = slot['id'] as String;
        ids.add(id);
        types[id] = JsonComponentType.normalize(slot['type'] as String, id: id);
      }
      placements[entry.key as String] = ids;
    }

    try {
      final rawSizes = value['slotPreferredSizes'] ?? const {};
      final rawConstraints = value['slotSizeConstraints'] ?? const {};
      final rawLabels = value['slotLabels'] ?? const {};
      final rawAxes = value['zoneAxes'] ?? const {};
      final rawFlows = value['zoneFlows'] ?? const {};
      if (rawSizes is! Map ||
          rawConstraints is! Map ||
          rawLabels is! Map ||
          rawAxes is! Map ||
          rawFlows is! Map) {
        throw const FormatException('Métadonnées de slots de TreeView invalides.');
      }
      if (rawLabels.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
        throw const FormatException('Libellés de slots de TreeView invalides.');
      }
      final parsedAxes = <String, Axis>{};
      for (final entry in rawAxes.entries) {
        if (entry.key is! String) {
          throw const FormatException('Axe de zone de TreeView invalide.');
        }
        final axis = Axis.values
            .where((candidate) => candidate.name == entry.value)
            .firstOrNull;
        if (axis == null) {
          throw const FormatException('Axe de zone de TreeView invalide.');
        }
        parsedAxes[entry.key as String] = axis;
      }
      final parsedFlows = <String, ZoneFlowConfig>{};
      for (final entry in rawFlows.entries) {
        if (entry.key is! String) {
          throw const FormatException('Flux de zone de TreeView invalide.');
        }
        parsedFlows[entry.key as String] = ZoneFlowConfig.fromJson(entry.value);
      }
      if (rawConstraints.keys.any((key) => key is! String)) {
        throw const FormatException('Contrainte de slot de TreeView invalide.');
      }
      final sizes = <String, Size?>{};
      for (final entry in rawSizes.entries) {
        if (entry.key is! String) {
          throw const FormatException('Taille de slot de TreeView invalide.');
        }
        sizes[entry.key as String] = JsonDimension.parsePreferredSize(
          entry.value,
          allowInfiniteSides: true,
        );
      }
      return SuperTreeViewConfig(
        binding: binding,
        childrenKey: childrenKey,
        headerSize: headerSize,
        rowHeight: rowHeight,
        indent: indent,
        initiallyExpanded: initiallyExpanded,
        showConnectors: showConnectors,
        showCheckboxes: showCheckboxes,
        emptyText: emptyText,
        itemId: itemId as String?,
        placements: placements,
        slotTypes: types,
        zoneAxes: parsedAxes,
        zoneFlows: parsedFlows,
        slotPreferredSizes: sizes,
        slotSizeConstraints: SlotSizeConstraints.parseMap(
          rawConstraints,
          placedIds: placements.values.expand((ids) => ids),
        ),
        slotLabels: Map<String, String>.from(rawLabels),
      )..validate();
    } on ArgumentError {
      throw const FormatException(
        'Identifiants de zones ou de slots de TreeView invalides.',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SuperTreeViewConfig) return false;
    if (binding != other.binding ||
        childrenKey != other.childrenKey ||
        headerSize != other.headerSize ||
        rowHeight != other.rowHeight ||
        indent != other.indent ||
        initiallyExpanded != other.initiallyExpanded ||
        showConnectors != other.showConnectors ||
        showCheckboxes != other.showCheckboxes ||
        emptyText != other.emptyText ||
        itemId != other.itemId ||
        placements.length != other.placements.length ||
        !mapEquals(slotTypes, other.slotTypes) ||
        !mapEquals(zoneAxes, other.zoneAxes) ||
        !mapEquals(zoneFlows, other.zoneFlows) ||
        !mapEquals(slotPreferredSizes, other.slotPreferredSizes) ||
        !mapEquals(slotSizeConstraints, other.slotSizeConstraints) ||
        !mapEquals(slotLabels, other.slotLabels)) {
      return false;
    }
    for (final entry in placements.entries) {
      if (!listEquals(entry.value, other.placements[entry.key])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    binding,
    childrenKey,
    headerSize,
    rowHeight,
    indent,
    initiallyExpanded,
    showConnectors,
    showCheckboxes,
    emptyText,
    itemId,
    Object.hashAllUnordered(
      placements.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
    ),
    Object.hashAllUnordered(
      slotTypes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      zoneAxes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      zoneFlows.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      slotPreferredSizes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      slotSizeConstraints.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      slotLabels.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  ]);
}
