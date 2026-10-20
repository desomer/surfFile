import 'package:material_ui/material_ui.dart';

import 'models/scaffold_page_config.dart';
import 'widgets/editing/overlay/editor_zoom.dart';
import 'widgets/native/scaffold_page_layout.dart';
import 'widgets/super_layout/slot_implementation.dart';

/// Page whose editable regions map directly to the native [Scaffold] slots.
class SuperPage extends StatelessWidget {
  const SuperPage({
    this.id = 'root',
    this.label = 'Page',
    this.menuIcon,
    this.child = const SizedBox.shrink(),
    this.appBar,
    this.drawer,
    this.endDrawer,
    this.bottomBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.bottomSheet,
    this.slots = const [],
    this.pageConfig,
    this.maxAutoZoomExtent = EditorZoom.defaultMaxAutoZoomExtent,
    super.key,
  }) : assert(
         bottomBar == null || bottomNavigationBar == null,
         'Use either bottomBar or bottomNavigationBar, not both.',
       );

  /// Stable persistence key. Use a different ID for each page.
  final String id;
  final String label;
  final IconData? menuIcon;
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? drawer;
  final Widget? endDrawer;

  /// Compatibility alias for [bottomNavigationBar].
  final Widget? bottomBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? bottomSheet;
  final List<SlotImplementation> slots;

  /// Initial native Scaffold region placement; persisted edits take precedence.
  final ScaffoldPageConfig? pageConfig;

  /// Taille (px) à partir de laquelle une sélection n'est plus zoomée en mode édition.
  final double maxAutoZoomExtent;

  @override
  Widget build(BuildContext context) {
    final resolvedConfig = pageConfig ?? ScaffoldPageConfig(
          placements: {
            if (appBar != null)
              ScaffoldPageRegion.appBar: const ['scaffold:appBar'],
            ScaffoldPageRegion.body: const ['scaffold:body'],
            if (drawer != null)
              ScaffoldPageRegion.drawer: const ['scaffold:drawer'],
            if (endDrawer != null)
              ScaffoldPageRegion.endDrawer: const ['scaffold:endDrawer'],
            if (bottomNavigationBar != null || bottomBar != null)
              ScaffoldPageRegion.bottomNavigationBar: const [
                'scaffold:bottomNavigationBar',
              ],
            if (floatingActionButton != null)
              ScaffoldPageRegion.floatingActionButton: const [
                'scaffold:floatingActionButton',
              ],
            if (bottomSheet != null)
              ScaffoldPageRegion.bottomSheet: const ['scaffold:bottomSheet'],
          },
        );
    return EditorZoom(
      maxAutoZoomExtent: maxAutoZoomExtent,
      child: ScaffoldPageLayout(
        id: id,
        label: label,
        menuIcon: menuIcon,
        config: resolvedConfig,
        slots: slots,
        appBar: appBar,
        body: child,
        drawer: drawer,
        endDrawer: endDrawer,
        bottomNavigationBar: bottomNavigationBar ?? bottomBar,
        floatingActionButton: floatingActionButton,
        bottomSheet: bottomSheet,
      ),
    );
  }
}
