import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test(
    'createSuperDesignerRegistry registers both core engine and extensions',
    () {
      final registry = createSuperDesignerRegistry();

      // Composants du moteur super_container_layout
      expect(registry.registry.containsKey('Layout'), isTrue);
      expect(registry.registry.containsKey('Card'), isTrue);
      expect(registry.registry.containsKey('Value'), isTrue);
      expect(registry.registry.containsKey('Action'), isTrue);
      expect(registry.registry.containsKey('ListView'), isTrue);
      expect(registry.registry.containsKey('Tab'), isTrue);
      expect(registry.registry.containsKey('TreeView'), isTrue);
      expect(registry.registry.containsKey('Table'), isTrue);

      // Composants d'extension super_container_extensions
      expect(registry.registry.containsKey('Chart'), isTrue);
      expect(ComponentConfigCatalog.of('chart'), isNotNull);
    },
  );

  testWidgets(
    'SuperDesignerApp mounts SuperPage, FloatingAppearanceToolbar and registered extensions',
    (tester) async {
      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();

      expect(find.byType(SuperPage), findsOneWidget);
      expect(find.byType(FloatingAppearanceToolbar), findsOneWidget);

      final superApp = tester.widget<SuperApp>(find.byType(SuperApp));
      expect(superApp.registry, isNotNull);
      expect(superApp.registry!.registry.containsKey('Layout'), isTrue);
      expect(superApp.registry!.registry.containsKey('Chart'), isTrue);
    },
  );
}
