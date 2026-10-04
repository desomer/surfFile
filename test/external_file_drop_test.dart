import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/services/external_drop_transfer.dart';
import 'package:surf_file/services/file_operations.dart';
import 'package:surf_file/services/windows_file_drop.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/services/folder_size_service.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer_heatmap_view.dart';
import 'package:surf_file/widgets/external_file_drop.dart';

Future<void> nativeEvent(String method, Object? arguments) async {
  final result = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        WindowsFileDrop.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (response) {
          if (response != null) {
            const StandardMethodCodec().decodeEnvelope(response);
          }
          result.complete();
        },
      );
  await result.future;
}

void main() {
  testWidgets('native coordinates select folders, background and split pane', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final drops = <(List<String>, String)>[];
    Widget pane(String path) => Expanded(
      child: ExternalFileDrop(
        path: path,
        enabled: true,
        onDrop: (sources, destination) => drops.add((sources, destination)),
        child: Column(
          children: [
            ExternalDropDestination(
              path: '$path\\folder',
              child: SizedBox(
                key: ValueKey('$path-folder'),
                height: 100,
                width: double.infinity,
                child: const Text('folder'),
              ),
            ),
            Expanded(
              child: SizedBox(
                key: ValueKey('$path-background'),
                width: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Row(children: [pane('left'), pane('right')])),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> drop(String key) async {
      final position = tester.getCenter(find.byKey(ValueKey(key))) * 2;
      await nativeEvent('entered', [position.dx, position.dy]);
      await tester.pump();
      await nativeEvent('drop', {
        'x': position.dx,
        'y': position.dy,
        'paths': [r'C:\outside\file.txt'],
      });
      await tester.pump();
    }

    await drop('left-folder');
    expect(drops.single.$2, r'left\folder');
    await drop('right-folder');
    expect(drops.last.$2, r'right\folder');
    await drop('right-background');
    expect(drops.last.$2, 'right');
    expect(drops.length, 3);
    expect(drops.first.$1, [r'C:\outside\file.txt']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled targets and modal dialogs ignore external drops', (
    tester,
  ) async {
    var count = 0;
    late BuildContext pageContext;
    var enabled = false;
    Widget page() => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            pageContext = context;
            return ExternalFileDrop(
              path: 'destination',
              enabled: enabled,
              onDrop: (_, _) => count++,
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
    Future<void> drop() async {
      await nativeEvent('entered', [100.0, 100.0]);
      await nativeEvent('drop', {
        'x': 100.0,
        'y': 100.0,
        'paths': [r'C:\file.txt'],
      });
    }

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await drop();
    expect(count, 0);
    enabled = true;
    await tester.pumpWidget(page());
    final dialog = showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(title: Text('Modal')),
    );
    await tester.pumpAndSettle();
    await drop();
    expect(count, 0);
    Navigator.of(pageContext).pop();
    await dialog;
    await tester.pumpAndSettle();
    await drop();
    expect(count, 1);
  });

  for (final mode in ['list', 'grid', 'heatmap']) {
    testWidgets('$mode drops target the folder rather than its parent', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('surf_drop_view_');
      final folder = Directory('${root.path}\\target')..createSync();
      File('${folder.path}\\content.txt').writeAsStringSync('content');
      addTearDown(() => root.deleteSync(recursive: true));
      addTearDown(FolderSizeService.reset);
      await tester.runAsync(() => FolderSizeService.compute(folder.path));
      final entries = [
        ExplorerEntry(
          entity: folder,
          name: 'target',
          isDirectory: true,
          modified: DateTime(2026),
          size: 0,
        ),
      ];
      String? destination;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExternalFileDrop(
              path: root.path,
              enabled: true,
              onDrop: (_, target) => destination = target,
              child: mode == 'heatmap'
                  ? ExplorerHeatmapView(
                      entries: entries,
                      selectedPaths: const {},
                      onOpen: (_) {},
                    )
                  : ExplorerEntriesView(
                      entries: entries,
                      gridView: mode == 'grid',
                      selectedPath: null,
                      onSelected: (_) {},
                      onOpen: (_) {},
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final point =
          tester.getCenter(find.text('target')) * tester.view.devicePixelRatio;
      await nativeEvent('entered', [point.dx, point.dy]);
      await tester.pump();
      await nativeEvent('drop', {
        'x': point.dx,
        'y': point.dy,
        'paths': [r'C:\outside.txt'],
      });
      expect(destination, folder.path);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  group('confirmation and transfers', () {
    late Directory root;
    late Directory destination;
    late File source;

    setUp(() {
      root = Directory.systemTemp.createTempSync('surf_drop_');
      destination = Directory('${root.path}\\destination')..createSync();
      source = File('${root.path}\\outside.txt')..writeAsStringSync('hello');
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<BuildContext> showPage(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return context;
    }

    for (final kind in FileTransfer.values) {
      testWidgets(
        '$kind starts only after confirmation and preserves content',
        (tester) async {
          final context = await showPage(tester);
          File('${destination.path}\\outside.txt')
              .writeAsStringSync('existing');
          final confirmation = ExternalDropTransfer.confirm(context, [
            source.path,
            source.path,
          ], destination.path);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('external-drop-dialog')),
            findsOneWidget,
          );
          expect(find.textContaining(destination.path), findsOneWidget);
          expect(source.existsSync(), isTrue);
          expect(
            File('${destination.path}\\outside (2).txt').existsSync(),
            isFalse,
          );
          expect(ExternalDropTransfer.prompting.value, isTrue);
          await tester.tap(
            find.byKey(
              ValueKey(
                kind == FileTransfer.copy
                    ? 'external-drop-copy'
                    : 'external-drop-move',
              ),
            ),
          );
          final job = await confirmation;
          expect(job, isNotNull);
          expect(job!.sources, [source.path]);
          for (var i = 0; i < 100 && !job.isDone; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(job.isDone, isTrue, reason: 'The transfer must finish.');
          expect(job.status, FileJobStatus.done);
          expect(source.existsSync(), kind == FileTransfer.copy);
          expect(
            File('${destination.path}\\outside (2).txt').readAsStringSync(),
            'hello',
          );
          expect(
            File('${destination.path}\\outside.txt').readAsStringSync(),
            'existing',
          );
          expect(ExternalDropTransfer.prompting.value, isFalse);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(FileJobs.keepFinished);
          FileJobs.dismiss(job);
        },
      );
    }

    testWidgets('cancel never modifies the source or destination', (
      tester,
    ) async {
      final context = await showPage(tester);
      final confirmation = ExternalDropTransfer.confirm(context, [
        source.path,
      ], destination.path);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      expect(await confirmation, isNull);
      expect(source.readAsStringSync(), 'hello');
      expect(destination.listSync(), isEmpty);
      expect(ExternalDropTransfer.prompting.value, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('rejects recursive drops and moves into the original folder', (
      tester,
    ) async {
      final context = await showPage(tester);
      await expectLater(
        ExternalDropTransfer.confirm(context, [root.path], destination.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(find.byKey(const ValueKey('external-drop-dialog')), findsNothing);
      final confirmation = ExternalDropTransfer.confirm(context, [
        source.path,
      ], root.path);
      final assertion = expectLater(
        confirmation,
        throwsA(isA<FileSystemException>()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('external-drop-move')));
      await assertion;
      expect(source.readAsStringSync(), 'hello');
      await tester.pumpAndSettle();
    });
  });
}
