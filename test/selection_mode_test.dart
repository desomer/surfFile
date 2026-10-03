import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/pages/explorer_page.dart';
import 'package:surf_file/services/personal_folders.dart';

void main() {
  testWidgets('selection mode menu switches between the three modes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await Directory.systemTemp.createTemp('surf_file_select_');
    for (final name in ['a.txt', 'b.txt', 'c.txt']) {
      await File('${root.path}\\$name').writeAsString(name);
    }
    addTearDown(() => root.delete(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      PersonalFolders.channel,
      (_) async => {for (final name in PersonalFolders.names) name: root.path},
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(PersonalFolders.channel, null),
    );
    Future<void> settleIo() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('Directory loading did not finish.');
    }

    Future<void> chooseMode(String key) async {
      await tester.tap(find.byKey(const ValueKey('selection-mode-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('selection-mode-$key')));
      await tester.pumpAndSettle();
    }

    Future<void> click(String name) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(name)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
    }

    await tester.pumpWidget(const MaterialApp(home: ExplorerPage()));
    await settleIo();
    expect(find.byType(Checkbox), findsNothing);

    // Clic sur la ligne : chaque clic ajoute ou retire la ligne.
    await chooseMode('rowClick');
    await click('a.txt');
    await click('b.txt');
    await click('a.txt');
    await click('c.txt');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('2 éléments copiés'), findsOneWidget);

    // Cases à cocher : une case par élément, la sélection est conservée.
    await chooseMode('checkbox');
    expect(find.byType(Checkbox), findsNWidgets(3));
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect([for (final box in boxes) box.value], [true, true, false]);

    await chooseMode('standard');
    expect(find.byType(Checkbox), findsNothing);
  });
}
