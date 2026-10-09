/// Geste qui démarre le glisser-déposer de fichiers depuis les vues.
enum FileDragMode {
  /// Pas de glisser-déposer : glisser trace toujours un cadre de sélection.
  never('Jamais'),

  /// Glisser un élément déjà sélectionné le déplace ; ailleurs, cadre.
  selected('Si sélectionné'),

  /// Glisser depuis l'icône ou le nom d'un élément le déplace ; ailleurs, cadre.
  nameAndIcon('Depuis le nom et l’icône');

  const FileDragMode(this.label);
  final String label;
}
