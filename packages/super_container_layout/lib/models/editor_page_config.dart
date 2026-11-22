/// Modèles de page routée ([EditorPageConfig]) et de catalogue de pages ([EditorPageCatalog]).
///
/// Persiste la liste des écrans de l'application, leurs chemins de route,
/// leurs identifiants de `Scaffold` / `SuperLayout` racines et la page d'accueil.
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show IconData, Icons;

import 'json_numbers.dart';
import 'responsive_layout_config.dart';

/// Type d'une page déclarée dans [EditorPageCatalog].
enum EditorPageType {
  /// Page applicative classique rendue dans un `Scaffold` ([SuperPage]).
  standard(
    'Écran',
    'Page applicative plein écran avec Scaffold',
    Icons.web_asset_outlined,
  ),

  /// Page document au format A4 multi-feuilles destinée à l'aperçu et à l'export PDF.
  a4Document(
    'PDF A4',
    'Document multi-feuilles A4 exportable en PDF',
    Icons.description_outlined,
  ),

  /// Fenêtre modale centrée affichée par-dessus la page courante.
  dialog(
    'Dialogue',
    'Fenêtre modale centrée au-dessus de l’écran',
    Icons.picture_in_picture_alt_outlined,
  ),

  /// Panneau modal glissant depuis le bas de l'écran.
  bottomSheet(
    'Panneau bas',
    'Feuille modale glissant depuis le bas (BottomSheet)',
    Icons.vertical_align_bottom_outlined,
  ),

  /// Panneau modal latéral glissant depuis le bord droit.
  sideSheet(
    'Panneau latéral',
    'Volet modal glissant depuis le bord droit',
    Icons.view_sidebar_outlined,
  );

  const EditorPageType(this.label, this.description, this.icon);

  /// Libellé court affiché dans l'interface d'édition.
  final String label;

  /// Description concise du rendu associé.
  final String description;

  /// Icône représentative dans le sélecteur de type de page.
  final IconData icon;

  /// Indique si ce type de page utilise une structure `Scaffold` ([SuperPage]).
  bool get usesScaffold => this != EditorPageType.a4Document;

  /// Indique si ce type de page est présenté sous forme de superposition modale.
  bool get isModal => switch (this) {
    EditorPageType.dialog ||
    EditorPageType.bottomSheet ||
    EditorPageType.sideSheet => true,
    EditorPageType.standard || EditorPageType.a4Document => false,
  };

  /// Décode un [EditorPageType] depuis son nom JSON.
  static EditorPageType fromJson(Object? value) => switch (value) {
    null || 'standard' || 'screen' || 'ecran' => EditorPageType.standard,
    'a4Document' || 'a4' || 'documentA4' || 'pdf' => EditorPageType.a4Document,
    'dialog' || 'modal' => EditorPageType.dialog,
    'bottomSheet' || 'sheet' => EditorPageType.bottomSheet,
    'sideSheet' || 'drawer' => EditorPageType.sideSheet,
    _ => throw FormatException('Type de page éditeur invalide : $value.'),
  };
}

/// A visually authored page with an identity independent of its route.
@immutable
class EditorPageConfig {
  EditorPageConfig({
    required this.id,
    required this.name,
    required this.path,
    this.pageType = EditorPageType.standard,
    this.modalWidth,
    this.modalHeight,
    this.showCloseButton = true,
    this.layoutOverride,
    Map<String, String> defaultParameters = const {},
  }) : defaultParameters = Map.unmodifiable(defaultParameters) {
    validate();
  }

  final String id;
  final String name;
  final String path;

  /// Nature de la page (`standard`, `a4Document`, `dialog`, `bottomSheet`, `sideSheet`).
  final EditorPageType pageType;

  /// Largeur optionnelle (px) pour les pages modales (`dialog`, `sideSheet`).
  final double? modalWidth;

  /// Hauteur optionnelle (px) pour les pages modales (`dialog`, `bottomSheet`).
  final double? modalHeight;

