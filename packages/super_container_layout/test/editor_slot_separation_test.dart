import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  for (final editable in [false, true]) {
    testWidgets('standalone size action respects editable=$editable', (
      tester,
    ) async {
      var edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IterableContent(
              editable: editable,
              onEditSize: () async => edits++,
              config: const SuperLayoutConfig(
                placements: {
                  SuperLayoutZone.center: ['target'],
                },
              ),
              slots: [
                BuilderSlot(
                  id: 'target',
                  label: 'Target',
                  builder: (_) => const Text('Standalone target'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(
        find.text('Standalone target'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final action = find.byKey(
        const ValueKey(
          'style-menu-size-Taille et marge préférées : Iterable Content',
        ),
      );
      expect(action, editable ? findsOneWidget : findsNothing);
      if (editable) {
        await tester.tap(action);
        await tester.pumpAndSettle();
      }
      expect(edits, editable ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inline-only actions cannot open an empty menu', (tester) async {
    final target = GlobalKey<EditorSlotState>();
    final action = EditorSlotAction(
      label: 'Inline size',
      inline: true,
      enabled: true,
      onEdit: () async {},
      child: const SizedBox(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorSlot(
            key: target,
            editable: false,
            child: const Text('Target'),
          ),
        ),
      ),
    );
    await target.currentState!.openMenu(Offset.zero, actions: [action]);
    expect(find.byType(PopupMenuItem<EditorSlotState>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inherited size actions do not intercept native secondary taps outside editing',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      var nativeTaps = 0;
      var edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: IterableContent(
                onEditSize: () async => edits++,
                config: const SuperLayoutConfig(
                  placements: {
                    SuperLayoutZone.center: ['native'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'native',
                    label: 'Native',
                    builder: (_) => GestureDetector(
                      onSecondaryTapUp: (_) => nativeTaps++,
                      child: const SizedBox(
                        width: 180,
                        height: 80,
                        child: Text('Native target'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      mode.value = false;
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Native target'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(nativeTaps, 1);
      expect(edits, 0);
      expect(find.byType(PopupMenuItem<EditorSlotState>), findsNothing);
      final target = tester.state<EditorSlotState>(
        find.byType(EditorSlot).first,
      );
      await target.openMenu(
        Offset.zero,
        actions: [
          EditorSlotAction(
            label: 'Standalone action',
            enabled: true,
            onEdit: () async => edits++,
            child: const SizedBox(),
          ),
        ],
      );
      expect(find.text('Standalone action'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('decoration alone has no editing behavior in edit mode', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: const Scaffold(
            body: Center(
              child: SuperContainer(
                style: ContainerStyle(radius: 18),
                child: SizedBox(width: 160, height: 80, child: Text('Surface')),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<StyledSurface>(find.byType(StyledSurface)).style.radius,
      18,
    );
    expect(find.byType(EditorSlot), findsNothing);
    await tester.tap(find.text('Surface'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<EditorSlotState>), findsNothing);
    expect(find.byType(NativeComponentEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decoration reads AppearanceSlot reactively without writing', (
    tester,
  ) async {
    final appearance = ValueNotifier(Appearance());
    addTearDown(appearance.dispose);
    final slot = AppearanceSlot(
      'Surface',
      name: 'surface',
      read: (value) => value.style('surface'),
      write: (value, style) => throw StateError('Rendering must not write.'),
      reset: (value) => throw StateError('Rendering must not reset.'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppearanceScope(
          controller: appearance,
          child: Scaffold(
            body: SuperContainer(slot: slot, child: const Text('Surface')),
          ),
        ),
      ),
    );
    appearance.value = appearance.value.withStyle(
      'surface',
      const ContainerStyle(radius: 27),
    );
    await tester.pump();
    expect(
      tester.widget<StyledSurface>(find.byType(StyledSurface)).style.radius,
      27,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('EditorSlot edits an undecorated widget and respects edit mode', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: Center(
              child: EditorSlot(
                label: 'Plain widget',
                onEdit: () async => edits++,
                child: const SizedBox(
                  width: 180,
                  height: 100,
                  child: Text('Content'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(SuperContainer), findsNothing);
    expect(find.byType(StyledSurface), findsNothing);
    await tester.tap(find.text('Content'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-menu-Plain widget')));
    await tester.pumpAndSettle();
    expect(edits, 1);
    mode.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Content'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<EditorSlotState>), findsNothing);
    expect(edits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested slots select ancestors before the target', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: EditorSlot(
              label: 'Parent',
              onEdit: () async {},
              onContextMenu: (_) => selected.add('Parent'),
              child: EditorSlot(
                label: 'Child',
                onEdit: () async {},
                onContextMenu: (_) => selected.add('Child'),
                child: const Text('Target'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(selected, ['Parent', 'Child']);
    expect(find.byKey(const ValueKey('style-menu-Parent')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-menu-Child')), findsOneWidget);
    expect(find.byType(SuperContainer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic target identity deduplicates shared menu entries', (
    tester,
  ) async {
    final identity = Object();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorSlot(
            label: 'Outer',
            identity: identity,
            onEdit: () async {},
            child: EditorSlot(
              label: 'Inner',
              identity: identity,
              onEdit: () async {},
              child: const Text('Shared target'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.text('Shared target'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('style-menu-Inner')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-menu-Outer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composition applies spacing once with margin outside editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: EditableSurface(
              style: ContainerStyle(margin: 7, padding: 11),
              padding: EdgeInsets.all(3),
              child: SizedBox(
                key: ValueKey('inner-content'),
                width: 80,
                height: 40,
              ),
            ),
          ),
        ),
      ),
    );
    final outer = tester.getRect(find.byType(EditableSurface));
    final surface = tester.getRect(find.byType(StyledSurface));
    final editor = tester.getRect(find.byType(EditorSlot));
    final inner = tester.getRect(find.byKey(const ValueKey('inner-content')));
    expect(surface, editor);
    expect(surface.topLeft - outer.topLeft, const Offset(7, 7));
    expect(inner.topLeft - surface.topLeft, const Offset(14, 14));
    expect(outer.size, const Size(122, 82));
    expect(tester.takeException(), isNull);
  });
}
