/// Configuration persistée ([SuperTableConfig]) d'un tableau multi-colonnes [SuperTable].
///
/// Définit les colonnes ([SuperTableColumnConfig]), le nombre de colonnes figées
/// à gauche, les lignes d'en-tête et de pied, la liaison JSON et les placements
/// par zone (`cell:<colId>`, `header:<colId>`, `bottom:<colId>`).
library;

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show Axis;

import '../theme/container_style.dart';
import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'super_layout_config.dart' show SlotSizeConstraints, ZoneFlowConfig;

/// Configuration d'une colonne de [SuperTable].
@immutable
class SuperTableColumnConfig {
  const SuperTableColumnConfig({
    required this.id,
    this.title = '',
    this.width = defaultWidth,
    this.fillPercent = defaultFillPercent,
  });

  static const double defaultWidth = 140.0;
  static const double minWidth = 50.0;
  static const double maxWidth = 4000.0;
  static const double defaultFillPercent = 0.0;
  static const double maxFillPercent = 100.0;

  /// Identifiant unique de la colonne dans le tableau (ex: `'col_0'`).
  final String id;

  /// Titre affiché par défaut dans la cellule d'en-tête de la colonne.
  final String title;

  /// Largeur de la colonne en pixels (sert de largeur minimale si [isFill] est vrai).
  final double width;

  /// Pourcentage (`0` à `100`) de l'espace horizontal restant occupé par la colonne.
  ///
  /// `0` signifie que la colonne a une largeur fixe égale à [width].
  final double fillPercent;

  /// Indique si la colonne s'étire pour occuper une part de l'espace horizontal restant.
  bool get isFill => fillPercent > 0;

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Identifiant de colonne invalide.');
    }
    if (!width.isFinite || width < minWidth || width > maxWidth) {
      throw const FormatException('Largeur de colonne invalide.');
    }
    if (!fillPercent.isFinite ||
        fillPercent < 0 ||
        fillPercent > maxFillPercent) {
      throw const FormatException(
        'Pourcentage de remplissage de colonne invalide.',
      );
    }
  }

  SuperTableColumnConfig copyWith({
    String? id,
    String? title,
    double? width,
    double? fillPercent,
  }) => SuperTableColumnConfig(
    id: id ?? this.id,
    title: title ?? this.title,
    width: width ?? this.width,
    fillPercent: fillPercent ?? this.fillPercent,
  );

  Map<String, Object?> toJson() {
    validate();
    return {
      'id': id,
      'title': title,
      'width': width,
      'fillPercent': fillPercent,
    };
  }

  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'id': id,
      if (title.isNotEmpty) 'title': title,
      if (width != defaultWidth) 'width': width,
      if (fillPercent != defaultFillPercent) 'fillPercent': fillPercent,
    };
  }

  factory SuperTableColumnConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Configuration de colonne invalide.');
    }
    final rawId = value['id'];
    final rawTitle = value['title'] ?? '';
    final rawWidth = value['width'] ?? defaultWidth;
    final rawFillPercent = value['fillPercent'] ?? defaultFillPercent;
    if (rawId is! String ||
        rawId.trim().isEmpty ||
        rawTitle is! String ||
        rawWidth is! num ||
        !rawWidth.isFinite ||
        rawFillPercent is! num ||
        !rawFillPercent.isFinite) {
      throw const FormatException('Configuration de colonne invalide.');
    }
    return SuperTableColumnConfig(
      id: rawId.trim(),
      title: rawTitle,
      width: rawWidth.toDouble(),
      fillPercent: rawFillPercent.toDouble(),
    )..validate();
  }

  @override
  bool operator ==(Object other) =>
      other is SuperTableColumnConfig &&
      other.id == id &&
      other.title == title &&
      other.width == width &&
      other.fillPercent == fillPercent;

  @override
  int get hashCode => Object.hash(id, title, width, fillPercent);
}

