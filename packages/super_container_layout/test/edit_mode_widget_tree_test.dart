import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_overlay.dart';

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
    VoidCallback onCreate, {
    VoidCallback? onDeactivate,
  }) async {
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
                        builder: (_) => _Probe(
                          onCreate: onCreate,
                          onDeactivate: onDeactivate,
                        ),
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
    testWidgets(
      '$name layout switches edit mode in-place without reparenting children',
      (tester) async {
        var created = 0;
        var deactivated = 0;
        final editMode = await pumpLayout(
          tester,
          config,
          () => created++,
          onDeactivate: () => deactivated++,
        );
        final regions = find.descendant(
          of: find.byType(SuperLayout),
          matching: find.byType(EditorSelectionRegion),
        );
        // A disabled region keeps a constant-depth inert BoxPointerRegion
        // without hit-testing, mouse tracking or GlobalKey reparenting.
        bool regionsInert() => regions.evaluate().every((element) {
          Widget? child;
          element.visitChildElements((e) => child = e.widget);
          return child is BoxPointerRegion &&
              !(child! as BoxPointerRegion).enabled;
        });
        final dragTargets = find.descendant(
          of: find.byType(SuperLayout),
          matching: find.byWidgetPredicate((widget) => widget is DragTarget),
        );
        expect(regionsInert(), isTrue);
        expect(dragTargets, findsNothing);
        final readOnlyCount = _elementCount(tester);
        await tester.enterText(
          find.byKey(const ValueKey('probe-input')),
          'kept',
        );

        editMode.value = true;
        await tester.pumpAndSettle();
        expect(regions, findsWidgets);
        expect(regionsInert(), isFalse);
        expect(deactivated, 0);
        expect(_elementCount(tester), readOnlyCount);

        editMode.value = false;
        await tester.pumpAndSettle();
        expect(regionsInert(), isTrue);
        expect(dragTargets, findsNothing);
        expect(_elementCount(tester), readOnlyCount);
        expect(created, 1);
        expect(deactivated, 0);
        expect(find.text('kept'), findsOneWidget);
      },
    );
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

  testWidgets(
    'SuperPage and SuperListView avoid child deactivation and unselected row edit rebuilds',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('edit-mode-list-opt-');
      final store = JsonRepositoryStore(dir);
      await tester.runAsync(() async {
        await store.create('Data');
        await store.save(
          'Data',
          jsonEncode({
            'items': [
              {'label': 'Row 0'},
              {'label': 'Row 1'},
              {'label': 'Row 2'},
            ],
          }),
          expectedText: await store.read('Data'),
        );
      });
      final repoId = await tester.runAsync(() => store.idOf('Data'));
      addTearDown(() {
        store.dispose();
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final editMode = ValueNotifier(false);
      final appearance = ValueNotifier(Appearance());
      addTearDown(editMode.dispose);
      addTearDown(appearance.dispose);

      var pageChildDeactivations = 0;
      final rowEditBuilds = <int, int>{};

      await tester.runAsync(() async {
        await tester.pumpWidget(
          JsonRepositoryScope(
            store: store,
            child: AppearanceScope(
              controller: appearance,
              child: StyleEditScope(
                controller: editMode,
                child: MaterialApp(
                  home: SuperPage(
                    child: Column(
                      children: [
                        _Probe(
                          onCreate: () {},
                          onDeactivate: () => pageChildDeactivations++,
                        ),
                        Expanded(
                          child: SuperListView(
                            id: 'items-list',
                            config: SuperListViewConfig(
                              binding: JsonTextBinding(
                                repositoryId: repoId,
                                path: 'items',
                              ),
                              itemExtent: 70,
                            ),
                            template: const SuperLayoutConfig(
                              placements: {
                                SuperLayoutZone.center: ['cell'],
                              },
                            ),
                            slots: [
                              BuilderSlot(
                                id: 'cell',
                                label: 'Cell',
                                builder: (context) {
                                  final idx =
                                      JsonListScope.maybeOf(context)
                                          ?.indices
                                          .lastOrNull ??
                                      -1;
                                  StyleEditScope.controllerOf(context);
                                  rowEditBuilds[idx] =
                                      (rowEditBuilds[idx] ?? 0) + 1;
                                  return Text('Item $idx');
                                },
                              ),
                            ],
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
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      });
      await tester.pumpAndSettle();

      final contents = tester
          .widgetList<IterableContent>(find.byType(IterableContent))
          .toList();
      expect(contents, hasLength(3));
      expect(contents[0].editable, isTrue);
      expect(contents[1].editable, isFalse);
      expect(contents[2].editable, isFalse);

      rowEditBuilds.clear();
      editMode.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(pageChildDeactivations, 0);
      expect(rowEditBuilds[0], 1);
      expect(rowEditBuilds.containsKey(1), isFalse);
      expect(rowEditBuilds.containsKey(2), isFalse);

      // Right-clicking unselected row 2 in edit mode selects it and opens its menu.
      await tester.tap(
        find.text('Item 2'),
        buttons: kSecondaryMouseButton,
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('style-menu-Iterable Content')),
        findsOneWidget,
      );
      EditorSlotState.closeActiveMenu();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      editMode.value = false;
      await tester.pumpAndSettle();
      expect(pageChildDeactivations, 0);

      await tester.runAsync(() async {
        await store.flushBindings();
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onCreate, this.onDeactivate});

  final VoidCallback onCreate;
  final VoidCallback? onDeactivate;

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
  void deactivate() {
    widget.onDeactivate?.call();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 200,
    height: 60,
    child: TextField(key: ValueKey('probe-input')),
  );
}
