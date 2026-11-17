/// Paramètres de flux, de défilement, d'alignement et d'espacement d'une zone.
library;

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/rendering.dart' show CrossAxisAlignment, MainAxisAlignment;

import 'scrollbar_style_config.dart';
import 'slot_size_constraints.dart' show readSlotPaddingInsets;

/// Paramètres de flux (scroll, alignements, espacement, marge) d'une zone.
class ZoneFlowConfig {
  static const maxSpacing = 100.0;
  static const maxPadding = 200.0;

  const ZoneFlowConfig({
    this.scrollable = false,
    this.showScrollbar = false,
    this.scrollbarStyle = const ScrollbarStyleConfig(),
    this.expandSlots = true,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.spacing = 0,
    this.padding = 0,
    this.paddingInsets,
  }) : assert(spacing >= 0 && spacing < double.infinity),
       assert(padding >= 0 && padding < double.infinity);

  final bool scrollable;

  /// Affiche une barre de défilement lorsque [scrollable] est activé.
  final bool showScrollbar;

  /// Style visuel de la barre de défilement lorsque [showScrollbar] est activé.
  final ScrollbarStyleConfig scrollbarStyle;

  /// Si `true` (défaut), les slots sans taille fixe se partagent l'espace
  /// (`flex: 1`). Si `false`, ils prennent la taille de leur contenu (`flex: 0`).
  final bool expandSlots;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;
  final double padding;
  final EdgeInsets? paddingInsets;

  EdgeInsets get contentPadding => paddingInsets ?? EdgeInsets.all(padding);
  bool get hasPadding => padding != 0 || paddingInsets != null;

  bool get isDefault =>
      !scrollable &&
      !showScrollbar &&
      scrollbarStyle.isDefault &&
      expandSlots &&
      mainAxisAlignment == MainAxisAlignment.start &&
      crossAxisAlignment == CrossAxisAlignment.stretch &&
      spacing == 0 &&
      !hasPadding;

  ZoneFlowConfig copyWith({
    bool? scrollable,
    bool? showScrollbar,
    ScrollbarStyleConfig? scrollbarStyle,
    bool? expandSlots,
    MainAxisAlignment? mainAxisAlignment,
    CrossAxisAlignment? crossAxisAlignment,
    double? spacing,
    double? padding,
    EdgeInsets? paddingInsets,
    bool clearPaddingInsets = false,
  }) => ZoneFlowConfig(
    scrollable: scrollable ?? this.scrollable,
    showScrollbar: showScrollbar ?? this.showScrollbar,
    scrollbarStyle: scrollbarStyle ?? this.scrollbarStyle,
    expandSlots: expandSlots ?? this.expandSlots,
    mainAxisAlignment: mainAxisAlignment ?? this.mainAxisAlignment,
    crossAxisAlignment: crossAxisAlignment ?? this.crossAxisAlignment,
    spacing: spacing ?? this.spacing,
    padding: padding ?? this.padding,
    paddingInsets: clearPaddingInsets
        ? null
        : (paddingInsets ?? this.paddingInsets),
  );

  Map<String, Object?> toJson() => {
    if (scrollable) 'scrollable': scrollable,
    if (showScrollbar) 'showScrollbar': showScrollbar,
    if (!scrollbarStyle.isDefault) 'scrollbarStyle': scrollbarStyle.toJson(),
    if (!expandSlots) 'expandSlots': expandSlots,
    if (mainAxisAlignment != MainAxisAlignment.start)
      'mainAxisAlignment': mainAxisAlignment.name,
    if (crossAxisAlignment != CrossAxisAlignment.stretch)
      'crossAxisAlignment': crossAxisAlignment.name,
    if (spacing != 0) 'spacing': spacing,
    if (padding != 0) 'padding': padding,
    if (paddingInsets != null)
      'paddingInsets': [
        paddingInsets!.top,
        paddingInsets!.right,
        paddingInsets!.bottom,
        paddingInsets!.left,
      ],
  };

  static ZoneFlowConfig fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Paramètres de flux de zone invalides.');
    }
    final scrollable = value['scrollable'] ?? false;
    if (scrollable is! bool) {
      throw const FormatException('Valeur invalide pour "scrollable".');
    }
    final showScrollbar = value['showScrollbar'] ?? false;
    if (showScrollbar is! bool) {
      throw const FormatException('Valeur invalide pour "showScrollbar".');
    }
    final scrollbarStyle = value['scrollbarStyle'] == null
        ? const ScrollbarStyleConfig()
        : ScrollbarStyleConfig.fromJson(value['scrollbarStyle']);
    final expandSlots = value['expandSlots'] ?? true;
    if (expandSlots is! bool) {
      throw const FormatException('Valeur invalide pour "expandSlots".');
    }
    final rawMain =
        value['mainAxisAlignment'] ??
        value['mainAxis'] ??
        MainAxisAlignment.start.name;
    final mainAxisAlignment =
        MainAxisAlignment.values.where((m) => m.name == rawMain).firstOrNull ??
        (throw const FormatException('Alignement principal de zone invalide.'));
    final rawCross =
        value['crossAxisAlignment'] ??
        value['crossAxis'] ??
        CrossAxisAlignment.stretch.name;
    final crossAxisAlignment =
        CrossAxisAlignment.values
            .where(
              (c) => c != CrossAxisAlignment.baseline && c.name == rawCross,
            )
            .firstOrNull ??
        (throw const FormatException(
          'Alignement transversal de zone invalide.',
        ));
    final spacing = value['spacing'] ?? 0;
    if (spacing is! num || !spacing.isFinite || spacing < 0) {
      throw const FormatException('Espacement de zone invalide.');
    }
    final padding = value['padding'] ?? 0;
    if (padding is! num || !padding.isFinite || padding < 0) {
      throw const FormatException('Marge de zone invalide.');
    }
    final rawPaddingInsets = value['paddingInsets'];
    final paddingInsets = rawPaddingInsets == null
        ? null
        : readSlotPaddingInsets(rawPaddingInsets);
    return ZoneFlowConfig(
      scrollable: scrollable,
      showScrollbar: showScrollbar,
      scrollbarStyle: scrollbarStyle,
      expandSlots: expandSlots,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      spacing: spacing.toDouble(),
      padding: padding.toDouble(),
      paddingInsets: paddingInsets,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ZoneFlowConfig &&
      other.scrollable == scrollable &&
      other.showScrollbar == showScrollbar &&
      other.scrollbarStyle == scrollbarStyle &&
      other.expandSlots == expandSlots &&
      other.mainAxisAlignment == mainAxisAlignment &&
      other.crossAxisAlignment == crossAxisAlignment &&
      other.spacing == spacing &&
      other.padding == padding &&
      other.paddingInsets == paddingInsets;

  @override
  int get hashCode => Object.hash(
    scrollable,
    showScrollbar,
    scrollbarStyle,
    expandSlots,
    mainAxisAlignment,
    crossAxisAlignment,
    spacing,
    padding,
    paddingInsets,
  );
}
