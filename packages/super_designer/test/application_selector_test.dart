import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_designer/main.dart';

void main() {
  final channels = [
    const MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];
  late Directory tempRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('designer-app-switch-');
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
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<void> pumpReal(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    await tester.runAsync(() async {
      await action();
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'FloatingAppearanceToolbar apps button creates, clones and hot-switches sandboxed apps while keeping design_systems global',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final appADir = Directory('${tempRoot.path}${Platform.pathSeparator}app_a');
      final appBDir = Directory('${tempRoot.path}${Platform.pathSeparator}app_b');
      final appCDir = Directory('${tempRoot.path}${Platform.pathSeparator}app_c');

      await pumpReal(tester, () async {
        await tester.pumpWidget(
          SuperDesignerApp(
            persistRepository: true,
            applicationDirectory: appADir,
          ),
        );
      });

      final appsButton = find.byKey(const ValueKey('appearance-applications'));
      expect(appsButton, findsOneWidget);
      expect(find.byIcon(Icons.apps), findsOneWidget);

      // Vérifie que design_systems reste pointé sur le magasin global.
      final superAppA = tester.widget<SuperApp>(find.byType(SuperApp));
      expect(
        superAppA.customDesignSystemStore?.directory.path,
        CustomDesignSystemStore.tryDefaultStore()?.directory.path,
      );

      const customRepoId = '00000000000000000000000000000002';

      // Modifie l'apparence et le repository de l'application A.
      final contextA = tester.element(find.byType(SuperPage));
      AppearanceScope.controllerOf(contextA)!.value =
          AppearanceScope.of(contextA).copyWith(mode: ThemeMode.dark);
      await pumpReal(tester, () async {
        await superAppA.repositoryStore!.writeAttribute(
          const JsonTextBinding(
            repositoryId: 'pan_model_repository',
            path: 'estSize',
          ),
          '420',
          expectedValue: 300,
        );
        await superAppA.repositoryStore!.createWithId(
          'custom_data',
          id: customRepoId,
          initialDocument: {'label': 'From A'},
        );
      });

      // Ouvre le sélecteur et clone l'application A vers l'application B.
      await tester.tap(appsButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('application-selector-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('application-selector-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('application-create-name-input')),
        'App B',
      );
      await tester.enterText(
        find.byKey(const ValueKey('application-create-path-input')),
        appBDir.path,
      );
      await pumpReal(tester, () async {
        await tester.tap(
          find.byKey(const ValueKey('application-create-submit')),
        );
      });

      // Vérifie que App B a bien cloné l'apparence et les repositories de App A.
      final contextB = tester.element(find.byType(SuperPage));
      expect(AppearanceScope.of(contextB).mode, ThemeMode.dark);
      final superAppB = tester.widget<SuperApp>(find.byType(SuperApp));
      await tester.runAsync(() async {
        expect(
          (await superAppB.repositoryStore!.readAttribute(
            const JsonTextBinding(
              repositoryId: 'pan_model_repository',
              path: 'estSize',
            ),
          )).value,
          420,
        );
        expect(
          (await superAppB.repositoryStore!.readAttribute(
            const JsonTextBinding(
              repositoryId: customRepoId,
              path: 'label',
            ),
          )).value,
          'From A',
        );
      });

      // Modifie App B : App A ne doit pas être impactée.
      AppearanceScope.controllerOf(contextB)!.value =
          AppearanceScope.of(contextB).copyWith(mode: ThemeMode.light);
      await pumpReal(tester, () async {
        await superAppB.repositoryStore!.writeAttribute(
          const JsonTextBinding(
            repositoryId: customRepoId,
            path: 'label',
          ),
          'Only B',
          expectedValue: 'From A',
        );
      });

      // Crée App C vide.
      await tester.tap(find.byKey(const ValueKey('appearance-applications')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('application-selector-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('application-create-name-input')),
        'App C',
      );
      await tester.enterText(
        find.byKey(const ValueKey('application-create-path-input')),
        appCDir.path,
      );
      await tester.tap(find.text('Application vide'));
      await tester.pumpAndSettle();
      await pumpReal(tester, () async {
        await tester.tap(
          find.byKey(const ValueKey('application-create-submit')),
        );
      });

      final contextC = tester.element(find.byType(SuperPage));
      expect(AppearanceScope.of(contextC).mode, ThemeMode.light);
      final superAppC = tester.widget<SuperApp>(find.byType(SuperApp));
      expect(
        superAppC.customDesignSystemStore?.directory.path,
        CustomDesignSystemStore.tryDefaultStore()?.directory.path,
      );
      await tester.runAsync(() async {
        expect(
          (await superAppC.repositoryStore!.readAttribute(
            const JsonTextBinding(
              repositoryId: 'pan_model_repository',
              path: 'estSize',
            ),
          )).value,
          300,
        );
        expect(
          (await superAppC.repositoryStore!.catalog()).any(
            (entry) => entry.id == customRepoId,
          ),
          isFalse,
        );
      });

      // Rebascule sur App A via les récentes et vérifie l'isolation.
      await tester.tap(find.byKey(const ValueKey('appearance-applications')));
      await tester.pumpAndSettle();
      await pumpReal(tester, () async {
        await tester.tap(find.text('app_a').last);
      });

      final contextBackA = tester.element(find.byType(SuperPage));
      expect(AppearanceScope.of(contextBackA).mode, ThemeMode.dark);
      final superAppBackA = tester.widget<SuperApp>(find.byType(SuperApp));
      await tester.runAsync(() async {
        expect(
          (await superAppBackA.repositoryStore!.readAttribute(
            const JsonTextBinding(
              repositoryId: customRepoId,
              path: 'label',
            ),
          )).value,
          'From A',
        );
      });

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
