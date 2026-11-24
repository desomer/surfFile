/// Page standard ([SuperPage]) et coquille structurelle ([SuperScaffold]) assemblant le `Scaffold` éditable.
///
/// Délègue le montage des régions (`appBar`, `body`, `sidebarStart`, `sidebarEnd`,
/// `drawer`, `endDrawer`, `bottomNavigationBar`, `floatingActionButton`, `bottomSheet`
/// et `scaffold:outlet`) à [ScaffoldPageLayout] avec prise en charge d'[EditorZoom].
library;

import 'package:material_ui/material_ui.dart';

import 'models/responsive_layout_config.dart';
import 'models/scaffold_page_config.dart';
import 'widgets/appearance/super_shell_scope.dart';
import 'widgets/components/super_component.dart';
import 'widgets/editing/overlay/editor_zoom.dart';
import 'widgets/components/native/scaffold_page_layout.dart';
import 'widgets/components/super_layout/slot_implementation.dart';

/// Page whose editable regions map directly to the native [Scaffold] slots.
class SuperPage extends SuperStatelessComponent<ScaffoldPageConfig?> {
  const SuperPage({
    this.id = 'root',
    this.label = 'Page',
    this.menuIcon,
    this.child = const SizedBox.shrink(),
    this.outlet,
    this.appBar,
    this.sidebarStart,
    this.sidebarEnd,
    this.drawer,
    this.endDrawer,
    this.bottomBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.bottomSheet,
    this.slots = const [],
    this.pageConfig,
    this.headerSpan,
    this.sidebarStartWidth,
    this.sidebarEndWidth,
    this.responsiveSidebarToDrawer,
    this.bodyMode,
    this.extendBody,
    this.extendBodyBehindAppBar,
    this.scrollDirection,
    this.reverse,
    this.primary,
    this.scrollPadding,
    this.clipBehavior,
    this.responsiveLayout,
    this.maxAutoZoomExtent = EditorZoom.defaultMaxAutoZoomExtent,
    super.behaviours,
    super.key,
  }) : assert(
         bottomBar == null || bottomNavigationBar == null,
         'Use either bottomBar or bottomNavigationBar, not both.',
       );

  /// Stable persistence key. Use a different ID for each page.
  @override
  final String id;
  final String label;
  final IconData? menuIcon;
  final Widget child;

  /// Contenu de la route enfant monté dans le slot `'scaffold:outlet'` (shell partagé).
  final Widget? outlet;

  final PreferredSizeWidget? appBar;

  /// Panneau latéral fixe au début (gauche en LTR) pour la région `sidebarStart`.
  final Widget? sidebarStart;

  /// Panneau latéral fixe à la fin (droite en LTR) pour la région `sidebarEnd`.
  final Widget? sidebarEnd;

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
  @override
  ScaffoldPageConfig? get config => pageConfig;

  /// Portée horizontale de l'en-tête (`fullWidth` ou `contentOnly`).
  final ScaffoldHeaderSpan? headerSpan;

  /// Largeur fixe optionnelle de la région `sidebarStart` (en pixels).
  final double? sidebarStartWidth;

  /// Largeur fixe optionnelle de la région `sidebarEnd` (en pixels).
  final double? sidebarEndWidth;

  /// Replie automatiquement `sidebarStart` dans le `drawer` sous le seuil tablette.
  final bool? responsiveSidebarToDrawer;

  /// Mode d'affichage de la zone `body` (`standard`, `singleChildScrollView`, `customScrollView`).
  final ScaffoldBodyMode? bodyMode;
  final bool? extendBody;
  final bool? extendBodyBehindAppBar;
  final Axis? scrollDirection;
  final bool? reverse;
  final bool? primary;
  final double? scrollPadding;
  final Clip? clipBehavior;

  /// Configuration responsive explicite (remplace la résolution via [Appearance]).
  final ResponsiveLayoutConfig? responsiveLayout;

  /// Taille (px) à partir de laquelle une sélection n'est plus zoomée en mode édition.
  final double maxAutoZoomExtent;

