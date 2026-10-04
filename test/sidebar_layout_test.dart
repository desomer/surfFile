import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/super_layout_config.dart';
import 'package:surf_file/services/disk_space.dart';
import 'package:surf_file/theme/appearance.dart';
import 'package:surf_file/widgets/explorer_sidebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const gib = 1024 * 1024 * 1024;
  setUp(
    () => messenger.setMockMethodCallHandler(
      DiskSpace.channel,
      (_) async => [
        for (final letter in 'CDEFGH'.split(''))
          {
            'path': '$letter:\\',
            'totalBytes': 100 * gib,
            'freeBytes': 50 * gib,
          },
      ],
    ),
  );
  tearDown(() => messenger.setMockMethodCallHandler(DiskSpace.channel, null));

  Future<void> pump(
    WidgetTester tester, {
    required double height,
    Appearance appearance = const Appearance(),
  }) async {
    final controller = ValueNotifier(appearance);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppearanceScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: height,
              child: ExplorerSidebar(
                locations: const [],
                currentPath: 'C:\\',
                onLocationSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect rect(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('places fill the centre and the disks sit at the south', (
    tester,
  ) async {
    await pump(tester, height: 700);
    final layout = rect(tester, 'sidebar-layout');
    final places = rect(tester, 'slot-fill-sidebar-places');
    final disks = rect(tester, 'slot-item-sidebar-disks');
    expect(places.top, layout.top);
    expect(disks.bottom, layout.bottom);
    expect(places.bottom, disks.top);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('sidebar-tab-0'))).dy,
      lessThan(tester.getTopLeft(find.text('C:\\')).dy),
    );
  });

  testWidgets('a short window keeps room for the places list', (tester) async {
    await pump(tester, height: 400);
    final layout = rect(tester, 'sidebar-layout');
    expect(
      rect(tester, 'slot-item-sidebar-disks').height,
      lessThanOrEqualTo(layout.height / 2),
    );
    expect(rect(tester, 'slot-fill-sidebar-places').height, greaterThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the layout comes from the appearance', (tester) async {
    await pump(
      tester,
      height: 700,
      appearance: Appearance(
        explorerSidebarLayout: Appearance.defaultExplorerSidebarLayout.withSwap(
          SuperLayoutZone.south,
        ),
      ),
    );
    final layout = rect(tester, 'sidebar-layout');
    expect(rect(tester, 'slot-item-sidebar-disks').top, layout.top);
    expect(rect(tester, 'slot-fill-sidebar-places').bottom, layout.bottom);
  });
}
