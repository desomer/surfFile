import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

Appearance _twoPagesAppearance({bool includeShared = false}) {
  final components = <String, ComponentConfig>{
    'root': ScaffoldPageConfig(
      placements: {
        ScaffoldPageRegion.body: const ['mainLayout'],
      },
      slotTypes: {'mainLayout': 'registry:Layout'},
    ),
    'mainLayout': const SuperLayoutConfig(),
    'page-a': ScaffoldPageConfig(
      placements: {
        ScaffoldPageRegion.body: const ['val-a'],
      },
      slotTypes: {'val-a': 'registry:Value'},
    ),
    'val-a': const SuperValueConfig(initialText: 'Texte Page A'),
    'page-b': ScaffoldPageConfig(
      placements: {
        ScaffoldPageRegion.body: includeShared
            ? const ['val-b', 'shared-val']
            : const ['val-b'],
      },
      slotTypes: {
        'val-b': 'registry:Value',
        if (includeShared) 'shared-val': 'registry:Value',
      },
    ),
    'val-b': const SuperValueConfig(initialText: 'Texte Page B'),
    if (includeShared)
      'shared-val': const SuperValueConfig(initialText: 'Texte Partage'),
  };
  if (includeShared) {
    components['page-a'] = ScaffoldPageConfig(
      placements: {
        ScaffoldPageRegion.body: const ['val-a', 'shared-val'],
      },
      slotTypes: {
        'val-a': 'registry:Value',
        'shared-val': 'registry:Value',
      },
    );
  }

  return Appearance(
    mode: ThemeMode.dark,
    accent: const Color(0xFF3355CC),
    styles: {
      'background': const ContainerStyle(color: Color(0xFF101010)),
      'val-a': const ContainerStyle(color: Color(0xFFAA0000)),
      'val-b': const ContainerStyle(color: Color(0xFF00AA00)),
      if (includeShared)
        'shared-val': const ContainerStyle(color: Color(0xFF0000AA)),
    },
    components: components,
    behaviors: {
      'val-a': [
        ComponentBehavior(
          id: 'beh-a',
          action: GoToPageAction(pagePath: '/page-b', pageId: 'page-b'),
        ),
      ],
      'val-b': [
        ComponentBehavior(
          id: 'beh-b',
          action: GoToPageAction(pagePath: '/page-a', pageId: 'page-a'),
        ),
      ],
    },
    usages: {
      'val-a': const ComponentUsage(kind: ComponentUsageKind.staticData),
      'val-b': const ComponentUsage(kind: ComponentUsageKind.staticData),
    },
    pageCatalog: EditorPageCatalog(
      pages: [
        EditorPageConfig(id: 'page-a', name: 'Page A', path: '/page-a'),
        EditorPageConfig(id: 'page-b', name: 'Page B', path: '/page-b'),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('paged-appearance-test-');
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() async {
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('EditorPageGraph.partitionForPages', () {
    test('separates exclusive page entries from root and shared entries', () {
      final registry = Registry()..bootstrap();
      addTearDown(registry.dispose);
      final appearance = _twoPagesAppearance(includeShared: true);

      final partition = EditorPageGraph.partitionForPages(
        appearance: appearance,
        registry: registry,
        loadedPageIds: const {'page-a', 'page-b'},
      );

      expect(partition.global.components.keys, containsAll(['root', 'mainLayout', 'shared-val']));
      expect(partition.global.components.keys, isNot(contains('page-a')));
      expect(partition.global.components.keys, isNot(contains('val-a')));
      expect(partition.global.components.keys, isNot(contains('page-b')));
      expect(partition.global.components.keys, isNot(contains('val-b')));
      expect(partition.global.styles.keys, containsAll(['background', 'shared-val']));

      final sliceA = partition.pages['page-a']!;
      expect(sliceA.components.keys, unorderedEquals(['page-a', 'val-a']));
      expect(sliceA.styles.keys, unorderedEquals(['val-a']));
      expect(sliceA.behaviors.keys, unorderedEquals(['val-a']));
      expect(sliceA.usages.keys, unorderedEquals(['val-a']));

      final sliceB = partition.pages['page-b']!;
      expect(sliceB.components.keys, unorderedEquals(['page-b', 'val-b']));
      expect(sliceB.styles.keys, unorderedEquals(['val-b']));
      expect(sliceB.behaviors.keys, unorderedEquals(['val-b']));
      expect(sliceB.usages.keys, unorderedEquals(['val-b']));
    });

    test('keeps globalProtectedIds in global until all catalog pages are loaded', () {
      final registry = Registry()..bootstrap();
      addTearDown(registry.dispose);
      final appearance = _twoPagesAppearance(includeShared: true);

      // Only page-a is loaded; shared-val was protected from appearance.json.
      final partial = EditorPageGraph.partitionForPages(
        appearance: appearance,
        registry: registry,
        loadedPageIds: const {'page-a'},
        globalProtectedIds: const {'shared-val', 'root', 'mainLayout', 'background'},
      );

      expect(partial.global.components.keys, contains('shared-val'));
      expect(partial.pages['page-a']!.components.keys, isNot(contains('shared-val')));
    });
  });

  group('PagedFileAppearanceStore & SandboxedApplicationStore', () {
    test('saves one file per page, lazy loads on demand, saves incrementally and deletes removed pages', () async {
      final registry = Registry()..bootstrap();
      addTearDown(registry.dispose);

      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app');
      final store = SandboxedApplicationStore.appearanceStoreFor(
        appDir,
        registry: registry,
      );

      final initial = _twoPagesAppearance();
      await store.save(initial);

      final globalFile = SandboxedApplicationStore.appearanceFileFor(appDir);
      final pageAFile = SandboxedApplicationStore.pageFileFor(appDir, 'page-a');
      final pageBFile = SandboxedApplicationStore.pageFileFor(appDir, 'page-b');

      expect(globalFile.existsSync(), isTrue);
      expect(pageAFile.existsSync(), isTrue);
      expect(pageBFile.existsSync(), isTrue);

      final globalJson =
          jsonDecode(globalFile.readAsStringSync()) as Map<String, dynamic>;
      expect((globalJson['components'] as Map).keys, unorderedEquals(['root', 'mainLayout']));
      expect((globalJson['styles'] as Map).keys, unorderedEquals(['background']));

      // Fresh store: load() only reads global appearance.json, not page-a or page-b.
      final fresh = SandboxedApplicationStore.appearanceStoreFor(
        appDir,
        registry: registry,
      );
      final loadedGlobal = await fresh.load();
      expect(loadedGlobal.pageCatalog.pages.map((p) => p.id), ['page-a', 'page-b']);
      expect(loadedGlobal.components.containsKey('val-a'), isFalse);
      expect(loadedGlobal.components.containsKey('val-b'), isFalse);
      expect(fresh.isPageLoaded('page-a'), isFalse);
      expect(fresh.isPageLoaded('page-b'), isFalse);

      // Load only page-a on demand.
      final sliceA = await fresh.loadPage('page-a');
      expect(fresh.isPageLoaded('page-a'), isTrue);
      expect(fresh.isPageLoaded('page-b'), isFalse);
      final withA = sliceA.mergeInto(loadedGlobal);
      expect(
        withA.tryComponent<SuperValueConfig>('val-a')?.initialText,
        'Texte Page A',
      );
      expect(withA.tryComponent<SuperValueConfig>('val-b'), isNull);

      // Modify page-a only and save: page-b.json must stay untouched on disk.
      final pageBBeforeText = pageBFile.readAsStringSync();
      final edited = withA.withValueComponent(
        'val-a',
        const SuperValueConfig(initialText: 'Texte Page A Modifié'),
      );
      await fresh.save(edited);

      expect(pageBFile.readAsStringSync(), pageBBeforeText);
      expect(
        (jsonDecode(pageAFile.readAsStringSync())['components'] as Map)['val-a']['initialText'],
        'Texte Page A Modifié',
      );

      // Remove page-b from pageCatalog and save: page-b.json is deleted.
      final withoutB = edited.copyWith(
        pageCatalog: EditorPageCatalog(
          pages: [
            EditorPageConfig(id: 'page-a', name: 'Page A', path: '/page-a'),
          ],
        ),
      );
      await fresh.save(withoutB);
      expect(pageBFile.existsSync(), isFalse);
      expect(pageAFile.existsSync(), isTrue);
    });

    test('cloning sandboxed application copies pages directory and isolates edits', () async {
      final appStore = SandboxedApplicationStore();
      final appADir = Directory('${tempDir.path}${Platform.pathSeparator}app_a');
      await appStore.createApplication(appADir, name: 'App A');

      final storeA = SandboxedApplicationStore.appearanceStoreFor(appADir);
      await storeA.save(_twoPagesAppearance());

      final appBDir = Directory('${tempDir.path}${Platform.pathSeparator}app_b');
      await appStore.createApplication(
        appBDir,
        name: 'App B',
        cloneFromDirectory: appADir,
      );

      final clonedPageAFile = SandboxedApplicationStore.pageFileFor(appBDir, 'page-a');
      expect(clonedPageAFile.existsSync(), isTrue);

      final storeB = SandboxedApplicationStore.appearanceStoreFor(appBDir);
      final loadedB = await storeB.load();
      final sliceBPageA = await storeB.loadPage('page-a');
      final mergedB = sliceBPageA.mergeInto(loadedB);
      expect(
        mergedB.tryComponent<SuperValueConfig>('val-a')?.initialText,
        'Texte Page A',
      );

      // Edit App B page-a; App A stays untouched.
      await storeB.save(
        mergedB.withValueComponent(
          'val-a',
          const SuperValueConfig(initialText: 'Only in B'),
        ),
      );

      final reloadA = SandboxedApplicationStore.appearanceStoreFor(appADir);
      final sliceAPageA = await reloadA.loadPage('page-a');
      expect(
        (sliceAPageA.components['val-a'] as SuperValueConfig).initialText,
        'Texte Page A',
      );
    });

    test('load, loadPage and save offload large payloads in Isolate without capturing store futures', () async {
      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app_iso');
      final store = PagedFileAppearanceStore(
        SandboxedApplicationStore.appearanceFileFor(appDir),
        pagesDirectory: SandboxedApplicationStore.pagesDirectoryFor(appDir),
        isolateThresholdBytes: 1,
        isolateThresholdEntries: 1,
      );

      await store.save(_twoPagesAppearance());

      final reload = PagedFileAppearanceStore(
        SandboxedApplicationStore.appearanceFileFor(appDir),
        pagesDirectory: SandboxedApplicationStore.pagesDirectoryFor(appDir),
        isolateThresholdBytes: 1,
        isolateThresholdEntries: 1,
      );
      final loaded = await reload.load();
      expect(loaded.pageCatalog.pages, hasLength(2));

      final sliceA = await reload.loadPage('page-a');
      expect(
        (sliceA.components['val-a'] as SuperValueConfig).initialText,
        'Texte Page A',
      );
    });
  });

  group('PersistentAppearanceController & EditorHistoryController hydration', () {
    test('ensurePageLoaded hydrates without triggering save or breaking Undo/Redo', () async {
      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app_hist');
      final seedStore = SandboxedApplicationStore.appearanceStoreFor(appDir);
      await seedStore.save(_twoPagesAppearance());

      final store = SandboxedApplicationStore.appearanceStoreFor(appDir);
      final controller = PersistentAppearanceController(
        store,
        (err) => fail('Unexpected save error: $err'),
        persistDelay: Duration.zero,
      );
      addTearDown(controller.dispose);

      await controller.restore();
      final editMode = ValueNotifier<bool>(true);
      addTearDown(editMode.dispose);
      final history = EditorHistoryController(
        appearance: controller,
        editMode: editMode,
      );
      addTearDown(history.dispose);

      // Load page-a first and edit it so Undo stack has an entry.
      await controller.ensurePageLoaded('page-a');
      expect(history.canUndo, isFalse);

      controller.value = controller.value.withValueComponent(
        'val-a',
        const SuperValueConfig(initialText: 'Modif 1'),
      );
      await controller.saved;
      expect(history.canUndo, isTrue);

      // Now hydrate page-b: should NOT push to undo stack or clear it.
      await controller.ensurePageLoaded('page-b');
      expect(controller.isPageLoaded('page-b'), isTrue);
      expect(
        controller.value.tryComponent<SuperValueConfig>('val-b')?.initialText,
        'Texte Page B',
      );
      expect(history.canUndo, isTrue);

      // Undo restores val-a while keeping hydrated page-b intact.
      history.undo();
      expect(
        controller.value.tryComponent<SuperValueConfig>('val-a')?.initialText,
        'Texte Page A',
      );
      expect(
        controller.value.tryComponent<SuperValueConfig>('val-b')?.initialText,
        'Texte Page B',
      );

      history.redo();
      expect(
        controller.value.tryComponent<SuperValueConfig>('val-a')?.initialText,
        'Modif 1',
      );
      expect(
        controller.value.tryComponent<SuperValueConfig>('val-b')?.initialText,
        'Texte Page B',
      );
      await controller.saved;
    });
  });

  group('Widget integration: lazy route loading, home preload, page manager, transfer', () {
    Future<void> pumpAsync(
      WidgetTester tester,
      Future<void> Function() action,
    ) async {
      await tester.runAsync(() async {
        await action();
        for (var i = 0; i < 20; i++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
    }

    testWidgets('SuperApp preloads homePageId and loads other pages on demand during navigation', (tester) async {
      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app_nav');
      final repoDir = Directory('${appDir.path}${Platform.pathSeparator}repositories');
      final repoStore = JsonRepositoryStore(repoDir);
      addTearDown(repoStore.dispose);

      final seed = SandboxedApplicationStore.appearanceStoreFor(appDir);
      final seeded = _twoPagesAppearance().copyWith(
        pageCatalog: EditorPageCatalog(
          homePageId: 'page-a',
          pages: [
            EditorPageConfig(id: 'page-a', name: 'Page A', path: '/page-a'),
            EditorPageConfig(id: 'page-b', name: 'Page B', path: '/page-b'),
          ],
        ),
      );
      await tester.runAsync(() => seed.save(seeded));

      final registry = Registry()..bootstrap();
      addTearDown(registry.dispose);
      final store = SandboxedApplicationStore.appearanceStoreFor(
        appDir,
        registry: registry,
      );
      final routing = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const SuperPage(child: Text('Coded Home')),
            ),
          ],
        ),
      );
      addTearDown(routing.dispose);

      await pumpAsync(tester, () async {
        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            appearanceStore: store,
            repositoryStore: repoStore,
          ),
        );
      });

      // homePageId (page-a) was preloaded at startup; page-b is still unloaded.
      expect(store.isPageLoaded('page-a'), isTrue);
      expect(store.isPageLoaded('page-b'), isFalse);
      expect(find.text('Texte Page A'), findsOneWidget);

      // Navigating to /page-b triggers on-demand loading of pages/page-b.json.
      await pumpAsync(tester, () async {
        routing.router.go('/page-b');
      });

      expect(store.isPageLoaded('page-b'), isTrue);
      expect(find.text('Texte Page B'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('VibeDiagnosticsInspector previewNavigationOrSelection loads target page on demand', (tester) async {
      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app_vibe');
      final repoDir = Directory('${appDir.path}${Platform.pathSeparator}repositories');
      final repoStore = JsonRepositoryStore(repoDir);
      addTearDown(repoStore.dispose);

      await tester.runAsync(
        () => SandboxedApplicationStore.appearanceStoreFor(appDir).save(
          _twoPagesAppearance(),
        ),
      );

      final registry = Registry()..bootstrap();
      addTearDown(registry.dispose);
      final store = SandboxedApplicationStore.appearanceStoreFor(
        appDir,
        registry: registry,
      );
      final routing = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const SuperPage(child: Text('Coded Home')),
            ),
          ],
        ),
      );
      addTearDown(routing.dispose);

      await pumpAsync(tester, () async {
        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            appearanceStore: store,
            repositoryStore: repoStore,
          ),
        );
      });

      final context = tester.element(find.byType(SuperPage));
      final controller =
          AppearanceScope.controllerOf(context)! as PersistentAppearanceController;
      expect(store.isPageLoaded('page-b'), isFalse);

      final inspector = VibeAppInspector(
        readAppearance: () => controller.value,
        registry: registry,
        repositoryStore: repoStore,
        pageRouting: routing,
        ensurePageLoaded: controller.ensurePageLoaded,
      );

      await pumpAsync(tester, () async {
        final result = await inspector.previewNavigationOrSelection(
          'call-1',
          'preview_navigation_or_selection',
          const {'pageId': 'page-b'},
        );
        expect(result.isError, isFalse);
      });

      expect(store.isPageLoaded('page-b'), isTrue);
      expect(find.text('Texte Page B'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('EditorPageManager loads unloaded page on demand before duplicating and AppearanceTransferDialog loads all pages before export', (tester) async {
      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app_mgr');
      final repoDir = Directory('${appDir.path}${Platform.pathSeparator}repositories');
      final repoStore = JsonRepositoryStore(repoDir);
      addTearDown(repoStore.dispose);

      await tester.runAsync(
        () => SandboxedApplicationStore.appearanceStoreFor(appDir).save(
          _twoPagesAppearance(),
        ),
      );

      final registry = Registry()..bootstrap();
      addTearDown(registry.dispose);
      final store = SandboxedApplicationStore.appearanceStoreFor(
        appDir,
        registry: registry,
      );
      final routing = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const SuperPage(child: Text('Coded Home')),
            ),
          ],
        ),
      );
      addTearDown(routing.dispose);

      await pumpAsync(tester, () async {
        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            appearanceStore: store,
            repositoryStore: repoStore,
          ),
        );
      });

      // Neither page-a nor page-b is loaded on '/' initially.
      expect(store.isPageLoaded('page-a'), isFalse);
      expect(store.isPageLoaded('page-b'), isFalse);

      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      // Open Page Manager and duplicate unloaded page-b.
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-pages')));
      await tester.pumpAndSettle();

      final duplicateButton = find.descendant(
        of: find.byKey(const ValueKey('editor-page-row-page-b')),
        matching: find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Dupliquer',
        ),
      );
      await tester.tap(duplicateButton);
      await tester.pumpAndSettle();

      await pumpAsync(tester, () async {
        await tester.tap(find.text('Valider'));
      });

      expect(store.isPageLoaded('page-b'), isTrue);

      await pumpAsync(tester, () async {
        await tester.tap(find.text('Appliquer'));
      });

      // Open AppearanceTransferDialog: must load remaining unloaded page-a for full export.
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-settings')));
      await tester.pumpAndSettle();
      await pumpAsync(tester, () async {
        await tester.tap(find.byKey(const ValueKey('style-edit-banner-transfer')));
      });

      expect(store.isPageLoaded('page-a'), isTrue);
      final exportField = tester.widget<TextField>(
        find.byKey(const ValueKey('transfer-export-text')),
      );
      expect(exportField.controller!.text, contains('Texte Page A'));
      expect(exportField.controller!.text, contains('Texte Page B'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('PagedFileAppearanceStore with shared shells', () {
    Appearance shelledAppearance() => Appearance(
      styles: {
        'background': const ContainerStyle(color: Color(0xFF101010)),
        'shell-nav': const ContainerStyle(color: Color(0xFF202020)),
        'val-a': const ContainerStyle(color: Color(0xFFAA0000)),
      },
      components: {
        'root': ScaffoldPageConfig(
          placements: const {
            ScaffoldPageRegion.body: ['mainLayout'],
          },
          slotTypes: const {'mainLayout': 'registry:Layout'},
        ),
        'mainLayout': const SuperLayoutConfig(),
        'main-shell': ScaffoldPageConfig(
          placements: const {
            ScaffoldPageRegion.sidebarStart: ['shell-nav'],
            ScaffoldPageRegion.body: ['scaffold:outlet'],
          },
          regions: const {ScaffoldPageRegion.sidebarStart: true},
          slotTypes: const {'shell-nav': 'registry:Value'},
          sidebarStartWidth: 240,
        ),
        'shell-nav': const SuperValueConfig(initialText: 'Shell Sidebar'),
        'page-a': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['val-a'],
          },
          slotTypes: {'val-a': 'registry:Value'},
        ),
        'val-a': const SuperValueConfig(initialText: 'Page A Body'),
        'page-b': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['val-b'],
          },
          slotTypes: {'val-b': 'registry:Value'},
        ),
        'val-b': const SuperValueConfig(initialText: 'Page B Body'),
      },
      pageCatalog: EditorPageCatalog(
        rootShellId: 'main-shell',
        shells: [EditorShellConfig(id: 'main-shell', name: 'Main Shell')],
        pages: [
          EditorPageConfig(
            id: 'page-a',
            name: 'Page A',
            path: '/page-a',
            shellId: 'main-shell',
          ),
          EditorPageConfig(
            id: 'page-b',
            name: 'Page B',
            path: '/page-b',
            shellId: 'main-shell',
          ),
        ],
      ),
    );

    test('persists shells in appearance.json, lazy-loads shelled pages, and persists detach/remove cleanly', () async {
      final registry = Registry()..bootstrap();
      addTearDown(registry.dispose);

      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app_shells');
      final store = SandboxedApplicationStore.appearanceStoreFor(
        appDir,
        registry: registry,
      );

      await store.save(shelledAppearance());

      final globalFile = SandboxedApplicationStore.appearanceFileFor(appDir);
      final shellFile = SandboxedApplicationStore.pageFileFor(appDir, 'main-shell');
      final pageAFile = SandboxedApplicationStore.pageFileFor(appDir, 'page-a');
      final pageBFile = SandboxedApplicationStore.pageFileFor(appDir, 'page-b');

      expect(globalFile.existsSync(), isTrue);
      expect(shellFile.existsSync(), isFalse);
      expect(pageAFile.existsSync(), isTrue);
      expect(pageBFile.existsSync(), isTrue);

      final globalJson = jsonDecode(globalFile.readAsStringSync()) as Map<String, dynamic>;
      final globalComponents = globalJson['components'] as Map;
      expect(globalComponents.keys, containsAll(['root', 'mainLayout', 'main-shell', 'shell-nav']));
      expect(globalComponents.keys, isNot(contains('page-a')));
      expect(globalComponents.keys, isNot(contains('val-a')));

      // Fresh load: shells are immediately available in global; pages lazy-load on demand.
      final fresh = SandboxedApplicationStore.appearanceStoreFor(
        appDir,
        registry: registry,
      );
      final loaded = await fresh.load();
      expect(fresh.isKnownCatalogShell('main-shell'), isTrue);
      expect(fresh.isKnownCatalogPage('main-shell'), isFalse);
      expect(fresh.isPageLoaded('page-a'), isFalse);
      expect(loaded.components.containsKey('main-shell'), isTrue);
      expect(loaded.components.containsKey('shell-nav'), isTrue);
      expect(loaded.components.containsKey('page-a'), isFalse);

      // Calling loadPage on a shell ID is a safe no-op returning an empty slice.
      final emptyShellSlice = await fresh.loadPage('main-shell');
      expect(emptyShellSlice.isEmpty, isTrue);
      expect(fresh.isPageLoaded('main-shell'), isFalse);

      // Lazy-load page-a and detach it from main-shell; page-b stays untouched on disk.
      final pageBBefore = pageBFile.readAsStringSync();
      final withPageA = (await fresh.loadPage('page-a')).mergeInto(loaded);
      final detached = EditorPageGraph.detachPageFromShell(
        appearance: withPageA,
        registry: registry,
        pageId: 'page-a',
      );
      await fresh.save(detached);

      expect(shellFile.existsSync(), isFalse);
      expect(pageBFile.readAsStringSync(), pageBBefore);
      final pageAJson = jsonDecode(pageAFile.readAsStringSync()) as Map<String, dynamic>;
      expect((pageAJson['components'] as Map).keys, containsAll(['page-a', 'page-a-body', 'val-a']));
      final globalAfterDetach = jsonDecode(globalFile.readAsStringSync()) as Map<String, dynamic>;
      expect((globalAfterDetach['components'] as Map).keys, containsAll(['main-shell', 'shell-nav']));

      // Remove main-shell and persist: shell & exclusive chrome disappear from appearance.json.
      final removed = EditorPageGraph.removeShell(
        appearance: detached,
        registry: registry,
        shellId: 'main-shell',
      ).appearance;
      await fresh.save(removed);

      expect(shellFile.existsSync(), isFalse);
      expect(fresh.isKnownCatalogShell('main-shell'), isFalse);
      final globalAfterRemove = jsonDecode(globalFile.readAsStringSync()) as Map<String, dynamic>;
      final globalCompsAfterRemove = globalAfterRemove['components'] as Map;
      expect(globalCompsAfterRemove.containsKey('main-shell'), isFalse);
      expect(globalCompsAfterRemove.containsKey('shell-nav'), isFalse);
    });
  });
}
