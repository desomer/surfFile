/// Réglages persistés d'un composant graphique `SuperChart` (`fl_chart`).
///
/// Enregistrés dans `Appearance.components` sous le discriminateur `'chart'`
/// et modifiés via la fenêtre « Graphique » (`showSuperChartEditor`).
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';

/// Type de graphique `fl_chart` affiché par `SuperChart`.
enum SuperChartKind {
  line('Courbe / Aire'),
  bar('Barres'),
  pie('Camembert / Donut'),
  scatter('Nuage de points'),
  radar('Radar');

  const SuperChartKind(this.label);

  final String label;
}

/// Définition d'une série de données dans un `SuperChart`.
@immutable
class SuperChartSeries {
  const SuperChartSeries({
    this.id = 'series-1',
    this.label = 'Série 1',
    this.valuePath = 'value',
    this.secondaryValuePath = '',
    this.color,
    this.strokeWidth = 3.0,
    this.radius = 6.0,
    this.isCurved = true,
    this.belowBarArea = false,
    this.showDots = true,
  });

  /// Identifiant technique de la série.
  final String id;

  /// Nom affiché dans la légende et les infobulles.
  final String label;

  /// Chemin relatif de la valeur numérique Y dans chaque élément du tableau
  /// (ex: `montant`, `stats.ca`), ou chaîne vide `''` lorsque le tableau
  /// contient directement des nombres.
  final String valuePath;

  /// Chemin relatif secondaire optionnel (ex: coordonnée X numérique pour
  /// un `ScatterChart` ou un `LineChart`).
  final String secondaryValuePath;

  /// Couleur principale de la série (`null` = couleur automatique de palette).
  final Color? color;

  /// Épaisseur du trait (`LineChart`, `RadarChart`).
  final double strokeWidth;

  /// Rayon des points (`LineChart`, `ScatterChart`) ou largeur des barres (`BarChart`).
  final double radius;

  /// Lisse la courbe (`LineChart`).
  final bool isCurved;

  /// Remplit l'aire sous la courbe (`LineChart`).
  final bool belowBarArea;

  /// Affiche les marqueurs de points sur la courbe (`LineChart`).
  final bool showDots;

