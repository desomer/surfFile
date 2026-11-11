import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_designer/super_designer.dart';

void main() {
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

  testWidgets('SuperDesigner places the edit banner at the bottom', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SuperDesignerApp());
    await tester.pumpAndSettle();

    StyleEditScope.controllerOf(tester.element(find.byType(SuperPage)))!.value =
        true;
    await tester.pumpAndSettle();
    final banner = find.byKey(const ValueKey('style-edit-banner'));
    expect(banner, findsOneWidget);
    expect(tester.getRect(banner).center.dx, 600);
    expect(tester.getRect(banner).bottom, 892);

    final aiButton = find.byKey(const ValueKey('style-edit-banner-ai'));
    final chat = find.byKey(const ValueKey('vibe-chat-dialog'));
    await tester.tap(aiButton);
    await tester.pumpAndSettle();
    expect(tester.getRect(chat).overlaps(tester.getRect(banner)), isFalse);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(tester.getRect(banner).bottom, 692);
    expect(tester.getRect(chat).overlaps(tester.getRect(banner)), isFalse);
    await tester.tap(aiButton);
    await tester.pumpAndSettle();
    expect(chat, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
