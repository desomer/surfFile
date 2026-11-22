/// Modèles immuables d'architecture de l'information, de thème visuel et de navigation ([UxNavigationSpec], [UxRouteNode], [UxVisualThemeSeed]).
library;

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Pattern de navigation primaire du shell applicatif.
enum UxShellPattern {
  /// Rail de navigation vertical compact (recommandé sur Desktop).
  navigationRail('NavigationRail'),

  /// Barre supérieure horizontale.
  topBar('Barre supérieure'),

  /// Barre latérale étendue (Sidebar / Drawer fixe).
  sidebar('Barre latérale'),

  /// Navigation par onglets principaux.
  tabs('Onglets'),

  /// Coque minimale sans barre de navigation primaire persistante.
  minimal('Minimal');

  /// Construit un pattern de shell applicatif.
  const UxShellPattern(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un pattern de shell depuis JSON ou un alias courant, avec repli sur [navigationRail].
  static UxShellPattern fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final pattern in UxShellPattern.values) {
        if (pattern.name.toLowerCase() == norm ||
            pattern.label.toLowerCase() == norm) {
          return pattern;
        }
      }
      switch (norm) {
        case 'navigation_rail':
        case 'navigation-rail':
        case 'rail':
          return UxShellPattern.navigationRail;
        case 'top_bar':
        case 'top-bar':
        case 'appbar':
        case 'app_bar':
          return UxShellPattern.topBar;
        case 'side_bar':
        case 'side-bar':
        case 'drawer':
          return UxShellPattern.sidebar;
        case 'tab':
        case 'tabbar':
        case 'tab_bar':
          return UxShellPattern.tabs;
        case 'none':
        case 'blank':
          return UxShellPattern.minimal;
      }
    }
    return UxShellPattern.navigationRail;
  }
}

/// Profil de densité spatiale de l'interface.
enum UxDensityProfile {
  /// Densité compacte optimisée pour la productivité Desktop.
  compact('Compacte (Desktop)'),

  /// Densité équilibrée polyvalente.
  comfortable('Équilibrée'),

  /// Densité aérée à fort espacement.
  spacious('Aérée');

  /// Construit un profil de densité UX.
  const UxDensityProfile(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un profil de densité depuis JSON ou un alias courant, avec repli sur [compact].
  static UxDensityProfile fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final profile in UxDensityProfile.values) {
        if (profile.name.toLowerCase() == norm ||
            profile.label.toLowerCase() == norm) {
          return profile;
        }
      }
      switch (norm) {
        case 'dense':
        case 'desktop':
          return UxDensityProfile.compact;
        case 'balanced':
        case 'standard':
        case 'normal':
        case 'equilibree':
          return UxDensityProfile.comfortable;
        case 'relaxed':
        case 'airy':
        case 'aeree':
          return UxDensityProfile.spacious;
      }
    }
    return UxDensityProfile.compact;
  }
}

/// Graine d'identité visuelle Material 3 et conventions éditoriales UX du projet.
@immutable
class UxVisualThemeSeed {
  /// Construit une graine de thème visuel immuable.
  const UxVisualThemeSeed({
    this.accentHex = '#3F51B5',
    this.themeMode = 'system',
    this.surfaceSystem = 'material',
    this.fontFamily = 'Inter',
    this.density = UxDensityProfile.compact,
    this.cardRadius = 14.0,
    this.uxVoiceGuidelines = '',
  });

  /// Graine visuelle par défaut conforme au Design System Material 3 Desktop.
  static const UxVisualThemeSeed defaults = UxVisualThemeSeed();

  /// Couleur d'accentuation primaire au format hexadécimal majuscule `#RRGGBB`.
  final String accentHex;

  /// Mode de luminosité cible (`'system'`, `'light'` ou `'dark'`).
  final String themeMode;

  /// Système de rendu des surfaces (`'material'`, `'liquidGlass'` ou `'neumorphism'`).
  final String surfaceSystem;

  /// Police typographique principale (ex. `'Inter'`, `'Plus Jakarta Sans'`).
  final String fontFamily;