  static const minStrokeWidth = 0.5;
  static const maxStrokeWidth = 24.0;
  static const minRadius = 1.0;
  static const maxRadius = 120.0;

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Identifiant de série de graphique vide.');
    }
    final trimmedValue = valuePath.trim();
    if (trimmedValue.isNotEmpty) {
      final parsed = JsonAttributePath(trimmedValue);
      if (!parsed.isResolved) {
        throw const FormatException(
          'Le chemin de valeur d’une série est relatif à l’élément et ne doit pas contenir [?].',
        );
      }
    }
    final trimmedSecondary = secondaryValuePath.trim();
    if (trimmedSecondary.isNotEmpty) {
      final parsed = JsonAttributePath(trimmedSecondary);
      if (!parsed.isResolved) {
        throw const FormatException(
          'Le chemin secondaire d’une série ne doit pas contenir [?].',
        );
      }
    }
    if (!strokeWidth.isFinite ||
        strokeWidth < minStrokeWidth ||
        strokeWidth > maxStrokeWidth) {
      throw const FormatException('Épaisseur de série invalide.');
    }
    if (!radius.isFinite || radius < minRadius || radius > maxRadius) {
      throw const FormatException('Rayon / largeur de série invalide.');
    }
  }

  SuperChartSeries copyWith({
    String? id,
    String? label,
    String? valuePath,
    String? secondaryValuePath,
    Color? color,
    bool clearColor = false,
    double? strokeWidth,
    double? radius,
    bool? isCurved,
    bool? belowBarArea,
    bool? showDots,
  }) => SuperChartSeries(
    id: id ?? this.id,
    label: label ?? this.label,
    valuePath: valuePath ?? this.valuePath,
    secondaryValuePath: secondaryValuePath ?? this.secondaryValuePath,
    color: clearColor ? null : color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    radius: radius ?? this.radius,
    isCurved: isCurved ?? this.isCurved,
    belowBarArea: belowBarArea ?? this.belowBarArea,
    showDots: showDots ?? this.showDots,
  );

  Map<String, Object?> toJson() {
    validate();
    return {
      'id': id,
      'label': label,
      'valuePath': valuePath,
      if (secondaryValuePath.isNotEmpty)
        'secondaryValuePath': secondaryValuePath,
      if (color != null) 'color': color!.toARGB32(),
      'strokeWidth': strokeWidth,
      'radius': radius,
      'isCurved': isCurved,
      'belowBarArea': belowBarArea,
      'showDots': showDots,
    };
  }

  Map<String, Object?> toCompactJson() {
    validate();
    const d = SuperChartSeries();
    return {
      if (id != d.id) 'id': id,
      if (label != d.label) 'label': label,
      if (valuePath != d.valuePath) 'valuePath': valuePath,
      if (secondaryValuePath.isNotEmpty)
        'secondaryValuePath': secondaryValuePath,
      if (color != null) 'color': JsonColor.toHex(color!),
      if (strokeWidth != d.strokeWidth) 'strokeWidth': strokeWidth,
      if (radius != d.radius) 'radius': radius,
      if (isCurved != d.isCurved) 'isCurved': isCurved,
      if (belowBarArea != d.belowBarArea) 'belowBarArea': belowBarArea,
      if (showDots != d.showDots) 'showDots': showDots,
    };
  }

  static const _keys = {
    'id',
    'label',
    'valuePath',
    'secondaryValuePath',
    'color',
    'strokeWidth',
    'radius',
    'isCurved',
    'belowBarArea',
    'showDots',
  };

  factory SuperChartSeries.fromJson(
    Object? value, {
    SuperChartSeries fallback = const SuperChartSeries(),
  }) {
    if (value is! Map || value.keys.any((key) => !_keys.contains(key))) {
      throw const FormatException('Configuration de série de graphique invalide.');
    }
    T read<T>(String key, T fallbackVal) {
      final raw = value[key];
      if (raw == null) return fallbackVal;
      if (raw is! T) {
        throw const FormatException('Configuration de série de graphique invalide.');
      }
      return raw;
    }

    double readNum(String key, double fallbackVal) {
      final raw = value[key];
      if (raw == null) return fallbackVal;
      if (raw is! num) {
        throw const FormatException('Configuration de série de graphique invalide.');
      }
      return raw.toDouble();
    }

    final Color? parsedColor;
    if (!value.containsKey('color')) {
      parsedColor = fallback.color;
    } else if (value['color'] == null) {
      parsedColor = null;
    } else {
      parsedColor = JsonColor.parse(value['color'], 'series.color');
    }

    final result = SuperChartSeries(
      id: read<String>('id', fallback.id),
      label: read<String>('label', fallback.label),
      valuePath: read<String>('valuePath', fallback.valuePath),
      secondaryValuePath: read<String>(
        'secondaryValuePath',
        fallback.secondaryValuePath,
      ),
      color: parsedColor,
      strokeWidth: readNum('strokeWidth', fallback.strokeWidth),
      radius: readNum('radius', fallback.radius),
      isCurved: read<bool>('isCurved', fallback.isCurved),
      belowBarArea: read<bool>('belowBarArea', fallback.belowBarArea),
      showDots: read<bool>('showDots', fallback.showDots),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperChartSeries &&
      other.id == id &&
      other.label == label &&
      other.valuePath == valuePath &&
      other.secondaryValuePath == secondaryValuePath &&
      other.color == color &&
      other.strokeWidth == strokeWidth &&
      other.radius == radius &&
      other.isCurved == isCurved &&
      other.belowBarArea == belowBarArea &&
      other.showDots == showDots;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    valuePath,
    secondaryValuePath,
    color,
    strokeWidth,
    radius,
    isCurved,
    belowBarArea,
    showDots,
  );
}

/// Configuration persistée d'un composant `SuperChart`.
@immutable
class SuperChartConfig extends ComponentConfig {
  const SuperChartConfig({
    this.binding,
    this.kind = SuperChartKind.line,
    this.labelPath = 'label',
    this.series = const [SuperChartSeries()],
    this.showGrid = true,
    this.showLegend = true,
    this.enableTooltips = true,
    this.enableSelection = true,
    this.showAxisLabels = true,
    this.showAxisTitles = false,
    this.xAxisTitle = '',
    this.yAxisTitle = '',
    this.minY,
    this.maxY,
    this.barStacked = false,
    this.pieCenterSpaceRadius = 32.0,
    this.pieSectionsSpace = 2.0,
    this.showDemoWhenUnbound = true,
    this.emptyText = 'Aucune donnée',
  });

  /// Liaison vers le tableau JSON source (ex: `ventes` ou `clients[?].ventes`).
  final JsonTextBinding? binding;

  /// Type de graphique `fl_chart`.
  final SuperChartKind kind;

  /// Chemin relatif du libellé (axe X / tranche / radar) dans chaque élément
  /// du tableau JSON (ex: `mois`, `nom`). Vide = indice de la ligne.
  final String labelPath;

