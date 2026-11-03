/// Formulaire de configuration initiale ([SuperSeparatorAddForm]) lors de l'ajout d'un [SuperSeparator].
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_separator_config.dart';
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
          SegmentedButton<SuperSeparatorKind>(
            key: const ValueKey('add-separator-kind'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: SuperSeparatorKind.divider,
                tooltip: 'Divider (trait)',
                icon: Icon(Icons.horizontal_rule, size: 16),
                label: Text('Divider (trait)'),
              ),
              ButtonSegment(
                value: SuperSeparatorKind.spacer,
                tooltip: 'Spacer (espace)',
                icon: Icon(Icons.space_bar, size: 16),
                label: Text('Spacer (espace)'),
              ),
            ],
            selected: {draft.kind},
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(kind: value.single)),
          ),
          const SizedBox(height: 8),
          SegmentedButton<Axis>(
            key: const ValueKey('add-separator-axis'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: Axis.horizontal,
                tooltip: 'Horizontal',
                icon: Icon(Icons.swap_horiz, size: 16),
                label: Text('Horizontal'),
              ),
              ButtonSegment(
                value: Axis.vertical,
                tooltip: 'Vertical',
                icon: Icon(Icons.swap_vert, size: 16),
                label: Text('Vertical'),
              ),
            ],
            selected: {draft.axis},
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(axis: value.single)),
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
