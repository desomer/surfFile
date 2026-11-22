/// Événements déclencheurs ([BehaviorEvent]) et catégories ([BehaviorEventCategory])
/// utilisés par les comportements ([ComponentBehavior]).
///
/// Remplace et étend l'ancien `BehaviorTrigger` (conservé en alias de type) en
/// prenant en charge les gestes utilisateur (`onTap`, `onDoubleTap`, `onLongPress`),
/// les événements de pointeur, sélection, valeur, focus, ouverture/fermeture,
/// cycle de vie et liaisons déclaratives (`onHover`, `onBinding`, `onCreate`),
/// tout en assurant une rétrocompatibilité JSON complète avec les noms historiques.
library;

import 'package:material_ui/material_ui.dart';

/// Catégorie fonctionnelle d'un [BehaviorEvent] utilisée pour organiser
/// l'interface de sélection dans l'éditeur de comportements.
enum BehaviorEventCategory {
  /// Gestes de pointeur / tactiles (`onTap`, `onDoubleTap`, `onLongPress`).
  gesture('Gestes', Icons.touch_app_outlined),

  /// Événements de survol impératifs (`onHoverEnter`, `onHoverExit`).
  pointer('Survol', Icons.mouse_outlined),

  /// Événements de sélection (`onSelected`).
  selection('Sélection', Icons.check_circle_outline),

  /// Événements de modification et soumission de valeur (`onChanged`, `onSubmitted`).
  value('Valeur & saisie', Icons.edit_outlined),

  /// Événements de focus clavier (`onFocus`, `onBlur`).
  focus('Focus', Icons.center_focus_strong_outlined),

  /// Événements d'ouverture / fermeture (`onExpanded`, `onCollapsed`).
  disclosure('Ouverture / Fermeture', Icons.unfold_more_outlined),

  /// Cycle de vie du composant (`onMount`).
  lifecycle('Cycle de vie', Icons.play_circle_outline),

  /// Comportements déclaratifs ou réactifs (`onHover`, `onBinding`, `onCreate`).
  declarative('Déclaratif / Réactif', Icons.link);

  const BehaviorEventCategory(this.label, this.icon);

  /// Libellé français de la catégorie.
  final String label;

  /// Icône représentative de la catégorie.
  final IconData icon;
}

/// Événement déclencheur d'un [ComponentBehavior] sur un composant.
enum BehaviorEvent {
  /// Clic simple ou tap sur le composant.
  onTap(
    label: 'Clic (onTap)',
    description: 'Sur un clic',
    icon: Icons.touch_app_outlined,
    category: BehaviorEventCategory.gesture,
    isImperative: true,
    legacyName: 'click',
  ),

  /// Double-clic ou double-tap sur le composant.
  onDoubleTap(
    label: 'Double-clic (onDoubleTap)',
    description: 'Sur un double-clic',
    icon: Icons.touch_app_outlined,
    category: BehaviorEventCategory.gesture,
    isImperative: true,
    legacyName: 'doubleClick',
  ),

  /// Appui long maintenu sur le composant.
  onLongPress(
    label: 'Appui long (onLongPress)',
    description: 'Lors d’un appui long',
    icon: Icons.pan_tool_alt_outlined,
    category: BehaviorEventCategory.gesture,
    isImperative: true,
  ),

  /// Entrée du curseur sur le composant (événement impératif).
  onHoverEnter(
    label: 'Entrée du survol (onHoverEnter)',
    description: 'Lorsque le pointeur entre sur le composant',
    icon: Icons.login_outlined,
    category: BehaviorEventCategory.pointer,
    isImperative: true,
  ),

  /// Sortie du curseur du composant (événement impératif).
  onHoverExit(
    label: 'Sortie du survol (onHoverExit)',
    description: 'Lorsque le pointeur quitte le composant',
    icon: Icons.logout_outlined,
    category: BehaviorEventCategory.pointer,
    isImperative: true,
  ),

  /// Sélection d'une ligne, d'un nœud, d'un onglet, d'une destination ou d'une option.
  onSelected(
    label: 'Sélection (onSelected)',
    description: 'Lorsqu’un élément, onglet ou choix est sélectionné',
    icon: Icons.check_circle_outline,
    category: BehaviorEventCategory.selection,
    isImperative: true,
  ),

  /// Modification de valeur effectuée par l'utilisateur (`SuperValue`, `Expansible`, `Menu`).
  onChanged(
    label: 'Modification (onChanged)',
    description: 'Lorsque la valeur est modifiée par l’utilisateur',
    icon: Icons.sync_alt_outlined,
    category: BehaviorEventCategory.value,
    isImperative: true,
  ),

