import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import 'container_fill.dart';
import 'container_style.dart';
import 'neon_style.dart';
import 'folder_transition.dart';

@immutable
class Appearance {
  static const minRowHeight = 20.0;
  static const maxRowHeight = 100.0;
  static const minSpacing = 4.0;
  static const maxSpacing = 64.0;
  static const minTransitionDuration = 100.0;
  static const maxTransitionDuration = 1000.0;
  static const minScrollFadeExtent = 8.0;
  static const maxScrollFadeExtent = 100.0;

  const Appearance({
    this.mode = ThemeMode.light,
    this.accent = const Color(0xFF5268D9),
    this.backgroundOpacity = 1,
    this.windowOpacity = 1,
    this.windowEffect = WindowEffect.transparent,
    this.cardStyle = defaultCardStyle,
    this.backgroundStyle = const ContainerStyle(),
    this.sidebarStyle = const ContainerStyle(),
    this.pathBarStyle = const ContainerStyle(borderWidth: 1),
    this.selectedCardStyle,
    this.selectedFolderStyle,
    this.cardHeight = 142,
    this.cardWidth = 180,
    this.rowHeight = 48,
    this.spacing = 12,
    this.fontSize = 12,
    this.iconSize = 49,
    this.folderTransition = FolderTransition.none,
    this.folderTransitionDuration = 220,
    this.scrollFadeEnabled = true,
    this.scrollFadeExtent = 28,
  });

  static const defaultCardStyle = ContainerStyle(
    radius: 13,
    borderWidth: 1,
    padding: 12,
  );

  final ThemeMode mode;
  final Color accent;
  final double backgroundOpacity;
  final double windowOpacity;

  /// Effet natif (flutter_acrylic) visible sous le fond transparent.
  final WindowEffect windowEffect;
  final ContainerStyle cardStyle;
  final ContainerStyle backgroundStyle;
  final ContainerStyle sidebarStyle;
  final ContainerStyle pathBarStyle;
  final ContainerStyle? selectedCardStyle;
  final ContainerStyle? selectedFolderStyle;
  final double cardHeight;
  final double cardWidth;
  final double rowHeight;
  final double spacing;
  final double fontSize;
  final double iconSize;
  final FolderTransition folderTransition;
  final double folderTransitionDuration;
  final bool scrollFadeEnabled;
  final double scrollFadeExtent;

  Appearance copyWith({
    ThemeMode? mode,
    Color? accent,
    double? backgroundOpacity,
    double? windowOpacity,
    WindowEffect? windowEffect,
    ContainerStyle? cardStyle,
    ContainerStyle? backgroundStyle,
    ContainerStyle? sidebarStyle,
    ContainerStyle? pathBarStyle,
    ContainerStyle? selectedCardStyle,
    ContainerStyle? selectedFolderStyle,
    bool resetSelectedCardStyle = false,
    bool resetSelectedFolderStyle = false,
    double? cardHeight,
    double? cardWidth,
    double? rowHeight,
    double? spacing,
    double? fontSize,
    double? iconSize,
    FolderTransition? folderTransition,
    double? folderTransitionDuration,
    bool? scrollFadeEnabled,
    double? scrollFadeExtent,
  }) => Appearance(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    windowOpacity: windowOpacity ?? this.windowOpacity,
    windowEffect: windowEffect ?? this.windowEffect,
    cardStyle: cardStyle ?? this.cardStyle,
    backgroundStyle: backgroundStyle ?? this.backgroundStyle,
    sidebarStyle: sidebarStyle ?? this.sidebarStyle,
    pathBarStyle: pathBarStyle ?? this.pathBarStyle,
    selectedCardStyle: resetSelectedCardStyle
        ? null
        : selectedCardStyle ?? this.selectedCardStyle,
    selectedFolderStyle: resetSelectedFolderStyle
        ? null
        : selectedFolderStyle ?? this.selectedFolderStyle,
    cardHeight: cardHeight ?? this.cardHeight,
    cardWidth: cardWidth ?? this.cardWidth,
    rowHeight: rowHeight ?? this.rowHeight,
    spacing: spacing ?? this.spacing,
    fontSize: fontSize ?? this.fontSize,
    iconSize: iconSize ?? this.iconSize,
    folderTransition: folderTransition ?? this.folderTransition,
    folderTransitionDuration:
        folderTransitionDuration ?? this.folderTransitionDuration,
    scrollFadeEnabled: scrollFadeEnabled ?? this.scrollFadeEnabled,
    scrollFadeExtent: scrollFadeExtent ?? this.scrollFadeExtent,
  );

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
    final scheme = generated.copyWith(
      primary: generated.primary.withValues(alpha: accent.a),
      onSurface: foreground(surface),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: backgroundStyle.fill.type == FillType.solid
          ? surface.withValues(alpha: surface.a * backgroundOpacity)
          : Colors.transparent,
      fontFamily: 'Segoe UI',
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  /// Automatic solid color of unselected cards when [cardStyle] has none.
  static Color defaultCardColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerLow
        : Colors.white;
  }

  Color cardBackground(BuildContext context, {bool selected = false}) {
    final style = selected ? effectiveSelectedCardStyle : cardStyle;
    if (style.fill.type != FillType.solid) {
      return Color.lerp(style.fill.start, style.fill.end, .5)!;
    }
    return style.color ??
        (selected
            ? Theme.of(context).colorScheme.primaryContainer
            : defaultCardColor(context));
  }

  double cardElevation({required bool selected}) =>
      selected ? effectiveSelectedCardStyle.elevation : cardStyle.elevation;

  NeonStyle get cardNeon => cardStyle.neon ?? const NeonStyle();

  ContainerStyle get effectiveSelectedCardStyle =>
      (selectedCardStyle ??
              ContainerStyle(
                radius: cardStyle.radius,
                borderWidth: cardStyle.borderWidth,
                elevation: cardStyle.elevation,
                shadowOpacity: cardStyle.shadowOpacity,
                padding: cardStyle.padding,
                margin: cardStyle.margin,
              ))
          .copyWith(neon: selectedCardStyle?.neon ?? cardNeon);

  ContainerStyle get effectiveSelectedFolderStyle =>
      (selectedFolderStyle ??
              ContainerStyle(radius: 9, shadowOpacity: cardStyle.shadowOpacity))
          .copyWith(neon: selectedFolderStyle?.neon ?? const NeonStyle());

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
      controllerOf(context)?.value ?? const Appearance();
}
