import 'package:material_ui/material_ui.dart';

import '../../../models/scaffold_page_config.dart';
import '../../../models/component_tag_filter.dart';
import '../../../super_app.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_layout/slot_implementation.dart';

/// Native Scaffold adapter; editing behavior lives in [NativeComponentEditor].
class ScaffoldPageLayout extends StatefulWidget {
  const ScaffoldPageLayout({
    required this.id,
    this.label = 'Page',
    this.menuIcon,
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
  final IconData? menuIcon;
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
    NativeRegion('body', 'Corps', required: true, editableFlow: true),
    NativeRegion('drawer', 'Drawer gauche', editableFlow: true),
    NativeRegion('endDrawer', 'Drawer droit', editableFlow: true),
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
      editableFlow: true,
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
      else
        BuilderSlot(
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
    final height = slots.fold<double>(slots.isEmpty ? kToolbarHeight : 0, (
      sum,
      slot,
    ) {
      final height = editor.preferredSizeFor(slot)?.height;
      return sum +
          (height != null && height.isFinite ? height : kToolbarHeight);
    });
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

  Widget _body(
    ScaffoldPageConfig config,
    NativeComponentEditorState editor,
  ) {
    final scrollAxis = config.scrollDirection;
    final paddingValue = config.scrollPadding;
    final padding = paddingValue != null && paddingValue > 0
        ? EdgeInsets.all(paddingValue)
        : EdgeInsets.zero;
    return switch (config.bodyMode) {
      ScaffoldBodyMode.standard => SizedBox.expand(
        child: editor.region('body'),
      ),
      ScaffoldBodyMode.singleChildScrollView => SizedBox.expand(
        child: ScrollViewportHost(
          padding: padding,
          child: SingleChildScrollView(
            key: const ValueKey('scaffold-page-single-child-scroll-view'),
            scrollDirection: scrollAxis,
            reverse: config.reverse,
            primary: config.primary,
            padding: padding == EdgeInsets.zero ? null : padding,
            clipBehavior: config.clipBehavior ?? Clip.hardEdge,
            child: SlotContentFitScope(
              fitWidth: scrollAxis == Axis.horizontal,
              fitHeight: scrollAxis == Axis.vertical,
              child: editor.region('body'),
            ),
          ),
        ),
      ),
      ScaffoldBodyMode.customScrollView => () {
        final bodySliver = editor.sliverRegion(
          'body',
          scrollDirection: scrollAxis,
          fillWhenEmpty: true,
        );
        return SizedBox.expand(
          child: ScrollViewportHost(
            padding: padding,
            child: editor.regionOverlay(
              'body',
              child: CustomScrollView(
                key: const ValueKey('scaffold-page-custom-scroll-view'),
                scrollDirection: scrollAxis,
                reverse: config.reverse,
                primary: config.primary,
                clipBehavior: config.clipBehavior ?? Clip.hardEdge,
                slivers: [
                  if (editor.visible('appBar'))
                    editor.sliverRegion(
                      'appBar',
                      scrollDirection: scrollAxis,
                    ),
                  if (padding != EdgeInsets.zero)
                    SliverPadding(padding: padding, sliver: bodySliver)
                  else
                    bodySliver,
                ],
              ),
            ),
          ),
        );
      }(),
    };
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
          id: widget.id,
          label: widget.label,
          menuType: 'Page',
          menuIcon: widget.menuIcon,
          keyPrefix: 'scaffold-page',
          settingsTitle: 'Configurer la page',
          config: config.native,
          onChanged: (value) =>
              controller.value = ScaffoldPageConfig.fromNative(value),
          regions: _regions,
          slots: _providedSlots(),
          registry: registry,
          propertyDescriptors: ScaffoldPageConfig.propertyDescriptors,
          isPropertyAvailable: (nativeConfig, descriptor) =>
              descriptor.id == 'bodyMode' ||
              descriptor.id == 'extendBody' ||
              descriptor.id == 'extendBodyBehindAppBar' ||
              ScaffoldBodyMode.fromName(
                    nativeConfig.stringProperty('bodyMode'),
                  ) !=
                  ScaffoldBodyMode.standard,
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
              for (final slot in [
                ...editor.slotsFor('appBar'),
                ...editor.slotsFor('bottomNavigationBar'),
              ])
                if (slot case NativePreferredSizeWidget native)
                  native.sizeListenable(context),
            ]),
            builder: (context, _) => Scaffold(
              key: _scaffoldKey,
              extendBody: config.extendBody,
              extendBodyBehindAppBar: config.extendBodyBehindAppBar,
              appBar: config.bodyMode == ScaffoldBodyMode.customScrollView
                  ? null
                  : _appBar(editor),
              body: _body(config, editor),
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
