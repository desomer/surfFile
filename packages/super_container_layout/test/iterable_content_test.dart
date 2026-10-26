import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_single_child.dart';

void main() {
  testWidgets('content sizing supports zones, grids and empty templates', (
    tester,
  ) async {
    for (final (config, expected) in [
      (
        const SuperLayoutConfig(
          north: true,
          west: true,
          south: false,
          east: false,
          autoSides: {SuperLayoutZone.north, SuperLayoutZone.west},
          placements: {
            SuperLayoutZone.center: ['center'],
            SuperLayoutZone.north: ['north'],
            SuperLayoutZone.west: ['west'],
          },
        ),
        const Size(130, 60),
      ),
      (
        const SuperLayoutConfig(
          positioning: SuperLayoutPositioning.grid,
          placements: {
            SuperLayoutZone.center: ['center'],
          },
          grid: GridLayoutConfig(
            columns: 2,
            rowHeight: 40,
            gap: 4,
            items: {'center': GridSlotPosition(width: 2, height: 2)},
          ),
        ),
        const Size(500, 84),
      ),
      (const SuperLayoutConfig(), const Size(16, 16)),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Wrap(
                  children: [
                    IterableContent(
                      shrinkWrap: true,
                      config: config,
                      slots: [
                        for (final (id, size) in [
                          ('center', const Size(100, 40)),
                          ('north', const Size(100, 20)),
                          ('west', const Size(30, 40)),
                        ])
                          BuilderSlot(
                            id: id,
                            label: id,
                            showLabel: false,
                            builder: (_) => SizedBox.fromSize(size: size),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(IterableContent)), expected);
      expect(tester.takeException(), isNull);
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    ContainerStyle style = const ContainerStyle(),
    ValueChanged<ContainerStyle>? onStyleChanged,
  }) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: editing,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                height: 400,
                child: IterableContent(
                  style: style,
                  onStyleChanged: onStyleChanged,
                  config: const SuperLayoutConfig(
                    north: false,
                    south: false,
                    west: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.center: ['text'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'text',
                      label: 'Text',
                      builder: (_) => const Text('Target'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('IterableContent starts transparent with a structural layout', (
    tester,
  ) async {
    await mount(tester);
    final surface = tester.widget<SuperContainer>(find.byType(SuperContainer));
    expect(surface.fallbackColor, Colors.transparent);
    expect(surface.style.color, isNull);
    expect(surface.style.outerMargin, EdgeInsets.zero);
    expect(surface.style.contentPadding, EdgeInsets.zero);
    expect(surface.style.elevation, 0);
    expect(surface.style.borderWidth, 0);
    expect(find.byType(SuperLayout), findsOneWidget);
    expect(find.byType(EditableSingleChild), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'IterableContent applies Card styling and keeps layout controls separate',
    (tester) async {
      const style = ContainerStyle(
        color: Colors.red,
        borderWidth: 2,
        radius: 12,
        padding: 10,
        margin: 8,
        elevation: 3,
      );
      await mount(tester, style: style);
      final surface = tester.widget<SuperContainer>(
        find.byType(SuperContainer),
      );
      expect(surface.style.color, Colors.red);
      expect(surface.style.radius, 12);
      expect(surface.style.contentPadding, const EdgeInsets.all(10));
      expect(surface.style.elevation, 3);
      await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      for (final label in ['Iterable Content', 'Centre', 'Layout']) {
        expect(find.byKey(ValueKey('style-menu-$label')), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('style-menu-add-Iterable Content')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-menu-add-Layout')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-menu-add-Centre')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-menu-remove-child-IterableContent')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling IterableContent style editing restores its style', (
    tester,
  ) async {
    final changes = <ContainerStyle>[];
    await mount(tester, onStyleChanged: changes.add);
    final state = tester.state<EditableSurfaceState>(
      find.byType(EditableSurface),
    );
    final dialog = state.openEditor();
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Slider &&
            widget.key == const ValueKey('padding-Iterable Content'),
      ),
    );
    slider.onChanged!(12);
    await tester.pumpAndSettle();
    expect(changes.last.padding, 12);
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    await dialog;
    expect(changes.last.padding, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty zone with stretch cross axis alignment stretches across available space',
    (tester) async {
      // 1. Column axis (vertical): cross axis is horizontal (width stretches to 500)
      const stretchColumn = SuperLayoutConfig(
        zoneFlows: {
          SuperLayoutZone.center: ZoneFlowConfig(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 400,
              child: SingleChildScrollView(
                child: Wrap(
                  children: [
                    IterableContent(
                      shrinkWrap: true,
                      config: stretchColumn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sizeCol = tester.getSize(find.byType(IterableContent));
      expect(sizeCol.width, 500);
      expect(sizeCol.height, 16);

      // 2. Row axis (horizontal): cross axis is vertical (height stretches to 300)
      const stretchRow = SuperLayoutConfig(
        zoneAxes: {
          SuperLayoutZone.center: Axis.horizontal,
        },
        zoneFlows: {
          SuperLayoutZone.center: ZoneFlowConfig(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 300,
              child: IterableContent(
                shrinkWrap: true,
                config: stretchRow,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sizeRow = tester.getSize(find.byType(IterableContent));
      expect(sizeRow.height, 300);
      expect(sizeRow.width, 500);
    },
  );
}
