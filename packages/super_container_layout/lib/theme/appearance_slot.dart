import 'appearance.dart';
import 'container_style.dart';

/// Zones de l'écran principal stylables par un `SuperContainer`.
class AppearanceSlot {
  static const background = AppearanceSlot._(
    'background',
    'Fond de l’application',
    editShape: false,
    extendedLook: false,
  );
  static const sidebar = AppearanceSlot._(
    'sidebar',
    'Style du panneau de gauche',
  );
  static const pathBar = AppearanceSlot._(
    'pathBar',
    'Style de la barre du chemin',
  );
  static const explorerViewModeBar = AppearanceSlot._(
    'explorerViewModeBar',
    'Style de la barre des modes d’affichage',
  );
  static const diskPanel = AppearanceSlot._(
    'diskPanel',
    'Style de la zone des disques',
  );
  static const diskTile = AppearanceSlot._(
    'diskTile',
    'Style des tuiles de disque',
  );
  static const selectedDiskTile = AppearanceSlot._(
    'selectedDiskTile',
    'Style du disque sélectionné',
  );
  static const card = AppearanceSlot._(
    'card',
    'Style des cartes',
    extendedLook: false,
  );
  static const selectedCard = AppearanceSlot._(
    'selectedCard',
    'Style des cartes sélectionnées',
    extendedLook: false,
  );
  static const folder = AppearanceSlot._(
    'folder',
    'Style des dossiers du panneau gauche',
  );
  static const selectedFolder = AppearanceSlot._(
    'selectedFolder',
    'Style de la sélection du panneau gauche',
  );

  /// Slots prédéfinis ; les instances personnalisées ne sont pas enregistrées.
  static const values = [
    background,
    sidebar,
    pathBar,
    explorerViewModeBar,
    diskPanel,
    diskTile,
    selectedDiskTile,
    card,
    selectedCard,
    folder,
    selectedFolder,
  ];

  const AppearanceSlot(
    this.label, {
    required this.name,
    required ContainerStyle Function(Appearance) read,
    required Appearance Function(Appearance, ContainerStyle) write,
    required Appearance Function(Appearance) reset,
    this.editShape = true,
    this.extendedLook = true,
    AppearanceSlot? selectedVariant,
    AppearanceSlot? standard,
  }) : _read = read,
       _write = write,
       _reset = reset,
       _selectedVariant = selectedVariant,
       _standard = standard;

  const AppearanceSlot._(
    this.name,
    this.label, {
    this.editShape = true,
    this.extendedLook = true,
  }) : _read = null,
       _write = null,
       _reset = null,
       _selectedVariant = null,
       _standard = null;

  final String name;
  final String label;
  final ContainerStyle Function(Appearance)? _read;
  final Appearance Function(Appearance, ContainerStyle)? _write;
  final Appearance Function(Appearance)? _reset;
  final AppearanceSlot? _selectedVariant;
  final AppearanceSlot? _standard;

  /// Arrondi, élévation et ombre n'ont pas de sens pour le fond plein écran.
  final bool editShape;

  /// Coins et côtés indépendants, ombres détaillées, motif, flou et
  /// transformation : rendus par StyledSurface, pas par les cartes, les lignes
  /// de l'explorateur ni le fond.
  final bool extendedLook;

  /// Variante « sélectionné » éditée dans un onglet de l'éditeur de ce slot.
  AppearanceSlot? get selectedVariant =>
      _selectedVariant ??
      switch (this) {
        card => selectedCard,
        diskTile => selectedDiskTile,
        folder => selectedFolder,
        _ => null,
      };

  /// Slot présenté dans les menus : la variante standard de la paire.
  AppearanceSlot get standard =>
      _standard ??
      switch (this) {
        selectedCard => card,
        selectedDiskTile => diskTile,
        selectedFolder => folder,
        _ => this,
      };

  bool get isSelectedVariant => standard != this;

  ContainerStyle read(Appearance a) =>
      _read?.call(a) ??
      switch (this) {
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
        _ => throw StateError('Lecture non définie pour le slot $name'),
      };

  Appearance write(Appearance a, ContainerStyle style) =>
      _write?.call(a, style) ??
      switch (this) {
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
        _ => throw StateError('Écriture non définie pour le slot $name'),
      };

  Appearance reset(Appearance a) =>
      _reset?.call(a) ??
      switch (this) {
        background => a.copyWith(backgroundStyle: const ContainerStyle()),
        sidebar => a.copyWith(sidebarStyle: const ContainerStyle()),
        pathBar => a.copyWith(
          pathBarStyle: const ContainerStyle(borderWidth: 1),
        ),
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
        _ => throw StateError(
          'Réinitialisation non définie pour le slot $name',
        ),
      };
}