  /// Séries numériques représentées sur le graphique.
  final List<SuperChartSeries> series;

  /// Affiche la grille de fond (Line, Bar, Scatter, Radar).
  final bool showGrid;

  /// Affiche la légende des séries / sections.
  final bool showLegend;

  /// Active les infobulles au survol / clic.
  final bool enableTooltips;

  /// Synchronise la sélection au clic avec le `JsonArrayBinding` du tableau.
  final bool enableSelection;

  /// Affiche les étiquettes de graduation sur les axes.
  final bool showAxisLabels;

  /// Affiche les titres des axes X et Y.
  final bool showAxisTitles;

  /// Titre de l'axe horizontal X.
  final String xAxisTitle;

  /// Titre de l'axe vertical Y.
  final String yAxisTitle;

  /// Borne minimale manuelle de l'axe Y (`null` = automatique).
  final double? minY;

  /// Borne maximale manuelle de l'axe Y (`null` = automatique).
  final double? maxY;

  /// Empile les séries dans un `BarChart` au lieu de les grouper côte à côte.
  final bool barStacked;

  /// Rayon de l'espace central d'un `PieChart` (0 = camembert plein, > 0 = donut).
  final double pieCenterSpaceRadius;

  /// Espacement entre les sections d'un `PieChart`.
  final double pieSectionsSpace;

  /// Affiche des données de démonstration lorsque le graphique n'est pas lié
  /// ou est affiché dans un gabarit placeholder.
  final bool showDemoWhenUnbound;

  /// Message affiché lorsque le tableau lié est vide.
  final String emptyText;

  static const maxPieCenterSpaceRadius = 300.0;
  static const maxPieSectionsSpace = 40.0;

  @override
  String get componentType => 'chart';

  @override
  void validate() {
    binding?.validate();
    final trimmedLabel = labelPath.trim();
    if (trimmedLabel.isNotEmpty) {
      final parsed = JsonAttributePath(trimmedLabel);
      if (!parsed.isResolved) {
        throw const FormatException(
          'Le chemin de libellé est relatif à l’élément et ne doit pas contenir [?].',
        );
      }
    }
    if (series.isEmpty) {
      throw const FormatException(
        'Le graphique doit comporter au moins une série.',
      );
    }
    final ids = <String>{};
    for (final item in series) {
      item.validate();
      if (!ids.add(item.id)) {
        throw const FormatException('Identifiant de série dupliqué.');
      }
    }
    if (minY != null && !minY!.isFinite) {
      throw const FormatException('Borne minimale Y invalide.');
    }
    if (maxY != null && !maxY!.isFinite) {
      throw const FormatException('Borne maximale Y invalide.');
    }
    if (minY != null && maxY != null && minY! >= maxY!) {
      throw const FormatException(
        'La borne minimale Y doit être strictement inférieure à la borne maximale Y.',
      );
    }
    if (!pieCenterSpaceRadius.isFinite ||
        pieCenterSpaceRadius < 0 ||
        pieCenterSpaceRadius > maxPieCenterSpaceRadius) {
      throw const FormatException('Rayon central du camembert invalide.');
    }
    if (!pieSectionsSpace.isFinite ||
        pieSectionsSpace < 0 ||
        pieSectionsSpace > maxPieSectionsSpace) {
      throw const FormatException('Espacement des sections invalide.');
    }
  }

