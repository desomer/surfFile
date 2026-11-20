/// Configuration persistée d'une page document au format A4 ([A4PageConfig]).
///
/// Modélise une page de type [EditorPageType.a4Document] composée d'une liste
/// ordonnée de feuilles A4 explicites ([A4SheetConfig]), avec orientation,
/// marges en points PDF, en-tête/pied de page optionnels et guides d'édition.
library;

import 'dart:ui' show Color, Size;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/painting.dart' show EdgeInsets;

import 'component_config.dart';
import 'json_numbers.dart';
import 'json_syntax.dart';

/// Orientation d'une page A4 (`portrait` 210x297 mm ou `landscape` 297x210 mm).
enum A4Orientation {
  /// Format portrait (595.28 x 841.89 pt).
  portrait('Portrait'),

  /// Format paysage (841.89 x 595.28 pt).
  landscape('Paysage');

  const A4Orientation(this.label);

  /// Libellé affiché dans l'éditeur.
  final String label;

  /// Dimensions exactes de la feuille en points PDF (72 DPI).
  Size get pageSize => switch (this) {
    A4Orientation.portrait => const Size(
      A4PageConfig.a4WidthPt,
      A4PageConfig.a4HeightPt,
    ),
    A4Orientation.landscape => const Size(
      A4PageConfig.a4HeightPt,
      A4PageConfig.a4WidthPt,
    ),
  };

  /// Décode une orientation depuis son nom JSON.
  static A4Orientation fromJson(Object? value) => switch (value) {
    null || 'portrait' => A4Orientation.portrait,
    'landscape' => A4Orientation.landscape,
    _ => throw FormatException('Orientation A4 invalide : $value.'),
  };
}

/// Définition d'une feuille individuelle au sein d'un document A4 multi-feuilles.
@immutable
class A4SheetConfig {
  /// Crée une feuille A4 associée à un slot racine [rootSlotId].
  A4SheetConfig({
    required this.id,
    required this.label,
    required this.rootSlotId,
    this.rootSlotType = 'registry:Layout',
    this.backgroundColor,
  }) {
    validate();
  }

  /// Identifiant stable de la feuille.
  final String id;

  /// Titre lisible de la feuille (ex. `Feuille 1`).
  final String label;

  /// Identifiant du slot racine contenu dans cette feuille.
  final String rootSlotId;

  /// Type de composant du slot racine (par défaut `registry:Layout`).
  final String rootSlotType;

  /// Couleur de fond optionnelle de la feuille (par défaut blanc papier).
  final Color? backgroundColor;

  /// Vérifie la validité des identifiants de la feuille.
  void validate() {
    if (id.trim().isEmpty) {
      throw ArgumentError('A4SheetConfig.id ne doit pas être vide.');
    }
    if (label.trim().isEmpty) {
      throw ArgumentError('A4SheetConfig.label ne doit pas être vide.');
    }
    if (rootSlotId.trim().isEmpty) {
      throw ArgumentError('A4SheetConfig.rootSlotId ne doit pas être vide.');
    }
    if (rootSlotType.trim().isEmpty) {
      throw ArgumentError('A4SheetConfig.rootSlotType ne doit pas être vide.');
    }
  }

  /// Retourne une copie modifiée de cette feuille.
  A4SheetConfig copyWith({
    String? id,
    String? label,
    String? rootSlotId,
    String? rootSlotType,
    Color? backgroundColor,
    bool clearBackgroundColor = false,
  }) => A4SheetConfig(
    id: id ?? this.id,
    label: label ?? this.label,
    rootSlotId: rootSlotId ?? this.rootSlotId,
    rootSlotType: rootSlotType ?? this.rootSlotType,
    backgroundColor: clearBackgroundColor
        ? null
        : backgroundColor ?? this.backgroundColor,
  );