  /// Soumission clavier (touche Entrée) dans un champ de saisie.
  onSubmitted(
    label: 'Validation clavier (onSubmitted)',
    description: 'Lorsque l’utilisateur valide avec Entrée',
    icon: Icons.keyboard_return_outlined,
    category: BehaviorEventCategory.value,
    isImperative: true,
  ),

  /// Prise de focus d'un champ ou composant focusable.
  onFocus(
    label: 'Prise de focus (onFocus)',
    description: 'Lorsque le composant reçoit le focus',
    icon: Icons.center_focus_strong_outlined,
    category: BehaviorEventCategory.focus,
    isImperative: true,
  ),

  /// Perte de focus d'un champ ou composant focusable.
  onBlur(
    label: 'Perte de focus (onBlur)',
    description: 'Lorsque le composant perd le focus',
    icon: Icons.center_focus_weak_outlined,
    category: BehaviorEventCategory.focus,
    isImperative: true,
  ),

  /// Ouverture / dépliage d'un panneau (`Expansible`), menu (`Menu`) ou nœud d'arbre.
  onExpanded(
    label: 'Dépliage (onExpanded)',
    description: 'Lorsqu’un panneau, menu ou nœud s’ouvre',
    icon: Icons.expand_more_outlined,
    category: BehaviorEventCategory.disclosure,
    isImperative: true,
  ),

  /// Fermeture / repliage d'un panneau (`Expansible`), menu (`Menu`) ou nœud d'arbre.
  onCollapsed(
    label: 'Repliage (onCollapsed)',
    description: 'Lorsqu’un panneau, menu ou nœud se ferme',
    icon: Icons.expand_less_outlined,
    category: BehaviorEventCategory.disclosure,
    isImperative: true,
  ),

  /// Exécution unique à l'affichage initial du composant (hors mode édition).
  onMount(
    label: 'Affichage initial (onMount)',
    description: 'Au chargement / affichage initial du composant',
    icon: Icons.play_circle_outline,
    category: BehaviorEventCategory.lifecycle,
    isImperative: true,
  ),

  /// Affichage déclaratif d'une info-bulle au survol (`TooltipAction`).
  onHover(
    label: 'Info-bulle au survol (onHover)',
    description: 'Au survol du composant',
    icon: Icons.info_outline,
    category: BehaviorEventCategory.declarative,
    isImperative: false,
    legacyName: 'hover',
  ),

  /// Comportement réactif déclenché par la valeur d'une liaison (`StateBindingAction`, `ZoneSizeBindingAction`).
  onBinding(
    label: 'Liaison réactive (onBinding)',
    description: 'Quand la valeur liée change',
    icon: Icons.link,
    category: BehaviorEventCategory.declarative,
    isImperative: false,
    legacyName: 'binding',
  ),

  /// Comportement déclaratif appliqué à la création d'une ligne (`CreationDefaultAction`).
  onCreate(
    label: 'Création de ligne (onCreate)',
    description: 'À la création d’une ligne',
    icon: Icons.add_box_outlined,
    category: BehaviorEventCategory.declarative,
    isImperative: false,
    legacyName: 'create',
  );

  /// Alias de compatibilité pour [onTap].
  static const BehaviorEvent click = onTap;

  /// Alias de compatibilité pour [onDoubleTap].
  static const BehaviorEvent doubleClick = onDoubleTap;

  /// Alias de compatibilité pour [onHover].
  static const BehaviorEvent hover = onHover;

  /// Alias de compatibilité pour [onBinding].
  static const BehaviorEvent binding = onBinding;

  /// Alias de compatibilité pour [onCreate].
  static const BehaviorEvent create = onCreate;

  /// Événements provoqués par un geste de pointeur / tactile.
  static const List<BehaviorEvent> gestures = [
    onTap,
    onDoubleTap,
    onLongPress,
  ];

  /// Tous les événements pouvant déclencher une action impérative.
  static const List<BehaviorEvent> imperativeEvents = [
    onTap,
    onDoubleTap,
    onLongPress,
    onHoverEnter,
    onHoverExit,
    onSelected,
    onChanged,
    onSubmitted,
    onFocus,
    onBlur,
    onExpanded,
    onCollapsed,
    onMount,
  ];

  /// Tous les événements déclaratifs / réactifs.
  static const List<BehaviorEvent> declarativeEvents = [
    onHover,
    onBinding,
    onCreate,
  ];

  const BehaviorEvent({
    required this.label,
    required this.description,
    required this.icon,
    required this.category,
    required this.isImperative,
    this.legacyName,
  });

