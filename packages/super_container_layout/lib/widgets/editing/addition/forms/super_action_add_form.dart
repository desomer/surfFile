/// Formulaire de configuration initiale ([SuperActionAddForm]) lors de l'ajout d'un [SuperAction].
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_action_config.dart';
import '../../components/shared/editor_segmented_field.dart';
import '../../components/super_action_editor.dart';
import '../../icons/material_icon_picker.dart';
import '../component_add_wizard.dart';
import 'add_form_common.dart';

double? _parse(String text) => parseAddFormDouble(text);

/// Formulaire de paramétrage initial d'un [SuperAction] dans l'assistant d'ajout.
class SuperActionAddForm extends StatefulWidget {
  const SuperActionAddForm({
    required this.draft,
    required this.onChanged,
    required this.availableFontFamilies,
    super.key,
  });

  final SuperActionConfig draft;
  final ValueChanged<SuperActionConfig> onChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperActionAddForm> createState() => _SuperActionAddFormState();
}

class _SuperActionAddFormState extends State<SuperActionAddForm>
    with DraftAddFormStateMixin {
  Future<void> _more() => openAdvancedDraftEditor(
    () => showSuperActionEditor(
      context: context,
      config: widget.draft,
      availableFontFamilies: widget.availableFontFamilies,
    ),
    widget.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final inTabZone =
        ComponentAddTargetScope.maybeOf(context)?.isTabZone ?? false;
    final effectiveVariant = draft.effectiveVariant(inTab: inTabZone);
    return buildRevisionSubtree(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorSegmentedField.actionKind(
            buttonKey: const ValueKey('add-action-kind'),
            label: null,
            textAndIconLabel: 'Texte + Icône',
            value: draft.kind,
            onChanged: (kind) => widget.onChanged(draft.copyWith(kind: kind)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<SuperActionVariant>(
            key: const ValueKey('add-action-variant'),
            isExpanded: true,
            initialValue: effectiveVariant,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Style / variante du bouton',
            ),
            items: const [
              DropdownMenuItem(
                value: SuperActionVariant.filled,
                child: Text('Filled (plein)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.tonal,
                child: Text('Tonal (secondaire)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.elevated,
                child: Text('Elevated (élevé)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.outlined,
                child: Text('Outlined (contour)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.text,
                child: Text('Text (sans fond)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.icon,
                child: Text('Icon Button'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.surface,
                child: Text('Surface personnalisée'),
              ),
            ],
            onChanged: (variant) {
              if (variant != null) {
                widget.onChanged(draft.copyWith(variant: variant));
              }
            },
          ),
          if (draft.kind.hasText)
            TextFormField(
              key: const ValueKey('add-action-label'),
              initialValue: draft.label,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Libellé du bouton',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(label: value)),
            ),
          if (draft.kind.hasIcon)
            MaterialIconPickerField(
              key: const ValueKey('add-action-icon'),
              label: 'Icône',
              nullable: true,
              isDense: true,
              showId: false,
              value: draft.icon.trim().isEmpty
                  ? null
                  : (SuperActionIcons.isKnown(draft.icon)
                        ? draft.icon
                        : 'touch_app'),
              onChanged: (icon) =>
                  widget.onChanged(draft.copyWith(icon: icon ?? '')),
            ),
          TextFormField(
            key: const ValueKey('add-action-font-size'),
            initialValue: draft.fontSize?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Taille du texte (vide : héritée)',
            ),
            onChanged: (value) {
              final size = _parse(value);
              widget.onChanged(
                value.trim().isEmpty
                    ? draft.copyWith(inheritFontSize: true)
                    : draft.copyWith(fontSize: size ?? -1),
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('add-action-more'),
              onPressed: _more,
              icon: const Icon(Icons.tune),
              label: const Text('Plus d’options…'),
            ),
          ),
        ],
      ),
    );
  }
}
