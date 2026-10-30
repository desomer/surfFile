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
       placements = Map.unmodifiable({
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
       zoneStyles = Map.unmodifiable({
         for (final entry in zoneStyles.entries)
           if (entry.value != const ContainerStyle()) entry.key: entry.value,
       }),
       slotPreferredSizes = Map.unmodifiable(slotPreferredSizes),
       slotSizeConstraints = Map.unmodifiable(slotSizeConstraints),
       slotLabels = Map.unmodifiable({
         for (final entry in slotLabels.entries)
           if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
       }) {
    final colIds = columns.map((c) => c.id.trim()).toList();
    final ids = placements.values.expand((value) => value).toList();
    if (columns.isEmpty ||
        colIds.any((id) => id.isEmpty) ||
        colIds.toSet().length != colIds.length ||
        ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length ||
        placements.keys.any((id) => id.trim().isEmpty) ||
        zoneAxes.keys.any((id) => id.trim().isEmpty) ||
        zoneFlows.keys.any((id) => id.trim().isEmpty) ||
        zoneStyles.keys.any((id) => id.trim().isEmpty) ||
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

  SuperTableConfig withoutSlot(String id) {
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

  SuperTableConfig withZoneAxis(
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

  SuperTableConfig withZoneFlow(String zone, ZoneFlowConfig flow) {
    final next = {...zoneFlows};
    if (flow.isDefault) {
      next.remove(zone);
    } else {
      next[zone] = flow;
    }
    return copyWith(zoneFlows: next);
  }

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
      if (zoneStyles.isNotEmpty)
        'zoneStyles': {
          for (final entry in zoneStyles.entries)
            if (entry.value != const ContainerStyle())
              entry.key: entry.value.toJson(),
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
      if (zoneStyles.isNotEmpty)
        'zoneStyles': {
          for (final entry in zoneStyles.entries)
            if (entry.value != const ContainerStyle())
              entry.key: entry.value.toCompactJson(),
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

    final rawPlacements = value['placements'] ?? const {};
    if (rawPlacements is! Map) {
      throw const FormatException('Placements de Table invalides.');
    }
    final placements = <String, List<String>>{};
    final types = <String, String>{};
    for (final entry in rawPlacements.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Zone de Table invalide.');
      }
      final ids = <String>[];
      for (final slot in entry.value as List) {
        if (slot is String && slot.trim().isNotEmpty) {
          ids.add(slot);
          types[slot] = JsonComponentType.normalize(slot, id: slot);
          continue;
        }
        if (slot is! Map || slot['id'] is! String || slot['type'] is! String) {
          throw const FormatException('Slot de Table invalide.');
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
      final rawStyles = value['zoneStyles'] ?? const {};
      if (rawSizes is! Map ||
          rawConstraints is! Map ||
          rawLabels is! Map ||
          rawAxes is! Map ||
          rawFlows is! Map ||
          rawStyles is! Map) {
        throw const FormatException('Métadonnées de slots de Table invalides.');
      }
      if (rawLabels.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
        throw const FormatException('Libellés de slots de Table invalides.');
      }
      final parsedAxes = <String, Axis>{};
      for (final entry in rawAxes.entries) {
        if (entry.key is! String) {
          throw const FormatException('Axe de zone de Table invalide.');
        }
        final axis = Axis.values
            .where((candidate) => candidate.name == entry.value)
            .firstOrNull;
        if (axis == null) {
          throw const FormatException('Axe de zone de Table invalide.');
        }
        parsedAxes[entry.key as String] = axis;
      }
      final parsedFlows = <String, ZoneFlowConfig>{};
      for (final entry in rawFlows.entries) {
        if (entry.key is! String) {
          throw const FormatException('Flux de zone de Table invalide.');
        }
        parsedFlows[entry.key as String] = ZoneFlowConfig.fromJson(entry.value);
      }
      final parsedStyles = <String, ContainerStyle>{};
      for (final entry in rawStyles.entries) {
        if (entry.key is! String) {
          throw const FormatException('Style de zone de Table invalide.');
        }
        parsedStyles[entry.key as String] = ContainerStyle.fromJson(entry.value);
      }
      if (rawConstraints.keys.any((key) => key is! String)) {
        throw const FormatException('Contrainte de slot de Table invalide.');
      }
      final sizes = <String, Size?>{};
      for (final entry in rawSizes.entries) {
        if (entry.key is! String) {
          throw const FormatException('Taille de slot de Table invalide.');
        }
        sizes[entry.key as String] = JsonDimension.parsePreferredSize(
          entry.value,
          allowInfiniteSides: true,
        );
      }
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
        slotTypes: types,
        zoneAxes: parsedAxes,
        zoneFlows: parsedFlows,
        zoneStyles: parsedStyles,
        slotPreferredSizes: sizes,
        slotSizeConstraints: SlotSizeConstraints.parseMap(
          rawConstraints,
          placedIds: placements.values.expand((ids) => ids),
        ),
        slotLabels: Map<String, String>.from(rawLabels),
      )..validate();
    } on ArgumentError {
      throw const FormatException(
        'Identifiants de zones ou de slots de Table invalides.',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SuperTableConfig) return false;
    if (binding != other.binding ||
        !listEquals(columns, other.columns) ||
        colFreezeLeftCount != other.colFreezeLeftCount ||
        showHeaderRow != other.showHeaderRow ||
        showBottomRow != other.showBottomRow ||
        headerRowHeight != other.headerRowHeight ||
        rowHeight != other.rowHeight ||
        bottomRowHeight != other.bottomRowHeight ||
        allowAdd != other.allowAdd ||
        allowRemove != other.allowRemove ||
        animateSelectionAndHover != other.animateSelectionAndHover ||
        emptyText != other.emptyText ||
        itemId != other.itemId ||
        placements.length != other.placements.length ||
        !mapEquals(slotTypes, other.slotTypes) ||
        !mapEquals(zoneAxes, other.zoneAxes) ||
        !mapEquals(zoneFlows, other.zoneFlows) ||
        !mapEquals(zoneStyles, other.zoneStyles) ||
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
      zoneStyles.entries.map((e) => Object.hash(e.key, e.value)),
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
