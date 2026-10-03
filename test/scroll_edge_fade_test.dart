import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/scroll_edge_fade.dart';
import 'package:surf_file/theme/appearance.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/widgets/appearance_settings.dart';

Future<List<int>> maskAlphas(WidgetTester tester) async {
  final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
  expect(mask.blendMode, BlendMode.dstIn);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const bounds = Rect.fromLTWH(0, 0, 100, 200);
  canvas.drawRect(bounds, Paint()..shader = mask.shaderCallback(bounds));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 200);
  final bytes = (await image.toByteData())!;
  final alphas = [
    for (final y in [0, 14, 28, 100, 171, 185, 199])
      bytes.getUint8((y * 100 + 50) * 4 + 3)
  ];
  image.dispose();
  picture.dispose();
  return alphas;
}

void main() {
  test('fade preferences round trip, validate and support old settings', () {
    final saved = AppearanceStore.decode(AppearanceStore.encode(
        const Appearance(scrollFadeEnabled: false, scrollFadeExtent: 80)));
    expect(saved.scrollFadeEnabled, isFalse);
    expect(saved.scrollFadeExtent, 80);
    final json = jsonDecode(AppearanceStore.encode(const Appearance()))
        as Map<String, dynamic>;
    json.remove('scrollFadeEnabled');
    json.remove('scrollFadeExtent');
    final old = AppearanceStore.decode(jsonEncode(json));
    expect(old.scrollFadeEnabled, isTrue);
    expect(old.scrollFadeExtent, 28);
    for (final value in [7, 101, 'invalid']) {
      expect(
          () => AppearanceStore.decode(
              jsonEncode({...json, 'scrollFadeExtent': value})),
          throwsFormatException);
    }
    expect(
        () => AppearanceStore.decode(
            jsonEncode({...json, 'scrollFadeEnabled': 1})),
        throwsFormatException);
  });

  testWidgets('fade button edits and resets only fade settings',
      (tester) async {
    final controller = ValueNotifier(const Appearance(spacing: 20));
    addTearDown(controller.dispose);
    await tester.pumpWidget(AppearanceScope(
      controller: controller,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => AppearanceSettings.show(context),
                        child: const Text('Réglages')),
                  ))),
    ));
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fondu des fichiers'));
    await tester.tap(find.text('Fondu des fichiers'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(80);
    await tester.pumpAndSettle();
    expect(controller.value.scrollFadeExtent, 80);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(controller.value.scrollFadeEnabled, isFalse);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text('Réinitialiser le fondu'));
    await tester.pumpAndSettle();
    expect(controller.value.scrollFadeEnabled, isTrue);
    expect(controller.value.scrollFadeExtent, 28);
    expect(controller.value.spacing, 20);
  });

  for (final grid in [false, true]) {
    testWidgets('file viewport fades only scrollable edges: grid=$grid',
        (tester) async {
      final entries = List.generate(
          80,
          (index) => ExplorerEntry(
                entity: Directory('folder-$index'),
                name: 'folder-$index',
                isDirectory: true,
                modified: DateTime(2026),
                size: 0,
              ));
      final controller = ValueNotifier(const Appearance());
      addTearDown(controller.dispose);
      Future<void> show(int count) async {
        await tester.pumpWidget(AppearanceScope(
            controller: controller,
            child: MaterialApp(
                home: Scaffold(
              body: SizedBox(
                  height: 200,
                  child: ExplorerEntriesView(
                    entries: entries.take(count).toList(),
                    gridView: grid,
                    selectedPath: null,
                    onSelected: (_) {},
                    onOpen: (_) {},
                  )),
            ))));
        await tester.pumpAndSettle();
      }

      await show(80);
      expect(find.byType(ScrollEdgeFade), findsOneWidget);
      var alpha = await tester.runAsync(() => maskAlphas(tester));
      expect(alpha!.first, 255);
      expect(alpha.last, lessThan(10));
      controller.value = controller.value.copyWith(scrollFadeEnabled: false);
      await tester.pumpAndSettle();
      alpha = await tester.runAsync(() => maskAlphas(tester));
      expect(alpha, everyElement(255));
      controller.value = controller.value
          .copyWith(scrollFadeEnabled: true, scrollFadeExtent: 80);
      await tester.pumpAndSettle();
      alpha = await tester.runAsync(() => maskAlphas(tester));
      expect(alpha![4], lessThan(110));
      expect(alpha[3], 255);
      controller.value = controller.value.copyWith(scrollFadeExtent: 28);
      await tester.pumpAndSettle();
      alpha = await tester.runAsync(() => maskAlphas(tester));
      expect(alpha, isNotNull);
      expect(alpha![5], inInclusiveRange(100, 160));
      expect(alpha[3], 255);
      final state = tester.state<ScrollableState>(find.byType(Scrollable));
      state.position.jumpTo(100);
      await tester.pumpAndSettle();
      alpha = await tester.runAsync(() => maskAlphas(tester));
      expect(alpha!.first, lessThan(10));
      expect(alpha[1], inInclusiveRange(100, 160));
      expect(alpha[2], 255);
      expect(alpha.last, lessThan(10));
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();
      alpha = await tester.runAsync(() => maskAlphas(tester));
      expect(alpha!.first, lessThan(10));
      expect(alpha.last, 255);
      await show(1);
      alpha = await tester.runAsync(() => maskAlphas(tester));
      expect(alpha, everyElement(255));
      expect(tester.takeException(), isNull);
    });
  }
}
