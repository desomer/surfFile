import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/overlay/style_edit_banner.dart';

void main() {
  Future<({Directory dir, JsonRepositoryStore store, String repoId})>
  createStoreWithData() async {
    final dir = await Directory.systemTemp.createTemp('bulk-delete-test-');
    final store = JsonRepositoryStore(dir);
    store.superBackend = SuperBackend(store: SqliteCollectionStore.inMemory());
    await store.superBackend.init();
    await store.superBackend.create('clients', {'name': 'Alice'}, id: 'c1');
    await store.superBackend.create('clients', {'name': 'Bob'}, id: 'c2');

    // Repository fourni par le code hôte (doit être préservé).
    store.registerRepository(
      RepositoryImpl(id: 'host_repo', json: {'ready': true}),
    );

    // Repository fichier utilisateur avec schéma JSON.
    const repoId = '0123456789abcdef0123456789abcdef';
    await store.createWithId(
      'Clients',
      id: repoId,
      initialDocument: {
        'items': [
          {'name': 'Alice'},
        ],
      },
      jsonSchema: {
        'type': 'object',
        'properties': {
          'items': {'type': 'array'},
        },
      },
    );

    await store.providers.save(
      HttpProviderConfig(
        id: 'search_clients',
        label: 'Rechercher clients',
        target: const JsonTextBinding(repositoryId: repoId, path: 'items'),
        request: HttpRequestTemplate(url: 'https://api.example.com/clients'),
      ),
    );
    await store.datasources.save(
      const DatasourceConfig(
        id: 'ds_clients',
        label: 'Clients',
        keyPath: 'name',
        search: DatasourceSearchConfig(provider: 'search_clients'),
      ),
    );

    return (dir: dir, store: store, repoId: repoId);
  }

  Appearance buildSampleAppearance(String repoId) {
    final page = EditorPageConfig(
      id: 'page-clients',
      name: 'Clients',
      path: '/clients',
      shellId: 'shell-main',
    );
    final shell = EditorShellConfig(
      id: 'shell-main',
      name: 'Navigation',
    );
    return Appearance(
      mode: ThemeMode.dark,
      accent: const Color(0xFFAA2244),
      styles: const {
        'background': ContainerStyle(color: Color(0xFF111111)),
        'card-1': ContainerStyle(radius: 12),
      },
      components: {
        'mainLayout': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['root-label'],
          },
          slotTypes: {
            'root-label': 'registry:Value',
          },
        ),
        'root-label': const SuperValueConfig(initialText: 'Racine'),
        'shell-main': ScaffoldPageConfig(
          placements: const {
            ScaffoldPageRegion.body: [EditorPageGraph.outletSlotId],
          },
        ),
        'page-clients': ScaffoldPageConfig(
          placements: const {
            ScaffoldPageRegion.body: ['client-title'],
          },
          slotTypes: const {
            'client-title': 'registry:Value',
          },
        ),
        'client-title': SuperValueConfig(
          binding: JsonTextBinding(
            repositoryId: repoId,
            path: 'items[0].name',
          ),
        ),
      },
      behaviors: const {
        'client-title': [
          ComponentBehavior(
            id: 'b1',
            trigger: BehaviorTrigger.onTap,
            action: DatasourceAction(
              datasourceId: 'ds_clients',
              command: DatasourceCommand.search,
            ),
          ),
        ],
      },
      pageCatalog: EditorPageCatalog(
        homePageId: 'page-clients',
        rootShellId: 'shell-main',
        pages: [page],
        shells: [shell],
      ),
    );
  }

  test('BulkDeleteService inspecte les compteurs et dépendances croisées', () async {
    final setup = await createStoreWithData();
    addTearDown(() async {
      setup.store.dispose();
      await setup.dir.delete(recursive: true);
    });

    final registry = Registry()..bootstrap();
    addTearDown(registry.dispose);
    final appearance = ValueNotifier(buildSampleAppearance(setup.repoId));
    addTearDown(appearance.dispose);
    addTearDown(clearDebugEntries);

    clearDebugEntries();
    saveLog('Info log');
    saveError('Erreur test', null);

    final inspection = await BulkDeleteService.inspect(
      appearanceController: appearance,
      registry: registry,
      repositoryStore: setup.store,
    );

    expect(inspection.pageCount, 1);
    expect(inspection.shellCount, 1);
    expect(inspection.componentCount, 5);
    expect(inspection.behaviorCount, 1);
    expect(inspection.styleCount, 2);
    expect(inspection.fileRepositories.length, 1);
    expect(inspection.registeredRepositoryCount, 1);
    expect(inspection.editableProviderIds, ['search_clients']);
    expect(inspection.editableDatasourceIds, ['ds_clients']);
    expect(inspection.superBackendCollections, ['clients']);
    expect(inspection.superBackendRowCount, 2);
    expect(inspection.debugEntryCount, 2);
    expect(inspection.debugErrorCount, 1);
    expect(inspection.hasCustomThemeOrGlobal, isTrue);

    final depsRepoOnly = inspection.analyzeDependencies({
      BulkDeleteTarget.repositories,
    });
    expect(depsRepoOnly.hasWarnings, isTrue);
    expect(depsRepoOnly.boundRepositoryNames, ['Clients']);
    expect(depsRepoOnly.providerUsedRepositoryNames, ['Clients']);
    expect(depsRepoOnly.suggestPagesAndShells, isTrue);
    expect(depsRepoOnly.suggestProvidersAndDatasources, isTrue);

    final depsAll = inspection.analyzeDependencies(inspection.availableTargets);
    expect(depsAll.hasWarnings, isFalse);
  });

  test('BulkDeleteService exécute des suppressions sélectives et préserve le reste', () async {
    final setup = await createStoreWithData();
    addTearDown(() async {
      setup.store.dispose();
      await setup.dir.delete(recursive: true);
    });

    final registry = Registry()..bootstrap();
    addTearDown(registry.dispose);
    final appearance = ValueNotifier(buildSampleAppearance(setup.repoId));
    registry.bindAppearance(appearance);
    addTearDown(appearance.dispose);
    addTearDown(clearDebugEntries);

    clearDebugEntries();
    saveLog('Test debug log');
    saveError('Test debug error', null);

    // 1. Supprimer uniquement les styles.
    final stylesResult = await BulkDeleteService.execute(
      appearanceController: appearance,
      targets: const {BulkDeleteTarget.styles},
      registry: registry,
      repositoryStore: setup.store,
    );
    expect(stylesResult.deletedStyles, 2);
    expect(appearance.value.styles, isEmpty);
    expect(appearance.value.pageCatalog.pages, hasLength(1));
    expect(appearance.value.mode, ThemeMode.dark);

    // 2. Supprimer uniquement les pages, le contenu racine et les Shells.
    final pagesResult = await BulkDeleteService.execute(
      appearanceController: appearance,
      targets: const {BulkDeleteTarget.pagesAndShells},
      registry: registry,
      repositoryStore: setup.store,
    );
    expect(pagesResult.deletedPages, 1);
    expect(pagesResult.deletedShells, 1);
    expect(pagesResult.deletedComponents, 5);
    expect(appearance.value.pageCatalog.pages, isEmpty);
    expect(appearance.value.pageCatalog.shells, isEmpty);
    expect(appearance.value.components, isEmpty);
    expect(appearance.value.behaviors, isEmpty);
    expect(appearance.value.usages, isEmpty);
    expect(
      registry.layoutController('mainLayout').value,
      const SuperLayoutConfig(),
    );

    // 3. Supprimer uniquement le thème et réglages globaux.
    final themeResult = await BulkDeleteService.execute(
      appearanceController: appearance,
      targets: const {BulkDeleteTarget.themeAndGlobal},
      registry: registry,
      repositoryStore: setup.store,
    );
    expect(themeResult.resetThemeAndGlobal, isTrue);
    expect(appearance.value.mode, ThemeMode.light);

    // 4. Supprimer les logs de debug.
    final logsResult = await BulkDeleteService.execute(
      appearanceController: appearance,
      targets: const {BulkDeleteTarget.debugLogs},
      registry: registry,
      repositoryStore: setup.store,
    );
    expect(logsResult.clearedDebugEntries, 2);
    expect(debugEntries, isEmpty);

    // 4. Supprimer les repositories fichiers avec force=true malgré le provider.
    final repoResult = await BulkDeleteService.execute(
      appearanceController: appearance,
      targets: const {BulkDeleteTarget.repositories},
      registry: registry,
      repositoryStore: setup.store,
      force: true,
    );
    expect(repoResult.deletedRepositories, 1);
    expect(
      (await setup.store.catalog())
          .where((e) => !setup.store.isRegisteredRepository(e.id)),
      isEmpty,
    );
    expect(setup.store.isRegisteredRepository('host_repo'), isTrue);

    // 5. Supprimer providers, datasources et SuperBackend.
    final providersResult = await BulkDeleteService.execute(
      appearanceController: appearance,
      targets: const {BulkDeleteTarget.providersAndDatasources},
      registry: registry,
      repositoryStore: setup.store,
      force: true,
    );
    expect(providersResult.deletedDatasources, 1);
    expect(providersResult.deletedProviders, 1);
    expect(providersResult.clearedBackendCollections, 1);
    expect(providersResult.clearedBackendRows, 2);
    expect(setup.store.providers.providers, isEmpty);
    expect(setup.store.datasources.datasources, isEmpty);
    expect(await setup.store.superBackend.listCollections(), isEmpty);
  });

  Future<void> settle(WidgetTester tester) async {
    // File I/O runs outside the widget test's fake clock.
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('StyleEditBanner ouvre « Tout supprimer… » et confirme sur la cible', (
    tester,
  ) async {
    final setup = (await tester.runAsync(createStoreWithData))!;
    addTearDown(() async {
      await tester.runAsync(() async {
        setup.store.dispose();
        await setup.dir.delete(recursive: true);
      });
    });

    final editMode = ValueNotifier(true);
    final appearance = ValueNotifier(buildSampleAppearance(setup.repoId));
    addTearDown(editMode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(clearDebugEntries);

    clearDebugEntries();
    saveLog('Widget test log');
    saveError('Widget test error', null);

    await tester.pumpWidget(
      JsonRepositoryScope(
        store: setup.store,
        child: StyleEditScope(
          controller: editMode,
          child: AppearanceScope(
            controller: appearance,
            child: AppearanceServicesScope(
              codec: const AppearanceCodec(),
              child: MaterialApp(
                home: Scaffold(
                  body: Stack(
                    children: [Positioned.fill(child: StyleEditBanner())],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // Ouvre la molette des paramètres.
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-settings')));
    await tester.pumpAndSettle();
    final deleteMenuItem = find.byKey(
      const ValueKey('style-edit-banner-delete-all'),
    );
    expect(deleteMenuItem, findsOneWidget);

    await tester.tap(deleteMenuItem);
    await settle(tester);
    expect(find.byKey(const ValueKey('bulk-delete-dialog')), findsOneWidget);

    // Le bouton de validation est désactivé tant qu'aucune cible n'est cochée.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('bulk-delete-submit')))
          .onPressed,
      isNull,
    );

    // Sélectionner uniquement les repositories fait apparaître l'avertissement de dépendance.
    final repoCheckbox = find.byKey(
      const ValueKey('bulk-delete-target-repositories'),
    );
    await tester.ensureVisible(repoCheckbox);
    await tester.pumpAndSettle();
    await tester.tap(repoCheckbox);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bulk-delete-dependencies-warning')),
      findsOneWidget,
    );

    // Ouvre la confirmation puis annule : rien n'est supprimé.
    await tester.tap(find.byKey(const ValueKey('bulk-delete-submit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bulk-delete-confirm-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bulk-delete-confirm-dependencies')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('bulk-delete-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(() => setup.store.catalog()))!
          .where((e) => !setup.store.isRegisteredRepository(e.id)),
      hasLength(1),
    );

    // Sélectionne toutes les cibles disponibles et confirme.
    final selectAll = find.byKey(const ValueKey('bulk-delete-select-all'));
    await tester.ensureVisible(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-delete-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-delete-confirm-submit')));
    await settle(tester);

    expect(find.byKey(const ValueKey('bulk-delete-dialog')), findsNothing);
    expect(appearance.value.pageCatalog.pages, isEmpty);
    expect(appearance.value.pageCatalog.shells, isEmpty);
    expect(appearance.value.components, isEmpty);
    expect(appearance.value.behaviors, isEmpty);
    expect(appearance.value.styles, isEmpty);
    expect(appearance.value.mode, ThemeMode.light);
    expect(debugEntries, isEmpty);
    expect(setup.store.providers.providers, isEmpty);
    expect(setup.store.datasources.datasources, isEmpty);
    expect(
      (await tester.runAsync(() => setup.store.catalog()))!
          .where((e) => !setup.store.isRegisteredRepository(e.id)),
      isEmpty,
    );
    expect(
      await tester.runAsync(() => setup.store.superBackend.listCollections()),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
