import 'package:flutter/widgets.dart';

import '../../components/super_layout/slot_implementation.dart';

/// Keeps code-provided slots reachable after an editor inserts a parent.
class ProvidedSlotScope extends InheritedWidget {
  const ProvidedSlotScope({
    required this.slots,
    required super.child,
    super.key,
  });

  final List<SlotImplementation> slots;

  static SlotImplementation? find(BuildContext context, String id) {
    SlotImplementation? result;
    context.visitAncestorElements((element) {
      if (element.widget case final ProvidedSlotScope scope) {
        result = scope.slots.where((slot) => slot.id == id).firstOrNull;
      }
      return result == null;
    });
    return result;
  }

  @override
  bool updateShouldNotify(ProvidedSlotScope oldWidget) =>
      slots != oldWidget.slots;
}
