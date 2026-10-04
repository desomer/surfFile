import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      WindowTransparency.channel,
      (_) async => null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      null,
    );
    messenger.setMockMethodCallHandler(WindowTransparency.channel, null);
  });

  testWidgets('public entry point builds a configured layout in SuperApp', (
    tester,
  ) async {
    await tester.pumpWidget(
      SuperApp(
        home: Scaffold(
          body: SuperContainer(
            child: SuperLayout(
              config: const SuperLayoutConfig(
                north: false,
                south: false,
                west: false,
                east: false,
                placements: {
                  SuperLayoutZone.center: ['content'],
                },
              ),
              slots: [
                BuilderSlot(
                  id: 'content',
                  label: 'Content',
                  builder: (_) => const Text('Package API'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      AppearanceScope.controllerOf(tester.element(find.text('Package API'))),
      isA<PersistentAppearanceController>(),
    );
    expect(find.byType(SuperContainer), findsWidgets);
    expect(find.byType(SuperLayout), findsOneWidget);
    expect(find.text('Package API'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
