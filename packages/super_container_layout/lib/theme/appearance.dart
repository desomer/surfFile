import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../models/component_config.dart';
import '../models/component_behavior.dart';
import '../models/super_layout_config.dart';
import '../models/scaffold_page_config.dart';
import '../models/native_component_config.dart';
import '../models/super_value_config.dart';
import '../models/super_action_config.dart';
import '../models/super_list_view_config.dart';
import '../models/super_tab_config.dart';
import '../models/super_table_config.dart';
import '../models/super_tree_view_config.dart';
import '../models/super_chart_config.dart';
import '../models/editor_page_config.dart';
import 'container_fill.dart';
import 'container_style.dart';
import 'neon_style.dart';

/// Application-independent theme, window, styles and layouts.
@immutable
class Appearance {
  Appearance({
    this.mode = ThemeMode.light,
    this.accent = const Color(0xFF5268D9),
    this.backgroundOpacity = 1,
    this.windowOpacity = 1,
    this.windowEffect = WindowEffect.transparent,
    Map<String, ContainerStyle> styles = const {},
    Map<String, SuperLayoutConfig> layouts = const {},
    Map<String, ComponentConfig> components = const {},
    Map<String, List<ComponentBehavior>> behaviors = const {},
    this.pageCatalog = const EditorPageCatalog.empty(),
  }) : styles = Map.unmodifiable(styles),
       components = Map.unmodifiable(_mergeComponents(components, layouts)),
       behaviors = Map.unmodifiable({
         for (final entry in behaviors.entries)
           entry.key: List<ComponentBehavior>.unmodifiable(entry.value),
       });

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

  static Map<String, ComponentConfig> _mergeComponents(
    Map<String, ComponentConfig> components,
    Map<String, SuperLayoutConfig> layouts,
  ) {
    final result = <String, ComponentConfig>{
      for (final entry in components.entries)
        entry.key: switch (entry.value) {
          final SuperLayoutConfig l => _freezeLayout(l),
          final SuperListViewConfig list => list.copyWith(
            template: _freezeLayout(list.template),
          ),
          final other => other,
        },
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
  final Map<String, ContainerStyle> styles;
  final Map<String, ComponentConfig> components;
  final Map<String, List<ComponentBehavior>> behaviors;
  final EditorPageCatalog pageCatalog;

  List<ComponentBehavior> behaviorsFor(String id) =>
      behaviors[id] ?? const [];

  Appearance withBehaviors(String id, List<ComponentBehavior> list) {
    final next = Map<String, List<ComponentBehavior>>.from(behaviors);
    if (list.isEmpty) {
      next.remove(id);
    } else {
      next[id] = List<ComponentBehavior>.unmodifiable(list);
    }
    return copyWith(behaviors: next);
  }

  Appearance withAddedBehavior(String id, ComponentBehavior behavior) {
    final current = behaviorsFor(id);
    return withBehaviors(id, [...current, behavior]);
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
    final next = {...components};
    if (value == null) {
      next.remove(id);
    } else {
      value.validate();
      next[id] = value;
    }
    return copyWith(components: next);
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

  SuperTabConfig tabComponent(
    String id, {
    SuperTabConfig? fallback,
  }) => component<SuperTabConfig>(id, fallback: fallback ?? SuperTabConfig());

  Appearance withTabComponent(String id, SuperTabConfig value) =>
      withComponent(id, value);

  SuperChartConfig chartComponent(
    String id, {
    SuperChartConfig fallback = const SuperChartConfig(),
  }) => component<SuperChartConfig>(id, fallback: fallback);

  Appearance withChartComponent(String id, SuperChartConfig value) =>
      withComponent(id, value);

  SuperTreeViewConfig treeViewComponent(
    String id, {
    SuperTreeViewConfig? fallback,
  }) => component<SuperTreeViewConfig>(
    id,
    fallback: fallback ?? SuperTreeViewConfig(),
  );

  Appearance withTreeViewComponent(String id, SuperTreeViewConfig value) =>
      withComponent(id, value);

  SuperTableConfig tableComponent(
    String id, {
    SuperTableConfig? fallback,
  }) => component<SuperTableConfig>(
    id,
    fallback: fallback ?? SuperTableConfig(),
  );

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
    ContainerStyle? backgroundStyle,
    Map<String, ContainerStyle>? styles,
    Map<String, SuperLayoutConfig>? layouts,
    Map<String, ComponentConfig>? components,
    Map<String, List<ComponentBehavior>>? behaviors,
    EditorPageCatalog? pageCatalog,
  }) {
    final baseComponents =
        components ??
        (layouts != null
            ? {
                for (final entry in this.components.entries)
                  if (entry.value is! SuperLayoutConfig) entry.key: entry.value,
              }
            : this.components);
    return Appearance(
      mode: mode ?? this.mode,
      accent: accent ?? this.accent,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      windowOpacity: windowOpacity ?? this.windowOpacity,
      windowEffect: windowEffect ?? this.windowEffect,
      styles: backgroundStyle == null
          ? styles ?? this.styles
          : {...styles ?? this.styles, 'background': backgroundStyle},
      layouts: layouts ?? const {},
      components: baseComponents,
      behaviors: behaviors ?? this.behaviors,
      pageCatalog: pageCatalog ?? this.pageCatalog,
    );
  }

  Appearance withStyle(String id, ContainerStyle? value) {
    final next = {...styles};
    if (value == null) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    return copyWith(styles: next);
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
  Appearance withScaffoldPage(String id, ScaffoldPageConfig value) =>
      withNativeComponent(id, value.native);
  Appearance withNativeComponent(String id, NativeComponentConfig value) =>
      withComponent(id, value);
  Appearance resetLayouts() => copyWith(
    components: const {},
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
    return count;
  }

  /// Indique si au moins une liaison de l'apparence référence [repositoryId].
  bool usesRepository(String repositoryId) =>
      countRepositoryBindings(repositoryId) > 0;

  ThemeData theme(Brightness brightness) {
    final surface =
        backgroundStyle.color ??
        (brightness == Brightness.dark
            ? const Color(0xFF171A23)
            : const Color(0xFFF8F9FC));
    final generated = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
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

class AppearanceScope extends InheritedNotifier<ValueNotifier<Appearance>> {
  const AppearanceScope({
    required ValueNotifier<Appearance> controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static ValueNotifier<Appearance>? controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
  static Appearance of(BuildContext context) =>
      controllerOf(context)?.value ?? Appearance();
}
