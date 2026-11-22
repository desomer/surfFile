/// Contrat de base [Appearance] de l'application (modèle immuable, sans widget).
///
/// Regroupe l'état global du thème (mode clair/sombre, couleur d'accent, opacités,
/// effet de fenêtre) et les dictionnaires plats par ID (`styles`, `components`,
/// `behaviors`, `usages`, `pageCatalog`, `repositories`).
library;

import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import 'theme_color.dart';

import '../models/a4_page_config.dart';
import '../models/component_config.dart';
import '../models/component_behavior.dart';
import '../models/component_usage.dart';
import '../models/super_layout_config.dart';
import '../models/scaffold_page_config.dart';
import '../models/native_component_config.dart';
import '../models/super_value_config.dart';
import '../models/super_action_config.dart';
import '../models/super_indicator_config.dart';
import '../models/super_separator_config.dart';
import '../models/super_list_view_config.dart';
import '../models/super_conditional_config.dart';
import '../models/super_tab_config.dart';
import '../models/super_table_config.dart';
import '../models/super_tree_view_config.dart';
import '../models/editor_page_config.dart';
import '../models/responsive_layout_config.dart';
import 'container_fill.dart';
import 'container_style.dart';
import 'neon_style.dart';

/// Application-independent theme, window, styles and layouts.
@immutable
class Appearance {
  /// Délai minimum (en ms) de temporisation anti-rebond globale des saisies liées.
  static const int minBindingDebounceMs = SuperValueConfig.minBindingDebounceMs;

  /// Délai maximum (en ms) de temporisation anti-rebond globale des saisies liées.
  static const int maxBindingDebounceMs = SuperValueConfig.maxBindingDebounceMs;

  /// Délai par défaut (en ms) avant enregistrement automatique des saisies liées.
  static const int defaultBindingDebounceMs =
      SuperValueConfig.defaultBindingDebounceMs;

  /// Pas recommandé (en ms) pour la molette de réglage du délai d'enregistrement.
  static const int bindingDebounceStepMs =
      SuperValueConfig.bindingDebounceStepMs;

  Appearance({
    this.mode = ThemeMode.light,
    this.accent = const Color(0xFF5268D9),
    this.backgroundOpacity = 1,
    this.windowOpacity = 1,
    this.windowEffect = WindowEffect.transparent,
    this.bindingDebounceMs = defaultBindingDebounceMs,
    this.bindingSaveOnBlurOnly = false,
    Map<String, ContainerStyle> styles = const {},
    Map<String, SuperLayoutConfig> layouts = const {},
    Map<String, ComponentConfig> components = const {},
    Map<String, List<ComponentBehavior>> behaviors = const {},
    Map<String, ComponentUsage> usages = const {},
    this.pageCatalog = const EditorPageCatalog.empty(),
    this.responsiveLayout = const ResponsiveLayoutConfig(),
  }) : styles = Map.unmodifiable(styles),
       components = Map.unmodifiable(_mergeComponents(components, layouts)),
       behaviors = Map.unmodifiable({
         for (final entry in behaviors.entries)
           entry.key: List<ComponentBehavior>.unmodifiable(entry.value),
       }),
       usages = Map.unmodifiable(usages) {
    _validateInvariants();
  }

  Appearance._frozen({
    required this.mode,
    required this.accent,
    required this.backgroundOpacity,
    required this.windowOpacity,
    required this.windowEffect,
    required this.bindingDebounceMs,
    required this.bindingSaveOnBlurOnly,
    required this.styles,
    required this.components,
    required this.behaviors,
    required this.usages,
    required this.pageCatalog,
    required this.responsiveLayout,
  }) {
    _validateInvariants();
  }

  void _validateInvariants() {
    if (accent is ThemeColor) {
      throw ArgumentError.value(
        accent,
        'accent',
        'Une couleur fixe est requise pour générer le thème.',
      );
    }
    if (bindingDebounceMs < minBindingDebounceMs ||
        bindingDebounceMs > maxBindingDebounceMs) {
      throw RangeError.range(
        bindingDebounceMs,
        minBindingDebounceMs,
        maxBindingDebounceMs,
        'bindingDebounceMs',
      );
    }
    responsiveLayout.validate();
  }

