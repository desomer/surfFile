import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/widgets/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_layout.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/super_app.dart';

import 'explorer_scope.dart';
import 'navigation/explorer_breadcrumbs.dart';
import 'navigation/explorer_toolbar.dart';
import 'navigation/explorer_sidebar.dart';
import 'navigation/explorer_filter_bar.dart';
import 'navigation/explorer_sort_header.dart';
import 'navigation/explorer_view_mode_bar.dart';
import '../../services/file_operations.dart';
import 'states/explorer_empty_state.dart';
import 'states/explorer_error_state.dart';
import 'states/explorer_skeleton.dart';
import 'views/explorer_columns_view.dart';
import 'views/explorer_entries_view.dart';
import 'views/explorer_heatmap_view.dart';
import 'transitions/folder_transition_view.dart';
import '../file_operations/external_file_drop.dart';
import '../preview/image_preview_panel.dart';
import '../preview/text_preview_panel.dart';
import '../preview/video_preview_panel.dart';

Registry createExplorerRegistry() {
  final registry = Registry();
  registerExplorerComponents(registry);
  return registry;
}

void registerExplorerComponents(Registry registry) {
  registry.registerComponent(
    'explorer_toolbar',
    RegisteredComponent(
      label: 'Barre d’outils',
      slotId: 'toolbar',
      sizing: SlotSizing.intrinsic,
      isAvailable: (context) => _available(context, 'explorer_toolbar'),
      builder: (context) {
        final navigation = ExplorerScope.of(context);
        return ExplorerToolbar(
          split: navigation.split,
          onToggleSplit: navigation.onToggleSplit,
          canGoBack: navigation.canGoBack,
          canGoForward: navigation.canGoForward,
          canGoUp: navigation.canGoUp,
          onBack: navigation.onBack,
          onForward: navigation.onForward,
          onUp: navigation.onUp,
          onRefresh: navigation.onRefresh,
          onSearchChanged: navigation.onSearchChanged,
          onCreateFolder: navigation.onCreateFolder,
        );
      },
    ),
  );
  registry.registerComponent(
    'explorer_breadcrumbs',
    RegisteredComponent(
      label: 'Barre du chemin',
      slotId: 'breadcrumbs',
      sizing: SlotSizing.intrinsic,
      isAvailable: (context) => _available(context, 'explorer_breadcrumbs'),
      builder: (context) {
        final navigation = ExplorerScope.of(context);
        return ExplorerBreadcrumbs(
          path: navigation.path,
          onNavigate: navigation.onNavigate,
        );
      },
    ),
  );

  registry.registerComponent(
    'explorer_sidebar',
    RegisteredComponent(
      label: 'Panneau gauche',
      slotId: 'sidebar',
      isAvailable: (context) => _available(context, 'explorer_sidebar'),
      builder: _sidebar,
    ),
  );
  registry.registerComponent(
    'explorer_main',
    RegisteredComponent(
      label: 'Explorateur',
      slotId: 'main',
      isAvailable: (context) => _available(context, 'explorer_main'),
      builder: _main,
    ),
  );
  registry.registerComponent(
    'explorer_split_indicator',
    RegisteredComponent(
      label: 'Indicateur du mode divisé',
      slotId: 'split-indicator',
      sizing: SlotSizing.intrinsic,
      isAvailable: (context) => _available(context, 'explorer_split_indicator'),
      builder: _splitIndicator,
    ),
  );
  registry.registerComponent(
    'explorer_view_mode_bar',
    RegisteredComponent(
      label: 'Barre des modes d’affichage',
      slotId: 'view-mode-bar',
      sizing: SlotSizing.intrinsic,
      isAvailable: (context) => _available(context, 'explorer_view_mode_bar'),
      builder: _viewModeBar,
    ),
  );
  registry.registerComponent(
    'explorer_filter_bar',
    RegisteredComponent(
      label: 'Barre de filtres',
      slotId: 'filter-bar',
      sizing: SlotSizing.intrinsic,
      isAvailable: (context) => _available(context, 'explorer_filter_bar'),
      builder: _filterBar,
    ),
  );
  registry.registerComponent(
    'explorer_sort_header',
    RegisteredComponent(
      label: 'En-tête de tri',
      slotId: 'sort-header',
      sizing: SlotSizing.intrinsic,
      isAvailable: (context) => _available(context, 'explorer_sort_header'),
      builder: _sortHeader,
    ),
  );
  registry.registerComponent(
    'explorer_content',
    RegisteredComponent(
      label: 'Contenu du dossier',
      slotId: 'content',
      isAvailable: (context) => _available(context, 'explorer_content'),
      builder: _content,
    ),
  );
  registry.registerComponent(
    'explorer_sidebar_places',
    RegisteredComponent(
      label: 'Espace et favoris',
      slotId: 'sidebar-places',
      isAvailable: (context) => _available(context, 'explorer_sidebar_places'),
      builder: (context) => ExplorerSidebarPlaces(
        data: ExplorerSidebarScope.of(context).data,
        actions: ExplorerSidebarScope.of(context).actions,
      ),
    ),
  );
  registry.registerComponent(
    'explorer_sidebar_disks',
    RegisteredComponent(
      label: 'Disques',
      slotId: 'sidebar-disks',
      sizing: SlotSizing.intrinsic,
      isAvailable: (context) => _available(context, 'explorer_sidebar_disks'),
      builder: (context) => ExplorerSidebarDisks(
        data: ExplorerSidebarScope.of(context).data,
        actions: ExplorerSidebarScope.of(context).actions,
      ),
    ),
  );
}

