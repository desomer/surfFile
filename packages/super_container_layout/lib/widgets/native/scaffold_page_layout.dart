  import 'package:material_ui/material_ui.dart';

import '../models/scaffold_page_config.dart';
import '../models/component_tag_filter.dart';
import '../super_app.dart';
import 'native_component_editor.dart';
import 'super_layout/slot_implementation.dart';

/// Native Scaffold adapter; editing behavior lives in [NativeComponentEditor].
class ScaffoldPageLayout extends StatefulWidget {
  const ScaffoldPageLayout({
    required this.id,
    this.label = 'Page',
    required this.config,
    required this.slots,
    required this.appBar,
    required this.body,
    required this.drawer,
    required this.endDrawer,
    required this.bottomNavigationBar,
    required this.floatingActionButton,
    required this.bottomSheet,
    super.key,
  });

  final String id;
  final String label;
  final ScaffoldPageConfig config;
  final List<SlotImplementation> slots;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? bottomSheet;

  @override
  State<ScaffoldPageLayout> createState() => _ScaffoldPageLayoutState();
}

class _ScaffoldPageLayoutState extends State<ScaffoldPageLayout> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final _localConfig = ValueNotifier(widget.config);

  static const _regions = [
    NativeRegion(
      'appBar',
      'AppBar',
      tagFilter: ComponentTagFilter(include: {'appBar'}),
    ),
    NativeRegion('body', 'Corps', required: true),
    NativeRegion('drawer', 'Drawer gauche'),
    NativeRegion('endDrawer', 'Drawer droit'),
    NativeRegion(
      'bottomNavigationBar',
      'Barre basse',
      tagFilter: ComponentTagFilter(include: {'bottomNavigationBar'}),
      expand: false,
      fillSize: Size.fromHeight(kBottomNavigationBarHeight),
    ),
    NativeRegion(
      'floatingActionButton',
      'Bouton flottant',
      expand: false,
      stretch: false,
      emptySize: Size.square(56),
      fillSize: Size.square(56),
    ),
    NativeRegion(
      'bottomSheet',
      'Panneau bas',
      expand: false,
      fillSize: Size.fromHeight(kBottomNavigationBarHeight),
    ),
  ];

  List<SlotImplementation> _providedSlots() => [
    if (widget.appBar case final bar?)
      if (bar is NativePreferredSizeWidget)
        NativeWidgetSlot(
          id: 'scaffold:appBar',
          label: 'AppBar',
          tags: const {'appBar'},
          child: bar,
        )
      else BuilderSlot(
        id: 'scaffold:appBar',
        label: 'AppBar',
        tags: const {'appBar'},
        sizing: SlotSizing.intrinsic,
        preferredSize: bar.preferredSize,
        builder: (_) => bar,
      ),
    BuilderSlot(
      id: 'scaffold:body',
      label: 'Body',
      builder: (_) => widget.body,
    ),
    if (widget.drawer case final drawer?)
      BuilderSlot(
        id: 'scaffold:drawer',
        label: 'Drawer',
        builder: (_) =>
            drawer is Drawer ? drawer.child ?? const SizedBox() : drawer,
      ),
    if (widget.endDrawer case final drawer?)
      BuilderSlot(
        id: 'scaffold:endDrawer',
        label: 'End drawer',
        builder: (_) =>
            drawer is Drawer ? drawer.child ?? const SizedBox() : drawer,
      ),
    if (widget.bottomNavigationBar case final bar?)
      BuilderSlot(
        id: 'scaffold:bottomNavigationBar',
        label: 'Bottom navigation bar',
        tags: const {'bottomNavigationBar'},
        sizing: SlotSizing.intrinsic,
        builder: (_) => bar,
      ),
    if (widget.floatingActionButton case final button?)
      BuilderSlot(
        id: 'scaffold:floatingActionButton',
        label: 'Floating action button',
        sizing: SlotSizing.intrinsic,
        builder: (_) => button,
      ),
    if (widget.bottomSheet case final sheet?)
      BuilderSlot(
        id: 'scaffold:bottomSheet',
        label: 'Bottom sheet',
        sizing: SlotSizing.intrinsic,
        builder: (_) => sheet,
      ),
    ...widget.slots,
  ];

  void _openDrawer(String region) {
    if (region == 'drawer') {
      _scaffoldKey.currentState?.openDrawer();
    } else {
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  PreferredSizeWidget? _appBar(NativeComponentEditorState editor) {
    if (!editor.visible('appBar')) return null;
    final slots = editor.slotsFor('appBar');
    final height = slots.fold<double>(
      slots.isEmpty ? kToolbarHeight : 0,
      (sum, slot) {
        final height = editor.preferredSizeFor(slot)?.height;
        return sum + (height != null && height.isFinite ? height : kToolbarHeight);
      },
    );
    return PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: editor.region('appBar'),
    );
  }

  Widget? _drawer(
    String region,
    NativeComponentEditorState editor,
    Widget? template,
  ) {
    if (!editor.visible(region)) return null;
    final content = editor.region(region);
    if (template is Drawer) {
      return Drawer(
        backgroundColor: template.backgroundColor,
        elevation: template.elevation,
        shadowColor: template.shadowColor,
        surfaceTintColor: template.surfaceTintColor,
        shape: template.shape,
        width: template.width,
        semanticLabel: template.semanticLabel,
        clipBehavior: template.clipBehavior,
        child: content,
      );
    }
    if (template != null &&
        editor.slotsFor(region).length == 1 &&
        !editor.editing) {
      return template;
    }
    return Drawer(child: content);
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller =
        registry?.scaffoldPageController(widget.id, fallback: widget.config) ??
        _localConfig;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final config = controller.value;
        return NativeComponentEditor(
          label: widget.label,
          keyPrefix: 'scaffold-page',
          settingsTitle: 'Configurer la page',
          config: config.native,
          onChanged: (value) =>
              controller.value = ScaffoldPageConfig.fromNative(value),
          regions: _regions,
          slots: _providedSlots(),
          registry: registry,
          onConfigured: (regions) {
            final drawer = regions
                .where((id) => id == 'drawer' || id == 'endDrawer')
                .lastOrNull;
            if (drawer != null) _openDrawer(drawer);
          },
          regionActions: (region) => [
            if (region == 'body')
              for (final drawer in [
                ScaffoldPageRegion.drawer,
                ScaffoldPageRegion.endDrawer,
              ])
                if (config.isEnabled(drawer))
                  IconButton(
                    key: ValueKey('scaffold-page-open-${drawer.name}'),
                    tooltip:
                        'Ouvrir ${drawer == ScaffoldPageRegion.drawer ? 'Drawer gauche' : 'Drawer droit'}',
                    icon: Icon(
                      drawer == ScaffoldPageRegion.drawer
                          ? Icons.menu
                          : Icons.menu_open,
                    ),
                    onPressed: () => _openDrawer(drawer.name),
                  ),
          ],
          builder: (context, editor) => ListenableBuilder(
            listenable: Listenable.merge([
              for (final slot in editor.slotsFor('appBar'))
                if (slot case NativePreferredSizeWidget native) native.sizeListenable(context),
            ]),
            builder: (context, _) => Scaffold(
            key: _scaffoldKey,
            appBar: _appBar(editor),
            body: SizedBox.expand(child: editor.region('body')),
            drawer: _drawer('drawer', editor, widget.drawer),
            endDrawer: _drawer('endDrawer', editor, widget.endDrawer),
            bottomNavigationBar: editor.visible('bottomNavigationBar')
                ? editor.region('bottomNavigationBar')
                : null,
            floatingActionButton: editor.visible('floatingActionButton')
                ? editor.region('floatingActionButton')
                : null,
            bottomSheet: editor.visible('bottomSheet')
                ? editor.region('bottomSheet')
                : null,
          ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _localConfig.dispose();
    super.dispose();
  }
}
