import 'package:material_ui/material_ui.dart';

import '../../../../models/super_action_config.dart';
import '../../components/super_action_editor.dart';
import '../../icons/material_icon_picker.dart';

double? _parse(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

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

class _SuperActionAddFormState extends State<SuperActionAddForm> {
  int _revision = 0;

  Future<void> _more() async {
    final result = await showSuperActionEditor(
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
    return KeyedSubtree(
      key: ValueKey(_revision),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SuperActionKind>(
            key: const ValueKey('add-action-kind'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: SuperActionKind.text,
                tooltip: 'Texte',
                icon: Icon(Icons.text_fields, size: 16),
                label: Text('Texte'),
              ),
              ButtonSegment(
                value: SuperActionKind.icon,
                tooltip: 'Icône',
                icon: Icon(Icons.interests_outlined, size: 16),
                label: Text('Icône'),
              ),
              ButtonSegment(
                value: SuperActionKind.textAndIcon,
                tooltip: 'Texte + Icône',
                icon: Icon(Icons.smart_button_outlined, size: 16),
                label: Text('Texte + Icône'),
              ),
            ],
            selected: {draft.kind},
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(kind: value.single)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<SuperActionVariant>(
            key: const ValueKey('add-action-variant'),
            isExpanded: true,
            initialValue: draft.variant,
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
