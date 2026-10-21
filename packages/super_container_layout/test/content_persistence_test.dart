import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
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

  for (final type in ['IterableContent', 'ListView']) {
    test('$type owns and duplicates its shared style and layout', () {
      final registry = Registry()..bootstrap();
      final original = Appearance(
        styles: {'item': const ContainerStyle(color: Colors.blue, radius: 14)},
        layouts: {
          'item': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['text'],
            },
            slotTypes: {'text': 'registry:Text'},
          ),
        },
        nativeComponents: {
          'page': NativeComponentConfig(
            placements: {
              'body': ['item'],
            },
            slotTypes: {'item': 'registry:$type'},
          ),
        },
        textComponents: {'text': const SuperTextConfig(initialText: 'Saved')},
        listComponents: type == 'ListView'
            ? {'item': const SuperListViewConfig()}
            : const {},
      );
      final copy = EditorPageGraph.duplicate(
        appearance: original,
        registry: registry,
        sourcePageId: 'page',
        targetPageId: 'copy',
      );
      final id = copy.nativeComponents['copy']!.slotsOf('body').single;
      expect(id, isNot('item'));
      expect(copy.styles[id]!.radius, 14);
      expect(copy.styles[id]!.color, Colors.blue);
      final child = copy.layouts[id]!.placedSlotIds.single;
      expect(child, isNot('text'));
      expect(copy.textComponents[child]!.initialText, 'Saved');
      if (type == 'ListView') {
        expect(copy.listComponents.containsKey(id), isTrue);
      }
      final removed = EditorPageGraph.removeInstance(
        appearance: original.copyWith(
          nativeComponents: {'page': NativeComponentConfig()},
        ),
        registry: registry,
        instanceId: 'item',
        type: 'registry:$type',
        containerKind: EditorConfigKind.nativeComponent,
      );
      expect(removed.styles.containsKey('item'), isFalse);
      expect(removed.layouts.containsKey('item'), isFalse);
      expect(removed.textComponents.containsKey('text'), isFalse);
      expect(removed.listComponents.containsKey('item'), isFalse);
      final shared = EditorPageGraph.removeInstance(
        appearance: original.copyWith(
          nativeComponents: {
            'other': NativeComponentConfig(
              placements: {
                'body': ['item'],
              },
              slotTypes: {'item': 'registry:$type'},
            ),
          },
        ),
        registry: registry,
        instanceId: 'item',
        type: 'registry:$type',
        containerKind: EditorConfigKind.nativeComponent,
      );
      expect(shared.styles.containsKey('item'), isTrue);
      expect(shared.layouts.containsKey('item'), isTrue);
    });
  }

  testWidgets(
    'IterableContent registry style persists and follows undo redo and restore',
    (tester) async {
      final registry = Registry()..bootstrap();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: IterableContent(id: 'content')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(IterableContent));
      StyleEditScope.controllerOf(context)!.value = true;
      final appearance = AppearanceScope.controllerOf(context)!;
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();
      final before = appearance.value;
      final surface = tester.widget<EditableSurface>(
        find.byType(EditableSurface),
      );
      surface.onStyleChanged!(
        const ContainerStyle(color: Colors.green, padding: 8),
      );
      await tester.pumpAndSettle();
      expect(appearance.value.styles['content']!.color, Colors.green);
      expect(
        tester
            .widget<SuperContainer>(find.byType(SuperContainer))
            .style
            .padding,
        8,
      );
      const codec = AppearanceCodec();
      final saved = codec.toJson(appearance.value);
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value, same(before));
      expect(
        tester
            .widget<SuperContainer>(find.byType(SuperContainer))
            .style
            .padding,
        0,
      );
      history.redo();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SuperContainer>(find.byType(SuperContainer))
            .style
            .padding,
        8,
      );
      appearance.value = codec.fromJson(saved);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SuperContainer>(find.byType(SuperContainer)).style.color,
        const Color(0xFF4CAF50),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ListView placeholder style uses its own persisted template ID', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: SuperListView(id: 'list')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SuperListView));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(IterableContent), findsOneWidget);
    final history = EditorHistoryScope.controllerOf(context)!;
    history.clear();
    final appearance = AppearanceScope.controllerOf(context)!;
    final before = appearance.value;
    tester
        .widget<IterableContent>(find.byType(IterableContent))
        .onStyleChanged!(
      const ContainerStyle(radius: 16, color: Colors.orange),
    );
    await tester.pumpAndSettle();
    expect(appearance.value.styles.keys, ['list']);
    expect(appearance.value.styles['list']!.radius, 16);
    history.undo();
    await tester.pumpAndSettle();
    expect(appearance.value, same(before));
    expect(
      tester.widget<IterableContent>(find.byType(IterableContent)).style.radius,
      0,
    );
    history.redo();
    await tester.pumpAndSettle();
    expect(
      tester.widget<IterableContent>(find.byType(IterableContent)).style.radius,
      16,
    );
    expect(tester.takeException(), isNull);
  });
}
