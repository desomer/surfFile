/// Assemblage de la structure `Scaffold` d'une page ou d'un shell ([ScaffoldPageLayout]).
///
/// Monte les régions `appBar`, `body`, `sidebarStart`, `sidebarEnd`, `drawer`,
/// `endDrawer`, `bottomNavigationBar`, `floatingActionButton` et `bottomSheet`,
/// ainsi que le slot `scaffold:outlet` pour les shells partagés.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../super_component.dart';

import '../../../models/responsive_layout_config.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/component_tag_filter.dart';
import '../../../super_app.dart';
import '../../appearance/appearance_scope.dart';
import '../../editing/components/native_component_editor.dart';
import '../responsive_page_container.dart';
import '../super_layout/slot_implementation.dart';

/// Native Scaffold adapter; editing behavior lives in [NativeComponentEditor].
class ScaffoldPageLayout extends SuperStatefulComponent<ScaffoldPageConfig> {
  const ScaffoldPageLayout({
    required this.id,
    this.label = 'Page',
    this.menuIcon,
    required this.config,
    required this.slots,
    required this.appBar,
    required this.body,
    this.sidebarStart,
    this.sidebarEnd,
    this.outlet,
    required this.drawer,
    required this.endDrawer,
    required this.bottomNavigationBar,
    required this.floatingActionButton,
    required this.bottomSheet,
    this.responsiveLayout,
    super.behaviours,
    super.key,
  });

  @override
  final String id;
  final String label;
  final IconData? menuIcon;
  @override
  final ScaffoldPageConfig config;
  final List<SlotImplementation> slots;
  final PreferredSizeWidget? appBar;
  final Widget body;

  /// Widget fourni par défaut pour la région latérale gauche (`sidebarStart`).
  final Widget? sidebarStart;

  /// Widget fourni par défaut pour la région latérale droite (`sidebarEnd`).
  final Widget? sidebarEnd;

  /// Contenu de route enfant exposé via le slot `'scaffold:outlet'` dans `body`.
  final Widget? outlet;

  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? bottomSheet;

  /// Configuration responsive explicite ; `null` résout depuis [AppearanceScope].
  final ResponsiveLayoutConfig? responsiveLayout;

  @override
  State<ScaffoldPageLayout> createState() => _ScaffoldPageLayoutState();
}

class _ScaffoldPageLayoutState extends State<ScaffoldPageLayout> {
  static const double _defaultSidebarStartWidth = 240.0;
  static const double _defaultSidebarEndWidth = 280.0;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final _localConfig = ValueNotifier(widget.config);

