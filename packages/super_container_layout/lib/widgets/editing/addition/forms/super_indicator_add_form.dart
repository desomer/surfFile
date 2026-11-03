/// Formulaire de configuration initiale ([SuperIndicatorAddForm]) lors de l'ajout d'un [SuperIndicator].
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_indicator_config.dart';
import '../../components/super_indicator_editor.dart';
import '../../icons/material_icon_picker.dart';
import 'add_form_common.dart';

double? _parse(String text) => parseAddFormDouble(text);

/// Formulaire de paramétrage initial d'un [SuperIndicator] dans l'assistant d'ajout.
class SuperIndicatorAddForm extends StatefulWidget {
  const SuperIndicatorAddForm({
    required this.draft,
    required this.onChanged,
    required this.availableFontFamilies,
    super.key,
  });

  final SuperIndicatorConfig draft;
  final ValueChanged<SuperIndicatorConfig> onChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperIndicatorAddForm> createState() => _SuperIndicatorAddFormState();
}

class _SuperIndicatorAddFormState extends State<SuperIndicatorAddForm>
    with DraftAddFormStateMixin {
  Future<void> _more() => openAdvancedDraftEditor(
    () => showSuperIndicatorEditor(
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
          MaterialIconPickerField(
            key: const ValueKey('add-indicator-icon'),
            label: 'Icône par défaut',
            nullable: true,
            isDense: true,
            showId: false,
            value: draft.icon.trim().isEmpty
                ? null
                : (SuperIndicatorIcons.isKnown(draft.icon)
                      ? draft.icon
                      : 'info'),
            onChanged: (icon) =>
                widget.onChanged(draft.copyWith(icon: icon ?? '')),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('add-indicator-icon-size'),
            initialValue: draft.iconSize?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Taille de l’icône (vide : 24 px)',
            ),
            onChanged: (value) {
              final size = _parse(value);
              widget.onChanged(
                value.trim().isEmpty
                    ? draft.copyWith(inheritIconSize: true)
                    : draft.copyWith(iconSize: size ?? -1),
              );
            },
          ),
          TextFormField(
            key: const ValueKey('add-indicator-label'),
            initialValue: draft.label,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Libellé optionnel (badge / statut)',
            ),
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(label: value)),
          ),
          TextFormField(
            key: const ValueKey('add-indicator-tooltip'),
            initialValue: draft.tooltip,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Infobulle (tooltip)',
            ),
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(tooltip: value)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('add-indicator-more'),
              onPressed: _more,
              icon: const Icon(Icons.tune),
              label: const Text('Plus d’options & États…'),
            ),
          ),
        ],
      ),
    );
  }
}
