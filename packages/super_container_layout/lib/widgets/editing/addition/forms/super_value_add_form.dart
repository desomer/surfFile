/// Formulaire de configuration initiale ([SuperValueAddForm]) lors de l'ajout d'un [SuperValue].
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_choice_config.dart';
import '../../../../models/super_value_config.dart';
import '../../components/shared/editor_segmented_field.dart';
import '../../components/super_value_editor.dart';
import 'add_form_common.dart';

double? _parse(String text) => parseAddFormDouble(text);

/// Formulaire de paramétrage initial d'un [SuperValue] dans l'assistant d'ajout.
class SuperValueAddForm extends StatefulWidget {
  const SuperValueAddForm({
    required this.draft,
    required this.onChanged,
    required this.availableFontFamilies,
    super.key,
  });

  final SuperValueConfig draft;
  final ValueChanged<SuperValueConfig> onChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperValueAddForm> createState() => _SuperValueAddFormState();
}

class _SuperValueAddFormState extends State<SuperValueAddForm>
    with DraftAddFormStateMixin {
  Future<void> _more() => openAdvancedDraftEditor(
    () => showSuperValueEditor(
      context: context,
      config: widget.draft,
      availableFontFamilies: widget.availableFontFamilies,
    ),
    widget.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final input = draft.mode == SuperValueMode.input;
    return buildRevisionSubtree(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorSegmentedField.valueKind(
            buttonKey: const ValueKey('add-value-kind'),
            label: null,
            shortLabels: true,
            value: draft.kind,
            onChanged: (kind) => widget.onChanged(
              draft.copyWith(
                kind: kind,
                mode: kind.isChoice ? SuperValueMode.input : draft.mode,
                obscureText: !kind.isText ? false : draft.obscureText,
                minLines: !kind.isText ? 1 : draft.minLines,
                maxLines: !kind.isText ? 1 : draft.maxLines,
                choice: kind.isChoice && draft.choice.options.isEmpty
                    ? draft.choice.copyWith(
                        options: SuperChoiceConfig.defaultFallbackOptions,
                      )
                    : draft.choice,
              ),
            ),
          ),
          if (draft.kind.isChoice) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<ChoiceVariant>(
              key: ValueKey('add-value-choice-variant-${draft.choice.variant.name}'),
              initialValue: draft.choice.variant,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Type de composant de choix',
              ),
              items: [
                for (final variant in ChoiceVariant.values)
                  DropdownMenuItem(
                    value: variant,
                    child: Text(
                      variant.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (variant) {
                if (variant == null) return;
                widget.onChanged(
                  draft.copyWith(
                    choice: draft.choice.copyWith(variant: variant),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          EditorSegmentedField.valueMode(
            buttonKey: const ValueKey('add-value-mode'),
            label: null,
            value: draft.mode,
            onChanged: (mode) => widget.onChanged(
              draft.copyWith(
                mode: mode,
                obscureText: mode == SuperValueMode.display
                    ? false
                    : draft.obscureText,
              ),
            ),
          ),
          if (draft.kind.isBoolean)
            EditorSwitchTile(
              tileKey: const ValueKey('add-value-initial-bool'),
              dense: true,
              title: 'Valeur initiale',
              value: draft.initialBool,
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(initialBool: value)),
            )
          else if (!draft.obscureText)
            TextFormField(
              key: const ValueKey('add-value-initial'),
              initialValue: draft.initialText,
              minLines: 1,
              maxLines: draft.kind.isChoice ? 1 : 3,
              keyboardType: draft.kind.isChoice
                  ? TextInputType.text
                  : TextInputType.multiline,
              decoration: InputDecoration(
                isDense: true,
                labelText: draft.kind.isChoice
                    ? 'Valeur initiale sélectionnée'
                    : 'Texte initial',
              ),
              onChanged: (value) {
                final lines = draft.kind.isChoice
                    ? 1
                    : '\n'.allMatches(value).length + 1;
                widget.onChanged(
                  draft.copyWith(
                    initialText: value,
                    maxLines: draft.kind.isChoice
                        ? 1
                        : math.max(draft.maxLines, lines),
                  ),
                );
              },
            ),
          if (input || draft.kind.isBoolean || draft.kind.isChoice) ...[
            TextFormField(
              key: const ValueKey('add-value-label'),
              initialValue: draft.label,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Libellé du champ',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(label: value)),
            ),
            if (!draft.kind.isBoolean)
              TextFormField(
                key: const ValueKey('add-value-placeholder'),
                initialValue: draft.placeholder,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Texte indicatif',
                ),
                onChanged: (value) =>
                    widget.onChanged(draft.copyWith(placeholder: value)),
              ),
          ],
          TextFormField(
            key: const ValueKey('add-value-font-size'),
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
          const SizedBox(height: 8),
          SegmentedButton<TextAlign>(
            key: const ValueKey('add-value-align'),
            segments: const [
              ButtonSegment(
                value: TextAlign.start,
                tooltip: 'Aligner à gauche',
                icon: Icon(Icons.format_align_left),
              ),
              ButtonSegment(
                value: TextAlign.center,
                tooltip: 'Centrer',
                icon: Icon(Icons.format_align_center),
              ),
              ButtonSegment(
                value: TextAlign.end,
                tooltip: 'Aligner à droite',
                icon: Icon(Icons.format_align_right),
              ),
            ],
            selected: {
              switch (draft.textAlign) {
                TextAlign.center => TextAlign.center,
                TextAlign.end || TextAlign.right => TextAlign.end,
                _ => TextAlign.start,
              },
            },
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(textAlign: value.single)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('add-value-more'),
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
