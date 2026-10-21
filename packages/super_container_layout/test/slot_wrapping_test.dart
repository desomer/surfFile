import 'package:flutter/gestures.dart';
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
  const hostKey = ValueKey('wrap-host');
  const dimensions = SlotSizeConstraints(
    preferredWidth: SlotDimension(240, SlotSizeUnit.pixels),
    preferredHeight: SlotDimension(140, SlotSizeUnit.pixels),
    padding: 4,
  );

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

  Future<ValueNotifier<Appearance>> mount(
    WidgetTester tester, {
    required String owner,
    required bool provided,
    ComponentTagFilter filter = const ComponentTagFilter(),
    bool editing = true,
    bool aliased = false,
    String? registeredType,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final registry = Registry()..bootstrap();
    const content = EditorSlot(
      label: 'Source editor',
      child: SizedBox.expand(child: Text('Provided target')),
    );
    const supplied = BuilderSlot(
      id: 'source',
      label: 'Source',
      builder: _providedContent,
    );
    if (registeredType != null) {
      registry.registerComponent(
        'Custom',
        const RegisteredComponent(
          label: 'Registered',
          slotId: 'legacy',
          builder: _providedContent,
          duplication: ComponentDuplicationContract.stateless(),
        ),
      );
    }
    final sourceId = owner == 'surface' ? '__provided-child' : 'source';
    final sourceType =
        registeredType ??
        (provided
            ? aliased
                  ? 'template'
                  : sourceId
            : 'factory:SuperText');
    final suppliedSlots = [
      if (provided)
        if (aliased)
          const BuilderSlot(
            id: 'template',
            label: 'Template',
            builder: _providedContent,
          )
        else
          supplied,
    ];
    final layout = SuperLayoutConfig(
      north: false,
      south: false,
      west: false,
      east: false,
      placements: {
        SuperLayoutZone.center: [sourceId],
      },
      slotTypes: {sourceId: sourceType},
      slotLabels: {sourceId: 'My child'},
      slotSizeConstraints: {sourceId: dimensions},
      positioning: owner == 'grid'
          ? SuperLayoutPositioning.grid
          : SuperLayoutPositioning.zones,
      grid: owner == 'grid'
          ? const GridLayoutConfig(
              compact: false,
              items: {
                'source': GridSlotPosition(x: 2, y: 1, width: 5, height: 4),
              },
            )
          : null,
    );
    final native = NativeComponentConfig(
      placements: {
        owner == 'surface' ? 'child' : 'body': [sourceId],
      },
      slotTypes: {sourceId: sourceType},
      slotLabels: {sourceId: 'My child'},
      slotSizeConstraints: {sourceId: dimensions},
    );
    final layoutController = registry.layoutController(
      'root',
      fallback: layout,
    );
    final nativeController = registry.nativeComponentController(
      'root',
      fallback: native,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                key: hostKey,
                width: 700,
                height: 500,
                child: owner == 'surface'
                    ? EditableSurface(
                        id: 'root',
                        label: 'Root',
                        child: provided ? content : null,
                      )
                    : owner == 'native'
                    ? ValueListenableBuilder<NativeComponentConfig>(
                        valueListenable: nativeController,
                        builder: (_, config, _) => NativeComponentEditor(
                          label: 'Root',
                          keyPrefix: 'wrap-native',
                          settingsTitle: 'Native settings',
                          editSurface: true,
                          registry: registry,
                          config: config,
                          onChanged: (value) => nativeController.value = value,
                          regions: [
                            NativeRegion(
                              'body',
                              'Body',
                              required: true,
                              tagFilter: filter,
                            ),
                          ],
                          slots: suppliedSlots,
                          builder: (_, editor) => editor.region('body'),
                        ),
                      )
                    : ValueListenableBuilder<SuperLayoutConfig>(
                        valueListenable: layoutController,
                        builder: (_, config, _) => SuperLayout(
                          label: 'Root',
                          config: config,
                          onChanged: (value) => layoutController.value = value,
                          zoneTagFilters: {SuperLayoutZone.center: filter},
                          slots: suppliedSlots,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(hostKey));
    final appearance = AppearanceScope.controllerOf(context)!;
    appearance.value = appearance.value.copyWith(
      layouts: owner == 'layout' || owner == 'grid'
          ? {'root': layout}
          : const {},
      nativeComponents: owner == 'native' || owner == 'surface'
          ? {'root': native}
          : const {},
      textComponents: provided
          ? const {}
          : {sourceId: const SuperTextConfig(initialText: 'Saved target')},
    );
    await tester.pumpAndSettle();
    StyleEditScope.controllerOf(context)!.value = editing;
    await tester.pumpAndSettle();
    EditorHistoryScope.controllerOf(context)!.clear();
    return appearance;
  }

  Future<void> openMenu(WidgetTester tester, bool provided) async {
    await tester.tap(
      provided ? find.text('Provided target') : find.byType(SuperText),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseWrapper(WidgetTester tester, String wrapper) async {
    await tester.tap(find.byKey(const ValueKey('style-menu-more-My child')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envelopper dans…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(wrapper));
    await tester.pumpAndSettle();
  }

  for (final owner in ['layout', 'grid', 'native', 'surface']) {
    for (final provided in [true, false]) {
      for (final wrapper in ['SuperContainer', 'SuperLayout']) {
        testWidgets(
          '$owner wraps ${provided ? 'provided' : 'catalog'} in $wrapper',
          (tester) async {
            final appearance = await mount(
              tester,
              owner: owner,
              provided: provided,
            );
            final before = appearance.value;
            final sourceId = owner == 'surface' ? '__provided-child' : 'source';
            await openMenu(tester, provided);
            await chooseWrapper(tester, wrapper);
            expect(tester.takeException(), isNull);
            final after = appearance.value;
            final inLayout = owner == 'layout' || owner == 'grid';
            final id = inLayout
                ? after.layouts['root']!.placedSlotIds.single
                : after
                      .nativeComponents['root']!
                      .placements
                      .values
                      .single
                      .single;
            expect(id, isNot(sourceId));
            expect(
              inLayout
                  ? after.layouts['root']!.slotTypeOf(id)
                  : after.nativeComponents['root']!.slotTypeOf(id),
              wrapper == 'SuperContainer'
                  ? 'registry:NewContainer'
                  : 'registry:NewLayout',
            );
            expect(
              inLayout
                  ? after.layouts['root']!.slotSizeConstraints[id]
                  : after.nativeComponents['root']!.slotSizeConstraints[id],
              same(dimensions),
            );
            if (owner == 'grid') {
              expect(after.layouts['root']!.grid!.items, {
                id: const GridSlotPosition(x: 2, y: 1, width: 5, height: 4),
              });
            }
            if (wrapper == 'SuperContainer') {
              expect(after.nativeComponents[id]!.slotsOf('child'), [sourceId]);
              expect(
                after.nativeComponents[id]!.slotLabels[sourceId],
                'My child',
              );
            } else {
              expect(after.layouts[id]!.placementsOf(SuperLayoutZone.center), [
                sourceId,
              ]);
              expect(after.layouts[id]!.slotLabels[sourceId], 'My child');
            }
            expect(
              provided ? find.text('Provided target') : find.byType(SuperText),
              findsOneWidget,
            );
            expect(after.textComponents, before.textComponents);
            const codec = AppearanceCodec();
            final decoded = codec.fromJson(codec.toJson(after));
            expect(codec.toJson(decoded), codec.toJson(after));
            final history = EditorHistoryScope.controllerOf(
              tester.element(find.byKey(hostKey)),
            )!;
            history.undo();
            await tester.pumpAndSettle();
            expect(appearance.value, same(before));
            expect(history.canUndo, isFalse);
            expect(
              provided ? find.text('Provided target') : find.byType(SuperText),
              findsOneWidget,
            );
            history.redo();
            await tester.pumpAndSettle();
            expect(appearance.value, same(after));
            expect(tester.takeException(), isNull);
            appearance.value = decoded;
            await tester.pumpAndSettle();
            expect(
              provided ? find.text('Provided target') : find.byType(SuperText),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final owner in ['layout', 'surface']) {
    testWidgets('$owner supports successive wrappers around code content', (
      tester,
    ) async {
      final appearance = await mount(tester, owner: owner, provided: true);
      await openMenu(tester, true);
      await chooseWrapper(tester, 'SuperContainer');
      final outer = owner == 'layout'
          ? appearance.value.layouts['root']!.placedSlotIds.single
          : appearance.value.nativeComponents['root']!.slotsOf('child').single;
      await openMenu(tester, true);
      await chooseWrapper(tester, 'SuperLayout');
      final inner = appearance.value.nativeComponents[outer]!
          .slotsOf('child')
          .single;
      expect(
        appearance.value.layouts[inner]!.placedSlotIds.single,
        owner == 'layout' ? 'source' : '__provided-child',
      );
      expect(find.text('Provided target'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'native provided template keeps its instance ID inside a layout',
    (tester) async {
      final appearance = await mount(
        tester,
        owner: 'native',
        provided: true,
        aliased: true,
      );
      await openMenu(tester, true);
      await chooseWrapper(tester, 'SuperLayout');
      final wrapper = appearance.value.nativeComponents['root']!
          .slotsOf('body')
          .single;
      expect(appearance.value.layouts[wrapper]!.placedSlotIds.single, 'source');
      expect(
        appearance.value.layouts[wrapper]!.slotTypeOf('source'),
        'template',
      );
      expect(find.byKey(const ValueKey('slot-source')), findsOneWidget);
      expect(find.text('Provided target'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final type in ['component:legacy', 'registry:Custom', 'legacy']) {
    testWidgets('native registered type $type survives layout wrapping', (
      tester,
    ) async {
      final appearance = await mount(
        tester,
        owner: 'native',
        provided: false,
        registeredType: type,
      );
      await openMenu(tester, true);
      await chooseWrapper(tester, 'SuperLayout');
      expect(find.text('Provided target'), findsOneWidget);
      final registry = SuperApp.of(tester.element(find.byKey(hostKey)))
          .registry!;
      final copy = EditorPageGraph.duplicate(
        appearance: appearance.value,
        registry: registry,
        sourcePageId: 'root',
        targetPageId: 'copy',
      );
      final wrapper = copy.nativeComponents['copy']!.slotsOf('body').single;
      final source = copy.layouts[wrapper]!.placedSlotIds.single;
      expect(source, isNot('source'));
      expect(copy.layouts[wrapper]!.slotTypeOf(source), type);
      expect(tester.takeException(), isNull);
    });
  }

  for (final wrapperType in ['SuperContainer', 'SuperLayout']) {
    testWidgets(
      '$wrapperType preserves catalog configurations during duplication',
      (tester) async {
        final appearance = await mount(
          tester,
          owner: 'native',
          provided: false,
        );
        await openMenu(tester, false);
        await chooseWrapper(tester, wrapperType);
        final registry = SuperApp.of(tester.element(find.byKey(hostKey)))
            .registry!;
        final copy = EditorPageGraph.duplicate(
          appearance: appearance.value,
          registry: registry,
          sourcePageId: 'root',
          targetPageId: 'copy',
        );
        final wrapper = copy.nativeComponents['copy']!.slotsOf('body').single;
        final source = wrapperType == 'SuperContainer'
            ? copy.nativeComponents[wrapper]!.slotsOf('child').single
            : copy.layouts[wrapper]!.placedSlotIds.single;
        expect(source, isNot('source'));
        expect(copy.textComponents[source]!.initialText, 'Saved target');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('removing $wrapperType recursively removes its catalog child', (
      tester,
    ) async {
      final appearance = await mount(tester, owner: 'layout', provided: false);
      await openMenu(tester, false);
      await chooseWrapper(tester, wrapperType);
      final before = appearance.value;
      final wrapper = before.layouts['root']!.placedSlotIds.single;
      await openMenu(tester, false);
      final label = wrapperType == 'SuperContainer'
          ? 'NewContainer'
          : 'NewLayout';
      await tester.tap(
        find.byKey(
          ValueKey('style-menu-remove-Taille et marge préférées : $label'),
        ),
      );
      await tester.pumpAndSettle();
      expect(appearance.value.layouts['root']!.placedSlotIds, isEmpty);
      expect(appearance.value.layouts.containsKey(wrapper), isFalse);
      expect(appearance.value.nativeComponents.containsKey(wrapper), isFalse);
      expect(appearance.value.textComponents.containsKey('source'), isFalse);
      final history = EditorHistoryScope.controllerOf(
        tester.element(find.byKey(hostKey)),
      )!;
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value, same(before));
      expect(find.byType(SuperText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dismissing the overflow menu changes nothing', (tester) async {
    final appearance = await mount(tester, owner: 'layout', provided: true);
    final before = appearance.value;
    await openMenu(tester, true);
    await tester.tap(find.byKey(const ValueKey('style-menu-more-My child')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(appearance.value, same(before));
    expect(tester.takeException(), isNull);
  });

  for (final owner in ['layout', 'native']) {
    testWidgets('$owner only offers compatible wrappers', (tester) async {
      await mount(
        tester,
        owner: owner,
        provided: true,
        filter: const ComponentTagFilter(include: {'container'}),
      );
      await openMenu(tester, true);
      await tester.tap(find.byKey(const ValueKey('style-menu-more-My child')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envelopper dans…'));
      await tester.pumpAndSettle();
      expect(find.text('SuperContainer'), findsOneWidget);
      expect(find.text('SuperLayout'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('read mode has no wrapping menu', (tester) async {
    await mount(tester, owner: 'layout', provided: true, editing: false);
    await openMenu(tester, true);
    expect(find.byTooltip('Autres options'), findsNothing);
    expect(find.text('Envelopper dans…'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _providedContent(BuildContext context) => const EditorSlot(
  label: 'Source editor',
  child: SizedBox.expand(child: Text('Provided target')),
);
