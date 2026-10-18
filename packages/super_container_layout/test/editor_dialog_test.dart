import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/editing/editor_dialog.dart';
import 'package:super_container_layout/widgets/editing/editor_overlay.dart';
import 'package:super_container_layout/widgets/editing/editor_zoom.dart';
import 'package:super_container_layout/widgets/surfaces/super_container.dart';

void main() {
  for (final zoomed in [false, true]) {
    testWidgets(
      'editor hides editing controls and restores them after nested dialogs (zoom=$zoomed)',
      (tester) async {
        final target = GlobalKey();
        final label = GlobalKey();
        final content = SizedBox(
          key: target,
          width: 240,
          height: 160,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.blue)),
              Positioned.fill(
                child: EditorOverlay(
                  child: Center(child: Text('Zone label', key: label)),
                ),
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: zoomed ? EditorZoom(child: content) : content,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Visibility visibility() => tester
            .widgetList<Visibility>(
              find.ancestor(
                of: find.byKey(label),
                matching: find.byType(Visibility),
              ),
            )
            .first;
        final before = tester.getSize(find.byKey(target));
        expect(visibility().visible, isTrue);
        final editor = showEditorDialog<void>(
          context: target.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Parent editor'),
            actions: [
              TextButton(
                onPressed: () => showEditorDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Nested editor'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close nested'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open nested'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close parent'),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(EditorOverlayVisibility.openDialogs.value, 1);
        expect(visibility().visible, isFalse);
        expect(tester.getSize(find.byKey(target)), before);
        await tester.tap(find.text('Open nested'));
        await tester.pumpAndSettle();
        expect(EditorOverlayVisibility.openDialogs.value, 2);
        expect(visibility().visible, isFalse);
        await tester.tap(find.text('Close nested'));
        await tester.pumpAndSettle();
        expect(EditorOverlayVisibility.openDialogs.value, 1);
        expect(visibility().visible, isFalse);
        await tester.tap(find.text('Close parent'));
        await tester.pumpAndSettle();
        await editor;
        expect(EditorOverlayVisibility.openDialogs.value, 0);
        expect(visibility().visible, isTrue);
        expect(tester.getSize(find.byKey(target)), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  Rect screenRect(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  Future<GlobalKey> pumpPage(
    WidgetTester tester,
    Size screen,
    Size target, {
    ValueNotifier<Size>? liveSize,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    Widget content(Size size) => SizedBox(
      key: key,
      width: size.width,
      height: size.height,
      child: const ColoredBox(color: Colors.blue),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: EditorZoom(
              child: Align(
                alignment: Alignment.topLeft,
                child: liveSize == null
                    ? content(target)
                    : ValueListenableBuilder<Size>(
                        valueListenable: liveSize,
                        builder: (context, size, _) => content(size),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  Widget dialog(BuildContext context) => AlertDialog(
    title: const Text('Editor'),
    content: const SizedBox(width: 420, height: 120, child: Text('Controls')),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  testWidgets('dialog reserves space, allows zoom out and restores framing', (
    tester,
  ) async {
    final key = await pumpPage(
      tester,
      const Size(1200, 800),
      const Size(900, 600),
    );
    final target = find.byKey(key);
    final before = screenRect(tester, target);
    final result = showEditorDialog<void>(
      context: key.currentContext!,
      target: key.currentContext,
      builder: dialog,
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('editor-dialog-panel'));
    final bounds = screenRect(tester, panel);
    final framed = screenRect(tester, target);
    expect(bounds, const Rect.fromLTWH(640, 0, 560, 800));
    expect(framed.center, const Offset(320, 400));
    expect(framed.width, closeTo(448, .01));
    expect(framed.overlaps(bounds), isFalse);
    await tester.tap(find.byKey(const ValueKey('editor-dialog-side')));
    await tester.pumpAndSettle();
    expect(screenRect(tester, panel), const Rect.fromLTWH(0, 0, 560, 800));
    expect(screenRect(tester, target).center, const Offset(880, 400));
    expect(
      screenRect(tester, target).overlaps(screenRect(tester, panel)),
      isFalse,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await result;
    expect(screenRect(tester, target), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog docks below target on narrow screens and resizes live', (
    tester,
  ) async {
    final key = await pumpPage(
      tester,
      const Size(700, 800),
      const Size(600, 600),
    );
    final result = showEditorDialog<void>(
      context: key.currentContext!,
      target: key.currentContext,
      builder: dialog,
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('editor-dialog-panel'));
    final target = find.byKey(key);
    expect(screenRect(tester, panel), const Rect.fromLTWH(0, 384, 700, 416));
    expect(screenRect(tester, target).center, const Offset(350, 192));
    expect(
      screenRect(tester, target).overlaps(screenRect(tester, panel)),
      isFalse,
    );
    expect(find.byKey(const ValueKey('editor-dialog-side')), findsNothing);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(screenRect(tester, target).center, const Offset(320, 400));
    expect(
      screenRect(tester, target).overlaps(screenRect(tester, panel)),
      isFalse,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await result;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nested dialogs inherit target and restore parent occupied space',
    (tester) async {
      final key = await pumpPage(
        tester,
        const Size(1400, 900),
        const Size(900, 600),
      );
      final width = ValueNotifier(680.0);
      addTearDown(width.dispose);
      final result = showEditorDialog<void>(
        context: key.currentContext!,
        target: key.currentContext,
        preferredWidth: width,
        builder: (context) => AlertDialog(
          title: const Text('Parent'),
          content: const SizedBox(width: 1000, height: 120),
          actions: [
            TextButton(
              onPressed: () =>
                  showEditorDialog<void>(context: context, builder: dialog),
              child: const Text('Nested'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close parent'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(key);
      expect(screenRect(tester, target).center, const Offset(360, 450));
      width.value = 1080;
      await tester.pumpAndSettle();
      final parent = screenRect(tester, target);
      expect(parent.center.dx, closeTo(315, .001));
      expect(parent.center.dy, closeTo(450, .001));
      await tester.tap(find.text('Nested'));
      await tester.pumpAndSettle();
      expect(screenRect(tester, target).center, const Offset(420, 450));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), parent);
      await tester.tap(find.text('Close parent'));
      await tester.pumpAndSettle();
      await result;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('framing follows live target geometry without compounding zoom', (
    tester,
  ) async {
    final size = ValueNotifier(const Size(900, 600));
    addTearDown(size.dispose);
    final key = await pumpPage(
      tester,
      const Size(1200, 800),
      size.value,
      liveSize: size,
    );
    final result = showEditorDialog<void>(
      context: key.currentContext!,
      target: key.currentContext,
      builder: dialog,
    );
    await tester.pumpAndSettle();
    size.value = const Size(200, 600);
    await tester.pumpAndSettle();
    final target = screenRect(tester, find.byKey(key));
    expect(target.center, const Offset(320, 400));
    expect(target.height, closeTo(560, .001));
    expect(target.width, closeTo(560 / 3, .001));
    expect(
      target.overlaps(
        screenRect(tester, find.byKey(const ValueKey('editor-dialog-panel'))),
      ),
      isFalse,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await result;
    expect(
      screenRect(tester, find.byKey(key)),
      const Rect.fromLTWH(0, 0, 200, 600),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'style dialog frames edited container even without slot selection',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      final key = GlobalKey<SuperContainerState>();
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: EditorZoom(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 900,
                    height: 600,
                    child: SuperContainer(
                      key: key,
                      child: const Text('Style target'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final result = key.currentState!.openEditor();
      await tester.pumpAndSettle();
      final target = find.byKey(key);
      final panel = find.byKey(const ValueKey('editor-dialog-panel'));
      final complete = screenRect(tester, panel);
      expect(screenRect(tester, target).overlaps(complete), isFalse);
      await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
      await tester.pumpAndSettle();
      final dense = screenRect(tester, panel);
      expect(dense.width, 680);
      expect(dense.width, lessThan(complete.width));
      expect(screenRect(tester, target).center.dx, closeTo(360, .001));
      expect(screenRect(tester, target).overlaps(dense), isFalse);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await result;
      expect(tester.takeException(), isNull);
    },
  );
}
