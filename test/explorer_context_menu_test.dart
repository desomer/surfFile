import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/shell_menu_item.dart';
import 'package:surf_file/services/windows_context_menu.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/widgets/explorer/menus/explorer_context_menu.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';

void main() {
  final entry = ExplorerEntry(
    entity: File('C:\\example.txt'),
    name: 'example.txt',
    isDirectory: false,
    modified: DateTime(2026),
    size: 123,
  );

  for (final gridView in [false, true]) {
    testWidgets('right click reaches the entry in grid=$gridView', (
      tester,
    ) async {
      ExplorerEntry? clicked;
      Offset? position;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
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

  testWidgets('custom popup handles disabled items, submenus and back', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(WindowsContextMenu.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'open') {
        return {
          'session': 7,
          'items': [
            {'id': 1, 'label': 'Ouvrir', 'default': true, 'verb': 'open'},
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
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
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    Future<void> mouseNavigation(int button, String label) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(label)),
        kind: PointerDeviceKind.mouse,
        buttons: button,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await mouseNavigation(kForwardMouseButton, 'Ouvrir');
    expect(find.text('Ouvrir avec'), findsOneWidget);
    expect(find.text('Extension dessinée'), findsNothing);
    expect(find.text('Afficher le menu Windows'), findsOneWidget);
    for (final item in tester.widgetList<PopupMenuItem<ShellMenuItem>>(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<ShellMenuItem>,
      ),
    )) {
      expect(item.height, 32);
    }
    final openItem = find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuItem<ShellMenuItem> && widget.value?.id == 1,
    );
    expect(tester.getSize(openItem).height, 32);
    expect(
      find.descendant(
        of: openItem,
        matching: find.byIcon(Icons.open_in_new_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Indisponible'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir avec'), findsOneWidget);
    await tester.tap(find.text('Ouvrir avec'));
    await tester.pumpAndSettle();
    expect(find.text('Bloc-notes'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuItem<ShellMenuItem> &&
                  widget.value?.id == -1,
            ),
          )
          .height,
      32,
    );
    await tester.tap(find.text('‹ Retour'));
    await tester.pumpAndSettle();
    await mouseNavigation(kForwardMouseButton, 'Indisponible');
    expect(find.text('Bloc-notes'), findsOneWidget);
    await mouseNavigation(kBackMouseButton, 'Bloc-notes');
    expect(find.text('Ouvrir avec'), findsOneWidget);
    await tester.tap(find.text('Ouvrir avec'));
    await tester.pumpAndSettle();
    await mouseNavigation(kForwardMouseButton, 'Bloc-notes');
    expect(find.text('Bloc-notes'), findsOneWidget);
    await tester.tap(find.text('Bloc-notes'));
    await tester.pumpAndSettle();
    expect(selected?.id, 8);
    expect(calls, ['open', 'submenu', 'submenu', 'close']);
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await mouseNavigation(kBackMouseButton, 'Indisponible');
    expect(find.text('Ouvrir avec'), findsNothing);
    expect(calls.last, 'close');
  });

  for (final gridView in [false, true]) {
    testWidgets(
      'ExplorerEntriesView mounts EditableSurface only on representative entries in grid=$gridView and opens style menu on secondary tap in edit mode',
      (tester) async {
        final entries = [
          for (var i = 0; i < 6; i++)
            ExplorerEntry(
              entity: File('C:\\file_$i.txt'),
              name: 'file_$i.txt',
              isDirectory: false,
              modified: DateTime(2026),
              size: 100 + i,
            ),
        ];
        final appearance = ValueNotifier(Appearance());
        final editMode = ValueNotifier(false);
        addTearDown(appearance.dispose);
        addTearDown(editMode.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editMode,
              child: MaterialApp(
                home: Scaffold(
                  body: ExplorerEntriesView(
                    entries: entries,
                    gridView: gridView,
                    selectedPath: 'C:\\file_1.txt',
                    onSelected: (_) {},
                    onOpen: (_) {},
                    onContextMenu: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Only 2 representative EditableSurface instances (first unselected + first selected).
        expect(find.byType(EditableSurface), findsNWidgets(2));

        editMode.value = true;
        await tester.pumpAndSettle();
        expect(find.byType(EditableSurface), findsNWidgets(2));

        // Right-clicking a non-representative entry (file_4.txt) still activates and opens the style menu.
        await tester.tap(
          find.text('file_4.txt'),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<EditorSlotState>), findsWidgets);
      },
    );
  }
}