  static SuperLayoutConfig _freezeLayout(SuperLayoutConfig l) => l.copyWith(
    swaps: Set.unmodifiable(l.swaps),
    autoSides: Set.unmodifiable(l.autoSides),
    sideResizing: Map.unmodifiable(l.sideResizing),
    collapsedSides: Map.unmodifiable(l.collapsedSides),
    zoneAxes: Map.unmodifiable(l.zoneAxes),
    slotTypes: Map.unmodifiable(l.slotTypes),
    slotLabels: Map.unmodifiable(l.slotLabels),
    grid: l.grid?.copyWith(items: Map.unmodifiable(l.grid!.items)),
    slotPreferredSizes: Map.unmodifiable(l.slotPreferredSizes),
    slotSizeConstraints: Map.unmodifiable(l.slotSizeConstraints),
    placements: Map.unmodifiable({
      for (final placement in l.placements.entries)
        placement.key: List<String>.unmodifiable(placement.value),
    }),
  );

  static ComponentConfig _freezeComponent(ComponentConfig value) =>
      switch (value) {
        final SuperLayoutConfig l => _freezeLayout(l),
        final SuperListViewConfig list => list.copyWith(
          template: _freezeLayout(list.template),
        ),
        final other => other,
      };

  static Map<String, ComponentConfig> _mergeComponents(
    Map<String, ComponentConfig> components,
    Map<String, SuperLayoutConfig> layouts,
  ) {
    final result = <String, ComponentConfig>{
      for (final entry in components.entries)
        entry.key: _freezeComponent(entry.value),
    };
    for (final entry in layouts.entries) {
      final frozen = _freezeLayout(entry.value);
      final existing = result[entry.key];
      if (existing is SuperListViewConfig) {
        result[entry.key] = existing.copyWith(template: frozen);
      } else {
        result[entry.key] = frozen;
      }
    }
    return result;
  }

  final ThemeMode mode;
  final Color accent;
  final double backgroundOpacity;
  final double windowOpacity;
  final WindowEffect windowEffect;

  /// Délai anti-rebond global (en ms, `100..2000`) avant sauvegarde automatique
  /// d'une saisie liée.
  final int bindingDebounceMs;

  /// Indique si les saisies liées ne sont enregistrées qu'à la perte de focus.
  final bool bindingSaveOnBlurOnly;
  final Map<String, ContainerStyle> styles;
  final Map<String, ComponentConfig> components;
  final Map<String, List<ComponentBehavior>> behaviors;

  /// Usages déclarés des composants, indexés par identifiant d'instance.
  final Map<String, ComponentUsage> usages;
  final EditorPageCatalog pageCatalog;

  /// Configuration responsive globale (mode conteneur, max-width, gutters, breakpoints).
  final ResponsiveLayoutConfig responsiveLayout;

  /// Résout la configuration responsive effective pour la page [pageId].
  ResponsiveLayoutConfig effectiveResponsiveLayoutForPage(String pageId) {
    for (final page in pageCatalog.pages) {
      if (page.id == pageId) {
        return page.layoutOverride?.applyOn(responsiveLayout) ??
            responsiveLayout;
      }
    }
    return responsiveLayout;
  }

  /// Usage déclaré pour l'instance [id], ou `null` s'il n'est pas défini.
  ComponentUsage? usageFor(String id) => usages[id];

  /// Définit l'usage de l'instance [id] ; `null` le retire.
  Appearance withUsage(String id, ComponentUsage? usage) {
    usage?.validate();
    if (usages[id] == usage) return this;
    final next = Map<String, ComponentUsage>.from(usages);
    if (usage == null) {
      next.remove(id);
    } else {
      next[id] = usage;
    }
    return Appearance._frozen(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      bindingDebounceMs: bindingDebounceMs,
      bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
      styles: styles,
      components: components,
      behaviors: behaviors,
      usages: Map.unmodifiable(next),
      pageCatalog: pageCatalog,
      responsiveLayout: responsiveLayout,
    );
  }

  List<ComponentBehavior> behaviorsFor(String id) => behaviors[id] ?? const [];

