/// Configuration persistée ([SuperTreeViewConfig]) d'un arbre hiérarchique [SuperTreeView].
///
/// Paramètre la liaison JSON récursive (`binding`, `childrenKey`), les dimensions
/// de la zone `header` et des lignes, l'indentation, les connecteurs et les
/// placements dans les zones `header` et `data`.
library;

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
    this.animateSelectionAndHover = true,
    this.emptyText = 'Aucun élément',
    this.itemId,
    Map<String, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<String, Axis> zoneAxes = const {},
    Map<String, ZoneFlowConfig> zoneFlows = const {},
    Map<String, Size?> slotPreferredSizes = const {},
    Map<String, SlotSizeConstraints> slotSizeConstraints = const {},
    Map<String, String> slotLabels = const {},
  }) : placements = JsonReader.normalizePlacements(placements),
       slotTypes = Map.unmodifiable(slotTypes),
       zoneAxes = Map.unmodifiable(zoneAxes),
       zoneFlows = JsonReader.normalizeZoneFlows(zoneFlows),
       slotPreferredSizes = Map.unmodifiable(slotPreferredSizes),
       slotSizeConstraints = Map.unmodifiable(slotSizeConstraints),
       slotLabels = JsonReader.normalizeSlotLabels(slotLabels) {
    if (JsonReader.hasInvalidSlotContainerMaps(
      placements: this.placements,
      slotTypes: this.slotTypes,
      zoneAxes: this.zoneAxes,
      zoneFlows: this.zoneFlows,
      slotPreferredSizes: this.slotPreferredSizes,
      slotSizeConstraints: this.slotSizeConstraints,
      slotLabels: this.slotLabels,
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

  /// Anime verticalement le déplacement du fond de la ligne sélectionnée et survolée.
  final bool animateSelectionAndHover;

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
    bool? animateSelectionAndHover,
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
    animateSelectionAndHover:
        animateSelectionAndHover ?? this.animateSelectionAndHover,
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
    final next = JsonReader.addSlotToMaps(
      id: id,
      zone: zone,
      type: type,
      replace: replace,
      placements: placements,
      slotTypes: slotTypes,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  SuperTreeViewConfig withoutSlot(String id) {
    final next = JsonReader.removeSlotsFromMaps(
      removedIds: slotsRemovedWith(id),
      placements: placements,
      slotTypes: slotTypes,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  SuperTreeViewConfig withZoneAxis(
    String zone,
    Axis? axis, {
    Axis? defaultAxis,
  }) => copyWith(
    zoneAxes: JsonReader.updateZoneAxisMap(
      zoneAxes,
      zone,
      axis,
      defaultAxis: defaultAxis,
    ),
  );

  SuperTreeViewConfig withZoneFlow(String zone, ZoneFlowConfig flow) =>
      copyWith(zoneFlows: JsonReader.updateZoneFlowMap(zoneFlows, zone, flow));

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
      'animateSelectionAndHover': animateSelectionAndHover,
      'emptyText': emptyText,
      if (itemId != null) 'itemId': itemId,
      ...JsonReader.encodeSlotContainerJson(
        placements: placements,
        slotTypeOf: slotTypeOf,
        zoneAxes: zoneAxes,
        zoneFlows: zoneFlows,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
      ),
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
      if (animateSelectionAndHover != d.animateSelectionAndHover)
        'animateSelectionAndHover': animateSelectionAndHover,
      if (emptyText != d.emptyText) 'emptyText': emptyText,
      if (itemId != null) 'itemId': itemId,
      ...JsonReader.encodeSlotContainerJson(
        placements: placements,
        slotTypeOf: slotTypeOf,
        zoneAxes: zoneAxes,
        zoneFlows: zoneFlows,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
        compact: true,
      ),
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
    final animateSelectionAndHover = value['animateSelectionAndHover'] ?? true;
    final emptyText = value['emptyText'] ?? 'Aucun élément';
    final itemId = value['itemId'];
    if (childrenKey is! String ||
        initiallyExpanded is! bool ||
        showConnectors is! bool ||
        showCheckboxes is! bool ||
        animateSelectionAndHover is! bool ||
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

    final (:placements, :slotTypes) = JsonReader.parseSlotPlacements(
      value['placements'],
      invalidPlacementsMessage: 'Placements de TreeView invalides.',
      invalidZoneMessage: 'Zone de TreeView invalide.',
      invalidSlotMessage: 'Slot de TreeView invalide.',
    );

    try {
      final meta = JsonReader.parseSlotContainerMetadata(
        value,
        placedIds: placements.values.expand((ids) => ids),
        invalidMetadataMessage: 'Métadonnées de slots de TreeView invalides.',
        invalidLabelsMessage: 'Libellés de slots de TreeView invalides.',
        invalidAxisMessage: 'Axe de zone de TreeView invalide.',
        invalidFlowMessage: 'Flux de zone de TreeView invalide.',
        invalidConstraintMessage: 'Contrainte de slot de TreeView invalide.',
        invalidSizeMessage: 'Taille de slot de TreeView invalide.',
      );
      return SuperTreeViewConfig(
        binding: binding,
        childrenKey: childrenKey,
        headerSize: headerSize,
        rowHeight: rowHeight,
        indent: indent,
        initiallyExpanded: initiallyExpanded,
        showConnectors: showConnectors,
        showCheckboxes: showCheckboxes,
        animateSelectionAndHover: animateSelectionAndHover,
        emptyText: emptyText,
        itemId: itemId as String?,
        placements: placements,
        slotTypes: slotTypes,
        zoneAxes: meta.zoneAxes,
        zoneFlows: meta.zoneFlows,
        slotPreferredSizes: meta.slotPreferredSizes,
        slotSizeConstraints: meta.slotSizeConstraints,
        slotLabels: meta.slotLabels,
      )..validate();
    } on ArgumentError {
      throw const FormatException(
        'Identifiants de zones ou de slots de TreeView invalides.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SuperTreeViewConfig &&
          binding == other.binding &&
          childrenKey == other.childrenKey &&
          headerSize == other.headerSize &&
          rowHeight == other.rowHeight &&
          indent == other.indent &&
          initiallyExpanded == other.initiallyExpanded &&
          showConnectors == other.showConnectors &&
          showCheckboxes == other.showCheckboxes &&
          animateSelectionAndHover == other.animateSelectionAndHover &&
          emptyText == other.emptyText &&
          itemId == other.itemId &&
          JsonReader.sameSlotLayoutMetadata(
            placementsA: placements,
            placementsB: other.placements,
            slotTypesA: slotTypes,
            slotTypesB: other.slotTypes,
            zoneAxesA: zoneAxes,
            zoneAxesB: other.zoneAxes,
            zoneFlowsA: zoneFlows,
            zoneFlowsB: other.zoneFlows,
            slotPreferredSizesA: slotPreferredSizes,
            slotPreferredSizesB: other.slotPreferredSizes,
            slotSizeConstraintsA: slotSizeConstraints,
            slotSizeConstraintsB: other.slotSizeConstraints,
            slotLabelsA: slotLabels,
            slotLabelsB: other.slotLabels,
          ));

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
    animateSelectionAndHover,
    emptyText,
    itemId,
    ...JsonReader.slotLayoutHashParts(
      placements: placements,
      slotTypes: slotTypes,
      zoneAxes: zoneAxes,
      zoneFlows: zoneFlows,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    ),
  ]);
}
