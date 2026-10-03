import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/shell_menu_item.dart';
import 'package:surf_file/services/windows_context_menu.dart';
import 'package:surf_file/widgets/explorer_context_menu.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';

void main() {
  final entry = ExplorerEntry(
    entity: File('C:\\example.txt'),
    name: 'example.txt',
    isDirectory: false,
    modified: DateTime(2026),
    size: 123,
  );

  for (final gridView in [false, true]) {
    testWidgets('right click reaches the entry in grid=$gridView',
        (tester) async {
      ExplorerEntry? clicked;
      Offset? position;
      var opened = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExplorerEntriesView(
            entries: [entry],
            gridView: gridView,
            selectedPath: null,
            onSelected: (_) {},
            onOpen: (_) => opened = true,
            onContextMenu: (entry, offset) {
              clicked = entry;
              position = offset;
            },
          ),
        ),
      ));
      final point = tester.getCenter(find.text('example.txt'));
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();
      expect(clicked, same(entry));
      expect(position, point);
      expect(opened, isFalse);
    });
  }

  testWidgets('custom popup handles disabled items, submenus and back',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(WindowsContextMenu.channel,
        (call) async {
      calls.add(call.method);
      if (call.method == 'open') {
        return {
          'session': 7,
          'items': [
            {'id': 1, 'label': 'Ouvrir', 'default': true},
            {'id': 2, 'label': 'Indisponible', 'enabled': false},
            {'id': 3, 'label': 'Ouvrir avec', 'submenu': 1},
            {'id': 4, 'label': 'Extension dessinée', 'nativeOnly': true},
          ],
        };
      }
      if (call.method == 'submenu') {
        return [
          {'id': 8, 'label': 'Bloc-notes'},
        ];
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(WindowsContextMenu.channel, null);
    });

    ShellMenuItem? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              final menu = await WindowsContextMenu.open(entry.entity.path);
              if (!context.mounted) return;
              try {
                selected = await ExplorerContextMenu.show(
                  context: context,
                  position: const Offset(100, 100),
                  menu: menu,
                );
              } finally {
                await menu.close();
              }
            },
            child: const Text('Menu'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Extension dessinée'), findsNothing);
    expect(find.text('Afficher le menu Windows'), findsOneWidget);
    await tester.tap(find.text('Indisponible'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir avec'), findsOneWidget);
    await tester.tap(find.text('Ouvrir avec'));
    await tester.pumpAndSettle();
    expect(find.text('Bloc-notes'), findsOneWidget);
    await tester.tap(find.text('‹ Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ouvrir avec'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloc-notes'));
    await tester.pumpAndSettle();
    expect(selected?.id, 8);
    expect(calls, ['open', 'submenu', 'submenu', 'close']);
  });
}
