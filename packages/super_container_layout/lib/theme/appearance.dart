import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../models/super_layout_config.dart';
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
  }) : styles = Map.unmodifiable(styles), layouts = Map.unmodifiable({
    for (final entry in layouts.entries)
      entry.key: entry.value.copyWith(
        swaps: Set.unmodifiable(entry.value.swaps),
        autoSides: Set.unmodifiable(entry.value.autoSides),
        placements: Map.unmodifiable({
          for (final placement in entry.value.placements.entries)
            placement.key: List<String>.unmodifiable(placement.value),
        }),
      ),
  });

  final ThemeMode mode;
  final Color accent;
  final double backgroundOpacity;
  final double windowOpacity;
  final WindowEffect windowEffect;
  final Map<String, ContainerStyle> styles;
  final Map<String, SuperLayoutConfig> layouts;

  ContainerStyle style(String id, {ContainerStyle fallback = const ContainerStyle()}) =>
      styles[id] ?? fallback;
  SuperLayoutConfig layout(String id, {SuperLayoutConfig fallback = const SuperLayoutConfig()}) =>
      layouts[id] ?? fallback;
  ContainerStyle get backgroundStyle => style('background');

  /// Resolves the optional variant [id] (a selected state, for instance) of
  /// the [standardId] style. Without an override, the variant keeps the shape
  /// and interaction settings of the standard style, plus its extended look
  /// when [inheritLook] is set, but not its colors. The neon is inherited
  /// unless the override defines its own.
  ContainerStyle variantStyle(String id, String standardId, {bool inheritLook = false}) {
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
  }) => Appearance(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    windowOpacity: windowOpacity ?? this.windowOpacity,
    windowEffect: windowEffect ?? this.windowEffect,
    styles: backgroundStyle == null ? styles ?? this.styles : {...styles ?? this.styles, 'background': backgroundStyle},
    layouts: layouts ?? this.layouts,
  );

  Appearance withStyle(String id, ContainerStyle? value) {
    final next = {...styles};
    if (value == null) { next.remove(id); } else { next[id] = value; }
    return copyWith(styles: next);
  }
  Appearance withLayout(String id, SuperLayoutConfig value) =>
      copyWith(layouts: {...layouts, id: value});
  Appearance resetLayouts() => copyWith(layouts: const {});

  ThemeData theme(Brightness brightness) {
    final surface = backgroundStyle.color ??
        (brightness == Brightness.dark ? const Color(0xFF171A23) : const Color(0xFFF8F9FC));
    final generated = ColorScheme.fromSeed(seedColor: accent, brightness: brightness, surface: surface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: generated.copyWith(primary: generated.primary.withValues(alpha: accent.a), onSurface: foreground(surface)),
      scaffoldBackgroundColor: backgroundStyle.fill.type == FillType.solid
          ? surface.withValues(alpha: surface.a * backgroundOpacity)
          : Colors.transparent,
      fontFamily: 'Segoe UI',
      appBarTheme: AppBarTheme(backgroundColor: surface, surfaceTintColor: Colors.transparent),
    );
  }
  static Color foreground(Color background) => ContainerStyle.foregroundFor(background);
}

class AppearanceScope extends InheritedNotifier<ValueNotifier<Appearance>> {
  const AppearanceScope({required ValueNotifier<Appearance> controller, required super.child, super.key})
      : super(notifier: controller);
  static ValueNotifier<Appearance>? controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
  static Appearance of(BuildContext context) => controllerOf(context)?.value ?? Appearance();
}
