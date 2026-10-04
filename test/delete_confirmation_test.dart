import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/pages/explorer_page.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/widgets/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer_sidebar.dart';

void main() {
  testWidgets('deleting asks for confirmation first', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('surf_file_delete_');
    final file = File('${root.path}\\a.txt')..writeAsStringSync('a');
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

    // Les E/S réelles avancent par étapes : attente réelle puis pump.
    Future<void> settleIo() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(const MaterialApp(home: ExplorerPage()));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ExplorerEntriesView).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(seconds: 1));
    // La page démarre dans le dossier personnel réel : on va d'abord dans le
    // dossier temporaire (« Documents » y pointe) avant toute suppression.
    await tester.tap(
      find.descendant(
        of: find.byType(ExplorerSidebar),
        matching: find.text('Documents'),
      ),
    );
    await settleIo();
    expect(
      tester.widget<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs)).path,
      root.path,
    );
    await tester.tap(find.text('a.txt'));
    await tester.pump(const Duration(milliseconds: 400));
    final dialog = find.byKey(const ValueKey('delete-confirm'));
    expect(dialog, findsNothing);

    // Suppr : confirmation avant la corbeille.
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump(const Duration(milliseconds: 400));
    expect(dialog, findsOneWidget);
    expect(find.text('Mettre à la corbeille ?'), findsOneWidget);
    expect(find.text('« a.txt » sera envoyé à la corbeille.'), findsOneWidget);

    // Entrée ne confirme pas : le focus initial est sur Annuler.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));
    expect(dialog, findsNothing);
    expect(file.existsSync(), isTrue);

    // Maj + Suppr : suppression définitive, annulée puis confirmée.
    Future<void> shiftDelete() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 400));
    }

    await shiftDelete();
    expect(find.text('Supprimer définitivement ?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(dialog, findsNothing);
    expect(file.existsSync(), isTrue);

    await shiftDelete();
    await tester.tap(find.byKey(const ValueKey('delete-accept')));
    await settleIo();
    expect(dialog, findsNothing);
    expect(file.existsSync(), isFalse);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
