import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/layout_reset_shortcut.dart';

void main() {
  group('LayoutResetShortcut', () {
    Future<List<int>> pump(WidgetTester tester) async {
      final resets = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LayoutResetShortcut(
            onReset: () => resets.add(resets.length),
            child: const Scaffold(body: TextField(autofocus: true)),
          ),
        ),
      );
      return resets;
    }

    testWidgets('Win + Escape resets, wherever the focus is', (tester) async {
      final resets = await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(resets, hasLength(1));
    });

    testWidgets('Escape alone and Ctrl + Escape do nothing', (tester) async {
      final resets = await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(resets, isEmpty);
    });

    testWidgets('the handler is removed with the widget', (tester) async {
      final resets = await pump(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(resets, isEmpty);
    });
  });

  test('resetLayouts restores every layout and keeps the other settings', () {
    final moved = Appearance(
      accent: const Color(0xFF00796B),
      explorerLayout: Appearance.defaultExplorerLayout.withSwap(
        SuperLayoutZone.west,
      ),
      explorerMainLayout: Appearance.defaultExplorerMainLayout.withSwap(
        SuperLayoutZone.north,
      ),
      explorerSidebarLayout: Appearance.defaultExplorerSidebarLayout.withSwap(
        SuperLayoutZone.south,
      ),
    );
    final reset = moved.resetLayouts();
    expect(reset.explorerLayout, Appearance.defaultExplorerLayout);
    expect(reset.explorerMainLayout, Appearance.defaultExplorerMainLayout);
    expect(
      reset.explorerSidebarLayout,
      Appearance.defaultExplorerSidebarLayout,
    );
    expect(
      reset.explorerSidebarLayout,
      Appearance.defaultExplorerSidebarLayout,
    );
    expect(reset.accent, moved.accent);
  });
}
