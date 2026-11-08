/// Sélecteur segmenté compact ([EditorSegmentedField]) et interrupteur sans
/// marge ([EditorSwitchTile]) partagés entre les éditeurs de composants et les
/// formulaires d'ajout.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_action_config.dart';
import '../../../../models/super_indicator_config.dart';
import '../../../../models/super_separator_config.dart';
import '../../../../models/super_tab_config.dart';
import '../../../../models/super_value_config.dart';

/// Style compact standard partagé par tous les [SegmentedButton] des éditeurs.
const editorCompactSegmentButtonStyle = ButtonStyle(
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Style standard d'un titre de champ au-dessus d'un [SegmentedButton].
const editorSegmentFieldLabelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
);

/// Option déclarative d'un [EditorSegmentedField].
@immutable
class EditorSegmentOption<T> {
  /// Crée une [EditorSegmentOption].
  const EditorSegmentOption({
    required this.value,
    this.label,
    this.icon,
    this.tooltip,
    this.iconSize = 16,
    this.flexibleIcon = false,
  });

  /// Valeur associée au segment.
  final T value;

  /// Libellé affiché dans le segment (omis pour un segment icône seule).
  final String? label;

  /// Icône optionnelle affichée dans le segment.
  final IconData? icon;

  /// Infobulle du segment (par défaut [label]).
  final String? tooltip;

  /// Taille de l'icône (16 par défaut).
  final double iconSize;

  /// Enveloppe l'icône dans un `Flexible(flex: 0)` pour les barres très denses.
  final bool flexibleIcon;

  /// Construit le [ButtonSegment] Material correspondant.
  ButtonSegment<T> toButtonSegment() {
    final iconWidget = icon == null
        ? null
        : flexibleIcon
        ? Flexible(flex: 0, child: Icon(icon, size: iconSize))
        : Icon(icon, size: iconSize);
    return ButtonSegment<T>(
      value: value,
      tooltip: tooltip ?? label,
      icon: iconWidget,
      label: label == null
          ? null
          : Text(label!, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Sélecteur segmenté compact avec titre optionnel, réduisant le boilerplate
/// des `SegmentedButton` dans les éditeurs de composants.
class EditorSegmentedField<T> extends StatelessWidget {
  /// Crée un [EditorSegmentedField].
  const EditorSegmentedField({
    this.buttonKey,
    this.label,
    this.subtitle,
    this.spacing = 4,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  /// Preset pour `Axis` (`Horizontal` / `Vertical`).
  static EditorSegmentedField<Axis> axis({
    required Key buttonKey,
    required Axis value,
    required ValueChanged<Axis> onChanged,
    String? label = 'Orientation',
  }) => EditorSegmentedField<Axis>(
    buttonKey: buttonKey,
    label: label,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: Axis.horizontal,
        label: 'Horizontal',
        icon: Icons.swap_horiz,
      ),
      EditorSegmentOption(
        value: Axis.vertical,
        label: 'Vertical',
        icon: Icons.swap_vert,
      ),
    ],
  );

  /// Preset pour la position d'icône d'un [SuperAction] (`leading` / `trailing`).
  static EditorSegmentedField<SuperActionIconPosition> actionIconPosition({
    required Key buttonKey,
    required SuperActionIconPosition value,
    required ValueChanged<SuperActionIconPosition> onChanged,
    String? label = 'Position de l’icône',
  }) => EditorSegmentedField<SuperActionIconPosition>(
    buttonKey: buttonKey,
    label: label,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: SuperActionIconPosition.leading,
        label: 'Début (avant le texte)',
        icon: Icons.first_page,
      ),
      EditorSegmentOption(
        value: SuperActionIconPosition.trailing,
        label: 'Fin (après le texte)',
        icon: Icons.last_page,
      ),
    ],
  );

  /// Preset pour la position d'icône d'un [SuperIndicator] (`leading` / `trailing`).
  static EditorSegmentedField<SuperIndicatorIconPosition>
  indicatorIconPosition({
    required Key buttonKey,
    required SuperIndicatorIconPosition value,
    required ValueChanged<SuperIndicatorIconPosition> onChanged,
    String? label = 'Position de l’icône',
  }) => EditorSegmentedField<SuperIndicatorIconPosition>(
    buttonKey: buttonKey,
    label: label,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: SuperIndicatorIconPosition.leading,
        label: 'Début (avant le texte)',
        icon: Icons.first_page,
      ),
      EditorSegmentOption(
        value: SuperIndicatorIconPosition.trailing,
        label: 'Fin (après le texte)',
        icon: Icons.last_page,
      ),
    ],
  );

