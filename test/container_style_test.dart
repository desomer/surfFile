import 'dart:convert';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/editing/styles/container_style_editor.dart';
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
            styles: {
              'card': ContainerStyle(fill: fill),
              'background': ContainerStyle(fill: fill),
            },
          ),
        ),
      );
      expect(saved.style('card').fill.toJson(), fill.toJson());
      expect(saved.style('background').fill.toJson(), fill.toJson());
      final gradient = saved.style('background').fill.gradient(opacity: .5);
      if (type == FillType.solid) {
        expect(gradient, isNull);
      } else {
        expect(gradient!.colors.first.a, closeTo(fill.start.a * .5, .005));
      }
    }
  });

  test('old settings default to solid and malformed gradients fail', () {
    final json = jsonDecode(
      AppearanceStore.encode(Appearance()),
    ) as Map<String, dynamic>;
    json.remove('cardStyle');
    json.remove('backgroundStyle');
    expect(
      AppearanceStore.decode(jsonEncode(json)).style('card').fill.type,
      FillType.solid,
    );
    for (final invalid in [
      {'type': 'unknown'},
      const ContainerFill().toJson()..['angle'] = 361,
      const ContainerFill().toJson()..['radius'] = 0,
      const ContainerFill().toJson()..['start'] = -1,
      const ContainerFill().toJson()..['imageUrl'] = 123,
      const ContainerFill().toJson()..['imageFit'] = 'invalidFit',
      const ContainerFill().toJson()..['imageOpacity'] = 1.5,
      const ContainerFill().toJson()..['imageOpacity'] = -0.1,
    ]) {
      json['cardStyle'] = SurfFileAppearanceDefaults.defaultCardStyle.toJson()
        ..['fill'] = invalid;
      expect(
        () => AppearanceStore.decode(jsonEncode(json)),
        throwsFormatException,
      );
    }
  });

  test('background image settings survive persistence and compact JSON', () {
    const fill = ContainerFill(
      type: FillType.linear,
      imageUrl: 'https://example.com/surface.jpg',
      imageFit: BoxFit.contain,
      imageOpacity: .75,
    );
    final saved = AppearanceStore.decode(
      AppearanceStore.encode(
        Appearance(
          styles: {
            'card': const ContainerStyle(fill: fill),
            'background': const ContainerStyle(fill: fill),
          },
        ),
      ),
    );
    expect(saved.style('card').fill, fill);
    expect(saved.style('background').fill.toJson(), fill.toJson());
    final compact = fill.toCompactJson();
    expect(compact['imageUrl'], 'https://example.com/surface.jpg');
    expect(compact['imageFit'], 'contain');
    expect(compact['imageOpacity'], .75);
    expect(ContainerFill.fromJson(compact), fill);
    final image = saved.style('background').fill.decorationImage(opacity: .5);
    expect(image, isNotNull);
    expect(
      (image!.image as NetworkImage).url,
      'https://example.com/surface.jpg',
    );
    expect(image.fit, BoxFit.contain);
    expect(image.opacity, closeTo(.375, .005));

    // Also supports .webp, .svg and base64 / data URI values through imageUrl
    const webpFill = ContainerFill(
      imageUrl: 'https://example.com/surface.webp',
    );
    expect(
      (webpFill.decorationImage()!.image as NetworkImage).url,
      'https://example.com/surface.webp',
    );
    const svgUrlFill = ContainerFill(
      imageUrl: 'https://example.com/surface.svg',
    );
    expect(
      (svgUrlFill.decorationImage()!.image as NetworkImage).url,
      'https://example.com/surface.svg',
    );
    const webpBase64 =
        'UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA';
    const base64Fill = ContainerFill(imageUrl: webpBase64);
    expect(base64Fill.decorationImage()!.image, isA<MemoryImage>());
    final svgDataFill = ContainerFill(
      imageUrl:
          'data:image/svg+xml;base64,${base64Encode(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>'))}',
    );
    expect(svgDataFill.decorationImage()!.image, isA<SvgMemoryImage>());
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
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<FillType>),
        matching: find.text('Radial'),
      ),
    );
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
    await tester.enterText(
      find.byKey(const ValueKey('image-url-field-Test')),
      'https://example.com/preview.png',
    );
    await tester.pumpAndSettle();
    expect(fill.imageUrl, 'https://example.com/preview.png');
    final updatedPreview = tester.widget<Container>(
      find.byKey(const ValueKey('preview-Test')),
    );
    final updatedDecoration = updatedPreview.decoration! as BoxDecoration;
    expect(updatedDecoration.image, isNotNull);
    expect(
      (updatedDecoration.image!.image as NetworkImage).url,
      'https://example.com/preview.png',
    );
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
        Appearance(styles: {'card': ContainerStyle(fill: fill)}),
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
