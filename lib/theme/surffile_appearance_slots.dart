import 'surffile_appearance.dart';
import 'package:super_container_layout/theme/appearance.dart' as shell;
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/neon_style.dart';

/// Style catalog belonging to SurfFile, not to the layout package.
///
/// Each slot edits the style of [SurfFileAppearance.styles] whose ID is its
/// [AppearanceSlot.name]; resetting removes the entry, which restores
/// [SurfFileAppearance.defaultStyles] or the derived default of an optional
/// variant. [AppearanceSlot.read] resolves these derived styles.
abstract final class SurfFileAppearanceSlots {
  static final background = _slot(
    'Fond de l’application',
    name: 'background',
    role: AppearanceSurfaceRole.applicationBackground,
    editShape: false,
    extendedLook: false,
  );
  static final sidebar = _slot('Style du panneau de gauche', name: 'sidebar');
  static final pathBar = _slot(
    'Style de la barre du chemin',
    name: 'pathBar',
  );
  static final explorerViewModeBar = _slot(
    'Style de la barre des modes d’affichage',
    name: 'explorerViewModeBar',
  );
  static final diskPanel = _slot(
    'Style de la zone des disques',
    name: 'diskPanel',
  );
  static final AppearanceSlot diskTile = _slot(
    'Style des tuiles de disque',
    name: 'diskTile',
    selectedVariantResolver: () => selectedDiskTile,
  );
  static final AppearanceSlot selectedDiskTile = _slot(
    'Style du disque sélectionné',
    name: 'selectedDiskTile',
    standard: diskTile,
    read: (a) => a.variantStyle('selectedDiskTile', 'diskTile', inheritLook: true),
  );
  static final AppearanceSlot card = _slot(
    'Style des cartes',
    name: 'card',
    extendedLook: false,
    selectedVariantResolver: () => selectedCard,
  );
  static final AppearanceSlot selectedCard = _slot(
    'Style des cartes sélectionnées',
    name: 'selectedCard',
    extendedLook: false,
    standard: card,
    read: (a) => a.variantStyle('selectedCard', 'card'),
  );
  static final AppearanceSlot folder = _slot(
    'Style des dossiers du panneau gauche',
    name: 'folder',
    read: (a) => _folderStyle(a, 'folder'),
    selectedVariantResolver: () => selectedFolder,
  );
  static final AppearanceSlot selectedFolder = _slot(
    'Style de la sélection du panneau gauche',
    name: 'selectedFolder',
    standard: folder,
    read: (a) => _folderStyle(a, 'selectedFolder'),
  );

  static final values = List<AppearanceSlot>.unmodifiable([
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
  ]);
}

/// Folder rows of the left panel: compact shape, card shadow, own neon only.
ContainerStyle _folderStyle(shell.Appearance a, String id) {
  final style =
      a.styles[id] ??
      ContainerStyle(radius: 9, shadowOpacity: a.style('card').shadowOpacity);
  return style.copyWith(neon: style.neon ?? const NeonStyle());
}

AppearanceSlot _slot(
  String label, {
  required String name,
  ContainerStyle Function(shell.Appearance)? read,
  bool editShape = true,
  bool extendedLook = true,
  AppearanceSurfaceRole role = AppearanceSurfaceRole.standard,
  AppearanceSlot? standard,
  AppearanceSlot Function()? selectedVariantResolver,
}) => AppearanceSlot(
  label,
  name: name,
  read: (value) => (read ?? (a) => a.style(name))(requireSurfFileAppearance(value)),
  write: (value, style) => requireSurfFileAppearance(value).withStyle(name, style),
  reset: (value) => requireSurfFileAppearance(value).withStyle(name, null),
  editShape: editShape,
  extendedLook: extendedLook,
  role: role,
  standard: standard,
  selectedVariantResolver: selectedVariantResolver,
);