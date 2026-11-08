/// Contrat et utilitaires partagés pour les composants Material natifs ([NativePreferredSizeWidget]).
///
/// Fournit la résolution des slots par région et l'adaptation des [SuperAction] en destinations.
library;

import 'package:material_ui/material_ui.dart';

import '../super_action.dart';
import '../super_layout/slot_implementation.dart';

/// Builds an ID-keyed map of supplied [SuperAction] destinations.
Map<String, SuperAction> suppliedActionDestinationMap(
  Iterable<SuperAction> destinations, [
  List<SlotImplementation> extraSlots = const [],
  BuildContext? context,
]) {
  final actions = <String, SuperAction>{
    for (final action in destinations) action.id: action,
  };
  if (context != null) {
    for (final slot in extraSlots) {
      if (slot is BuilderSlot) {
        try {
          final built = slot.builder(context);
          if (built is SuperAction) {
            actions.putIfAbsent(slot.id, () => built);
            if (built.id.isNotEmpty) {
              actions.putIfAbsent(built.id, () => built);
            }
          }
        } on Object {
          // Ignore les builders dependant d'un InheritedWidget non monte.
        }
      }
    }
  }
  return actions;
}

/// Wraps supplied [SuperAction] destinations as [BuilderSlot]s followed by [extraSlots].
List<SlotImplementation> buildActionDestinationSlots(
  Iterable<SuperAction> destinations,
  List<SlotImplementation> extraSlots,
) => [
  for (final action in destinations)
    BuilderSlot(
      id: action.id,
      label: action.config.label,
      tags: const {'action', 'button', 'input'},
      sizing: SlotSizing.intrinsic,
      builder: (_) => action,
    ),
  ...extraSlots,
];

/// Computes target and effective heights for bottom bars accounting for system bottom inset.
({double targetHeight, double effectiveHeight}) resolveBottomBarHeights(
  BoxConstraints constraints,
  double baseHeight,
  double bottomPadding,
) {
  final targetHeight = constraints.hasTightHeight
      ? constraints.maxHeight
      : (baseHeight + bottomPadding).clamp(
          constraints.minHeight,
          constraints.maxHeight,
        );
  final resolvedHeight = targetHeight - bottomPadding;
  final effectiveHeight = resolvedHeight.isFinite && resolvedHeight > 0
      ? resolvedHeight
      : baseHeight;
  return (targetHeight: targetHeight, effectiveHeight: effectiveHeight);
}
