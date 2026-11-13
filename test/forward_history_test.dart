import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/pages/explorer_page.dart';
import 'package:surf_file/services/disk_space.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/widgets/explorer/explorer_scope.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';

void main() {
  testWidgets('forward history survives refresh and failed navigation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Directory root;
    late Directory a;
    late Directory b;
    late Directory c;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('surf_file_history_');
      a = await Directory('${root.path}\\a').create();
      b = await Directory('${root.path}\\b').create();
      c = await Directory('${root.path}\\c').create();
    });
    addTearDown(
      () async => tester.runAsync(() => root.delete(recursive: true)),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DiskSpace.channel, (_) async => []);
    addTearDown(
      () => messenger.setMockMethodCallHandler(DiskSpace.channel, null),
    );
    messenger.setMockMethodCallHandler(
      PersonalFolders.channel,
      (_) async => {
        for (final name in PersonalFolders.names) name: a.path,
        'Pictures': b.path,
        'Music': c.path,
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(PersonalFolders.channel, null),
    );
    Future<void> settleIo() async {
      var idleFrames = 0;
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        final scopeFinder = find.byType(ExplorerPaneScope);
        if (scopeFinder.evaluate().isNotEmpty) {
          final data = tester.widget<ExplorerPaneScope>(scopeFinder).data;
          if (data.hasLoaded && !data.loading) {
            if (++idleFrames == 4) return;
            continue;
          }
        }
        idleFrames = 0;
      }
      fail('Directory loading did not finish.');
    }

    String getPath() => tester
        .widget<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs))
        .path;
    Future<void> location(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(ExplorerSidebar),
          matching: find.text(label),
        ),
      );
      await settleIo();
    }

    Future<void> mouse(int button, {bool enabled = true}) async {
      final tooltip = button == kBackMouseButton ? 'Retour' : 'Suivant';
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == tooltip,
              ),
            )
            .onPressed,
        enabled ? isNotNull : isNull,
      );
      final gesture = await tester.startGesture(
        const Offset(500, 500),
        kind: PointerDeviceKind.mouse,
        buttons: button,
      );
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
    final forwardButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Suivant',
    );
    expect(tester.widget<IconButton>(forwardButton).onPressed, isNotNull);
    await tester.runAsync(() => b.create());
    await tester.tap(find.text('Réessayer'));
    await settleIo();
    expect(getPath(), b.path);
    await mouse(kBackMouseButton);
    await location('Musique');
    expect(getPath(), c.path);
    expect(tester.widget<IconButton>(forwardButton).onPressed, isNull);
    await mouse(kForwardMouseButton, enabled: false);
    expect(getPath(), c.path);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
