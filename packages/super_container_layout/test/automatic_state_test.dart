import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  test('automatic states roundtrip, reorder and reject invalid keys', () {
    final config = SuperValueConfig(
      mode: SuperValueMode.input,
      states: ValueConfigStates(
        automatic: {
          for (final state in AutomaticState.values.skip(2))
            state: ValueConfigOverride(
              config: const SuperValueConfig(fontSize: 24),
              properties: {ValueStateProperty.fontSize},
            ),
        },
      ),
    );
    final decoded = SuperValueConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
    );
    expect(decoded, config);
    expect(decoded.hashCode, config.hashCode);
    expect(decoded.states!.automatic.length, 4);
    expect(decoded.states!.order, [
      ValueConfigStates.hoverKey,
      ValueConfigStates.selectedKey,
      ...AutomaticState.values.skip(2).map((state) => state.key),
    ]);
    expect(() => decoded.validate(), returnsNormally);
    final removed = decoded.states!.copyWith(automatic: {});
    expect(removed.order, [
      ValueConfigStates.hoverKey,
      ValueConfigStates.selectedKey,
    ]);
    expect(
      () => ValueConfigStates.fromJson({
        'named': {},
        'automatic': {'unknown': {}},
      }),
      throwsFormatException,
    );
    expect(
      () => ValueConfigStates(
        automatic: {AutomaticState.hover: ValueConfigOverride()},
      ),
      throwsFormatException,
    );
    final style = ContainerStyle(
      states: SurfaceStyleStates(
        automatic: {
          AutomaticState.contentHover: SelectedSurfaceStyle(
            style: const ContainerStyle(padding: 12),
            properties: {SurfaceStyleProperty.padding},
          ),
        },
      ),
    );
    final surface = ContainerStyle.fromJson(
      jsonDecode(jsonEncode(style.toJson())),
    );
    expect(surface.states, style.states);
    expect(
      surface.states!
          .resolve(surface, activeStates: {AutomaticState.contentHover})
          .padding,
      12,
    );
    expect(
      () => SurfaceStyleStates(
        automatic: {AutomaticState.focused: SelectedSurfaceStyle()},
      ),
      throwsFormatException,
    );
  });

  Future<void> text(
    WidgetTester tester,
    SuperValueConfig config, {
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 140,
              child: SuperValue(
                id: 'test',
                config: config,
                controller: controller,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final field = find.byKey(const ValueKey('super-value-input-test'));

  testWidgets(
    'focus enters and exits once, resets content and preserves focus while typing',
    (tester) async {
      final changes = <String>[];
      await text(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          initialText: 'Default',
          states: ValueConfigStates(
            automatic: {
              AutomaticState.focused: ValueConfigOverride(
                config: const SuperValueConfig(
                  mode: SuperValueMode.input,
                  initialText: 'Focused',
                  fontSize: 26,
                ),
                properties: {
                  ValueStateProperty.content,
                  ValueStateProperty.fontSize,
                },
              ),
            },
          ),
        ),
        onChanged: changes.add,
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(field).style!.fontSize, 26);
      expect(tester.widget<TextField>(field).controller!.text, 'Focused');
      expect(changes, isEmpty);
      await tester.enterText(field, 'Typed');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Typed');
      expect(changes, ['Typed']);
      tester.widget<TextField>(field).focusNode!.unfocus();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Default');
      expect(changes, ['Typed']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled and readOnly use pre-overlay behavior without oscillation',
    (tester) async {
      final config = SuperValueConfig(
        mode: SuperValueMode.input,
        enabled: false,
        readOnly: true,
        states: ValueConfigStates(
          automatic: {
            AutomaticState.disabled: ValueConfigOverride(
              config: const SuperValueConfig(
                enabled: true,
                readOnly: false,
                fontSize: 25,
              ),
              properties: {
                ValueStateProperty.enabled,
                ValueStateProperty.fontSize,
              },
            ),
            AutomaticState.readOnly: ValueConfigOverride(
              config: const SuperValueConfig(color: Colors.red),
              properties: {ValueStateProperty.color},
            ),
          },
        ),
      );
      await text(tester, config);
      for (var i = 0; i < 3; i++) {
        final input = tester.widget<TextField>(field);
        expect(input.enabled, isTrue);
        expect(input.readOnly, isFalse);
        expect(input.style!.fontSize, 25);
        expect(input.style!.color!.toARGB32(), Colors.red.toARGB32());
        await tester.pump(const Duration(milliseconds: 50));
      }
      await text(tester, config.copyWith(mode: SuperValueMode.display));
      final display = tester.widget<Text>(
        find.byKey(const ValueKey('super-value-display-test')),
      );
      expect(display.style!.fontSize, isNot(25));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('focus never resets an externally owned controller', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Owned');
    addTearDown(controller.dispose);
    await text(
      tester,
      SuperValueConfig(
        mode: SuperValueMode.input,
        states: ValueConfigStates(
          automatic: {
            AutomaticState.focused: ValueConfigOverride(
              config: const SuperValueConfig(fontSize: 30),
              properties: {ValueStateProperty.fontSize},
            ),
          },
        ),
      ),
      controller: controller,
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(controller.text, 'Owned');
    expect(tester.widget<TextField>(field).style!.fontSize, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Content hover covers sibling space and is independent across rows and nested Content',
    (tester) async {
      Widget label(String id) => SuperValue(
        id: id,
        config: SuperValueConfig(
          initialText: id,
          states: ValueConfigStates(
            automatic: {
              AutomaticState.contentHover: ValueConfigOverride(
                config: const SuperValueConfig(color: Colors.red),
                properties: {ValueStateProperty.color},
              ),
            },
          ),
        ),
      );
      Widget content(String id, {Widget? nested}) => SizedBox(
        key: ValueKey('row-$id'),
        width: 500,
        height: 180,
        child: IterableContent(
          editable: false,
          style: ContainerStyle(
            states: SurfaceStyleStates(
              automatic: {
                AutomaticState.contentHover: SelectedSurfaceStyle(
                  style: const ContainerStyle(color: Colors.blue),
                  properties: {SurfaceStyleProperty.background},
                ),
              },
            ),
          ),
          config: const SuperLayoutConfig(
            north: false,
            south: false,
            east: false,
            west: false,
            placements: {
              SuperLayoutZone.center: ['row'],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'row',
              label: 'row',
              showLabel: false,
              builder: (_) => Row(
                children: [
                  SizedBox(width: 80, child: label(id)),
                  if (nested != null)
                    Expanded(child: nested)
                  else
                    const Spacer(),
                  const SizedBox(width: 80, height: 100),
                ],
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  content('a', nested: content('inner')),
                  content('b'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      int? color(String id) => tester
          .widget<Text>(find.byKey(ValueKey('super-value-display-$id')))
          .style!
          .color
          ?.toARGB32();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getTopRight(find.byKey(const ValueKey('row-a'))) +
            const Offset(-20, 80),
      );
      await tester.pumpAndSettle();
      expect(color('a'), Colors.red.toARGB32());
      expect(
        tester
            .widget<SuperContainer>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('row-a')),
                    matching: find.byType(SuperContainer),
                  )
                  .first,
            )
            .style
            .color!
            .toARGB32(),
        Colors.blue.toARGB32(),
      );
      expect(color('inner'), isNot(Colors.red.toARGB32()));
      expect(color('b'), isNot(Colors.red.toARGB32()));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('row-inner'))),
      );
      await tester.pumpAndSettle();
      expect(color('inner'), Colors.red.toARGB32());
      await mouse.moveTo(
        tester.getTopRight(find.byKey(const ValueKey('row-b'))) +
            const Offset(-20, 80),
      );
      await tester.pumpAndSettle();
      expect(color('a'), isNot(Colors.red.toARGB32()));
      expect(color('inner'), isNot(Colors.red.toARGB32()));
      expect(color('b'), Colors.red.toARGB32());
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
