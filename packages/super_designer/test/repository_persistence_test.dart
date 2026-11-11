import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_designer/super_designer.dart';

void main() {
  const repositoryId = '0123456789abcdef0123456789abcdef';
  const sourceBinding = JsonTextBinding(
    repositoryId: repositoryId,
    path: 'source',
  );
  const sizeBinding = JsonTextBinding(
    repositoryId: repositoryId,
    path: 'estSize',
  );
  const titleBinding = JsonTextBinding(
    repositoryId: repositoryId,
    path: 'nodes[0].title',
  );
  const requiredBinding = JsonTextBinding(
    repositoryId: repositoryId,
    path: 'nodes[0].isRequired',
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
    await directory.delete(recursive: true);
  });

  Future<void> real(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 70));
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

  testWidgets('restores data and retains node edits after a YAML change', (
    tester,
  ) async {
    const source = 'User:\n  status: string(enum)\n  email: email';
    const updatedSource = '$source\n  age: int';
    const loadedSource =
        'Account:\n  status: string(enum)\n  email: email\n  age: int';
    var store = await mount(tester);

    await real(tester, () async {
      await store.writeAttribute(sourceBinding, source, expectedValue: '');
    });
    late String rootId;
    late String childId;
    await real(tester, () async {
      final nodes = await store.readArray(repositoryId, 'nodes');
      final root = nodes.single as Map<String, dynamic>;
      final children = root['children'] as List<dynamic>;
      rootId = root['id'] as String;
      childId = (children.first as Map<String, dynamic>)['id'] as String;
      await store.writeAttribute(
        titleBinding,
        'Utilisateur',
        expectedValue: null,
      );
      await store.writeAttribute(
        requiredBinding,
        'false',
        expectedValue: true,
        asBool: true,
      );
      await store.writeAttribute(sizeBinding, '0', expectedValue: 300);
      await store.saveRepository(repositoryId);
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    store = await mount(tester);
    await real(tester, () async {
      expect((await store.readAttribute(sourceBinding)).value, source);
      expect((await store.readAttribute(sizeBinding)).value, 0);
      expect((await store.readAttribute(titleBinding)).value, 'Utilisateur');
      expect((await store.readAttribute(requiredBinding)).value, isFalse);
      final nodes = await store.readArray(repositoryId, 'nodes');
      final root = nodes.single as Map<String, dynamic>;
      expect(root['id'], rootId);
      expect(
        ((root['children'] as List<dynamic>).first
            as Map<String, dynamic>)['id'],
        childId,
      );
      await store.writeAttribute(
        sourceBinding,
        updatedSource,
        expectedValue: source,
      );
    });
    await real(tester, () async {
      final nodes = await store.readArray(repositoryId, 'nodes');
      final root = nodes.single as Map<String, dynamic>;
      final children = root['children'] as List<dynamic>;
      expect(root['id'], rootId);
      expect(root['title'], 'Utilisateur');
      expect(root['isRequired'], isFalse);
      expect((children.first as Map<String, dynamic>)['id'], childId);
      expect(children, hasLength(3));
    });

    final file = File(
      '${directory.path}${Platform.pathSeparator}registered'
      '${Platform.pathSeparator}$repositoryId.json',
    );
    await real(tester, () async {
      final document =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final root =
          (document['nodes'] as List<dynamic>).single as Map<String, dynamic>;
      document['source'] = loadedSource;
      root['title'] = 'Rechargé';
      await file.writeAsString(jsonEncode(document));
      await store.loadRepository(repositoryId);
    });
    await real(tester, () async {
      expect((await store.readAttribute(sourceBinding)).value, loadedSource);
      expect((await store.readAttribute(titleBinding)).value, 'Rechargé');
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
      final document =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final root =
          (document['nodes'] as List<dynamic>).single as Map<String, dynamic>;
      expect(root['id'], rootId);
      expect(root['name'], 'User');
      expect(root['title'], 'Rechargé');
      expect(root['isRequired'], isFalse);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

  testWidgets('exit waits for validation triggered by the final save', (
    tester,
  ) async {
    final store = await mount(tester);
    var flushCount = 0;
    Future<void> lastDraft() async {
      if (++flushCount == 2) {
        await store.writeAttribute(
          sourceBinding,
          'User:\n  email: email',
          expectedValue: '',
        );
      }
    }

    store.addFlusher(lastDraft);
    await tester.runAsync(() async {
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
      final nodes = await store.readArray(repositoryId, 'nodes');
      expect((nodes.single as Map<String, dynamic>)['name'], 'User');
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$repositoryId.json',
      );
      final document =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect((document['nodes'] as List<dynamic>), hasLength(1));
    });
    store.removeFlusher(lastDraft);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the default widget keeps its repository in memory', (
    tester,
  ) async {
    await real(tester, () async {
      await tester.pumpWidget(SuperDesignerApp(repositoryDirectory: directory));
    });
    final store = tester
        .widget<SuperApp>(find.byType(SuperApp))
        .repositoryStore!;
    final file = File(
      '${directory.path}${Platform.pathSeparator}registered'
      '${Platform.pathSeparator}$repositoryId.json',
    );
    await real(tester, () async {
      await store.writeAttribute(sizeBinding, '0', expectedValue: 300);
      expect(await file.exists(), isFalse);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reports a corrupt saved repository without replacing it', (
    tester,
  ) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}registered'
      '${Platform.pathSeparator}$repositoryId.json',
    );
    await real(tester, () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('{invalid');
      await tester.pumpWidget(
        SuperDesignerApp(
          persistRepository: true,
          repositoryDirectory: directory,
        ),
      );
    });
    expect(
      find.textContaining('Impossible de charger le repository'),
      findsOneWidget,
    );
    await real(tester, () async {
      expect(await file.readAsString(), '{invalid');
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
