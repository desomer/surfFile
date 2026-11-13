import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/providers/data_provider.dart';
import 'package:super_container_layout/models/providers/http_provider_config.dart';
import 'package:super_container_layout/services/providers/data_provider_http_transport.dart';
import 'package:super_container_layout/services/repositories/json_repository_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/editing/providers/data_provider_manager.dart';

const _target = JsonTextBinding(repositoryId: 'resultats', path: 'rows');

class _FakeTransport extends DataProviderHttpTransport {
  final requests = <DataProviderHttpRequest>[];

  @override
  Future<DataProviderHttpResponse> send(DataProviderHttpRequest request) async {
    requests.add(request);
    return const DataProviderHttpResponse(
      statusCode: 200,
      body: '[{"nom": "Dupont"}]',
    );
  }
}

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late _FakeTransport transport;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('provider-manager-');
    store = JsonRepositoryStore(directory);
    transport = _FakeTransport();
    store.providers.httpTransport = transport;
    store.registerRepository(
      RepositoryImpl(id: 'filtre', json: {'q': 'dupont'}),
    );
    store.registerRepository(
      RepositoryImpl(id: 'resultats', json: {'rows': <Object?>[]}),
    );
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  File providerFile(String id) => File(
    '${directory.path}${Platform.pathSeparator}providers'
    '${Platform.pathSeparator}$id.json',
  );

  Future<void> settle(WidgetTester tester) async {
    // File I/O runs outside the widget test's fake clock: alternate frames and
    // real delays until no progress indicator remains.
    final progress = find.byWidgetPredicate(
      (widget) =>
          widget is ProgressIndicator ||
          widget is Text && widget.data == 'Chargement des repositories…',
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

  Future<List<String?>> open(
    WidgetTester tester, {
    ValueNotifier<Appearance>? appearance,
    String? initialProviderId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
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
                  builder: (_) => DataProviderManager(
                    store: store,
                    appearance: appearance,
                    initialProviderId: initialProviderId,
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

  HttpProviderConfig config({String label = 'Clients'}) => HttpProviderConfig(
    id: 'clients',
    label: label,
    filterRepositoryId: 'filtre',
    target: _target,
    request: HttpRequestTemplate(url: 'https://api.test/clients'),
  );

  Object? rows() => store.peekDocument('resultats')?.document;

  testWidgets('creates, tests, saves and runs an HTTP provider', (
    tester,
  ) async {
    final results = await open(tester);
    expect(find.text('Aucun provider.'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('provider-create')));
    expect(find.byKey(const ValueKey('provider-entry-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('provider-search')), findsNothing);

    await type(tester, 'provider-id', 'clients');
    await type(tester, 'provider-label', 'Clients');
    await type(tester, 'provider-url', 'https://api.test/clients');
    await choose(
      tester,
      find.byKey(const ValueKey('provider-filter')),
      'filtre',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('provider-form-error')))
          .data,
      contains('Résultats'),
    );
    await choose(
      tester,
      find.byKey(const ValueKey('provider-binding-target-repository')),
      'resultats',
    );
    await type(tester, 'provider-binding-target-repository-path', 'rows');
    expect(find.byKey(const ValueKey('provider-form-error')), findsNothing);

    await tap(tester, find.byKey(const ValueKey('provider-test')));
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('provider-test-result')),
          )
          .data,
      allOf(contains('1 ligne(s) reçue(s).'), contains('"nom": "Dupont"')),
    );
    expect(transport.requests.single.uri.queryParameters, {'q': 'dupont'});
    expect(rows(), {'rows': <Object?>[]});
    expect(
      await tester.runAsync(() => providerFile('clients').exists()),
      false,
    );

    await tap(tester, find.byKey(const ValueKey('provider-save')));
    expect(find.text('Provider enregistré.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('provider-entry-clients')),
      findsOneWidget,
    );
    final saved = await tester.runAsync(
      () => providerFile('clients').readAsString(),
    );
    expect(jsonDecode(saved!), config().toJson());

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('provider-status'))).data,
      'Aucune recherche lancée.',
    );
    await tap(tester, find.byKey(const ValueKey('provider-search')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('provider-status'))).data,
      '1 ligne(s) écrite(s) lors de la dernière recherche.',
    );
    expect(rows(), {
      'rows': [
        {'nom': 'Dupont'},
      ],
    });

    await tap(tester, find.byKey(const ValueKey('provider-close')));
    expect(find.byType(DataProviderManager), findsNothing);
    expect(results, ['clients']);
  });

  testWidgets('unsaved edits block the search and ask before leaving', (
    tester,
  ) async {
    await tester.runAsync(() => store.providers.save(config()));
    store.providers.register(
      CallbackDataProvider(
        id: 'local',
        label: 'Local',
        target: _target,
        callback: (_) async => const [],
      ),
    );
    final results = await open(tester, initialProviderId: 'clients');
    expect(find.byKey(const ValueKey('provider-test')), findsOneWidget);

    await type(tester, 'provider-label', 'Clients modifiés');
    final search = find.byKey(const ValueKey('provider-search'));
    expect(tester.widget<TextButton>(search).onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('provider-save')))
          .onPressed,
      isNotNull,
    );

    await tap(tester, find.byKey(const ValueKey('provider-entry-local')));
    expect(
      find.byKey(const ValueKey('provider-confirm-discard')),
      findsOneWidget,
    );
    await tap(tester, find.text('Conserver'));
    expect(find.text('Clients modifiés'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('provider-entry-local')));
    await tap(tester, find.byKey(const ValueKey('provider-confirm-discard')));
    expect(find.byKey(const ValueKey('provider-readonly')), findsOneWidget);
    expect(find.byKey(const ValueKey('provider-test')), findsNothing);
    expect(find.byKey(const ValueKey('provider-delete')), findsNothing);

    await tap(tester, find.byKey(const ValueKey('provider-search')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('provider-status'))).data,
      '0 ligne(s) écrite(s) lors de la dernière recherche.',
    );

    await tap(tester, find.byKey(const ValueKey('provider-create')));
    await type(tester, 'provider-id', 'clients');
    await type(tester, 'provider-url', 'https://api.test/autre');
    await choose(
      tester,
      find.byKey(const ValueKey('provider-binding-target-repository')),
      'resultats',
    );
    await type(tester, 'provider-binding-target-repository-path', 'rows');
    await tap(tester, find.byKey(const ValueKey('provider-save')));
    expect(find.text('Un provider « clients » existe déjà.'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('provider-close')));
    await tap(tester, find.byKey(const ValueKey('provider-confirm-discard')));
    expect(find.byType(DataProviderManager), findsNothing);
    expect(results, [null]);
    expect(store.providers.configOf('clients'), config());
  });

  testWidgets('a provider used by a behavior cannot be deleted', (
    tester,
  ) async {
    await tester.runAsync(() => store.providers.save(config()));
    final appearance = ValueNotifier(
      Appearance(
        behaviors: {
          'button': [
            const ComponentBehavior(
              id: 'search',
              trigger: BehaviorTrigger.click,
              action: SearchProviderAction(providerId: 'clients'),
            ),
          ],
        },
      ),
    );
    addTearDown(appearance.dispose);
    await open(tester, appearance: appearance);

    await tap(tester, find.byKey(const ValueKey('provider-entry-clients')));
    await tap(tester, find.byKey(const ValueKey('provider-delete')));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('provider-manager-error')))
          .data,
      contains('encore utilisé par un comportement'),
    );
    expect(find.byKey(const ValueKey('provider-confirm-delete')), findsNothing);

    appearance.value = Appearance();
    await tap(tester, find.byKey(const ValueKey('provider-delete')));
    await tap(tester, find.byKey(const ValueKey('provider-confirm-delete')));
    expect(find.text('Provider supprimé.'), findsOneWidget);
    expect(find.byKey(const ValueKey('provider-entry-clients')), findsNothing);
    expect(
      await tester.runAsync(() => providerFile('clients').exists()),
      false,
    );
  });
}
