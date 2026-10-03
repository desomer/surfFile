import 'appearance.dart';
import 'container_style.dart';

/// Zones de l'écran principal stylables par un `SuperContainer`.
enum AppearanceSlot {
  background('Fond de l’application', editShape: false),
  sidebar('Style du panneau de gauche'),
  pathBar('Style de la barre du chemin'),
  explorerViewModeBar('Style de la barre des modes d’affichage'),
  diskPanel('Style de la zone des disques'),
  diskTile('Style des tuiles de disque'),
  selectedDiskTile('Style du disque sélectionné'),
  card('Style des cartes'),
  selectedCard('Style des cartes sélectionnées'),
  folder('Style des dossiers du panneau gauche'),
  selectedFolder('Style de la sélection du panneau gauche');

  const AppearanceSlot(this.label, {this.editShape = true});

  final String label;

  /// Arrondi, élévation et ombre n'ont pas de sens pour le fond plein écran.
  final bool editShape;

  /// Variante « sélectionné » éditée dans un onglet de l'éditeur de ce slot.
  AppearanceSlot? get selectedVariant => switch (this) {
    card => selectedCard,
    diskTile => selectedDiskTile,
    folder => selectedFolder,
    _ => null,
  };

  /// Slot présenté dans les menus : la variante standard de la paire.
  AppearanceSlot get standard => switch (this) {
    selectedCard => card,
    selectedDiskTile => diskTile,
    selectedFolder => folder,
    _ => this,
  };

  bool get isSelectedVariant => standard != this;

  ContainerStyle read(Appearance a) => switch (this) {
    background => a.backgroundStyle,
    sidebar => a.sidebarStyle,
    pathBar => a.pathBarStyle,
    explorerViewModeBar => a.explorerViewModeBarStyle,
    diskPanel => a.diskPanelStyle,
    diskTile => a.diskTileStyle,
    selectedDiskTile => a.effectiveSelectedDiskTileStyle,
    card => a.cardStyle,
    selectedCard => a.effectiveSelectedCardStyle,
    folder => a.effectiveFolderStyle,
    selectedFolder => a.effectiveSelectedFolderStyle,
  };

  Appearance write(Appearance a, ContainerStyle style) => switch (this) {
    background => a.copyWith(backgroundStyle: style),
    sidebar => a.copyWith(sidebarStyle: style),
    pathBar => a.copyWith(pathBarStyle: style),
    explorerViewModeBar => a.copyWith(explorerViewModeBarStyle: style),
    diskPanel => a.copyWith(diskPanelStyle: style),
    diskTile => a.copyWith(diskTileStyle: style),
    selectedDiskTile => a.copyWith(selectedDiskTileStyle: style),
    card => a.copyWith(cardStyle: style),
    selectedCard => a.copyWith(selectedCardStyle: style),
    folder => a.copyWith(folderStyle: style),
    selectedFolder => a.copyWith(selectedFolderStyle: style),
  };

  Appearance reset(Appearance a) => switch (this) {
    background => a.copyWith(backgroundStyle: const ContainerStyle()),
    sidebar => a.copyWith(sidebarStyle: const ContainerStyle()),
    pathBar => a.copyWith(pathBarStyle: const ContainerStyle(borderWidth: 1)),
    explorerViewModeBar => a.copyWith(
      explorerViewModeBarStyle: const ContainerStyle(),
    ),
    diskPanel => a.copyWith(diskPanelStyle: const ContainerStyle()),
    diskTile => a.copyWith(diskTileStyle: Appearance.defaultDiskTileStyle),
    selectedDiskTile => a.copyWith(resetSelectedDiskTileStyle: true),
    card => a.copyWith(cardStyle: Appearance.defaultCardStyle),
    selectedCard => a.copyWith(resetSelectedCardStyle: true),
    folder => a.copyWith(resetFolderStyle: true),
    selectedFolder => a.copyWith(resetSelectedFolderStyle: true),
  };
}
