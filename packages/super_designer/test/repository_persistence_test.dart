import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_designer/super_designer.dart';

void main() {
  const repositoryId = '00000000000000000000000000000001';
  const titleBinding = JsonTextBinding(
    repositoryId: repositoryId,
    path: 'title',
  );
  final channels = [
    const MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('designer-repository-');
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() async {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<void> real(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<JsonRepositoryStore> mount(WidgetTester tester) async {
    await real(tester, () async {
      await tester.pumpWidget(
        SuperDesignerApp(
          persistRepository: true,
          repositoryDirectory: directory,
        ),
      );
    });
    expect(find.byType(SuperApp), findsOneWidget);
    return tester.widget<SuperApp>(find.byType(SuperApp)).repositoryStore!;
  }

  testWidgets(
    'persists JSON repositories across restarts and flushes on exit',
    (tester) async {
      var store = await mount(tester);

      await real(tester, () async {
        await store.createWithId(
          'project_data',
          id: repositoryId,
          initialDocument: {'title': 'Initial'},
        );
        await store.writeAttribute(
          titleBinding,
          'Mis à jour',
          expectedValue: 'Initial',
        );
      });

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      store = await mount(tester);
      await real(tester, () async {
        expect((await store.readAttribute(titleBinding)).value, 'Mis à jour');
      });

      var flushedOnExit = false;
      Future<void> exitFlusher() async {
        if (flushedOnExit) return;
        flushedOnExit = true;
        await store.writeAttribute(
          titleBinding,
          'Sauvegardé à la fermeture',
          expectedValue: 'Mis à jour',
        );
      }

      store.addFlusher(exitFlusher);
      await tester.runAsync(() async {
        expect(
          await tester.binding.handleRequestAppExit(),
          AppExitResponse.exit,
        );
        expect(flushedOnExit, isTrue);
        expect(
          (await store.readAttribute(titleBinding)).value,
          'Sauvegardé à la fermeture',
        );
      });
      store.removeFlusher(exitFlusher);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a failed pending draft prevents a successful exit', (
    tester,
  ) async {
    final store = await mount(tester);
    Future<void> failedDraft() async {}
    store.addFlusher(
      failedDraft,
      pendingError: () => 'Une saisie ne peut pas être enregistrée.',
    );
    AppExitResponse? response;
    await tester.runAsync(() async {
      response = await tester.binding.handleRequestAppExit();
      expect(tester.takeException(), isA<FormatException>());
    });
    expect(response, AppExitResponse.cancel);
    store.removeFlusher(failedDraft);
    await tester.runAsync(() async {
      response = await tester.binding.handleRequestAppExit();
    });
    expect(response, AppExitResponse.exit);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reports an invalid applicationDirectory target without overwriting it',
    (tester) async {
      final notADir = File(
        '${directory.path}${Platform.pathSeparator}not_a_directory.json',
      );
      await real(tester, () async {
        await notADir.writeAsString('{keep-me}');
        await tester.pumpWidget(
          SuperDesignerApp(
            persistRepository: true,
            applicationDirectory: Directory(notADir.path),
          ),
        );
      });
      expect(
        find.textContaining('Impossible d’initialiser l’application'),
        findsOneWidget,
      );
      await real(tester, () async {
        expect(await notADir.readAsString(), '{keep-me}');
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
