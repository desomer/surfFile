import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZoneSizeBindingAction', () {
    test('round-trips through the behavior catalog', () {
      final action = ZoneSizeBindingAction(
        zone: SuperLayoutZone.east,
        binding: const JsonTextBinding(path: 'ui.panel'),
        unit: SlotSizeUnit.percent,
        durationMs: 400,
        curve: BehaviorCurve.fastOutSlowIn,
      );
      final behavior = ComponentBehavior(
        id: 'b-zone',
        trigger: BehaviorTrigger.binding,
        action: action,
      );
      final decoded = ComponentBehavior.fromJson(
        jsonDecode(jsonEncode(behavior.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, behavior);
      expect(decoded.action, isA<ZoneSizeBindingAction>());
      expect(decoded.trigger, BehaviorTrigger.binding);
      expect(action.description, contains('%'));
    });

    test('defaults and validation', () {
      final action = ZoneSizeBindingAction.fromJson({
        'type': 'bindZoneSize',
        'zone': 'west',
        'binding': {'path': 'ui.width'},
      });
      expect(action.unit, SlotSizeUnit.pixels);
      expect(action.durationMs, ZoneSizeBindingAction.defaultDurationMs);
      expect(action.curve, BehaviorCurve.easeInOut);
      expect(
        () => ZoneSizeBindingAction(
          zone: SuperLayoutZone.center,
          binding: const JsonTextBinding(path: 'a'),
        ),
        throwsArgumentError,
      );
      expect(
        () => ZoneSizeBindingAction(
          zone: SuperLayoutZone.west,
          binding: const JsonTextBinding(path: 'a'),
          durationMs: -1,
        ),
        throwsArgumentError,
      );
      expect(BehaviorCatalog.items, contains(BehaviorCatalog.zoneSize));
      expect(
        BehaviorTrigger.gestures,
        isNot(contains(BehaviorTrigger.binding)),
      );
    });
  });

  group('SuperLayout zone size binding', () {
    late Directory directory;
    late JsonRepositoryStore store;
    late String repositoryId;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('zone-size-test-');
      store = JsonRepositoryStore(directory);
      await store.create('Ui');
      repositoryId = await store.idOf('Ui');
    });

    tearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    Future<void> write(WidgetTester tester, Object? value) async {
      await tester.runAsync(() async {
        final before = await store.read('Ui');
        await store.save(
          'Ui',
          jsonEncode({
            'ui': {'west': value},
          }),
          expectedText: before,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      // Laisse la lecture asynchrone du binding aboutir.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    Widget harness({
      SlotSizeUnit unit = SlotSizeUnit.pixels,
      SuperLayoutZone zone = SuperLayoutZone.west,
    }) => MaterialApp(
      home: JsonRepositoryScope(
        store: store,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: 600,
            child: SuperLayout(
              editable: false,
              showZoneNames: false,
              behaviours: [
                ComponentBehavior(
                  id: 'zone-west',
                  trigger: BehaviorTrigger.binding,
                  action: ZoneSizeBindingAction(
                    zone: zone,
                    binding: JsonTextBinding(
                      repositoryId: repositoryId,
                      path: 'ui.west',
                    ),
                    unit: unit,
                    durationMs: 200,
                    curve: BehaviorCurve.linear,
                  ),
                ),
              ],
              config: SuperLayoutConfig(
                west: zone == SuperLayoutZone.west,
                east: zone == SuperLayoutZone.east,
                north: zone == SuperLayoutZone.north,
                south: zone == SuperLayoutZone.south,
                autoSides: const {},
                placements: {
                  zone: ['w'],
                  SuperLayoutZone.center: ['c'],
                },
              ),
              slots: [
                BuilderSlot(
                  id: 'w',
                  label: 'West',
                  builder: (_) =>
                      const SizedBox.expand(key: ValueKey('west-content')),
                ),
                BuilderSlot(
                  id: 'c',
                  label: 'Center',
                  builder: (_) =>
                      const SizedBox.expand(key: ValueKey('center-content')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    double westWidth(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(const ValueKey('center-content'))).dx;

    for (final zone in [
      SuperLayoutZone.west,
      SuperLayoutZone.east,
      SuperLayoutZone.north,
      SuperLayoutZone.south,
    ]) {
      testWidgets('$zone slides fixed-size content on close and open', (
        tester,
      ) async {
        await write(tester, 300);
        await tester.pumpWidget(harness(zone: zone));
        await write(tester, 300);
        await tester.pumpAndSettle();
        final content = find.byKey(const ValueKey('west-content'));
        final center = find.byKey(const ValueKey('center-content'));
        final opened = tester.getRect(content);
        final horizontal =
            zone == SuperLayoutZone.west || zone == SuperLayoutZone.east;

        void expectSliding() {
          final panelRect = tester.getRect(content);
          final centerRect = tester.getRect(center);
          expect(
            horizontal ? panelRect.width : panelRect.height,
            closeTo(300, 1),
          );
          final movement = switch (zone) {
            SuperLayoutZone.west => opened.left - panelRect.left,
            SuperLayoutZone.east => panelRect.left - opened.left,
            SuperLayoutZone.north => opened.top - panelRect.top,
            _ => panelRect.top - opened.top,
          };
          expect(movement, greaterThan(1));
          expect(movement, lessThan(299));
          final gap = switch (zone) {
            SuperLayoutZone.west => centerRect.left - panelRect.right,
            SuperLayoutZone.east => panelRect.left - centerRect.right,
            SuperLayoutZone.north => centerRect.top - panelRect.bottom,
            _ => panelRect.top - centerRect.bottom,
          };
          expect(gap, closeTo(0, 1));
        }

        await write(tester, 0);
        await tester.pump(const Duration(milliseconds: 100));
        expectSliding();
        await tester.pumpAndSettle();
        expect(content, findsNothing);

        await write(tester, 300);
        await tester.pump(const Duration(milliseconds: 100));
        expectSliding();
        await tester.pumpAndSettle();
        expect(tester.getRect(content), opened);
      });
    }

    testWidgets('animates between the old and new bound sizes', (tester) async {
      await write(tester, 120);
      await tester.pumpWidget(harness());
      await write(tester, 120);
      await tester.pumpAndSettle();
      expect(westWidth(tester), moreOrLessEquals(120, epsilon: 1));

      await write(tester, 300);
      await tester.pump(const Duration(milliseconds: 100));
      final middle = westWidth(tester);
      expect(middle, greaterThan(125));
      expect(middle, lessThan(295));
      // Le contenu garde la plus grande taille pendant l'animation.
      expect(
        tester.getSize(find.byKey(const ValueKey('west-content'))).width,
        moreOrLessEquals(300, epsilon: 1),
      );
      await tester.pumpAndSettle();
      expect(westWidth(tester), moreOrLessEquals(300, epsilon: 1));

      await write(tester, 0);
      await tester.pumpAndSettle();
      expect(westWidth(tester), moreOrLessEquals(0, epsilon: 1));
      expect(find.byKey(const ValueKey('west-content')), findsNothing);

      await write(tester, 80);
      await tester.pumpAndSettle();
      expect(westWidth(tester), moreOrLessEquals(80, epsilon: 1));
      expect(find.byKey(const ValueKey('west-content')), findsOneWidget);
    });

    testWidgets('percent unit and invalid values', (tester) async {
      await write(tester, 25);
      await tester.pumpWidget(harness(unit: SlotSizeUnit.percent));
      await write(tester, 25);
      await tester.pumpAndSettle();
      expect(westWidth(tester), moreOrLessEquals(200, epsilon: 1));

      await write(tester, 'abc');
      await tester.pumpAndSettle();
      expect(westWidth(tester), moreOrLessEquals(100, epsilon: 1));
    });
  });
}
