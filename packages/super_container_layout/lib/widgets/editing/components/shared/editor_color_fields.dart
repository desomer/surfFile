/// Contrôles de couleurs, champs numériques/hexadécimaux et cartes d'aperçu
/// partagés entre les éditeurs de composants (`SuperAction`, `SuperValue`,
/// `SuperIndicator`, `SuperSeparator`, `SuperTab`).
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/json_text_binding.dart';
import '../../../../theme/theme_color.dart';
import '../../../../services/repositories/json_list_scope.dart';
import '../../../../services/repositories/json_repository_store.dart';
import '../../repositories/repository_binding_fields.dart';
import '../../styles/container_style_editor.dart' show styleColorTile;

final RegExp _hexColorPattern = RegExp(r'^[0-9a-fA-F]{8}$');

/// Formate une [Color] nullable en chaîne hexadécimale AARRGGBB de 8 caractères.
String formatEditorColorHex(Color? color) => color == null
    ? ''
    : color is ThemeColor
    ? color.toJson()
    : color.toARGB32().toRadixString(16).padLeft(8, '0');

/// Analyse une chaîne hexadécimale AARRGGBB issue d'un [TextEditingController].
Color? parseEditorColorHex(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('theme:')) return ThemeColor.fromJson(trimmed);
  if (!_hexColorPattern.hasMatch(trimmed)) {
    throw const FormatException('Couleur AARRGGBB à 8 chiffres requise.');
  }
  return Color(int.parse(trimmed, radix: 16));
}

/// Analyse un nombre décimal issu d'un [TextEditingController].
double? parseEditorNumberField(
  String text, {
  bool allowZero = false,
  bool allowNegative = false,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final value = double.tryParse(trimmed.replaceAll(',', '.'));
  if (value == null ||
      !value.isFinite ||
      (!allowNegative && (allowZero ? value < 0 : value <= 0))) {
    throw const FormatException('Valeur numérique invalide.');
  }
  return value;
}

/// Construit un [TextFormField] standard d'éditeur de propriétés (texte,
/// nombre décimal ou couleur hexadécimale 8 caractères).
Widget buildEditorSettingTextField({
  required Key fieldKey,
  required TextEditingController controller,
  required String label,
  bool numeric = false,
  bool allowZero = false,
  bool allowNegative = false,
  bool colorHex = false,
  String invalidColorMessage =
      'Couleur AARRGGBB à 8 chiffres hexadécimaux requise.',
}) => TextFormField(
  key: fieldKey,
  controller: controller,
  keyboardType: numeric
      ? const TextInputType.numberWithOptions(decimal: true)
      : TextInputType.text,
  decoration: InputDecoration(labelText: label),
  validator: (raw) {
    final value = raw?.trim() ?? '';
    if (numeric && value.isNotEmpty) {
      final number = double.tryParse(value.replaceAll(',', '.'));
      if (number == null ||
          !number.isFinite ||
          (!allowNegative && (allowZero ? number < 0 : number <= 0))) {
        return 'Valeur numérique valide requise.';
      }
    } else if (colorHex &&
        value.isNotEmpty &&
        !isEditorColorValue(value)) {
      return invalidColorMessage;
    }
    return null;
  },
);

/// Indique si une saisie contient une couleur AARRGGBB ou un rôle de thème connu.
bool isEditorColorValue(String value) {
  if (_hexColorPattern.hasMatch(value)) return true;
  if (!value.startsWith('theme:')) return false;
  return ThemeColorRole.values.any((role) => value == 'theme:${role.name}');
}

/// Empile verticalement une liste de widgets avec un espacement uniforme (12 px par défaut).
Widget buildEditorFieldGroup(List<Widget> children, {double spacing = 12}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          children[i],
        ],
      ],
    );

/// Carte d'aperçu standard affichée en haut d'un [StyleEditorPanel].
class ComponentEditorPreviewCard extends StatelessWidget {
  /// Crée une [ComponentEditorPreviewCard].
  const ComponentEditorPreviewCard({
    required this.cardKey,
    required this.child,
    this.minHeight = 100,
    this.alignment = Alignment.center,
    super.key,
  });

  final Key cardKey;
  final Widget child;
  final double minHeight;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: cardKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              constraints: BoxConstraints(minHeight: minHeight),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              alignment: alignment,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Enrobe un contrôle de propriété avec un bouton de liaison repository
/// ([RepositoryBoundPropertyTile]) et ouvre [showRepositoryBindingDialog] au clic.
class EditablePropertyBindingScope<TProperty extends Enum> {
  /// Crée un [EditablePropertyBindingScope].
  const EditablePropertyBindingScope({
    required this.context,
    required this.componentPrefix,
    required this.allowBinding,
    required this.repositories,
    required this.listScope,
    required this.bindings,
    required this.onBindingsChanged,
  });

  final BuildContext context;
  final String componentPrefix;
  final bool allowBinding;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final Map<TProperty, JsonTextBinding> bindings;
  final ValueChanged<Map<TProperty, JsonTextBinding>> onBindingsChanged;

  /// Ouvre la boîte de dialogue de liaison pour [property].
  Future<void> editBinding(TProperty property, String label) async {
    final result = await showRepositoryBindingDialog(
      context: context,
      title: 'Lier $label',
      keyPrefix: '$componentPrefix-property-${property.name}',
      pathHint: 'client.${property.name}',
      binding: bindings[property],
      store: repositories,
      listScope: listScope,
      helper: 'Lecture seule : la valeur du repository remplace ce paramètre.',
    );
    if (result == null || !context.mounted) return;
    final next = Map<TProperty, JsonTextBinding>.of(bindings);
    if (result.binding == null) {
      next.remove(property);
    } else {
      next[property] = result.binding!;
    }
    onBindingsChanged(next);
  }

