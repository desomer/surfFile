import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleOptions = [
    SuperChoiceOption(value: 'fr', label: 'France', icon: 'flag'),
    SuperChoiceOption(value: 'be', label: 'Belgique'),
    SuperChoiceOption(value: 'ch', label: 'Suisse'),
  ];

  Widget host(Widget child, {JsonRepositoryStore? store}) {
    final content = MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 420, child: child)),
      ),
    );
    if (store == null) return content;
    return JsonRepositoryScope(store: store, child: content);
  }

  group('SuperChoiceConfig & SuperValueConfig serialization', () {
    test('supports choice and choise alias in JSON and compact JSON', () {
      const config = SuperValueConfig(
        mode: SuperValueMode.input,
        kind: SuperValueKind.choice,
        initialText: 'fr',
        label: 'Pays',
        choice: SuperChoiceConfig(
          variant: ChoiceVariant.segmented,
          options: sampleOptions,
          allowEmpty: true,
        ),
      );

      final json = config.toJson();
      expect(json['kind'], 'choice');
      expect(SuperValueConfig.fromJson(json), config);

      final compact = config.toCompactJson();
      expect(SuperValueConfig.fromJson(compact), config);

      final fromChoiseAlias = SuperValueConfig.fromJson({
        'mode': 'input',
        'kind': 'choise',
        'value': ['fr', 'be'],
        'choise': {
          'variant': 'FilterChip',
          'options': ['fr', 'be', 'ch'],
        },
      });
      expect(fromChoiseAlias.kind, SuperValueKind.choice);
      expect(fromChoiseAlias.choice.variant, ChoiceVariant.filterChip);
      expect(fromChoiseAlias.initialText, 'fr,be');
      expect(fromChoiseAlias.choice.options.length, 3);
    });

    test('validates segmented option bounds when static options provided', () {
      expect(
        () => SuperChoiceConfig(
          variant: ChoiceVariant.segmented,
          options: const [SuperChoiceOption(value: 'only_one')],
        ).validate(),
        throwsFormatException,
      );
    });
  });

  group('SuperChoice widget variants', () {
    testWidgets('SegmentedButton selects single choice', (tester) async {
      String? changed;
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'seg',
            onChanged: (val) => changed = val,
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              kind: SuperValueKind.choice,
              initialText: 'fr',
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.segmented,
                options: sampleOptions,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      await tester.tap(find.text('Belgique'));
      await tester.pumpAndSettle();
      expect(changed, 'be');
    });

    testWidgets('DropdownButton selects single choice', (tester) async {
      String? changed;
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'drop',
            onChanged: (val) => changed = val,
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              kind: SuperValueKind.choice,
              initialText: 'fr',
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.dropdown,
                options: sampleOptions,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suisse').last);
      await tester.pumpAndSettle();
      expect(changed, 'ch');
    });

    testWidgets('RadioListTile selects single visible choice', (tester) async {
      String? changed;
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'radio',
            onChanged: (val) => changed = val,
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              kind: SuperValueKind.choice,
              initialText: 'fr',
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.radio,
                options: sampleOptions,
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('super-choice-radio-be')),
      );
      await tester.pumpAndSettle();
      expect(changed, 'be');
    });

    testWidgets('FilterChip and CheckboxListTile support multiple choices', (
      tester,
    ) async {
      String? changed;
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'chips',
            onChanged: (val) => changed = val,
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              kind: SuperValueKind.choice,
              initialText: 'fr',
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.filterChip,
                options: sampleOptions,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('super-choice-chip-ch')));
      await tester.pumpAndSettle();
      expect(changed, 'fr,ch');

      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'checks',
            onChanged: (val) => changed = val,
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              kind: SuperValueKind.choice,
              initialText: 'fr,ch',
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.checkboxList,
                options: sampleOptions,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('super-choice-checkbox-fr')));
      await tester.pumpAndSettle();
      expect(changed, 'ch');
    });

    testWidgets('SearchAnchor filters and selects from searchable list', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'fr');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          SuperChoise(
            controller: controller,
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              kind: SuperValueKind.choice,
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.searchAnchor,
                options: sampleOptions,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('super-choice-search-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('super-choice-search-item-be')),
      );
      await tester.pumpAndSettle();
      expect(controller.text, 'be');
    });

    testWidgets('supports dynamic repository options and JSON array storage', (
      tester,
    ) async {
      final store = JsonRepositoryStore(Directory.systemTemp);
      addTearDown(store.dispose);
      Map<String, Object?> latestDoc = {
        'selectedTags': ['t1'],
        'tags': [
          {'id': 't1', 'label': 'Urgent'},
          {'id': 't2', 'label': 'Important'},
          {'id': 't3', 'label': 'Archive'},
        ],
      };
      store.registerRepository(
        RepositoryImpl(
          id: 'app_data',
          json: latestDoc,
          onChanged: (ctx) {
            if (ctx.newValue is List) {
              latestDoc = {...latestDoc, 'selectedTags': ctx.newValue};
            }
          },
        ),
      );

      await tester.pumpWidget(
        host(
          const SuperValue(
            id: 'repo_choice',
            config: SuperValueConfig(
              mode: SuperValueMode.input,
              kind: SuperValueKind.choice,
              binding: JsonTextBinding(
                repositoryId: 'app_data',
                path: 'selectedTags',
              ),
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.filterChip,
                optionsBinding: JsonTextBinding(
                  repositoryId: 'app_data',
                  path: 'tags',
                ),
                optionValueKey: 'id',
                optionLabelKey: 'label',
              ),
            ),
          ),
          store: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Urgent'), findsOneWidget);
      expect(find.text('Important'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('super-choice-chip-t2')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(latestDoc['selectedTags'], ['t1', 't2']);
    });
  });
}
