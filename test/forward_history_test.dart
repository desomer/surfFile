import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/pages/explorer_page.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';

void main() {
  testWidgets('forward history survives refresh and failed navigation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await Directory.systemTemp.createTemp('surf_file_history_');
    final a = await Directory('${root.path}\\a').create();
    final b = await Directory('${root.path}\\b').create();
    final c = await Directory('${root.path}\\c').create();
    addTearDown(() => root.delete(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        PersonalFolders.channel,
        (_) async => {
              for (final name in PersonalFolders.names) name: a.path,
              'Pictures': b.path,
              'Music': c.path,
            });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(PersonalFolders.channel, null));
    Future<void> settleIo() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('Directory loading did not finish.');
    }

    String getPath() => tester
        .widget<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs))
        .path;
    Future<void> location(String label) async {
      await tester.tap(find.descendant(
          of: find.byType(ExplorerSidebar), matching: find.text(label)));
      await settleIo();
    }

    Future<void> mouse(int button) async {
      final gesture = await tester.startGesture(const Offset(500, 500),
          kind: PointerDeviceKind.mouse, buttons: button);
      await gesture.up();
      await settleIo();
    }

    await tester.pumpWidget(const MaterialApp(home: ExplorerPage()));
    await settleIo();
    await location('Documents');
    expect(getPath(), a.path);
    await location('Images');
    expect(getPath(), b.path);
    await mouse(kBackMouseButton);
    expect(getPath(), a.path);
    await tester.tap(find.byTooltip('Actualiser'));
    await settleIo();
    await mouse(kForwardMouseButton);
    expect(getPath(), b.path);
    await mouse(kBackMouseButton);
    await tester.runAsync(() => b.delete());
    await mouse(kForwardMouseButton);
    expect(getPath(), a.path);
    expect(tester.widget<IconButton>(find.byTooltip('Suivant')).onPressed,
        isNotNull);
    await tester.runAsync(() => b.create());
    await tester.tap(find.text('Réessayer'));
    await settleIo();
    expect(getPath(), b.path);
    await mouse(kBackMouseButton);
    await location('Musique');
    expect(getPath(), c.path);
    expect(
        tester.widget<IconButton>(find.byTooltip('Suivant')).onPressed, isNull);
    await mouse(kForwardMouseButton);
    expect(getPath(), c.path);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