/// Configuration persistée d'un composant [SuperTable] lié à un repository JSON.
@immutable
class SuperTableConfig extends ComponentConfig {
  SuperTableConfig({
    this.binding,
    List<SuperTableColumnConfig> columns = defaultColumns,
    this.colFreezeLeftCount = 0,
    this.showHeaderRow = true,
    this.showBottomRow = false,
    this.headerRowHeight = 40.0,
    this.rowHeight = 40.0,
    this.bottomRowHeight = 40.0,
    this.allowAdd = false,
    this.allowRemove = false,
    this.animateSelectionAndHover = true,
    this.emptyText = 'Aucun élément',
    this.itemId,
    Map<String, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<String, Axis> zoneAxes = const {},
    Map<String, ZoneFlowConfig> zoneFlows = const {},
    Map<String, ContainerStyle> zoneStyles = const {},
    Map<String, Size?> slotPreferredSizes = const {},
    Map<String, SlotSizeConstraints> slotSizeConstraints = const {},
    Map<String, String> slotLabels = const {},
  }) : columns = List.unmodifiable(columns),
       placements = JsonReader.normalizePlacements(placements),
       slotTypes = Map.unmodifiable(slotTypes),
       zoneAxes = Map.unmodifiable(zoneAxes),
       zoneFlows = JsonReader.normalizeZoneFlows(zoneFlows),
       zoneStyles = Map.unmodifiable({
         for (final entry in zoneStyles.entries)
           if (entry.value != const ContainerStyle()) entry.key: entry.value,
       }),
       slotPreferredSizes = Map.unmodifiable(slotPreferredSizes),
       slotSizeConstraints = Map.unmodifiable(slotSizeConstraints),
       slotLabels = JsonReader.normalizeSlotLabels(slotLabels) {
    final colIds = columns.map((c) => c.id.trim()).toList();
    if (columns.isEmpty ||
        colIds.any((id) => id.isEmpty) ||
        colIds.toSet().length != colIds.length ||
        JsonReader.hasInvalidSlotContainerMaps(
          placements: this.placements,
          slotTypes: this.slotTypes,
          zoneAxes: this.zoneAxes,
          zoneFlows: this.zoneFlows,
          slotPreferredSizes: this.slotPreferredSizes,
          slotSizeConstraints: this.slotSizeConstraints,
          slotLabels: this.slotLabels,
          extraZoneKeys: this.zoneStyles.keys,
        )) {
      throw ArgumentError('Invalid SuperTable configuration.');
    }
  }

  static const List<SuperTableColumnConfig> defaultColumns = [
    SuperTableColumnConfig(id: 'col_0', title: 'Colonne 1'),
    SuperTableColumnConfig(id: 'col_1', title: 'Colonne 2'),
    SuperTableColumnConfig(id: 'col_2', title: 'Colonne 3'),
  ];

  static String headerZoneFor(String colId) => 'header:$colId';
  static String cellZoneFor(String colId) => 'cell:$colId';
  static String bottomZoneFor(String colId) => 'bottom:$colId';

  static const double minRowHeight = 16.0;
  static const double maxRowHeight = 400.0;

  /// Tableau JSON du repository lié, ou `null` pour une table non liée.
  final JsonTextBinding? binding;

  /// Colonnes du tableau.
  final List<SuperTableColumnConfig> columns;

  /// Nombre de colonnes figées à gauche.
  final int colFreezeLeftCount;

  /// Affiche la ligne d'en-tête figée en haut.
  final bool showHeaderRow;

  /// Affiche la ligne de pied figée en bas.
  final bool showBottomRow;

  /// Hauteur de la ligne d'en-tête en pixels.
  final double headerRowHeight;

  /// Hauteur d'une ligne de données en pixels.
  final double rowHeight;

  /// Hauteur de la ligne de pied en pixels.
  final double bottomRowHeight;

  /// Autorise l'ajout d'une ligne au tableau JSON lié.
  final bool allowAdd;

  /// Autorise la suppression d'une ligne du tableau JSON lié.
  final bool allowRemove;

  /// Anime verticalement le déplacement du fond de la ligne sélectionnée et survolée.
  final bool animateSelectionAndHover;

  /// Message affiché lorsque le tableau est vide.
  final String emptyText;

  /// ID technique distinct pour l'[IterableContent] des lignes.
  final String? itemId;

  final Map<String, List<String>> placements;
  final Map<String, String> slotTypes;
  final Map<String, Axis> zoneAxes;
  final Map<String, ZoneFlowConfig> zoneFlows;
  final Map<String, ContainerStyle> zoneStyles;
  final Map<String, Size?> slotPreferredSizes;
  final Map<String, SlotSizeConstraints> slotSizeConstraints;
  final Map<String, String> slotLabels;