  /// Enrobe [child] dans une [RepositoryBoundPropertyTile] pour [property].
  Widget wrap(TProperty property, String label, Widget child) {
    final binding = bindings[property];
    final canBind = allowBinding && repositories != null;
    return RepositoryBoundPropertyTile(
      buttonKey: ValueKey('$componentPrefix-bind-${property.name}'),
      keyPrefix: '$componentPrefix-bind-${property.name}',
      binding: binding,
      tooltip: binding != null
          ? 'Modifier la liaison de $label'
          : 'Lier $label à un repository',
      onPressed: !canBind ? null : () => editBinding(property, label),
      onClear: !canBind || binding == null
          ? null
          : () {
              final next = Map<TProperty, JsonTextBinding>.of(bindings)
                ..remove(property);
              onBindingsChanged(next);
            },
      child: child,
    );
  }
}

/// Sélecteur de couleur combinant `styleColorTile`, un champ texte hexadécimal
/// `AARRGGBB` liant éventuellement une propriété repository et un bouton de
/// retour à la couleur du thème/parent.
class BoundHexColorField extends StatelessWidget {
  /// Crée un [BoundHexColorField].
  const BoundHexColorField({
    required this.controller,
    required this.label,
    required this.fallbackColor,
    required this.pickerKey,
    required this.fieldKey,
    required this.inheritButtonKey,
    required this.onChanged,
    this.fieldLabel,
    this.resetButtonLabel = 'Utiliser la couleur du thème',
    this.disableResetWhenEmpty = true,
    this.alignResetRight = true,
    this.wrapField,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final Color fallbackColor;
  final Key pickerKey;
  final Key fieldKey;
  final Key inheritButtonKey;
  final VoidCallback onChanged;
  final String? fieldLabel;
  final String resetButtonLabel;
  final bool disableResetWhenEmpty;
  final bool alignResetRight;
  final Widget Function(Widget field)? wrapField;

  @override
  Widget build(BuildContext context) {
    final raw = controller.text.trim();
    final current = isEditorColorValue(raw)
        ? parseEditorColorHex(raw)!
        : fallbackColor;
    final textField = buildEditorSettingTextField(
      fieldKey: fieldKey,
      controller: controller,
      label: fieldLabel ?? '$label AARRGGBB / theme:rôle (vide = thème)',
      colorHex: true,
    );
    final resetButton = TextButton(
      key: inheritButtonKey,
      onPressed: disableResetWhenEmpty && raw.isEmpty
          ? null
          : () {
              controller.clear();
              onChanged();
            },
      child: Text(resetButtonLabel),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        styleColorTile(
          label,
          current,
          (color) {
            controller.text = formatEditorColorHex(color);
            onChanged();
          },
          key: pickerKey,
          onClear: () {
            controller.clear();
            onChanged();
          },
        ),
        wrapField != null ? wrapField!(textField) : textField,
        if (alignResetRight)
          Align(alignment: Alignment.centerRight, child: resetButton)
        else
          resetButton,
      ],
    );
  }
}

/// Tuile de couleur [styleColorTile] accompagnée d'un bouton de remise à la
/// valeur du thème lorsque [isOverridden] vaut `true`.
class ThemeResetColorTile extends StatelessWidget {
  /// Crée une [ThemeResetColorTile].
  const ThemeResetColorTile({
    required this.label,
    required this.effectiveColor,
    required this.isOverridden,
    required this.onChanged,
    required this.onClear,
    required this.resetLabel,
    this.tileKey,
    super.key,
  });

  final String label;
  final Color effectiveColor;
  final bool isOverridden;
  final ValueChanged<Color> onChanged;
  final VoidCallback onClear;
  final String resetLabel;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      styleColorTile(
        label,
        effectiveColor,
        onChanged,
        key: tileKey,
        onClear: onClear,
      ),
      if (isOverridden)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onClear, child: Text(resetLabel)),
        ),
    ],
  );
}

/// Construit la liste standard des champs de boîte (rayon, épaisseur de
/// bordure, élévation et marges internes H/V) partagée entre `SuperAction` et
/// `SuperIndicator`.
List<Widget> buildComponentBoxDimensionFields<TProperty extends Enum>({
  required EditablePropertyBindingScope<TProperty> bindingScope,
  required Widget Function(
    String key,
    String label, {
    bool numeric,
    bool allowZero,
  })
  buildField,
  required TProperty radiusProperty,
  required TProperty borderWidthProperty,
  required TProperty elevationProperty,
  String radiusLabel = 'Rayon des coins (vide = thème)',
  String borderWidthLabel = 'Épaisseur de bordure (vide = thème)',
  String elevationLabel = 'Élévation (vide = thème)',
}) => [
  bindingScope.wrap(
    radiusProperty,
    'le rayon',
    buildField('radius', radiusLabel, numeric: true, allowZero: true),
  ),
  bindingScope.wrap(
    borderWidthProperty,
    'l’épaisseur de bordure',
    buildField('borderWidth', borderWidthLabel, numeric: true, allowZero: true),
  ),
  bindingScope.wrap(
    elevationProperty,
    'l’élévation',
    buildField('elevation', elevationLabel, numeric: true, allowZero: true),
  ),
  Row(
    children: [
      Expanded(
        child: buildField(
          'horizontalPadding',
          'Marge interne H (px)',
          numeric: true,
          allowZero: true,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: buildField(
          'verticalPadding',
          'Marge interne V (px)',
          numeric: true,
          allowZero: true,
        ),
      ),
    ],
  ),
];
