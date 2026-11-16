import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/datasources/datasource_config.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/providers/data_provider.dart';
import 'package:super_container_layout/services/repositories/json_repository_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/editing/datasources/datasource_manager.dart';

const _target = JsonTextBinding(repositoryId: 'resultats', path: 'rows');

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late List<DataProviderRequest> requests;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('datasource-manager-');
    store = JsonRepositoryStore(directory);
    requests = [];
    store.registerRepository(
      RepositoryImpl(id: 'filtre', json: {'q': 'dupont'}),
    );
    store.registerRepository(
      RepositoryImpl(id: 'resultats', json: {'rows': <Object?>[]}),
    );
    store.providers.register(
      CallbackDataProvider(
        id: 'clients_search',
        label: 'Recherche',
        filterRepositoryId: 'filtre',
        target: _target,
        onExecute: (request) async {
          requests.add(request);
          final rows = [
            for (var i = 1; i <= 3; i++) {'id': i, 'nom': 'Client $i'},
          ];
          final page = request.context['page']! as int;
          final size = request.context['pageSize']! as int;
          final slice = rows.skip((page - 1) * size).take(size).toList();
          return DataProviderResult(
            data: slice,
            raw: {'items': slice, 'total': rows.length},
          );
        },
      ),
    );
    store.providers.register(
      CallbackDataProvider(
        id: 'clients_delete',
        label: 'Suppression',
        onExecute: (_) async => const DataProviderResult(),
      ),
    );
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  File datasourceFile(String id) => File(
    '${directory.path}${Platform.pathSeparator}datasources'
    '${Platform.pathSeparator}$id.json',
  );

  Future<void> settle(WidgetTester tester) async {
    // File I/O runs outside the widget test's fake clock: alternate frames and
    // real delays until no progress indicator remains.
    final progress = find.byWidgetPredicate(
      (widget) => widget is ProgressIndicator,
    );
    for (var i = 0; i < 50; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (i >= 2 && progress.evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, Finder field, String item) async {
    await tap(tester, field);
    await tap(tester, find.text(item).last);
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await settle(tester);
  }

  String? text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data;

  Future<List<String?>> open(
    WidgetTester tester, {
    ValueNotifier<Appearance>? appearance,
    String? initialDatasourceId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final results = <String?>[];
    await tester.pumpWidget(
      JsonRepositoryScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DatasourceManager(
                    store: store,
                    appearance: appearance,
                    initialDatasourceId: initialDatasourceId,
                  ),
                ).then(results.add),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settle(tester);
    return results;
  }

  const expected = DatasourceConfig(
    id: 'clients',
    label: 'Clients',
    keyPath: 'id',
    search: DatasourceSearchConfig(
      provider: 'clients_search',
      pagination: DatasourcePagination(pageSize: 2, totalPath: 'total'),
    ),
    delete: DatasourceEntityConfig(provider: 'clients_delete'),
  );

  testWidgets('creates, tests, saves and runs a datasource', (tester) async {
    final results = await open(tester);
    expect(find.text('Aucune datasource.'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('datasource-create')));
    expect(find.byKey(const ValueKey('datasource-entry-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('datasource-search')), findsNothing);

    await type(tester, 'datasource-id', 'clients');
    await type(tester, 'datasource-label', 'Clients');
    expect(text(tester, 'datasource-form-error'), isNotNull);

    await choose(
      tester,
      find.byKey(const ValueKey('datasource-provider-delete')),
      'Suppression (clients_delete)',
    );
    expect(text(tester, 'datasource-form-error'), contains('clé'));
    await type(tester, 'datasource-key-path', 'id');
    await choose(
      tester,
      find.byKey(const ValueKey('datasource-provider-search')),
      'Recherche (clients_search)',
    );
    await tap(tester, find.byKey(const ValueKey('datasource-pagination')));
    await type(tester, 'datasource-page-size', '2');
    await type(tester, 'datasource-total-path', 'total');
    expect(find.byKey(const ValueKey('datasource-form-error')), findsNothing);

    await tap(tester, find.byKey(const ValueKey('datasource-test')));
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('datasource-test-result')),
          )
          .data,
      allOf(contains('2 ligne(s) reçue(s) sur 3.'), contains('"Client 1"')),
    );
    expect(requests.single.parameters, {'q': 'dupont'});
    expect(store.peekDocument('resultats')?.document, {'rows': <Object?>[]});
    expect(
      await tester.runAsync(() => datasourceFile('clients').exists()),
      false,
    );

    await tap(tester, find.byKey(const ValueKey('datasource-save')));
    expect(find.text('Datasource enregistrée.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('datasource-entry-clients')),
      findsOneWidget,
    );
    expect(store.datasources.datasource('clients'), expected);
    final saved = await tester.runAsync(
      () => datasourceFile('clients').readAsString(),
    );
    expect(jsonDecode(saved!), expected.toJson());

    expect(text(tester, 'datasource-status'), 'Aucune commande lancée.');
    await tap(tester, find.byKey(const ValueKey('datasource-search')));
    expect(
      text(tester, 'datasource-status'),
      'Commande « Rechercher » terminée : page 1 sur 2 (3 ligne(s) au total) '
      '· page suivante disponible.',
    );
    expect(store.peekDocument('resultats')?.document, {
      'rows': [
        {'id': 1, 'nom': 'Client 1'},
        {'id': 2, 'nom': 'Client 2'},
      ],
    });

    await tap(tester, find.byKey(const ValueKey('datasource-close')));
    expect(find.byType(DatasourceManager), findsNothing);
    expect(results, ['clients']);
  });

  testWidgets('code datasources are read-only and used ones are kept', (
    tester,
  ) async {
    store.datasources.register(
      const DatasourceConfig(
        id: 'code',
        label: 'Code',
        search: DatasourceSearchConfig(provider: 'clients_search'),
      ),
    );
    await tester.runAsync(() => store.datasources.save(expected));
    final appearance = ValueNotifier(
      Appearance(
        behaviors: {
          'button': [
            const ComponentBehavior(
              id: 'search',
              trigger: BehaviorTrigger.click,
              action: DatasourceAction(datasourceId: 'clients'),
            ),
          ],
        },
      ),
    );
    addTearDown(appearance.dispose);
    final results = await open(
      tester,
      appearance: appearance,
      initialDatasourceId: 'code',
    );

    expect(find.byKey(const ValueKey('datasource-readonly')), findsOneWidget);
    expect(find.byKey(const ValueKey('datasource-delete')), findsNothing);
    expect(find.byKey(const ValueKey('datasource-id')), findsNothing);

    await tap(tester, find.byKey(const ValueKey('datasource-entry-clients')));
    await type(tester, 'datasource-label', 'Clients modifiés');
    final search = find.byKey(const ValueKey('datasource-search'));
    expect(tester.widget<TextButton>(search).onPressed, isNull);
    await tap(tester, find.byKey(const ValueKey('datasource-entry-code')));
    expect(
      find.byKey(const ValueKey('datasource-confirm-discard')),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const ValueKey('datasource-confirm-discard')));
    expect(find.byKey(const ValueKey('datasource-readonly')), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('datasource-entry-clients')));
    await tap(tester, find.byKey(const ValueKey('datasource-delete')));
    expect(
      text(tester, 'datasource-manager-error'),
      contains('encore utilisée par un comportement'),
    );
    expect(
      find.byKey(const ValueKey('datasource-confirm-delete')),
      findsNothing,
    );

    appearance.value = Appearance();
    await tap(tester, find.byKey(const ValueKey('datasource-delete')));
    await tap(tester, find.byKey(const ValueKey('datasource-confirm-delete')));
    expect(find.text('Datasource supprimée.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('datasource-entry-clients')),
      findsNothing,
    );
    expect(
      await tester.runAsync(() => datasourceFile('clients').exists()),
      false,
    );
    expect(store.datasources.datasource('clients'), isNull);

    await tap(tester, find.byKey(const ValueKey('datasource-close')));
    expect(results, [null]);
  });
}