  Appearance withBehaviors(String id, List<ComponentBehavior> list) {
    final next = Map<String, List<ComponentBehavior>>.from(behaviors);
    if (list.isEmpty) {
      if (!behaviors.containsKey(id)) return this;
      next.remove(id);
    } else {
      next[id] = List<ComponentBehavior>.unmodifiable(list);
    }
    return Appearance._frozen(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      bindingDebounceMs: bindingDebounceMs,
      bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
      styles: styles,
      components: components,
      behaviors: Map.unmodifiable(next),
      usages: usages,
      pageCatalog: pageCatalog,
      responsiveLayout: responsiveLayout,
    );
  }

  Appearance withAddedBehavior(String id, ComponentBehavior behavior) {
    final current = behaviorsFor(id);
    return withBehaviors(id, [...current, behavior]);
  }

  /// Remplace le comportement de même identifiant sans déplacer ses voisins.
  /// Ne recrée pas un comportement supprimé pendant l'édition.
  Appearance withReplacedBehavior(String componentId, ComponentBehavior value) {
    final current = behaviorsFor(componentId);
    final index = current.indexWhere((item) => item.id == value.id);
    if (index < 0 || current[index] == value) return this;
    return withBehaviors(componentId, [...current]..[index] = value);
  }

  Appearance withRemovedBehavior(String componentId, String behaviorId) {
    final current = behaviorsFor(componentId);
    return withBehaviors(
      componentId,
      current.where((b) => b.id != behaviorId).toList(),
    );
  }

  Map<String, SuperLayoutConfig> get layouts => Map.unmodifiable({
    for (final entry in components.entries)
      if (entry.value case final SuperLayoutConfig l)
        entry.key: l
      else if (entry.value case final SuperListViewConfig list)
        entry.key: list.template,
  });

  T? tryComponent<T extends ComponentConfig>(String id) =>
      switch (components[id]) {
        final T value => value,
        _ => null,
      };

  T component<T extends ComponentConfig>(String id, {required T fallback}) =>
      tryComponent<T>(id) ?? fallback;

  Map<String, T> componentsOfType<T extends ComponentConfig>() =>
      Map.unmodifiable({
        for (final entry in components.entries)
          if (entry.value is T) entry.key: entry.value as T,
      });

  Appearance withComponent(String id, ComponentConfig? value) {
    if (value == null) {
      if (!components.containsKey(id)) return this;
      final next = {...components}..remove(id);
      return Appearance._frozen(
        mode: mode,
        accent: accent,
        backgroundOpacity: backgroundOpacity,
        windowOpacity: windowOpacity,
        windowEffect: windowEffect,
        bindingDebounceMs: bindingDebounceMs,
        bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
        styles: styles,
        components: Map.unmodifiable(next),
        behaviors: behaviors,
        usages: usages,
        pageCatalog: pageCatalog,
        responsiveLayout: responsiveLayout,
      );
    }
    value.validate();
    final frozen = _freezeComponent(value);
    if (components[id] == frozen) return this;
    final next = {...components, id: frozen};
    return Appearance._frozen(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      bindingDebounceMs: bindingDebounceMs,
      bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
      styles: styles,
      components: Map.unmodifiable(next),
      behaviors: behaviors,
      usages: usages,
      pageCatalog: pageCatalog,
      responsiveLayout: responsiveLayout,
    );
  }

  SuperValueConfig valueComponent(
    String id, {
    SuperValueConfig fallback = const SuperValueConfig(),
  }) => component<SuperValueConfig>(id, fallback: fallback);

  Appearance withValueComponent(String id, SuperValueConfig value) =>
      withComponent(id, value);

  SuperActionConfig actionComponent(
    String id, {
    SuperActionConfig fallback = const SuperActionConfig(),
  }) => component<SuperActionConfig>(id, fallback: fallback);

  Appearance withActionComponent(String id, SuperActionConfig value) =>
      withComponent(id, value);

  SuperIndicatorConfig indicatorComponent(
    String id, {
    SuperIndicatorConfig fallback = const SuperIndicatorConfig(),
  }) => component<SuperIndicatorConfig>(id, fallback: fallback);