Widget _sidebar(BuildContext context) {
  final data = ExplorerPaneScope.of(context).data.sidebar;
  return ExplorerSidebar(
    locations: data.locations,
    currentPath: data.currentPath,
    onLocationSelected: ExplorerPaneScope.of(context).actions.onSidebarLocation,
  );
}

Widget _main(BuildContext context) {
  final scope = ExplorerPaneScope.of(context);
  final data = scope.data;
  final appearance = AppearanceScope.controllerOf(context);
  final config = AppearanceScope.of(context).layout('explorerMain');
  final registry =
      SuperApp.maybeOf(context)?.registry ?? createExplorerRegistry();
  return Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => scope.actions.onActivate(),
    child: registeredExplorerLayout(
      registry: registry,
      layout: SuperLayout(
        key: const ValueKey('explorer-main-layout'),
        label: 'Disposition de l’explorateur',
        name: 'Explorateur',
        editable: data.editable,
        onChanged: appearance == null
            ? null
            : (value) => appearance.value = appearance.value.withLayout(
                'explorerMain',
                value,
              ),
        config: data.previewExpanded
            ? config.withSide(config.contentZone(SuperLayoutZone.north), false)
            : config,
        slots: [
          registry.component('explorer_split_indicator').createSlot(
            'split-indicator',
            visible: data.split,
          ),
          registry.component('explorer_toolbar').createSlot('toolbar'),
          registry.component('explorer_breadcrumbs').createSlot('breadcrumbs'),
          registry
              .component('explorer_view_mode_bar')
              .createSlot('view-mode-bar'),
          registry.component('explorer_filter_bar').createSlot('filter-bar'),
          registry.component('explorer_sort_header').createSlot(
            'sort-header',
            visible: !data.columnView && !data.heatmapView,
          ),
          registry.component('explorer_content').createSlot('content'),
        ],
      ),
    ),
  );
}

Widget _splitIndicator(BuildContext context) {
  final data = ExplorerPaneScope.of(context).data;
  return AnimatedContainer(
    key: ValueKey('split-active-${data.active}'),
    duration: const Duration(milliseconds: 150),
    height: 3,
    color: data.active
        ? AppearanceScope.of(context).accent
        : Colors.transparent,
  );
}

