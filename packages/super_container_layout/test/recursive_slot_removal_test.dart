import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Menu contextuel d'une liste imbriquée et suppression récursive de ses
/// configurations persistées.
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

  const targetKey = ValueKey('editable-container');

  Future<ValueNotifier<Appearance>> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 400,
                child: EditableSurface(key: targetKey, id: 'box', label: 'Box'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(router: router, registry: Registry()..bootstrap()),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(targetKey));
    final appearance = AppearanceScope.controllerOf(context)!;
    appearance.value = appearance.value.copyWith(
      nativeComponents: {
        ...appearance.value.nativeComponents,
        'box': NativeComponentConfig(
          placements: {
            'child': ['lay'],
          },
          slotTypes: {'lay': 'factory:Layout'},
        ),
      },
      layouts: {
        ...appearance.value.layouts,
        'lay': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['first', 'list1'],
          },
          slotTypes: {
            'first': 'registry:Text',
            'list1': 'registry:ListView',
          },
        ),
        'list1': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['t1'],
          },
          slotTypes: {'t1': 'registry:Text'},
        ),
      },
      textComponents: {
        ...appearance.value.textComponents,
        'first': const SuperTextConfig(initialText: 'First'),
        't1': const SuperTextConfig(initialText: 'Row text'),
      },
      listComponents: {
        ...appearance.value.listComponents,
        'list1': const SuperListViewConfig(),
      },
    );
    await tester.pumpAndSettle();
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    EditorHistoryScope.controllerOf(context)!.clear();
    return appearance;
  }

  Finder rowText() => find.descendant(
    of: find.byKey(const ValueKey('super-list-row-list1-template')),
    matching: find.byType(SuperText),
  );

  testWidgets('a non-first list shows its size and remove actions', (
    tester,
  ) async {
    await mount(tester);
    expect(rowText(), findsOneWidget);
    await tester.tap(rowText(), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    final listEntry = find.byKey(const ValueKey('style-menu-Liste'));
    expect(listEntry, findsOneWidget);
    expect(
      find.descendant(of: listEntry, matching: find.byIcon(Icons.straighten)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: listEntry,
        matching: find.byIcon(Icons.delete_outline),
      ),
      findsOneWidget,
    );
  });

  testWidgets('removing a list deletes its subtree in one undoable edit', (
    tester,
  ) async {
    final appearance = await mount(tester);
    final before = appearance.value;
    await tester.tap(rowText(), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('style-menu-Liste')),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();

    final after = appearance.value;
    expect(after.layouts['lay']!.placements[SuperLayoutZone.center], ['first']);
    expect(after.layouts.containsKey('list1'), isFalse);
    expect(after.listComponents.containsKey('list1'), isFalse);
    expect(after.textComponents.containsKey('t1'), isFalse);
    expect(after.textComponents.containsKey('first'), isTrue);
    expect(find.byType(SuperListView), findsNothing);

    final history = EditorHistoryScope.controllerOf(
      tester.element(find.byKey(targetKey)),
    )!;
    history.undo();
    await tester.pumpAndSettle();
    expect(identical(appearance.value, before), isTrue);
    expect(history.canUndo, isFalse);
    expect(find.byType(SuperListView), findsOneWidget);
  });
}
