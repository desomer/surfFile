import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_zone_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<GoRouter> mount(
    Widget page,
    WidgetTester tester,
    Registry registry, {
    AppearanceStore? store,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => page)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(router: router, registry: registry, appearanceStore: store),
    );
    await tester.pumpAndSettle();
    return router;
  }

  test(
    'native moves preserve instance metadata, ordering and enabled source',
    () {
      final initial = NativeComponentConfig(
        placements: {
          'left': ['a', 'b'],
          'right': ['c'],
        },
        slotTypes: {'a': 'factory:A'},
        slotPreferredSizes: {'a': const Size(70, 30)},
        slotSizeConstraints: {
          'a': const SlotSizeConstraints(
            minWidth: SlotDimension(20, SlotSizeUnit.pixels),
          ),
        },
      );
      final reordered = initial.withSlotMoved('a', 'left', afterId: 'b');
      expect(reordered.slotsOf('left'), ['b', 'a']);
      expect(reordered.withSlotMoved('a', 'left'), same(reordered));
      final moved = reordered.withSlotMoved('a', 'right', beforeId: 'c');
      expect(moved.slotsOf('left'), ['b']);
      expect(moved.slotsOf('right'), ['a', 'c']);
      expect(moved.slotTypes, initial.slotTypes);
      expect(moved.slotPreferredSizes, initial.slotPreferredSizes);
      expect(moved.slotSizeConstraints, initial.slotSizeConstraints);
      final emptySource = moved.withSlotMoved('b', 'right');
      expect(emptySource.slotsOf('left'), isEmpty);
      expect(emptySource.isEnabled('left'), isTrue);
      expect(
        NativeComponentConfig.fromJson(emptySource.toJson()).toJson(),
        emptySource.toJson(),
      );
      expect(
        () => initial.withSlotMoved('unknown', 'left'),
        throwsArgumentError,
      );
      final padded = initial.withSlotSizeConstraints(
        'a',
        const SlotSizeConstraints(padding: 12),
      );
      expect(
        NativeComponentConfig.fromJson(padded.toJson()).slotSizeConstraints,
        padded.slotSizeConstraints,
      );
    },
  );

  testWidgets('native body badge matches SuperLayout and hides add when used', (
    tester,
  ) async {
    await mount(
      const SuperPage(child: Text('Body content')),
      tester,
      Registry(),
    );
    final context = tester.element(find.byType(SuperPage));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();

    final body = find.byKey(const ValueKey('scaffold-page-select-body'));
    expect(body, findsOneWidget);
    expect(find.byKey(const ValueKey('scaffold-page-add-body')), findsNothing);
    final badge = find
        .ancestor(of: body, matching: find.byType(Material))
        .first;
    final colors = Theme.of(tester.element(body)).colorScheme;
    expect(
      tester.widget<Material>(badge).color,
      colors.primary.withValues(alpha: .35),
    );
    expect(tester.takeException(), isNull);
  });

  for (final appBar in [true, false]) {
    testWidgets(
      '${appBar ? 'AppBar' : 'bottom bar'} shares min preferred max editor and cancellation',
      (tester) async {
        final registry = Registry()
          ..registerFactory('A', const SizedBox.expand());
        final region = appBar ? 'title' : 'left';
        final initial = NativeComponentConfig(
          placements: {
            region: ['a'],
          },
          slotTypes: {'a': 'factory:A'},
          slotPreferredSizes: {'a': const Size(100, 32)},
        );
        await mount(
          appBar
              ? SuperPage(
                  appBar: SuperAppBar(id: 'size-bar', nativeConfig: initial),
                )
              : SuperPage(
                  bottomNavigationBar: SuperBottomAppBar(
                    id: 'size-bar',
                    nativeConfig: initial,
                  ),
                ),
          tester,
          registry,
        );
        final context = tester.element(
          find.byType(appBar ? SuperAppBar : SuperBottomAppBar),
        );
        StyleEditScope.controllerOf(context)!.value = true;
        final history = EditorHistoryScope.controllerOf(context)!;
        await tester.pumpAndSettle();
        history.clear();
        Future<void> open() async {
          final stack = tester
              .widgetList<SlotStack>(find.byType(SlotStack))
              .singleWhere(
                (stack) => stack.slots.any((slot) => slot.id == 'a'),
              );
          unawaited(stack.onEditPreferredSize!(stack.slots.single));
          await tester.pumpAndSettle();
        }

        Future<void> enter(String field, String text) async {
          final finder = find.byKey(ValueKey('slot-$field'));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.enterText(finder, text);
          await tester.pumpAndSettle();
        }

        await open();
        expect(find.byType(TextFormField), findsNWidgets(6));
        expect(find.byKey(const ValueKey('slot-preview-zone')), findsOneWidget);
        await enter('min-width', '200');
        await enter('max-width', '100');
        expect(
          find.text('La largeur minimale dépasse la largeur maximale.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Appliquer'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        final controller = registry.nativeComponentController('size-bar');
        expect(controller.value.toJson(), initial.toJson());
        expect(history.canUndo, isFalse);
        await open();
        await enter('min-width', '40');
        await enter('preferred-width', '50');
        final unit = tester.widget<DropdownButton<SlotSizeUnit>>(
          find.byKey(const ValueKey('slot-unit-preferred-width')),
        );
        unit.onChanged!(SlotSizeUnit.percent);
        await tester.pumpAndSettle();
        await enter('max-width', '180');
        await tester.tap(find.text('Appliquer'));
        await tester.pumpAndSettle();
        final saved = controller.value.slotSizeConstraints['a']!;
        expect(saved.minWidth, const SlotDimension(40, SlotSizeUnit.pixels));
        expect(
          saved.preferredWidth,
          const SlotDimension(50, SlotSizeUnit.percent),
        );
        expect(saved.maxWidth, const SlotDimension(180, SlotSizeUnit.pixels));
        expect(
          tester.getSize(find.byKey(const ValueKey('slot-a'))).width,
          lessThanOrEqualTo(180),
        );
        history.undo();
        await tester.pumpAndSettle();
        expect(controller.value.toJson(), initial.toJson());
        history.redo();
        await tester.pumpAndSettle();
        expect(controller.value.slotSizeConstraints['a'], saved);
        await open();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('slot-max-width')),
              )
              .controller!
              .text,
          '180.0',
        );
        tester
            .widget<Slider>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Slider &&
                    widget.key == const ValueKey('slot-padding'),
              ),
            )
            .onChanged!(18);
        await tester.pumpAndSettle();
        expect(controller.value.slotSizeConstraints['a']!.padding, 18);
        await tester.tap(find.text('Taille et marge par défaut'));
        await tester.pumpAndSettle();
        expect(
          controller.value.slotSizeConstraints['a'],
          const SlotSizeConstraints(),
        );
        expect(controller.value.slotPreferredSizes.containsKey('a'), isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${appBar ? 'AppBar' : 'bottom bar'} resizes selected slots using handles',
      (tester) async {
        final registry = Registry()
          ..registerFactory(
            'A',
            const EditableSurface(
              label: 'AB',
              child: Center(child: Text('A')),
            ),
          );
        final region = appBar ? 'title' : 'left';
        final initial = NativeComponentConfig(
          placements: {
            region: ['a'],
          },
          slotTypes: {'a': 'factory:A'},
          slotPreferredSizes: {'a': const Size(100, 32)},
        );
        await mount(
          appBar
              ? SuperPage(
                  appBar: SuperAppBar(id: 'resize-bar', nativeConfig: initial),
                )
              : SuperPage(
                  bottomNavigationBar: SuperBottomAppBar(
                    id: 'resize-bar',
                    nativeConfig: initial,
                  ),
                ),
          tester,
          registry,
        );
        final context = tester.element(
          find.byType(appBar ? SuperAppBar : SuperBottomAppBar),
        );
        final mode = StyleEditScope.controllerOf(context)!;
        final history = EditorHistoryScope.controllerOf(context)!;
        final appearance =
            AppearanceScope.controllerOf(context)!
                as PersistentAppearanceController;
        mode.value = true;
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('style-edit-banner-drag')),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();
        final editor = tester.state<NativeComponentEditorState>(
          find.descendant(
            of: find.byType(appBar ? SuperAppBar : SuperBottomAppBar),
            matching: find.byType(NativeComponentEditor),
          ),
        );
        editor.select(region);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('slot-resize-a-e')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('slot-label-select-a')));
        await tester.pumpAndSettle();
        final handle = find.byKey(const ValueKey('slot-resize-a-e'));
        expect(handle, findsOneWidget);
        final before = tester.getSize(find.byKey(const ValueKey('slot-a')));
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('slot-resize-size-a')),
          findsOneWidget,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        final controller = registry.nativeComponentController('resize-bar');
        final dimensions = controller.value.slotSizeConstraints['a']!;
        expect(dimensions.preferredWidth!.value, closeTo(before.width + 40, 1));
        expect(dimensions.preferredHeight!.value, 32);
        expect(controller.value.slotPreferredSizes.containsKey('a'), isFalse);
        expect(
          tester.getSize(find.byKey(const ValueKey('slot-a'))).width,
          closeTo(before.width + 40, 1),
        );
        history.undo();
        await tester.pumpAndSettle();
        expect(controller.value.slotSizeConstraints, isEmpty);
        expect(controller.value.slotPreferredSizes['a'], const Size(100, 32));
        history.redo();
        await tester.pumpAndSettle();
        expect(controller.value.slotSizeConstraints['a'], dimensions);
        await appearance.saved;
        expect(
          (await AppearanceStore().load())
              .nativeComponent('resize-bar')
              .slotSizeConstraints['a'],
          dimensions,
        );
        final heightHandle = find.byKey(const ValueKey('slot-resize-a-s'));
        expect(heightHandle, findsOneWidget);
        final vertical = await tester.startGesture(
          tester.getCenter(heightHandle),
        );
        await vertical.moveBy(const Offset(0, 100));
        await tester.pump();
        await vertical.moveBy(const Offset(0, 100));
        await tester.pump();
        await vertical.up();
        await tester.pumpAndSettle();
        final height =
            controller.value.slotSizeConstraints['a']!.preferredHeight!.value;
        expect(height, greaterThanOrEqualTo(32));
        expect(
          height,
          lessThanOrEqualTo(
            appBar ? kToolbarHeight : kBottomNavigationBarHeight,
          ),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('slot-a'))).height,
          lessThanOrEqualTo(
            appBar ? kToolbarHeight : kBottomNavigationBarHeight,
          ),
        );
        mode.value = false;
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('slot-resize-a-e')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${appBar ? 'AppBar' : 'bottom bar'} moves A by dragging between native regions',
      (tester) async {
        final registry = Registry()
          ..registerFactory(
            'A',
            const EditableSurface(
              label: 'AB',
              child: Center(child: Text('A')),
            ),
          );
        final initial = NativeComponentConfig(
          regions: appBar
              ? {'title': true, 'actions': true}
              : {'left': true, 'center': true, 'right': true},
          placements: {
            appBar ? 'title' : 'left': ['a'],
          },
          slotTypes: {'a': 'factory:A'},
          slotPreferredSizes: {'a': const Size(48, 32)},
        );
        await mount(
          appBar
              ? SuperPage(
                  appBar: SuperAppBar(id: 'drag-bar', nativeConfig: initial),
                )
              : SuperPage(
                  bottomNavigationBar: SuperBottomAppBar(
                    id: 'drag-bar',
                    nativeConfig: initial,
                  ),
                ),
          tester,
          registry,
        );
        final context = tester.element(
          find.byType(appBar ? SuperAppBar : SuperBottomAppBar),
        );
        final history = EditorHistoryScope.controllerOf(context)!;
        final appearance =
            AppearanceScope.controllerOf(context)!
                as PersistentAppearanceController;
        StyleEditScope.controllerOf(context)!.value = true;
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('style-edit-banner-drag')),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();
        final prefix = appBar ? 'super-app-bar' : 'super-bottom-app-bar';
        final sourceRegion = appBar ? 'title' : 'left';
        final targetRegion = appBar ? 'actions' : 'right';
        final editor = tester.state<NativeComponentEditorState>(
          find.descendant(
            of: find.byType(appBar ? SuperAppBar : SuperBottomAppBar),
            matching: find.byType(NativeComponentEditor),
          ),
        );
        editor.select(sourceRegion);
        await tester.pumpAndSettle();
        final label = find.byKey(const ValueKey('slot-label-select-a'));
        expect(
          find.descendant(
            of: label,
            matching: find.byType(Draggable<SlotDragData>),
          ),
          findsOneWidget,
        );
        final source = tester.getCenter(label);
        final target = tester.getRect(
          find.byKey(ValueKey('$prefix-slot-drop-$targetRegion')),
        );
        final gesture = await tester.startGesture(source);
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump();
        await gesture.moveTo(Offset(target.center.dx, target.bottom - 8));
        await tester.pump();
        expect(find.textContaining('→'), findsOneWidget);
        await gesture.up();
        await tester.pumpAndSettle();
        final controller = registry.nativeComponentController('drag-bar');
        expect(controller.value.slotsOf(sourceRegion), isEmpty);
        expect(controller.value.slotsOf(targetRegion), ['a']);
        expect(controller.value.isEnabled(sourceRegion), isTrue);
        expect(controller.value.slotTypeOf('a'), 'factory:A');
        expect(controller.value.slotPreferredSizes['a'], const Size(48, 32));
        history.undo();
        await tester.pumpAndSettle();
        expect(controller.value.slotsOf(sourceRegion), ['a']);
        expect(controller.value.slotsOf(targetRegion), isEmpty);
        history.redo();
        await tester.pumpAndSettle();
        expect(controller.value.slotsOf(targetRegion), ['a']);
        await appearance.saved;
        expect(
          (await AppearanceStore().load())
              .nativeComponent('drag-bar')
              .slotsOf(targetRegion),
          ['a'],
        );
        controller.value = controller.value
            .withSlotAdded('b', targetRegion, type: 'factory:A')
            .withSlotSize('b', const Size(48, 32));
        await tester.pumpAndSettle();
        tester
            .state<NativeComponentEditorState>(
              find.descendant(
                of: find.byType(appBar ? SuperAppBar : SuperBottomAppBar),
                matching: find.byType(NativeComponentEditor),
              ),
            )
            .select(targetRegion);
        await tester.pumpAndSettle();
        final reorder = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('slot-label-select-a'))),
        );
        await reorder.moveBy(const Offset(12, 0));
        await tester.pump();
        final other = tester.getRect(find.byKey(const ValueKey('slot-b')));
        await reorder.moveTo(Offset(other.right - 5, other.bottom - 5));
        await tester.pump();
        await reorder.up();
        await tester.pumpAndSettle();
        expect(controller.value.slotsOf(targetRegion), ['b', 'a']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'generic placements are immutable, validated and losslessly serialized',
    () {
      final ids = ['first'];
      final config = NativeComponentConfig(
        placements: {'title': ids},
        slotTypes: {'first': 'component:heading'},
      ).withSlotSize('first', const Size(120, double.infinity));
      ids.clear();
      expect(config.slotsOf('title'), ['first']);
      expect(() => config.slotsOf('title').clear(), throwsUnsupportedError);
      expect(() => config.regions.clear(), throwsUnsupportedError);
      final hidden = config.withRegionEnabled('title', false);
      expect(hidden.slotsOf('title'), ['first']);
      expect(hidden.isEnabled('title'), isFalse);
      final restored = NativeComponentConfig.fromJson(hidden.toJson());
      expect(restored.toJson(), hidden.toJson());
      expect(
        restored.slotPreferredSizes['first'],
        const Size(120, double.infinity),
      );
      final replaced = restored.withSlotAdded('next', 'title', replace: true);
      expect(replaced.slotsOf('title'), ['next']);
      expect(replaced.slotTypes, isEmpty);
      expect(replaced.slotPreferredSizes, isEmpty);
      expect(replaced.withoutSlot('next').isEnabled('title'), isTrue);
      expect(
        () => NativeComponentConfig(
          placements: {
            'a': ['same'],
            'b': ['same'],
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeComponentConfig.fromJson({
          'placements': {
            'title': [
              {'id': '', 'type': 'heading'},
            ],
          },
        }),
        throwsFormatException,
      );
      expect(
        () => ScaffoldPageConfig().withRegionEnabled(
          ScaffoldPageRegion.body,
          false,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'native configs persist, transfer, reset and retain the appearance subtype',
    () async {
      final appearance = DefaultAppearance(
        spacing: 19,
        components: {
          'bar': NativeComponentConfig(
            placements: {
              'title': ['heading'],
            },
          ),
        },
      );
      const codec = DefaultAppearanceCodec();
      final store = AppearanceStore(codec: codec);
      await store.save(appearance);
      final restored = await store.load();
      expect(codec.encode(restored), codec.encode(appearance));
      final transferred = AppearanceTransfer.import(
        DefaultAppearance(),
        AppearanceTransfer.export(appearance, {
          TransferGroup.layouts,
        }, codec: codec),
        {TransferGroup.layouts},
        codec: codec,
      );
      expect(transferred.nativeComponent('bar').slotsOf('title'), ['heading']);
      final changed = appearance.withNativeComponent(
        'bar',
        NativeComponentConfig(),
      );
      expect(changed, isA<DefaultAppearance>());
      expect((changed).spacing, 19);
      expect(changed.resetLayouts().components, isEmpty);
    },
  );

  test('Scaffold compatibility controller shares generic storage and follows undo/reset', () {
    final original = ScaffoldPageConfig(
      placements: {
        ScaffoldPageRegion.body: ['body'],
      },
    );
    final appearance = ValueNotifier<Appearance>(
      Appearance(components: {'page': original}),
    );
    final registry = Registry()..bindAppearance(appearance);
    addTearDown(registry.unbindAppearance);
    addTearDown(appearance.dispose);
    final page = registry.scaffoldPageController('page');
    final native = registry.nativeComponentController('page');
    expect(page.value.slotsOf(ScaffoldPageRegion.body), ['body']);
    page.value = page.value.withRegionEnabled(ScaffoldPageRegion.drawer, true);
    expect(native.value.isEnabled('drawer'), isTrue);
    expect(appearance.value.components['page'], isA<NativeComponentConfig>());
    expect(
      appearance.value
          .scaffoldPage('page')
          .isEnabled(ScaffoldPageRegion.drawer),
      isTrue,
    );
    native.value = native.value.withRegionEnabled('drawer', false);
    expect(page.value.isEnabled(ScaffoldPageRegion.drawer), isFalse);
    appearance.value = appearance.value.resetLayouts();
    expect(page.value.slotsOf(ScaffoldPageRegion.body), isEmpty);
  });

  testWidgets(
    'AppBar uses all five native properties without a registered layout',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(
          appBar: SuperAppBar(
            leading: Text('Back content'),
            title: Text('Native title'),
            actions: [Text('One'), Text('Two')],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(32),
              child: Text('Tabs'),
            ),
            flexibleSpace: ColoredBox(color: Colors.blue),
          ),
          child: Text('Body content'),
        ),
        tester,
        registry,
      );
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.leading, isNotNull);
      expect(bar.title, isNotNull);
      expect(bar.actions, hasLength(2));
      expect(bar.bottom!.preferredSize.height, 32);
      expect(bar.flexibleSpace, isNotNull);
      expect(find.byType(RegisteredSuperLayout), findsNothing);
      expect(registry.superLayoutConfigById, isEmpty);
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Body content')).dy, 88);
      final config = registry.nativeComponentController('root-appBar');
      config.value = config.value.withRegionEnabled('bottom', false);
      await tester.pumpAndSettle();
      expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
      expect(tester.getTopLeft(find.text('Body content')).dy, 56);
      config.value = config.value.withRegionEnabled('bottom', true);
      await tester.pumpAndSettle();
      expect(find.text('Tabs'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Body content')).dy, 88);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved AppBar layout is ignored in favor of source defaults', (
    tester,
  ) async {
    final store = AppearanceStore();
    await store.save(
      Appearance(
        layouts: {
          'bar': const SuperLayoutConfig(
            east: true,
            placements: {
              SuperLayoutZone.center: ['heading'],
              SuperLayoutZone.east: ['refresh'],
            },
            slotTypes: {'heading': 'title', 'refresh': 'action'},
          ),
        },
      ),
    );
    final registry = Registry();
    await mount(
      const SuperPage(
        appBar: SuperAppBar(
          id: 'bar',
          title: Text('Migrated heading'),
          action: Text('Migrated action'),
        ),
      ),
      tester,
      registry,
      store: store,
    );
    final controller = registry.nativeComponentController('bar');
    expect(controller.value.slotsOf('title'), ['title']);
    expect(controller.value.slotsOf('actions'), ['action']);
    expect(find.text('Migrated action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AppBar context config, hierarchy and overlays use the shared editor',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(appBar: SuperAppBar(title: Text('Heading'))),
        tester,
        registry,
      );
      final context = tester.element(find.byType(SuperAppBar));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.text('Heading')) + const Offset(3, 3),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Page', 'AppBar', 'AppBar', 'Titre']);
      expect(
        find.byKey(const ValueKey('scaffold-page-add-appBar')),
        findsNothing,
      );
      final row = find.byKey(const ValueKey('style-menu-Titre'));
      final subtitle = find.byKey(const ValueKey('style-menu-zone-Titre'));
      expect(subtitle, findsOneWidget);
      expect(tester.widget<Text>(subtitle).data, 'ApplicationBar');
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(EditorSlot.zoneMenuIcon),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: row, matching: find.text('zone Titre')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-settings')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNWidgets(9));
      final toggle = find.byKey(const ValueKey('super-app-bar-switch-actions'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-add-actions')),
        findsOneWidget,
      );
      LayoutSelection.select(['Page']);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-add-actions')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-appBar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native overlays hide add for occupied regions and zoom sibling badges',
    (tester) async {
      await mount(
        const SuperPage(
          appBar: SuperAppBar(
            title: Text('Heading'),
            leading: Text('Original leading'),
          ),
        ),
        tester,
        Registry(),
      );
      final context = tester.element(find.byType(SuperAppBar));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.text('Original leading')) + const Offset(2, 2),
      );
      await tester.pumpAndSettle();
      for (var level = 0; level < 2; level++) {
        await tester.pump(const Duration(seconds: 1));
        final point =
            tester.getTopLeft(find.text('Original leading')) +
            const Offset(2, 2);
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('super-app-bar-add-leading')),
        findsNothing,
      );
      final titleBadge = find.byKey(
        const ValueKey('super-app-bar-select-title'),
      );
      expect(titleBadge, findsOneWidget);
      expect(
        find.byKey(const ValueKey('super-app-bar-select-leading')),
        findsOneWidget,
      );

      final titleBadgeWidget = tester.widget<EditorZoneBadge>(
        find.byKey(const ValueKey('super-app-bar-badge-content-title')),
      );
      titleBadgeWidget.onHover!(true);
      await tester.pump(const Duration(milliseconds: 150));
      for (final region in ['title', 'leading']) {
        final badge = find.byKey(
          ValueKey('super-app-bar-badge-content-$region'),
        );
        final scale = tester.widget<AnimatedScale>(
          find.ancestor(of: badge, matching: find.byType(AnimatedScale)),
        );
        expect(scale.scale, EmphasizedLabel.scale);
      }
      titleBadgeWidget.onHover!(false);
      await tester.pump(const Duration(milliseconds: 150));
      for (final region in ['title', 'leading']) {
        final badge = find.byKey(
          ValueKey('super-app-bar-badge-content-$region'),
        );
        final scale = tester.widget<AnimatedScale>(
          find.ancestor(of: badge, matching: find.byType(AnimatedScale)),
        );
        expect(scale.scale, 1);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('migrated slot aliases remain removable by instance ID', (
    tester,
  ) async {
    final registry = Registry();
    await mount(
      SuperPage(
        appBar: SuperAppBar(
          title: const Text('Alias heading'),
          nativeConfig: NativeComponentConfig(
            placements: {
              'title': ['alias'],
            },
            slotTypes: {'alias': 'title'},
          ),
        ),
      ),
      tester,
      registry,
    );
    StyleEditScope.controllerOf(tester.element(find.byType(SuperAppBar)))!
            .value =
        true;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.text('Alias heading')) + const Offset(3, 3),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('style-menu-remove-Taille et marge préférées : title'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      registry.nativeComponentController('root-appBar').value.slotsOf('title'),
      isEmpty,
    );
    expect(find.text('Alias heading'), findsNothing);
    expect(
      find.byKey(const ValueKey('super-app-bar-add-title')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit native switches suppress automatically implied Scaffold controls',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(
          appBar: SuperAppBar(title: Text('Heading')),
          drawer: Drawer(child: Text('Left')),
          endDrawer: Drawer(child: Text('Right')),
        ),
        tester,
        registry,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).automaticallyImplyLeading,
        isTrue,
      );
      expect(find.byIcon(Icons.menu), findsNWidgets(2));
      final controller = registry.nativeComponentController('root-appBar');
      controller.value = controller.value
          .withRegionEnabled('leading', false)
          .withRegionEnabled('actions', false);
      await tester.pumpAndSettle();
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.automaticallyImplyLeading, isFalse);
      expect(bar.actions, isEmpty);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'navigation preference survives native mutations JSON transfer and reset',
    () {
      final config = NativeComponentConfig(
        properties: const {'useDefaultNavigation': true},
        placements: {
          'leading': ['a'],
        },
        slotTypes: {'a': 'factory:A'},
      );
      final mutations = [
        config.withRegionEnabled('title', true),
        config.withSlotAdded('b', 'title'),
        config.withSlotMoved('a', 'title'),
        config.withoutSlot('a'),
        config.withSlotSize('a', const Size(30, 30)),
        config.withSlotSizeConstraints('a', const SlotSizeConstraints()),
      ];
      for (final value in mutations) {
        expect(value.useDefaultNavigation, isTrue);
        expect(
          NativeComponentConfig.fromJson(value.toJson()).useDefaultNavigation,
          isTrue,
        );
      }
      expect(config.withDefaultNavigation(false).useDefaultNavigation, isFalse);
      expect(
        NativeComponentConfig.fromJson({'placements': {}}).useDefaultNavigation,
        isNull,
      );
      expect(
        () => NativeComponentConfig.fromJson({
          'placements': {},
          'useDefaultNavigation': 'yes',
        }),
        throwsFormatException,
      );
      final appearance = Appearance(components: {'bar': config});
      final restored = AppearanceStore.decode(
        AppearanceStore.encode(appearance),
      );
      expect(restored.nativeComponent('bar').useDefaultNavigation, isTrue);
      final exported = AppearanceTransfer.export(appearance, {
        TransferGroup.layouts,
      });
      final imported = AppearanceTransfer.import(Appearance(), exported, {
        TransferGroup.layouts,
      });
      expect(imported.nativeComponent('bar').useDefaultNavigation, isTrue);
      expect(imported.resetLayouts().components, isEmpty);
    },
  );

  testWidgets(
    'default navigation keeps drawer button in editing and hides navigation zone',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(
          appBar: SuperAppBar(title: Text('Heading')),
          drawer: Drawer(child: Text('Drawer contents')),
        ),
        tester,
        registry,
      );
      final context = tester.element(find.byType(SuperAppBar));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperAppBar),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      expect(editor.enabled('leading'), isFalse);
      expect(find.byType(DrawerButton), findsOneWidget);
      await tester.tap(find.byType(DrawerButton));
      await tester.pumpAndSettle();
      expect(
        Scaffold.of(tester.element(find.byType(AppBar))).isDrawerOpen,
        isTrue,
      );
      Scaffold.of(tester.element(find.byType(AppBar))).closeDrawer();
      await tester.pumpAndSettle();
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();
      unawaited(editor.configure());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('super-app-bar-default-navigation')),
            )
            .value,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-switch-leading')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('super-app-bar-default-navigation')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-switch-leading')),
        findsOneWidget,
      );
      expect(find.byType(DrawerButton), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('super-app-bar-switch-leading')),
      );
      await tester.tap(
        find.byKey(const ValueKey('super-app-bar-switch-leading')),
      );
      await tester.pumpAndSettle();
      expect(editor.enabled('leading'), isTrue);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      history.undo();
      await tester.pumpAndSettle();
      expect(find.byType(DrawerButton), findsOneWidget);
      expect(editor.enabled('leading'), isFalse);
      history.redo();
      await tester.pumpAndSettle();
      expect(find.byType(DrawerButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native navigation hides custom slots without losing their configuration',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(
          appBar: SuperAppBar(leading: Text('Custom navigation')),
          drawer: Drawer(),
        ),
        tester,
        registry,
      );
      expect(find.text('Custom navigation'), findsOneWidget);
      final config = registry.nativeComponentController('root-appBar');
      config.value = config.value.withDefaultNavigation(true);
      await tester.pumpAndSettle();
      expect(find.text('Custom navigation'), findsNothing);
      expect(find.byType(DrawerButton), findsOneWidget);
      expect(config.value.slotsOf('leading'), ['leading']);
      config.value = config.value.withDefaultNavigation(false);
      await tester.pumpAndSettle();
      expect(find.text('Custom navigation'), findsOneWidget);
      expect(find.byType(DrawerButton), findsNothing);
    },
  );

  testWidgets(
    'default navigation retains Flutter back behavior without a drawer',
    (tester) async {
      final registry = Registry();
      await mount(const SuperPage(child: Text('Home')), tester, registry);
      final navigator = Navigator.of(tester.element(find.text('Home')));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const SuperPage(
              id: 'details',
              appBar: SuperAppBar(title: Text('Details')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SuperAppBar));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing another native region preserves child state and percentage sizes',
    (tester) async {
      final registry = Registry();
      await mount(
        SuperPage(
          appBar: SuperAppBar(
            title: const TextField(key: ValueKey('stateful-title')),
            action: const SizedBox(
              key: ValueKey('sized-action'),
              width: 20,
              height: 20,
            ),
            nativeConfig: NativeComponentConfig(
              placements: {
                'title': ['title'],
                'actions': ['action'],
              },
              slotSizeConstraints: {
                'action': const SlotSizeConstraints(
                  preferredWidth: SlotDimension(20, SlotSizeUnit.percent),
                  percentBasis: SlotPercentBasis.layout,
                ),
              },
            ),
          ),
        ),
        tester,
        registry,
      );
      await tester.enterText(
        find.byKey(const ValueKey('stateful-title')),
        'Preserved',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('slot-item-action'))).width,
        closeTo(160, .1),
      );
      final controller = registry.nativeComponentController('root-appBar');
      controller.value = controller.value.withRegionEnabled(
        'flexibleSpace',
        true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Preserved'), findsOneWidget);
      controller.value = controller.value.withRegionEnabled(
        'flexibleSpace',
        false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Preserved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'registered native AppBar instances propagate edited preferred heights',
    (tester) async {
      final registry = Registry()..bootstrap();
      await mount(
        SuperPage(
          pageConfig: ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.appBar: ['created-bar'],
              ScaffoldPageRegion.body: ['scaffold:body'],
            },
            slotTypes: {'created-bar': 'factory:AppBar'},
          ),
          child: const Text('Remaining body'),
        ),
        tester,
        registry,
      );
      expect(tester.getTopLeft(find.text('Remaining body')).dy, 56);
      final controller = registry.nativeComponentController('created-bar');
      controller.value = controller.value
          .withSlotAdded('tab-item', 'bottom', type: 'factory:Card')
          .withSlotSize('tab-item', const Size(double.infinity, 40));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Remaining body')).dy, 96);
      expect(tester.getSize(find.byType(AppBar)).height, 96);
      controller.value = controller.value.withRegionEnabled('bottom', false);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Remaining body')).dy, 56);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native size editor validates dimensions and persists the result',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(appBar: SuperAppBar(title: Text('Sized heading'))),
        tester,
        registry,
      );
      StyleEditScope.controllerOf(tester.element(find.byType(SuperAppBar)))!
              .value =
          true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.text('Sized heading')) + const Offset(3, 3),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : title'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '-1',
      );
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Saisissez une dimension positive en pixels ou en %.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '120',
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-height')),
        '40',
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-min-width')),
        '80',
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-max-width')),
        '200',
      );
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        registry
            .nativeComponentController('root-appBar')
            .value
            .slotSizeConstraints['title'],
        const SlotSizeConstraints(
          minWidth: SlotDimension(80, SlotSizeUnit.pixels),
          preferredWidth: SlotDimension(120, SlotSizeUnit.pixels),
          preferredHeight: SlotDimension(40, SlotSizeUnit.pixels),
          maxWidth: SlotDimension(200, SlotSizeUnit.pixels),
          percentBasis: SlotPercentBasis.layout,
        ),
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final fromRegistry in [false, true]) {
    testWidgets(
      'empty AppBar exposes configuration and breadcrumbs (${fromRegistry ? 'catalog' : 'provided'})',
      (tester) async {
        final registry = Registry()..bootstrap();
        await mount(
          fromRegistry
              ? SuperPage(
                  pageConfig: ScaffoldPageConfig(
                    placements: {
                      ScaffoldPageRegion.appBar: ['empty-bar'],
                      ScaffoldPageRegion.body: ['scaffold:body'],
                    },
                    slotTypes: {'empty-bar': 'factory:AppBar'},
                  ),
                )
              : const SuperPage(appBar: SuperAppBar()),
          tester,
          registry,
        );
        StyleEditScope.controllerOf(tester.element(find.byType(SuperPage)))!
                .value =
            true;
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('style-edit-banner-drag')),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();
        final bar = find.byType(AppBar);
        await tester.tapAt(tester.getTopLeft(bar) + const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value, ['Page', 'AppBar']);
        for (var level = 0; level < 2; level++) {
          await tester.pump(const Duration(seconds: 1));
          final point = tester.getTopLeft(bar) + const Offset(8, 8);
          await tester.tapAt(point);
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tapAt(point);
          await tester.pumpAndSettle();
        }
        expect(LayoutSelection.path.value, ['Page', 'AppBar', 'AppBar']);
        expect(
          find.byKey(const ValueKey('scaffold-page-add-appBar')),
          findsNothing,
        );
        await tester.tapAt(
          tester.getTopLeft(bar) + const Offset(8, 8),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        final configure = find.byKey(
          const ValueKey('style-menu-Configurer la barre'),
        );
        expect(configure, findsOneWidget);
        expect(
          find.descendant(of: configure, matching: find.text('AppBar')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('style-menu-AppBar')), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: configure,
            matching: find.text('Configurer la barre'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('super-app-bar-settings')),
          findsOneWidget,
        );
        final toggle = find.byKey(const ValueKey('super-app-bar-switch-title'));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Appliquer'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('super-app-bar-add-title')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('super-app-bar-add-title')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('super-app-bar-add-slot-factory:Card')),
        );
        await tester.pumpAndSettle();
        final controller = registry.nativeComponentController(
          fromRegistry ? 'empty-bar' : 'root-appBar',
        );
        expect(controller.value.slotsOf('title'), hasLength(1));
        expect(
          controller.value.slotTypeOf(controller.value.slotsOf('title').single),
          'factory:Card',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'free bottom bar uses native bounded regions and preserves callbacks',
    (tester) async {
      final registry = Registry();
      var taps = 0;
      await mount(
        SuperPage(
          bottomNavigationBar: SuperBottomAppBar(
            left: TextButton(
              onPressed: () => taps++,
              child: const Text('Home'),
            ),
            center: const Text('Status'),
            right: const Text('Tools'),
          ),
          child: const SizedBox.expand(key: ValueKey('bottom-bar-body')),
        ),
        tester,
        registry,
      );
      expect(find.byType(BottomAppBar), findsOneWidget);
      expect(find.byType(RegisteredSuperLayout), findsNothing);
      expect(tester.getSize(find.byType(BottomAppBar)).height, 56);
      expect(
        tester.getSize(find.byKey(const ValueKey('bottom-bar-body'))).height,
        544,
      );
      await tester.tap(find.text('Home'));
      expect(taps, 1);
      final controller = registry.nativeComponentController(
        'root-bottomAppBar',
      );
      controller.value = controller.value.withRegionEnabled('center', false);
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsNothing);
      expect(controller.value.slotsOf('center'), ['center']);
      final restored = AppearanceStore.decode(
        AppearanceStore.encode(
          AppearanceScope.of(tester.element(find.byType(SuperBottomAppBar))),
        ),
      );
      expect(
        restored.nativeComponent('root-bottomAppBar').isEnabled('center'),
        isFalse,
      );
      controller.value = controller.value.withRegionEnabled('center', true);
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog bottom bar exposes settings, adds multiple slots and undoes removal',
    (tester) async {
      final registry = Registry()..bootstrap();
      await mount(
        SuperPage(
          pageConfig: ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: ['scaffold:body'],
              ScaffoldPageRegion.bottomNavigationBar: ['free-bar'],
            },
            slotTypes: {'free-bar': 'factory:BottomAppBar'},
          ),
        ),
        tester,
        registry,
      );
      final pageContext = tester.element(find.byType(SuperPage));
      final history = EditorHistoryScope.controllerOf(pageContext)!;
      StyleEditScope.controllerOf(pageContext)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      final bar = find.byType(BottomAppBar);
      await tester.tapAt(
        tester.getTopLeft(bar) + const Offset(4, 4),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.take(3), [
        'Page',
        'Barre basse',
        'Barre basse',
      ]);
      expect(
        find.byKey(const ValueKey('scaffold-page-add-bottomNavigationBar')),
        findsNothing,
      );
      final settings = find.byKey(
        const ValueKey('style-menu-Configurer la barre basse'),
      );
      await tester.tap(
        find.descendant(
          of: settings,
          matching: find.text('Configurer la barre basse'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      final toggle = find.byKey(
        const ValueKey('super-bottom-app-bar-switch-right'),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-bottom-app-bar-add-right')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('super-bottom-app-bar-add-left')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('super-bottom-app-bar-add-slot-factory:Card'),
        ),
      );
      await tester.pumpAndSettle();
      final controller = registry.nativeComponentController('free-bar');
      final ids = controller.value.slotsOf('left');
      expect(ids, hasLength(1));
      expect(ids.toSet(), hasLength(1));
      expect(
        find.byKey(const ValueKey('super-bottom-app-bar-add-left')),
        findsNothing,
      );
      expect(tester.getSize(find.byType(BottomAppBar)).height, 56);
      final slot = find.byKey(ValueKey('slot-item-${ids.last}'));
      await tester.tapAt(
        tester.getTopLeft(slot) + const Offset(2, 2),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-remove-Taille et marge préférées : Card'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('left'), [ids.first]);
      history.undo();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('left'), ids);
      history.redo();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('left'), [ids.first]);
      LayoutSelection.select(['Page']);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-bottom-app-bar-add-left')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-bottomNavigationBar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog bottom bar includes the native bottom safe area', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    await mount(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(bottom: 24),
        ),
        child: SuperPage(
          pageConfig: ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: ['scaffold:body'],
              ScaffoldPageRegion.bottomNavigationBar: ['safe-bar'],
            },
            slotTypes: {'safe-bar': 'factory:BottomAppBar'},
          ),
          child: const SizedBox.expand(key: ValueKey('safe-body')),
        ),
      ),
      tester,
      registry,
    );
    expect(tester.getSize(find.byType(BottomAppBar)).height, 80);
    expect(tester.getSize(find.byKey(const ValueKey('safe-body'))).height, 520);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Action button in AppBar actions keeps its natural text width', (
    tester,
  ) async {
    const exportedJson = '''
{
  "format": "super_container_layout.appearance",
  "version": 1,
  "groups": ["styles", "layouts"],
  "data": {
    "mode": "light",
    "accent": 4283590873,
    "backgroundOpacity": 1.0,
    "windowOpacity": 1.0,
    "windowEffect": "transparent",
    "styles": {},
    "components": {
      "root": {
        "type": "native",
        "regions": {"appBar": true},
        "placements": {
          "body": [{"id": "scaffold:body", "type": "scaffold:body"}],
          "appBar": [{"id": "ErYewU1iY5", "type": "factory:ApplicationBar"}]
        }
      },
      "ErYewU1iY5": {
        "type": "native",
        "regions": {"actions": true},
        "placements": {
          "actions": [{"id": "HjcJAptQol", "type": "factory:Action"}]
        }
      }
    },
    "behaviors": {},
    "pageCatalog": {"pages": [], "homePageId": null}
  }
}
''';
    final imported = AppearanceTransfer.import(Appearance(), exportedJson, {
      TransferGroup.styles,
      TransferGroup.layouts,
    });
    final store = AppearanceStore();
    await store.save(imported);
    final registry = Registry()..bootstrap();
    await mount(
      const SuperPage(child: Text('Body')),
      tester,
      registry,
      store: store,
    );
    final buttonFinder = find.byKey(
      const ValueKey('super-action-button-HjcJAptQol'),
    );
    final labelFinder = find.byKey(
      const ValueKey('super-action-label-HjcJAptQol'),
    );
    expect(buttonFinder, findsOneWidget);
    expect(labelFinder, findsOneWidget);
    expect(tester.getSize(buttonFinder).width, greaterThan(80));
    expect(tester.getSize(labelFinder).width, greaterThan(30));
    expect(
      tester.getCenter(buttonFinder).dy,
      closeTo(tester.getCenter(find.byType(AppBar)).dy, 1.0),
    );
    expect(tester.takeException(), isNull);
  });

  test('NativePropertyDescriptor serializes to/from JSON and NativeComponentConfig stores flat properties', () {
    final jsonList = NativePropertyDescriptor.listToJson(
      SuperAppBar.propertyDescriptors,
    );
    final roundTripped = NativePropertyDescriptor.listFromJson(jsonList);
    expect(roundTripped, SuperAppBar.propertyDescriptors);

    final config = NativeComponentConfig.fromJson({
      'placements': <String, Object>{},
      'regions': {'title': true},
      'backgroundColor': '#1E293B',
      'foregroundColor': '#FFFFFF',
      'elevation': 6,
      'toolbarHeight': 72,
      'centerTitle': true,
      'clipBehavior': 'antiAlias',
      'systemOverlayStyle': 'light',
    });
    expect(config.colorProperty('backgroundColor'), const Color(0xFF1E293B));
    expect(config.colorProperty('foregroundColor'), const Color(0xFFFFFFFF));
    expect(config.doubleProperty('elevation'), 6.0);
    expect(config.doubleProperty('toolbarHeight'), 72.0);
    expect(config.boolProperty('centerTitle'), isTrue);
    expect(config.stringProperty('clipBehavior'), 'antiAlias');
    expect(config.stringProperty('systemOverlayStyle'), 'light');

    final serialized = config.toJson();
    expect(serialized['backgroundColor'], '#1E293B');
    expect(serialized['elevation'], 6.0);
    expect(serialized['toolbarHeight'], 72.0);
    expect(serialized['centerTitle'], isTrue);

    final patched = config.patchFromJson({
      'backgroundColor': null,
      'elevation': 12,
    });
    expect(patched.colorProperty('backgroundColor'), isNull);
    expect(patched.toJson().containsKey('backgroundColor'), isFalse);
    expect(patched.doubleProperty('elevation'), 12.0);

    final withDirectColor = patched.withProperty(
      'backgroundColor',
      const Color(0xFF38BDF8),
    );
    expect(
      withDirectColor.colorProperty('backgroundColor'),
      const Color(0xFF38BDF8),
    );
    expect(withDirectColor.toJson()['backgroundColor'], '#38BDF8');
  });

  testWidgets(
    'SuperAppBar applies Flutter style properties and edits them through generic property controls',
    (tester) async {
      final registry = Registry();
      await mount(
        SuperPage(
          appBar: SuperAppBar(
            id: 'styled-bar',
            title: const Text('Styled Heading'),
            nativeConfig: NativeComponentConfig.fromJson({
              'placements': {
                'title': ['title'],
              },
              'backgroundColor': '#1E293B',
              'foregroundColor': '#F8FAFC',
              'elevation': 8,
              'toolbarHeight': 72,
              'centerTitle': true,
              'clipBehavior': 'antiAlias',
              'systemOverlayStyle': 'light',
            }),
          ),
          child: const Text('Body below bar'),
        ),
        tester,
        registry,
      );

      var appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFF1E293B));
      expect(appBar.foregroundColor, const Color(0xFFF8FAFC));
      expect(appBar.elevation, 8.0);
      expect(appBar.toolbarHeight, 72.0);
      expect(appBar.centerTitle, isTrue);
      expect(appBar.clipBehavior, Clip.antiAlias);
      expect(appBar.systemOverlayStyle, SystemUiOverlayStyle.light);
      expect(tester.getTopLeft(find.text('Body below bar')).dy, 72.0);

      final context = tester.element(find.byType(SuperAppBar));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperAppBar),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      unawaited(editor.configure());
      await tester.pumpAndSettle();

      final centerTitleSwitch = find.byKey(
        const ValueKey('super-app-bar-prop-centerTitle'),
      );
      await tester.ensureVisible(centerTitleSwitch);
      await tester.pumpAndSettle();
      await tester.tap(centerTitleSwitch);
      await tester.pumpAndSettle();

      appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isFalse);

      final resetBg = find.byKey(
        const ValueKey('super-app-bar-prop-reset-backgroundColor'),
      );
      await tester.ensureVisible(resetBg);
      await tester.pumpAndSettle();
      await tester.tap(resetBg);
      await tester.pumpAndSettle();

      appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, isNull);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFF1E293B));
      expect(appBar.centerTitle, isTrue);

      unawaited(editor.configure());
      await tester.pumpAndSettle();

      final shapeTile = find.byKey(const ValueKey('super-app-bar-prop-shape'));
      await tester.ensureVisible(shapeTile);
      await tester.pumpAndSettle();
      await tester.tap(shapeTile);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-app-bar-shape-shape-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('super-app-bar-shape-shape-independent-corners'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('super-app-bar-shape-shape-apply')),
      );
      await tester.pumpAndSettle();

      appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.shape, isA<RoundedRectangleBorder>());

      await tester.tap(find.text('Réinitialiser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, isNull);
      expect(appBar.elevation, isNull);
      expect(appBar.centerTitle, isNull);
      expect(appBar.shape, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SuperAppBar centerTitle centers a SuperValue placed in the title region',
    (tester) async {
      final registry = Registry()..bootstrap();
      final store = AppearanceStore();
      await store.save(
        Appearance(
          components: {
            'root': ScaffoldPageConfig.fromJson({
              'regions': {'appBar': true, 'body': true},
              'placements': {
                'appBar': [
                  {'id': 'main-appbar', 'type': 'registry:ApplicationBar'},
                ],
                'body': [
                  {'id': 'scaffold:body', 'type': 'scaffold:body'},
                ],
              },
            }),
            'main-appbar': NativeComponentConfig.fromJson({
              'centerTitle': true,
              'regions': {'title': true},
              'placements': {
                'title': [
                  {'id': 'app-title', 'type': 'registry:Value'},
                ],
              },
            }),
            'app-title': const SuperValueConfig(initialText: 'Titre Centré'),
          },
        ),
      );
      await mount(
        const SuperPage(child: Text('Body')),
        tester,
        registry,
        store: store,
      );

      final titleFinder = find.text('Titre Centré');
      expect(titleFinder, findsOneWidget);
      final appBarCenter = tester.getCenter(find.byType(AppBar)).dx;
      expect(tester.getCenter(titleFinder).dx, closeTo(appBarCenter, 1.0));
      expect(tester.getTopLeft(titleFinder).dx, greaterThan(200));

      final controller = registry.nativeComponentController('main-appbar');
      controller.value = controller.value.withProperty('centerTitle', false);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(titleFinder).dx, closeTo(0, 1.0));
      expect(tester.takeException(), isNull);
    },
  );
}
