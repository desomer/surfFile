import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/main.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  const toolbarKey = ValueKey('appearance-toolbar');
  const dragKey = ValueKey('appearance-toolbar-drag');
  final channels = [
    const MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const TestApp());
    await tester.pumpAndSettle();
  }

  Rect toolbar(WidgetTester tester) => tester.getRect(find.byKey(toolbarKey));

  Future<void> move(WidgetTester tester, Offset delta) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragKey)),
    );
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(delta);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('six-dot handle precedes working appearance actions', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byIcon(Icons.drag_indicator), findsWidgets);
    final handle = tester.getRect(find.byKey(dragKey));
    final edit = find.byKey(const ValueKey('style-edit-mode'));
    final editMode = StyleEditScope.controllerOf(
      tester.element(find.byKey(dragKey)),
    )!;
    final initiallyEditing = editMode.value;
    expect(handle.right, tester.getRect(edit).left);
    expect(toolbar(tester).top, 514);
    expect(toolbar(tester).right, 784);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(editMode.value, !initiallyEditing);
    await tester.tap(find.byKey(const ValueKey('appearance-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceSettings), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handle drags the toolbar without toggling style editing', (
    tester,
  ) async {
    await pumpApp(tester);
    final initial = toolbar(tester);
    final editMode = StyleEditScope.controllerOf(
      tester.element(find.byKey(dragKey)),
    )!;
    final initiallyEditing = editMode.value;
    await move(tester, const Offset(-100, 80));
    expect(toolbar(tester).left, initial.left - 100);
    expect(toolbar(tester).top, 564);
    expect(toolbar(tester).bottom, 600);
    expect(editMode.value, initiallyEditing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar stays bounded and reverses immediately at an edge', (
    tester,
  ) async {
    await pumpApp(tester);
    await move(tester, const Offset(-2000, -2000));
    expect(toolbar(tester).topLeft, Offset.zero);
    await move(tester, const Offset(30, 30));
    expect(toolbar(tester).topLeft, const Offset(30, 30));
    await move(tester, const Offset(2000, 2000));
    expect(toolbar(tester).bottomRight, const Offset(800, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing keeps the dragged toolbar in the viewport', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await move(tester, const Offset(2000, 2000));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 240);
    await tester.pumpAndSettle();
    expect(toolbar(tester).left, greaterThanOrEqualTo(0));
    expect(toolbar(tester).top, greaterThanOrEqualTo(0));
    expect(toolbar(tester).right, lessThanOrEqualTo(360));
    expect(toolbar(tester).bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets('apps button is hidden by default and shown when configured', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('appearance-applications')), findsNothing);

    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StyleEditScope(
            controller: ValueNotifier(false),
            child: ApplicationSelectorScope(
              onOpenApplications: () => opened++,
              child: const FloatingAppearanceToolbar(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appsButton = find.byKey(const ValueKey('appearance-applications'));
    expect(appsButton, findsOneWidget);
    expect(find.byIcon(Icons.apps), findsOneWidget);
    await tester.tap(appsButton);
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('ApplicationSelectorDialog opens folders and creates empty/cloned apps', (
    tester,
  ) async {
    late Directory tempDir;
    late Directory appA;
    late Directory appB;
    final store = SandboxedApplicationStore();
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('app-dialog-test-');
      appA = Directory('${tempDir.path}${Platform.pathSeparator}alpha');
      appB = Directory('${tempDir.path}${Platform.pathSeparator}beta');
      await store.createApplication(appA, name: 'Alpha');
    });
    addTearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Directory? selectedDir;
    Directory? createdDir;
    String? createdName;
    bool? createdClone;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ApplicationSelectorDialog.show(
                  context,
                  store: store,
                  currentDirectory: appA,
                  currentName: 'Alpha',
                  pickDirectory: (_) async => appB.path,
                  onSelectDirectory: (dir, {required initializeNonEmpty}) async {
                    selectedDir = dir;
                  },
                  onCreateApplication: (
                    dir, {
                    required name,
                    required cloneCurrent,
                  }) async {
                    createdDir = dir;
                    createdName = name;
                    createdClone = cloneCurrent;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('application-selector-dialog')), findsOneWidget);
    expect(find.text('Alpha'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('application-selector-new')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('application-create-name-input')),
      'Gamma',
    );
    await tester.enterText(
      find.byKey(const ValueKey('application-create-path-input')),
      '${tempDir.path}${Platform.pathSeparator}gamma',
    );
    await tester.tap(find.text('Application vide'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('application-create-submit')));
    await tester.pumpAndSettle();

    expect(createdName, 'Gamma');
    expect(createdClone, isFalse);
    expect(createdDir?.path, '${tempDir.path}${Platform.pathSeparator}gamma');

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('application-selector-open-folder')));
    await tester.pumpAndSettle();
    expect(selectedDir?.path, appB.path);
  });
}