  /// Sérialise la feuille en JSON complet.
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'rootSlotId': rootSlotId,
    'rootSlotType': rootSlotType,
    if (backgroundColor != null)
      'backgroundColor': JsonColor.toHex(backgroundColor!),
  };

  /// Sérialisation compacte omettant les valeurs par défaut.
  Map<String, Object?> toCompactJson() => {
    'id': id,
    'label': label,
    'rootSlotId': rootSlotId,
    if (rootSlotType != 'registry:Layout') 'rootSlotType': rootSlotType,
    if (backgroundColor != null)
      'backgroundColor': JsonColor.toHex(backgroundColor!),
  };

  /// Décode une [A4SheetConfig] depuis JSON.
  factory A4SheetConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Configuration de feuille A4 invalide.');
    }
    final allowedKeys = {
      'id',
      'label',
      'rootSlotId',
      'rootSlotType',
      'backgroundColor',
    };
    final unknownKeys = value.keys
        .where((k) => k is! String || !allowedKeys.contains(k))
        .toList();
    if (unknownKeys.isNotEmpty) {
      throw FormatException(
        'Clé inconnue dans A4SheetConfig : ${unknownKeys.join(', ')}. '
        'Clés autorisées : id, label, rootSlotId, rootSlotType, backgroundColor.',
      );
    }
    final rawId = value['id'];
    final rawLabel = value['label'];
    final rootSlotId = value['rootSlotId'];
    final rootSlotType = value['rootSlotType'];
    if (rootSlotId is! String ||
        rootSlotId.trim().isEmpty ||
        (rawId != null && rawId is! String) ||
        (rawLabel != null && rawLabel is! String) ||
        (rootSlotType != null && rootSlotType is! String)) {
      throw const FormatException(
        'Champs requis manquants dans A4SheetConfig (rootSlotId requis).',
      );
    }
    final id = (rawId as String?)?.trim().isNotEmpty == true
        ? (rawId as String).trim()
        : 'sheet-1';
    final label = (rawLabel as String?)?.trim().isNotEmpty == true
        ? (rawLabel as String).trim()
        : 'Feuille 1';
    try {
      return A4SheetConfig(
        id: id,
        label: label,
        rootSlotId: rootSlotId,
        rootSlotType: rootSlotType == null
            ? 'registry:Layout'
            : JsonComponentType.normalize(rootSlotType as String),
        backgroundColor: JsonColor.parseNullable(
          value['backgroundColor'],
          'backgroundColor',
        ),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Feuille A4 invalide : $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is A4SheetConfig &&
          other.id == id &&
          other.label == label &&
          other.rootSlotId == rootSlotId &&
          other.rootSlotType == rootSlotType &&
          other.backgroundColor == backgroundColor;

  @override
  int get hashCode =>
      Object.hash(id, label, rootSlotId, rootSlotType, backgroundColor);
}

/// Configuration persistée d'une page document A4 multi-feuilles.
@immutable
class A4PageConfig extends ComponentConfig {
  /// Largeur A4 standard en points PDF (210 mm à 72 DPI).
  static const double a4WidthPt = 595.28;

  /// Hauteur A4 standard en points PDF (297 mm à 72 DPI).
  static const double a4HeightPt = 841.89;

  /// Marge par défaut en points PDF (~12.7 mm).
  static const double defaultMarginPt = 36.0;

  /// Hauteur par défaut de l'en-tête répété en points PDF.
  static const double defaultHeaderHeightPt = 48.0;

  /// Hauteur par défaut du pied de page répété en points PDF.
  static const double defaultFooterHeightPt = 36.0;

  /// Crée une configuration de page A4.
  A4PageConfig({
    this.orientation = A4Orientation.portrait,
    this.marginTop = defaultMarginPt,
    this.marginRight = defaultMarginPt,
    this.marginBottom = defaultMarginPt,
    this.marginLeft = defaultMarginPt,
    List<A4SheetConfig>? sheets,
    this.headerSlotId,
    this.headerSlotType = 'registry:Layout',
    this.headerHeight = defaultHeaderHeightPt,
    this.footerSlotId,
    this.footerSlotType = 'registry:Layout',
    this.footerHeight = defaultFooterHeightPt,
    this.showPageNumbers = false,
    this.showPageGuides = true,
    this.defaultFileName = 'document.pdf',
  }) : sheets = List<A4SheetConfig>.unmodifiable(
         sheets ??
             [
               A4SheetConfig(
                 id: 'sheet-1',
                 label: 'Feuille 1',
                 rootSlotId: 'a4-sheet-1',
               ),
             ],
       ) {
    validate();
  }

  /// Construit une configuration A4 initiale propre pour une page [pageId].
  factory A4PageConfig.initialForPage(String pageId) => A4PageConfig(
    sheets: [
      A4SheetConfig(
        id: 'sheet-1',
        label: 'Feuille 1',
        rootSlotId: '$pageId-sheet-1',
      ),
    ],
  );

  /// Orientation des feuilles (`portrait` ou `landscape`).
  final A4Orientation orientation;

  /// Marge supérieure en points PDF.
  final double marginTop;

  /// Marge droite en points PDF.
  final double marginRight;

  /// Marge inférieure en points PDF.
  final double marginBottom;

  /// Marge gauche en points PDF.
  final double marginLeft;

  /// Liste ordonnée des feuilles explicites du document.
  final List<A4SheetConfig> sheets;

  /// Identifiant optionnel du slot d'en-tête répété sur chaque feuille.
  final String? headerSlotId;

  /// Type du slot d'en-tête.
  final String headerSlotType;

  /// Hauteur allouée à l'en-tête en points PDF.
  final double headerHeight;

  /// Identifiant optionnel du slot de pied de page répété sur chaque feuille.
  final String? footerSlotId;

  /// Type du slot de pied de page.
  final String footerSlotType;

  /// Hauteur allouée au pied de page en points PDF.
  final double footerHeight;

  /// Affiche automatiquement `Page X / Y` en pied de page lors de l'aperçu et du PDF.
  final bool showPageNumbers;

  /// Affiche les repères de marges et cadres en mode édition.
  final bool showPageGuides;

  /// Nom de fichier suggéré lors de l'export PDF.
  final String defaultFileName;

  /// Marges converties en [EdgeInsets].
  EdgeInsets get margins =>
      EdgeInsets.fromLTRB(marginLeft, marginTop, marginRight, marginBottom);

  /// Dimensions totales de chaque feuille selon [orientation].
  Size get pageSize => orientation.pageSize;

  @override
  String get componentType => 'a4Document';

  @override
  Map<String, String> get childSlots => Map.unmodifiable({
    for (final sheet in sheets) sheet.rootSlotId: sheet.rootSlotType,
    if (headerSlotId != null && headerSlotId!.trim().isNotEmpty)
      headerSlotId!: headerSlotType,
    if (footerSlotId != null && footerSlotId!.trim().isNotEmpty)
      footerSlotId!: footerSlotType,
  });

  @override
  A4PageConfig copyWithRemappedSlots(String Function(String id) remap) =>
      copyWith(
        sheets: [
          for (final sheet in sheets)
            sheet.copyWith(rootSlotId: remap(sheet.rootSlotId)),
        ],
        headerSlotId: headerSlotId == null ? null : remap(headerSlotId!),
        footerSlotId: footerSlotId == null ? null : remap(footerSlotId!),
      );

  @override
  void validate() {
    for (final entry in {
      'marginTop': marginTop,
      'marginRight': marginRight,
      'marginBottom': marginBottom,
      'marginLeft': marginLeft,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0 || entry.value > 250) {
        throw RangeError(
          '${entry.key} doit être compris entre 0 et 250 pt (${entry.value}).',
        );
      }
    }
    if (!headerHeight.isFinite || headerHeight < 16 || headerHeight > 240) {
      throw RangeError('headerHeight doit être compris entre 16 et 240 pt.');
    }
    if (!footerHeight.isFinite || footerHeight < 16 || footerHeight > 240) {
      throw RangeError('footerHeight doit être compris entre 16 et 240 pt.');
    }
    final size = orientation.pageSize;
    if (marginLeft + marginRight >= size.width - 40 ||
        marginTop + marginBottom >= size.height - 40) {
      throw ArgumentError(
        'Les marges A4 laissent une zone imprimable trop réduite.',
      );
    }
    if (sheets.isEmpty) {
      throw ArgumentError('Une page A4 doit contenir au moins une feuille.');
    }
    final sheetIds = <String>{};
    final slotIds = <String>{};
    for (final sheet in sheets) {
      sheet.validate();
      if (!sheetIds.add(sheet.id)) {
        throw ArgumentError('Identifiant de feuille A4 dupliqué : ${sheet.id}.');
      }
      if (!slotIds.add(sheet.rootSlotId)) {
        throw ArgumentError(
          'Slot racine de feuille A4 dupliqué : ${sheet.rootSlotId}.',
        );
      }
    }
    if (headerSlotId != null) {
      if (headerSlotId!.trim().isEmpty) {
        throw ArgumentError('headerSlotId ne doit pas être vide.');
      }
      if (!slotIds.add(headerSlotId!)) {
        throw ArgumentError('headerSlotId en conflit avec un autre slot.');
      }
    }
    if (footerSlotId != null) {
      if (footerSlotId!.trim().isEmpty) {
        throw ArgumentError('footerSlotId ne doit pas être vide.');
      }
      if (!slotIds.add(footerSlotId!)) {
        throw ArgumentError('footerSlotId en conflit avec un autre slot.');
      }
    }
    if (defaultFileName.trim().isEmpty) {
      throw ArgumentError('defaultFileName ne doit pas être vide.');
    }
  }

  /// Retourne une copie modifiée de cette configuration A4.
  A4PageConfig copyWith({
    A4Orientation? orientation,
    double? marginTop,
    double? marginRight,
    double? marginBottom,
    double? marginLeft,
    List<A4SheetConfig>? sheets,
    String? headerSlotId,
    bool clearHeaderSlot = false,
    String? headerSlotType,
    double? headerHeight,
    String? footerSlotId,
    bool clearFooterSlot = false,
    String? footerSlotType,
    double? footerHeight,
    bool? showPageNumbers,
    bool? showPageGuides,
    String? defaultFileName,
  }) => A4PageConfig(
    orientation: orientation ?? this.orientation,
    marginTop: marginTop ?? this.marginTop,
    marginRight: marginRight ?? this.marginRight,
    marginBottom: marginBottom ?? this.marginBottom,
    marginLeft: marginLeft ?? this.marginLeft,
    sheets: sheets ?? this.sheets,
    headerSlotId: clearHeaderSlot ? null : headerSlotId ?? this.headerSlotId,
    headerSlotType: headerSlotType ?? this.headerSlotType,
    headerHeight: headerHeight ?? this.headerHeight,
    footerSlotId: clearFooterSlot ? null : footerSlotId ?? this.footerSlotId,
    footerSlotType: footerSlotType ?? this.footerSlotType,
    footerHeight: footerHeight ?? this.footerHeight,
    showPageNumbers: showPageNumbers ?? this.showPageNumbers,
    showPageGuides: showPageGuides ?? this.showPageGuides,
    defaultFileName: defaultFileName ?? this.defaultFileName,
  );

  @override
  A4PageConfig patchFromJson(Map<Object?, Object?> patch) =>
      A4PageConfig.fromJson({...toJson(), ...patch});

  @override
  Map<String, Object?> toJson() => {
    'orientation': orientation.name,
    'marginTop': JsonNumbers.round(marginTop),
    'marginRight': JsonNumbers.round(marginRight),
    'marginBottom': JsonNumbers.round(marginBottom),
    'marginLeft': JsonNumbers.round(marginLeft),
    'sheets': [for (final sheet in sheets) sheet.toJson()],
    if (headerSlotId != null) 'headerSlotId': headerSlotId,
    if (headerSlotId != null) 'headerSlotType': headerSlotType,
    'headerHeight': JsonNumbers.round(headerHeight),
    if (footerSlotId != null) 'footerSlotId': footerSlotId,
    if (footerSlotId != null) 'footerSlotType': footerSlotType,
    'footerHeight': JsonNumbers.round(footerHeight),
    'showPageNumbers': showPageNumbers,
    'showPageGuides': showPageGuides,
    'defaultFileName': defaultFileName,
  };

  @override
  Map<String, Object?> toCompactJson() => {
    if (orientation != A4Orientation.portrait) 'orientation': orientation.name,
    if (marginTop != defaultMarginPt) 'marginTop': JsonNumbers.round(marginTop),
    if (marginRight != defaultMarginPt)
      'marginRight': JsonNumbers.round(marginRight),
    if (marginBottom != defaultMarginPt)
      'marginBottom': JsonNumbers.round(marginBottom),
    if (marginLeft != defaultMarginPt)
      'marginLeft': JsonNumbers.round(marginLeft),
    'sheets': [for (final sheet in sheets) sheet.toCompactJson()],
    if (headerSlotId != null) 'headerSlotId': headerSlotId,
    if (headerSlotId != null && headerSlotType != 'registry:Layout')
      'headerSlotType': headerSlotType,
    if (headerHeight != defaultHeaderHeightPt)
      'headerHeight': JsonNumbers.round(headerHeight),
    if (footerSlotId != null) 'footerSlotId': footerSlotId,
    if (footerSlotId != null && footerSlotType != 'registry:Layout')
      'footerSlotType': footerSlotType,
    if (footerHeight != defaultFooterHeightPt)
      'footerHeight': JsonNumbers.round(footerHeight),
    if (showPageNumbers) 'showPageNumbers': true,
    if (!showPageGuides) 'showPageGuides': false,
    if (defaultFileName != 'document.pdf') 'defaultFileName': defaultFileName,
  };

  /// Décode une [A4PageConfig] depuis JSON.
  factory A4PageConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Configuration de page A4 invalide.');
    }
    const allowedKeys = {
      'orientation',
      'marginTop',
      'marginRight',
      'marginBottom',
      'marginLeft',
      'margins',
      'sheets',
      'headerSlotId',
      'headerSlotType',
      'headerHeight',
      'footerSlotId',
      'footerSlotType',
      'footerHeight',
      'showPageNumbers',
      'showPageGuides',
      'defaultFileName',
    };
    final unknownKeys = value.keys
        .where((k) => k is! String || !allowedKeys.contains(k))
        .toList();
    if (unknownKeys.isNotEmpty) {
      if (unknownKeys.any(
        (k) => const {'placements', 'regions', 'body', 'content', 'slotLabels'}
            .contains(k),
      )) {
        throw FormatException(
          'Un composant "a4Document" n’utilise pas "${unknownKeys.join('", "')}" '
          '(réservés à "scaffold"/"native"). Utilise "sheets": '
          '[{"id": "sheet-1", "label": "Feuille 1", "rootSlotId": "<layoutId>", '
          '"rootSlotType": "registry:Layout"}] et place le contenu de la feuille '
          'dans components["<layoutId>"] ("type": "layout").',
        );
      }
      throw FormatException(
        'Clé inconnue dans A4PageConfig : ${unknownKeys.join(', ')}. '
        'Clés autorisées : orientation, marginTop, marginRight, marginBottom, '
        'marginLeft, margins, sheets, headerSlotId, headerSlotType, headerHeight, '
        'footerSlotId, footerSlotType, footerHeight, showPageNumbers, '
        'showPageGuides, defaultFileName.',
      );
    }

    double? uniformMargin;
    if (value.containsKey('margins')) {
      final raw = value['margins'];
      if (raw is! num) {
        throw const FormatException('margins doit être un nombre.');
      }
      uniformMargin = raw.toDouble();
    }

    double parseDim(String key, double fallback) {
      if (!value.containsKey(key)) return uniformMargin ?? fallback;
      final raw = value[key];
      if (raw is! num) {
        throw FormatException('$key doit être un nombre.');
      }
      return raw.toDouble();
    }

    bool parseBool(String key, bool fallback) {
      if (!value.containsKey(key)) return fallback;
      final raw = value[key];
      if (raw is! bool) {
        throw FormatException('$key doit être un booléen.');
      }
      return raw;
    }

    final rawSheets = value['sheets'];
    final List<A4SheetConfig>? sheets;
    if (rawSheets == null) {
      sheets = null;
    } else if (rawSheets is List) {
      sheets = [for (final entry in rawSheets) A4SheetConfig.fromJson(entry)];
    } else {
      throw const FormatException('sheets doit être une liste.');
    }

    final headerSlotId = value['headerSlotId'];
    final headerSlotType = value['headerSlotType'];
    final footerSlotId = value['footerSlotId'];
    final footerSlotType = value['footerSlotType'];
    final defaultFileName = value['defaultFileName'];
    if ((headerSlotId != null && headerSlotId is! String) ||
        (headerSlotType != null && headerSlotType is! String) ||
        (footerSlotId != null && footerSlotId is! String) ||
        (footerSlotType != null && footerSlotType is! String) ||
        (defaultFileName != null && defaultFileName is! String)) {
      throw const FormatException('Champs invalides dans A4PageConfig.');
    }

    try {
      return A4PageConfig(
        orientation: A4Orientation.fromJson(value['orientation']),
        marginTop: parseDim('marginTop', defaultMarginPt),
        marginRight: parseDim('marginRight', defaultMarginPt),
        marginBottom: parseDim('marginBottom', defaultMarginPt),
        marginLeft: parseDim('marginLeft', defaultMarginPt),
        sheets: sheets,
        headerSlotId: headerSlotId as String?,
        headerSlotType: headerSlotType == null
            ? 'registry:Layout'
            : JsonComponentType.normalize(headerSlotType as String),
        headerHeight: parseDim('headerHeight', defaultHeaderHeightPt),
        footerSlotId: footerSlotId as String?,
        footerSlotType: footerSlotType == null
            ? 'registry:Layout'
            : JsonComponentType.normalize(footerSlotType as String),
        footerHeight: parseDim('footerHeight', defaultFooterHeightPt),
        showPageNumbers: parseBool('showPageNumbers', false),
        showPageGuides: parseBool('showPageGuides', true),
        defaultFileName: (defaultFileName as String?) ?? 'document.pdf',
      );
    } on ArgumentError catch (error) {
      throw FormatException('Configuration de page A4 invalide : $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is A4PageConfig &&
          other.orientation == orientation &&
          other.marginTop == marginTop &&
          other.marginRight == marginRight &&
          other.marginBottom == marginBottom &&
          other.marginLeft == marginLeft &&
          listEquals(other.sheets, sheets) &&
          other.headerSlotId == headerSlotId &&
          other.headerSlotType == headerSlotType &&
          other.headerHeight == headerHeight &&
          other.footerSlotId == footerSlotId &&
          other.footerSlotType == footerSlotType &&
          other.footerHeight == footerHeight &&
          other.showPageNumbers == showPageNumbers &&
          other.showPageGuides == showPageGuides &&
          other.defaultFileName == defaultFileName;

  @override
  int get hashCode => Object.hash(
    orientation,
    marginTop,
    marginRight,
    marginBottom,
    marginLeft,
    Object.hashAll(sheets),
    headerSlotId,
    headerSlotType,
    headerHeight,
    footerSlotId,
    footerSlotType,
    footerHeight,
    showPageNumbers,
    showPageGuides,
    defaultFileName,
  );
}