  /// Libellé principal affiché dans l'éditeur.
  final String label;

  /// Description courte de l'événement.
  final String description;

  /// Icône Material associée.
  final IconData icon;

  /// Catégorie fonctionnelle de l'événement.
  final BehaviorEventCategory category;

  /// Indique si cet événement exécute des actions impératives (avec validateur optionnel).
  final bool isImperative;

  /// Nom historique `BehaviorTrigger` utilisé pour la rétrocompatibilité JSON et bus d'événements.
  final String? legacyName;

  /// Nom transmis au champ `trigger` du bus `SuperEventBus` pour préserver
  /// la compatibilité des écouteurs existants (`'click'`, `'doubleClick'`, etc.)
  /// tout en exposant le nom canonique pour les nouveaux événements.
  String get legacyTriggerName => legacyName ?? name;

  /// Table de résolution canonique + alias historiques.
  static const Map<String, BehaviorEvent> _byName = {
    'onTap': onTap,
    'click': onTap,
    'tap': onTap,
    'onDoubleTap': onDoubleTap,
    'doubleClick': onDoubleTap,
    'doubleTap': onDoubleTap,
    'onLongPress': onLongPress,
    'longPress': onLongPress,
    'onHoverEnter': onHoverEnter,
    'hoverEnter': onHoverEnter,
    'onHoverExit': onHoverExit,
    'hoverExit': onHoverExit,
    'onSelected': onSelected,
    'selected': onSelected,
    'onChanged': onChanged,
    'changed': onChanged,
    'onSubmitted': onSubmitted,
    'submitted': onSubmitted,
    'onFocus': onFocus,
    'focus': onFocus,
    'onBlur': onBlur,
    'blur': onBlur,
    'onExpanded': onExpanded,
    'expanded': onExpanded,
    'onCollapsed': onCollapsed,
    'collapsed': onCollapsed,
    'onMount': onMount,
    'mount': onMount,
    'onHover': onHover,
    'hover': onHover,
    'onBinding': onBinding,
    'binding': onBinding,
    'onCreate': onCreate,
    'create': onCreate,
  };

  /// Résout un nom JSON (canonique ou historique), ou `null` s'il est inconnu.
  static BehaviorEvent? tryParse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return _byName[trimmed];
  }

  /// Décode un nom JSON (canonique ou historique) et lève [FormatException] s'il est invalide.
  static BehaviorEvent fromJson(Object? raw) {
    if (raw == null) return BehaviorEvent.onTap;
    if (raw is! String) {
      throw FormatException(
        'Événement de comportement invalide (chaîne attendue) : $raw',
      );
    }
    final parsed = tryParse(raw);
    if (parsed == null) {
      throw FormatException('Événement de comportement inconnu : "$raw"');
    }
    return parsed;
  }

  /// Indique si cet événement est particulièrement pertinent pour un type de
  /// composant donné (`'value'`, `'listView'`, `'table'`, `'treeView'`, `'tab'`,
  /// `'expansible'`, `'menu'`, `'action'`, `'layout'`, etc.).
  bool isRecommendedForComponentType(String? componentType) {
    final normalized = (componentType ?? '').trim().toLowerCase();
    return switch (this) {
      onTap ||
      onDoubleTap ||
      onLongPress ||
      onHoverEnter ||
      onHoverExit ||
      onMount ||
      onHover ||
      onBinding => true,
      onCreate => normalized == 'value' || normalized.isEmpty,
      onChanged =>
        normalized == 'value' ||
            normalized == 'expansible' ||
            normalized == 'menu' ||
            normalized.isEmpty,
      onSubmitted ||
      onFocus ||
      onBlur => normalized == 'value' || normalized.isEmpty,
      onSelected =>
        normalized == 'listview' ||
            normalized == 'list' ||
            normalized == 'table' ||
            normalized == 'treeview' ||
            normalized == 'tree' ||
            normalized == 'tab' ||
            normalized == 'tabs' ||
            normalized == 'value' ||
            normalized == 'bottomnavigationbar' ||
            normalized == 'navigationrail' ||
            normalized == 'iterablecontent' ||
            normalized == 'chart' ||
            normalized.isEmpty,
      onExpanded ||
      onCollapsed =>
        normalized == 'expansible' ||
            normalized == 'menu' ||
            normalized == 'treeview' ||
            normalized == 'tree' ||
            normalized.isEmpty,
    };
  }
}

/// Alias de compatibilité conservé pour les appelants historiques utilisant `BehaviorTrigger`.
typedef BehaviorTrigger = BehaviorEvent;
