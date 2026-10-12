import 'package:material_ui/material_ui.dart';

import 'models/super_layout_config.dart';
import 'widgets/super_layout/registered_super_layout.dart';
import 'widgets/super_layout/slot_implementation.dart';

/// App bar with editable title and action layout zones.
class SuperAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SuperAppBar({
    this.id = 'root-appBar',
    this.title,
    this.action,
    this.slots = const [],
    this.config,
    super.key,
  });

  final String id;
  final Widget? title;
  final Widget? action;
  final List<SlotImplementation> slots;
  final SuperLayoutConfig? config;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: preferredSize.height,
    child: AppBar(
      titleSpacing: 0,
      title: SizedBox(
        height: preferredSize.height,
        child: RegisteredSuperLayout(
          id: id,
          label: 'Super app bar',
          zoneLabels: const {
            SuperLayoutZone.center: 'title',
            SuperLayoutZone.east: 'action',
          },
          config: config ?? SuperLayoutConfig(
            north: false,
            south: false,
            west: false,
            eastSize: 48,
            autoSides: const {SuperLayoutZone.east},
            zoneAxes: const {SuperLayoutZone.east: Axis.horizontal},
            placements: {
              if (title != null) SuperLayoutZone.center: const ['title'],
              if (action != null) SuperLayoutZone.east: const ['action'],
            },
          ),
          slots: [
            if (title case final content?)
              BuilderSlot(
                id: 'title',
                label: 'title',
                builder: (_) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: content,
                ),
              ),
            if (action case final content?)
              BuilderSlot(
                id: 'action',
                label: 'action',
                sizing: SlotSizing.intrinsic,
                builder: (_) => content,
              ),
            ...slots,
          ],
        ),
      ),
    ),
  );
}