Widget _viewModeBar(BuildContext context) {
  final scope = ExplorerPaneScope.of(context);
  final data = scope.data;
  final actions = scope.actions;
  return ValueListenableBuilder(
    valueListenable: FileClipboard.content,
    builder: (context, clipboard, _) => ExplorerViewModeBar(
      actions: actions.barActions(canPaste: clipboard != null),
      title: data.title,
      itemCount: data.entries.length,
      pending: data.pending,
      gridView: data.gridView,
      onGridViewChanged: actions.onGridViewChanged,
      columnView: data.columnView,
      onColumnViewChanged: actions.onColumnViewChanged,
      heatmapView: data.heatmapView,
      onHeatmapViewChanged: actions.onHeatmapViewChanged,
      titleIconKey: data.titleIconKey,
      filterCount: data.filter.activeCount,
      filterOpen: data.filterOpen,
      onToggleFilter: actions.onToggleFilter,
      selectionMode: data.selectionMode,
      onSelectionModeChanged: actions.onSelectionModeChanged,
    ),
  );
}

Widget _filterBar(BuildContext context) {
  final scope = ExplorerPaneScope.of(context);
  final data = scope.data;
  return AnimatedSize(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: data.filterOpen
        ? ExplorerFilterBar(
            filter: data.filter,
            shown: data.entries.length,
            total: data.total,
            onChanged: scope.actions.onFilterChanged,
            onClose: scope.actions.onCloseFilter,
          )
        : const SizedBox(width: double.infinity),
  );
}

Widget _sortHeader(BuildContext context) {
  final scope = ExplorerPaneScope.of(context);
  return ExplorerSortHeader(
    sort: scope.data.sort,
    ascending: scope.data.ascending,
    onSortChanged: scope.actions.onSortChanged,
  );
}

Widget _content(BuildContext context) {
  final scope = ExplorerPaneScope.of(context);
  final data = scope.data;
  final actions = scope.actions;
  final showGrid = data.gridView && !data.columnView;
  final content = IgnorePointer(
    ignoring: data.loading,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: data.pending && data.error == null
          ? ExplorerSkeleton(
              key: const ValueKey('explorer-skeleton'),
              gridView: showGrid,
            )
          : KeyedSubtree(
              key: const ValueKey('explorer-content'),
              child: data.loading && !data.hasLoaded
                  ? const Center(child: CircularProgressIndicator())
                  : data.error != null
                  ? ExplorerErrorState(
                      message: data.error!,
                      onRetry: actions.onRetry,
                    )
                  : data.entries.isEmpty
                  ? ExplorerEmptyState(hasQuery: data.hasQuery)
                  : LayoutBuilder(
                      builder: (context, constraints) =>
                          _entriesAndPreview(data, actions, constraints),
                    ),
            ),
    ),
  );
  return KeyedSubtree(
    key: data.contentKey,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ExternalFileDrop(
          path: data.path,
          enabled: data.dropEnabled,
          onDrop: actions.onDrop,
          child: data.columnView && !data.previewExpanded
              ? ExplorerColumnsView(
                  path: data.path,
                  current: content,
                  lastMinWidth:
                      ExplorerColumnsView.columnWidth +
                      (data.previewVisible ? 352 : 0),
                  sort: data.sort,
                  ascending: data.ascending,
                  onNavigate: actions.onNavigateColumn,
                  onOpen: actions.onOpen,
                  refreshToken: data.refreshToken,
                )
              : FolderTransitionView(
                  revision: data.folderRevision,
                  reverse: data.reverseTransition,
                  child: content,
                ),
        ),
        if (data.loading && data.hasLoaded && !data.pending)
          const Center(child: CircularProgressIndicator()),
      ],
    ),
  );
}

