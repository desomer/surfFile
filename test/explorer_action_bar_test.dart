import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/widgets/explorer_action_bar.dart';
import 'package:surf_file/widgets/explorer_view_mode_bar.dart';

void main() {
  group('ExplorerActionBar', () {
    List<ExplorerBarAction> actions(List<String> log, {bool enabled = true}) =>
        [
          ExplorerBarAction(
            id: 'copy',
            icon: Icons.content_copy_rounded,
            label: 'Copier',
            shortcut: 'Ctrl+C',
            onPressed: enabled ? () => log.add('copy') : null,
          ),
          ExplorerBarAction(
            id: 'delete',
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer',
            destructive: true,
            separatorBefore: true,
            onPressed: () => log.add('delete'),
          ),
        ];

    Future<void> pump(
      WidgetTester tester,
      List<ExplorerBarAction> actions, {
      bool compact = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplorerActionBar(actions: actions, compact: compact),
        ),
      ),
    );

    testWidgets('buttons call their action; disabled ones do nothing', (
      tester,
    ) async {
      final log = <String>[];
      await pump(tester, actions(log, enabled: false));
      await tester.tap(find.byKey(const ValueKey('action-copy')));
      await tester.tap(find.byKey(const ValueKey('action-delete')));
      expect(log, ['delete']);
      await pump(tester, actions(log));
      await tester.tap(find.byKey(const ValueKey('action-copy')));
      expect(log, ['delete', 'copy']);
    });

    testWidgets('compact mode groups the actions in a menu', (tester) async {
      final log = <String>[];
      await pump(tester, actions(log), compact: true);
      expect(find.byKey(const ValueKey('action-copy')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('actions-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-delete')));
      await tester.pumpAndSettle();
      expect(log, ['delete']);
    });
  });

  testWidgets('the view mode bar shows the actions on the left', (
    tester,
  ) async {
    final log = <String>[];
    Future<void> pumpBar(double width) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ExplorerViewModeBar(
                title: 'Dossier',
                itemCount: 2,
                gridView: false,
                onGridViewChanged: (_) {},
                actions: [
                  ExplorerBarAction(
                    id: 'copy',
                    icon: Icons.content_copy_rounded,
                    label: 'Copier',
                    onPressed: () => log.add('copy'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await pumpBar(1000);
    final button = find.byKey(const ValueKey('action-copy'));
    expect(
      tester.getTopLeft(button).dx,
      lessThan(tester.getTopLeft(find.text('Dossier')).dx),
    );
    await tester.tap(button);
    expect(log, ['copy']);

    await pumpBar(500);
    expect(button, findsNothing);
    expect(find.byKey(const ValueKey('actions-menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
