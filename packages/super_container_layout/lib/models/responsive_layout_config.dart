/// Modèles purs de configuration responsive : breakpoints, container max-width et gutters.
///
/// Définit les seuils d'écran ([ResponsiveBreakpoint], [ResponsiveBreakpointsConfig]),
/// les marges latérales adaptatives ([ResponsiveGuttersConfig]), la configuration globale
/// ([ResponsiveLayoutConfig]) portée par `Appearance` et la surcharge optionnelle par
/// page ([ResponsiveLayoutOverride]) portée par `EditorPageConfig`.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'json_numbers.dart';

/// Palier de largeur d'écran reconnu par le moteur de mise en page.
enum ResponsiveBreakpoint {
  /// Mobile (référence 375 px, largeur < seuil Tablette).
  mobile('Mobile', 375),

  /// Tablette (seuil par défaut 768 px).
  tablet('Tablette', 768),

  /// Desktop standard (seuil par défaut 1280 px).
  desktop('Desktop', 1280),

  /// Large Desktop (seuil par défaut 1440 px).
  largeDesktop('Large Desktop', 1440);

  const ResponsiveBreakpoint(this.label, this.defaultWidth);

  /// Libellé lisible du palier.
  final String label;

  /// Largeur de référence par défaut (px) associée à ce palier.
  final double defaultWidth;

  /// Décode un [ResponsiveBreakpoint] depuis une chaîne JSON.
  static ResponsiveBreakpoint fromJson(Object? value) => switch (value) {
    'mobile' => ResponsiveBreakpoint.mobile,
    'tablet' || 'tablette' => ResponsiveBreakpoint.tablet,
    'desktop' => ResponsiveBreakpoint.desktop,
    'largeDesktop' ||
    'large_desktop' ||
    'large-desktop' => ResponsiveBreakpoint.largeDesktop,
    _ => throw FormatException('Breakpoint responsive invalide : $value.'),
  };
}

/// Mode d'occupation horizontale du `body` d'une page standard.
enum PageContainerMode {
  /// Pleine largeur native sans contrainte `maxWidth` ni gutter automatique.
  fullPage(
    'Pleine page',
    'Occupe toute la largeur disponible sans contrainte ni marge latérale automatique.',
  ),

  /// Conteneur centré borné à `maxWidth` avec marges latérales flexibles et gutters.
  constrained(
    'Conteneur centré',
    'Centre le contenu dans une largeur maximale (ex. 1440 px) avec marges latérales flexibles et gutters adaptatifs.',
  );

  const PageContainerMode(this.label, this.description);

  /// Libellé court affiché dans les éditeurs.
  final String label;

  /// Description concise du comportement associé.
  final String description;

  /// Décode un [PageContainerMode] depuis une chaîne JSON.
  static PageContainerMode fromJson(Object? value) => switch (value) {
    null || 'fullPage' || 'full' || 'fullWidth' => PageContainerMode.fullPage,
    'constrained' || 'centered' || 'container' => PageContainerMode.constrained,
    _ => throw FormatException('Mode de conteneur de page invalide : $value.'),
  };
}

/// Configuration des seuils de breakpoints (px) utilisés pour la résolution et l'aperçu.
@immutable
class ResponsiveBreakpointsConfig {
  /// Largeur de référence Mobile par défaut (px).
  static const double defaultMobileWidth = 375.0;

  /// Seuil minimal Tablette par défaut (px).
  static const double defaultTabletMinWidth = 768.0;

  /// Seuil minimal Desktop par défaut (px).
  static const double defaultDesktopMinWidth = 1280.0;

  /// Seuil minimal Large Desktop par défaut (px).
  static const double defaultLargeDesktopMinWidth = 1440.0;

  static const double _minWidth = 200.0;
  static const double _maxWidth = 10000.0;

  const ResponsiveBreakpointsConfig({
    this.mobileWidth = defaultMobileWidth,
    this.tabletMinWidth = defaultTabletMinWidth,
    this.desktopMinWidth = defaultDesktopMinWidth,
    this.largeDesktopMinWidth = defaultLargeDesktopMinWidth,
  });

  /// Largeur de référence/aperçu pour le palier Mobile.
  final double mobileWidth;

  /// Largeur minimale à partir de laquelle le palier Tablette est actif.
  final double tabletMinWidth;

