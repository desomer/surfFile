import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/layout_selection.dart';
import 'package:super_container_layout/widgets/style_edit_banner.dart';
import 'package:super_container_layout/widgets/super_container.dart';

void main() {
  Future<void> pump(WidgetTester tester, ValueNotifier<bool> editMode) =>
      tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            builder: (context, child) => Stack(
              children: [
                child!,
                const Positioned.fill(child: StyleEditBanner()),
              ],
            ),
            home: const Scaffold(),
          ),
        ),
      );

  Rect banner(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('style-edit-banner')));

  Future<void> move(WidgetTester tester, Offset delta) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('style-edit-banner-drag'))),
    );
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveBy(delta);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('banner moves and retains its position when editing is toggled', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode);
    final initial = banner(tester);
    expect(initial.center.dx, 400);
    expect(initial.top, 8);
    await move(tester, const Offset(100, 80));
    final moved = banner(tester);
    expect(moved.left, closeTo(initial.left + 100, 1));
    expect(moved.top, greaterThan(initial.top + 70));

    await tester.tap(find.byKey(const ValueKey('style-edit-banner-close')));
    await tester.pump();
    expect(mode.value, isFalse);
    expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
    mode.value = true;
    await tester.pump();
    expect(banner(tester), moved);
    await move(tester, const Offset(-50, 30));
    expect(banner(tester).left, closeTo(moved.left - 50, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging is bounded and immediately reverses at the edges', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode);
    await move(tester, const Offset(-2000, -2000));
    expect(banner(tester).topLeft, Offset.zero);
    await move(tester, const Offset(30, 30));
    expect(banner(tester).left, 30);
    expect(banner(tester).top, greaterThan(0));
    await move(tester, const Offset(2000, 2000));
    expect(banner(tester).right, 800);
    expect(banner(tester).bottom, 600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consecutive pointer events accumulate before the next frame', (tester) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode);
    final initial = banner(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('style-edit-banner-drag'))),
    );
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    final start = banner(tester);
    await gesture.moveBy(const Offset(20, 10));
    await gesture.moveBy(const Offset(30, 15));
    await tester.pump();
    await gesture.up();
    expect(banner(tester).left, initial.left + 50);
    expect(banner(tester).top, start.top + 25);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing keeps the banner in the viewport', (tester) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    addTearDown(tester.view.reset);
    await pump(tester, mode);
    await move(tester, const Offset(2000, 2000));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 240);
    await tester.pumpAndSettle();
    expect(banner(tester).left, greaterThanOrEqualTo(0));
    expect(banner(tester).top, greaterThanOrEqualTo(0));
    expect(banner(tester).right, lessThanOrEqualTo(360));
    expect(banner(tester).bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a growing path stays bounded and its segments remain clickable',
    (tester) async {
      final mode = ValueNotifier(true);
      final owner = Object();
      addTearDown(mode.dispose);
      addTearDown(tester.view.reset);
      addTearDown(() => LayoutSelection.report(owner, const []));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 240);
      await pump(tester, mode);
      await move(tester, const Offset(1000, 1000));
      var cleared = false;
      LayoutSelection.report(owner, [
        'Disposition avec un titre tres long',
        'Nord',
      ], clear: () => cleared = true);
      await tester.pumpAndSettle();
      expect(banner(tester).right, lessThanOrEqualTo(360));
      expect(banner(tester).bottom, lessThanOrEqualTo(240));
      final segment = find.byKey(const ValueKey('style-edit-banner-path-1'));
      await tester.ensureVisible(segment);
      await tester.tap(segment);
      await tester.pump();
      expect(cleared, isTrue);
      await move(tester, const Offset(-20, -20));
      expect(banner(tester).left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    },
  );
}
