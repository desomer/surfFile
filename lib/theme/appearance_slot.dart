import 'appearance.dart';
import 'container_style.dart';

/// Zones de l'écran principal stylables par un `SuperContainer`.
enum AppearanceSlot {
  background('Fond de l’application', editShape: false),
  sidebar('Style du panneau de gauche'),
  pathBar('Style de la barre du chemin'),
  card('Style des cartes'),
  selectedCard('Style des cartes sélectionnées'),
  selectedFolder('Style de la sélection du panneau gauche');

  const AppearanceSlot(this.label, {this.editShape = true});

  final String label;

  /// Arrondi, élévation et ombre n'ont pas de sens pour le fond plein écran.
  final bool editShape;

  ContainerStyle read(Appearance a) => switch (this) {
    background => a.backgroundStyle,
    sidebar => a.sidebarStyle,
    pathBar => a.pathBarStyle,
    card => a.cardStyle,
    selectedCard => a.effectiveSelectedCardStyle,
    selectedFolder => a.effectiveSelectedFolderStyle,
  };

  Appearance write(Appearance a, ContainerStyle style) => switch (this) {
    background => a.copyWith(backgroundStyle: style),
    sidebar => a.copyWith(sidebarStyle: style),
    pathBar => a.copyWith(pathBarStyle: style),
    card => a.copyWith(cardStyle: style),
    selectedCard => a.copyWith(selectedCardStyle: style),
    selectedFolder => a.copyWith(selectedFolderStyle: style),
  };

  Appearance reset(Appearance a) => switch (this) {
    background => a.copyWith(backgroundStyle: const ContainerStyle()),
    sidebar => a.copyWith(sidebarStyle: const ContainerStyle()),
    pathBar => a.copyWith(pathBarStyle: const ContainerStyle(borderWidth: 1)),
    card => a.copyWith(cardStyle: Appearance.defaultCardStyle),
    selectedCard => a.copyWith(resetSelectedCardStyle: true),
    selectedFolder => a.copyWith(resetSelectedFolderStyle: true),
  };
}