  Appearance withIndicatorComponent(String id, SuperIndicatorConfig value) =>
      withComponent(id, value);

  SuperSeparatorConfig separatorComponent(
    String id, {
    SuperSeparatorConfig fallback = const SuperSeparatorConfig(),
  }) => component<SuperSeparatorConfig>(id, fallback: fallback);

  Appearance withSeparatorComponent(String id, SuperSeparatorConfig value) =>
      withComponent(id, value);

  SuperTabConfig tabComponent(String id, {SuperTabConfig? fallback}) =>
      component<SuperTabConfig>(id, fallback: fallback ?? SuperTabConfig());

  Appearance withTabComponent(String id, SuperTabConfig value) =>
      withComponent(id, value);

  SuperConditionalConfig conditionalComponent(
    String id, {
    SuperConditionalConfig? fallback,
  }) => component<SuperConditionalConfig>(
    id,
    fallback: fallback ?? SuperConditionalConfig(),
  );

  Appearance withConditionalComponent(
    String id,
    SuperConditionalConfig value,
  ) => withComponent(id, value);

  SuperTreeViewConfig treeViewComponent(
    String id, {
    SuperTreeViewConfig? fallback,
  }) => component<SuperTreeViewConfig>(
    id,
    fallback: fallback ?? SuperTreeViewConfig(),
  );

  Appearance withTreeViewComponent(String id, SuperTreeViewConfig value) =>
      withComponent(id, value);

  SuperTableConfig tableComponent(String id, {SuperTableConfig? fallback}) =>
      component<SuperTableConfig>(id, fallback: fallback ?? SuperTableConfig());

  Appearance withTableComponent(String id, SuperTableConfig value) =>
      withComponent(id, value);

  SuperListViewConfig listComponent(
    String id, {
    SuperListViewConfig fallback = const SuperListViewConfig(),
  }) => component<SuperListViewConfig>(id, fallback: fallback);

  Appearance withListComponent(String id, SuperListViewConfig value) {
    final existing = components[id];
    final merged =
        value.template == const SuperLayoutConfig() &&
            existing is SuperLayoutConfig
        ? value.copyWith(template: existing)
        : value.template == const SuperLayoutConfig() &&
              existing is SuperListViewConfig
        ? value.copyWith(template: existing.template)
        : value;
    return withComponent(id, merged);
  }

  NativeComponentConfig nativeComponent(
    String id, {
    NativeComponentConfig? fallback,
  }) => switch (components[id]) {
    final NativeComponentConfig n => n,
    final ScaffoldPageConfig s => s.native,
    _ => fallback ?? NativeComponentConfig(),
  };

  ContainerStyle style(
    String id, {
    ContainerStyle fallback = const ContainerStyle(),
  }) => styles[id] ?? fallback;
  SuperLayoutConfig layout(
    String id, {
    SuperLayoutConfig fallback = const SuperLayoutConfig(),
  }) => switch (components[id]) {
    final SuperLayoutConfig l => l,
    final SuperListViewConfig list => list.template,
    _ => fallback,
  };
  ScaffoldPageConfig scaffoldPage(String id, {ScaffoldPageConfig? fallback}) =>
      switch (components[id]) {
        final ScaffoldPageConfig s => s,
        final NativeComponentConfig n => ScaffoldPageConfig.fromNative(n),
        _ => fallback ?? ScaffoldPageConfig(),
      };
  A4PageConfig a4Page(String id, {A4PageConfig? fallback}) =>
      component<A4PageConfig>(
        id,
        fallback: fallback ?? A4PageConfig.initialForPage(id),
      );
  Appearance withA4Page(String id, A4PageConfig value) =>
      withComponent(id, value);
  ContainerStyle get backgroundStyle => style('background');