  SuperChartConfig copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    SuperChartKind? kind,
    String? labelPath,
    List<SuperChartSeries>? series,
    bool? showGrid,
    bool? showLegend,
    bool? enableTooltips,
    bool? enableSelection,
    bool? showAxisLabels,
    bool? showAxisTitles,
    String? xAxisTitle,
    String? yAxisTitle,
    double? minY,
    bool clearMinY = false,
    double? maxY,
    bool clearMaxY = false,
    bool? barStacked,
    double? pieCenterSpaceRadius,
    double? pieSectionsSpace,
    bool? showDemoWhenUnbound,
    String? emptyText,
  }) => SuperChartConfig(
    binding: clearBinding ? null : binding ?? this.binding,
    kind: kind ?? this.kind,
    labelPath: labelPath ?? this.labelPath,
    series: series == null ? this.series : List.unmodifiable(series),
    showGrid: showGrid ?? this.showGrid,
    showLegend: showLegend ?? this.showLegend,
    enableTooltips: enableTooltips ?? this.enableTooltips,
    enableSelection: enableSelection ?? this.enableSelection,
    showAxisLabels: showAxisLabels ?? this.showAxisLabels,
    showAxisTitles: showAxisTitles ?? this.showAxisTitles,
    xAxisTitle: xAxisTitle ?? this.xAxisTitle,
    yAxisTitle: yAxisTitle ?? this.yAxisTitle,
    minY: clearMinY ? null : minY ?? this.minY,
    maxY: clearMaxY ? null : maxY ?? this.maxY,
    barStacked: barStacked ?? this.barStacked,
    pieCenterSpaceRadius: pieCenterSpaceRadius ?? this.pieCenterSpaceRadius,
    pieSectionsSpace: pieSectionsSpace ?? this.pieSectionsSpace,
    showDemoWhenUnbound: showDemoWhenUnbound ?? this.showDemoWhenUnbound,
    emptyText: emptyText ?? this.emptyText,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      if (binding != null) 'binding': binding!.toJson(),
      'kind': kind.name,
      'labelPath': labelPath,
      'series': [for (final s in series) s.toJson()],
      'showGrid': showGrid,
      'showLegend': showLegend,
      'enableTooltips': enableTooltips,
      'enableSelection': enableSelection,
      'showAxisLabels': showAxisLabels,
      'showAxisTitles': showAxisTitles,
      if (xAxisTitle.isNotEmpty) 'xAxisTitle': xAxisTitle,
      if (yAxisTitle.isNotEmpty) 'yAxisTitle': yAxisTitle,
      if (minY != null) 'minY': minY,
      if (maxY != null) 'maxY': maxY,
      'barStacked': barStacked,
      'pieCenterSpaceRadius': pieCenterSpaceRadius,
      'pieSectionsSpace': pieSectionsSpace,
      'showDemoWhenUnbound': showDemoWhenUnbound,
      'emptyText': emptyText,
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    const d = SuperChartConfig();
    return {
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (kind != d.kind) 'kind': kind.name,
      if (labelPath != d.labelPath) 'labelPath': labelPath,
      if (!listEquals(series, d.series))
        'series': [for (final s in series) s.toCompactJson()],
      if (showGrid != d.showGrid) 'showGrid': showGrid,
      if (showLegend != d.showLegend) 'showLegend': showLegend,
      if (enableTooltips != d.enableTooltips) 'enableTooltips': enableTooltips,
      if (enableSelection != d.enableSelection)
        'enableSelection': enableSelection,
      if (showAxisLabels != d.showAxisLabels) 'showAxisLabels': showAxisLabels,
      if (showAxisTitles != d.showAxisTitles) 'showAxisTitles': showAxisTitles,
      if (xAxisTitle != d.xAxisTitle) 'xAxisTitle': xAxisTitle,
      if (yAxisTitle != d.yAxisTitle) 'yAxisTitle': yAxisTitle,
      if (minY != null) 'minY': minY,
      if (maxY != null) 'maxY': maxY,
      if (barStacked != d.barStacked) 'barStacked': barStacked,
      if (pieCenterSpaceRadius != d.pieCenterSpaceRadius)
        'pieCenterSpaceRadius': pieCenterSpaceRadius,
      if (pieSectionsSpace != d.pieSectionsSpace)
        'pieSectionsSpace': pieSectionsSpace,
      if (showDemoWhenUnbound != d.showDemoWhenUnbound)
        'showDemoWhenUnbound': showDemoWhenUnbound,
      if (emptyText != d.emptyText) 'emptyText': emptyText,
    };
  }

  @override
  SuperChartConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperChartConfig.fromJson(patch, fallback: this);

  static const _keys = {
    'binding',
    'kind',
    'labelPath',
    'series',
    'showGrid',
    'showLegend',
    'enableTooltips',
    'enableSelection',
    'showAxisLabels',
    'showAxisTitles',
    'xAxisTitle',
    'yAxisTitle',
    'minY',
    'maxY',
    'barStacked',
    'pieCenterSpaceRadius',
    'pieSectionsSpace',
    'showDemoWhenUnbound',
    'emptyText',
  };

  factory SuperChartConfig.fromJson(
    Object? value, {
    SuperChartConfig fallback = const SuperChartConfig(),
  }) {
    if (value is! Map || value.keys.any((key) => !_keys.contains(key))) {
      throw const FormatException('Configuration de graphique invalide.');
    }
    T read<T>(String key, T fallbackVal) {
      final raw = value[key];
      if (raw == null) return fallbackVal;
      if (raw is! T) {
        throw const FormatException('Configuration de graphique invalide.');
      }
      return raw;
    }

    double readNum(String key, double fallbackVal) {
      final raw = value[key];
      if (raw == null) return fallbackVal;
      if (raw is! num) {
        throw const FormatException('Configuration de graphique invalide.');
      }
      return raw.toDouble();
    }

    double? readNullableNum(String key, double? fallbackVal) {
      if (!value.containsKey(key)) return fallbackVal;
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! num) {
        throw const FormatException('Configuration de graphique invalide.');
      }
      return raw.toDouble();
    }

    final rawKind = value['kind'];
    final SuperChartKind kind;
    if (rawKind == null) {
      kind = fallback.kind;
    } else if (rawKind is String) {
      final match = SuperChartKind.values
          .where((candidate) => candidate.name == rawKind)
          .firstOrNull;
      if (match == null) {
        throw const FormatException('Type de graphique inconnu.');
      }
      kind = match;
    } else {
      throw const FormatException('Configuration de graphique invalide.');
    }

    final JsonTextBinding? binding;
    if (!value.containsKey('binding')) {
      binding = fallback.binding;
    } else if (value['binding'] == null) {
      binding = null;
    } else {
      binding = JsonTextBinding.fromJson(value['binding']);
    }

    final List<SuperChartSeries> parsedSeries;
    if (!value.containsKey('series')) {
      parsedSeries = fallback.series;
    } else {
      final rawSeries = value['series'];
      if (rawSeries is! List || rawSeries.isEmpty) {
        throw const FormatException('Configuration de séries invalide.');
      }
      parsedSeries = List.unmodifiable([
        for (var i = 0; i < rawSeries.length; i++)
          SuperChartSeries.fromJson(
            rawSeries[i],
            fallback: SuperChartSeries(
              id: 'series-${i + 1}',
              label: 'Série ${i + 1}',
            ),
          ),
      ]);
    }

    final result = SuperChartConfig(
      binding: binding,
      kind: kind,
      labelPath: read<String>('labelPath', fallback.labelPath),
      series: parsedSeries,
      showGrid: read<bool>('showGrid', fallback.showGrid),
      showLegend: read<bool>('showLegend', fallback.showLegend),
      enableTooltips: read<bool>('enableTooltips', fallback.enableTooltips),
      enableSelection: read<bool>('enableSelection', fallback.enableSelection),
      showAxisLabels: read<bool>('showAxisLabels', fallback.showAxisLabels),
      showAxisTitles: read<bool>('showAxisTitles', fallback.showAxisTitles),
      xAxisTitle: read<String>('xAxisTitle', fallback.xAxisTitle),
      yAxisTitle: read<String>('yAxisTitle', fallback.yAxisTitle),
      minY: readNullableNum('minY', fallback.minY),
      maxY: readNullableNum('maxY', fallback.maxY),
      barStacked: read<bool>('barStacked', fallback.barStacked),
      pieCenterSpaceRadius: readNum(
        'pieCenterSpaceRadius',
        fallback.pieCenterSpaceRadius,
      ),
      pieSectionsSpace: readNum('pieSectionsSpace', fallback.pieSectionsSpace),
      showDemoWhenUnbound: read<bool>(
        'showDemoWhenUnbound',
        fallback.showDemoWhenUnbound,
      ),
      emptyText: read<String>('emptyText', fallback.emptyText),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperChartConfig &&
      other.binding == binding &&
      other.kind == kind &&
      other.labelPath == labelPath &&
      listEquals(other.series, series) &&
      other.showGrid == showGrid &&
      other.showLegend == showLegend &&
      other.enableTooltips == enableTooltips &&
      other.enableSelection == enableSelection &&
      other.showAxisLabels == showAxisLabels &&
      other.showAxisTitles == showAxisTitles &&
      other.xAxisTitle == xAxisTitle &&
      other.yAxisTitle == yAxisTitle &&
      other.minY == minY &&
      other.maxY == maxY &&
      other.barStacked == barStacked &&
      other.pieCenterSpaceRadius == pieCenterSpaceRadius &&
      other.pieSectionsSpace == pieSectionsSpace &&
      other.showDemoWhenUnbound == showDemoWhenUnbound &&
      other.emptyText == emptyText;

  @override
  int get hashCode => Object.hash(
    binding,
    kind,
    labelPath,
    Object.hashAll(series),
    showGrid,
    showLegend,
    enableTooltips,
    enableSelection,
    showAxisLabels,
    showAxisTitles,
    xAxisTitle,
    yAxisTitle,
    minY,
    maxY,
    barStacked,
    pieCenterSpaceRadius,
    pieSectionsSpace,
    showDemoWhenUnbound,
    emptyText,
  );
}
