import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/styles/surface_state_controls.dart';

void main() {
  testWidgets('state buttons wrap and keep exactly one state selected', (
    tester,
  ) async {
    String? selected;
    final style = ContainerStyle(
      states: SurfaceStyleStates(
        named: {
          'ready': const ContainerStyle(),
          'pending': const ContainerStyle(),
          'A very long state name that must fit within a narrow panel':
              const ContainerStyle(),
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: SurfaceStateControls(
                    style: style,
                    state: selected,
                    allowSelected: true,
                    ownerContext: context,
                    onChanged: (_) {},
                    onSelect: (value) => setState(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final choices = find.descendant(
      of: find.byKey(const ValueKey('surface-state-selector')),
      matching: find.byType(ChoiceChip),
    );
    expect(choices, findsNWidgets(6));
    final ready = find.byKey(const ValueKey('surface-state-choice-ready'));
    final defaultState = find.byKey(const ValueKey('surface-state-choice-'));
    expect(
      tester.getTopLeft(ready).dy,
      greaterThan(tester.getTopLeft(defaultState).dy),
    );
    for (final key in ['ready', selectedSurfaceStateKey, '']) {
      await tester.tap(find.byKey(ValueKey('surface-state-choice-$key')));
      await tester.pumpAndSettle();
      expect(selected, key.isEmpty ? null : key);
      expect(
        tester.widgetList<ChoiceChip>(choices).where((chip) => chip.selected),
        hasLength(1),
      );
    }
    expect(tester.takeException(), isNull);
  });

  Future<void> mount(
    WidgetTester tester, {
    ContainerStyle style = const ContainerStyle(),
    bool inList = false,
    bool selected = false,
    bool? outerSelected,
    ValueChanged<ContainerStyle>? onChanged,
  }) async {
    Widget surface = EditableSurface(
      label: 'Target',
      style: style,
      onStyleChanged: onChanged,
      child: const SizedBox(width: 160, height: 80, child: Text('Content')),
    );
    if (inList) {
      surface = JsonListScope(
        repositoryId: null,
        indices: const [0],
        selected: selected,
        child: surface,
      );
    }
    if (outerSelected != null) {
      surface = JsonListScope(
        repositoryId: null,
        indices: const [0],
        selected: outerSelected,
        child: surface,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: surface)),
      ),
    );
    await tester.pumpAndSettle();
  }

  ContainerStyle rendered(WidgetTester tester) =>
      tester.widget<SuperContainer>(find.byType(SuperContainer)).style;

  testWidgets(
    'pointer hover applies overrides and restores on exit without writes',
    (tester) async {
      final changes = <ContainerStyle>[];
      final style = ContainerStyle(
        color: Colors.green,
        states: SurfaceStyleStates(
          hover: SelectedSurfaceStyle(
            style: const ContainerStyle(color: Colors.red),
            properties: {SurfaceStyleProperty.background},
          ),
          selected: SelectedSurfaceStyle(
            style: const ContainerStyle(borderWidth: 2),
            properties: {SurfaceStyleProperty.border},
          ),
        ),
      );
      await mount(
        tester,
        style: style,
        inList: true,
        selected: true,
        onChanged: changes.add,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Content')));
      await tester.pumpAndSettle();
      expect(rendered(tester).color, const Color(0xFFF44336));
      expect(rendered(tester).borderWidth, 2);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(rendered(tester).color, const Color(0xFF4CAF50));
      expect(rendered(tester).borderWidth, 2);
      expect(changes, isEmpty);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hover editing and button dragging preview priority and cancel together',
    (tester) async {
      final style = ContainerStyle(
        color: Colors.green,
        states: SurfaceStyleStates(
          selected: SelectedSurfaceStyle(
            style: const ContainerStyle(padding: 8),
            properties: {SurfaceStyleProperty.padding},
          ),
        ),
      );
      await mount(tester, style: style, inList: true, selected: true);
      final state = tester.state<EditableSurfaceState>(
        find.byType(EditableSurface),
      );
      final dialog = state.openEditor();
      await tester.pumpAndSettle();
      final hover = find.byKey(
        const ValueKey('surface-state-choice-$hoverSurfaceStateKey'),
      );
      final selected = find.byKey(
        const ValueKey('surface-state-choice-$selectedSurfaceStateKey'),
      );
      expect(
        tester.getTopLeft(hover).dx,
        lessThan(tester.getTopLeft(selected).dx),
      );
      await tester.tap(hover);
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(
            find.byWidgetPredicate(
              (w) => w is Slider && w.key == const ValueKey('padding-Target'),
            ),
          )
          .onChanged!(12);
      await tester.pumpAndSettle();
      expect(state.style.states!.hover!.properties, {
        SurfaceStyleProperty.padding,
      });
      expect(rendered(tester).padding, 8);
      await tester.dragFrom(
        tester.getCenter(hover),
        tester.getCenter(selected) - tester.getCenter(hover),
      );
      await tester.pumpAndSettle();
      expect(state.style.states!.order, [
        selectedSurfaceStateKey,
        hoverSurfaceStateKey,
      ]);
      expect(rendered(tester).padding, 12);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      await dialog;
      expect(state.style.states, style.states);
      expect(rendered(tester).padding, 8);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nearest list row selection overrides only configured fields', (
    tester,
  ) async {
    final style = ContainerStyle(
      color: Colors.blue,
      radius: 9,
      states: SurfaceStyleStates(
        selected: SelectedSurfaceStyle(
          style: const ContainerStyle(borderWidth: 2, radius: 0),
          properties: {
            SurfaceStyleProperty.border,
            SurfaceStyleProperty.corners,
          },
        ),
      ),
    );
    await mount(tester, style: style, inList: true, selected: true);
    expect(rendered(tester).radius, 0);
    expect(rendered(tester).borderWidth, 2);
    expect(rendered(tester).color, const Color(0xFF2196F3));
    await mount(
      tester,
      style: style,
      inList: true,
      selected: false,
      outerSelected: true,
    );
    expect(rendered(tester).radius, 9);
    expect(rendered(tester).borderWidth, 0);
    await mount(tester, style: style);
    expect(rendered(tester).radius, 9);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'state CRUD previews locally and cancellation restores definitions',
    (tester) async {
      final changes = <ContainerStyle>[];
      await mount(
        tester,
        style: const ContainerStyle(color: Colors.blue),
        onChanged: changes.add,
      );
      final state = tester.state<EditableSurfaceState>(
        find.byType(EditableSurface),
      );
      final dialog = state.openEditor();
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('surface-state-selector'));
      expect(
        find.descendant(of: selector, matching: find.byType(ChoiceChip)),
        findsNWidgets(2),
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('surface-state-choice-')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('surface-state-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('surface-state-name')),
        'Par défaut',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(find.text('Nom d’état vide ou réservé.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('surface-state-name')),
        'ready',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(changes.last.states!.named.keys, ['ready']);
      expect(changes.last.states!.named['ready']!.color, Colors.blue);
      final slider = tester.widget<Slider>(
        find.byWidgetPredicate(
          (w) => w is Slider && w.key == const ValueKey('padding-Target'),
        ),
      );
      slider.onChanged!(12);
      await tester.pumpAndSettle();
      expect(changes.last.padding, 0);
      expect(changes.last.states!.named['ready']!.padding, 12);
      expect(rendered(tester).padding, 12);
      await tester.tap(find.byTooltip('Renommer l’état'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('surface-state-name')),
        'done',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(changes.last.states!.named.keys, ['done']);
      expect(changes.last.states!.named['done']!.padding, 12);
      await tester.tap(find.byKey(const ValueKey('surface-state-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('surface-state-name')),
        'done',
      );
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      expect(find.text('Ce nom existe déjà.'), findsOneWidget);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('surface-state-delete')));
      await tester.pumpAndSettle();
      expect(changes.last.states!.named, isEmpty);
      expect(rendered(tester).padding, 0);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      await dialog;
      expect(changes.last.states, isNull);
      expect(rendered(tester).padding, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview affects only the edited surface', (tester) async {
    final style = ContainerStyle(
      states: SurfaceStyleStates(
        named: {'ready': const ContainerStyle(padding: 12)},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              EditableSurface(
                style: style,
                label: 'First',
                child: const Text('First'),
              ),
              EditableSurface(
                style: style,
                label: 'Second',
                child: const Text('Second'),
              ),
            ],
          ),
        ),
      ),
    );
    final dialog = tester
        .state<EditableSurfaceState>(find.byType(EditableSurface).first)
        .openEditor();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('surface-state-choice-ready')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<SuperContainer>(find.byType(SuperContainer))
          .map((w) => w.style.padding),
      [12, 0],
    );
    await tester.tap(find.text('Appliquer').last);
    await tester.pumpAndSettle();
    await dialog;
    expect(
      tester
          .widgetList<SuperContainer>(find.byType(SuperContainer))
          .map((w) => w.style.padding),
      [0, 0],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('state edits form one history entry and cancel leaves none', (
    tester,
  ) async {
    final initial = ContainerStyle(
      states: SurfaceStyleStates(named: {'ready': const ContainerStyle()}),
    );
    final appearance = ValueNotifier(Appearance(styles: {'target': initial}));
    final editing = ValueNotifier(true);
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editing,
    );
    addTearDown(history.dispose);
    addTearDown(editing.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorHistoryScope(
          controller: history,
          child: ValueListenableBuilder<Appearance>(
            valueListenable: appearance,
            builder: (_, value, _) => Scaffold(
              body: EditableSurface(
                label: 'Target',
                style: value.styles['target']!,
                onStyleChanged: (style) => appearance.value = appearance.value
                    .withStyle('target', style),
                child: const Text('Content'),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> edit(double padding, {required bool confirm}) async {
      final dialog = tester
          .state<EditableSurfaceState>(find.byType(EditableSurface))
          .openEditor();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('surface-state-choice-ready')),
      );
      await tester.pumpAndSettle();
      for (final value in [padding / 2, padding]) {
        tester
            .widget<Slider>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Slider &&
                    widget.key == const ValueKey('padding-Target'),
              ),
            )
            .onChanged!(value);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(confirm ? 'Appliquer' : 'Annuler').last);
      await tester.pumpAndSettle();
      await dialog;
    }

    await edit(20, confirm: true);
    expect(
      appearance.value.styles['target']!.states!.named['ready']!.padding,
      20,
    );
    expect(history.canUndo, isTrue);
    history.undo();
    await tester.pumpAndSettle();
    expect(appearance.value.styles['target'], same(initial));
    expect(history.canUndo, isFalse);
    history.redo();
    await tester.pumpAndSettle();
    expect(
      appearance.value.styles['target']!.states!.named['ready']!.padding,
      20,
    );
    history.clear();
    final before = appearance.value;
    await edit(30, confirm: false);
    expect(
      appearance.value.styles['target']!.states,
      before.styles['target']!.states,
    );
    expect(history.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected property switches support reset and persist independently',
    (tester) async {
      ContainerStyle? saved;
      await mount(tester, inList: true, onChanged: (value) => saved = value);
      final state = tester.state<EditableSurfaceState>(
        find.byType(EditableSurface),
      );
      final dialog = state.openEditor();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('surface-state-choice-$selectedSurfaceStateKey'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('surface-state-override-border')),
      );
      await tester.pumpAndSettle();
      expect(saved!.states!.selected!.properties, {
        SurfaceStyleProperty.border,
      });
      await tester.tap(
        find.byKey(const ValueKey('surface-state-override-border')),
      );
      await tester.pumpAndSettle();
      expect(saved!.states!.selected!.isEmpty, isTrue);
      await tester.tap(find.text('Appliquer').last);
      await tester.pumpAndSettle();
      await dialog;
      expect(tester.takeException(), isNull);
    },
  );
}