  /// Resolves the optional variant [id] (a selected state, for instance) of
  /// the [standardId] style. Without an override, the variant keeps the shape
  /// and interaction settings of the standard style, plus its extended look
  /// when [inheritLook] is set, but not its colors. The neon is inherited
  /// unless the override defines its own.
  ContainerStyle variantStyle(
    String id,
    String standardId, {
    bool inheritLook = false,
  }) {
    final standard = style(standardId);
    final override = styles[id];
    final shape = ContainerStyle(
      radius: standard.radius,
      borderWidth: standard.borderWidth,
      elevation: standard.elevation,
      shadowOpacity: standard.shadowOpacity,
      padding: standard.padding,
      margin: standard.margin,
      interactionEffect: standard.interactionEffect,
      hoverEffect: standard.hoverEffect,
      hoverTint: standard.hoverTint,
      hoverColor: standard.hoverColor,
    );
    return (override ?? (inheritLook ? shape.withLookOf(standard) : shape))
        .copyWith(neon: override?.neon ?? standard.neon ?? const NeonStyle());
  }

  Appearance copyWith({
    ThemeMode? mode,
    Color? accent,
    double? backgroundOpacity,
    double? windowOpacity,
    WindowEffect? windowEffect,
    int? bindingDebounceMs,
    bool? bindingSaveOnBlurOnly,
    ContainerStyle? backgroundStyle,
    Map<String, ContainerStyle>? styles,
    Map<String, SuperLayoutConfig>? layouts,
    Map<String, ComponentConfig>? components,
    Map<String, List<ComponentBehavior>>? behaviors,
    Map<String, ComponentUsage>? usages,
    EditorPageCatalog? pageCatalog,
    ResponsiveLayoutConfig? responsiveLayout,
  }) {
    final nextStyles = backgroundStyle == null
        ? (styles == null ? this.styles : Map<String, ContainerStyle>.unmodifiable(styles))
        : Map<String, ContainerStyle>.unmodifiable({
            ...(styles ?? this.styles),
            'background': backgroundStyle,
          });
    final Map<String, ComponentConfig> nextComponents;
    if (components == null && layouts == null) {
      nextComponents = this.components;
    } else {
      final baseComponents =
          components ??
          {
            for (final entry in this.components.entries)
              if (entry.value is! SuperLayoutConfig) entry.key: entry.value,
          };
      nextComponents = Map.unmodifiable(
        _mergeComponents(baseComponents, layouts ?? const {}),
      );
    }
    final nextBehaviors = behaviors == null
        ? this.behaviors
        : Map<String, List<ComponentBehavior>>.unmodifiable({
            for (final entry in behaviors.entries)
              entry.key: List<ComponentBehavior>.unmodifiable(entry.value),
          });
    final nextUsages = usages == null
        ? this.usages
        : Map<String, ComponentUsage>.unmodifiable(usages);
    return Appearance._frozen(
      mode: mode ?? this.mode,
      accent: accent ?? this.accent,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      windowOpacity: windowOpacity ?? this.windowOpacity,
      windowEffect: windowEffect ?? this.windowEffect,
      bindingDebounceMs: bindingDebounceMs ?? this.bindingDebounceMs,
      bindingSaveOnBlurOnly:
          bindingSaveOnBlurOnly ?? this.bindingSaveOnBlurOnly,
      styles: nextStyles,
      components: nextComponents,
      behaviors: nextBehaviors,
      usages: nextUsages,
      pageCatalog: pageCatalog ?? this.pageCatalog,
      responsiveLayout: responsiveLayout ?? this.responsiveLayout,
    );
  }

  Appearance withStyle(String id, ContainerStyle? value) {
    if (value == null) {
      if (!styles.containsKey(id)) return this;
      final next = {...styles}..remove(id);
      return Appearance._frozen(
        mode: mode,
        accent: accent,
        backgroundOpacity: backgroundOpacity,
        windowOpacity: windowOpacity,
        windowEffect: windowEffect,
        bindingDebounceMs: bindingDebounceMs,
        bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
        styles: Map.unmodifiable(next),
        components: components,
        behaviors: behaviors,
        usages: usages,
        pageCatalog: pageCatalog,
        responsiveLayout: responsiveLayout,
      );
    }
    if (styles[id] == value) return this;
    final next = {...styles, id: value};
    return Appearance._frozen(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      bindingDebounceMs: bindingDebounceMs,
      bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
      styles: Map.unmodifiable(next),
      components: components,
      behaviors: behaviors,
      usages: usages,
      pageCatalog: pageCatalog,
      responsiveLayout: responsiveLayout,
    );
  }