  /// Profil de densité spatiale appliqué aux composants et collections.
  final UxDensityProfile density;

  /// Rayon d'arrondi par défaut des cartes principales (`0..32`).
  final double cardRadius;

  /// Consignes de ton éditorial, micro-copie et accessibilité UX.
  final String uxVoiceGuidelines;

  /// Vrai si tous les paramètres visuels correspondent à [defaults].
  bool get isDefault => this == defaults;

  /// Normalise une couleur hexadécimale en `#RRGGBB` majuscule, avec repli sur [fallback].
  static String normalizeAccentHex(
    String raw, {
    String fallback = '#3F51B5',
  }) {
    final trimmed = raw.trim();
    final stripped = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (RegExp(r'^[0-9A-Fa-f]{3}$').hasMatch(stripped)) {
      final r = stripped[0];
      final g = stripped[1];
      final b = stripped[2];
      return '#$r$r$g$g$b$b'.toUpperCase();
    }
    if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(stripped)) {
      return '#${stripped.toUpperCase()}';
    }
    if (RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(stripped)) {
      return '#${stripped.substring(2).toUpperCase()}';
    }
    return fallback;
  }

  /// Normalise un mode de thème vers `'system'`, `'light'` ou `'dark'`.
  static String normalizeThemeMode(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'light' || 'clair' => 'light',
        'dark' || 'sombre' => 'dark',
        _ => 'system',
      };

  /// Normalise un système de surface vers `'material'`, `'liquidGlass'` ou `'neumorphism'`.
  static String normalizeSurfaceSystem(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'liquidglass' ||
        'liquid_glass' ||
        'liquid-glass' ||
        'glass' ||
        'glassmorphism' => 'liquidGlass',
        'neumorphism' || 'neumorphic' => 'neumorphism',
        _ => 'material',
      };

  /// Vérifie les invariants de la graine de thème visuel.
  void validate() {
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(accentHex)) {
      throw FormatException(
        'UxVisualThemeSeed.accentHex doit être au format #RRGGBB : $accentHex',
      );
    }
    if (themeMode != 'system' && themeMode != 'light' && themeMode != 'dark') {
      throw FormatException(
        'UxVisualThemeSeed.themeMode invalide : $themeMode',
      );
    }
    if (surfaceSystem != 'material' &&
        surfaceSystem != 'liquidGlass' &&
        surfaceSystem != 'neumorphism') {
      throw FormatException(
        'UxVisualThemeSeed.surfaceSystem invalide : $surfaceSystem',
      );
    }
    if (fontFamily.trim().isEmpty) {
      throw const FormatException(
        'UxVisualThemeSeed.fontFamily ne peut pas être vide.',
      );
    }
    if (!cardRadius.isFinite || cardRadius < 0 || cardRadius > 32) {
      throw FormatException(
        'UxVisualThemeSeed.cardRadius doit être compris entre 0 et 32 : $cardRadius',
      );
    }
  }

  /// Retourne une copie modifiée (normalise la casse `#RRGGBB` et borne `cardRadius` sur `0..32`).
  UxVisualThemeSeed copyWith({
    String? accentHex,
    String? themeMode,
    String? surfaceSystem,
    String? fontFamily,
    UxDensityProfile? density,
    double? cardRadius,
    String? uxVoiceGuidelines,
  }) => UxVisualThemeSeed(
    accentHex: accentHex == null
        ? this.accentHex
        : normalizeAccentHex(accentHex, fallback: accentHex.trim()),
    themeMode: themeMode ?? this.themeMode,
    surfaceSystem: surfaceSystem ?? this.surfaceSystem,
    fontFamily: fontFamily ?? this.fontFamily,
    density: density ?? this.density,
    cardRadius: cardRadius == null
        ? this.cardRadius
        : (cardRadius.isFinite ? cardRadius.clamp(0.0, 32.0) : cardRadius),
    uxVoiceGuidelines: uxVoiceGuidelines ?? this.uxVoiceGuidelines,
  );

  /// Sérialise la graine visuelle en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'accentHex': normalizeAccentHex(accentHex),
    'themeMode': themeMode,
    'surfaceSystem': surfaceSystem,
    'fontFamily': fontFamily,
    'density': density.name,
    'cardRadius': cardRadius,
    'uxVoiceGuidelines': uxVoiceGuidelines,
  };

  /// Désérialise une graine visuelle depuis JSON avec normalisation tolérante.
  factory UxVisualThemeSeed.fromJson(Object? raw) {
    if (raw == null) return UxVisualThemeSeed.defaults;
    if (raw is! Map) {
      throw const FormatException(
        'UxVisualThemeSeed doit être un objet JSON.',
      );
    }
    final rawFont = (raw['fontFamily'] as String?)?.trim() ?? '';
    final rawRadius = raw['cardRadius'];
    final parsedRadius = switch (rawRadius) {
      final num v when v.isFinite => v.toDouble().clamp(0.0, 32.0),
      final String s =>
        (double.tryParse(s.trim()) ?? 14.0).clamp(0.0, 32.0),
      _ => 14.0,
    };
    final seed = UxVisualThemeSeed(
      accentHex: normalizeAccentHex((raw['accentHex'] as String?) ?? ''),
      themeMode: normalizeThemeMode((raw['themeMode'] as String?) ?? 'system'),
      surfaceSystem: normalizeSurfaceSystem(
        (raw['surfaceSystem'] as String?) ?? 'material',
      ),
      fontFamily: rawFont.isEmpty ? 'Inter' : rawFont,
      density: UxDensityProfile.fromJson(raw['density']),
      cardRadius: parsedRadius,
      uxVoiceGuidelines: (raw['uxVoiceGuidelines'] as String?)?.trim() ?? '',
    );
    seed.validate();
    return seed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxVisualThemeSeed &&
          other.accentHex.toUpperCase() == accentHex.toUpperCase() &&
          other.themeMode == themeMode &&
          other.surfaceSystem == surfaceSystem &&
          other.fontFamily == fontFamily &&
          other.density == density &&
          other.cardRadius == cardRadius &&
          other.uxVoiceGuidelines == uxVoiceGuidelines;

  @override
  int get hashCode => Object.hash(
    accentHex.toUpperCase(),
    themeMode,
    surfaceSystem,
    fontFamily,
    density,
    cardRadius,
    uxVoiceGuidelines,
  );
}

