import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/pages/explorer_page.dart';
import 'package:surf_file/services/file_operations.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';
import 'package:surf_file/widgets/explorer/states/explorer_skeleton.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_toolbar.dart';
import 'package:surf_file/widgets/file_operations/file_action_bar.dart';

void main() {
  testWidgets('split view shows two independent folder navigations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('surf_file_split_');
    final a = Directory('${root.path}\\a')..createSync();
    final b = Directory('${root.path}\\b')..createSync();
    addTearDown(() => root.deleteSync(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      PersonalFolders.channel,
      (_) async => {
        for (final name in PersonalFolders.names) name: a.path,
        'Pictures': b.path,
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(PersonalFolders.channel, null),
    );
    Future<void> settleIo() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find.byType(ExplorerSkeleton).evaluate().isEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('Directory loading did not finish.');
    }

    List<String> paths() => tester
        .widgetList<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs))
        .map((crumbs) => crumbs.path)
        .toList();
    Future<void> location(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(ExplorerSidebar),
          matching: find.text(label),
        ),
      );
      await settleIo();
    }

    await tester.pumpWidget(const MaterialApp(home: ExplorerPage()));
    await settleIo();
    await location('Documents');
    expect(find.byType(ExplorerToolbar), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('split-view')));
    await settleIo();
    expect(find.byType(ExplorerToolbar), findsNWidgets(2));
    expect(find.byType(ExplorerSidebar), findsOneWidget);
    expect(paths(), [a.path, a.path]);

    // The right pane is active after opening: the sidebar drives it.
    await location('Images');
    expect(paths(), [a.path, b.path]);

    // Clicking the left pane makes the sidebar drive it instead.
    final left = tester.getTopLeft(find.byType(ExplorerToolbar).first);
    await tester.tapAt(left + const Offset(20, 200));
    await settleIo();
    await location('Images');
    expect(paths(), [b.path, b.path]);

    await tester.tap(find.byKey(const ValueKey('split-view')).first);
    await settleIo();
    expect(find.byType(ExplorerToolbar), findsOneWidget);
    expect(paths(), [b.path]);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('action bar swaps panes and copies or moves to the right', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('surf_file_bar_');
    final a = Directory('${root.path}\\a')..createSync();
    final b = Directory('${root.path}\\b')..createSync();
    File('${a.path}\\note.txt').writeAsStringSync('hello');
    addTearDown(() => root.deleteSync(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      PersonalFolders.channel,
      (_) async => {
        for (final name in PersonalFolders.names) name: a.path,
        'Pictures': b.path,
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(PersonalFolders.channel, null),
    );
    Future<void> settleIo() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find.byType(ExplorerSkeleton).evaluate().isEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('Directory loading did not finish.');
    }

    List<String> paths() => tester
        .widgetList<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs))
        .map((crumbs) => crumbs.path)
        .toList();
    bool enabled(String id) =>
        tester
            .widget<IconButton>(find.byKey(ValueKey('file-action-$id')))
            .onPressed !=
        null;
    Future<void> act(String id) async {
      await tester.tap(find.byKey(ValueKey('file-action-$id')));
      await settleIo();
    }

    await tester.pumpWidget(const MaterialApp(home: ExplorerPage()));
    await settleIo();
    await tester.tap(
      find.descendant(
        of: find.byType(ExplorerSidebar),
        matching: find.text('Documents'),
      ),
    );
    await settleIo();
    expect(find.byType(FileActionBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('split-view')));
    await settleIo();
    await tester.tap(
      find.descendant(
        of: find.byType(ExplorerSidebar),
        matching: find.text('Images'),
      ),
    );
    await settleIo();
    expect(paths(), [a.path, b.path]);
    expect(tester.getSize(find.byType(FileActionBar)).width, 40);
    expect(enabled('swap'), isTrue);
    expect(enabled('copy-right'), isFalse);

    await tester.tap(find.text('note.txt'));
    await tester.pump();
    expect(enabled('copy-right'), isTrue);
    await act('copy-right');
    expect(File('${b.path}\\note.txt').existsSync(), isTrue);
    expect(File('${a.path}\\note.txt').existsSync(), isTrue);
    expect(find.text('1 élément copié'), findsOneWidget);
    expect(find.text('note.txt'), findsNWidgets(2));

    await tester.tap(find.text('note.txt').first);
    await tester.pump();
    await act('move-right');
    expect(File('${a.path}\\note.txt').existsSync(), isFalse);
    expect(File('${b.path}\\note (2).txt').existsSync(), isTrue);
    expect(find.text('note (2).txt'), findsOneWidget);

    await act('swap');
    expect(paths(), [b.path, a.path]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(FileJobs.keepFinished);
  }, skip: !Platform.isWindows);
}
