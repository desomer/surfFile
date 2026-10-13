import 'package:material_ui/material_ui.dart';

import '../../models/super_layout_config.dart';
import '../../super_app.dart';
import 'slot_implementation.dart';
import 'super_layout.dart';

/// Editable layout backed by the application's registry when one is available.
class RegisteredSuperLayout extends StatelessWidget {
  const RegisteredSuperLayout({
    required this.id,
    required this.config,
    required this.label,
    this.slots = const [],
    this.zoneLabels = const {},
    this.onSlotAdded = SuperLayout.defaultSlotAddition,
    super.key,
  });

  final String id;
  final SuperLayoutConfig config;
  final String label;
  final List<SlotImplementation> slots;
  final Map<SuperLayoutZone, String> zoneLabels;
  final SlotAddedCallback onSlotAdded;

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    
    Widget layout(SuperLayoutConfig value,
        ValueChanged<SuperLayoutConfig>? onChanged) => SuperLayout(
      config: value,
      slots: slots,
      label: label,
      zoneLabels: zoneLabels,
      onChanged: onChanged,
      onSlotAdded: onSlotAdded,
    );

    if (registry == null) return layout(config, null);
    final controller = registry.layoutController(id, fallback: config);
    return ValueListenableBuilder<SuperLayoutConfig>(
      valueListenable: controller,
      builder: (context, value, _) =>
          layout(value, (value) => controller.value = value),
    );
  }
}