/// Nœud de route applicative reliant la navigation UX au catalogue de pages SuperDesigner.
@immutable
class UxRouteNode {
  /// Construit un nœud de route immuable en normalisant un chemin non vide pour débuter par `'/'`.
  UxRouteNode({
    required this.id,
    required String path,
    required this.title,
    this.iconName = 'web_asset_outlined',
    this.pageType = EditorPageType.standard,
    this.moduleId = '',
    this.parentRouteId = '',
    List<String> allowedPersonaIds = const <String>[],
    List<String> permissionRuleIds = const <String>[],
    this.showInPrimaryNav = true,
  }) : path = normalizePath(path),
       allowedPersonaIds = List<String>.unmodifiable(allowedPersonaIds),
       permissionRuleIds = List<String>.unmodifiable(permissionRuleIds);

  /// Identifiant unique de la route (ex. `route_commandes`).
  final String id;

  /// Chemin applicatif commençant par `'/'` (ex. `'/'`, `'/commandes'`).
  final String path;

  /// Intitulé affiché dans la navigation et la barre de titre.
  final String title;

  /// Nom d'icône Material associé à l'entrée de navigation.
  final String iconName;

  /// Type de page SuperDesigner (`standard`, `a4Document`, `dialog`, `bottomSheet`, `sideSheet`).
  final EditorPageType pageType;

  /// Identifiant optionnel du [SpecModule] fonctionnel rattaché.
  final String moduleId;

  /// Identifiant de la route parente (pour sous-routes ou modales contextuelles).
  final String parentRouteId;

  /// Identifiants des personas autorisés à accéder à cette route (vide = tous).
  final List<String> allowedPersonaIds;

  /// Identifiants ou codes des règles de gestion d'habilitation (`RG-xxx`) associées.
  final List<String> permissionRuleIds;

