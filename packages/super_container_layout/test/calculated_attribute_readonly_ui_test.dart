import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repositoryId;
  var calculationRuns = 0;
  var repositoryWrites = 0;

  setUp(() async {
    calculationRuns = 0;
    repositoryWrites = 0;
    directory = Directory(
      '${Directory.current.path}\\test\\calculated_attribute_readonly_data',
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
    store = JsonRepositoryStore(directory);
    repositoryId = 'people_repo';
    final repository =
        RepositoryImpl(
            id: repositoryId,
            json: {
              'stats': {'total': 42},
              'active': true,
              'selected': 'one',
              'note': 'Initial',
              'articles': [
                {'price': 7},
              ],
            },
            onChanged: (_) => repositoryWrites++,
          )
          ..addCalculatedAttribute('total', (context) {
            calculationRuns++;
            return context.getValue('stats.total');
          })
          ..addCalculatedAttribute('tree', (context) {
            calculationRuns++;
            return [
              {
                'name': 'Root',
                'children': [
                  {'name': 'Child', 'children': []},
                ],
              },
            ];
          })
          ..addCalculatedAttribute('computedRows', (context) {
            calculationRuns++;
            return [
              {'value': 'Derived'},
            ];
          })
          ..addCalculatedAttribute('active', (context) {
            calculationRuns++;
            return context.getValue('active');
          })
          ..addCalculatedAttribute('selected', (context) {
            calculationRuns++;
            return context.getValue('selected');
          })
          ..addCalculatedAttribute('amount', (context) {
            calculationRuns++;
            return context.getNum('price');
          }, scope: 'articles[?]');
    store.registerRepository(repository);
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'computed controller paths never become dirty or flush writes',
    () async {
      for (final (path, expected) in [
        ('@total', '42'),
        ('articles[0].@amount', '7'),
      ]) {
        final controller = TextEditingController();
        final binding = JsonTextControllerBinding(
          store: store,
          binding: JsonTextBinding(repositoryId: repositoryId, path: path),
          controller: controller,
        );
        await binding.reload();

        expect(binding.isReadOnly, isTrue);
        expect(controller.text, expected);
        controller.text = 'Draft';
        expect(controller.text, expected);
        expect(binding.dirty, isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await binding.flush();
        await store.flushBindings();
        expect(binding.dirty, isFalse);

        binding.dispose();
        controller.dispose();
      }

      expect(repositoryWrites, 0);
      final unavailableController = TextEditingController(text: 'No draft');
      final unavailableBinding = JsonTextControllerBinding(
        store: store,
        binding: JsonTextBinding(
          repositoryId: repositoryId,
          path: '@missing',
        ),
        controller: unavailableController,
      );
      await unavailableBinding.reload();
      expect(unavailableBinding.isReadOnly, isTrue);
      expect(unavailableBinding.dirty, isFalse);
      await expectLater(store.flushBindings(), completes);
      unavailableBinding.dispose();
      unavailableController.dispose();
      expect(
        (await store.readAttribute(
          JsonTextBinding(repositoryId: repositoryId, path: '@total'),
        )).text,
        '42',
      );
    },
  );

  test('ordinary controller bindings remain writable', () async {
    final controller = TextEditingController();
    final binding = JsonTextControllerBinding(
      store: store,
      binding: JsonTextBinding(repositoryId: repositoryId, path: 'note'),
      controller: controller,
    );
    await binding.reload();

    expect(binding.isReadOnly, isFalse);
    controller.text = 'Updated';
    expect(binding.dirty, isTrue);
    await binding.flush();

    expect(
      (await store.readAttribute(
        JsonTextBinding(repositoryId: repositoryId, path: 'note'),
      )).text,
      'Updated',
    );
    expect(repositoryWrites, 1);
    binding.dispose();
    controller.dispose();
  });

  testWidgets('SuperValue text, bool, and choice controls are read-only', (
    tester,
  ) async {
    final directChoiceController = TextEditingController(text: 'one');
    addTearDown(directChoiceController.dispose);
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      JsonRepositoryScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SuperValue(
                  id: 'computed-text',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    binding: JsonTextBinding(
                      repositoryId: repositoryId,
                      path: '@total',
                    ),
                  ),
                ),
                SuperValue(
                  id: 'computed-bool',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    kind: SuperValueKind.checkbox,
                    binding: JsonTextBinding(
                      repositoryId: repositoryId,
                      path: '@active',
                    ),
                  ),
                ),
                SuperValue(
                  id: 'computed-choice',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    kind: SuperValueKind.choice,
                    binding: JsonTextBinding(
                      repositoryId: repositoryId,
                      path: '@selected',
                    ),
                    choice: const SuperChoiceConfig(
                      options: [
                        SuperChoiceOption(value: 'one'),
                        SuperChoiceOption(value: 'two'),
                      ],
                    ),
                  ),
                ),
                SuperChoice(
                  inputKey: const ValueKey('standalone-computed-choice'),
                  controller: directChoiceController,
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    kind: SuperValueKind.choice,
                    binding: JsonTextBinding(
                      repositoryId: repositoryId,
                      path: '@selected',
                    ),
                    choice: const SuperChoiceConfig(
                      options: [
                        SuperChoiceOption(value: 'one'),
                        SuperChoiceOption(value: 'two'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(
      find.byKey(const ValueKey('super-value-input-computed-text')),
    );
    expect(textField.readOnly, isTrue);
    expect(textField.controller!.text, '42');
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('super-value-checkbox-computed-bool')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: find.byKey(
                const ValueKey('super-value-choice-computed-choice'),
              ),
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: find.byKey(const ValueKey('standalone-computed-choice')),
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .onChanged,
      isNull,
    );
    expect(repositoryWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculated tree rows inherit read-only calculated bindings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(
      () => tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 600,
                child: SuperTreeView(
                  id: 'calculated-tree',
                  config: SuperTreeViewConfig(
                    binding: JsonTextBinding(
                      repositoryId: repositoryId,
                      path: '@tree',
                    ),
                    placements: const {
                      SuperTreeViewConfig.headerZone: ['header'],
                    },
                  ),
                  header: const SuperValue(
                    id: 'calculated-tree-name',
                    config: SuperValueConfig(
                      mode: SuperValueMode.input,
                      binding: JsonTextBinding(path: '@tree[?].name'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.map((field) => field.controller!.text), ['Root', 'Child']);
    expect(fields.every((field) => field.readOnly), isTrue);
    expect(calculationRuns, greaterThan(0));
    expect(repositoryWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('derived collection data cannot be added or removed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(
      () => tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 600,
                child: SuperListView(
                  id: 'calculated-list',
                  config: SuperListViewConfig(
                    binding: JsonTextBinding(
                      repositoryId: repositoryId,
                      path: '@computedRows',
                    ),
                    allowAdd: true,
                    allowRemove: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    expect(calculationRuns, greaterThan(0));
    expect(
      find.byKey(const ValueKey('super-list-add-calculated-list')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('super-list-remove-calculated-list-0')),
      findsNothing,
    );
    expect(repositoryWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'binding fields suggest inherited calculated paths without evaluating them',
    (tester) async {
      expect(
        store.hasCalculatedAttribute(repositoryId, 'articles[?].@amount'),
        isTrue,
      );
      expect(
        store
            .calculatedAttributeCatalog(repositoryId)
            .map((descriptor) => descriptor.path),
        contains('articles[?].@amount'),
      );
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => tester.pumpWidget(
          JsonRepositoryScope(
            store: store,
            child: MaterialApp(
              home: Scaffold(
                body: JsonListScope(
                  repositoryId: repositoryId,
                  indices: const [0],
                  child: RepositoryBindingFields(
                    keyPrefix: 'calculated',
                    binding: const JsonTextBinding(path: 'articles[?].@amount'),
                    pathHint: 'Chemin',
                    store: store,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.text('articles[?].@amount'), findsWidgets);
      final renderedText = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .toList();
      expect(
        renderedText,
        contains('Calculé — lecture seule'),
        reason: 'Rendered text: $renderedText',
      );
      expect(calculationRuns, 0);

      await tester.tap(
        find.byKey(const ValueKey('calculated-calculated-suggestion-0')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('calculated-repository-path')),
            )
            .controller!
            .text,
        'articles[?].@amount',
      );
      expect(calculationRuns, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('computed binding labels and unknown paths are preserved', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const knownBinding = JsonTextBinding(path: '@total');
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                RepositoryBindingBanner(binding: knownBinding),
                RepositoryBindingIconButton(
                  key: const ValueKey('calculated-binding-button'),
                  binding: knownBinding,
                  tooltip: 'Modifier la liaison',
                  onPressed: () {},
                ),
                RepositoryBindingFields(
                  keyPrefix: 'unknown',
                  binding: JsonTextBinding(
                    repositoryId: repositoryId,
                    path: '@unknown',
                  ),
                  pathHint: 'Chemin',
                  store: store,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Lié à : @total — Calculé — lecture seule'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('calculated-binding-button')),
              matching: find.byType(IconButton),
            ),
          )
          .tooltip,
      'Modifier la liaison (@total — Calculé — lecture seule)',
    );
    final pathField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('unknown-repository-path')),
    );
    expect(pathField.controller!.text, '@unknown');
    expect(find.text('Chemin — Calculé — lecture seule'), findsOneWidget);
    expect(
      find.text('Attribut calculé inconnu dans ce repository.'),
      findsOneWidget,
    );
    expect(calculationRuns, 0);
    expect(tester.takeException(), isNull);
  });
}
