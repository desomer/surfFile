import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis;

import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'super_layout_config.dart' show SlotSizeConstraints, ZoneFlowConfig;

/// Mode de fonctionnement d'un composant [SuperTab] :
/// - [static] : onglets fixes définis dans la zone `'tabs'`, chacun avec sa
///   propre zone de contenu `'content:<tabSlotId>'`.
/// - [dynamic] : onglets générés dynamiquement depuis un tableau JSON lié via
///   [SuperTabConfig.binding], partageant un onglet gabarit (`'tabs'`) et une
///   zone de contenu gabarit (`'content'`) sous un `JsonListScope`.
enum SuperTabMode { static, dynamic }

/// Position de la barre d'onglets (`TabBar`) par rapport au contenu (`TabBarView`).
enum SuperTabBarPosition { top, bottom }

/// Configuration persistée d'un composant spécifique [SuperTab].
@immutable
class SuperTabConfig extends ComponentConfig {
  SuperTabConfig({
    this.mode = SuperTabMode.static,
    this.tabBarPosition = SuperTabBarPosition.top,
    this.isScrollable = false,
    this.initialIndex = 0,
    this.binding,
    this.allowAdd = false,
    this.allowRemove = false,
    this.emptyText = 'Aucun onglet',
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
    if (initialIndex < 0 ||
        ids.any((id) => id.trim().isEmpty) ||
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
      throw ArgumentError('Invalid SuperTab configuration.');
    }
  }

  static const String tabsZone = 'tabs';
  static const String dynamicContentZone = 'content';
  static String contentZoneFor(String tabSlotId) => 'content:$tabSlotId';
  static String? tabSlotIdOfZone(String zone) =>
      zone.startsWith('content:') && zone.length > 'content:'.length
      ? zone.substring('content:'.length)
      : null;

  final SuperTabMode mode;
  final SuperTabBarPosition tabBarPosition;
  final bool isScrollable;
  final int initialIndex;

  /// En mode [SuperTabMode.dynamic], chemin du tableau JSON générant les onglets.
  /// En mode [SuperTabMode.static], liaison optionnelle de l'index actif.
  final JsonTextBinding? binding;

  /// En mode dynamique, autorise l'ajout d'un élément au tableau JSON lié.
  final bool allowAdd;

  /// En mode dynamique, autorise la suppression d'un élément du tableau JSON lié.
  final bool allowRemove;

  /// Message affiché quand le tableau dynamique est vide.
  final String emptyText;

  final Map<String, List<String>> placements;
  final Map<String, String> slotTypes;
  final Map<String, Axis> zoneAxes;
  final Map<String, ZoneFlowConfig> zoneFlows;
  final Map<String, Size?> slotPreferredSizes;
  final Map<String, SlotSizeConstraints> slotSizeConstraints;
  final Map<String, String> slotLabels;

  @override
  String get componentType => 'tab';

  @override
  void validate() {
    binding?.validate();
    if (initialIndex < 0) {
      throw const FormatException('Index initial d’onglet invalide.');
    }
    for (final constraint in slotSizeConstraints.values) {
      SlotSizeConstraints.fromJson(constraint.toJson());
    }
  }

  List<String> slotsOf(String zone) => placements[zone] ?? const [];
  List<String> get tabSlotIds => slotsOf(tabsZone);
  String slotTypeOf(String id) => slotTypes[id] ?? id;
  Axis? zoneAxisOf(String zone) => zoneAxes[zone];
  ZoneFlowConfig zoneFlowOf(String zone) =>
      zoneFlows[zone] ?? const ZoneFlowConfig();

  Set<String> get placedSlotIds => {
    for (final ids in placements.values) ...ids,
  };

  /// Tous les slots qui seraient retirés si [id] est supprimé (incluant les
  /// composants placés dans `'content:$id'` si [id] est un onglet statique).
  Set<String> slotsRemovedWith(String id) {
    final removed = <String>{id};
    if (tabSlotIds.contains(id)) {
      removed.addAll(slotsOf(contentZoneFor(id)));
    }
    return removed;
  }

  SuperTabConfig copyWith({
    SuperTabMode? mode,
    SuperTabBarPosition? tabBarPosition,
    bool? isScrollable,
    int? initialIndex,
    JsonTextBinding? binding,
    bool clearBinding = false,
    bool? allowAdd,
    bool? allowRemove,
    String? emptyText,
    Map<String, List<String>>? placements,
    Map<String, String>? slotTypes,
    Map<String, Axis>? zoneAxes,
    Map<String, ZoneFlowConfig>? zoneFlows,
    Map<String, Size?>? slotPreferredSizes,
    Map<String, SlotSizeConstraints>? slotSizeConstraints,
    Map<String, String>? slotLabels,
  }) => SuperTabConfig(
    mode: mode ?? this.mode,
    tabBarPosition: tabBarPosition ?? this.tabBarPosition,
    isScrollable: isScrollable ?? this.isScrollable,
    initialIndex: initialIndex ?? this.initialIndex,
    binding: clearBinding ? null : binding ?? this.binding,
    allowAdd: allowAdd ?? this.allowAdd,
    allowRemove: allowRemove ?? this.allowRemove,
    emptyText: emptyText ?? this.emptyText,
    placements: placements ?? this.placements,
    slotTypes: slotTypes ?? this.slotTypes,
    zoneAxes: zoneAxes ?? this.zoneAxes,
    zoneFlows: zoneFlows ?? this.zoneFlows,
    slotPreferredSizes: slotPreferredSizes ?? this.slotPreferredSizes,
    slotSizeConstraints: slotSizeConstraints ?? this.slotSizeConstraints,
    slotLabels: slotLabels ?? this.slotLabels,
  );

  SuperTabConfig withSlotAdded(
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

  SuperTabConfig withoutSlot(String id) {
    final contentZone = tabSlotIds.contains(id) ? contentZoneFor(id) : null;
    final removedIds = slotsRemovedWith(id);
    return copyWith(
      placements: {
        for (final entry in placements.entries)
          if (entry.key != contentZone)
            entry.key: entry.value
                .where((value) => !removedIds.contains(value))
                .toList(),
      },
      slotTypes: {...slotTypes}..removeWhere((k, _) => removedIds.contains(k)),
      zoneAxes: contentZone == null
          ? null
          : ({...zoneAxes}..remove(contentZone)),
      zoneFlows: contentZone == null
          ? null
          : ({...zoneFlows}..remove(contentZone)),
      slotPreferredSizes: {...slotPreferredSizes}
        ..removeWhere((k, _) => removedIds.contains(k)),
      slotSizeConstraints: {...slotSizeConstraints}
        ..removeWhere((k, _) => removedIds.contains(k)),
      slotLabels: {...slotLabels}
        ..removeWhere((k, _) => removedIds.contains(k)),
    );
  }

  SuperTabConfig withSlotMoved(
    String id,
    String zone, {
    String? beforeId,
    String? afterId,
  }) {
    if (!placedSlotIds.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown SuperTab slot.');
    }
    if (zone.trim().isEmpty ||
        (beforeId != null && afterId != null) ||
        (beforeId != null && !slotsOf(zone).contains(beforeId)) ||
        (afterId != null && !slotsOf(zone).contains(afterId))) {
      throw ArgumentError('Invalid SuperTab slot destination.');
    }
    if (beforeId == id || afterId == id) return this;
    final next = <String, List<String>>{
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    };
    final destination = next.putIfAbsent(zone, () => []);
    final index = beforeId != null
        ? destination.indexOf(beforeId)
        : afterId != null
        ? destination.indexOf(afterId) + 1
        : destination.length;
    destination.insert(index, id);
    return copyWith(placements: next);
  }

  SuperTabConfig withSlotReplaced(
    String id,
    String replacementId,
    String type,
  ) {
    if (!placedSlotIds.contains(id) ||
        replacementId.trim().isEmpty ||
        placedSlotIds.contains(replacementId)) {
      throw ArgumentError('Invalid SuperTab slot replacement.');
    }
    final oldContentZone = contentZoneFor(id);
    final newContentZone = contentZoneFor(replacementId);
    String remapZone(String z) => z == oldContentZone ? newContentZone : z;
    return copyWith(
      placements: {
        for (final entry in placements.entries)
          remapZone(entry.key): [
            for (final slot in entry.value) slot == id ? replacementId : slot,
          ],
      },
      slotTypes: {...slotTypes}
        ..remove(id)
        ..[replacementId] = type,
      zoneAxes: {
        for (final entry in zoneAxes.entries)
          remapZone(entry.key): entry.value,
      },
      zoneFlows: {
        for (final entry in zoneFlows.entries)
          remapZone(entry.key): entry.value,
      },
      slotPreferredSizes: {
        for (final entry in slotPreferredSizes.entries)
          (entry.key == id ? replacementId : entry.key): entry.value,
      },
      slotSizeConstraints: {
        for (final entry in slotSizeConstraints.entries)
          (entry.key == id ? replacementId : entry.key): entry.value,
      },
      slotLabels: {...slotLabels}..remove(id),
    );
  }

  SuperTabConfig withZoneAxis(
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

  SuperTabConfig withZoneFlow(String zone, ZoneFlowConfig flow) {
    final next = {...zoneFlows};
    if (flow.isDefault) {
      next.remove(zone);
    } else {
      next[zone] = flow;
    }
    return copyWith(zoneFlows: next);
  }

  SuperTabConfig withSlotSize(String id, Size? size) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes, id: size},
    slotSizeConstraints: {...slotSizeConstraints}..remove(id),
  );

  SuperTabConfig withSlotSizeConstraints(
    String id,
    SlotSizeConstraints constraints,
  ) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints, id: constraints},
  );

  SuperTabConfig withSlotLabel(String id, String? label) => copyWith(
    slotLabels: {...slotLabels}
      ..remove(id)
      ..addAll({id: ?label}),
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'mode': mode.name,
      'tabBarPosition': tabBarPosition.name,
      'isScrollable': isScrollable,
      'initialIndex': initialIndex,
      if (binding != null) 'binding': binding!.toJson(),
      'allowAdd': allowAdd,
      'allowRemove': allowRemove,
      'emptyText': emptyText,
      'placements': {
        for (final entry in placements.entries)
          if (entry.value.isNotEmpty)
            entry.key: [
              for (final id in entry.value) {'id': id, 'type': slotTypeOf(id)},
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
    final d = SuperTabConfig();
    return {
      if (mode != d.mode) 'mode': mode.name,
      if (tabBarPosition != d.tabBarPosition)
        'tabBarPosition': tabBarPosition.name,
      if (isScrollable != d.isScrollable) 'isScrollable': isScrollable,
      if (initialIndex != d.initialIndex) 'initialIndex': initialIndex,
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (allowAdd != d.allowAdd) 'allowAdd': allowAdd,
      if (allowRemove != d.allowRemove) 'allowRemove': allowRemove,
      if (emptyText != d.emptyText) 'emptyText': emptyText,
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
  SuperTabConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperTabConfig.fromJson({...toJson(), ...patch});

  factory SuperTabConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Configuration d’onglets invalide.');
    }
    final rawMode = value['mode'] ?? SuperTabMode.static.name;
    final mode = SuperTabMode.values
        .where((candidate) => candidate.name == rawMode)
        .firstOrNull;
    if (mode == null) {
      throw const FormatException('Mode d’onglets invalide.');
    }
    final rawPosition = value['tabBarPosition'] ?? SuperTabBarPosition.top.name;
    final tabBarPosition = SuperTabBarPosition.values
        .where((candidate) => candidate.name == rawPosition)
        .firstOrNull;
    if (tabBarPosition == null) {
      throw const FormatException('Position de barre d’onglets invalide.');
    }
    final isScrollable = value['isScrollable'] ?? false;
    if (isScrollable is! bool) {
      throw const FormatException('Option isScrollable invalide.');
    }
    final initialIndex = value['initialIndex'] ?? 0;
    if (initialIndex is! int || initialIndex < 0) {
      throw const FormatException('Index initial d’onglet invalide.');
    }
    final binding = value.containsKey('binding') && value['binding'] != null
        ? JsonTextBinding.fromJson(value['binding'])
        : null;
    final allowAdd = value['allowAdd'] ?? false;
    final allowRemove = value['allowRemove'] ?? false;
    final emptyText = value['emptyText'] ?? 'Aucun onglet';
    if (allowAdd is! bool || allowRemove is! bool || emptyText is! String) {
      throw const FormatException('Options dynamiques d’onglets invalides.');
    }

    final rawPlacements = value['placements'] ?? const {};
    if (rawPlacements is! Map) {
      throw const FormatException('Placements d’onglets invalides.');
    }
    final placements = <String, List<String>>{};
    final types = <String, String>{};
    for (final entry in rawPlacements.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Zone d’onglets invalide.');
      }
      final ids = <String>[];
      for (final slot in entry.value as List) {
        if (slot is String && slot.trim().isNotEmpty) {
          ids.add(slot);
          types[slot] = JsonComponentType.normalize(slot, id: slot);
          continue;
        }
        if (slot is! Map || slot['id'] is! String || slot['type'] is! String) {
          throw const FormatException('Slot d’onglet invalide.');
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
        throw const FormatException('Métadonnées de slots d’onglets invalides.');
      }
      if (rawLabels.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
        throw const FormatException('Libellés de slots d’onglets invalides.');
      }
      final parsedAxes = <String, Axis>{};
      for (final entry in rawAxes.entries) {
        if (entry.key is! String) {
          throw const FormatException('Axe de zone d’onglet invalide.');
        }
        final axis = Axis.values
            .where((candidate) => candidate.name == entry.value)
            .firstOrNull;
        if (axis == null) {
          throw const FormatException('Axe de zone d’onglet invalide.');
        }
        parsedAxes[entry.key as String] = axis;
      }
      final parsedFlows = <String, ZoneFlowConfig>{};
      for (final entry in rawFlows.entries) {
        if (entry.key is! String) {
          throw const FormatException('Flux de zone d’onglet invalide.');
        }
        parsedFlows[entry.key as String] = ZoneFlowConfig.fromJson(entry.value);
      }
      if (rawConstraints.keys.any((key) => key is! String)) {
        throw const FormatException('Contrainte de slot d’onglet invalide.');
      }
      final sizes = <String, Size?>{};
      for (final entry in rawSizes.entries) {
        if (entry.key is! String) {
          throw const FormatException('Taille de slot d’onglet invalide.');
        }
        sizes[entry.key as String] = JsonDimension.parsePreferredSize(
          entry.value,
          allowInfiniteSides: true,
        );
      }
      return SuperTabConfig(
        mode: mode,
        tabBarPosition: tabBarPosition,
        isScrollable: isScrollable,
        initialIndex: initialIndex,
        binding: binding,
        allowAdd: allowAdd,
        allowRemove: allowRemove,
        emptyText: emptyText,
        placements: placements,
        slotTypes: types,
        zoneAxes: parsedAxes,
        zoneFlows: parsedFlows,
        slotPreferredSizes: sizes,
        slotSizeConstraints: {
          for (final entry in rawConstraints.entries)
            entry.key as String: SlotSizeConstraints.fromJson(entry.value),
        },
        slotLabels: Map<String, String>.from(rawLabels),
      )..validate();
    } on ArgumentError {
      throw const FormatException('Identifiants de zones ou de slots invalides.');
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SuperTabConfig) return false;
    if (mode != other.mode ||
        tabBarPosition != other.tabBarPosition ||
        isScrollable != other.isScrollable ||
        initialIndex != other.initialIndex ||
        binding != other.binding ||
        allowAdd != other.allowAdd ||
        allowRemove != other.allowRemove ||
        emptyText != other.emptyText ||
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
  int get hashCode => Object.hash(
    mode,
    tabBarPosition,
    isScrollable,
    initialIndex,
    binding,
    allowAdd,
    allowRemove,
    emptyText,
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
  );
}