  /// Indique si la route apparaît dans la navigation primaire du shell.
  final bool showInPrimaryNav;

  /// Normalise un chemin non vide afin qu'il débute par `'/'` sans barre oblique finale superflue.
  static String normalizePath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    final collapsed = withLeadingSlash.replaceAll(RegExp(r'/+'), '/');
    if (collapsed.length > 1 && collapsed.endsWith('/')) {
      return collapsed.substring(0, collapsed.length - 1);
    }
    return collapsed;
  }

  /// Vérifie les invariants du nœud de route.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('UxRouteNode.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException('UxRouteNode.title ne peut pas être vide.');
    }
    if (path.trim().isEmpty || !path.startsWith('/')) {
      throw FormatException(
        'UxRouteNode.path doit être non vide et commencer par "/" : $path',
      );
    }
  }

  /// Retourne une copie modifiée.
  UxRouteNode copyWith({
    String? id,
    String? path,
    String? title,
    String? iconName,
    EditorPageType? pageType,
    String? moduleId,
    String? parentRouteId,
    List<String>? allowedPersonaIds,
    List<String>? permissionRuleIds,
    bool? showInPrimaryNav,
  }) => UxRouteNode(
    id: id ?? this.id,
    path: path ?? this.path,
    title: title ?? this.title,
    iconName: iconName ?? this.iconName,
    pageType: pageType ?? this.pageType,
    moduleId: moduleId ?? this.moduleId,
    parentRouteId: parentRouteId ?? this.parentRouteId,
    allowedPersonaIds: allowedPersonaIds ?? this.allowedPersonaIds,
    permissionRuleIds: permissionRuleIds ?? this.permissionRuleIds,
    showInPrimaryNav: showInPrimaryNav ?? this.showInPrimaryNav,
  );

  /// Sérialise la route en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'path': path,
    'title': title,
    'iconName': iconName,
    'pageType': pageType.name,
    'moduleId': moduleId,
    'parentRouteId': parentRouteId,
    'allowedPersonaIds': allowedPersonaIds,
    'permissionRuleIds': permissionRuleIds,
    'showInPrimaryNav': showInPrimaryNav,
  };

  /// Désérialise un nœud de route depuis JSON avec valeurs de repli tolérantes.
  factory UxRouteNode.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UxRouteNode doit être un objet JSON.');
    }
    final rawTitle =
        (raw['title'] as String?)?.trim() ??
        (raw['name'] as String?)?.trim() ??
        '';
    final title = rawTitle.isEmpty ? 'Page sans titre' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final id = rawId.isEmpty ? 'route_${title.hashCode.abs()}' : rawId;
    final rawPath = (raw['path'] as String?)?.trim() ?? '';
    final derivedPath = rawPath.isEmpty ? '/${_slugify(title)}' : rawPath;
    final rawIcon = (raw['iconName'] as String?)?.trim() ?? '';
    final pageType = _parseEditorPageType(raw['pageType']);
    final node = UxRouteNode(
      id: id,
      path: derivedPath,
      title: title,
      iconName: rawIcon.isEmpty ? 'web_asset_outlined' : rawIcon,
      pageType: pageType,
      moduleId: (raw['moduleId'] as String?)?.trim() ?? '',
      parentRouteId: (raw['parentRouteId'] as String?)?.trim() ?? '',
      allowedPersonaIds: _stringList(raw['allowedPersonaIds']),
      permissionRuleIds: _stringList(raw['permissionRuleIds']),
      showInPrimaryNav: raw['showInPrimaryNav'] is bool
          ? raw['showInPrimaryNav'] as bool
          : !pageType.isModal,
    );
    node.validate();
    return node;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxRouteNode &&
          other.id == id &&
          other.path == path &&
          other.title == title &&
          other.iconName == iconName &&
          other.pageType == pageType &&
          other.moduleId == moduleId &&
          other.parentRouteId == parentRouteId &&
          listEquals(other.allowedPersonaIds, allowedPersonaIds) &&
          listEquals(other.permissionRuleIds, permissionRuleIds) &&
          other.showInPrimaryNav == showInPrimaryNav;

  @override
  int get hashCode => Object.hash(
    id,
    path,
    title,
    iconName,
    pageType,
    moduleId,
    parentRouteId,
    Object.hashAll(allowedPersonaIds),
    Object.hashAll(permissionRuleIds),
    showInPrimaryNav,
  );
}

