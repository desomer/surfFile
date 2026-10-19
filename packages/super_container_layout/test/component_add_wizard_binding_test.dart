import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repositoryId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('add-wizard-binding-');
    store = JsonRepositoryStore(directory);
    await store.create('People');
    repositoryId = await store.idOf('People');
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.text('Chargement des repositories…').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<ValueNotifier<ComponentAddRequest?>> open(
    WidgetTester tester,
    ComponentAddCandidate candidate, {
    required String fields,
    bool inList = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = ValueNotifier<ComponentAddRequest?>(null);
    addTearDown(result.dispose);
    Widget launcher = Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result.value = await showComponentAddWizard(
            context: context,
            title: 'Ajouter',
            keyPrefix: 'w',
            candidates: [candidate],
            targets: const [ComponentAddTarget(id: 'a', label: 'Zone A')],
            initialTargetId: 'a',
          );
        },
        child: const Text('Ouvrir'),
      ),
    );
    if (inList) {
      launcher = JsonListScope(
        repositoryId: repositoryId,
        indices: const [0],
        child: launcher,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Below the Navigator: the wizard must forward the scopes.
          body: JsonRepositoryScope(store: store, child: launcher),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'w-add-card-${candidate.id}');
    expect(
      tester
          .widget<Stepper>(find.byKey(const ValueKey('w-add-stepper')))
          .steps[2]
          .state,
      StepState.indexed,
    );
    await tapKey(tester, 'w-add-next');
    // Settings step: the binding has its own step.
    expect(find.byKey(const ValueKey('w-add-label')), findsOneWidget);
    expect(find.byKey(ValueKey('$fields-repository')), findsNothing);
    await tapKey(tester, 'w-add-next');
    expect(find.byKey(const ValueKey('w-add-binding')), findsOneWidget);
    await settle(tester);
    return result;
  }

  FilledButton next(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const ValueKey('w-add-next')));

  testWidgets('text binding is chosen in the dedicated binding step', (
    tester,
  ) async {
    final result = await open(
      tester,
      ComponentAddCandidate(
        id: 'text',
        label: 'Texte',
        configurator: superTextAddConfigurator(const []),
      ),
      fields: 'add-text',
    );
    expect(next(tester).onPressed, isNotNull);
    expect(
      find.byKey(const ValueKey('add-text-repository-path')),
      findsNothing,
    );
    await tapKey(tester, 'add-text-repository');
    await tester.tap(find.text('People').last);
    await tester.pumpAndSettle();

    final path = find.byKey(const ValueKey('add-text-repository-path'));
    expect(path, findsOneWidget);
    expect(find.text('Chemin requis.'), findsOneWidget);
    expect(find.text('Chemin de liaison requis.'), findsOneWidget);
    expect(next(tester).onPressed, isNull);
    await tester.enterText(path, 'client..nom');
    await tester.pumpAndSettle();
    expect(next(tester).onPressed, isNull);
    await tester.enterText(path, 'client.nom');
    await tester.pumpAndSettle();
    expect(next(tester).onPressed, isNotNull);
    expect(
      find.text('Le repository fournit la valeur (liaison bidirectionnelle).'),
      findsOneWidget,
    );

    // Going back keeps the settings valid and the binding in the draft.
    await tapKey(tester, 'w-add-back');
    expect(next(tester).onPressed, isNotNull);
    await tapKey(tester, 'w-add-next');
    await settle(tester);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('add-text-repository-path')),
          )
          .controller!
          .text,
      'client.nom',
    );

    await tapKey(tester, 'w-add-next');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('w-add-summary')),
        matching: find.text('$repositoryId · client.nom'),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'w-add-next');
    final draft = result.value!.draft! as SuperTextConfig;
    expect(draft.binding!.repositoryId, repositoryId);
    expect(draft.binding!.path, 'client.nom');
    expect(tester.takeException(), isNull);
  });

  testWidgets('list binding can inherit the enclosing list repository', (
    tester,
  ) async {
    final result = await open(
      tester,
      ComponentAddCandidate(
        id: 'list',
        label: 'Liste',
        configurator: listViewAddConfigurator,
      ),
      fields: 'add-list',
      inList: true,
    );
    await tapKey(tester, 'add-list-repository');
    await tester.tap(find.text('Hérité de la liste englobante').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-list-repository-path')),
      'clients[?].commandes',
    );
    await tester.pumpAndSettle();
    await tapKey(tester, 'w-add-next');
    await tapKey(tester, 'w-add-next');
    final draft = result.value!.draft! as SuperListViewConfig;
    expect(draft.binding!.repositoryId, isNull);
    expect(draft.binding!.path, 'clients[?].commandes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing the binding clears it from the draft', (tester) async {
    final result = await open(
      tester,
      ComponentAddCandidate(
        id: 'text',
        label: 'Texte',
        configurator: superTextAddConfigurator(const []),
      ),
      fields: 'add-text',
    );
    await tapKey(tester, 'add-text-repository');
    await tester.tap(find.text('People').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-text-repository-path')),
      'client.nom',
    );
    await tester.pumpAndSettle();
    await tapKey(tester, 'add-text-repository');
    await tester.tap(find.text('Sans liaison').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'w-add-next');
    await tapKey(tester, 'w-add-next');
    expect((result.value!.draft! as SuperTextConfig).binding, isNull);
  });
}
