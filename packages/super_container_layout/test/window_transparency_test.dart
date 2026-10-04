import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/services/window_transparency.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';

import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background opacity leaves content colors opaque', () {
    const appearance = Appearance(backgroundOpacity: .25);
    final theme = appearance.theme(Brightness.light);
    expect(theme.scaffoldBackgroundColor.a, closeTo(.25, .001));
    expect(theme.colorScheme.onSurface.a, 1);
    expect(theme.colorScheme.primary.a, 1);
    final translucent = appearance.copyWith(
      backgroundStyle: const ContainerStyle(color: Color(0x80FFFFFF)),
    );
    expect(
      translucent.theme(Brightness.light).scaffoldBackgroundColor.a,
      closeTo(.25 * 128 / 255, .001),
    );
  });

  test(
    'native composition and whole-window opacity use separate channels',
    () async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const acrylic = MethodChannel('com.alexmercerind/flutter_acrylic');
      messenger.setMockMethodCallHandler(acrylic, (call) async {
        calls.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(WindowTransparency.channel, (
        call,
      ) async {
        calls.add(call.method);
        expect(call.arguments, {'opacity': .8});
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(acrylic, null);
        messenger.setMockMethodCallHandler(WindowTransparency.channel, null);
      });
      await WindowTransparency.apply(.8);
      expect(calls, ['Initialize', 'SetEffect', 'setOpacity']);
    },
    skip: !Platform.isWindows,
  );
}
