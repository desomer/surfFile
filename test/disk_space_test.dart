import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/services/disk_space.dart';
import 'package:surf_file/widgets/disk_space/disk_gauge.dart';
import 'package:surf_file/widgets/disk_space/disk_space_panel.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const gib = 1024 * 1024 * 1024;
  final disks = [
    {'path': 'C:\\', 'totalBytes': 100 * gib, 'freeBytes': 25 * gib},
    {'path': 'D:\\', 'totalBytes': 100 * gib, 'freeBytes': 5 * gib},
    {'path': 'E:\\', 'totalBytes': 100 * gib, 'freeBytes': 100 * gib},
    {'path': 'F:\\', 'error': 'No media'},
    {'path': 'G:\\', 'totalBytes': 100 * gib, 'freeBytes': 0},
  ];
  setUp(
      () => messenger.setMockMethodCallHandler(DiskSpace.channel, (call) async {
            expect(call.method, 'getDisks');
            return disks;
          }));
  tearDown(() => messenger.setMockMethodCallHandler(DiskSpace.channel, null));

  test('capacity reports real used fractions and unavailable media', () async {
    final values = await DiskSpace.load();
    expect(values.map((disk) => disk.usedFraction), [.75, .95, 0, null, 1]);
  });

  test('invalid capacity is rejected', () async {
    messenger.setMockMethodCallHandler(
        DiskSpace.channel,
        (_) async => [
              {'path': 'C:\\', 'totalBytes': 100, 'freeBytes': 101},
            ]);
    await expectLater(DiskSpace.load(), throwsFormatException);
  });

  testWidgets('two-column disk grid renders usage, free space and navigation',
      (tester) async {
    String? path;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SizedBox(
        width: 210,
        child: DiskSpacePanel(onNavigate: (value) => path = value),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('75 %'), findsOneWidget);
    expect(find.text('25.0 Gio libres'), findsOneWidget);
    expect(find.text('Indisponible'), findsOneWidget);
    final gauges =
        tester.widgetList<DiskGauge>(find.byType(DiskGauge)).toList();
    expect(gauges.map((gauge) => gauge.value), [.75, .95, 0, null, 1]);
    expect(gauges.map((gauge) => gauge.alert),
        [false, true, false, false, true]);
    expect(gauges[1].alertColor,
        Theme.of(tester.element(find.text('D:\\'))).colorScheme.error);
    final c = tester.getCenter(find.text('C:\\'));
    final d = tester.getCenter(find.text('D:\\'));
    final e = tester.getCenter(find.text('E:\\'));
    expect(c.dy, d.dy);
    expect(c.dx, e.dx);
    expect(e.dy, greaterThan(c.dy));
    await tester.tap(find.text('D:\\'));
    expect(path, 'D:\\');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failure is visible and refresh can recover', (tester) async {
    messenger.setMockMethodCallHandler(DiskSpace.channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SizedBox(width: 210, child: DiskSpacePanel(onNavigate: (_) {})),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de lire les disques.'), findsOneWidget);
    messenger.setMockMethodCallHandler(DiskSpace.channel, (_) async => disks);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('75 %'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sidebar scrolls to all disks in a short window', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SizedBox(
          height: 260,
          child: ExplorerSidebar(
            locations: const [],
            currentPath: 'C:\\',
            onLocationSelected: (_) {},
          )),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Vos fichiers, à portée de main.'), findsNothing);
    await tester.ensureVisible(find.text('G:\\'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