  @override
  void didUpdateWidget(ScaffoldPageLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != oldWidget.config) {
      _localConfig.value = widget.config;
    }
  }

  static const _regions = [
    NativeRegion(
      'appBar',
      'AppBar',
      tagFilter: ComponentTagFilter(include: {'appBar'}),
    ),
    NativeRegion('body', 'Corps', required: true, editableFlow: true),
    NativeRegion(
      'sidebarStart',
      'Menu gauche',
      axis: Axis.vertical,
      expand: true,
      editableFlow: true,
      emptySize: Size(_defaultSidebarStartWidth, double.infinity),
    ),
    NativeRegion(
      'sidebarEnd',
      'Panneau droit',
      axis: Axis.vertical,
      expand: true,
      editableFlow: true,
      emptySize: Size(_defaultSidebarEndWidth, double.infinity),
    ),
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
    if (widget.outlet case final outlet?)
      BuilderSlot(
        id: 'scaffold:outlet',
        label: 'Contenu de la page',
        builder: (_) => outlet,
      ),
    if (widget.sidebarStart case final sidebar?)
      if (sidebar is NativePreferredSizeWidget)
        NativeWidgetSlot(
          id: 'scaffold:sidebarStart',
          label: 'Menu gauche',
          sizing: SlotSizing.fill,
          child: sidebar,
        )
      else
        BuilderSlot(
          id: 'scaffold:sidebarStart',
          label: 'Menu gauche',
          builder: (_) => sidebar,
        ),
    if (widget.sidebarEnd case final sidebar?)
      if (sidebar is NativePreferredSizeWidget)
        NativeWidgetSlot(
          id: 'scaffold:sidebarEnd',
          label: 'Panneau droit',
          sizing: SlotSizing.fill,
          child: sidebar,
        )
      else
        BuilderSlot(
          id: 'scaffold:sidebarEnd',
          label: 'Panneau droit',
          builder: (_) => sidebar,
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

  double _resolveSidebarWidth(
    String region,
    double? configuredWidth,
    NativeComponentEditorState editor,
    double fallbackWidth,
  ) {
    if (configuredWidth != null && configuredWidth.isFinite) {
      return configuredWidth;
    }
    final regionSlots = editor.slotsFor(region);
    if (regionSlots.isEmpty) return fallbackWidth;
    double? maxPreferredWidth;
    var allHaveFiniteWidth = true;
    for (final slot in regionSlots) {
      final width = editor.preferredSizeFor(slot)?.width;
      if (width != null && width.isFinite && width > 0) {
        maxPreferredWidth = maxPreferredWidth == null
            ? width
            : math.max(maxPreferredWidth, width);
      } else {
        allHaveFiniteWidth = false;
      }
    }
    if (allHaveFiniteWidth && maxPreferredWidth != null) {
      return maxPreferredWidth;
    }
    return maxPreferredWidth != null
        ? math.max(maxPreferredWidth, fallbackWidth)
        : fallbackWidth;
  }

  Widget _buildSidebar(
    String region,
    double? configuredWidth,
    NativeComponentEditorState editor,
    double fallbackWidth,
  ) {
    final width = _resolveSidebarWidth(
      region,
      configuredWidth,
      editor,
      fallbackWidth,
    );
    return SizedBox(width: width, child: editor.region(region));
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

  ResponsiveLayoutConfig _resolveResponsiveLayout(BuildContext context) {
    if (widget.responsiveLayout != null) return widget.responsiveLayout!;
    final appearance = AppearanceScope.controllerOf(context)?.value;
    if (appearance == null) return const ResponsiveLayoutConfig();
    for (final page in appearance.pageCatalog.pages) {
      if (page.id == widget.id && page.pageType.isModal) {
        return appearance.responsiveLayout.copyWith(
          containerMode: PageContainerMode.fullPage,
        );
      }
    }
    return appearance.effectiveResponsiveLayoutForPage(widget.id);
  }

  Widget _body(
    BuildContext context,
    ScaffoldPageConfig config,
    NativeComponentEditorState editor,
    ResponsiveLayoutConfig responsiveConfig,
  ) {
    final scrollAxis = config.scrollDirection;
    final paddingValue = config.scrollPadding;
    final padding = paddingValue != null && paddingValue > 0
        ? EdgeInsets.all(paddingValue)
        : EdgeInsets.zero;
    final fallbackOutletSlot =
        widget.outlet != null && editor.slotsFor('body').isEmpty
        ? BuilderSlot(
            id: 'scaffold:outlet',
            label: 'Contenu de la page',
            builder: (_) => widget.outlet!,
          )
        : null;
    Widget bodyRegion() => editor.region('body', item: fallbackOutletSlot);
    return switch (config.bodyMode) {
      ScaffoldBodyMode.standard => SizedBox.expand(
        child: ResponsiveBodyContainer(
          config: responsiveConfig,
          child: bodyRegion(),
        ),
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
            child: ResponsiveBodyContainer(
              config: responsiveConfig,
              scrollable: true,
              scrollDirection: scrollAxis,
              child: SlotContentFitScope(
                fitWidth: scrollAxis == Axis.horizontal,
                fitHeight: scrollAxis == Axis.vertical,
                child: bodyRegion(),
              ),
            ),
          ),
        ),
      ),
      ScaffoldBodyMode.customScrollView => () {
        final rawBodySliver = fallbackOutletSlot != null
            ? SliverFillRemaining(child: widget.outlet!)
            : editor.sliverRegion(
                'body',
                scrollDirection: scrollAxis,
                fillWhenEmpty: true,
              );
        final bodySliver =
            responsiveConfig.containerMode == PageContainerMode.fullPage
            ? (padding != EdgeInsets.zero
                  ? SliverPadding(padding: padding, sliver: rawBodySliver)
                  : rawBodySliver)
            : SliverLayoutBuilder(
                builder: (context, sliverConstraints) {
                  final resolved = responsiveConfig.resolveForWidth(
                    sliverConstraints.crossAxisExtent,
                  );
                  if (!resolved.isConstrained ||
                      scrollAxis != Axis.vertical) {
                    final effectivePadding = scrollAxis == Axis.horizontal
                        ? padding +
                              EdgeInsets.symmetric(horizontal: resolved.gutter)
                        : padding;
                    return effectivePadding != EdgeInsets.zero
                        ? SliverPadding(
                            padding: effectivePadding,
                            sliver: rawBodySliver,
                          )
                        : rawBodySliver;
                  }
                  final availableWidth = sliverConstraints.crossAxisExtent;
                  final containerWidth = math.min(
                    availableWidth,
                    resolved.maxWidth!,
                  );
                  final outerMargin = math.max(
                    0.0,
                    (availableWidth - containerWidth) / 2,
                  );
                  final safeGutter = math.min(
                    resolved.gutter,
                    math.max(0.0, containerWidth / 2),
                  );
                  final horizontalInset = outerMargin + safeGutter;
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left + horizontalInset,
                      padding.top,
                      padding.right + horizontalInset,
                      padding.bottom,
                    ),
                    sliver: rawBodySliver,
                  );
                },
              );
        return SizedBox.expand(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              return ResponsiveBreakpointScope(
                layout: responsiveConfig.resolveForWidth(width),
                viewportWidth: width,
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
                        bodySliver,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }(),
    };
  }

  Widget _buildScaffold(
    BuildContext context,
    ScaffoldPageConfig config,
    NativeComponentEditorState editor,
    ResponsiveLayoutConfig responsiveConfig,
    double viewportWidth,
  ) {
    final hasSidebarStart = editor.visible('sidebarStart');
    final hasSidebarEnd = editor.visible('sidebarEnd');
    final foldSidebarStartToDrawer =
        config.responsiveSidebarToDrawer &&
        hasSidebarStart &&
        viewportWidth < responsiveConfig.breakpoints.tabletMinWidth;
    final showDockedSidebarStart =
        hasSidebarStart && !foldSidebarStartToDrawer;
    final showDockedSidebarEnd = hasSidebarEnd;

    final explicitDrawer = _drawer('drawer', editor, widget.drawer);
    final effectiveDrawer =
        explicitDrawer ??
        (foldSidebarStartToDrawer
            ? Drawer(
                width: config.sidebarStartWidth,
                child: editor.region('sidebarStart'),
              )
            : null);
    final effectiveEndDrawer = _drawer('endDrawer', editor, widget.endDrawer);
    final effectiveBottomNav = editor.visible('bottomNavigationBar')
        ? editor.region('bottomNavigationBar')
        : null;
    final effectiveFab = editor.visible('floatingActionButton')
        ? editor.region('floatingActionButton')
        : null;
    final effectiveBottomSheet = editor.visible('bottomSheet')
        ? editor.region('bottomSheet')
        : null;
    final mainBody = _body(context, config, editor, responsiveConfig);

    if (!showDockedSidebarStart && !showDockedSidebarEnd) {
      return Scaffold(
        key: _scaffoldKey,
        extendBody: config.extendBody,
        extendBodyBehindAppBar: config.extendBodyBehindAppBar,
        appBar: config.bodyMode == ScaffoldBodyMode.customScrollView
            ? null
            : _appBar(editor),
        body: mainBody,
        drawer: effectiveDrawer,
        endDrawer: effectiveEndDrawer,
        bottomNavigationBar: effectiveBottomNav,
        floatingActionButton: effectiveFab,
        bottomSheet: effectiveBottomSheet,
      );
    }

    final isContentOnlyHeader =
        config.headerSpan == ScaffoldHeaderSpan.contentOnly;
    final header = config.bodyMode == ScaffoldBodyMode.customScrollView
        ? null
        : _appBar(editor);
    Widget centerContent = mainBody;
    if (isContentOnlyHeader && header != null) {
      final topPadding = MediaQuery.paddingOf(context).top;
      final headerHeight = header.preferredSize.height + topPadding;
      centerContent = config.extendBodyBehindAppBar
          ? Stack(
              children: [
                Positioned.fill(child: mainBody),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: headerHeight,
                  child: header,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: headerHeight, child: header),
                Expanded(
                  child: topPadding > 0
                      ? MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: mainBody,
                        )
                      : mainBody,
                ),
              ],
            );
    }

    return Scaffold(
      key: _scaffoldKey,
      extendBody: config.extendBody,
      extendBodyBehindAppBar: config.extendBodyBehindAppBar,
      appBar: isContentOnlyHeader ? null : header,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showDockedSidebarStart)
            _buildSidebar(
              'sidebarStart',
              config.sidebarStartWidth,
              editor,
              _defaultSidebarStartWidth,
            ),
          Expanded(child: centerContent),
          if (showDockedSidebarEnd)
            _buildSidebar(
              'sidebarEnd',
              config.sidebarEndWidth,
              editor,
              _defaultSidebarEndWidth,
            ),
        ],
      ),
      drawer: effectiveDrawer,
      endDrawer: effectiveEndDrawer,
      bottomNavigationBar: effectiveBottomNav,
      floatingActionButton: effectiveFab,
      bottomSheet: effectiveBottomSheet,
    );
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
          behaviours: widget.behaviours,
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
              switch (descriptor.id) {
                'bodyMode' ||
                'extendBody' ||
                'extendBodyBehindAppBar' => true,
                'headerSpan' =>
                  nativeConfig.isEnabled('sidebarStart') ||
                      nativeConfig.isEnabled('sidebarEnd'),
                'sidebarStartWidth' ||
                'responsiveSidebarToDrawer' => nativeConfig.isEnabled(
                  'sidebarStart',
                ),
                'sidebarEndWidth' => nativeConfig.isEnabled('sidebarEnd'),
                _ =>
                  ScaffoldBodyMode.fromName(
                        nativeConfig.stringProperty('bodyMode'),
                      ) !=
                      ScaffoldBodyMode.standard,
              },
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
                ...editor.slotsFor('sidebarStart'),
                ...editor.slotsFor('sidebarEnd'),
                ...editor.slotsFor('bottomNavigationBar'),
              ])
                if (slot case NativePreferredSizeWidget native)
                  native.sizeListenable(context),
            ]),
            builder: (context, _) {
              final responsiveConfig = _resolveResponsiveLayout(context);
              final needsResponsiveViewport =
                  config.responsiveSidebarToDrawer &&
                  editor.visible('sidebarStart');
              if (!needsResponsiveViewport) {
                return _buildScaffold(
                  context,
                  config,
                  editor,
                  responsiveConfig,
                  MediaQuery.sizeOf(context).width,
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.sizeOf(context).width;
                  return _buildScaffold(
                    context,
                    config,
                    editor,
                    responsiveConfig,
                    width,
                  );
                },
              );
            },
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
