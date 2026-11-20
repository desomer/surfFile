import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('sandboxed-app-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileAppearanceStore', () {
    test('returns defaults when missing and persists round-trip to file', () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}appearance.json',
      );
      final store = FileAppearanceStore(file);

      final initial = await store.load();
      expect(initial.mode, ThemeMode.light);
      expect(await file.exists(), isFalse);

      final updated = initial.copyWith(
        mode: ThemeMode.dark,
        accent: const Color(0xFF123456),
      );
      await store.save(updated);
      expect(await file.exists(), isTrue);

      final reloaded = await store.load();
      expect(reloaded.mode, ThemeMode.dark);
      expect(reloaded.accent, const Color(0xFF123456));
    });
  });

  group('SandboxedApplicationStore', () {
    test('creates empty and cloned applications with isolated files', () async {
      final appStore = SandboxedApplicationStore();
      final appADir = Directory('${tempDir.path}${Platform.pathSeparator}app_a');
      final manifestA = await appStore.createApplication(
        appADir,
        name: 'Alpha App',
      );

      expect(manifestA.name, 'Alpha App');
      expect(SandboxedApplicationStore.manifestFileFor(appADir).existsSync(), isTrue);
      expect(
        SandboxedApplicationStore.repositoriesDirectoryFor(appADir).existsSync(),
        isTrue,
      );

      final appearanceStoreA = SandboxedApplicationStore.appearanceStoreFor(appADir);
      await appearanceStoreA.save(
        const AppearanceCodec().defaults.copyWith(mode: ThemeMode.dark),
      );

      const ordersId = '00000000000000000000000000000001';
      final repoStoreA = SandboxedApplicationStore.repositoryStoreFor(appADir);
      addTearDown(repoStoreA.dispose);
      await repoStoreA.createWithId(
        'orders',
        id: ordersId,
        initialDocument: {'count': 42},
      );

      final appBDir = Directory('${tempDir.path}${Platform.pathSeparator}app_b');
      final manifestB = await appStore.createApplication(
        appBDir,
        name: 'Beta Clone',
        cloneFromDirectory: appADir,
      );
      expect(manifestB.name, 'Beta Clone');

      final clonedAppearance = await SandboxedApplicationStore.appearanceStoreFor(
        appBDir,
      ).load();
      expect(clonedAppearance.mode, ThemeMode.dark);

      final repoStoreB = SandboxedApplicationStore.repositoryStoreFor(appBDir);
      addTearDown(repoStoreB.dispose);
      expect(
        (await repoStoreB.readAttribute(
          const JsonTextBinding(repositoryId: ordersId, path: 'count'),
        )).value,
        42,
      );

      await repoStoreB.writeAttribute(
        const JsonTextBinding(repositoryId: ordersId, path: 'count'),
        '99',
        expectedValue: 42,
      );
      expect(
        (await repoStoreA.readAttribute(
          const JsonTextBinding(repositoryId: ordersId, path: 'count'),
        )).value,
        42,
      );

      final recent = await appStore.loadRecentApplications();
      expect(recent.map((e) => e.name), ['Beta Clone', 'Alpha App']);
      expect(
        SandboxedApplicationStore.samePath(
          (await appStore.loadActiveApplicationPath())!,
          appBDir.path,
        ),
        isTrue,
      );
    });

    test('protects non-empty unrelated directories unless confirmed', () async {
      final appStore = SandboxedApplicationStore();
      final otherDir = Directory('${tempDir.path}${Platform.pathSeparator}other')
        ..createSync(recursive: true);
      File('${otherDir.path}${Platform.pathSeparator}notes.txt')
          .writeAsStringSync('keep me');

      await expectLater(
        () => appStore.openApplication(otherDir),
        throwsA(isA<NonEmptyNonAppDirectoryException>()),
      );

      final manifest = await appStore.openApplication(
        otherDir,
        initializeNonEmpty: true,
      );
      expect(manifest.name, 'other');
      expect(
        File('${otherDir.path}${Platform.pathSeparator}notes.txt').existsSync(),
        isTrue,
      );
      expect(
        SandboxedApplicationStore.manifestFileFor(otherDir).existsSync(),
        isTrue,
      );
    });

    test('removes recent entries without deleting files on disk', () async {
      final appStore = SandboxedApplicationStore();
      final appDir = Directory('${tempDir.path}${Platform.pathSeparator}kept');
      await appStore.createApplication(appDir, name: 'Kept');

      final afterRemove = await appStore.removeRecentApplication(appDir.path);
      expect(afterRemove, isEmpty);
      expect(appDir.existsSync(), isTrue);
      expect(
        jsonDecode(
          SandboxedApplicationStore.manifestFileFor(appDir).readAsStringSync(),
        )['name'],
        'Kept',
      );
    });
  });
}