  @override
  Widget build(BuildContext context) {
    if (SuperShellScope.maybeOf(context) != null &&
        id == 'root' &&
        outlet == null &&
        this is! SuperScaffold) {
      return child;
    }
    var resolvedConfig =
        pageConfig ??
        ScaffoldPageConfig(
          placements: {
            if (appBar != null)
              ScaffoldPageRegion.appBar: const ['scaffold:appBar'],
            ScaffoldPageRegion.body: outlet != null
                ? const ['scaffold:outlet']
                : const ['scaffold:body'],
            if (sidebarStart != null)
              ScaffoldPageRegion.sidebarStart: const ['scaffold:sidebarStart'],
            if (sidebarEnd != null)
              ScaffoldPageRegion.sidebarEnd: const ['scaffold:sidebarEnd'],
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
    if (headerSpan != null) {
      resolvedConfig = resolvedConfig.withHeaderSpan(headerSpan);
    }
    if (sidebarStartWidth != null) {
      resolvedConfig = resolvedConfig.withSidebarStartWidth(sidebarStartWidth);
    }
    if (sidebarEndWidth != null) {
      resolvedConfig = resolvedConfig.withSidebarEndWidth(sidebarEndWidth);
    }
    if (responsiveSidebarToDrawer != null) {
      resolvedConfig = resolvedConfig.withResponsiveSidebarToDrawer(
        responsiveSidebarToDrawer,
      );
    }
    if (bodyMode != null) {
      resolvedConfig = resolvedConfig.withBodyMode(bodyMode);
    }
    if (extendBody != null) {
      resolvedConfig = resolvedConfig.withExtendBody(extendBody);
    }
    if (extendBodyBehindAppBar != null) {
      resolvedConfig = resolvedConfig.withExtendBodyBehindAppBar(
        extendBodyBehindAppBar,
      );
    }
    if (scrollDirection != null) {
      resolvedConfig = resolvedConfig.withScrollDirection(scrollDirection);
    }
    if (reverse != null) {
      resolvedConfig = resolvedConfig.withReverse(reverse);
    }
    if (primary != null) {
      resolvedConfig = resolvedConfig.withPrimary(primary);
    }
    if (scrollPadding != null) {
      resolvedConfig = resolvedConfig.withScrollPadding(scrollPadding);
    }
    if (clipBehavior != null) {
      resolvedConfig = resolvedConfig.withClipBehavior(clipBehavior);
    }
    return EditorZoom(
      maxAutoZoomExtent: maxAutoZoomExtent,
      child: ScaffoldPageLayout(
        id: id,
        behaviours: behaviours,
        label: label,
        menuIcon: menuIcon,
        config: resolvedConfig,
        slots: slots,
        appBar: appBar,
        body: child,
        sidebarStart: sidebarStart,
        sidebarEnd: sidebarEnd,
        outlet: outlet,
        drawer: drawer,
        endDrawer: endDrawer,
        bottomNavigationBar: bottomNavigationBar ?? bottomBar,
        floatingActionButton: floatingActionButton,
        bottomSheet: bottomSheet,
        responsiveLayout: responsiveLayout,
      ),
    );
  }
}

/// Coquille structurelle éditable ([SuperScaffold]) pour construire un shell
/// partagé multi-pages (avec [outlet]) ou une page complète avec panneaux latéraux.
///
/// Étend [SuperPage] avec des valeurs par défaut ergonomiques (`id = 'main-shell'`,
/// `label = 'Structure'`) et relaie l'ensemble des régions natives du `Scaffold`.
class SuperScaffold extends SuperPage {
  /// Crée un [SuperScaffold] configurable via [pageConfig] ou les régions fournies.
  const SuperScaffold({
    super.id = 'main-shell',
    super.label = 'Structure',
    super.menuIcon,
    super.outlet,
    super.child = const SizedBox.shrink(),
    super.appBar,
    super.sidebarStart,
    super.sidebarEnd,
    super.drawer,
    super.endDrawer,
    super.bottomBar,
    super.bottomNavigationBar,
    super.floatingActionButton,
    super.bottomSheet,
    super.slots = const [],
    super.pageConfig,
    super.headerSpan,
    super.sidebarStartWidth,
    super.sidebarEndWidth,
    super.responsiveSidebarToDrawer,
    super.bodyMode,
    super.extendBody,
    super.extendBodyBehindAppBar,
    super.scrollDirection,
    super.reverse,
    super.primary,
    super.scrollPadding,
    super.clipBehavior,
    super.responsiveLayout,
    super.maxAutoZoomExtent = EditorZoom.defaultMaxAutoZoomExtent,
    super.behaviours,
    super.key,
  });
}
