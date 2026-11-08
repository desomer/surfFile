/// Formulaire de configuration initiale ([SuperSeparatorAddForm]) lors de l'ajout d'un [SuperSeparator].
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_separator_config.dart';
import '../../components/shared/editor_segmented_field.dart';
import '../../components/super_separator_editor.dart';
import 'add_form_common.dart';

double? _parse(String text) => parseAddFormDouble(text);

/// Formulaire de paramétrage initial d'un [SuperSeparator] dans l'assistant d'ajout.
class SuperSeparatorAddForm extends StatefulWidget {
  const SuperSeparatorAddForm({
    required this.draft,
    required this.onChanged,
    required this.availableFontFamilies,
    super.key,
  });

  final SuperSeparatorConfig draft;
  final ValueChanged<SuperSeparatorConfig> onChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperSeparatorAddForm> createState() => _SuperSeparatorAddFormState();
}

class _SuperSeparatorAddFormState extends State<SuperSeparatorAddForm>
    with DraftAddFormStateMixin {
  Future<void> _more() => openAdvancedDraftEditor(
    () => showSuperSeparatorEditor(
      context: context,
      config: widget.draft,
      availableFontFamilies: widget.availableFontFamilies,
    ),
    widget.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return buildRevisionSubtree(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorSegmentedField.separatorKind(
            buttonKey: const ValueKey('add-separator-kind'),
            label: null,
            value: draft.kind,
            onChanged: (kind) => widget.onChanged(draft.copyWith(kind: kind)),
          ),
          const SizedBox(height: 8),
          EditorSegmentedField.axis(
            buttonKey: const ValueKey('add-separator-axis'),
            label: null,
            value: draft.axis,
            onChanged: (axis) => widget.onChanged(draft.copyWith(axis: axis)),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('add-separator-extent'),
            initialValue: draft.extent.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              isDense: true,
              labelText: draft.axis == Axis.horizontal
                  ? 'Hauteur / espace (px)'
                  : 'Largeur / espace (px)',
            ),
            onChanged: (value) {
              final extent = _parse(value);
              widget.onChanged(draft.copyWith(extent: extent ?? -1));
            },
          ),
          if (draft.kind.isDivider)
            TextFormField(
              key: const ValueKey('add-separator-thickness'),
              initialValue: draft.thickness.toString(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Épaisseur du trait (px)',
              ),
              onChanged: (value) {
                final thickness = _parse(value);
                widget.onChanged(draft.copyWith(thickness: thickness ?? -1));
              },
            ),
          TextFormField(
            key: const ValueKey('add-separator-label'),
            initialValue: draft.label,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Libellé optionnel (vide : sans texte)',
            ),
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(label: value)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('add-separator-more'),
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
