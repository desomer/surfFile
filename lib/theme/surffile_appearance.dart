import 'package:material_ui/material_ui.dart';

import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/theme/default_appearance.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'disk_gauge_style.dart';
import 'file_drag_mode.dart';
import 'folder_transition.dart';

export 'surffile_appearance_scope.dart';
export 'surffile_preferences.dart';
export 'package:super_container_layout/theme/default_appearance.dart';

/// Application catalog and scalar defaults, independent of the runtime model.
abstract final class SurfFileAppearanceDefaults {
  static const minRowHeight = DefaultAppearance.minRowHeight;
  static const maxRowHeight = DefaultAppearance.maxRowHeight;
  static const minSpacing = DefaultAppearance.minSpacing;
  static const maxSpacing = DefaultAppearance.maxSpacing;
  static const minTransitionDuration = 100.0;
  static const maxTransitionDuration = 1000.0;
  static const minScrollFadeExtent = DefaultAppearance.minScrollFadeExtent;
  static const maxScrollFadeExtent = DefaultAppearance.maxScrollFadeExtent;

  static const folderTransitionDuration = 220.0;
  static const folderTransition = FolderTransition.none;
  static const fileDragMode = FileDragMode.nameAndIcon;
  static const diskGaugeStyle = DiskGaugeStyle();
  static const cardHeight = 142.0;
  static const cardWidth = 180.0;
  static const rowHeight = 48.0;
  static const spacing = 12.0;
  static const fontSize = 12.0;
  static const iconSize = 49.0;
  static const scrollFadeEnabled = true;
  static const scrollFadeExtent = 28.0;

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

}

/// Creates a package model with the application catalog explicitly merged.
DefaultAppearance defaultSurfFileAppearance({
  Map<String, ContainerStyle>? styles,
  Map<String, SuperLayoutConfig>? layouts,
}) => DefaultAppearance(
  styles: {...SurfFileAppearanceDefaults.defaultStyles, ...?styles},
  layouts: {...SurfFileAppearanceDefaults.defaultLayouts, ...?layouts},
);

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

typedef Appearance = DefaultAppearance;
