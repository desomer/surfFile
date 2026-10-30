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
        const Text(
          'Mode des onglets',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        SegmentedButton<SuperTabMode>(
          key: const ValueKey('add-tab-mode'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(
              value: SuperTabMode.static,
              tooltip: 'Statique (onglets fixes)',
              icon: Icon(Icons.tab, size: 16),
              label: Text(
                'Statique (onglets fixes)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment(
              value: SuperTabMode.dynamic,
              tooltip: 'Dynamique (tableau JSON du repository)',
              icon: Icon(Icons.dynamic_feed, size: 16),
              label: Text(
                'Dynamique (tableau JSON du repository)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: {draft.mode},
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) {
              onChanged(draft.copyWith(mode: selected.first));
            }
          },
        ),
        const Text(
          'Position de la barre d’onglets',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        SegmentedButton<SuperTabBarPosition>(
          key: const ValueKey('add-tab-position'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(
              value: SuperTabBarPosition.top,
              tooltip: 'En haut',
              icon: Icon(Icons.vertical_align_top, size: 16),
              label: Text('En haut', overflow: TextOverflow.ellipsis),
            ),
            ButtonSegment(
              value: SuperTabBarPosition.bottom,
              tooltip: 'En bas',
              icon: Icon(Icons.vertical_align_bottom, size: 16),
              label: Text('En bas', overflow: TextOverflow.ellipsis),
            ),
          ],
          selected: {draft.tabBarPosition},
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) {
              onChanged(draft.copyWith(tabBarPosition: selected.first));
            }
          },
        ),
        const Text(
          'Style de l’indicateur',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        SegmentedButton<SuperTabIndicatorKind>(
          key: const ValueKey('add-tab-indicator-kind'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(
              value: SuperTabIndicatorKind.underline,
              tooltip: 'Soulignement (Underline)',
              icon: Icon(Icons.horizontal_rule, size: 16),
              label: Text(
                'Soulignement (Underline)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment(
              value: SuperTabIndicatorKind.box,
              tooltip: 'Pilule / Boîte remplie (Box)',
              icon: Icon(Icons.check_box_outline_blank, size: 16),
              label: Text(
                'Pilule / Boîte remplie (Box)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment(
              value: SuperTabIndicatorKind.none,
              tooltip: 'Aucun indicateur',
              icon: Icon(Icons.block, size: 16),
              label: Text('Aucun indicateur', overflow: TextOverflow.ellipsis),
            ),
          ],
          selected: {draft.indicatorKind},
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) {
              onChanged(draft.copyWith(indicatorKind: selected.first));
            }
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
