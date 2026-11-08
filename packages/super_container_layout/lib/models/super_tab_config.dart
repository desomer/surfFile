/// Configuration persistée ([SuperTabConfig]) d'un composant d'onglets [SuperTab].
///
/// Supporte le mode statique (vues dédiées par onglet `tab_0`, `tab_1`, ...) et
/// le mode dynamique lié à un tableau JSON, ainsi que le style de la `TabBar`.
library;

import 'dart:ui' show Color, Size;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart'
    show Axis, TabAlignment, TabBarIndicatorSize;

import '../theme/container_style.dart';
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

/// Style visuel de l'indicateur d'onglet actif dans la `TabBar`.
enum SuperTabIndicatorKind { underline, box, none }

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
    this.tabBarStyle = const ContainerStyle(),
    this.indicatorKind = SuperTabIndicatorKind.underline,
    this.indicatorSize = TabBarIndicatorSize.tab,
    this.indicatorColor,
    this.indicatorWeight = 2.0,
    this.indicatorRadius = 0.0,
    this.indicatorHorizontalPadding = 0.0,
    this.indicatorVerticalPadding = 0.0,
    this.labelColor,
    this.unselectedLabelColor,
    this.overlayColor,
    this.labelHorizontalPadding,
    this.dividerColor,
    this.dividerHeight,
    this.tabAlignment,
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
    if (initialIndex < 0 ||
        JsonReader.hasInvalidSlotContainerMaps(
          placements: this.placements,
          slotTypes: this.slotTypes,
          zoneAxes: this.zoneAxes,
          zoneFlows: this.zoneFlows,
          slotPreferredSizes: this.slotPreferredSizes,
          slotSizeConstraints: this.slotSizeConstraints,
          slotLabels: this.slotLabels,
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

  /// Style complet de surface (`StyledSurface`) de la zone « Onglets » (`TabBar`).
  final ContainerStyle tabBarStyle;

  /// Forme de l'indicateur d'onglet sélectionné.
  final SuperTabIndicatorKind indicatorKind;

  /// Étendue horizontale de l'indicateur (`tab` ou `label`).
  final TabBarIndicatorSize indicatorSize;

  /// Couleur de l'indicateur d'onglet actif.
  final Color? indicatorColor;

  /// Épaisseur du trait d'indicateur (mode `underline` ou bordure).
  final double indicatorWeight;

  /// Rayon de courbure de l'indicateur (`underline` ou `box`).
  final double indicatorRadius;

  /// Marge intérieure horizontale de l'indicateur.
  final double indicatorHorizontalPadding;

  /// Marge intérieure verticale de l'indicateur.
  final double indicatorVerticalPadding;

  /// Couleur du texte et de l'icône de l'onglet actif.
  final Color? labelColor;

  /// Couleur du texte et de l'icône des onglets inactifs.
  final Color? unselectedLabelColor;

  /// Couleur d'effet au survol / clic sur un onglet.
  final Color? overlayColor;

  /// Marge intérieure horizontale de chaque onglet.
  final double? labelHorizontalPadding;

  /// Couleur du trait de séparation sous la `TabBar`.
  final Color? dividerColor;

  /// Hauteur du trait de séparation (`0` pour masquer).
  final double? dividerHeight;

  /// Alignement des onglets dans la `TabBar`.
  final TabAlignment? tabAlignment;

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
    if (!indicatorWeight.isFinite || indicatorWeight < 0) {
      throw const FormatException('Épaisseur d’indicateur invalide.');
    }
    if (!indicatorRadius.isFinite || indicatorRadius < 0) {
      throw const FormatException('Rayon d’indicateur invalide.');
    }
    if (!indicatorHorizontalPadding.isFinite ||
        indicatorHorizontalPadding < 0 ||
        !indicatorVerticalPadding.isFinite ||
        indicatorVerticalPadding < 0) {
      throw const FormatException('Marge d’indicateur invalide.');
    }
    if (labelHorizontalPadding != null &&
        (!labelHorizontalPadding!.isFinite || labelHorizontalPadding! < 0)) {
      throw const FormatException('Marge d’onglet invalide.');
    }
    if (dividerHeight != null &&
        (!dividerHeight!.isFinite || dividerHeight! < 0)) {
      throw const FormatException('Hauteur de séparateur invalide.');
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
    ContainerStyle? tabBarStyle,
    SuperTabIndicatorKind? indicatorKind,
    TabBarIndicatorSize? indicatorSize,
    Color? indicatorColor,
    bool clearIndicatorColor = false,
    double? indicatorWeight,
    double? indicatorRadius,
    double? indicatorHorizontalPadding,
    double? indicatorVerticalPadding,
    Color? labelColor,
    bool clearLabelColor = false,
    Color? unselectedLabelColor,
    bool clearUnselectedLabelColor = false,
    Color? overlayColor,
    bool clearOverlayColor = false,
    double? labelHorizontalPadding,
    bool clearLabelHorizontalPadding = false,
    Color? dividerColor,
    bool clearDividerColor = false,
    double? dividerHeight,
    bool clearDividerHeight = false,
    TabAlignment? tabAlignment,
    bool clearTabAlignment = false,
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
    tabBarStyle: tabBarStyle ?? this.tabBarStyle,
    indicatorKind: indicatorKind ?? this.indicatorKind,
    indicatorSize: indicatorSize ?? this.indicatorSize,
    indicatorColor: clearIndicatorColor
        ? null
        : indicatorColor ?? this.indicatorColor,
    indicatorWeight: indicatorWeight ?? this.indicatorWeight,
    indicatorRadius: indicatorRadius ?? this.indicatorRadius,
    indicatorHorizontalPadding:
        indicatorHorizontalPadding ?? this.indicatorHorizontalPadding,
    indicatorVerticalPadding:
        indicatorVerticalPadding ?? this.indicatorVerticalPadding,
    labelColor: clearLabelColor ? null : labelColor ?? this.labelColor,
    unselectedLabelColor: clearUnselectedLabelColor
        ? null
        : unselectedLabelColor ?? this.unselectedLabelColor,
    overlayColor: clearOverlayColor ? null : overlayColor ?? this.overlayColor,
    labelHorizontalPadding: clearLabelHorizontalPadding
        ? null
        : labelHorizontalPadding ?? this.labelHorizontalPadding,
    dividerColor: clearDividerColor ? null : dividerColor ?? this.dividerColor,
    dividerHeight: clearDividerHeight
        ? null
        : dividerHeight ?? this.dividerHeight,
    tabAlignment: clearTabAlignment ? null : tabAlignment ?? this.tabAlignment,
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

  SuperTabConfig withoutSlot(String id) {
    final contentZone = tabSlotIds.contains(id) ? contentZoneFor(id) : null;
    final next = JsonReader.removeSlotsFromMaps(
      removedIds: slotsRemovedWith(id),
      removedZone: contentZone,
      placements: placements,
      slotTypes: slotTypes,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      zoneAxes: contentZone == null
          ? null
          : ({...zoneAxes}..remove(contentZone)),
      zoneFlows: contentZone == null
          ? null
          : ({...zoneFlows}..remove(contentZone)),
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  SuperTabConfig withSlotMoved(
    String id,
    String zone, {
    String? beforeId,
    String? afterId,
  }) {
    final next = JsonReader.moveSlotInPlacements(
      id: id,
      zone: zone,
      beforeId: beforeId,
      afterId: afterId,
      placements: placements,
      unknownError: 'Unknown SuperTab slot.',
      destinationError: 'Invalid SuperTab slot destination.',
    );
    return next == null ? this : copyWith(placements: next);
  }

  SuperTabConfig withSlotReplaced(
    String id,
    String replacementId,
    String type,
  ) {
    final oldContentZone = contentZoneFor(id);
    final newContentZone = contentZoneFor(replacementId);
    final next = JsonReader.replaceSlotInMaps(
      id: id,
      replacementId: replacementId,
      type: type,
      placements: placements,
      slotTypes: slotTypes,
      zoneAxes: zoneAxes,
      zoneFlows: zoneFlows,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
      remapZone: (z) => z == oldContentZone ? newContentZone : z,
      errorMessage: 'Invalid SuperTab slot replacement.',
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      zoneAxes: next.zoneAxes,
      zoneFlows: next.zoneFlows,
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  SuperTabConfig withZoneAxis(
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

  SuperTabConfig withZoneFlow(String zone, ZoneFlowConfig flow) =>
      copyWith(zoneFlows: JsonReader.updateZoneFlowMap(zoneFlows, zone, flow));

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
      if (tabBarStyle != const ContainerStyle())
        'tabBarStyle': tabBarStyle.toJson(),
      'indicatorKind': indicatorKind.name,
      'indicatorSize': indicatorSize.name,
      if (indicatorColor != null)
        'indicatorColor': JsonColor.toHex(indicatorColor!),
      'indicatorWeight': indicatorWeight,
      'indicatorRadius': indicatorRadius,
      'indicatorHorizontalPadding': indicatorHorizontalPadding,
      'indicatorVerticalPadding': indicatorVerticalPadding,
      if (labelColor != null) 'labelColor': JsonColor.toHex(labelColor!),
      if (unselectedLabelColor != null)
        'unselectedLabelColor': JsonColor.toHex(unselectedLabelColor!),
      if (overlayColor != null) 'overlayColor': JsonColor.toHex(overlayColor!),
      if (labelHorizontalPadding != null)
        'labelHorizontalPadding': labelHorizontalPadding,
      if (dividerColor != null) 'dividerColor': JsonColor.toHex(dividerColor!),
      if (dividerHeight != null) 'dividerHeight': dividerHeight,
      if (tabAlignment != null) 'tabAlignment': tabAlignment!.name,
      ...JsonReader.encodeSlotContainerJson(
        placements: placements,
        slotTypeOf: slotTypeOf,
        zoneAxes: zoneAxes,
        zoneFlows: zoneFlows,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
        alwaysIncludePlacements: true,
        useShortTypeNameInFullJson: false,
        allowBareSlotIdInFullJson: false,
      ),
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
      if (tabBarStyle != d.tabBarStyle)
        'tabBarStyle': tabBarStyle.toCompactJson(),
      if (indicatorKind != d.indicatorKind)
        'indicatorKind': indicatorKind.name,
      if (indicatorSize != d.indicatorSize)
        'indicatorSize': indicatorSize.name,
      if (indicatorColor != null)
        'indicatorColor': JsonColor.toHex(indicatorColor!),
      if (indicatorWeight != d.indicatorWeight)
        'indicatorWeight': indicatorWeight,
      if (indicatorRadius != d.indicatorRadius)
        'indicatorRadius': indicatorRadius,
      if (indicatorHorizontalPadding != d.indicatorHorizontalPadding)
        'indicatorHorizontalPadding': indicatorHorizontalPadding,
      if (indicatorVerticalPadding != d.indicatorVerticalPadding)
        'indicatorVerticalPadding': indicatorVerticalPadding,
      if (labelColor != null) 'labelColor': JsonColor.toHex(labelColor!),
      if (unselectedLabelColor != null)
        'unselectedLabelColor': JsonColor.toHex(unselectedLabelColor!),
      if (overlayColor != null) 'overlayColor': JsonColor.toHex(overlayColor!),
      if (labelHorizontalPadding != null)
        'labelHorizontalPadding': labelHorizontalPadding,
      if (dividerColor != null) 'dividerColor': JsonColor.toHex(dividerColor!),
      if (dividerHeight != null) 'dividerHeight': dividerHeight,
      if (tabAlignment != null) 'tabAlignment': tabAlignment!.name,
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

    final rawTabBarStyle = value['tabBarStyle'];
    final tabBarStyle = rawTabBarStyle == null
        ? const ContainerStyle()
        : rawTabBarStyle is Map
        ? const ContainerStyle().patchFromJson(rawTabBarStyle)
        : (throw const FormatException('Style de barre d’onglets invalide.'));

    final rawIndicatorKind =
        value['indicatorKind'] ?? SuperTabIndicatorKind.underline.name;
    final indicatorKind = SuperTabIndicatorKind.values
        .where((candidate) => candidate.name == rawIndicatorKind)
        .firstOrNull;
    if (indicatorKind == null) {
      throw const FormatException('Type d’indicateur invalide.');
    }
    final rawIndicatorSize =
        value['indicatorSize'] ?? TabBarIndicatorSize.tab.name;
    final indicatorSize = TabBarIndicatorSize.values
        .where((candidate) => candidate.name == rawIndicatorSize)
        .firstOrNull;
    if (indicatorSize == null) {
      throw const FormatException('Taille d’indicateur invalide.');
    }
    double readNonNegativeDouble(String key, double fallback) {
      final raw = value[key];
      if (raw == null) return fallback;
      if (raw is! num || !raw.isFinite || raw < 0) {
        throw FormatException('Valeur numérique invalide pour $key.');
      }
      return raw.toDouble();
    }

    double? readNullableNonNegativeDouble(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! num || !raw.isFinite || raw < 0) {
        throw FormatException('Valeur numérique invalide pour $key.');
      }
      return raw.toDouble();
    }

    final indicatorColor = JsonColor.parseNullable(
      value['indicatorColor'],
      'indicatorColor',
    );
    final indicatorWeight = readNonNegativeDouble('indicatorWeight', 2.0);
    final indicatorRadius = readNonNegativeDouble('indicatorRadius', 0.0);
    final indicatorHorizontalPadding = readNonNegativeDouble(
      'indicatorHorizontalPadding',
      0.0,
    );
    final indicatorVerticalPadding = readNonNegativeDouble(
      'indicatorVerticalPadding',
      0.0,
    );
    final labelColor = JsonColor.parseNullable(
      value['labelColor'],
      'labelColor',
    );
    final unselectedLabelColor = JsonColor.parseNullable(
      value['unselectedLabelColor'],
      'unselectedLabelColor',
    );
    final overlayColor = JsonColor.parseNullable(
      value['overlayColor'],
      'overlayColor',
    );
    final labelHorizontalPadding = readNullableNonNegativeDouble(
      'labelHorizontalPadding',
    );
    final dividerColor = JsonColor.parseNullable(
      value['dividerColor'],
      'dividerColor',
    );
    final dividerHeight = readNullableNonNegativeDouble('dividerHeight');

    final rawTabAlignment = value['tabAlignment'];
    TabAlignment? tabAlignment;
    if (rawTabAlignment != null) {
      tabAlignment = TabAlignment.values
          .where((candidate) => candidate.name == rawTabAlignment)
          .firstOrNull;
      if (tabAlignment == null) {
        throw const FormatException('Alignement d’onglets invalide.');
      }
    }

    final (:placements, :slotTypes) = JsonReader.parseSlotPlacements(
      value['placements'],
      invalidPlacementsMessage: 'Placements d’onglets invalides.',
      invalidZoneMessage: 'Zone d’onglets invalide.',
      invalidSlotMessage: 'Slot d’onglet invalide.',
    );

    try {
      final meta = JsonReader.parseSlotContainerMetadata(
        value,
        placedIds: placements.values.expand((ids) => ids),
        invalidMetadataMessage: 'Métadonnées de slots d’onglets invalides.',
        invalidLabelsMessage: 'Libellés de slots d’onglets invalides.',
        invalidAxisMessage: 'Axe de zone d’onglet invalide.',
        invalidFlowMessage: 'Flux de zone d’onglet invalide.',
        invalidConstraintMessage: 'Contrainte de slot d’onglet invalide.',
        invalidSizeMessage: 'Taille de slot d’onglet invalide.',
      );
      return SuperTabConfig(
        mode: mode,
        tabBarPosition: tabBarPosition,
        isScrollable: isScrollable,
        initialIndex: initialIndex,
        binding: binding,
        allowAdd: allowAdd,
        allowRemove: allowRemove,
        emptyText: emptyText,
        tabBarStyle: tabBarStyle,
        indicatorKind: indicatorKind,
        indicatorSize: indicatorSize,
        indicatorColor: indicatorColor,
        indicatorWeight: indicatorWeight,
        indicatorRadius: indicatorRadius,
        indicatorHorizontalPadding: indicatorHorizontalPadding,
        indicatorVerticalPadding: indicatorVerticalPadding,
        labelColor: labelColor,
        unselectedLabelColor: unselectedLabelColor,
        overlayColor: overlayColor,
        labelHorizontalPadding: labelHorizontalPadding,
        dividerColor: dividerColor,
        dividerHeight: dividerHeight,
        tabAlignment: tabAlignment,
        placements: placements,
        slotTypes: slotTypes,
        zoneAxes: meta.zoneAxes,
        zoneFlows: meta.zoneFlows,
        slotPreferredSizes: meta.slotPreferredSizes,
        slotSizeConstraints: meta.slotSizeConstraints,
        slotLabels: meta.slotLabels,
      )..validate();
    } on ArgumentError {
      throw const FormatException('Identifiants de zones ou de slots invalides.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SuperTabConfig &&
          mode == other.mode &&
          tabBarPosition == other.tabBarPosition &&
          isScrollable == other.isScrollable &&
          initialIndex == other.initialIndex &&
          binding == other.binding &&
          allowAdd == other.allowAdd &&
          allowRemove == other.allowRemove &&
          emptyText == other.emptyText &&
          tabBarStyle == other.tabBarStyle &&
          indicatorKind == other.indicatorKind &&
          indicatorSize == other.indicatorSize &&
          indicatorColor == other.indicatorColor &&
          indicatorWeight == other.indicatorWeight &&
          indicatorRadius == other.indicatorRadius &&
          indicatorHorizontalPadding == other.indicatorHorizontalPadding &&
          indicatorVerticalPadding == other.indicatorVerticalPadding &&
          labelColor == other.labelColor &&
          unselectedLabelColor == other.unselectedLabelColor &&
          overlayColor == other.overlayColor &&
          labelHorizontalPadding == other.labelHorizontalPadding &&
          dividerColor == other.dividerColor &&
          dividerHeight == other.dividerHeight &&
          tabAlignment == other.tabAlignment &&
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
    mode,
    tabBarPosition,
    isScrollable,
    initialIndex,
    binding,
    allowAdd,
    allowRemove,
    emptyText,
    tabBarStyle,
    indicatorKind,
    indicatorSize,
    indicatorColor,
    indicatorWeight,
    indicatorRadius,
    indicatorHorizontalPadding,
    indicatorVerticalPadding,
    labelColor,
    unselectedLabelColor,
    overlayColor,
    labelHorizontalPadding,
    dividerColor,
    dividerHeight,
    tabAlignment,
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

/// Résumé des propriétés d'un [SuperTabConfig] pour l'info-bulle du menu contextuel.
String formatSuperTabTooltip({
  required String title,
  required SuperTabConfig config,
}) {
  final modeLabel =
      config.mode == SuperTabMode.dynamic ? 'Dynamique' : 'Statique';
  final posLabel =
      config.tabBarPosition == SuperTabBarPosition.bottom ? 'En bas' : 'En haut';
  final bindingLabel = config.binding == null
      ? null
      : '${config.binding!.repositoryId ?? 'Hérité'} → ${config.binding!.path}';
  final contentLine = config.mode == SuperTabMode.dynamic
      ? [
          'Liaison : ${bindingLabel ?? 'Aucune'}',
          'Ajout : ${config.allowAdd ? 'Activé' : 'Désactivé'}',
          'Suppression : ${config.allowRemove ? 'Activée' : 'Désactivée'}',
        ].join(' · ')
      : [
          'Onglets : ${config.slotsOf(SuperTabConfig.tabsZone).length}',
          'Index initial : ${config.initialIndex}',
          if (bindingLabel != null) 'Liaison : $bindingLabel',
        ].join(' · ');
  final indicatorColorSuffix = config.indicatorColor != null
      ? ' ${JsonColor.toHex(config.indicatorColor!)}'
      : '';
  final indicatorLabel = switch (config.indicatorKind) {
    SuperTabIndicatorKind.underline =>
      'Souligné (${JsonReader.formatNumber(config.indicatorWeight)} px$indicatorColorSuffix)',
    SuperTabIndicatorKind.box =>
      'Boîte (rayon ${JsonReader.formatNumber(config.indicatorRadius)} px$indicatorColorSuffix)',
    SuperTabIndicatorKind.none => 'Aucun',
  };
  final colorParts = <String>[
    if (config.labelColor != null)
      'Texte actif : ${JsonColor.toHex(config.labelColor!)}',
    if (config.unselectedLabelColor != null)
      'Texte inactif : ${JsonColor.toHex(config.unselectedLabelColor!)}',
    if (config.dividerColor != null)
      'Séparateur : ${JsonColor.toHex(config.dividerColor!)}',
  ];
  return [
    title,
    [
      'Mode : $modeLabel',
      'Barre : $posLabel',
      if (config.isScrollable) 'Défilable',
    ].join(' · '),
    contentLine,
    [
      'Indicateur : $indicatorLabel',
      ...colorParts,
    ].join(' · '),
  ].join('\n');
}

