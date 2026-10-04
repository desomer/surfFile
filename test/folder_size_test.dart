import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/services/folder_size_service.dart';
import 'package:surf_file/widgets/folder_size_cell.dart';
import 'package:surf_file/widgets/folder_size_indicator.dart';
import 'package:surf_file/widgets/transfer_panel.dart';

void main() {
  late Directory root;

  setUp(() {
    FolderSizeService.reset();
    root = Directory.systemTemp.createTempSync('folder_size_');
    File('${root.path}/a.bin').writeAsBytesSync(List.filled(100, 0));
    Directory('${root.path}/sub/deep').createSync(recursive: true);
    File('${root.path}/sub/b.bin').writeAsBytesSync(List.filled(50, 0));
    File('${root.path}/sub/deep/c.bin').writeAsBytesSync(List.filled(25, 0));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('folderSizeSync sums files recursively', () {
    expect(FolderSizeService.folderSizeSync(root.path), 175);
  });

  test(
    'publishes scanned bytes, files, folders and the current path',
    () async {
      final computation = FolderSizeService.compute(root.path);
      final job = FolderSizeService.jobs.value.single;
      final reports = <FolderSizeProgress>[];
      job.addListener(() => reports.add(job.latest));
      expect(job.status, FolderSizeJobStatus.running);
      expect(await computation, isTrue);
      expect(job.status, FolderSizeJobStatus.done);
      expect(job.latest.bytes, 175);
      expect(job.latest.files, 3);
      expect(job.latest.folders, 3);
      expect(job.latest.skipped, 0);
      expect(job.latest.currentPath, endsWith('c.bin'));
      expect(reports, isNotEmpty);
      expect(FolderSizeService.bytesOf(root.path), 175);
      FolderSizeService.dismiss(job);
      expect(FolderSizeService.jobs.value, isEmpty);
    },
  );

  test('failed scans expose the error without caching a zero size', () async {
    final missing = '${root.path}${Platform.pathSeparator}missing';
    expect(await FolderSizeService.compute(missing), isFalse);
    final job = FolderSizeService.jobs.value.single;
    expect(job.status, FolderSizeJobStatus.failed);
    expect(job.error, contains(missing));
    expect(FolderSizeService.of(missing).value.computing, isFalse);
    expect(FolderSizeService.bytesOf(missing), isNull);
  });

  test('cancellation restores a previously computed size', () async {
    await FolderSizeService.compute(root.path);
    final computation = FolderSizeService.compute(root.path);
    final job = FolderSizeService.jobs.value.last;
    FolderSizeService.dismiss(job);
    expect(FolderSizeService.jobs.value, contains(job));
    expect(await FolderSizeService.compute(root.path), isFalse);
    expect(FolderSizeService.jobs.value.length, 1);
    job.cancel();
    expect(await computation, isFalse);
    expect(job.status, FolderSizeJobStatus.cancelled);
    expect(FolderSizeService.of(root.path).value.computing, isFalse);
    expect(FolderSizeService.bytesOf(root.path), 175);
  });

  testWidgets('size tracking uses the transfer panel and can be cancelled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Align(child: TransferPanel())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-size-card')), findsNothing);
    final computation = FolderSizeService.compute(root.path);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Calcul de taille'), findsOneWidget);
    expect(find.text('Total inconnu pendant le parcours'), findsOneWidget);
    expect(find.text('Parcours en cours · 0 o'), findsOneWidget);
    expect(find.text('0 fichiers · 0 dossiers'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('folder-size-current-path')))
          .data,
      root.path,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('folder-size-job-progress')),
          )
          .value,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('folder-size-job-cancel')));
    expect(
      FolderSizeService.jobs.value.single.status,
      FolderSizeJobStatus.cancelled,
      reason: 'The cancellation button must handle the tap before awaiting.',
    );
    await computation;
    await tester.pump();
    expect(find.text('Calcul annulé · 0 o'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-size-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-size-card')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  testWidgets('batch calculations display their results in the panel', (
    tester,
  ) async {
    final empty = Directory('${root.path}${Platform.pathSeparator}empty')
      ..createSync();
    await tester.runAsync(
      () => FolderSizeService.computeAll([root.path, empty.path]),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Align(child: TransferPanel())),
      ),
    );
    expect(find.byKey(const ValueKey('folder-size-card')), findsOneWidget);
    expect(find.text('Calcul terminé · 175 o'), findsOneWidget);
    expect(find.text('2 / 2 dossiers terminés'), findsOneWidget);
    expect(find.text('3 fichiers · 5 dossiers'), findsOneWidget);
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byKey(const ValueKey('folder-size-job-progress')),
          )
          .map((indicator) => indicator.value),
      [1],
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one cumulative popup cancels running and queued folders', (
    tester,
  ) async {
    final paths = [
      for (var i = 0; i < 6; i++)
        (Directory(
          '${root.path}${Platform.pathSeparator}batch_$i',
        )..createSync()).path,
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Align(child: TransferPanel())),
      ),
    );
    await tester.pumpAndSettle();
    final computation = FolderSizeService.computeAll(paths, concurrency: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('folder-size-card')), findsOneWidget);
    expect(find.text('0 / 6 dossiers terminés'), findsOneWidget);
    expect(find.text('2 calculs simultanés'), findsOneWidget);
    expect(FolderSizeService.queued.value, 4);
    await tester.tap(find.byKey(const ValueKey('folder-size-job-cancel')));
    expect(
      FolderSizeService.jobs.value.map((job) => job.status),
      everyElement(FolderSizeJobStatus.cancelled),
      reason: 'The cancellation button must handle the tap before awaiting.',
    );
    await computation;
    await tester.pump();
    expect(FolderSizeService.queued.value, 0);
    expect(FolderSizeService.jobs.value.length, 2);
    expect(
      FolderSizeService.jobs.value.map((job) => job.status),
      everyElement(FolderSizeJobStatus.cancelled),
    );
    expect(paths.map(FolderSizeService.bytesOf), everyElement(isNull));
    expect(find.text('2 calculs annulés'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-size-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-size-card')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  test('size sort orders folders by computed size numerically', () async {
    final dirs = [
      for (final name in ['big', 'small', 'unknown'])
        Directory('${root.path}/s_$name')..createSync(),
    ];
    File('${dirs[0].path}/f').writeAsBytesSync(List.filled(1000, 0));
    File('${dirs[1].path}/f').writeAsBytesSync(List.filled(90, 0));
    await FolderSizeService.compute(dirs[0].path);
    await FolderSizeService.compute(dirs[1].path);
    final entries = [
      for (final d in dirs)
        ExplorerEntry(
          entity: d,
          name: d.path.split(RegExp(r'[\\/]')).last,
          isDirectory: true,
          modified: DateTime(2020),
          size: 0,
        ),
    ];
    sortExplorerEntries(entries, ExplorerSort.size, ascending: true);
    expect(entries.map((e) => e.name), ['s_unknown', 's_small', 's_big']);
    sortExplorerEntries(entries, ExplorerSort.size, ascending: false);
    expect(entries.map((e) => e.name), ['s_big', 's_small', 's_unknown']);
  });

  testWidgets('shows the chosen size indicator, relative to the biggest', (
    tester,
  ) async {
    final a = Directory('${root.path}/ia')..createSync();
    final b = Directory('${root.path}/ib')..createSync();
    File('${a.path}/f').writeAsBytesSync(List.filled(100, 0));
    File('${b.path}/f').writeAsBytesSync(List.filled(25, 0));
    await tester.runAsync(() async {
      await FolderSizeService.compute(a.path);
      await FolderSizeService.compute(b.path);
    });
    List<int> sizes() => [100, 25, 50];
    expect(FolderSizeIndicator.ratio(25, sizes()), .25);
    expect(FolderSizeIndicator.ratio(null, sizes()), isNull);
    addTearDown(() => FolderSizeIndicator.mode.value = FolderSizeDisplay.bar);

    Future<void> show(FolderSizeDisplay display) async {
      FolderSizeIndicator.mode.value = display;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const FolderSizeDisplayButton(),
                FolderSizeCell(
                  path: b.path,
                  style: const TextStyle(),
                  siblingFolders: () => [a.path, b.path],
                  siblingSizes: sizes,
                ),
                SizeGauge(
                  bytes: () => 50,
                  siblingSizes: sizes,
                  child: const Text('file'),
                ),
                SizedBox(
                  height: 30,
                  child: SizeRowBackground(
                    bytes: () => FolderSizeService.bytesOf(b.path),
                    siblingSizes: sizes,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await show(FolderSizeDisplay.bar);
    expect(find.byKey(const ValueKey('folder-size-bar')), findsNWidgets(2));
    await show(FolderSizeDisplay.dot);
    expect(find.byKey(const ValueKey('folder-size-dot')), findsNWidgets(2));
    await show(FolderSizeDisplay.pie);
    expect(find.byKey(const ValueKey('folder-size-pie')), findsNWidgets(2));
    await show(FolderSizeDisplay.background);
    expect(
      find.byKey(const ValueKey('folder-size-background')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('folder-size-bar')), findsNothing);
    await show(FolderSizeDisplay.none);
    expect(find.byKey(const ValueKey('folder-size-background')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('folder-size-display-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-size-display-pie')));
    await tester.pumpAndSettle();
    expect(FolderSizeIndicator.mode.value, FolderSizeDisplay.pie);
    expect(find.byKey(const ValueKey('folder-size-pie')), findsNWidgets(2));
  });

  testWidgets('hovering the progress shows a cross that cancels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderSizeCell(path: root.path, style: const TextStyle()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('folder-size-compute')));
    await tester.pump();
    expect(find.byKey(const ValueKey('folder-size-cancel')), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('folder-size-progress'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('folder-size-cancel')));
    await tester.pump();
    final state = FolderSizeService.of(root.path).value;
    expect(state.computing, isFalse);
    expect(state.bytes, isNull);
    expect(find.byKey(const ValueKey('folder-size-compute')), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(FolderSizeService.of(root.path).value.bytes, isNull);
  });

  testWidgets('tapping the calculator computes the size in an isolate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderSizeCell(path: root.path, style: const TextStyle()),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('folder-size-compute')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-size-compute')));
    await tester.pump();
    expect(find.byKey(const ValueKey('folder-size-progress')), findsOneWidget);
    for (
      var i = 0;
      i < 100 && FolderSizeService.of(root.path).value.computing;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(FolderSizeService.of(root.path).value.bytes, 175);
    expect(find.byKey(const ValueKey('folder-size-compute')), findsNothing);
    expect(find.text('175 o'), findsOneWidget);
  });

  testWidgets('offers to compute the other folders once done', (tester) async {
    final other = Directory('${root.path}/other')..createSync();
    File('${other.path}/d.bin').writeAsBytesSync(List.filled(10, 0));
    final sub = '${root.path}/sub';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderSizeCell(
            path: sub,
            style: const TextStyle(),
            siblingFolders: () => [sub, other.path],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('folder-size-compute')));
    await tester.pump();
    final dialog = find.byKey(const ValueKey('folder-size-others-dialog'));
    for (var i = 0; i < 100 && dialog.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(dialog, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-size-others-confirm')));
    await tester.pump();
    for (
      var i = 0;
      i < 100 && FolderSizeService.of(other.path).value.bytes == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(FolderSizeService.of(other.path).value.bytes, 10);
  });
}
