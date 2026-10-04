import 'dart:convert';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/services/appearance_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';

void main() {
  test('all gradient types and alpha survive persistence', () {
    for (final type in FillType.values) {
      final fill = ContainerFill(
        type: type,
        start: const Color(0x405268D9),
        end: const Color(0x80B794F4),
        angle: 270,
        radius: 1.4,
      );
      final saved = AppearanceStore.decode(
        AppearanceStore.encode(
          Appearance(
            cardStyle: ContainerStyle(fill: fill),
            backgroundStyle: ContainerStyle(fill: fill),
          ),
        ),
      );
      expect(saved.cardStyle.fill.toJson(), fill.toJson());
      expect(saved.backgroundStyle.fill.toJson(), fill.toJson());
      final gradient = saved.backgroundStyle.fill.gradient(opacity: .5);
      if (type == FillType.solid) {
        expect(gradient, isNull);
      } else {
        expect(gradient!.colors.first.a, closeTo(fill.start.a * .5, .005));
      }
    }
  });

  test('old settings default to solid and malformed gradients fail', () {
    final json = jsonDecode(
      AppearanceStore.encode(const Appearance()),
    ) as Map<String, dynamic>;
    json.remove('cardStyle');
    json.remove('backgroundStyle');
    expect(
      AppearanceStore.decode(jsonEncode(json)).cardStyle.fill.type,
      FillType.solid,
    );
    for (final invalid in [
      {'type': 'unknown'},
      const ContainerFill().toJson()..['angle'] = 361,
      const ContainerFill().toJson()..['radius'] = 0,
      const ContainerFill().toJson()..['start'] = -1,
    ]) {
      json['cardStyle'] = Appearance.defaultCardStyle.toJson()
        ..['fill'] = invalid;
      expect(
        () => AppearanceStore.decode(jsonEncode(json)),
        throwsFormatException,
      );
    }
  });

  testWidgets('editor changes type and renders a matching gradient preview', (
    tester,
  ) async {
    var fill = const ContainerFill();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: ContainerStyleEditor(
                label: 'Test',
                value: fill,
                solidColor: Colors.white,
                onChanged: (value) => setState(() => fill = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<FillType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radial').last);
    await tester.pumpAndSettle();
    expect(fill.type, FillType.radial);
    final preview = tester.widget<Container>(
      find.byKey(const ValueKey('preview-Test')),
    );
    expect(
      (preview.decoration! as BoxDecoration).gradient,
      isA<RadialGradient>(),
    );
    expect(find.text('Couleur de départ'), findsOneWidget);
    await tester.tap(find.text('Couleur de départ'));
    await tester.pumpAndSettle();
    tester
        .widget<ColorPicker>(find.byType(ColorPicker).first)
        .onColorChanged(const Color(0x40112233));
    await tester.pumpAndSettle();
    expect(fill.start, const Color(0x40112233));
    expect(tester.takeException(), isNull);
  });

  for (final grid in [false, true]) {
    testWidgets('gradient renders on unselected cards only, grid=$grid', (
      tester,
    ) async {
      const fill = ContainerFill(
        type: FillType.linear,
        start: Color(0x405268D9),
        end: Color(0x80B794F4),
      );
      final controller = ValueNotifier(
        const Appearance(cardStyle: ContainerStyle(fill: fill)),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: ExplorerEntriesView(
                entries: [
                  for (final name in ['first.txt', 'second.txt'])
                    ExplorerEntry(
                      entity: File(name),
                      name: name,
                      isDirectory: false,
                      modified: DateTime(2026),
                      size: 1,
                    ),
                ],
                gridView: grid,
                selectedPath: 'first.txt',
                onSelected: (_) {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      if (grid) {
        final selected = tester.widget<Ink>(
          find
              .ancestor(of: find.text('first.txt'), matching: find.byType(Ink))
              .first,
        );
        final unselected = tester.widget<Ink>(
          find
              .ancestor(of: find.text('second.txt'), matching: find.byType(Ink))
              .first,
        );
        expect((selected.decoration! as BoxDecoration).gradient, isNull);
        final gradient = (unselected.decoration! as BoxDecoration).gradient!;
        expect(gradient.colors, [fill.start, fill.end]);
        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.text('second.txt'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, Colors.transparent);
      } else {
        final surface = find.byKey(const ValueKey('row-surface-second.txt'));
        final decoration = tester.widget<DecoratedBox>(
          find
              .descendant(of: surface, matching: find.byType(DecoratedBox))
              .last,
        );
        expect((decoration.decoration as BoxDecoration).gradient!.colors, [
          fill.start,
          fill.end,
        ]);
        final material = tester.widget<Material>(
          find.descendant(of: surface, matching: find.byType(Material)),
        );
        expect(material.color, Colors.transparent);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
