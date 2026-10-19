import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../models/super_layout_config.dart';
import '../models/scaffold_page_config.dart';
import '../models/native_component_config.dart';
import '../models/super_text_config.dart';
import '../models/super_list_view_config.dart';
import '../models/editor_page_config.dart';
import 'appearance.dart';
import 'container_style.dart';

/// Reusable appearance preferences without an application-specific catalog.
@immutable
class DefaultAppearance extends Appearance {
  static const minRowHeight = 20.0;
  static const maxRowHeight = 100.0;
  static const minSpacing = 4.0;
  static const maxSpacing = 64.0;
  static const minScrollFadeExtent = 8.0;
  static const maxScrollFadeExtent = 100.0;

  DefaultAppearance({
    super.mode,
    super.accent,
    super.backgroundOpacity,
    super.windowOpacity,
    super.windowEffect,
    super.styles,
    super.layouts,
    super.scaffoldPages,
    super.nativeComponents,
    super.textComponents,
    super.listComponents,
    super.pageCatalog,
    this.cardHeight = 142,
    this.cardWidth = 180,
    this.rowHeight = 48,
    this.spacing = 12,
    this.fontSize = 12,
    this.iconSize = 49,
    this.scrollFadeEnabled = true,
    this.scrollFadeExtent = 28,
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
      copyWith(layouts: {...layouts, id: value});

  @override
  DefaultAppearance withTextComponent(String id, SuperTextConfig value) {
    value.validate();
    return copyWith(textComponents: {...textComponents, id: value});
  }

  @override
  DefaultAppearance withListComponent(String id, SuperListViewConfig value) {
    value.validate();
    return copyWith(listComponents: {...listComponents, id: value});
  }

  @override
  DefaultAppearance withPageCatalog(EditorPageCatalog value) =>
      copyWith(pageCatalog: value);

  @override
  DefaultAppearance resetLayouts() => copyWith(
    layouts: const {},
    scaffoldPages: const {},
    nativeComponents: const {},
    textComponents: const {},
    listComponents: const {},
    pageCatalog: const EditorPageCatalog.empty(),
  );

  @override
  DefaultAppearance copyWith({
    Map<String, ContainerStyle>? styles,
    Map<String, SuperLayoutConfig>? layouts,
    Map<String, ScaffoldPageConfig>? scaffoldPages,
    Map<String, NativeComponentConfig>? nativeComponents,
    Map<String, SuperTextConfig>? textComponents,
    Map<String, SuperListViewConfig>? listComponents,
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
  }) => DefaultAppearance(
    styles: {...styles ?? this.styles, 'background': ?backgroundStyle},
    layouts: layouts ?? this.layouts,
    scaffoldPages: scaffoldPages ?? this.scaffoldPages,
    nativeComponents: nativeComponents ?? this.nativeComponents,
    textComponents: textComponents ?? this.textComponents,
    listComponents: listComponents ?? this.listComponents,
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