  /// Indique si le bouton « Fermer » (`×`) est affiché par défaut en haut à droite
  /// des pages modales (`dialog`, `bottomSheet`, `sideSheet`). Vaut `true` par défaut.
  final bool showCloseButton;

  /// Surcharge responsive optionnelle de cette page (mode conteneur, max-width, gutters).
  final ResponsiveLayoutOverride? layoutOverride;
  final Map<String, String> defaultParameters;

  /// Route syntax and parameter constraints are validated by the router.
  void validate() {
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        path.trim().isEmpty ||
        !path.startsWith('/')) {
      throw ArgumentError(
        'Invalid editor page identity, name or absolute path.',
      );
    }
    if (defaultParameters.keys.any((key) => key.trim().isEmpty)) {
      throw ArgumentError('Editor page parameter names must not be empty.');
    }
    if (modalWidth != null &&
        (!modalWidth!.isFinite || modalWidth! < 120 || modalWidth! > 4000)) {
      throw ArgumentError('Editor page modalWidth must be between 120 and 4000.');
    }
    if (modalHeight != null &&
        (!modalHeight!.isFinite || modalHeight! < 120 || modalHeight! > 4000)) {
      throw ArgumentError(
        'Editor page modalHeight must be between 120 and 4000.',
      );
    }
    layoutOverride?.validate();
  }

  EditorPageConfig copyWith({
    String? id,
    String? name,
    String? path,
    EditorPageType? pageType,
    double? modalWidth,
    bool clearModalWidth = false,
    double? modalHeight,
    bool clearModalHeight = false,
    bool? showCloseButton,
    ResponsiveLayoutOverride? layoutOverride,
    bool clearLayoutOverride = false,
    Map<String, String>? defaultParameters,
  }) => EditorPageConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    path: path ?? this.path,
    pageType: pageType ?? this.pageType,
    modalWidth: clearModalWidth ? null : modalWidth ?? this.modalWidth,
    modalHeight: clearModalHeight ? null : modalHeight ?? this.modalHeight,
    showCloseButton: showCloseButton ?? this.showCloseButton,
    layoutOverride: clearLayoutOverride
        ? null
        : (layoutOverride ?? this.layoutOverride),
    defaultParameters: defaultParameters ?? this.defaultParameters,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    if (pageType != EditorPageType.standard) 'pageType': pageType.name,
    if (modalWidth != null) 'modalWidth': JsonNumbers.round(modalWidth!),
    if (modalHeight != null) 'modalHeight': JsonNumbers.round(modalHeight!),
    if (!showCloseButton) 'showCloseButton': false,
    if (layoutOverride != null && !layoutOverride!.isEmpty)
      'layoutOverride': layoutOverride!.toJson(),
    'defaultParameters': defaultParameters,
  };

  /// Sérialise la page au format compact en omettant les valeurs par défaut.
  Map<String, Object?> toCompactJson() => {
    'id': id,
    'name': name,
    'path': path,
    if (pageType != EditorPageType.standard) 'pageType': pageType.name,
    if (modalWidth != null) 'modalWidth': JsonNumbers.round(modalWidth!),
    if (modalHeight != null) 'modalHeight': JsonNumbers.round(modalHeight!),
    if (!showCloseButton) 'showCloseButton': false,
    if (layoutOverride != null && !layoutOverride!.isEmpty)
      'layoutOverride': layoutOverride!.toJson(),
    if (defaultParameters.isNotEmpty) 'defaultParameters': defaultParameters,
  };

  factory EditorPageConfig.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.any(
          (key) => !const {
            'id',
            'name',
            'path',
            'pageType',
            'modalWidth',
            'modalHeight',
            'showCloseButton',
            'layoutOverride',
            'defaultParameters',
          }.contains(key),
        ) ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['path'] is! String) {
      throw const FormatException('Invalid editor page configuration.');
    }
    final pageType = value.containsKey('pageType')
        ? (value['pageType'] is String
              ? EditorPageType.fromJson(value['pageType'])
              : throw const FormatException('Invalid editor page type.'))
        : EditorPageType.standard;
    final rawModalWidth = value['modalWidth'];
    final rawModalHeight = value['modalHeight'];
    if ((value.containsKey('modalWidth') && rawModalWidth is! num?) ||
        (value.containsKey('modalHeight') && rawModalHeight is! num?)) {
      throw const FormatException('Invalid editor page modal dimensions.');
    }
    final rawShowCloseButton = value['showCloseButton'];
    if (value.containsKey('showCloseButton') && rawShowCloseButton is! bool) {
      throw const FormatException('Invalid editor page showCloseButton.');
    }
    final layoutOverride = value.containsKey('layoutOverride')
        ? ResponsiveLayoutOverride.fromJson(value['layoutOverride'])
        : null;
    final parameters = value.containsKey('defaultParameters')
        ? value['defaultParameters']
        : const <String, String>{};
    if (parameters is! Map ||
        parameters.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        )) {
      throw const FormatException('Invalid editor page default parameters.');
    }
    try {
      return EditorPageConfig(
        id: value['id'] as String,
        name: value['name'] as String,
        path: value['path'] as String,
        pageType: pageType,
        modalWidth: (rawModalWidth as num?)?.toDouble(),
        modalHeight: (rawModalHeight as num?)?.toDouble(),
        showCloseButton: rawShowCloseButton as bool? ?? true,
        layoutOverride: layoutOverride,
        defaultParameters: Map<String, String>.from(parameters),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid editor page configuration: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorPageConfig &&
          other.id == id &&
          other.name == name &&
          other.path == path &&
          other.pageType == pageType &&
          other.modalWidth == modalWidth &&
          other.modalHeight == modalHeight &&
          other.showCloseButton == showCloseButton &&
          other.layoutOverride == layoutOverride &&
          mapEquals(other.defaultParameters, defaultParameters);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    path,
    pageType,
    modalWidth,
    modalHeight,
    showCloseButton,
    layoutOverride,
    Object.hashAllUnordered(
      defaultParameters.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Ordered editor pages and their optional startup destination.
@immutable
class EditorPageCatalog {
  EditorPageCatalog({List<EditorPageConfig> pages = const [], this.homePageId})
    : pages = List.unmodifiable(pages) {
    validate();
  }

  const EditorPageCatalog.empty() : pages = const [], homePageId = null;

  final List<EditorPageConfig> pages;
  final String? homePageId;

  void validate() {
    final ids = <String>{};
    for (final page in pages) {
      page.validate();
      if (!ids.add(page.id)) {
        throw ArgumentError('Duplicate editor page ID "${page.id}".');
      }
    }
    if (homePageId != null && !ids.contains(homePageId)) {
      throw ArgumentError('The editor home page must exist in the catalog.');
    }
  }

  EditorPageCatalog copyWith({
    List<EditorPageConfig>? pages,
    String? homePageId,
    bool clearHomePage = false,
  }) => EditorPageCatalog(
    pages: pages ?? this.pages,
    homePageId: clearHomePage ? null : homePageId ?? this.homePageId,
  );

  Map<String, Object?> toJson() => {
    'pages': [for (final page in pages) page.toJson()],
    'homePageId': homePageId,
  };

  /// Sérialise le catalogue au format compact en omettant `homePageId` lorsqu'il est nul.
  Map<String, Object?> toCompactJson() => {
    'pages': [for (final page in pages) page.toCompactJson()],
    if (homePageId != null) 'homePageId': homePageId,
  };

  factory EditorPageCatalog.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.any((key) => !const {'pages', 'homePageId'}.contains(key)) ||
        value['pages'] is! List ||
        (value['homePageId'] != null && value['homePageId'] is! String)) {
      throw const FormatException('Invalid editor page catalog.');
    }
    try {
      return EditorPageCatalog(
        pages: [
          for (final page in value['pages'] as List)
            EditorPageConfig.fromJson(page),
        ],
        homePageId: value['homePageId'] as String?,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid editor page catalog: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorPageCatalog &&
          other.homePageId == homePageId &&
          listEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(homePageId, Object.hashAll(pages));
}
