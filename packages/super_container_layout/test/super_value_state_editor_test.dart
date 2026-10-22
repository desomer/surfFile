import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_value_editor.dart';

void main() {
  setUp(() => StyleEditorPanel.preferredDense = false);
  Future<void> open(
    WidgetTester tester,
    SuperValueConfig config, {
    bool inList = false,
    bool allowBinding = true,
    bool allowContentHover = false,
    ValueChanged<SuperValueConfig?>? onResult,
    ValueChanged<SuperValueConfig>? onPreview,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget child = Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final result = await showSuperValueEditor(
            context: context,
            config: config,
            availableFontFamilies: [],
            allowBinding: allowBinding,
            allowContentHover: allowContentHover,
            onPreviewChanged: onPreview,
          );
          onResult?.call(result);
        },
        child: const Text('Open'),
      ),
    );
    if (inList) {
      child = JsonListScope(
        repositoryId: null,
        indices: const [0],
        child: child,
      );
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey('value-state-choice-$key'));
    final state = AutomaticState.fromKey(key);
    if (button.evaluate().isEmpty && state != null) {
      final add = find.byKey(const ValueKey('value-state-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('value-state-add-${state.name}')));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String field, String value) async {
    final target = find.byKey(ValueKey('super-value-setting-$field'));
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  Future<void> addMenu(WidgetTester tester) async {
    final add = find.byKey(const ValueKey('value-state-add'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Text hover and selected are opt-in, removable and saved only after adding',
    (tester) async {
      SuperValueConfig? saved;
      await open(
        tester,
        const SuperValueConfig(),
        inList: true,
        onResult: (value) => saved = value,
      );
      for (final state in [AutomaticState.hover, AutomaticState.selected]) {
        final chip = find.byKey(ValueKey('value-state-choice-${state.key}'));
        expect(chip, findsNothing);
        await addMenu(tester);
        final item = find.byKey(ValueKey('value-state-add-${state.name}'));
        expect(tester.widget<PopupMenuItem<String>>(item).enabled, isTrue);
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        final remove = find.byKey(const ValueKey('value-state-delete'));
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(chip, findsNothing);
      }
      await choose(tester, ValueConfigStates.hoverKey);
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(saved!.states!.hover, isNotNull);
      expect(saved!.states!.selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bound named overrides start empty, toggle and follow rename and save',
    (tester) async {
      SuperValueConfig? saved;
      final previews = <SuperValueConfig>[];
      await open(
        tester,
        SuperValueConfig(
          fontSize: 16,
          initialText: 'Default',
          states: ValueConfigStates(
            binding: const JsonTextBinding(path: 'status'),
            named: {
              'ready': const SuperValueConfig(
                fontSize: 24,
                initialText: 'Ready',
              ),
            },
          ),
        ),
        onResult: (value) => saved = value,
        onPreview: previews.add,
      );
      await choose(tester, 'ready');
      final toggle = find.byKey(const ValueKey('value-state-override-fontSize'));
      expect(tester.widget<FilterChip>(toggle).selected, isFalse);
      expect(tester.widget<FilterChip>(toggle).onSelected, isNotNull);
      expect(previews.last.fontSize, 16);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(previews.last.fontSize, 24);
      expect(previews.last.initialText, 'Default');
      await enter(tester, 'label', 'Named label');
      await choose(tester, '');
      await choose(tester, 'ready');
      expect(tester.widget<FilterChip>(toggle).selected, isTrue);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(previews.last.fontSize, 16);
      final rename = find.byTooltip('Renommer l’état');
      await tester.ensureVisible(rename);
      await tester.tap(rename);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('value-state-name')),
        'done',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(saved!.states!.namedProperties, {
        'done': {ValueStateProperty.textLabel},
      });
      expect(saved!.states!.resolve(saved!, name: 'done').label, 'Named label');
      expect(saved!.states!.resolve(saved!, name: 'done').fontSize, 16);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalogue filters field and row states, adds once and deletes cleanly',
    (tester) async {
      SuperValueConfig? saved;
      await open(
        tester,
        const SuperValueConfig(mode: SuperValueMode.input),
        inList: true,
        allowContentHover: true,
        onResult: (value) => saved = value,
      );
      await addMenu(tester);
      for (final value in AutomaticState.values) {
        expect(
          find.byKey(ValueKey('value-state-add-${value.name}')),
          findsOneWidget,
        );
      }
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.byKey(const ValueKey('value-state-add-hover')),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('value-state-add-focused')));
      await tester.pumpAndSettle();
      final focused = find.byKey(
        ValueKey('value-state-choice-${AutomaticState.focused.key}'),
      );
      expect(tester.widget<ChoiceChip>(focused).selected, isTrue);
      await enter(tester, 'fontSize', '28');
      await addMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.byKey(const ValueKey('value-state-add-focused')),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('value-state-add-readOnly')));
      await tester.pumpAndSettle();
      await choose(tester, AutomaticState.focused.key);
      await tester.ensureVisible(
        find.byKey(const ValueKey('value-state-delete')),
      );
      await tester.tap(find.byKey(const ValueKey('value-state-delete')));
      await tester.pumpAndSettle();
      expect(focused, findsNothing);
      await addMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.byKey(const ValueKey('value-state-add-focused')),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('value-state-add-focused')));
      await tester.pumpAndSettle();
      await enter(tester, 'fontSize', '26');
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(
        saved!.states!.automatic.keys,
        containsAll([AutomaticState.focused, AutomaticState.readOnly]),
      );
      expect(
        saved!.states!.automatic[AutomaticState.focused]!.config.fontSize,
        26,
      );
      expect(saved!.states!.order.last, AutomaticState.focused.key);
      expect(saved!.states!.named, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('display outside Content does not offer field or row states', (
    tester,
  ) async {
    await open(tester, const SuperValueConfig());
    await addMenu(tester);
    expect(find.byKey(const ValueKey('value-state-add-hover')), findsOneWidget);
    for (final value in AutomaticState.values.skip(1)) {
      expect(
        find.byKey(ValueKey('value-state-add-${value.name}')),
        findsNothing,
      );
    }
    expect(find.byKey(const ValueKey('value-state-add-custom')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid draft blocks adding an automatic state', (tester) async {
    await open(tester, const SuperValueConfig(mode: SuperValueMode.input));
    await enter(tester, 'fontSize', '-1');
    await addMenu(tester);
    await tester.tap(find.byKey(const ValueKey('value-state-add-focused')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('value-state-choice-${AutomaticState.focused.key}')),
      findsNothing,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('value-state-choice-')))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shared controls edit named and hover properties and return whole table',
    (tester) async {
      SuperValueConfig? saved;
      final previews = <SuperValueConfig>[];
      await open(
        tester,
        const SuperValueConfig(initialText: 'Default'),
        inList: true,
        onResult: (value) => saved = value,
        onPreview: previews.add,
      );
      expect(
        find.byType(EditorStateControls<ValueStateProperty>),
        findsOneWidget,
      );
      final defaultOverride = tester.widget<FilterChip>(
        find.byKey(const ValueKey('value-state-override-fontSize')),
      );
      expect(defaultOverride.selected, isTrue);
      expect(defaultOverride.onSelected, isNull);
      await tester.tap(find.byKey(const ValueKey('value-state-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('value-state-add-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('value-state-name')),
        'ready',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      await enter(tester, 'initialText', 'Ready');
      await choose(tester, hoverSurfaceStateKey);
      await enter(tester, 'fontSize', '26');
      expect(previews.last.fontSize, 26);
      await choose(tester, 'ready');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('super-value-setting-initialText')),
            )
            .controller!
            .text,
        'Ready',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(saved!.initialText, 'Default');
      expect(saved!.states!.named['ready']!.initialText, 'Ready');
      expect(saved!.states!.hover!.config.fontSize, 26);
      expect(
        saved!.states!.hover!.properties.any((p) => p.name == 'fontSize'),
        isTrue,
      );
      expect(
        saved!.states!
            .resolve(saved!, name: 'ready', isHovered: true)
            .initialText,
        'Ready',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('state switch validates drafts and cancel discards all states', (
    tester,
  ) async {
    SuperValueConfig? result = const SuperValueConfig();
    await open(
      tester,
      SuperValueConfig(states: ValueConfigStates(hover: ValueConfigOverride())),
      onResult: (value) => result = value,
    );
    await enter(tester, 'fontSize', '-1');
    await choose(tester, hoverSurfaceStateKey);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('value-state-choice-')))
          .selected,
      isTrue,
    );
    await enter(tester, 'fontSize', '18');
    await choose(tester, hoverSurfaceStateKey);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('value-state-choice-$hoverSurfaceStateKey'),
            ),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rename and delete preserve definitions without resurrecting states',
    (tester) async {
      SuperValueConfig? saved;
      await open(
        tester,
        SuperValueConfig(
          states: ValueConfigStates(
            named: {'ready': const SuperValueConfig(initialText: 'Ready')},
          ),
        ),
        onResult: (value) => saved = value,
      );
      await choose(tester, 'ready');
      await tester.tap(find.byTooltip('Renommer l’état'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('value-state-name')),
        'done',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('value-state-choice-ready')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('value-state-delete')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('value-state-choice-done')),
        findsNothing,
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(saved!.states!.named, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit overrides can be disabled and drag priority persists', (
    tester,
  ) async {
    SuperValueConfig? saved;
    final previews = <SuperValueConfig>[];
    await open(
      tester,
      SuperValueConfig(
        fontSize: 16,
        states: ValueConfigStates(
          hover: ValueConfigOverride(
            config: const SuperValueConfig(fontSize: 24),
            properties: {ValueStateProperty.fontSize},
          ),
        ),
      ),
      inList: true,
      onResult: (value) => saved = value,
      onPreview: previews.add,
    );
    await choose(tester, hoverSurfaceStateKey);
    final toggle = find.byKey(const ValueKey('value-state-override-fontSize'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(previews.last.fontSize, 16);
    final hover = find.byKey(
      const ValueKey('value-state-choice-$hoverSurfaceStateKey'),
    );
    final selected = find.byKey(
      const ValueKey('value-state-choice-$selectedSurfaceStateKey'),
    );
    await choose(tester, selectedSurfaceStateKey);
    await choose(tester, hoverSurfaceStateKey);
    await tester.ensureVisible(hover);
    await tester.dragFrom(
      tester.getCenter(hover),
      tester.getCenter(selected) - tester.getCenter(hover),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer').last);
    await tester.pumpAndSettle();
    expect(saved!.states!.hover!.properties, isEmpty);
    expect(saved!.states!.order, [
      selectedSurfaceStateKey,
      hoverSurfaceStateKey,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'external ownership rejects content bindings in inactive states',
    (tester) async {
      SuperValueConfig? saved;
      await open(
        tester,
        SuperValueConfig(
          states: ValueConfigStates(
            named: {
              'hidden': const SuperValueConfig(
                binding: JsonTextBinding(
                  repositoryId: '0123456789abcdef0123456789abcdef',
                  path: 'name',
                ),
              ),
            },
          ),
        ),
        allowBinding: false,
        onResult: (value) => saved = value,
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(
        find.text('La liaison nécessite le contrôleur interne de Value.'),
        findsWidgets,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
