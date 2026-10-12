import 'package:material_ui/material_ui.dart';

import 'models/super_layout_config.dart';
import 'widgets/editing/editor_zoom.dart';
import 'widgets/super_layout/registered_super_layout.dart';
import 'widgets/super_layout/slot_implementation.dart';

/// Page with editable appBar, body and bottomBar layout zones.
class SuperPage extends StatelessWidget {
  const SuperPage({
    this.id = 'root',
    this.child = const SizedBox.shrink(),
    this.appBar,
    this.bottomBar,
    this.slots = const [],
    this.config,
    super.key,
  });

  /// Stable persistence key. Use a different ID for each page.
  final String id;
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomBar;
  final List<SlotImplementation> slots;

  /// Initial layout; registry preferences take precedence when available.
  final SuperLayoutConfig? config;

  @override
  Widget build(BuildContext context) => EditorZoom(
    child: Scaffold(
      body: RegisteredSuperLayout(
        id: id,
        label: 'Super page',
        zoneLabels: const {
          SuperLayoutZone.north: 'appBar',
          SuperLayoutZone.center: 'body',
          SuperLayoutZone.south: 'bottomBar',
        },
        config:
            config ??
            SuperLayoutConfig(
              west: false,
              east: false,
              northSize: kToolbarHeight,
              southSize: kBottomNavigationBarHeight,
              autoSides: const {SuperLayoutZone.north, SuperLayoutZone.south},
              placements: {
                if (appBar != null) SuperLayoutZone.north: const ['appBar'],
                SuperLayoutZone.center: const ['body'],
                if (bottomBar != null)
                  SuperLayoutZone.south: const ['bottomBar'],
              },
            ),
        slots: [
          if (appBar case final bar?)
            BuilderSlot(
              id: 'appBar',
              label: 'appBar',
              sizing: SlotSizing.intrinsic,
              builder: (_) =>
                  SizedBox(height: bar.preferredSize.height, child: bar),
            ),
          BuilderSlot(id: 'body', label: 'body', builder: (_) => child),
          if (bottomBar case final bar?)
            BuilderSlot(
              id: 'bottomBar',
              label: 'bottomBar',
              sizing: SlotSizing.intrinsic,
              builder: (_) => bar,
            ),
          ...slots,
        ],
      ),
    ),
  );
}
