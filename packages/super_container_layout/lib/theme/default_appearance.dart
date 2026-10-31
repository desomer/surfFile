import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../models/component_behavior.dart';
import '../models/component_config.dart';
import '../models/super_layout_config.dart';
import '../models/scaffold_page_config.dart';
import '../models/native_component_config.dart';
import '../models/super_value_config.dart';
import '../models/super_action_config.dart';
import '../models/super_list_view_config.dart';
import '../models/editor_page_config.dart';
import 'appearance.dart';
import 'container_fill.dart';
import 'container_style.dart';

/// Reusable appearance preferences without an application-specific catalog.
@immutable
class DefaultAppearance extends Appearance {
  static const minCardHeight = 142.0;
  static const maxCardHeight = 300.0;
  static const minCardWidth = 180.0;
  static const maxCardWidth = 360.0;
  static const minRowHeight = 20.0;
  static const maxRowHeight = 100.0;
  static const minSpacing = 4.0;
  static const maxSpacing = 64.0;
  static const minFontSize = 10.0;
  static const maxFontSize = 16.0;
  static const minIconSize = 24.0;
  static const maxIconSize = 64.0;
  static const minScrollFadeExtent = 8.0;
  static const maxScrollFadeExtent = 100.0;

  static const defaultCardHeight = 142.0;
  static const defaultCardWidth = 180.0;
  static const defaultRowHeight = 48.0;
  static const defaultSpacing = 12.0;
  static const defaultFontSize = 12.0;
  static const defaultIconSize = 49.0;
  static const defaultScrollFadeEnabled = true;
  static const defaultScrollFadeExtent = 28.0;

  DefaultAppearance({
    super.mode,
    super.accent,
    super.backgroundOpacity,
    super.windowOpacity,
    super.windowEffect,
    super.styles,
    super.layouts,
    super.components,
    super.behaviors,
    super.pageCatalog,
    this.cardHeight = defaultCardHeight,
    this.cardWidth = defaultCardWidth,
    this.rowHeight = defaultRowHeight,
    this.spacing = defaultSpacing,
    this.fontSize = defaultFontSize,
    this.iconSize = defaultIconSize,
    this.scrollFadeEnabled = defaultScrollFadeEnabled,
    this.scrollFadeExtent = defaultScrollFadeExtent,
  });

  final double cardHeight;
  final double cardWidth;
  final double rowHeight;
  final double spacing;
  final double fontSize;
  final double iconSize;
  final bool scrollFadeEnabled;
  final double scrollFadeExtent;

  @override
  DefaultAppearance withStyle(String id, ContainerStyle? value) {
    final next = {...styles};
    if (value == null) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    return copyWith(styles: next);
  }

  @override
  DefaultAppearance withLayout(String id, SuperLayoutConfig value) =>
      switch (components[id]) {
        final SuperListViewConfig list => withComponent(
          id,
          list.copyWith(template: value),
        ),
        _ => withComponent(id, value),
      };

  @override
  DefaultAppearance withComponent(String id, ComponentConfig? value) {
    final next = {...components};
    if (value == null) {
      next.remove(id);
    } else {
      value.validate();
      next[id] = value;
    }
    return copyWith(components: next);
  }

  @override
  DefaultAppearance withValueComponent(String id, SuperValueConfig value) =>
      withComponent(id, value);

  @override
  DefaultAppearance withActionComponent(String id, SuperActionConfig value) =>
      withComponent(id, value);

  @override
  DefaultAppearance withListComponent(String id, SuperListViewConfig value) {
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

  @override
  DefaultAppearance withNativeComponent(
    String id,
    NativeComponentConfig value,
  ) => withComponent(id, value);

  @override
  DefaultAppearance withScaffoldPage(String id, ScaffoldPageConfig value) =>
      withNativeComponent(id, value.native);

  @override
  DefaultAppearance withPageCatalog(EditorPageCatalog value) =>
      copyWith(pageCatalog: value);

  @override
  DefaultAppearance resetLayouts() => copyWith(
    components: const {},
    pageCatalog: const EditorPageCatalog.empty(),
  );

  @override
  DefaultAppearance copyWith({
    Map<String, ContainerStyle>? styles,
    Map<String, SuperLayoutConfig>? layouts,
    Map<String, ComponentConfig>? components,
    Map<String, List<ComponentBehavior>>? behaviors,
    EditorPageCatalog? pageCatalog,
    ThemeMode? mode,
    Color? accent,
    double? backgroundOpacity,
    double? windowOpacity,
    WindowEffect? windowEffect,
    ContainerStyle? backgroundStyle,
    double? cardHeight,
    double? cardWidth,
    double? rowHeight,
    double? spacing,
    double? fontSize,
    double? iconSize,
    bool? scrollFadeEnabled,
    double? scrollFadeExtent,
  }) {
    final baseComponents =
        components ??
        (layouts != null
            ? {
                for (final entry in this.components.entries)
                  if (entry.value is! SuperLayoutConfig) entry.key: entry.value,
              }
            : this.components);
    return DefaultAppearance(
      styles: {...styles ?? this.styles, 'background': ?backgroundStyle},
      layouts: layouts ?? const {},
      components: baseComponents,
      behaviors: behaviors ?? this.behaviors,
      pageCatalog: pageCatalog ?? this.pageCatalog,
      mode: mode ?? this.mode,
      accent: accent ?? this.accent,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      windowOpacity: windowOpacity ?? this.windowOpacity,
      windowEffect: windowEffect ?? this.windowEffect,
      cardHeight: cardHeight ?? this.cardHeight,
      cardWidth: cardWidth ?? this.cardWidth,
      rowHeight: rowHeight ?? this.rowHeight,
      spacing: spacing ?? this.spacing,
      fontSize: fontSize ?? this.fontSize,
      iconSize: iconSize ?? this.iconSize,
      scrollFadeEnabled: scrollFadeEnabled ?? this.scrollFadeEnabled,
      scrollFadeExtent: scrollFadeExtent ?? this.scrollFadeExtent,
    );
  }
}

/// Automatic solid color of unselected cards whose style has none.
Color defaultCardColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.brightness == Brightness.dark
      ? scheme.surfaceContainerLow
      : Colors.white;
}

/// Solid color of a card drawn with the resolved [style].
Color cardColor(
  BuildContext context,
  ContainerStyle style, {
  bool selected = false,
}) {
  if (style.fill.type != FillType.solid) {
    return Color.lerp(style.fill.start, style.fill.end, .5)!;
  }
  return style.color ??
      (selected
          ? Theme.of(context).colorScheme.primaryContainer
          : defaultCardColor(context));
}

Color foregroundForCard(Color background) =>
    ContainerStyle.foregroundFor(background);

