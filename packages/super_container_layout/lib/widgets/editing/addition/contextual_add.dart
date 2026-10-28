import 'package:material_ui/material_ui.dart';

import '../../../super_app.dart';
import '../history/editor_history.dart';
import 'component_add_wizard.dart';
import 'insertion_plan.dart';

/// Opens the add wizard with positions relative to the edited element and its
/// parents, and with the zones of the containers holding it. [levels] are
/// ordered from the element to the outermost container.
///
/// Only registry components are offered: they are the only ones every level
/// can resolve.
Future<void> showContextualAddWizard(
  BuildContext context,
  List<ContextualAddLevel> levels, {
  BuildContext? target,
}) async {
  final registry = SuperApp.maybeOf(context)?.registry;
  if (registry == null || levels.isEmpty) return;
  final actions = <String, Future<void> Function(InsertedComponent)>{};
  final placements = <ComponentAddPlacement>[];
  var relativeIndex = 0;
  var zoneIndex = 0;
  // Levels go outwards: a title already used names an enclosing container.
  final titles = <String, int>{};
  String unique(String title) {
    final count = titles[title] = (titles[title] ?? 0) + 1;
    return switch (count) {
      1 => title,
      2 => '$title (parent)',
      _ => '$title (parent ${count - 1})',
    };
  }

  for (final level in levels) {
    switch (level) {
      case EditorSlotInsertion():
        final index = relativeIndex++;
        final group = unique(level.label);
        for (final mode in InsertMode.values) {
          for (final direction in InsertDirection.values) {
            final plan = planInsertion(level.host, direction, mode);
            if (plan == null) continue;
            final id = '$index-${mode.name}-${direction.name}';
            actions[id] = (component) => level.insert(plan, component);
            placements.add(
              ComponentAddPlacement(
                id: id,
                group: group,
                label: mode == InsertMode.beside
                    ? direction.label
                    : 'À la place, pousse ${direction.pushLabel}',
                icon: mode == InsertMode.beside
                    ? direction.icon
                    : direction.pushIcon,
                hint: plan.hint,
                accepts: plan is WrapInsertion ? null : level.acceptsTags,
                // The wrapper's center zone is dedicated to nothing.
                zoneTags: plan is WrapInsertion ? const {} : level.zoneTags,
              ),
            );
          }
        }
      case EditorAddZoneGroup():
        final index = zoneIndex++;
        final group = unique('Dans ${level.label}');
        for (final zone in level.zones) {
          final id = 'z$index-${zone.id}';
          actions[id] = zone.insert;
          placements.add(
            ComponentAddPlacement(
              id: id,
              group: group,
              label: zone.label,
              icon: Icons.add_box_outlined,
              hint: zone.hint ?? 'À la fin de la zone ${zone.label}',
              accepts: zone.accept,
              zoneTags: zone.zoneTags,
            ),
          );
        }
    }
  }
  if (placements.isEmpty) return;
  final candidates = [
    for (final entry in registry.components.entries)
      if (context.mounted && (entry.value.isAvailable?.call(context) ?? true))
        ComponentAddCandidate(
          id: 'component:${entry.value.slotId ?? entry.key}',
          label: entry.value.label,
          tags: entry.value.tags,
          placementTags: entry.value.placementTags,
          configurator: entry.value.addConfigurator,
          previewBuilder: entry.value.previewBuilder,
        ),
    for (final entry in registry.registry.entries)
      ComponentAddCandidate(
        id: 'factory:${entry.key}',
        label: entry.value.label ?? entry.key,
        tags: entry.value.tags,
        placementTags: entry.value.placementTags,
        configurator: entry.value.addConfigurator,
        previewBuilder: entry.value.previewBuilder,
      ),
  ];
  final first = levels.first;
  final request = await showComponentAddWizard(
    context: context,
    target: target,
    title: switch (first) {
      EditorSlotInsertion(:final label) => 'Ajouter près de $label',
      EditorAddZoneGroup(:final label) => 'Ajouter dans $label',
    },
    keyPrefix: 'contextual',
    candidates: [
      for (final candidate in candidates)
        if (placements.any((option) => option.admits(candidate))) candidate,
    ],
    placements: placements,
  );
  if (request == null || !context.mounted) return;
  final insert = actions[request.placementId]!;
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  try {
    await insert(
      InsertedComponent(
        type: request.component.id,
        label: request.label,
        size: request.size,
        configure: (id) => request.applyConfiguration(registry, id),
      ),
    );
  } finally {
    history?.commitTransaction();
  }
}
