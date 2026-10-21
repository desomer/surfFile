import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_text_editor.dart';

void main() {
  setUp(() => StyleEditorPanel.preferredDense = false);
  Future<void> open(
    WidgetTester tester,
    SuperTextConfig config, {
    bool inList = false,
    bool allowBinding = true,
    ValueChanged<SuperTextConfig?>? onResult,
    ValueChanged<SuperTextConfig>? onPreview,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget child = Builder(
      builder: (context) => TextButton(
        onPressed: () async => onResult?.call(
          await showSuperTextEditor(
            context: context,
            config: config,
            availableFontFamilies: [],
            allowBinding: allowBinding,
            onPreviewChanged: onPreview,
          ),
        ),
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
    final button = find.byKey(ValueKey('text-state-choice-$key'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String field, String value) async {
    final target = find.byKey(ValueKey('super-text-setting-$field'));
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shared controls edit named and hover properties and return whole table',
    (tester) async {
      SuperTextConfig? saved;
      final previews = <SuperTextConfig>[];
      await open(
        tester,
        const SuperTextConfig(initialText: 'Default'),
        inList: true,
        onResult: (value) => saved = value,
        onPreview: previews.add,
      );
      expect(
        find.byType(EditorStateControls<TextStateProperty>),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('text-state-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('text-state-name')),
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
              find.byKey(const ValueKey('super-text-setting-initialText')),
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
    SuperTextConfig? result = const SuperTextConfig();
    await open(
      tester,
      const SuperTextConfig(),
      onResult: (value) => result = value,
    );
    await enter(tester, 'fontSize', '-1');
    await choose(tester, hoverSurfaceStateKey);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('text-state-choice-')))
          .selected,
      isTrue,
    );
    await enter(tester, 'fontSize', '18');
    await choose(tester, hoverSurfaceStateKey);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(
              const ValueKey('text-state-choice-$hoverSurfaceStateKey'),
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
      SuperTextConfig? saved;
      await open(
        tester,
        SuperTextConfig(
          states: TextConfigStates(
            named: {'ready': const SuperTextConfig(initialText: 'Ready')},
          ),
        ),
        onResult: (value) => saved = value,
      );
      await choose(tester, 'ready');
      await tester.tap(find.byTooltip('Renommer l’état'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('text-state-name')),
        'done',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('text-state-choice-ready')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('text-state-delete')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('text-state-choice-done')),
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
    SuperTextConfig? saved;
    final previews = <SuperTextConfig>[];
    await open(
      tester,
      SuperTextConfig(
        fontSize: 16,
        states: TextConfigStates(
          hover: TextConfigOverride(
            config: const SuperTextConfig(fontSize: 24),
            properties: {TextStateProperty.fontSize},
          ),
        ),
      ),
      inList: true,
      onResult: (value) => saved = value,
      onPreview: previews.add,
    );
    await choose(tester, hoverSurfaceStateKey);
    final toggle = find.byKey(const ValueKey('text-state-override-fontSize'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(previews.last.fontSize, 16);
    final hover = find.byKey(
      const ValueKey('text-state-choice-$hoverSurfaceStateKey'),
    );
    final selected = find.byKey(
      const ValueKey('text-state-choice-$selectedSurfaceStateKey'),
    );
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
      SuperTextConfig? saved;
      await open(
        tester,
        SuperTextConfig(
          states: TextConfigStates(
            named: {
              'hidden': const SuperTextConfig(
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
        find.text('La liaison nécessite le contrôleur interne de Text.'),
        findsWidgets,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
