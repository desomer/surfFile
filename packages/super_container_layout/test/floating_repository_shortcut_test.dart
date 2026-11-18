import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late JsonRepositoryStore repositoryStore;
  late String clientsRepoId;
  late String ordersRepoId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    directory = await Directory.systemTemp.createTemp(
      'floating-repo-shortcut-test-',
    );
    repositoryStore = JsonRepositoryStore(directory);
    await repositoryStore.create('Clients');
    clientsRepoId = await repositoryStore.idOf('Clients');
    await repositoryStore.save(
      'Clients',
      '{"titre":"Clients VIP","liste":[{"nom":"Alice"}]}\n',
      expectedText: await repositoryStore.read('Clients'),
    );
    await repositoryStore.create('Commandes');
    ordersRepoId = await repositoryStore.idOf('Commandes');
    await repositoryStore.save(
      'Commandes',
      '{"total":42}\n',
      expectedText: await repositoryStore.read('Commandes'),
    );
  });

  tearDown(() async {
    LayoutSelection.select(const []);
    LayoutSelection.focus.value = null;
    repositoryStore.dispose();
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> pressF1(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'F1 opens floating JSON editor for direct binding, falls back to first bound child (mounted or unmounted), and opens manager when unbound',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final registry = Registry()..bootstrap();
      final appearanceStore = AppearanceStore();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              child: SuperLayout(
                id: 'mainLayout',
                label: 'Main Layout',
                config: const SuperLayoutConfig(
                  west: true,
                  westSize: 220,
                  east: true,
                  eastSize: 220,
                  placements: {
                    SuperLayoutZone.west: ['unbound-slot'],
                    SuperLayoutZone.center: ['parent-card', 'orders-value'],
                    SuperLayoutZone.east: ['tabs-container'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'unbound-slot',
                    label: 'Statique',
                    builder: (_) => const SuperValue(
                      id: 'unbound-slot',
                      config: SuperValueConfig(initialText: 'Sans binding'),
                    ),
                  ),
                  BuilderSlot(
                    id: 'parent-card',
                    label: 'Parent Card',
                    builder: (_) => EditableSurface(
                      id: 'parent-card',
                      label: 'Parent Card',
                      child: SuperLayout(
                        id: 'card-inner-layout',
                        label: 'Card Layout',
                        config: const SuperLayoutConfig(
                          placements: {
                            SuperLayoutZone.center: [
                              'static-header',
                              'client-title',
                              'order-total',
                            ],
                          },
                        ),
                        slots: [
                          BuilderSlot(
                            id: 'static-header',
                            label: 'En-tête',
                            builder: (_) => const SuperValue(
                              id: 'static-header',
                              config: SuperValueConfig(initialText: 'Détails'),
                            ),
                          ),
                          BuilderSlot(
                            id: 'client-title',
                            label: 'Titre Client',
                            builder: (_) => SuperValue(
                              id: 'client-title',
                              config: SuperValueConfig(
                                binding: JsonTextBinding(
                                  repositoryId: clientsRepoId,
                                  path: 'titre',
                                ),
                              ),
                            ),
                          ),
                          BuilderSlot(
                            id: 'order-total',
                            label: 'Total Commande',
                            builder: (_) => SuperValue(
                              id: 'order-total',
                              config: SuperValueConfig(
                                binding: JsonTextBinding(
                                  repositoryId: ordersRepoId,
                                  path: 'total',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  BuilderSlot(
                    id: 'orders-value',
                    label: 'Commande Directe',
                    builder: (_) => SuperValue(
                      id: 'orders-value',
                      config: SuperValueConfig(
                        mode: SuperValueMode.input,
                        binding: JsonTextBinding(
                          repositoryId: ordersRepoId,
                          path: 'total',
                        ),
                      ),
                    ),
                  ),
                  BuilderSlot(
                    id: 'tabs-container',
                    label: 'Onglets',
                    builder: (_) => const SuperTab(id: 'tabs-container'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          registry: registry,
          appearanceStore: appearanceStore,
          repositoryStore: repositoryStore,
        ),
      );
      await tester.pumpAndSettle();

      // Configure 'tabs-container' with an unmounted second tab containing a bound SuperValue.
      final appearance = AppearanceScope.controllerOf(
        tester.element(find.byType(SuperPage)),
      )!;
      appearance.value = appearance.value
          .withTabComponent(
            'tabs-container',
            SuperTabConfig(
              placements: {
                'tabs': const ['tab1', 'tab2'],
                'content:tab1': const [],
                'content:tab2': const ['hidden-tab-value'],
              },
              slotTypes: const {
                'tab1': 'registry:Value',
                'tab2': 'registry:Value',
                'hidden-tab-value': 'registry:Value',
              },
            ),
          )
          .withValueComponent(
            'tab1',
            const SuperValueConfig(initialText: 'Vide'),
          )
          .withValueComponent(
            'tab2',
            const SuperValueConfig(initialText: 'Caché'),
          )
          .withValueComponent(
            'hidden-tab-value',
            SuperValueConfig(
              binding: JsonTextBinding(
                repositoryId: clientsRepoId,
                path: 'titre',
              ),
            ),
          );
      await tester.pumpAndSettle();

      // 1. Outside edit mode with nothing selected/focused -> F1 opens JsonRepositoryManager (no duplicate stacking).
      await pressF1(tester);
      expect(find.byType(JsonRepositoryManager), findsOneWidget);
      await pressF1(tester);
      expect(find.byType(JsonRepositoryManager), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonRepositoryManager), findsNothing);

      // 2. Outside edit mode (runtime): focusing an input SuperValue and pressing F1 opens its bound floating JSON editor.
      await tester.tap(
        find.byKey(const ValueKey('super-value-input-orders-value')),
      );
      await tester.pumpAndSettle();

      // Ctrl + F1 is ignored.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('floating-repository-$ordersRepoId')),
        findsNothing,
      );

      await pressF1(tester);
      final ordersFloating = find.byKey(
        ValueKey('floating-repository-$ordersRepoId'),
      );
      expect(ordersFloating, findsOneWidget);
      final ordersEditorText = tester
          .widget<EditableText>(
            find.descendant(
              of: ordersFloating,
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(jsonDecode(ordersEditorText), {'total': 42});

      await tester.tap(find.byKey(const ValueKey('floating-repository-close')));
      await tester.pumpAndSettle();
      expect(ordersFloating, findsNothing);

      // 3. In edit mode: selecting 'Parent Card' (no direct binding) searches children
      // and opens the FIRST bound child's repository ('Clients', skipping static-header).
      final editMode = StyleEditScope.controllerOf(
        tester.element(find.byType(SuperPage)),
      )!;
      editMode.value = true;
      await tester.pumpAndSettle();

      LayoutSelection.select(const [
        'Page',
        'Corps',
        'Main Layout',
        'Centre',
        'Parent Card',
      ]);
      await tester.pumpAndSettle();

      await pressF1(tester);
      final clientsFloating = find.byKey(
        ValueKey('floating-repository-$clientsRepoId'),
      );
      expect(clientsFloating, findsOneWidget);
      expect(ordersFloating, findsNothing);

      // Pressing F1 again keeps the existing floating editor without duplicating it.
      await pressF1(tester);
      expect(clientsFloating, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('floating-repository-close')));
      await tester.pumpAndSettle();
      expect(clientsFloating, findsNothing);

      // 4. Selecting 'Onglets' (whose bound child is in unmounted tab2) still resolves 'Clients' via persisted childSlots.
      LayoutSelection.select(const [
        'Page',
        'Corps',
        'Main Layout',
        'Est',
        'Onglets',
      ]);
      await tester.pumpAndSettle();

      await pressF1(tester);
      expect(clientsFloating, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('floating-repository-close')));
      await tester.pumpAndSettle();

      // 5. Selecting 'Statique' (no binding on self or children) falls back to JsonRepositoryManager.
      LayoutSelection.select(const [
        'Page',
        'Corps',
        'Main Layout',
        'Ouest',
        'Statique',
      ]);
      await tester.pumpAndSettle();

      await pressF1(tester);
      expect(find.byType(JsonRepositoryManager), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F1 resolves inherited repository binding on a child inside SuperListView',
    (tester) async {
      final registry = Registry()..bootstrap();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              child: SuperLayout(
                id: 'mainLayout',
                label: 'Main Layout',
                config: const SuperLayoutConfig(
                  placements: {
                    SuperLayoutZone.center: ['clients-list'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'clients-list',
                    label: 'Liste Clients',
                    builder: (_) => const SuperListView(id: 'clients-list'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          registry: registry,
          appearanceStore: AppearanceStore(),
          repositoryStore: repositoryStore,
        ),
      );
      await tester.pumpAndSettle();

      final appearance = AppearanceScope.controllerOf(
        tester.element(find.byType(SuperPage)),
      )!;
      appearance.value = appearance.value
          .withListComponent(
            'clients-list',
            SuperListViewConfig(
              binding: JsonTextBinding(
                repositoryId: clientsRepoId,
                path: 'liste',
              ),
              template: const SuperLayoutConfig(
                placements: {
                  SuperLayoutZone.center: ['row-name'],
                },
                slotTypes: {'row-name': 'registry:Value'},
              ),
            ),
          )
          .withValueComponent(
            'row-name',
            const SuperValueConfig(
              // Inherited repositoryId (null) with [?] wildcard path:
              binding: JsonTextBinding(path: 'liste[?].nom'),
            ),
          );
      await tester.pumpAndSettle();

      final editMode = StyleEditScope.controllerOf(
        tester.element(find.byType(SuperPage)),
      )!;
      editMode.value = true;
      await tester.pumpAndSettle();

      final rowSlot = tester
          .stateList<EditorSlotState>(find.byType(EditorSlot))
          .firstWhere((s) => s.effectiveComponentId == 'row-name');
      LayoutSelection.updateActiveFocus(rowSlot.context, id: 'row-name');
      await tester.pumpAndSettle();

      await pressF1(tester);
      expect(
        find.byKey(ValueKey('floating-repository-$clientsRepoId')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('floating-repository-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
