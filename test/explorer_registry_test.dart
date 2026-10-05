import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The existing video_player dependency supplies its platform test interface.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:surf_file/services/disk_space.dart';
import 'package:surf_file/widgets/explorer/explorer_components.dart';
import 'package:surf_file/widgets/explorer/explorer_scope.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_toolbar.dart';
import 'package:super_container_layout/widgets/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_layout.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/explorer_filter.dart';
import 'package:surf_file/models/explorer_location.dart';
import 'package:surf_file/models/selection_mode.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_filter_bar.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sort_header.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_view_mode_bar.dart';
import 'package:surf_file/widgets/explorer/states/explorer_empty_state.dart';
import 'package:surf_file/widgets/explorer/states/explorer_error_state.dart';
import 'package:surf_file/widgets/explorer/states/explorer_skeleton.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer/views/explorer_heatmap_view.dart';
import 'package:surf_file/widgets/explorer/views/explorer_columns_view.dart';
import 'package:surf_file/widgets/explorer/transitions/folder_transition_view.dart';
import 'package:surf_file/widgets/preview/text_preview_panel.dart';
import 'package:surf_file/widgets/preview/image_preview_panel.dart';
import 'package:surf_file/widgets/preview/video_preview_panel.dart';

ExplorerPaneData paneData({
  String path = r'C:\',
  String? error,
  List<ExplorerEntry> entries = const [],
  Set<String> selection = const {},
  bool loading = false,
  bool pending = false,
  bool hasLoaded = true,
  bool grid = false,
  bool columns = false,
  bool heatmap = false,
  bool preview = false,
  bool expanded = false,
  bool filterOpen = false,
  GlobalKey? contentKey,
  int revision = 0,
}) => (
  sidebar: (locations: const [], currentPath: path),
  path: path,
  title: path,
  split: true,
  active: true,
  editable: false,
  gridView: grid,
  columnView: columns,
  heatmapView: heatmap,
  filterOpen: filterOpen,
  filter: const ExplorerFilter(),
  sort: ExplorerSort.name,
  ascending: true,
  selectionMode: SelectionMode.checkbox,
  entries: entries,
  total: entries.length,
  selection: selection,
  selectedPath: selection.firstOrNull,
  checkboxSelection: true,
  revealToken: revision,
  loading: loading,
  pending: pending,
  hasLoaded: hasLoaded,
  error: error,
  hasQuery: false,
  dropEnabled: false,
  previewVisible: preview,
  previewExpanded: expanded,
  folderRevision: revision,
  reverseTransition: false,
  refreshToken: revision,
  contentKey: contentKey ?? GlobalKey(),
  titleIconKey: GlobalKey(),
  imagePreviewKey: GlobalKey(),
  textPreviewKey: GlobalKey(),
  videoPreviewKey: GlobalKey(),
);

ExplorerPaneActions paneActions(List<String> calls) => (
  onSidebarLocation: (path) => calls.add('sidebar:$path'),
  onActivate: () => calls.add('activate'),
  barActions: ({required bool canPaste}) => [],
  onGridViewChanged: (value) => calls.add('grid:$value'),
  onColumnViewChanged: (value) => calls.add('columns:$value'),
  onHeatmapViewChanged: (value) => calls.add('heatmap:$value'),
  onSelectionModeChanged: (value) => calls.add('mode:$value'),
  onToggleFilter: () => calls.add('filter'),
  onFilterChanged: (value) => calls.add('filter-changed'),
  onCloseFilter: () => calls.add('filter-close'),
  onSortChanged: (value) => calls.add('sort:$value'),
  onRetry: () => calls.add('retry'),
  onPointerSelect: (value) => calls.add('select:$value'),
  onTapped: (value) => calls.add('tap:$value'),
  onColumnTapped: (value) => calls.add('column-tap:$value'),
  onSelectionChanged: (value) => calls.add('selection:${value.length}'),
  onToggleSelection: (value) => calls.add('toggle:$value'),
  onViewportChanged: (_) {},
  onOpen: (entry) => calls.add('open:${entry.name}'),
  onOpenWithBounds: (entry, card, icon) => calls.add('hero:${entry.name}'),
  onContextMenu: (entry, position) => calls.add('menu:${entry.name}'),
  onNavigateColumn: (path, {String? select}) =>
      calls.add('column:$path:$select'),
  onDrop: (sources, destination) => calls.add('drop:$destination'),
  onClosePreview: () => calls.add('preview-close'),
  onTogglePreviewExpanded: () => calls.add('preview-expand'),
);

