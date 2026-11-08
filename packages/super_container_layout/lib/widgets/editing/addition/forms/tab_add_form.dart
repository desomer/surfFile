/// Formulaire de configuration initiale ([TabAddForm]) lors de l'ajout d'un [SuperTab].
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_tab_config.dart';
import '../../components/shared/editor_segmented_field.dart';

/// Formulaire de paramétrage initial d'un [SuperTab] dans l'assistant d'ajout.
class TabAddForm extends StatelessWidget {
  const TabAddForm({required this.draft, required this.onChanged, super.key});

  final SuperTabConfig draft;
  final ValueChanged<SuperTabConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDynamic = draft.mode == SuperTabMode.dynamic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        EditorSegmentedField.tabMode(
          buttonKey: const ValueKey('add-tab-mode'),
          spacing: 12,
          value: draft.mode,
          onChanged: (mode) => onChanged(draft.copyWith(mode: mode)),
        ),
        EditorSegmentedField.tabBarPosition(
          buttonKey: const ValueKey('add-tab-position'),
          spacing: 12,
          value: draft.tabBarPosition,
          onChanged: (pos) => onChanged(draft.copyWith(tabBarPosition: pos)),
        ),
        EditorSegmentedField.tabIndicatorKind(
          buttonKey: const ValueKey('add-tab-indicator-kind'),
          spacing: 12,
          value: draft.indicatorKind,
          onChanged: (kind) => onChanged(draft.copyWith(indicatorKind: kind)),
        ),
        EditorSwitchTile(
          tileKey: const ValueKey('add-tab-scrollable'),
          title: 'Onglets défilables',
          value: draft.isScrollable,
          onChanged: (value) => onChanged(draft.copyWith(isScrollable: value)),
        ),
        if (isDynamic) ...[
          EditorSwitchTile(
            tileKey: const ValueKey('add-tab-allow-add'),
            title: 'Autoriser l’ajout d’onglet',
            value: draft.allowAdd,
            onChanged: (value) => onChanged(draft.copyWith(allowAdd: value)),
          ),
          EditorSwitchTile(
            tileKey: const ValueKey('add-tab-allow-remove'),
            title: 'Autoriser la suppression d’onglet',
            value: draft.allowRemove,
            onChanged: (value) => onChanged(draft.copyWith(allowRemove: value)),
          ),
        ],
      ],
    );
  }
}
