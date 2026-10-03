/// Façon de sélectionner les éléments avec la souris.
enum SelectionMode {
  /// Clic pour sélectionner ; Ctrl/Maj pour étendre.
  standard('Standard', 'Clic, Ctrl et Maj'),

  /// Une case à cocher par élément ; un clic sélectionne l'élément seul.
  checkbox('Cases à cocher', 'Une case par élément'),

  /// Chaque clic sur une ligne l'ajoute ou la retire de la sélection.
  rowClick('Clic sur la ligne', 'Un clic bascule la sélection');

  const SelectionMode(this.label, this.description);

  final String label;
  final String description;
}
