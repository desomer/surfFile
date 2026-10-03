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
    this.cardColor,
    this.backgroundColor,
    this.backgroundOpacity = 1,
    this.windowOpacity = 1,
    this.cardFill = const ContainerFill(),
    this.backgroundFill = const ContainerFill(),
    this.sidebarStyle = const ContainerStyle(),
    this.pathBarStyle = const ContainerStyle(borderWidth: 1),
    this.selectedCardStyle,
    this.selectedFolderStyle,
    this.cardNeon = const NeonStyle(),
    this.selectedFolderNeon = const NeonStyle(),
    this.backgroundNeon = const NeonStyle(),
    this.cardHeight = 142,
    this.cardWidth = 180,
    this.rowHeight = 48,
    this.radius = 13,
    this.spacing = 12,
    this.elevation = 0,
    this.selectedCardElevation,
    this.selectedFolderElevation = 0,
    this.shadowOpacity = .2,
    this.borderWidth = 1,
    this.cardBorderColor,
    this.backgroundBorderColor,
    this.backgroundBorderWidth = 0,
    this.fontSize = 12,
    this.iconSize = 49,
    this.folderTransition = FolderTransition.none,
    this.folderTransitionDuration = 220,
    this.scrollFadeEnabled = true,
    this.scrollFadeExtent = 28,
  });

  final ThemeMode mode;
  final Color accent;
  final Color? cardColor;
  final Color? backgroundColor;
  final double backgroundOpacity;
  final double windowOpacity;
  final ContainerFill cardFill;
  final ContainerFill backgroundFill;
  final ContainerStyle sidebarStyle;
  final ContainerStyle pathBarStyle;
  final ContainerStyle? selectedCardStyle;
  final ContainerStyle? selectedFolderStyle;
  final NeonStyle cardNeon;
  final NeonStyle selectedFolderNeon;
  final NeonStyle backgroundNeon;
  final double cardHeight;
  final double cardWidth;
  final double rowHeight;
  final double radius;
  final double spacing;
  final double elevation;
  final double? selectedCardElevation;
  final double selectedFolderElevation;
  final double shadowOpacity;
  final double borderWidth;
  final Color? cardBorderColor;
  final Color? backgroundBorderColor;
  final double backgroundBorderWidth;
  final double fontSize;
  final double iconSize;
  final FolderTransition folderTransition;
  final double folderTransitionDuration;
  final bool scrollFadeEnabled;
  final double scrollFadeExtent;

  Appearance copyWith({
    ThemeMode? mode,
    Color? accent,
    Color? cardColor,
    Color? backgroundColor,
    double? backgroundOpacity,
    double? windowOpacity,
    ContainerFill? cardFill,
    ContainerFill? backgroundFill,
    ContainerStyle? sidebarStyle,
    ContainerStyle? pathBarStyle,
    ContainerStyle? selectedCardStyle,
    ContainerStyle? selectedFolderStyle,
    bool resetSelectedCardStyle = false,
    bool resetSelectedFolderStyle = false,
    NeonStyle? cardNeon,
    NeonStyle? selectedFolderNeon,
    NeonStyle? backgroundNeon,
    bool resetCardColor = false,
    bool resetBackgroundColor = false,
    double? cardHeight,
    double? cardWidth,
    double? rowHeight,
    double? radius,
    double? spacing,
    double? elevation,
    double? selectedCardElevation,
    double? selectedFolderElevation,
    double? shadowOpacity,
    double? borderWidth,
    Color? cardBorderColor,
    Color? backgroundBorderColor,
    double? backgroundBorderWidth,
    bool resetCardBorderColor = false,
    bool resetBackgroundBorderColor = false,
    double? fontSize,
    double? iconSize,
    FolderTransition? folderTransition,
    double? folderTransitionDuration,
    bool? scrollFadeEnabled,
    double? scrollFadeExtent,
  }) =>
      Appearance(
        mode: mode ?? this.mode,
        accent: accent ?? this.accent,
        cardColor: resetCardColor ? null : cardColor ?? this.cardColor,
        backgroundColor: resetBackgroundColor
            ? null
            : backgroundColor ?? this.backgroundColor,
        backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
        windowOpacity: windowOpacity ?? this.windowOpacity,
        cardFill: cardFill ?? this.cardFill,
        backgroundFill: backgroundFill ?? this.backgroundFill,
        sidebarStyle: sidebarStyle ?? this.sidebarStyle,
        pathBarStyle: pathBarStyle ?? this.pathBarStyle,
        selectedCardStyle: resetSelectedCardStyle
            ? null
            : (selectedCardStyle ?? this.selectedCardStyle)
                ?.copyWith(elevation: selectedCardElevation),
        selectedFolderStyle: resetSelectedFolderStyle
            ? null
            : (selectedFolderStyle ?? this.selectedFolderStyle)
                ?.copyWith(elevation: selectedFolderElevation),
        cardNeon: cardNeon ?? this.cardNeon,
        selectedFolderNeon: selectedFolderNeon ?? this.selectedFolderNeon,
        backgroundNeon: backgroundNeon ?? this.backgroundNeon,
        cardHeight: cardHeight ?? this.cardHeight,
        cardWidth: cardWidth ?? this.cardWidth,
        rowHeight: rowHeight ?? this.rowHeight,
        radius: radius ?? this.radius,
        spacing: spacing ?? this.spacing,
        elevation: elevation ?? this.elevation,
        selectedCardElevation:
            selectedCardElevation ?? this.selectedCardElevation,
        selectedFolderElevation:
            selectedFolderElevation ?? this.selectedFolderElevation,
        shadowOpacity: shadowOpacity ?? this.shadowOpacity,
        borderWidth: borderWidth ?? this.borderWidth,
        cardBorderColor: resetCardBorderColor
            ? null
            : cardBorderColor ?? this.cardBorderColor,
        backgroundBorderColor: resetBackgroundBorderColor
            ? null
            : backgroundBorderColor ?? this.backgroundBorderColor,
        backgroundBorderWidth:
            backgroundBorderWidth ?? this.backgroundBorderWidth,
        fontSize: fontSize ?? this.fontSize,
        iconSize: iconSize ?? this.iconSize,
        folderTransition: folderTransition ?? this.folderTransition,
        folderTransitionDuration:
            folderTransitionDuration ?? this.folderTransitionDuration,
        scrollFadeEnabled: scrollFadeEnabled ?? this.scrollFadeEnabled,
        scrollFadeExtent: scrollFadeExtent ?? this.scrollFadeExtent,
      );

  ThemeData theme(Brightness brightness) {
    final surface = backgroundColor ??
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
      scaffoldBackgroundColor: backgroundFill.type == FillType.solid
          ? surface.withValues(alpha: surface.a * backgroundOpacity)
          : Colors.transparent,
      fontFamily: 'Segoe UI',
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  Color cardBackground(BuildContext context, {bool selected = false}) {
    final scheme = Theme.of(context).colorScheme;
    if (selected) {
      final style = effectiveSelectedCardStyle;
      if (style.fill.type != FillType.solid) {
        return Color.lerp(style.fill.start, style.fill.end, .5)!;
      }
      return style.color ?? scheme.primaryContainer;
    }
    if (cardFill.type != FillType.solid) {
      return Color.lerp(cardFill.start, cardFill.end, .5)!;
    }
    return cardColor ??
        (scheme.brightness == Brightness.dark
            ? scheme.surfaceContainerLow
            : Colors.white);
  }

  double cardElevation({required bool selected}) =>
      selected ? effectiveSelectedCardStyle.elevation : elevation;

  ContainerStyle get effectiveSelectedCardStyle => (selectedCardStyle ??
          ContainerStyle(
            radius: radius,
            borderWidth: borderWidth,
            elevation: selectedCardElevation ?? elevation,
            shadowOpacity: shadowOpacity,
          ))
      .copyWith(neon: selectedCardStyle?.neon ?? cardNeon);

  ContainerStyle get effectiveSelectedFolderStyle => (selectedFolderStyle ??
          ContainerStyle(
            radius: 9,
            elevation: selectedFolderElevation,
            shadowOpacity: shadowOpacity,
          ))
      .copyWith(neon: selectedFolderStyle?.neon ?? selectedFolderNeon);

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
