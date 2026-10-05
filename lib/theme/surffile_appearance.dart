import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/theme/appearance.dart' as shell;
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'disk_gauge_style.dart';
import 'folder_transition.dart';
export 'surffile_appearance_scope.dart';

/// SurfFile appearance: generic [styles] and [layouts] maps keyed by ID (see
/// `SurfFileAppearanceSlots`), plus scalar business preferences.
///
/// Missing entries of [defaultStyles] and [defaultLayouts] are always filled
/// in, so a partial map never erases a default; removing such an entry with
/// [withStyle] resets it. Optional variants (`selectedCard`, `folder`…) are
/// absent by default and derived through the slot catalog.
@immutable
class SurfFileAppearance extends shell.Appearance {
  static const minRowHeight = 20.0;
  static const maxRowHeight = 100.0;
  static const minSpacing = 4.0;
  static const maxSpacing = 64.0;
  static const minTransitionDuration = 100.0;
  static const maxTransitionDuration = 1000.0;
  static const minScrollFadeExtent = 8.0;
  static const maxScrollFadeExtent = 100.0;

  SurfFileAppearance({
    super.mode,
    super.accent,
    super.backgroundOpacity,
    super.windowOpacity,
    super.windowEffect,
    this.diskGaugeStyle = const DiskGaugeStyle(),
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
    Map<String, ContainerStyle>? styles,
    Map<String, SuperLayoutConfig>? layouts,
  }) : super(
         styles: {...defaultStyles, ...?styles},
         layouts: {...defaultLayouts, ...?layouts},
       );

  static const defaultCardStyle = ContainerStyle(
    radius: 13,
    borderWidth: 1,
    padding: 12,
  );

  static const defaultSidebarWidth = 236.0;

  /// Panneau gauche à l'ouest, explorateur au centre.
  static const defaultExplorerLayout = SuperLayoutConfig(
    north: false,
    south: false,
    east: false,
    westSize: defaultSidebarWidth,
    placements: {
      SuperLayoutZone.west: ['sidebar'],
      SuperLayoutZone.center: ['main'],
    },
  );

  /// Barres empilées au nord (hauteur automatique), contenu au centre.
  static const defaultExplorerMainLayout = SuperLayoutConfig(
    south: false,
    west: false,
    east: false,
    autoSides: {SuperLayoutZone.north},
    placements: {
      SuperLayoutZone.north: [
        'split-indicator',
        'toolbar',
        'breadcrumbs',
        'view-mode-bar',
        'filter-bar',
        'sort-header',
      ],
      SuperLayoutZone.center: ['content'],
    },
  );

  /// Espace perso / favoris au centre, disques au sud (hauteur automatique).
  static const defaultExplorerSidebarLayout = SuperLayoutConfig(
    north: false,
    west: false,
    east: false,
    autoSides: {SuperLayoutZone.south},
    placements: {
      SuperLayoutZone.center: ['sidebar-places'],
      SuperLayoutZone.south: ['sidebar-disks'],
    },
  );

  static const defaultDiskTileStyle = ContainerStyle(
    radius: 12,
    borderWidth: 1,
  );

  /// Styles always present; the optional variants `selectedDiskTile`,
  /// `selectedCard`, `folder` and `selectedFolder` are absent by default.
  static const defaultStyles = <String, ContainerStyle>{
    'background': ContainerStyle(),
    'card': defaultCardStyle,
    'sidebar': ContainerStyle(),
    'pathBar': ContainerStyle(borderWidth: 1),
    'explorerViewModeBar': ContainerStyle(),
    'diskPanel': ContainerStyle(),
    'diskTile': defaultDiskTileStyle,
  };

  static const defaultLayouts = <String, SuperLayoutConfig>{
    'explorer': defaultExplorerLayout,
    'explorerMain': defaultExplorerMainLayout,
    'explorerSidebar': defaultExplorerSidebarLayout,
  };

  final DiskGaugeStyle diskGaugeStyle;
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

  @override
  SurfFileAppearance withStyle(String id, ContainerStyle? value) =>
      requireSurfFileAppearance(super.withStyle(id, value));

  @override
  SurfFileAppearance withLayout(String id, SuperLayoutConfig value) =>
      requireSurfFileAppearance(super.withLayout(id, value));

  /// Remet toutes les zones et tous les slots à leur place par défaut : les
  /// dispositions SurfFile reprennent [defaultLayouts] et celles déclarées
  /// dynamiquement (registre) sont retirées, donc relues avec leur valeur par
  /// défaut d'enregistrement.
  @override
  SurfFileAppearance resetLayouts() =>
      requireSurfFileAppearance(super.resetLayouts());

  @override
  SurfFileAppearance copyWith({
    Map<String, ContainerStyle>? styles,
    Map<String, SuperLayoutConfig>? layouts,
    ThemeMode? mode,
    Color? accent,
    double? backgroundOpacity,
    double? windowOpacity,
    WindowEffect? windowEffect,
    ContainerStyle? backgroundStyle,
    DiskGaugeStyle? diskGaugeStyle,
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
  }) => SurfFileAppearance(
    styles: {...styles ?? this.styles, 'background': ?backgroundStyle},
    layouts: layouts ?? this.layouts,
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    windowOpacity: windowOpacity ?? this.windowOpacity,
    windowEffect: windowEffect ?? this.windowEffect,
    diskGaugeStyle: diskGaugeStyle ?? this.diskGaugeStyle,
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

  /// Automatic solid color of unselected cards whose style has none.
  static Color defaultCardColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerLow
        : Colors.white;
  }

  /// Solid color of a card drawn with the resolved [style].
  static Color cardColor(
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

  static Color foreground(Color background) =>
      ContainerStyle.foregroundFor(background);
}

typedef Appearance = SurfFileAppearance;

SurfFileAppearance requireSurfFileAppearance(shell.Appearance value) {
  if (value is SurfFileAppearance) return value;
  throw StateError('SurfFile requires its configured appearance store.');
}