/// Spécification globale de navigation, de shell applicatif et d'identité visuelle (étape UX 2).
@immutable
class UxNavigationSpec {
  /// Construit une spécification de navigation immuable.
  UxNavigationSpec({
    this.shellPattern = UxShellPattern.navigationRail,
    this.hasAppBar = true,
    this.hasBreadcrumbs = true,
    this.hasGlobalSearch = false,
    this.homeRouteId = '',
    List<UxRouteNode> routes = const <UxRouteNode>[],
    this.visualTheme = UxVisualThemeSeed.defaults,
  }) : routes = List<UxRouteNode>.unmodifiable(routes);

  /// Spécification de navigation vide initiale.
  static final UxNavigationSpec empty = UxNavigationSpec();

  /// Pattern structurel du shell applicatif.
  final UxShellPattern shellPattern;

  /// Indique si une barre d'application supérieure (`ApplicationBar`) est affichée.
  final bool hasAppBar;

  /// Indique si un fil d'Ariane contextuel est affiché pour les sous-vues.
  final bool hasBreadcrumbs;

  /// Indique si une recherche globale transversale est proposée dans le shell.
  final bool hasGlobalSearch;

  /// Identifiant de la route d'accueil ouverte au démarrage.
  final String homeRouteId;

  /// Catalogue ordonné des routes applicatives et modales.
  final List<UxRouteNode> routes;

  /// Graine de thème visuel Material 3 et charte d'expression UX.
  final UxVisualThemeSeed visualTheme;

  /// Vrai si des routes ont été définies ou si la configuration diffère des valeurs initiales.
  bool get hasContent =>
      routes.isNotEmpty ||
      homeRouteId.trim().isNotEmpty ||
      !visualTheme.isDefault ||
      shellPattern != UxShellPattern.navigationRail ||
      !hasAppBar ||
      !hasBreadcrumbs ||
      hasGlobalSearch;

  /// Recherche une route par identifiant ou chemin normalisé (insensible à la casse).
  UxRouteNode? findRoute(String idOrPath) {
    final trimmed = idOrPath.trim();
    if (trimmed.isEmpty) return null;
    final needle = trimmed.toLowerCase();
    for (final route in routes) {
      if (route.id.toLowerCase() == needle) return route;
    }
    final normalizedNeedle = UxRouteNode.normalizePath(trimmed).toLowerCase();
    for (final route in routes) {
      if (route.path.toLowerCase() == needle ||
          route.path.toLowerCase() == normalizedNeedle) {
        return route;
      }
    }
    return null;
  }

