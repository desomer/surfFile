import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/pages/explorer_page.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/widgets/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer_sidebar.dart';
import 'package:surf_file/widgets/explorer_sort_header.dart';
import 'package:surf_file/widgets/explorer_toolbar.dart';
import 'package:surf_file/widgets/explorer_view_mode_bar.dart';

void main() {
  testWidgets('explorer frame keeps its blocks where they are', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('surf_file_frame_');
    File('${root.path}\\a.txt').writeAsStringSync('a');
    addTearDown(() => root.deleteSync(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      PersonalFolders.channel,
      (_) async => {for (final name in PersonalFolders.names) name: root.path},
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(PersonalFolders.channel, null),
    );
    await tester.pumpWidget(const MaterialApp(home: ExplorerPage()));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ExplorerEntriesView).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(seconds: 1));
    Rect rect(Type type) => tester.getRect(find.byType(type));
    final frame = {
      'sidebar': rect(ExplorerSidebar),
      'toolbar': rect(ExplorerToolbar),
      'breadcrumbs': rect(ExplorerBreadcrumbs),
      'viewModeBar': rect(ExplorerViewModeBar),
      'sortHeader': rect(ExplorerSortHeader),
      'entries': rect(ExplorerEntriesView),
    };
    expect(frame, {
      'sidebar': const Rect.fromLTRB(0, 0, 236, 800),
      'toolbar': const Rect.fromLTRB(236, 0, 1200, 62),
      'breadcrumbs': const Rect.fromLTRB(236, 62, 1200, 108),
      'viewModeBar': const Rect.fromLTRB(236, 108, 1200, 148),
      'sortHeader': const Rect.fromLTRB(236, 148, 1200, 178),
      'entries': const Rect.fromLTRB(236, 178, 1200, 800),
    });
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
