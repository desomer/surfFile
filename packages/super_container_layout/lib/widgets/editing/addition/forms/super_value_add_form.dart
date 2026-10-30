import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_value_config.dart';
import '../../components/super_value_editor.dart';

double? _parse(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

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

class _SuperValueAddFormState extends State<SuperValueAddForm> {
  /// Recreates the text fields after the full editor changed the draft.
  int _revision = 0;

  Future<void> _more() async {
    final result = await showSuperValueEditor(
      context: context,
      config: widget.draft,
      availableFontFamilies: widget.availableFontFamilies,
    );
    if (result == null || !mounted) return;
    setState(() => _revision++);
    widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final input = draft.mode == SuperValueMode.input;
    return KeyedSubtree(
      key: ValueKey(_revision),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SuperValueKind>(
            key: const ValueKey('add-value-kind'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: SuperValueKind.text,
                tooltip: 'Texte',
                icon: Icon(Icons.text_fields, size: 16),
                label: Text('Texte'),
              ),
              ButtonSegment(
                value: SuperValueKind.checkbox,
                tooltip: 'Checkbox',
                icon: Icon(Icons.check_box_outlined, size: 16),
                label: Text('Checkbox'),
              ),
              ButtonSegment(
                value: SuperValueKind.switchControl,
                tooltip: 'Switch',
                icon: Icon(Icons.toggle_on_outlined, size: 16),
                label: Text('Switch'),
              ),
            ],
            selected: {draft.kind},
            onSelectionChanged: (value) {
              final kind = value.single;
              widget.onChanged(
                draft.copyWith(
                  kind: kind,
                  obscureText: kind.isBoolean ? false : draft.obscureText,
                  minLines: kind.isBoolean ? 1 : draft.minLines,
                  maxLines: kind.isBoolean ? 1 : draft.maxLines,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<SuperValueMode>(
            key: const ValueKey('add-value-mode'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: SuperValueMode.display,
                tooltip: 'Affichage',
                icon: Icon(Icons.visibility_outlined, size: 16),
                label: Text('Affichage'),
              ),
              ButtonSegment(
                value: SuperValueMode.input,
                tooltip: 'Saisie',
                icon: Icon(Icons.edit_outlined, size: 16),
                label: Text('Saisie'),
              ),
            ],
            selected: {draft.mode},
            onSelectionChanged: (value) {
              final mode = value.single;
              widget.onChanged(
                draft.copyWith(
                  mode: mode,
                  obscureText: mode == SuperValueMode.display
                      ? false
                      : draft.obscureText,
                ),
              );
            },
          ),
          if (draft.kind.isBoolean)
            SwitchListTile(
              key: const ValueKey('add-value-initial-bool'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Valeur initiale'),
              value: draft.initialBool,
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(initialBool: value)),
            )
          else if (!draft.obscureText)
            TextFormField(
              key: const ValueKey('add-value-initial'),
              initialValue: draft.initialText,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Texte initial',
              ),
              onChanged: (value) {
                final lines = '\n'.allMatches(value).length + 1;
                widget.onChanged(
                  draft.copyWith(
                    initialText: value,
                    maxLines: math.max(draft.maxLines, lines),
                  ),
                );
              },
            ),
          if (input || draft.kind.isBoolean) ...[
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