  /// Vérifie les invariants du thème visuel, des routes et l'unicité des IDs/chemins non modaux.
  void validate() {
    visualTheme.validate();
    final routeIds = <String>{};
    final nonModalPaths = <String>{};
    for (final route in routes) {
      route.validate();
      if (!routeIds.add(route.id)) {
        throw FormatException('Identifiant de route UX dupliqué : ${route.id}');
      }
      if (!route.pageType.isModal && !nonModalPaths.add(route.path)) {
        throw FormatException(
          'Chemin de route UX non modale dupliqué : ${route.path}',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  UxNavigationSpec copyWith({
    UxShellPattern? shellPattern,
    bool? hasAppBar,
    bool? hasBreadcrumbs,
    bool? hasGlobalSearch,
    String? homeRouteId,
    List<UxRouteNode>? routes,
    UxVisualThemeSeed? visualTheme,
  }) => UxNavigationSpec(
    shellPattern: shellPattern ?? this.shellPattern,
    hasAppBar: hasAppBar ?? this.hasAppBar,
    hasBreadcrumbs: hasBreadcrumbs ?? this.hasBreadcrumbs,
    hasGlobalSearch: hasGlobalSearch ?? this.hasGlobalSearch,
    homeRouteId: homeRouteId ?? this.homeRouteId,
    routes: routes ?? this.routes,
    visualTheme: visualTheme ?? this.visualTheme,
  );

  /// Sérialise la spécification de navigation en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'shellPattern': shellPattern.name,
    'hasAppBar': hasAppBar,
    'hasBreadcrumbs': hasBreadcrumbs,
    'hasGlobalSearch': hasGlobalSearch,
    'homeRouteId': homeRouteId,
    'routes': [for (final r in routes) r.toJson()],
    'visualTheme': visualTheme.toJson(),
  };

  /// Désérialise une spécification de navigation depuis JSON.
  factory UxNavigationSpec.fromJson(Object? raw) {
    if (raw == null) return UxNavigationSpec.empty;
    if (raw is! Map) {
      throw const FormatException(
        'UxNavigationSpec doit être un objet JSON.',
      );
    }
    final parsedRoutes = <UxRouteNode>[];
    final seenIds = <String>{};
    final seenNonModalPaths = <String>{};
    if (raw['routes'] is List) {
      for (final item in raw['routes'] as List) {
        var route = UxRouteNode.fromJson(item);
        if (!seenIds.add(route.id)) {
          var suffix = 2;
          while (!seenIds.add('${route.id}_$suffix')) {
            suffix++;
          }
          route = route.copyWith(id: '${route.id}_$suffix');
        }
        if (!route.pageType.isModal && !seenNonModalPaths.add(route.path)) {
          final base = route.path == '/' ? '/page' : route.path;
          var suffix = 2;
          while (!seenNonModalPaths.add('$base-$suffix')) {
            suffix++;
          }
          route = route.copyWith(path: '$base-$suffix');
        }
        parsedRoutes.add(route);
      }
    }

    final nav = UxNavigationSpec(
      shellPattern: UxShellPattern.fromJson(raw['shellPattern']),
      hasAppBar: raw['hasAppBar'] is bool ? raw['hasAppBar'] as bool : true,
      hasBreadcrumbs: raw['hasBreadcrumbs'] is bool
          ? raw['hasBreadcrumbs'] as bool
          : true,
      hasGlobalSearch: raw['hasGlobalSearch'] == true,
      homeRouteId: (raw['homeRouteId'] as String?)?.trim() ?? '',
      routes: parsedRoutes,
      visualTheme: UxVisualThemeSeed.fromJson(raw['visualTheme']),
    );
    nav.validate();
    return nav;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxNavigationSpec &&
          other.shellPattern == shellPattern &&
          other.hasAppBar == hasAppBar &&
          other.hasBreadcrumbs == hasBreadcrumbs &&
          other.hasGlobalSearch == hasGlobalSearch &&
          other.homeRouteId == homeRouteId &&
          listEquals(other.routes, routes) &&
          other.visualTheme == visualTheme;

  @override
  int get hashCode => Object.hash(
    shellPattern,
    hasAppBar,
    hasBreadcrumbs,
    hasGlobalSearch,
    homeRouteId,
    Object.hashAll(routes),
    visualTheme,
  );
}

EditorPageType _parseEditorPageType(Object? raw) {
  if (raw == null) return EditorPageType.standard;
  try {
    return EditorPageType.fromJson(raw);
  } on FormatException {
    if (raw is String) {
      switch (raw.trim().toLowerCase()) {
        case 'a4document':
        case 'a4_document':
        case 'a4-document':
        case 'document_a4':
        case 'documenta4':
        case 'a4':
        case 'pdf':
          return EditorPageType.a4Document;
        case 'dialog':
        case 'modal':
          return EditorPageType.dialog;
        case 'bottomsheet':
        case 'bottom_sheet':
        case 'bottom-sheet':
        case 'sheet':
          return EditorPageType.bottomSheet;
        case 'sidesheet':
        case 'side_sheet':
        case 'side-sheet':
        case 'drawer':
          return EditorPageType.sideSheet;
      }
    }
    return EditorPageType.standard;
  }
}

String _slugify(String input) {
  final lower = input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãäå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return lower.isEmpty ? 'page' : lower;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
