import 'package:material_ui/material_ui.dart';

import '../../../../models/super_tab_config.dart';

class TabAddForm extends StatelessWidget {
  const TabAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final SuperTabConfig draft;
  final ValueChanged<SuperTabConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDynamic = draft.mode == SuperTabMode.dynamic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        DropdownButtonFormField<SuperTabMode>(
          key: const ValueKey('add-tab-mode'),
          initialValue: draft.mode,
          decoration: const InputDecoration(labelText: 'Mode des onglets'),
          items: const [
            DropdownMenuItem(
              value: SuperTabMode.static,
              child: Text('Statique (onglets fixes)'),
            ),
            DropdownMenuItem(
              value: SuperTabMode.dynamic,
              child: Text('Dynamique (tableau JSON du repository)'),
            ),
          ],
          onChanged: (mode) {
            if (mode != null) onChanged(draft.copyWith(mode: mode));
          },
        ),
        DropdownButtonFormField<SuperTabBarPosition>(
          key: const ValueKey('add-tab-position'),
          initialValue: draft.tabBarPosition,
          decoration: const InputDecoration(
            labelText: 'Position de la barre d’onglets',
          ),
          items: const [
            DropdownMenuItem(
              value: SuperTabBarPosition.top,
              child: Text('En haut'),
            ),
            DropdownMenuItem(
              value: SuperTabBarPosition.bottom,
              child: Text('En bas'),
            ),
          ],
          onChanged: (pos) {
            if (pos != null) onChanged(draft.copyWith(tabBarPosition: pos));
          },
        ),
        SwitchListTile(
          key: const ValueKey('add-tab-scrollable'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Onglets défilables'),
          value: draft.isScrollable,
          onChanged: (value) => onChanged(draft.copyWith(isScrollable: value)),
        ),
        if (isDynamic) ...[
          SwitchListTile(
            key: const ValueKey('add-tab-allow-add'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Autoriser l’ajout d’onglet'),
            value: draft.allowAdd,
            onChanged: (value) => onChanged(draft.copyWith(allowAdd: value)),
          ),
          SwitchListTile(
            key: const ValueKey('add-tab-allow-remove'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Autoriser la suppression d’onglet'),
            value: draft.allowRemove,
            onChanged: (value) =>
                onChanged(draft.copyWith(allowRemove: value)),
          ),
        ],
      ],
    );
  }
}
