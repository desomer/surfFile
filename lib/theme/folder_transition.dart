enum FolderTransition {
  none('Aucune'),
  fade('Fondu'),
  slide('Glissement'),
  fullSlide('Glissement pleine largeur'),
  heroExpand('Hero — expansion du dossier'),
  heroIcon('Hero — icône vers le titre'),
  zoom('Zoom');

  const FolderTransition(this.label);
  final String label;
}
