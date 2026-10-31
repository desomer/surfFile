import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_overlay.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_selection_region.dart';

int _elementCount(WidgetTester tester) =>
    find.byType(SuperLayout).evaluate().fold(0, (count, element) {
      var total = 1;
      void visit(Element child) {
        total++;
        child.visitChildElements(visit);
      }

      element.visitChildElements(visit);
      return count + total;
    });

void main() {
  const size = Size(600, 400);

  Future<ValueNotifier<bool>> pumpLayout(
    WidgetTester tester,
    SuperLayoutConfig config,
    VoidCallback onCreate,
  ) async {
    final editMode = ValueNotifier(false);
    final appearance = ValueNotifier(Appearance(layouts: {'page': config}));
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editMode,
    );
    addTearDown(editMode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: editMode,
          child: EditorHistoryScope(
            controller: history,
            child: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: ValueListenableBuilder<Appearance>(
                  valueListenable: appearance,
                  builder: (context, value, _) => SuperLayout(
                    label: 'Page',
                    config: value.layouts['page']!,
                    onChanged: (next) => appearance.value = appearance.value
                        .withLayout('page', next),
                    slots: [
                      BuilderSlot(
                        id: 'a',
                        label: 'a',
                        builder: (_) => _Probe(onCreate: onCreate),
                      ),
                      BuilderSlot(
                        id: 'b',
                        label: 'b',
                        sizing: SlotSizing.fill,
                        builder: (_) => const SizedBox.expand(),
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
    await tester.pumpAndSettle();
    return editMode;
  }

  const flow = SuperLayoutConfig(
    north: false,
    south: false,
    west: false,
    east: false,
    placements: {
      SuperLayoutZone.center: ['a', 'b'],
    },
  );

  for (final (name, config) in [
    ('flow', flow),
    ('grid', flow.withPositioning(SuperLayoutPositioning.grid)),
  ]) {
    testWidgets('$name layout mounts edit wrappers only in edit mode', (
      tester,
    ) async {
      var created = 0;
      final editMode = await pumpLayout(tester, config, () => created++);
      final regions = find.descendant(
        of: find.byType(SuperLayout),
        matching: find.byType(EditorSelectionRegion),
      );
      // A disabled region renders its child directly, without hit-testing,
      // hover or painting layers.
      bool regionsInert() => regions.evaluate().every((element) {
        Widget? child;
        element.visitChildElements((e) => child = e.widget);
        return child is KeyedSubtree;
      });
      final dragTargets = find.descendant(
        of: find.byType(SuperLayout),
        matching: find.byWidgetPredicate((widget) => widget is DragTarget),
      );
      expect(regionsInert(), isTrue);
      expect(dragTargets, findsNothing);
      final readOnlyCount = _elementCount(tester);
      await tester.enterText(find.byKey(const ValueKey('probe-input')), 'kept');

      editMode.value = true;
      await tester.pumpAndSettle();
      expect(regions, findsWidgets);
      expect(regionsInert(), isFalse);
      expect(_elementCount(tester), greaterThan(readOnlyCount));

      editMode.value = false;
      await tester.pumpAndSettle();
      expect(regionsInert(), isTrue);
      expect(dragTargets, findsNothing);
      expect(_elementCount(tester), readOnlyCount);
      expect(created, 1);
      expect(find.text('kept'), findsOneWidget);
    });
  }

  testWidgets(
    'edit mode skips idle drop highlights and unselected resize portals',
    (tester) async {
      final editMode = await pumpLayout(
        tester,
        const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['a', 'b'],
          },
        ),
        () {},
      );
      editMode.value = true;
      await tester.pumpAndSettle();

      // Idle SlotZoneTarget widgets do not mount EditorOverlay until a drag hovers them.
      expect(
        find.descendant(
          of: find.byType(SlotZoneTarget),
          matching: find.byType(EditorOverlay),
        ),
        findsNothing,
      );
      // No slot is selected yet, so no slot resize OverlayPortal is mounted.
      expect(
        find.descendant(
          of: find.byType(SuperLayout),
          matching: find.byType(OverlayPortal),
        ),
        findsNothing,
      );
    },
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 200,
    height: 60,
    child: TextField(key: ValueKey('probe-input')),
  );
}