Widget _entriesAndPreview(
  ExplorerPaneData data,
  ExplorerPaneActions actions,
  BoxConstraints constraints,
) {
  final fileList = data.heatmapView
      ? ExplorerHeatmapView(
          key: ValueKey('heatmap-${data.path}'),
          entries: data.entries,
          selectedPaths: data.selection,
          onPointerSelect: actions.onPointerSelect,
          onTapped: actions.onTapped,
          onOpen: actions.onOpen,
          onContextMenu: actions.onContextMenu,
        )
      : ExplorerEntriesView(
          key: ValueKey(data.path),
          entries: data.entries,
          gridView: data.gridView && !data.columnView,
          compact: data.columnView,
          selectedPath: data.selectedPath,
          selectedPaths: data.selection,
          onSelected: actions.onPointerSelect,
          onTapped: data.columnView ? actions.onColumnTapped : actions.onTapped,
          onSelectionChanged: actions.onSelectionChanged,
          onToggle: data.checkboxSelection ? actions.onToggleSelection : null,
          revealToken: data.revealToken,
          onViewportChanged: actions.onViewportChanged,
          onOpen: actions.onOpen,
          onOpenWithBounds: data.columnView ? null : actions.onOpenWithBounds,
          onContextMenu: actions.onContextMenu,
        );
  if (!data.previewVisible) {
    return data.columnView
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: ExplorerColumnsView.columnWidth, child: fileList),
            ],
          )
        : fileList;
  }
  final selected = data.entries
      .where((entry) => entry.entity.path == data.selectedPath)
      .firstOrNull;
  final preview = selected != null && VideoPreviewPanel.supports(selected.name)
      ? VideoPreviewPanel(
          key: data.videoPreviewKey,
          path: selected.entity.path,
          onClose: actions.onClosePreview,
          isExpanded: data.previewExpanded,
          onToggleExpanded: actions.onTogglePreviewExpanded,
        )
      : selected != null && ImagePreviewPanel.supports(selected.name)
      ? ImagePreviewPanel(
          key: data.imagePreviewKey,
          path: selected.entity.path,
          onClose: actions.onClosePreview,
          isExpanded: data.previewExpanded,
          onToggleExpanded: actions.onTogglePreviewExpanded,
        )
      : TextPreviewPanel(
          key: data.textPreviewKey,
          path: selected != null && TextPreviewPanel.supports(selected.name)
              ? selected.entity.path
              : null,
          onClose: actions.onClosePreview,
          isExpanded: data.previewExpanded,
          onToggleExpanded: actions.onTogglePreviewExpanded,
        );
  if (data.previewExpanded) return preview;
  if (data.columnView) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: ExplorerColumnsView.columnWidth, child: fileList),
        const SizedBox(width: 12),
        Expanded(child: preview),
      ],
    );
  }
  if (constraints.maxWidth >= 760) {
    return Row(
      children: [
        Expanded(child: fileList),
        const SizedBox(width: 12),
        SizedBox(width: 340, child: preview),
      ],
    );
  }
  return Column(
    children: [
      Expanded(flex: 3, child: fileList),
      const SizedBox(height: 12),
      SizedBox(height: 240, child: preview),
    ],
  );
}

bool _available(BuildContext context, String key) {
  final scope = ExplorerComponentScope.maybeOf(context);
  if (scope != null && !scope.visible.contains(key)) return false;
  return switch (key) {
    'explorer_toolbar' ||
    'explorer_breadcrumbs' => ExplorerScope.maybeOf(context) != null,
    'explorer_sidebar_places' ||
    'explorer_sidebar_disks' => ExplorerSidebarScope.maybeOf(context) != null,
    _ => ExplorerPaneScope.maybeOf(context) != null,
  };
}

/// Résout les slots historiques via le catalogue sans déplacer leur état métier.
Widget registeredExplorerLayout({
  required Registry registry,
  required SuperLayout layout,
}) {
  final byId = {
    for (final entry in registry.components.entries)
      if (entry.value.slotId != null) entry.value.slotId!: entry,
  };
  final visible = <String>{};
  final slots = <SlotImplementation>[];
  for (final slot in layout.slots) {
    final entry = byId[slot.id];
    if (entry == null || slot is! BuilderSlot) {
      throw StateError('Slot explorateur non enregistré : ${slot.id}');
    }
    if (slot.visible) visible.add(entry.key);
    slots.add(
      BuilderSlot(
        id: slot.id,
        label: entry.value.label,
        sizing: entry.value.sizing,
        visible: slot.visible,
        showLabel: slot.showLabel,
        labelAlignment: slot.labelAlignment,
        key: slot.key,
        builder: entry.value.builder,
      ),
    );
  }
  return ExplorerComponentScope(
    visible: visible,
    child: SuperLayout(
      key: layout.key,
      config: layout.config,
      onChanged: layout.onChanged,
      label: layout.label,
      name: layout.name,
      editable: layout.editable,
      showZoneNames: layout.showZoneNames,
      slots: slots,
    ),
  );
}