  @override
  String get componentType => 'table';

  @override
  void validate() {
    binding?.validate();
    if (columns.isEmpty) {
      throw const FormatException(
        'Le tableau doit contenir au moins une colonne.',
      );
    }
    for (final col in columns) {
      col.validate();
    }
    if (colFreezeLeftCount < 0 || colFreezeLeftCount > columns.length) {
      throw const FormatException(
        'Nombre de colonnes figées à gauche invalide.',
      );
    }
    if (!headerRowHeight.isFinite ||
        headerRowHeight < minRowHeight ||
        headerRowHeight > maxRowHeight) {
      throw const FormatException('Hauteur d’en-tête invalide.');
    }
    if (!rowHeight.isFinite ||
        rowHeight < minRowHeight ||
        rowHeight > maxRowHeight) {
      throw const FormatException('Hauteur de ligne invalide.');
    }
    if (!bottomRowHeight.isFinite ||
        bottomRowHeight < minRowHeight ||
        bottomRowHeight > maxRowHeight) {
      throw const FormatException('Hauteur de ligne de pied invalide.');
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
  ContainerStyle zoneStyleOf(String zone) =>
      zoneStyles[zone] ?? const ContainerStyle();

  Set<String> get placedSlotIds => {
    for (final ids in placements.values) ...ids,
  };

  Set<String> slotsRemovedWith(String id) => <String>{id};

  SuperTableConfig copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    List<SuperTableColumnConfig>? columns,
    int? colFreezeLeftCount,
    bool? showHeaderRow,
    bool? showBottomRow,
    double? headerRowHeight,
    double? rowHeight,
    double? bottomRowHeight,
    bool? allowAdd,
    bool? allowRemove,
    bool? animateSelectionAndHover,
    String? emptyText,
    String? itemId,
    Map<String, List<String>>? placements,
    Map<String, String>? slotTypes,
    Map<String, Axis>? zoneAxes,
    Map<String, ZoneFlowConfig>? zoneFlows,
    Map<String, ContainerStyle>? zoneStyles,
    Map<String, Size?>? slotPreferredSizes,
    Map<String, SlotSizeConstraints>? slotSizeConstraints,
    Map<String, String>? slotLabels,
  }) => SuperTableConfig(
    binding: clearBinding ? null : binding ?? this.binding,
    columns: columns ?? this.columns,
    colFreezeLeftCount: colFreezeLeftCount ?? this.colFreezeLeftCount,
    showHeaderRow: showHeaderRow ?? this.showHeaderRow,
    showBottomRow: showBottomRow ?? this.showBottomRow,
    headerRowHeight: headerRowHeight ?? this.headerRowHeight,
    rowHeight: rowHeight ?? this.rowHeight,
    bottomRowHeight: bottomRowHeight ?? this.bottomRowHeight,
    allowAdd: allowAdd ?? this.allowAdd,
    allowRemove: allowRemove ?? this.allowRemove,
    animateSelectionAndHover:
        animateSelectionAndHover ?? this.animateSelectionAndHover,
    emptyText: emptyText ?? this.emptyText,
    itemId: itemId ?? this.itemId,
    placements: placements ?? this.placements,
    slotTypes: slotTypes ?? this.slotTypes,
    zoneAxes: zoneAxes ?? this.zoneAxes,
    zoneFlows: zoneFlows ?? this.zoneFlows,
    zoneStyles: zoneStyles ?? this.zoneStyles,
    slotPreferredSizes: slotPreferredSizes ?? this.slotPreferredSizes,
    slotSizeConstraints: slotSizeConstraints ?? this.slotSizeConstraints,
    slotLabels: slotLabels ?? this.slotLabels,
  );

  SuperTableConfig withColumnWidths(Map<int, double> widthsByIndex) {
    final nextCols = [
      for (var i = 0; i < columns.length; i++)
        widthsByIndex.containsKey(i) && !columns[i].isFill
            ? columns[i].copyWith(
                width: widthsByIndex[i]!.clamp(
                  SuperTableColumnConfig.minWidth,
                  SuperTableColumnConfig.maxWidth,
                ),
              )
            : columns[i],
    ];
    return copyWith(columns: nextCols);
  }