class _UnavailableVideoPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async =>
      throw MissingPluginException('No video backend in registry test');

  @override
  Future<void> dispose(int textureId) async {}
}

ExplorerNavigation navigation(String path, List<String> actions) =>
    ExplorerNavigation(
      path: path,
      canGoBack: true,
      canGoForward: true,
      canGoUp: true,
      split: true,
      onBack: () => actions.add('back'),
      onForward: () => actions.add('forward'),
      onUp: () => actions.add('up'),
      onRefresh: () => actions.add('refresh'),
      onSearchChanged: (value) => actions.add('search:$value'),
      onCreateFolder: () => actions.add('create'),
      onNavigate: (value) => actions.add('navigate:$value'),
      onToggleSplit: () => actions.add('split'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DiskSpace.channel, (_) async => []);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DiskSpace.channel, null);
  });
  testWidgets('content factory observes typed updates without page builders', (
    tester,
  ) async {
    final registry = createExplorerRegistry();
    final calls = <String>[];
    final key = GlobalKey();
    final data = ValueNotifier(paneData(contentKey: key));
    addTearDown(data.dispose);
    final component = Builder(
      builder: registry.component('explorer_content').builder,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<ExplorerPaneData>(
            valueListenable: data,
            child: component,
            builder: (_, value, child) => ExplorerPaneScope(
              data: value,
              actions: paneActions(calls),
              child: child!,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ExplorerEmptyState), findsOneWidget);
    final transitionState = tester.state(find.byType(FolderTransitionView));
    data.value = paneData(error: 'Read failed', contentKey: key, revision: 1);
    await tester.pumpAndSettle();
    expect(find.byType(ExplorerErrorState), findsOneWidget);
    expect(
      tester.state(find.byType(FolderTransitionView)),
      same(transitionState),
    );
    tester
        .widget<ExplorerErrorState>(find.byType(ExplorerErrorState))
        .onRetry();
    expect(calls, ['retry']);
    data.value = paneData(loading: true, pending: true, contentKey: key);
    await tester.pump();
    expect(find.byType(ExplorerSkeleton), findsOneWidget);
    data.value = paneData(loading: true, hasLoaded: false, contentKey: key);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'content factory constructs entries, heatmap, columns and previews',
    (tester) async {
      final platform = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = _UnavailableVideoPlatform();
      addTearDown(() => VideoPlayerPlatform.instance = platform);
      final registry = createExplorerRegistry();
      final calls = <String>[];
      ExplorerEntry entry(String name) => ExplorerEntry(
        entity: File('C:\\$name'),
        name: name,
        isDirectory: false,
        modified: DateTime(2020),
        size: 12,
      );
      Future<void> show(ExplorerPaneData data) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExplorerPaneScope(
                data: data,
                actions: paneActions(calls),
                child: Builder(
                  builder: registry.component('explorer_content').builder,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      final file = entry('notes.txt');
      await show(
        paneData(entries: [file], selection: {file.entity.path}, grid: true),
      );
      final view = tester.widget<ExplorerEntriesView>(
        find.byType(ExplorerEntriesView),
      );
      expect(view.gridView, isTrue);
      expect(view.selectedPaths, {file.entity.path});
      view.onSelected(file.entity.path);
      view.onSelectionChanged!({file.entity.path});
      view.onToggle!(file.entity.path);
      expect(calls, [
        'select:${file.entity.path}',
        'selection:1',
        'toggle:${file.entity.path}',
      ]);
      await show(paneData(entries: [file], heatmap: true));
      expect(find.byType(ExplorerHeatmapView), findsOneWidget);
      await show(paneData(entries: [file], columns: true));
      expect(find.byType(ExplorerColumnsView), findsOneWidget);
      expect(
        tester
            .widget<ExplorerEntriesView>(find.byType(ExplorerEntriesView))
            .compact,
        isTrue,
      );
      await show(paneData(entries: [file], preview: true));
      final text = tester.widget<TextPreviewPanel>(
        find.byType(TextPreviewPanel),
      );
      expect(text.path, isNull);
      text.onClose();
      text.onToggleExpanded();
      expect(calls.sublist(3), ['preview-close', 'preview-expand']);
      final image = entry('picture.png');
      await show(
        paneData(
          entries: [image],
          selection: {image.entity.path},
          preview: true,
          expanded: true,
        ),
      );
      expect(find.byType(ImagePreviewPanel), findsOneWidget);
      expect(find.byType(ExplorerEntriesView), findsNothing);
      final video = entry('movie.mp4');
      await show(
        paneData(
          entries: [video],
          selection: {video.entity.path},
          preview: true,
          expanded: true,
        ),
      );
      expect(find.byType(VideoPreviewPanel), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bar factories receive pane data and route typed actions', (
    tester,
  ) async {
    final registry = createExplorerRegistry();
    final calls = <String>[];
    await tester.binding.setSurfaceSize(const Size(1800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplorerPaneScope(
            data: paneData(filterOpen: true),
            actions: paneActions(calls),
            child: Column(
              children: [
                Builder(
                  builder: registry.component('explorer_view_mode_bar').builder,
                ),
                Builder(
                  builder: registry.component('explorer_filter_bar').builder,
                ),
                Builder(
                  builder: registry.component('explorer_sort_header').builder,
                ),
                Builder(
                  builder: registry
                      .component('explorer_split_indicator')
                      .builder,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final view = tester.widget<ExplorerViewModeBar>(
      find.byType(ExplorerViewModeBar),
    );
    expect(view.selectionMode, SelectionMode.checkbox);
    view.onGridViewChanged(true);
    view.onColumnViewChanged!(true);
    view.onHeatmapViewChanged!(true);
    final filter = tester.widget<ExplorerFilterBar>(
      find.byType(ExplorerFilterBar),
    );
    filter.onClose();
    tester
        .widget<ExplorerSortHeader>(find.byType(ExplorerSortHeader))
        .onSortChanged(ExplorerSort.size);
    expect(calls, [
      'grid:true',
      'columns:true',
      'heatmap:true',
      'filter-close',
      'sort:ExplorerSort.size',
    ]);
    expect(find.byKey(const ValueKey('split-active-true')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar block factories read current typed scope and shared tab',
    (tester) async {
      final registry = createExplorerRegistry();
      final calls = <String>[];
      ExplorerSidebar.tab.value = 0;
      addTearDown(() => ExplorerSidebar.tab.value = 0);
      final data = ValueNotifier<ExplorerSidebarData>((
        locations: const [
          ExplorerLocation('Documents', r'C:\Docs', Icons.folder),
        ],
        currentPath: r'C:\Docs',
      ));
      addTearDown(data.dispose);
      final blocks = Column(
        children: [
          Expanded(
            child: Builder(
              builder: registry.component('explorer_sidebar_places').builder,
            ),
          ),
          Expanded(
            child: Builder(
              builder: registry.component('explorer_sidebar_disks').builder,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ValueListenableBuilder<ExplorerSidebarData>(
                valueListenable: data,
                child: blocks,
                builder: (_, value, child) => ExplorerSidebarScope(
                  data: value,
                  actions: (onLocationSelected: (path) => calls.add(path)),
                  child: child!,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ExplorerSidebarPlaces), findsOneWidget);
      expect(find.byType(ExplorerSidebarDisks), findsOneWidget);
      await tester.tap(find.text('Documents'));
      expect(calls, [r'C:\Docs']);
      data.value = (
        locations: const [
          ExplorerLocation('Pictures', r'D:\Pics', Icons.image),
        ],
        currentPath: r'D:\Pics',
      );
      await tester.pump();
      expect(find.text('Pictures'), findsOneWidget);
      expect(find.text('Documents'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-tab-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-favorites')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'catalog preserves historical IDs and rejects duplicate registration',
    () {
      final registry = createExplorerRegistry();
      expect(registry.components.length, 11);
      expect(registry.component('explorer_toolbar').slotId, 'toolbar');
      expect(registry.component('explorer_breadcrumbs').slotId, 'breadcrumbs');
      expect(
        registry.component('explorer_toolbar').sizing,
        SlotSizing.intrinsic,
      );
      final indicator = registry.component('explorer_split_indicator');
      expect(indicator.createSlot('split-indicator').visible, isTrue);
      final hidden = indicator.createSlot('split-indicator', visible: false);
      expect(hidden.visible, isFalse);
      expect(hidden.id, 'split-indicator');
      expect(hidden.label, indicator.label);
      expect(hidden.sizing, indicator.sizing);
      expect(hidden.builder, same(indicator.builder));
      expect(() => registerExplorerComponents(registry), throwsStateError);
      expect(() => registry.component('missing'), throwsStateError);
    },
  );

  testWidgets(
    'factories use current scoped navigation independently per pane',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final registry = createExplorerRegistry();
      final left = <String>[];
      final right = <String>[];
      final leftData = ValueNotifier(navigation('C:\\Left\\Documents', left));
      addTearDown(leftData.dispose);
      final toolbar = registry.component('explorer_toolbar');
      final breadcrumbs = registry.component('explorer_breadcrumbs');
      Widget components() => Column(
        children: [
          Builder(builder: toolbar.builder),
          Builder(builder: breadcrumbs.builder),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<ExplorerNavigation>(
                    valueListenable: leftData,
                    child: components(),
                    builder: (_, value, child) =>
                        ExplorerScope(navigation: value, child: child!),
                  ),
                ),
                Expanded(
                  child: ExplorerScope(
                    navigation: navigation('D:\\Right\\Pictures', right),
                    child: components(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Retour').first);
      await tester.tap(find.byTooltip('Actualiser').last);
      await tester.enterText(find.byType(TextField).last, 'photo');
      expect(left, ['back']);
      expect(right, ['refresh', 'search:photo']);
      expect(
        tester
            .widgetList<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs))
            .map((widget) => widget.path),
        ['C:\\Left\\Documents', 'D:\\Right\\Pictures'],
      );
      leftData.value = navigation('C:\\Updated', left);
      await tester.pump();
      expect(
        tester
            .widgetList<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs))
            .map((widget) => widget.path),
        ['C:\\Updated', 'D:\\Right\\Pictures'],
      );
      expect(find.byType(ExplorerToolbar), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('components are unavailable outside an explorer scope', (
    tester,
  ) async {
    final registry = createExplorerRegistry();
    final component = registry.component('explorer_toolbar');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(component.isAvailable!(context), isFalse);
            expect(
              () => ExplorerScope.of(context),
              throwsA(isA<FlutterError>()),
            );
            return ExplorerScope(
              navigation: navigation('C:\\', []),
              child: Builder(
                builder: (context) {
                  expect(component.isAvailable!(context), isTrue);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
  });

  testWidgets(
    'registered layouts preserve metadata and restrict their catalog',
    (tester) async {
      final registry = createExplorerRegistry();
      final component = registry.component('explorer_content');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplorerPaneScope(
              data: paneData(error: 'Scoped folder content'),
              actions: paneActions([]),
              child: registeredExplorerLayout(
                registry: registry,
                layout: SuperLayout(
                  key: const ValueKey('registered-layout'),
                  config: const SuperLayoutConfig(
                    placements: {
                      SuperLayoutZone.center: ['content'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'content',
                      label: 'Old label',
                      labelAlignment: Alignment.topRight,
                      builder: (_) =>
                          throw StateError('Obsolete builder delegation'),
                    ),
                    BuilderSlot(
                      id: 'split-indicator',
                      label: 'Hidden indicator',
                      visible: false,
                      builder: (_) => const Text('Hidden'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Scoped folder content'), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
      final layout = tester.widget<SuperLayout>(
        find.byKey(const ValueKey('registered-layout')),
      );
      expect(layout.slots.first.label, 'Contenu du dossier');
      expect(layout.slots.first.labelAlignment, Alignment.topRight);
      expect(layout.slots.last.visible, isFalse);
      expect(layout.slots.last.sizing, SlotSizing.intrinsic);
      final contentContext = tester.element(find.byType(ExplorerErrorState));
      expect(component.isAvailable!(contentContext), isTrue);
      expect(
        registry.component('explorer_main').isAvailable!(contentContext),
        isFalse,
      );
      expect(
        registry.component('explorer_sidebar_places').isAvailable!(
          contentContext,
        ),
        isFalse,
      );
      expect(
        registry.component('explorer_split_indicator').isAvailable!(
          contentContext,
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