  Appearance withLayout(String id, SuperLayoutConfig value) =>
      switch (components[id]) {
        final SuperListViewConfig list => withComponent(
          id,
          list.copyWith(template: value),
        ),
        _ => withComponent(id, value),
      };
  Appearance withPageCatalog(EditorPageCatalog value) =>
      copyWith(pageCatalog: value);
  Appearance withResponsiveLayout(ResponsiveLayoutConfig value) =>
      copyWith(responsiveLayout: value);
  Appearance withScaffoldPage(String id, ScaffoldPageConfig value) =>
      withNativeComponent(id, value.native);
  Appearance withNativeComponent(String id, NativeComponentConfig value) =>
      withComponent(id, value);
  Appearance resetLayouts() => copyWith(
    components: const {},
    usages: const {},
    pageCatalog: const EditorPageCatalog.empty(),
  );

  /// Nombre de liaisons (`JsonTextBinding`) de l'apparence qui référencent [repositoryId].
  int countRepositoryBindings(String repositoryId) {
    if (repositoryId.isEmpty) return 0;
    var count = 0;
    void visit(Object? node) {
      if (node is Map) {
        if (node['repositoryId'] == repositoryId && node['path'] is String) {
          count++;
        }
        for (final value in node.values) {
          visit(value);
        }
      } else if (node is Iterable) {
        for (final item in node) {
          visit(item);
        }
      }
    }

    for (final style in styles.values) {
      visit(style.toJson());
    }
    for (final component in components.values) {
      visit(component.toTypedJson());
    }
    for (final list in behaviors.values) {
      for (final behavior in list) {
        visit(behavior.toJson());
      }
    }
    return count;
  }

  /// Indique si au moins une liaison de l'apparence référence [repositoryId].
  bool usesRepository(String repositoryId) =>
      countRepositoryBindings(repositoryId) > 0;

  /// Indique si un comportement de l'apparence lance le provider [providerId].
  bool usesProvider(String providerId) => behaviors.values.any(
    (list) => list.any((behavior) {
      final action = behavior.action;
      return action is SearchProviderAction && action.providerId == providerId;
    }),
  );

  /// Indique si un comportement de l'apparence lance une commande de la
  /// datasource [datasourceId].
  bool usesDatasource(String datasourceId) => behaviors.values.any(
    (list) => list.any((behavior) {
      final action = behavior.action;
      return action is DatasourceAction && action.datasourceId == datasourceId;
    }),
  );

  ThemeData theme(Brightness brightness) {
    final seedScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    final resolvedBackground = backgroundStyle.resolveThemeColors(seedScheme);
    final defaultSurface = brightness == Brightness.dark
        ? const Color(0xFF171A23)
        : const Color(0xFFF8F9FC);
    final surface = resolvedBackground.fill.type != FillType.solid
        ? Color.lerp(
            resolvedBackground.fill.start,
            resolvedBackground.fill.end,
            .5,
          )!
        : (resolvedBackground.color ?? defaultSurface);
    final usesThemeColor =
        backgroundStyle.color is ThemeColor ||
        (backgroundStyle.fill.type != FillType.solid &&
            (backgroundStyle.fill.start is ThemeColor ||
                backgroundStyle.fill.end is ThemeColor));
    final effectiveBrightness = usesThemeColor
        ? brightness
        : ThemeData.estimateBrightnessForColor(surface);
    final generated = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: effectiveBrightness,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: generated.copyWith(
        primary: generated.primary.withValues(alpha: accent.a),
        onSurface: foreground(surface),
      ),
      scaffoldBackgroundColor:
          backgroundStyle.fill.type == FillType.solid &&
              !backgroundStyle.hasImage
          ? surface.withValues(alpha: surface.a * backgroundOpacity)
          : Colors.transparent,
      fontFamily: 'Segoe UI',
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      // Les tooltips (OverlayPortal) réorganisent l'arbre sémantique et font
      // planter le pont AXTree Windows (flutter/flutter#182444).
      tooltipTheme: const TooltipThemeData(excludeFromSemantics: true),
    );
  }

  static Color foreground(Color background) =>
      ContainerStyle.foregroundFor(background);
}
