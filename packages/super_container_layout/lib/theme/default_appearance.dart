import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../models/super_layout_config.dart';
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
  DefaultAppearance resetLayouts() => copyWith(layouts: const {});

  @override
  DefaultAppearance copyWith({
    Map<String, ContainerStyle>? styles,
    Map<String, SuperLayoutConfig>? layouts,
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