  /// Largeur minimale à partir de laquelle le palier Desktop est actif.
  final double desktopMinWidth;

  /// Largeur minimale à partir de laquelle le palier Large Desktop est actif.
  final double largeDesktopMinWidth;

  /// Vérifie la stricte progression et la validité numérique des seuils.
  void validate() {
    for (final (name, value) in [
      ('mobileWidth', mobileWidth),
      ('tabletMinWidth', tabletMinWidth),
      ('desktopMinWidth', desktopMinWidth),
      ('largeDesktopMinWidth', largeDesktopMinWidth),
    ]) {
      if (!value.isFinite || value < _minWidth || value > _maxWidth) {
        throw ArgumentError(
          'Le seuil "$name" doit être compris entre $_minWidth et $_maxWidth px.',
        );
      }
    }
    if (!(mobileWidth < tabletMinWidth &&
        tabletMinWidth < desktopMinWidth &&
        desktopMinWidth < largeDesktopMinWidth)) {
      throw ArgumentError(
        'Les seuils de breakpoints doivent être strictement croissants '
        '(mobile < tablet < desktop < largeDesktop).',
      );
    }
  }

  /// Détermine le [ResponsiveBreakpoint] correspondant à [width] (px).
  ResponsiveBreakpoint resolveBreakpoint(double width) {
    if (!width.isFinite || width < tabletMinWidth) {
      return ResponsiveBreakpoint.mobile;
    }
    if (width < desktopMinWidth) {
      return ResponsiveBreakpoint.tablet;
    }
    if (width < largeDesktopMinWidth) {
      return ResponsiveBreakpoint.desktop;
    }
    return ResponsiveBreakpoint.largeDesktop;
  }

  /// Retourne la largeur de simulation d'aperçu pour [breakpoint].
  double previewWidthFor(ResponsiveBreakpoint breakpoint) =>
      switch (breakpoint) {
        ResponsiveBreakpoint.mobile => mobileWidth,
        ResponsiveBreakpoint.tablet => tabletMinWidth,
        ResponsiveBreakpoint.desktop => desktopMinWidth,
        ResponsiveBreakpoint.largeDesktop => largeDesktopMinWidth,
      };

  ResponsiveBreakpointsConfig copyWith({
    double? mobileWidth,
    double? tabletMinWidth,
    double? desktopMinWidth,
    double? largeDesktopMinWidth,
  }) => ResponsiveBreakpointsConfig(
    mobileWidth: mobileWidth ?? this.mobileWidth,
    tabletMinWidth: tabletMinWidth ?? this.tabletMinWidth,
    desktopMinWidth: desktopMinWidth ?? this.desktopMinWidth,
    largeDesktopMinWidth: largeDesktopMinWidth ?? this.largeDesktopMinWidth,
  );

  Map<String, Object?> toJson() => {
    'mobileWidth': JsonNumbers.round(mobileWidth),
    'tabletMinWidth': JsonNumbers.round(tabletMinWidth),
    'desktopMinWidth': JsonNumbers.round(desktopMinWidth),
    'largeDesktopMinWidth': JsonNumbers.round(largeDesktopMinWidth),
  };

  Map<String, Object?> toCompactJson() => {
    if (mobileWidth != defaultMobileWidth)
      'mobileWidth': JsonNumbers.round(mobileWidth),
    if (tabletMinWidth != defaultTabletMinWidth)
      'tabletMinWidth': JsonNumbers.round(tabletMinWidth),
    if (desktopMinWidth != defaultDesktopMinWidth)
      'desktopMinWidth': JsonNumbers.round(desktopMinWidth),
    if (largeDesktopMinWidth != defaultLargeDesktopMinWidth)
      'largeDesktopMinWidth': JsonNumbers.round(largeDesktopMinWidth),
  };