  SuperTableConfig withSlotAdded(
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

  SuperTableConfig withoutSlot(String id) {
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

  SuperTableConfig withZoneAxis(
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

  SuperTableConfig withZoneFlow(String zone, ZoneFlowConfig flow) =>
      copyWith(zoneFlows: JsonReader.updateZoneFlowMap(zoneFlows, zone, flow));

  SuperTableConfig withZoneStyle(String zone, ContainerStyle style) {
    final next = {...zoneStyles};
    if (style == const ContainerStyle()) {
      next.remove(zone);
    } else {
      next[zone] = style;
    }
    return copyWith(zoneStyles: next);
  }

  SuperTableConfig withSlotSize(String id, Size? size) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes, id: size},
    slotSizeConstraints: {...slotSizeConstraints}..remove(id),
  );

  SuperTableConfig withSlotSizeConstraints(
    String id,
    SlotSizeConstraints constraints,
  ) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints, id: constraints},
  );

  SuperTableConfig withSlotLabel(String id, String? label) {
    if (!placedSlotIds.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown SuperTable slot.');
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
      'columns': [for (final col in columns) col.toJson()],
      'colFreezeLeftCount': colFreezeLeftCount,
      'showHeaderRow': showHeaderRow,
      'showBottomRow': showBottomRow,
      'headerRowHeight': headerRowHeight,
      'rowHeight': rowHeight,
      'bottomRowHeight': bottomRowHeight,
      'allowAdd': allowAdd,
      'allowRemove': allowRemove,
      'animateSelectionAndHover': animateSelectionAndHover,
      'emptyText': emptyText,
      if (itemId != null) 'itemId': itemId,
      ...JsonReader.encodeSlotContainerJson(
        placements: placements,
        slotTypeOf: slotTypeOf,
        zoneAxes: zoneAxes,
        zoneFlows: zoneFlows,
        zoneStyles: zoneStyles,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
      ),
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    final d = SuperTableConfig();
    return {
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (!listEquals(columns, d.columns))
        'columns': [for (final col in columns) col.toCompactJson()],
      if (colFreezeLeftCount != d.colFreezeLeftCount)
        'colFreezeLeftCount': colFreezeLeftCount,
      if (showHeaderRow != d.showHeaderRow) 'showHeaderRow': showHeaderRow,
      if (showBottomRow != d.showBottomRow) 'showBottomRow': showBottomRow,
      if (headerRowHeight != d.headerRowHeight)
        'headerRowHeight': headerRowHeight,
      if (rowHeight != d.rowHeight) 'rowHeight': rowHeight,
      if (bottomRowHeight != d.bottomRowHeight)
        'bottomRowHeight': bottomRowHeight,
      if (allowAdd != d.allowAdd) 'allowAdd': allowAdd,
      if (allowRemove != d.allowRemove) 'allowRemove': allowRemove,
      if (animateSelectionAndHover != d.animateSelectionAndHover)
        'animateSelectionAndHover': animateSelectionAndHover,
      if (emptyText != d.emptyText) 'emptyText': emptyText,
      if (itemId != null) 'itemId': itemId,
      ...JsonReader.encodeSlotContainerJson(
        placements: placements,
        slotTypeOf: slotTypeOf,
        zoneAxes: zoneAxes,
        zoneFlows: zoneFlows,
        zoneStyles: zoneStyles,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
        compact: true,
      ),
    };
  }

  @override
  SuperTableConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperTableConfig.fromJson({...toJson(), ...patch});

  factory SuperTableConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Configuration de Table invalide.');
    }
    final binding = value.containsKey('binding') && value['binding'] != null
        ? JsonTextBinding.fromJson(value['binding'])
        : null;
    final rawColumns = value['columns'];
    final List<SuperTableColumnConfig> columns;
    if (rawColumns == null) {
      columns = defaultColumns;
    } else if (rawColumns is List) {
      columns = [
        for (final item in rawColumns) SuperTableColumnConfig.fromJson(item),
      ];
    } else {
      throw const FormatException('Colonnes de Table invalides.');
    }

    final rawFreeze = value['colFreezeLeftCount'] ?? 0;
    final showHeaderRow = value['showHeaderRow'] ?? true;
    final showBottomRow = value['showBottomRow'] ?? false;
    final allowAdd = value['allowAdd'] ?? false;
    final allowRemove = value['allowRemove'] ?? false;
    final animateSelectionAndHover = value['animateSelectionAndHover'] ?? true;
    final emptyText = value['emptyText'] ?? 'Aucun élément';
    final itemId = value['itemId'];

    if (rawFreeze is! int ||
        showHeaderRow is! bool ||
        showBottomRow is! bool ||
        allowAdd is! bool ||
        allowRemove is! bool ||
        animateSelectionAndHover is! bool ||
        emptyText is! String ||
        (itemId != null && itemId is! String)) {
      throw const FormatException('Options de Table invalides.');
    }

    double readDouble(String key, double fallback) {
      final raw = value[key];
      if (raw == null) return fallback;
      if (raw is! num || !raw.isFinite) {
        throw FormatException('Valeur numérique invalide pour $key.');
      }
      return raw.toDouble();
    }

    final headerRowHeight = readDouble('headerRowHeight', 40.0);
    final rowHeight = readDouble('rowHeight', 40.0);
    final bottomRowHeight = readDouble('bottomRowHeight', 40.0);

    final (:placements, :slotTypes) = JsonReader.parseSlotPlacements(
      value['placements'],
      invalidPlacementsMessage: 'Placements de Table invalides.',
      invalidZoneMessage: 'Zone de Table invalide.',
      invalidSlotMessage: 'Slot de Table invalide.',
    );

    try {
      final meta = JsonReader.parseSlotContainerMetadata(
        value,
        placedIds: placements.values.expand((ids) => ids),
        parseZoneStyles: true,
        invalidMetadataMessage: 'Métadonnées de slots de Table invalides.',
        invalidLabelsMessage: 'Libellés de slots de Table invalides.',
        invalidAxisMessage: 'Axe de zone de Table invalide.',
        invalidFlowMessage: 'Flux de zone de Table invalide.',
        invalidStyleMessage: 'Style de zone de Table invalide.',
        invalidConstraintMessage: 'Contrainte de slot de Table invalide.',
        invalidSizeMessage: 'Taille de slot de Table invalide.',
      );
      return SuperTableConfig(
        binding: binding,
        columns: columns,
        colFreezeLeftCount: rawFreeze,
        showHeaderRow: showHeaderRow,
        showBottomRow: showBottomRow,
        headerRowHeight: headerRowHeight,
        rowHeight: rowHeight,
        bottomRowHeight: bottomRowHeight,
        allowAdd: allowAdd,
        allowRemove: allowRemove,
        animateSelectionAndHover: animateSelectionAndHover,
        emptyText: emptyText,
        itemId: itemId as String?,
        placements: placements,
        slotTypes: slotTypes,
        zoneAxes: meta.zoneAxes,
        zoneFlows: meta.zoneFlows,
        zoneStyles: meta.zoneStyles,
        slotPreferredSizes: meta.slotPreferredSizes,
        slotSizeConstraints: meta.slotSizeConstraints,
        slotLabels: meta.slotLabels,
      )..validate();
    } on ArgumentError {
      throw const FormatException(
        'Identifiants de zones ou de slots de Table invalides.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SuperTableConfig &&
          binding == other.binding &&
          listEquals(columns, other.columns) &&
          colFreezeLeftCount == other.colFreezeLeftCount &&
          showHeaderRow == other.showHeaderRow &&
          showBottomRow == other.showBottomRow &&
          headerRowHeight == other.headerRowHeight &&
          rowHeight == other.rowHeight &&
          bottomRowHeight == other.bottomRowHeight &&
          allowAdd == other.allowAdd &&
          allowRemove == other.allowRemove &&
          animateSelectionAndHover == other.animateSelectionAndHover &&
          emptyText == other.emptyText &&
          itemId == other.itemId &&
          mapEquals(zoneStyles, other.zoneStyles) &&
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
    Object.hashAll(columns),
    colFreezeLeftCount,
    showHeaderRow,
    showBottomRow,
    headerRowHeight,
    rowHeight,
    bottomRowHeight,
    allowAdd,
    allowRemove,
    animateSelectionAndHover,
    emptyText,
    itemId,
    ...JsonReader.slotLayoutHashParts(
      placements: placements,
      slotTypes: slotTypes,
      zoneAxes: zoneAxes,
      zoneFlows: zoneFlows,
      zoneStyles: zoneStyles,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    ),
  ]);
}
