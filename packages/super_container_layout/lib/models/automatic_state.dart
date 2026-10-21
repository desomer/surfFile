enum AutomaticState {
  hover('Hover', 'Survol du composant'),
  selected('Sélectionné', 'ListView sélectionné'),
  contentHover('Content survolé', 'Content survolé'),
  focused('Focus', 'Focus du champ'),
  disabled('Désactivé', 'Champ désactivé'),
  readOnly('Lecture seule', 'Champ en lecture seule');

  const AutomaticState(this.label, this.description);
  final String label;
  final String description;
  String get key => '\u0000$name';

  static AutomaticState? fromKey(String? key) =>
      values.where((value) => value.key == key).firstOrNull;
}