  /// Preset pour le type d'action [SuperActionKind].
  static EditorSegmentedField<SuperActionKind> actionKind({
    required Key buttonKey,
    required SuperActionKind value,
    required ValueChanged<SuperActionKind> onChanged,
    String? label = 'Type de bouton',
    String textAndIconLabel = 'Texte et icône',
  }) => EditorSegmentedField<SuperActionKind>(
    buttonKey: buttonKey,
    label: label,
    value: value,
    onChanged: onChanged,
    options: [
      const EditorSegmentOption(
        value: SuperActionKind.text,
        label: 'Texte',
        icon: Icons.text_fields,
      ),
      const EditorSegmentOption(
        value: SuperActionKind.icon,
        label: 'Icône',
        icon: Icons.interests_outlined,
      ),
      EditorSegmentOption(
        value: SuperActionKind.textAndIcon,
        label: textAndIconLabel,
        icon: Icons.smart_button_outlined,
      ),
    ],
  );

  /// Preset pour le type de séparateur [SuperSeparatorKind].
  static EditorSegmentedField<SuperSeparatorKind> separatorKind({
    required Key buttonKey,
    required SuperSeparatorKind value,
    required ValueChanged<SuperSeparatorKind> onChanged,
    String? label = 'Type de composant',
  }) => EditorSegmentedField<SuperSeparatorKind>(
    buttonKey: buttonKey,
    label: label,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: SuperSeparatorKind.divider,
        label: 'Divider (trait)',
        tooltip: 'Trait de séparation (Divider)',
        icon: Icons.horizontal_rule,
      ),
      EditorSegmentOption(
        value: SuperSeparatorKind.spacer,
        label: 'Spacer (espace)',
        tooltip: 'Espace vide (Spacer)',
        icon: Icons.space_bar,
      ),
    ],
  );

  /// Preset pour le mode des onglets [SuperTabMode].
  static EditorSegmentedField<SuperTabMode> tabMode({
    required Key buttonKey,
    required SuperTabMode value,
    required ValueChanged<SuperTabMode> onChanged,
    String? label = 'Mode des onglets',
    double spacing = 4,
  }) => EditorSegmentedField<SuperTabMode>(
    buttonKey: buttonKey,
    label: label,
    spacing: spacing,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: SuperTabMode.static,
        label: 'Statique (onglets fixes)',
        icon: Icons.tab,
      ),
      EditorSegmentOption(
        value: SuperTabMode.dynamic,
        label: 'Dynamique (tableau JSON du repository)',
        icon: Icons.dynamic_feed,
      ),
    ],
  );

  /// Preset pour la position de la barre d'onglets [SuperTabBarPosition].
  static EditorSegmentedField<SuperTabBarPosition> tabBarPosition({
    required Key buttonKey,
    required SuperTabBarPosition value,
    required ValueChanged<SuperTabBarPosition> onChanged,
    String? label = 'Position de la barre d’onglets',
    double spacing = 4,
  }) => EditorSegmentedField<SuperTabBarPosition>(
    buttonKey: buttonKey,
    label: label,
    spacing: spacing,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: SuperTabBarPosition.top,
        label: 'En haut',
        icon: Icons.vertical_align_top,
      ),
      EditorSegmentOption(
        value: SuperTabBarPosition.bottom,
        label: 'En bas',
        icon: Icons.vertical_align_bottom,
      ),
    ],
  );

  /// Preset pour le style d'indicateur d'onglet [SuperTabIndicatorKind].
  static EditorSegmentedField<SuperTabIndicatorKind> tabIndicatorKind({
    required Key buttonKey,
    required SuperTabIndicatorKind value,
    required ValueChanged<SuperTabIndicatorKind> onChanged,
    String? label = 'Style de l’indicateur',
    double spacing = 4,
  }) => EditorSegmentedField<SuperTabIndicatorKind>(
    buttonKey: buttonKey,
    label: label,
    spacing: spacing,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: SuperTabIndicatorKind.underline,
        label: 'Soulignement (Underline)',
        icon: Icons.horizontal_rule,
      ),
      EditorSegmentOption(
        value: SuperTabIndicatorKind.box,
        label: 'Pilule / Boîte remplie (Box)',
        icon: Icons.check_box_outline_blank,
      ),
      EditorSegmentOption(
        value: SuperTabIndicatorKind.none,
        label: 'Aucun indicateur',
        icon: Icons.block,
      ),
    ],
  );

  /// Preset pour le type de valeur [SuperValueKind].
  static EditorSegmentedField<SuperValueKind> valueKind({
    required Key buttonKey,
    required SuperValueKind value,
    required ValueChanged<SuperValueKind> onChanged,
    String? label = 'Type de valeur',
    bool shortLabels = false,
  }) => EditorSegmentedField<SuperValueKind>(
    buttonKey: buttonKey,
    label: label,
    value: value,
    onChanged: onChanged,
    options: [
      const EditorSegmentOption(
        value: SuperValueKind.text,
        label: 'Texte',
        icon: Icons.text_fields,
      ),
      EditorSegmentOption(
        value: SuperValueKind.checkbox,
        label: shortLabels ? 'Checkbox' : 'Case à cocher (Checkbox)',
        icon: Icons.check_box_outlined,
      ),
      EditorSegmentOption(
        value: SuperValueKind.switchControl,
        label: shortLabels ? 'Switch' : 'Interrupteur (Switch)',
        icon: Icons.toggle_on_outlined,
      ),
    ],
  );

  /// Preset pour le mode de valeur [SuperValueMode].
  static EditorSegmentedField<SuperValueMode> valueMode({
    required Key buttonKey,
    required SuperValueMode value,
    required ValueChanged<SuperValueMode> onChanged,
    String? label = 'Mode',
  }) => EditorSegmentedField<SuperValueMode>(
    buttonKey: buttonKey,
    label: label,
    value: value,
    onChanged: onChanged,
    options: const [
      EditorSegmentOption(
        value: SuperValueMode.display,
        label: 'Affichage',
        icon: Icons.visibility_outlined,
      ),
      EditorSegmentOption(
        value: SuperValueMode.input,
        label: 'Saisie',
        icon: Icons.edit_outlined,
      ),
    ],
  );

  /// Clé appliquée au [SegmentedButton] interne.
  final Key? buttonKey;

  /// Titre optionnel affiché au-dessus du bouton segmenté.
  final String? label;

  /// Sous-titre optionnel affiché sous [label].
  final String? subtitle;

  /// Espacement vertical entre le titre et le bouton segmenté.
  final double spacing;

  /// Valeur actuellement sélectionnée.
  final T value;

  /// Liste des segments proposés.
  final List<EditorSegmentOption<T>> options;

  /// Callback appelé lorsqu'un segment est sélectionné.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final button = SegmentedButton<T>(
      key: buttonKey,
      showSelectedIcon: false,
      style: editorCompactSegmentButtonStyle,
      segments: [for (final option in options) option.toButtonSegment()],
      selected: {value},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) {
          onChanged(selected.first);
        }
      },
    );
    if (label == null && subtitle == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: spacing,
      children: [
        if (label != null) Text(label!, style: editorSegmentFieldLabelStyle),
        if (subtitle != null)
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        button,
      ],
    );
  }
}

/// Interrupteur [SwitchListTile] standardisé sans marge horizontale interne
/// (`contentPadding: EdgeInsets.zero`).
class EditorSwitchTile extends StatelessWidget {
  /// Crée un [EditorSwitchTile].
  const EditorSwitchTile({
    this.tileKey,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.dense,
    this.secondary,
    super.key,
  });

  final Key? tileKey;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool? dense;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: tileKey,
    dense: dense,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null ? Text(subtitle!) : null,
    secondary: secondary,
    value: value,
    onChanged: onChanged,
  );
}
