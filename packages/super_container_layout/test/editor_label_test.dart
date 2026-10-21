import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/dialogs/editor_dialog_header.dart';

void main() {
  const initial = SuperLayoutConfig(
    north: false,
    south: false,
    east: false,
    west: false,
    placements: {
      SuperLayoutZone.center: ['a', 'b'],
    },
  );

  Future<ValueNotifier<SuperLayoutConfig>> pump(WidgetTester tester) async {
    final config = ValueNotifier(initial);
    final mode = ValueNotifier(true);
    addTearDown(config.dispose);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: ValueListenableBuilder<SuperLayoutConfig>(
                valueListenable: config,
                builder: (context, value, _) => SuperLayout(
                  label: 'Layout original',
                  config: value,
                  onChanged: (value) => config.value = value,
                  slots: [
                    for (final id in ['a', 'b'])
                      BuilderSlot(
                        id: id,
                        label: 'Component $id',
                        builder: (_) => EditableSurface(
                          label: 'Style $id',
                          child: IgnorePointer(
                            child: TextField(key: ValueKey('content-$id')),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    return config;
  }

  Future<void> rename(WidgetTester tester, String value) async {
    await tester.tap(find.byKey(const ValueKey('editor-label-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-label-input')),
      value,
    );
    await tester.tap(find.byKey(const ValueKey('editor-label-save')));
    await tester.pumpAndSettle();
  }

  Future<void> openSize(WidgetTester tester, String label) async {
    await tester.tapAt(
      tester.getBottomRight(find.byKey(const ValueKey('content-a'))) -
          const Offset(40, 40),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey('style-menu-size-Taille et marge préférées : $label'),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('instance names serialize, snapshot, move and remove independently', () {
    final config = initial
        .copyWith(label: 'Page')
        .withSlotLabel('a', 'Renamed');
    final restored = SuperLayoutConfig.fromJson(config.toJson());
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
    expect(
      restored.withSlotMoved('a', SuperLayoutZone.north).slotLabels['a'],
      'Renamed',
    );
    expect(restored.withoutSlot('a').slotLabels, isEmpty);
    expect(initial.slotLabels, isEmpty);
    final labels = <String, String>{'a': 'First'};
    final appearance = Appearance(
      layouts: {'root': initial.copyWith(slotLabels: labels)},
    );
    labels['a'] = 'Changed';
    expect(appearance.layouts['root']!.slotLabels['a'], 'First');
    expect(
      () => appearance.layouts['root']!.slotLabels['a'] = 'No',
      throwsUnsupportedError,
    );
    for (final json in [
      {'label': ''},
      {
        'slotLabels': {'a': ' '},
      },
      {
        'slotLabels': {'': 'Name'},
      },
      {
        'slotLabels': {'a': 1},
      },
    ]) {
      expect(() => SuperLayoutConfig.fromJson(json), throwsFormatException);
    }
  });

  testWidgets(
    'size dialog renames instance, preserves child state and cancels',
    (tester) async {
      final config = await pump(tester);
      await tester.enterText(find.byKey(const ValueKey('content-a')), 'kept');
      await openSize(tester, 'Component a');
      await rename(tester, 'Renamed');
      expect(config.value.slotLabels, {'a': 'Renamed'});
      expect(find.text('Taille et marge préférées : Renamed'), findsOneWidget);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(find.text('kept'), findsOneWidget);
      expect(config.value.placements, initial.placements);
      await tester.tap(find.byKey(const ValueKey('slot-label-select-a')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'Renamed');
      await openSize(tester, 'Renamed');
      await rename(tester, 'Temporary');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(config.value.slotLabels, {'a': 'Renamed'});
      expect(find.text('kept'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'style header combines name and dense action and renames only instance',
    (tester) async {
      final config = await pump(tester);
      Future<void> open() async {
        final container = find
            .ancestor(
              of: find.byKey(const ValueKey('content-a')),
              matching: find.byType(EditableSurface),
            )
            .first;
        tester.state<EditableSurfaceState>(container).openEditor();
        await tester.pumpAndSettle();
      }

      await open();
      final header = find.byType(EditorDialogHeader);
      expect(header, findsOneWidget);
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('style-dense-toggle')),
        ),
        findsOneWidget,
      );
      await rename(tester, 'My instance');
      expect(config.value.slotLabels['a'], 'My instance');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(config.value.slotLabels, isEmpty);
      await open();
      await rename(tester, 'My instance');
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(config.value.slotLabels, {'a': 'My instance'});
      expect(config.value.slotLabels.containsKey('b'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('layout dialog renames layout and cancel restores config', (
    tester,
  ) async {
    final config = await pump(tester);
    final layout = tester.state<SuperLayoutState>(find.byType(SuperLayout));
    Future<void> open() async {
      final container = find.byWidgetPredicate(
        (w) =>
            w is EditorSlot &&
            (w.label == 'Layout original' || w.label == 'New layout'),
      );
      tester.state<EditorSlotState>(container).openEditor();
      await tester.pumpAndSettle();
    }

    await open();
    await rename(tester, 'New layout');
    expect(config.value.label, 'New layout');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(config.value, initial);
    await open();
    await rename(tester, 'New layout');
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(layout.config.label, 'New layout');
    expect(
      find.byWidgetPredicate((w) => w is EditorSlot && w.label == 'New layout'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested layout does not rename its containing component', (
    tester,
  ) async {
    final layout = ValueNotifier(initial);
    final mode = ValueNotifier(true);
    addTearDown(layout.dispose);
    addTearDown(mode.dispose);
    String? outerRename;
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: EditorComponentLabel(
                label: 'Liste renommée',
                overridden: true,
                onChanged: (value) => outerRename = value,
                onRestore: () {},
                child: EditorSlot(
                  label: 'Liste',
                  child: ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: layout,
                    builder: (context, value, _) => SuperLayout(
                      label: 'Ligne',
                      config: value,
                      onChanged: (value) => layout.value = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final row = tester.state<EditorSlotState>(
      find.byWidgetPredicate(
        (widget) => widget is EditorSlot && widget.label == 'Ligne',
      ),
    );
    expect(row.label, 'Ligne');
    row.openEditor();
    await tester.pumpAndSettle();
    await rename(tester, 'Ligne renommée');

    expect(layout.value.label, 'Ligne renommée');
    expect(outerRename, isNull);
    expect(
      tester
          .state<EditorSlotState>(
            find.byWidgetPredicate(
              (widget) => widget is EditorSlot && widget.label == 'Liste',
            ),
          )
          .label,
      'Liste renommée',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty names are rejected without changing instance', (
    tester,
  ) async {
    final config = await pump(tester);
    await openSize(tester, 'Component a');
    await rename(tester, ' ');
    expect(find.text('Le nom ne peut pas être vide.'), findsOneWidget);
    expect(config.value.slotLabels, isEmpty);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renaming in size editor participates in undo and redo', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier<Appearance>(
      Appearance(layouts: {'root': initial}),
    );
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: mode,
    );
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorHistoryScope(
          controller: history,
          child: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: ValueListenableBuilder<Appearance>(
                  valueListenable: appearance,
                  builder: (context, value, _) => SuperLayout(
                    config: value.layouts['root']!,
                    onChanged: (value) => appearance.value = appearance.value
                        .withLayout('root', value),
                    slots: [
                      BuilderSlot(
                        id: 'a',
                        label: 'Component a',
                        builder: (_) => const EditableSurface(
                          label: 'Style a',
                          child: SizedBox.expand(key: ValueKey('content-a')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await openSize(tester, 'Component a');
    await rename(tester, 'First rename');
    await rename(tester, 'Final rename');
    expect(history.canUndo, isFalse);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(history.canUndo, isTrue);
    history.undo();
    await tester.pumpAndSettle();
    expect(appearance.value.layouts['root']!.slotLabels, isEmpty);
    expect(history.canUndo, isFalse);
    history.redo();
    await tester.pumpAndSettle();
    expect(appearance.value.layouts['root']!.slotLabels, {'a': 'Final rename'});
    expect(tester.takeException(), isNull);
  });
}
