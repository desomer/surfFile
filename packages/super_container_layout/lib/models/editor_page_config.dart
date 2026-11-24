/// Modèles de page routée ([EditorPageConfig]), de shell partagé ([EditorShellConfig])
/// et de catalogue de pages ([EditorPageCatalog]).
///
/// Persiste la liste des écrans et des shells de l'application, leurs chemins de route,
/// leurs identifiants de `Scaffold` / `SuperLayout` racines, la page d'accueil et le shell racine.
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

/// Coquille de mise en page partagée ([EditorShellConfig]) réutilisable par
/// plusieurs pages routées et éventuellement par la route hôte `'/'`.
///
/// Son identifiant [id] correspond à l'entrée `components[id]` (de type
/// `scaffold` / `superScaffold`) dont la région `body` sert de point d'insertion
/// pour le contenu de la page active.
@immutable
class EditorShellConfig {
  /// Crée une configuration de shell validée.
  EditorShellConfig({required this.id, required this.name}) {
    validate();
  }

  /// Identifiant unique du shell (également clé dans `Appearance.components`).
  final String id;

  /// Libellé lisible du shell affiché dans l'éditeur.
  final String name;

  /// Valide l'identifiant et le libellé du shell.
  void validate() {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Invalid editor shell identity or name.');
    }
  }

  /// Retourne une copie modifiée de cette configuration de shell.
  EditorShellConfig copyWith({String? id, String? name}) =>
      EditorShellConfig(id: id ?? this.id, name: name ?? this.name);

  /// Sérialise la configuration du shell en objet JSON.
  Map<String, Object?> toJson() => {'id': id, 'name': name};

  /// Sérialise la configuration du shell au format compact.
  Map<String, Object?> toCompactJson() => toJson();

  /// Décode une configuration de shell depuis un objet JSON.
  factory EditorShellConfig.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) => key is! String || !const {'id', 'name'}.contains(key),
        ) ||
        value['id'] is! String ||
        value['name'] is! String) {
      throw const FormatException('Invalid editor shell configuration.');
    }
    try {
      return EditorShellConfig(
        id: value['id'] as String,
        name: value['name'] as String,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid editor shell configuration: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorShellConfig && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A visually authored page with an identity independent of its route.
@immutable
class EditorPageConfig {
  EditorPageConfig({
    required this.id,
    required this.name,
    required this.path,
    this.pageType = EditorPageType.standard,
    this.shellId,
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

  /// Identifiant optionnel du shell ([EditorShellConfig.id]) enveloppant cette page.
  final String? shellId;

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
    if (shellId != null) {
      if (shellId!.trim().isEmpty) {
        throw ArgumentError('Editor page shellId must not be empty.');
      }
      if (pageType.isModal) {
        throw ArgumentError('Modal pages cannot be attached to a shell.');
      }
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
    String? shellId,
    bool clearShellId = false,
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
    shellId: clearShellId ? null : (shellId ?? this.shellId),
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
    if (shellId != null) 'shellId': shellId,
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
    if (shellId != null) 'shellId': shellId,
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
            'shellId',
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
    final rawShellId = value['shellId'];
    if (value.containsKey('shellId') && rawShellId is! String?) {
      throw const FormatException('Invalid editor page shellId.');
    }
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
        shellId: rawShellId as String?,
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
          other.shellId == shellId &&
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
    shellId,
    modalWidth,
    modalHeight,
    showCloseButton,
    layoutOverride,
    Object.hashAllUnordered(
      defaultParameters.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Ordered editor pages, shared shells and their optional startup/root bindings.
@immutable
class EditorPageCatalog {
  EditorPageCatalog({
    List<EditorPageConfig> pages = const [],
    List<EditorShellConfig> shells = const [],
    this.homePageId,
    this.rootShellId,
  }) : pages = List.unmodifiable(pages),
       shells = List.unmodifiable(shells) {
    validate();
  }

  const EditorPageCatalog.empty()
    : pages = const [],
      shells = const [],
      homePageId = null,
      rootShellId = null;

  final List<EditorPageConfig> pages;

  /// Liste ordonnée des shells partagés déclarés dans ce catalogue.
  final List<EditorShellConfig> shells;

  final String? homePageId;

  /// Identifiant optionnel du shell enveloppant la route hôte codée `'/'`.
  final String? rootShellId;

  /// Indique si le catalogue déclare au moins un shell partagé.
  bool get hasShells => shells.isNotEmpty;

  /// Retourne le shell correspondant à [id], ou `null` s'il est absent.
  EditorShellConfig? shellById(String? id) {
    if (id == null) return null;
    for (final shell in shells) {
      if (shell.id == id) return shell;
    }
    return null;
  }

  void validate() {
    final shellIds = <String>{};
    for (final shell in shells) {
      shell.validate();
      if (!shellIds.add(shell.id)) {
        throw ArgumentError('Duplicate editor shell ID "${shell.id}".');
      }
    }
    final pageIds = <String>{};
    for (final page in pages) {
      page.validate();
      if (!pageIds.add(page.id)) {
        throw ArgumentError('Duplicate editor page ID "${page.id}".');
      }
      if (shellIds.contains(page.id)) {
        throw ArgumentError(
          'Editor page ID "${page.id}" collides with a shell ID.',
        );
      }
      if (page.shellId != null && !shellIds.contains(page.shellId)) {
        throw ArgumentError(
          'Editor page "${page.id}" references unknown shell "${page.shellId}".',
        );
      }
    }
    if (homePageId != null && !pageIds.contains(homePageId)) {
      throw ArgumentError('The editor home page must exist in the catalog.');
    }
    if (rootShellId != null && !shellIds.contains(rootShellId)) {
      throw ArgumentError('The editor root shell must exist in the catalog.');
    }
  }

  EditorPageCatalog copyWith({
    List<EditorPageConfig>? pages,
    List<EditorShellConfig>? shells,
    String? homePageId,
    bool clearHomePage = false,
    String? rootShellId,
    bool clearRootShellId = false,
  }) => EditorPageCatalog(
    pages: pages ?? this.pages,
    shells: shells ?? this.shells,
    homePageId: clearHomePage ? null : homePageId ?? this.homePageId,
    rootShellId: clearRootShellId ? null : rootShellId ?? this.rootShellId,
  );

  Map<String, Object?> toJson() => {
    'pages': [for (final page in pages) page.toJson()],
    if (shells.isNotEmpty) 'shells': [for (final shell in shells) shell.toJson()],
    'homePageId': homePageId,
    if (rootShellId != null) 'rootShellId': rootShellId,
  };

  /// Sérialise le catalogue au format compact en omettant les valeurs par défaut.
  Map<String, Object?> toCompactJson() => {
    'pages': [for (final page in pages) page.toCompactJson()],
    if (shells.isNotEmpty)
      'shells': [for (final shell in shells) shell.toCompactJson()],
    if (homePageId != null) 'homePageId': homePageId,
    if (rootShellId != null) 'rootShellId': rootShellId,
  };

  factory EditorPageCatalog.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.any(
          (key) => !const {
            'pages',
            'homePageId',
            'shells',
            'rootShellId',
          }.contains(key),
        ) ||
        value['pages'] is! List ||
        (value.containsKey('shells') && value['shells'] is! List) ||
        (value['homePageId'] != null && value['homePageId'] is! String) ||
        (value['rootShellId'] != null && value['rootShellId'] is! String)) {
      throw const FormatException('Invalid editor page catalog.');
    }
    try {
      return EditorPageCatalog(
        pages: [
          for (final page in value['pages'] as List)
            EditorPageConfig.fromJson(page),
        ],
        shells: value.containsKey('shells')
            ? [
                for (final shell in value['shells'] as List)
                  EditorShellConfig.fromJson(shell),
              ]
            : const [],
        homePageId: value['homePageId'] as String?,
        rootShellId: value['rootShellId'] as String?,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid editor page catalog: $error');
    }
  }

  /// Applique un patch JSON partiel sur ce catalogue en préservant les champs omis.
  ///
  /// Utilisé par les mises à jour incrémentales Vibe afin de pouvoir modifier
  /// `pages`, `shells`, `homePageId` ou `rootShellId` indépendamment sans
  /// perdre les entrées déjà déclarées.
  EditorPageCatalog patchFromJson(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) =>
              key is! String ||
              !const {
                'pages',
                'homePageId',
                'shells',
                'rootShellId',
              }.contains(key),
        )) {
      throw const FormatException('Invalid editor page catalog.');
    }

    final List<EditorShellConfig> nextShells;
    final shellsUpdated = value.containsKey('shells');
    if (shellsUpdated) {
      final rawShells = value['shells'];
      if (rawShells is! List) {
        throw const FormatException('Invalid editor page catalog.');
      }
      nextShells = [
        for (final shell in rawShells) EditorShellConfig.fromJson(shell),
      ];
    } else {
      nextShells = shells;
    }

    final List<EditorPageConfig> nextPages;
    final pagesUpdated = value.containsKey('pages');
    if (pagesUpdated) {
      final rawPages = value['pages'];
      if (rawPages is! List) {
        throw const FormatException('Invalid editor page catalog.');
      }
      nextPages = [
        for (final page in rawPages) EditorPageConfig.fromJson(page),
      ];
    } else {
      nextPages = pages;
    }

    final String? nextHomePageId;
    if (value.containsKey('homePageId')) {
      final rawHomePageId = value['homePageId'];
      if (rawHomePageId != null && rawHomePageId is! String) {
        throw const FormatException('Invalid editor page catalog.');
      }
      nextHomePageId = rawHomePageId as String?;
    } else if (pagesUpdated &&
        homePageId != null &&
        !nextPages.any((page) => page.id == homePageId)) {
      nextHomePageId = null;
    } else {
      nextHomePageId = homePageId;
    }

    final String? nextRootShellId;
    if (value.containsKey('rootShellId')) {
      final rawRootShellId = value['rootShellId'];
      if (rawRootShellId != null && rawRootShellId is! String) {
        throw const FormatException('Invalid editor page catalog.');
      }
      nextRootShellId = rawRootShellId as String?;
    } else if (shellsUpdated &&
        rootShellId != null &&
        !nextShells.any((shell) => shell.id == rootShellId)) {
      nextRootShellId = null;
    } else {
      nextRootShellId = rootShellId;
    }

    try {
      return EditorPageCatalog(
        pages: nextPages,
        shells: nextShells,
        homePageId: nextHomePageId,
        rootShellId: nextRootShellId,
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
          other.rootShellId == rootShellId &&
          listEquals(other.pages, pages) &&
          listEquals(other.shells, shells);

  @override
  int get hashCode => Object.hash(
    homePageId,
    rootShellId,
    Object.hashAll(pages),
    Object.hashAll(shells),
  );
}