  factory ResponsiveBreakpointsConfig.fromJson(Object? value) {
    if (value == null) return const ResponsiveBreakpointsConfig();
    if (value is! Map) {
      throw const FormatException('Configuration de breakpoints invalide.');
    }
    const known = {
      'mobileWidth',
      'tabletMinWidth',
      'desktopMinWidth',
      'largeDesktopMinWidth',
    };
    if (value.keys.any((key) => !known.contains(key))) {
      throw const FormatException(
        'Clé inconnue dans la configuration de breakpoints.',
      );
    }
    double readThreshold(String key, double fallback) {
      final raw = value[key];
      if (raw == null) return fallback;
      if (raw is! num || !raw.isFinite) {
        throw FormatException('Seuil de breakpoint invalide pour "$key".');
      }
      return raw.toDouble();
    }

    final result = ResponsiveBreakpointsConfig(
      mobileWidth: readThreshold('mobileWidth', defaultMobileWidth),
      tabletMinWidth: readThreshold('tabletMinWidth', defaultTabletMinWidth),
      desktopMinWidth: readThreshold('desktopMinWidth', defaultDesktopMinWidth),
      largeDesktopMinWidth: readThreshold(
        'largeDesktopMinWidth',
        defaultLargeDesktopMinWidth,
      ),
    );
    try {
      result.validate();
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ResponsiveBreakpointsConfig &&
      other.mobileWidth == mobileWidth &&
      other.tabletMinWidth == tabletMinWidth &&
      other.desktopMinWidth == desktopMinWidth &&
      other.largeDesktopMinWidth == largeDesktopMinWidth;

  @override
  int get hashCode => Object.hash(
    mobileWidth,
    tabletMinWidth,
    desktopMinWidth,
    largeDesktopMinWidth,
  );
}

/// Configuration des gutters horizontaux (marges intérieures gauche/droite du conteneur).
@immutable
class ResponsiveGuttersConfig {
  /// Gutter horizontal Mobile par défaut (24 px).
  static const double defaultMobileGutter = 24.0;

  /// Gutter horizontal Desktop par défaut (32 px).
  static const double defaultDesktopGutter = 32.0;

  static const double maxGutter = 400.0;

  const ResponsiveGuttersConfig({
    this.mobile = defaultMobileGutter,
    this.tablet,
    this.desktop = defaultDesktopGutter,
    this.largeDesktop,
  });

  /// Marge horizontale appliquée au palier Mobile (et Tablette si [tablet] est `null`).
  final double mobile;

  /// Marge horizontale optionnelle spécifique au palier Tablette.
  final double? tablet;

  /// Marge horizontale appliquée au palier Desktop (et Large Desktop si [largeDesktop] est `null`).
  final double desktop;

  /// Marge horizontale optionnelle spécifique au palier Large Desktop.
  final double? largeDesktop;

  /// Résout la marge horizontale (px) à appliquer pour [breakpoint].
  double gutterFor(ResponsiveBreakpoint breakpoint) => switch (breakpoint) {
    ResponsiveBreakpoint.mobile => mobile,
    ResponsiveBreakpoint.tablet => tablet ?? mobile,
    ResponsiveBreakpoint.desktop => desktop,
    ResponsiveBreakpoint.largeDesktop => largeDesktop ?? desktop,
  };

  /// Vérifie la validité des valeurs de gutters.
  void validate() {
    for (final (name, value) in [
      ('mobile', mobile),
      if (tablet != null) ('tablet', tablet!),
      ('desktop', desktop),
      if (largeDesktop != null) ('largeDesktop', largeDesktop!),
    ]) {
      if (!value.isFinite || value < 0 || value > maxGutter) {
        throw ArgumentError(
          'Le gutter "$name" doit être compris entre 0 et $maxGutter px.',
        );
      }
    }
  }

  ResponsiveGuttersConfig copyWith({
    double? mobile,
    double? tablet,
    bool clearTablet = false,
    double? desktop,
    double? largeDesktop,
    bool clearLargeDesktop = false,
  }) => ResponsiveGuttersConfig(
    mobile: mobile ?? this.mobile,
    tablet: clearTablet ? null : (tablet ?? this.tablet),
    desktop: desktop ?? this.desktop,
    largeDesktop: clearLargeDesktop
        ? null
        : (largeDesktop ?? this.largeDesktop),
  );

  Map<String, Object?> toJson() => {
    'mobile': JsonNumbers.round(mobile),
    if (tablet != null) 'tablet': JsonNumbers.round(tablet!),
    'desktop': JsonNumbers.round(desktop),
    if (largeDesktop != null) 'largeDesktop': JsonNumbers.round(largeDesktop!),
  };

  Map<String, Object?> toCompactJson() => {
    if (mobile != defaultMobileGutter) 'mobile': JsonNumbers.round(mobile),
    if (tablet != null) 'tablet': JsonNumbers.round(tablet!),
    if (desktop != defaultDesktopGutter) 'desktop': JsonNumbers.round(desktop),
    if (largeDesktop != null) 'largeDesktop': JsonNumbers.round(largeDesktop!),
  };

  factory ResponsiveGuttersConfig.fromJson(Object? value) {
    if (value == null) return const ResponsiveGuttersConfig();
    if (value is! Map) {
      throw const FormatException('Configuration de gutters invalide.');
    }
    const known = {'mobile', 'tablet', 'desktop', 'largeDesktop'};
    if (value.keys.any((key) => !known.contains(key))) {
      throw const FormatException(
        'Clé inconnue dans la configuration de gutters.',
      );
    }
    double? readOptional(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! num || !raw.isFinite) {
        throw FormatException('Gutter invalide pour "$key".');
      }
      return raw.toDouble();
    }

    final result = ResponsiveGuttersConfig(
      mobile: readOptional('mobile') ?? defaultMobileGutter,
      tablet: readOptional('tablet'),
      desktop: readOptional('desktop') ?? defaultDesktopGutter,
      largeDesktop: readOptional('largeDesktop'),
    );
    try {
      result.validate();
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ResponsiveGuttersConfig &&
      other.mobile == mobile &&
      other.tablet == tablet &&
      other.desktop == desktop &&
      other.largeDesktop == largeDesktop;

  @override
  int get hashCode => Object.hash(mobile, tablet, desktop, largeDesktop);
}

/// Résultat résolu pour une largeur d'affichage donnée.
@immutable
class ResolvedPageLayout {
  const ResolvedPageLayout({
    required this.breakpoint,
    required this.containerMode,
    required this.maxWidth,
    required this.gutter,
  });

  /// Palier responsive actif.
  final ResponsiveBreakpoint breakpoint;

  /// Mode effectif appliqué au `body`.
  final PageContainerMode containerMode;

  /// Largeur maximale du conteneur (`null` en mode [PageContainerMode.fullPage]).
  final double? maxWidth;

  /// Marge horizontale gauche/droite (px) appliquée au conteneur (`0` en `fullPage`).
  final double gutter;

  /// Indique si un conteneur borné et centré est actif.
  bool get isConstrained =>
      containerMode == PageContainerMode.constrained && maxWidth != null;

  @override
  bool operator ==(Object other) =>
      other is ResolvedPageLayout &&
      other.breakpoint == breakpoint &&
      other.containerMode == containerMode &&
      other.maxWidth == maxWidth &&
      other.gutter == gutter;

  @override
  int get hashCode => Object.hash(breakpoint, containerMode, maxWidth, gutter);
}

/// Configuration responsive globale de mise en page des écrans.
@immutable
class ResponsiveLayoutConfig {
  /// Largeur maximale par défaut du conteneur centré (1440 px).
  static const double defaultMaxWidth = 1440.0;

  /// Borne minimale autorisée pour [maxWidth].
  static const double minMaxWidth = 240.0;

  /// Borne maximale autorisée pour [maxWidth].
  static const double maxMaxWidth = 10000.0;

  const ResponsiveLayoutConfig({
    this.containerMode = PageContainerMode.fullPage,
    this.maxWidth = defaultMaxWidth,
    this.gutters = const ResponsiveGuttersConfig(),
    this.breakpoints = const ResponsiveBreakpointsConfig(),
  });

  /// Mode du conteneur de page (`fullPage` par défaut pour préserver l'existant).
  final PageContainerMode containerMode;

  /// Largeur maximale du conteneur lorsque [containerMode] vaut [PageContainerMode.constrained].
  final double maxWidth;

  /// Marges latérales (gutters) selon le breakpoint.
  final ResponsiveGuttersConfig gutters;

  /// Seuils des 4 breakpoints.
  final ResponsiveBreakpointsConfig breakpoints;

  /// Indique si cette configuration correspond exactement aux valeurs par défaut.
  bool get isDefault => this == const ResponsiveLayoutConfig();

  /// Valide la configuration complète.
  void validate() {
    if (!maxWidth.isFinite ||
        maxWidth < minMaxWidth ||
        maxWidth > maxMaxWidth) {
      throw ArgumentError(
        'La largeur maximale du conteneur doit être comprise entre '
        '$minMaxWidth et $maxMaxWidth px.',
      );
    }
    gutters.validate();
    breakpoints.validate();
  }

  /// Résout le breakpoint, la largeur maximale et le gutter pour une largeur [width].
  ResolvedPageLayout resolveForWidth(double width) {
    final breakpoint = breakpoints.resolveBreakpoint(width);
    if (containerMode == PageContainerMode.fullPage) {
      return ResolvedPageLayout(
        breakpoint: breakpoint,
        containerMode: PageContainerMode.fullPage,
        maxWidth: null,
        gutter: 0,
      );
    }
    return ResolvedPageLayout(
      breakpoint: breakpoint,
      containerMode: PageContainerMode.constrained,
      maxWidth: maxWidth,
      gutter: gutters.gutterFor(breakpoint),
    );
  }

  ResponsiveLayoutConfig copyWith({
    PageContainerMode? containerMode,
    double? maxWidth,
    ResponsiveGuttersConfig? gutters,
    ResponsiveBreakpointsConfig? breakpoints,
  }) => ResponsiveLayoutConfig(
    containerMode: containerMode ?? this.containerMode,
    maxWidth: maxWidth ?? this.maxWidth,
    gutters: gutters ?? this.gutters,
    breakpoints: breakpoints ?? this.breakpoints,
  );

  Map<String, Object?> toJson() => {
    'containerMode': containerMode.name,
    'maxWidth': JsonNumbers.round(maxWidth),
    'gutters': gutters.toJson(),
    'breakpoints': breakpoints.toJson(),
  };

  Map<String, Object?> toCompactJson() {
    final compactGutters = gutters.toCompactJson();
    final compactBreakpoints = breakpoints.toCompactJson();
    return {
      if (containerMode != PageContainerMode.fullPage)
        'containerMode': containerMode.name,
      if (maxWidth != defaultMaxWidth) 'maxWidth': JsonNumbers.round(maxWidth),
      if (compactGutters.isNotEmpty) 'gutters': compactGutters,
      if (compactBreakpoints.isNotEmpty) 'breakpoints': compactBreakpoints,
    };
  }

  factory ResponsiveLayoutConfig.fromJson(Object? value) {
    if (value == null) return const ResponsiveLayoutConfig();
    if (value is! Map) {
      throw const FormatException('Configuration responsive invalide.');
    }
    const known = {'containerMode', 'maxWidth', 'gutters', 'breakpoints'};
    if (value.keys.any((key) => !known.contains(key))) {
      throw const FormatException(
        'Clé inconnue dans la configuration responsive.',
      );
    }
    final containerMode = PageContainerMode.fromJson(value['containerMode']);
    final rawMaxWidth = value['maxWidth'];
    if (rawMaxWidth != null && (rawMaxWidth is! num || !rawMaxWidth.isFinite)) {
      throw const FormatException('Largeur maximale de conteneur invalide.');
    }
    final result = ResponsiveLayoutConfig(
      containerMode: containerMode,
      maxWidth: (rawMaxWidth as num?)?.toDouble() ?? defaultMaxWidth,
      gutters: ResponsiveGuttersConfig.fromJson(value['gutters']),
      breakpoints: ResponsiveBreakpointsConfig.fromJson(value['breakpoints']),
    );
    try {
      result.validate();
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
    return result;
  }

  /// Applique un patch partiel JSON sur cette configuration.
  ResponsiveLayoutConfig patchFromJson(Object? raw) {
    if (raw == null) return this;
    if (raw is! Map) {
      throw const FormatException('Patch de configuration responsive invalide.');
    }
    const known = {'containerMode', 'maxWidth', 'gutters', 'breakpoints'};
    if (raw.keys.any((key) => !known.contains(key))) {
      throw const FormatException(
        'Clé inconnue dans le patch de configuration responsive.',
      );
    }
    final nextMode = raw.containsKey('containerMode')
        ? PageContainerMode.fromJson(raw['containerMode'])
        : containerMode;
    double nextMaxWidth = maxWidth;
    if (raw.containsKey('maxWidth')) {
      final value = raw['maxWidth'];
      if (value == null) {
        nextMaxWidth = defaultMaxWidth;
      } else if (value is num && value.isFinite) {
        nextMaxWidth = value.toDouble();
      } else {
        throw const FormatException('Largeur maximale de conteneur invalide.');
      }
    }
    final nextGutters = raw.containsKey('gutters')
        ? (raw['gutters'] == null
              ? const ResponsiveGuttersConfig()
              : _patchGutters(gutters, raw['gutters']))
        : gutters;
    final nextBreakpoints = raw.containsKey('breakpoints')
        ? (raw['breakpoints'] == null
              ? const ResponsiveBreakpointsConfig()
              : _patchBreakpoints(breakpoints, raw['breakpoints']))
        : breakpoints;
    final result = ResponsiveLayoutConfig(
      containerMode: nextMode,
      maxWidth: nextMaxWidth,
      gutters: nextGutters,
      breakpoints: nextBreakpoints,
    );
    try {
      result.validate();
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
    return result;
  }

  static ResponsiveGuttersConfig _patchGutters(
    ResponsiveGuttersConfig current,
    Object? raw,
  ) {
    if (raw is! Map) {
      throw const FormatException('Patch de gutters invalide.');
    }
    final merged = <String, Object?>{
      ...current.toJson(),
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    return ResponsiveGuttersConfig.fromJson(merged);
  }

  static ResponsiveBreakpointsConfig _patchBreakpoints(
    ResponsiveBreakpointsConfig current,
    Object? raw,
  ) {
    if (raw is! Map) {
      throw const FormatException('Patch de breakpoints invalide.');
    }
    final merged = <String, Object?>{
      ...current.toJson(),
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    return ResponsiveBreakpointsConfig.fromJson(merged);
  }

  @override
  bool operator ==(Object other) =>
      other is ResponsiveLayoutConfig &&
      other.containerMode == containerMode &&
      other.maxWidth == maxWidth &&
      other.gutters == gutters &&
      other.breakpoints == breakpoints;

  @override
  int get hashCode =>
      Object.hash(containerMode, maxWidth, gutters, breakpoints);
}

/// Surcharge optionnelle par page de la configuration responsive globale.
///
/// Tous les champs sont optionnels : toute propriété laissée à `null` hérite
/// de la configuration globale [ResponsiveLayoutConfig].
@immutable
class ResponsiveLayoutOverride {
  const ResponsiveLayoutOverride({
    this.containerMode,
    this.maxWidth,
    this.mobileGutter,
    this.tabletGutter,
    this.desktopGutter,
    this.largeDesktopGutter,
  });

  /// Force le mode de conteneur (`fullPage` ou `constrained`), ou `null` pour hériter.
  final PageContainerMode? containerMode;

  /// Surcharge optionnelle de la largeur maximale du conteneur (px).
  final double? maxWidth;

  /// Surcharge optionnelle du gutter Mobile (px).
  final double? mobileGutter;

  /// Surcharge optionnelle du gutter Tablette (px).
  final double? tabletGutter;

  /// Surcharge optionnelle du gutter Desktop (px).
  final double? desktopGutter;

  /// Surcharge optionnelle du gutter Large Desktop (px).
  final double? largeDesktopGutter;

  /// Indique si aucune surcharge n'est définie.
  bool get isEmpty =>
      containerMode == null &&
      maxWidth == null &&
      mobileGutter == null &&
      tabletGutter == null &&
      desktopGutter == null &&
      largeDesktopGutter == null;

  /// Valide les valeurs définies dans la surcharge.
  void validate() {
    if (maxWidth != null &&
        (!maxWidth!.isFinite ||
            maxWidth! < ResponsiveLayoutConfig.minMaxWidth ||
            maxWidth! > ResponsiveLayoutConfig.maxMaxWidth)) {
      throw ArgumentError(
        'La largeur maximale de la page doit être comprise entre '
        '${ResponsiveLayoutConfig.minMaxWidth} et ${ResponsiveLayoutConfig.maxMaxWidth} px.',
      );
    }
    for (final (name, value) in [
      if (mobileGutter != null) ('mobileGutter', mobileGutter!),
      if (tabletGutter != null) ('tabletGutter', tabletGutter!),
      if (desktopGutter != null) ('desktopGutter', desktopGutter!),
      if (largeDesktopGutter != null)
        ('largeDesktopGutter', largeDesktopGutter!),
    ]) {
      if (!value.isFinite ||
          value < 0 ||
          value > ResponsiveGuttersConfig.maxGutter) {
        throw ArgumentError(
          'Le gutter "$name" doit être compris entre 0 et '
          '${ResponsiveGuttersConfig.maxGutter} px.',
        );
      }
    }
  }

  /// Fusionne cette surcharge sur la configuration globale [base].
  ResponsiveLayoutConfig applyOn(ResponsiveLayoutConfig base) => base.copyWith(
    containerMode: containerMode ?? base.containerMode,
    maxWidth: maxWidth ?? base.maxWidth,
    gutters: base.gutters.copyWith(
      mobile: mobileGutter ?? base.gutters.mobile,
      tablet: tabletGutter,
      desktop: desktopGutter ?? base.gutters.desktop,
      largeDesktop: largeDesktopGutter,
    ),
  );

  ResponsiveLayoutOverride copyWith({
    PageContainerMode? containerMode,
    bool clearContainerMode = false,
    double? maxWidth,
    bool clearMaxWidth = false,
    double? mobileGutter,
    bool clearMobileGutter = false,
    double? tabletGutter,
    bool clearTabletGutter = false,
    double? desktopGutter,
    bool clearDesktopGutter = false,
    double? largeDesktopGutter,
    bool clearLargeDesktopGutter = false,
  }) => ResponsiveLayoutOverride(
    containerMode: clearContainerMode
        ? null
        : (containerMode ?? this.containerMode),
    maxWidth: clearMaxWidth ? null : (maxWidth ?? this.maxWidth),
    mobileGutter: clearMobileGutter
        ? null
        : (mobileGutter ?? this.mobileGutter),
    tabletGutter: clearTabletGutter
        ? null
        : (tabletGutter ?? this.tabletGutter),
    desktopGutter: clearDesktopGutter
        ? null
        : (desktopGutter ?? this.desktopGutter),
    largeDesktopGutter: clearLargeDesktopGutter
        ? null
        : (largeDesktopGutter ?? this.largeDesktopGutter),
  );

  Map<String, Object?> toJson() => {
    if (containerMode != null) 'containerMode': containerMode!.name,
    if (maxWidth != null) 'maxWidth': JsonNumbers.round(maxWidth!),
    if (mobileGutter != null) 'mobileGutter': JsonNumbers.round(mobileGutter!),
    if (tabletGutter != null) 'tabletGutter': JsonNumbers.round(tabletGutter!),
    if (desktopGutter != null)
      'desktopGutter': JsonNumbers.round(desktopGutter!),
    if (largeDesktopGutter != null)
      'largeDesktopGutter': JsonNumbers.round(largeDesktopGutter!),
  };

  static ResponsiveLayoutOverride? fromJson(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Surcharge responsive de page invalide.');
    }
    const known = {
      'containerMode',
      'maxWidth',
      'mobileGutter',
      'tabletGutter',
      'desktopGutter',
      'largeDesktopGutter',
    };
    if (value.keys.any((key) => !known.contains(key))) {
      throw const FormatException(
        'Clé inconnue dans la surcharge responsive de page.',
      );
    }
    double? readOptional(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! num || !raw.isFinite) {
        throw FormatException('Valeur invalide pour "$key".');
      }
      return raw.toDouble();
    }

    final result = ResponsiveLayoutOverride(
      containerMode: value.containsKey('containerMode') &&
              value['containerMode'] != null
          ? PageContainerMode.fromJson(value['containerMode'])
          : null,
      maxWidth: readOptional('maxWidth'),
      mobileGutter: readOptional('mobileGutter'),
      tabletGutter: readOptional('tabletGutter'),
      desktopGutter: readOptional('desktopGutter'),
      largeDesktopGutter: readOptional('largeDesktopGutter'),
    );
    try {
      result.validate();
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
    return result.isEmpty ? null : result;
  }

  @override
  bool operator ==(Object other) =>
      other is ResponsiveLayoutOverride &&
      other.containerMode == containerMode &&
      other.maxWidth == maxWidth &&
      other.mobileGutter == mobileGutter &&
      other.tabletGutter == tabletGutter &&
      other.desktopGutter == desktopGutter &&
      other.largeDesktopGutter == largeDesktopGutter;

  @override
  int get hashCode => Object.hash(
    containerMode,
    maxWidth,
    mobileGutter,
    tabletGutter,
    desktopGutter,
    largeDesktopGutter,
  );
}
