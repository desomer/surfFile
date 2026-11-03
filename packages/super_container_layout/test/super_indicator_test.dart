import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    StyleEditorPanel.preferredDense = false;
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

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );

  Future<void> mount(
    WidgetTester tester,
    Registry registry,
    Widget page, {
    JsonRepositoryStore? repositoryStore,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => page)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(
        router: router,
        registry: registry,
        repositoryStore: repositoryStore,
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'SuperIndicatorConfig serializes, patches, validates and resolves states',
    () {
      final config = SuperIndicatorConfig(
        icon: 'info',
        iconPosition: SuperIndicatorIconPosition.trailing,
        iconSize: 22,
        iconSpacing: 8,
        label: 'Info',
        tooltip: 'Détail du statut',
        enabled: true,
        fontFamily: 'Roboto',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        italic: true,
        color: const Color(0xFF112233),
        iconColor: const Color(0xFF445566),
        backgroundColor: const Color(0xFFAA00BB),
        borderColor: const Color(0xFFCC00DD),
        radius: 12,
        borderWidth: 2,
        elevation: 3,
        horizontalPadding: 14,
        verticalPadding: 6,
        textAlign: TextAlign.end,
        letterSpacing: 0.5,
        style: const ContainerStyle(hoverEffect: true),
        propertyBindings: const {
          SuperIndicatorProperty.tooltip: JsonTextBinding(
            repositoryId: '0123456789abcdef0123456789abcdef',
            path: 'item.tooltip',
          ),
        },
        states: IndicatorConfigStates(
          binding: const JsonTextBinding(
            repositoryId: '0123456789abcdef0123456789abcdef',
            path: 'item.status',
          ),
          named: const {
            'ok': SuperIndicatorConfig(
              icon: 'check_circle',
              iconColor: Color(0xFF2E7D32),
              label: 'Validé',
            ),
            'error': SuperIndicatorConfig(
              icon: 'error',
              iconColor: Color(0xFFC62828),
              label: 'Erreur',
            ),
          },
          namedProperties: const {
            'ok': {
              IndicatorStateProperty.icon,
              IndicatorStateProperty.iconColor,
              IndicatorStateProperty.textLabel,
            },
            'error': {
              IndicatorStateProperty.icon,
              IndicatorStateProperty.iconColor,
              IndicatorStateProperty.textLabel,
            },
          },
          hover: IndicatorConfigOverride(
            config: const SuperIndicatorConfig(iconSize: 28),
            properties: const {IndicatorStateProperty.iconSize},
          ),
          selected: IndicatorConfigOverride(
            config: const SuperIndicatorConfig(
              backgroundColor: Color(0xFFE3F2FD),
            ),
            properties: const {IndicatorStateProperty.backgroundColor},
          ),
          automatic: {
            AutomaticState.contentHover: IndicatorConfigOverride(
              config: const SuperIndicatorConfig(elevation: 6),
              properties: const {IndicatorStateProperty.elevation},
            ),
            AutomaticState.disabled: IndicatorConfigOverride(
              config: const SuperIndicatorConfig(icon: 'lock'),
              properties: const {IndicatorStateProperty.icon},
            ),
          },
        ),
      );

      final json = config.toJson();
      expect(SuperIndicatorConfig.fromJson(json), config);

      final compact = config.toCompactJson();
      expect(SuperIndicatorConfig.fromJson(compact), config);

      // Resolve named + standard states
      final resolvedOk = config.states!.resolve(
        config,
        name: 'ok',
        isHovered: true,
        isSelected: true,
        activeStates: const {AutomaticState.contentHover},
      );
      expect(resolvedOk.icon, 'check_circle');
      expect(resolvedOk.iconColor, const Color(0xFF2E7D32));
      expect(resolvedOk.label, 'Validé');
      expect(resolvedOk.iconSize, 28);
      expect(resolvedOk.backgroundColor, const Color(0xFFE3F2FD));
      expect(resolvedOk.elevation, 6);

      final resolvedDisabled = config.states!.resolve(
        config,
        name: 'error',
        activeStates: const {AutomaticState.disabled},
      );
      expect(resolvedDisabled.icon, 'lock');
      expect(resolvedDisabled.label, 'Erreur');

      final patched = config.patchFromJson({
        'icon': 'warning',
        'label': 'Attention',
        'enabled': false,
      });
      expect(patched.icon, 'warning');
      expect(patched.label, 'Attention');
      expect(patched.enabled, isFalse);

      expect(
        () => SuperIndicatorConfig(icon: 'unknown_icon').validate(),
        throwsArgumentError,
      );
      expect(
        () => SuperIndicatorConfig(iconSize: 0).validate(),
        throwsArgumentError,
      );
      expect(
        () => SuperIndicatorConfig(radius: -1).validate(),
        throwsArgumentError,
      );
    },
  );

  testWidgets(
    'SuperIndicator renders icon, label, badge surface and reacts to hover / named states from repository',
    (tester) async {
      late Directory tempDir;
      late JsonRepositoryStore repoStore;
      late String repoId;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'super_indicator_repo_',
        );
        repoStore = JsonRepositoryStore(tempDir);
        await repoStore.create('Main');
        repoId = await repoStore.idOf('Main');
        await repoStore.writeAttribute(
          JsonTextBinding(repositoryId: repoId, path: 'server.status'),
          'online',
          expectedValue: null,
        );
        await repoStore.writeAttribute(
          JsonTextBinding(repositoryId: repoId, path: 'server.label'),
          'Serveur Actif',
          expectedValue: null,
        );
      });
      addTearDown(() async {
        repoStore.dispose();
        await tempDir.delete(recursive: true);
      });

      final config = SuperIndicatorConfig(
        icon: 'help',
        label: 'Inconnu',
        radius: 16,
        backgroundColor: const Color(0xFFEEEEEE),
        propertyBindings: {
          SuperIndicatorProperty.label: JsonTextBinding(
            repositoryId: repoId,
            path: 'server.label',
          ),
        },
        states: IndicatorConfigStates(
          binding: JsonTextBinding(repositoryId: repoId, path: 'server.status'),
          named: const {
            'online': SuperIndicatorConfig(
              icon: 'check_circle',
              iconColor: Color(0xFF2E7D32),
            ),
            'offline': SuperIndicatorConfig(
              icon: 'error',
              iconColor: Color(0xFFC62828),
            ),
          },
          namedProperties: const {
            'online': {
              IndicatorStateProperty.icon,
              IndicatorStateProperty.iconColor,
            },
            'offline': {
              IndicatorStateProperty.icon,
              IndicatorStateProperty.iconColor,
            },
          },
          hover: IndicatorConfigOverride(
            config: const SuperIndicatorConfig(icon: 'verified'),
            properties: const {IndicatorStateProperty.icon},
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          JsonRepositoryScope(
            store: repoStore,
            child: host(SuperIndicator(id: 'status-ind', config: config)),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      expect(find.byType(StyledSurface), findsOneWidget);
      expect(find.text('Serveur Actif'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      // Switch repository state to 'offline'
      await tester.runAsync(() async {
        await repoStore.writeAttribute(
          JsonTextBinding(repositoryId: repoId, path: 'server.status'),
          'offline',
          expectedValue: 'online',
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Hover over the indicator triggers the hover override ('verified')
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(SuperIndicator)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'SuperIndicator editor updates config, supports undo/redo and persists in Appearance',
    (tester) async {
      final registry = Registry()..bootstrap(availableFontFamilies: ['Roboto']);
      await mount(
        tester,
        registry,
        const SuperPage(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 80),
              child: SizedBox(
                width: 320,
                child: SuperIndicator(
                  id: 'persisted-indicator',
                  config: SuperIndicatorConfig(
                    icon: 'info',
                    label: 'Statut Initial',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      StyleEditScope.controllerOf(tester.element(find.byType(SuperIndicator)))!
              .value =
          true;
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SuperIndicator));
      final history = EditorHistoryScope.controllerOf(context)!;
      final appearance = AppearanceScope.controllerOf(context)!;
      final design = registry.indicatorController('persisted-indicator');

      await tester.tap(
        find.byType(SuperIndicator),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Indicator'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-indicator-settings')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('super-indicator-setting-label')),
        'Statut Modifié',
      );
      await tester.pumpAndSettle();

      expect(find.text('Statut Modifié'), findsWidgets);
      expect(history.canUndo, isFalse);

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      expect(design.value.label, 'Statut Modifié');
      expect(history.canUndo, isTrue);

      final store = AppearanceStore();
      await store.save(appearance.value);
      expect(
        (await store.load())
            .tryComponent<SuperIndicatorConfig>('persisted-indicator')
            ?.label,
        'Statut Modifié',
      );

      history.undo();
      await tester.pumpAndSettle();
      expect(design.value.label, 'Statut Initial');

      history.redo();
      await tester.pumpAndSettle();
      expect(design.value.label, 'Statut Modifié');
    },
  );

  test('AppearanceCodec, JsonComponentType and EditorPageGraph handle Indicator components', () {
    expect(JsonComponentType.normalize('Indicator'), 'registry:Indicator');
    expect(JsonComponentType.normalize('SuperIndicator'), 'registry:Indicator');
    expect(JsonComponentType.normalize('Icon'), 'registry:Indicator');
    expect(JsonComponentType.shortName('registry:Indicator'), 'Indicator');

    final registry = Registry()..bootstrap();
    final appearance = const AppearanceCodec().fromJson({
      'version': 1,
      'components': {
        'home': {
          'type': 'native',
          'regions': {'body': true},
          'placements': {
            'body': [
              {'id': 'home-body', 'type': 'registry:Layout'},
            ],
          },
        },
        'home-body': {
          'type': 'layout',
          'placements': {
            'center': [
              {'id': 'ind1', 'type': 'Indicator'},
            ],
          },
        },
        'ind1': {
          'type': 'indicator',
          'icon': 'bolt',
          'label': 'Actif',
          'iconSize': 20,
        },
      },
      'pageCatalog': {
        'pages': [
          {'id': 'home', 'name': 'Accueil', 'path': '/'},
        ],
        'homePageId': null,
      },
    });
    final ind1 = appearance.tryComponent<SuperIndicatorConfig>('ind1');
    expect(ind1, isNotNull);
    expect(ind1!.icon, 'bolt');
    expect(ind1.label, 'Actif');
    expect(ind1.iconSize, 20);

    final duplicated = EditorPageGraph.duplicate(
      appearance: appearance,
      registry: registry,
      sourcePageId: 'home',
      targetPageId: 'copy',
    );
    expect(duplicated.componentsOfType<SuperIndicatorConfig>().length, 2);
  });

  testWidgets('superIndicatorAddConfigurator configures draft in add wizard', (
    tester,
  ) async {
    final registry = Registry()..bootstrap(availableFontFamilies: ['Roboto']);
    final configurator = superIndicatorAddConfigurator(const ['Roboto']);
    var draft = const SuperIndicatorConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => configurator.buildDraft(
              context,
              draft,
              (next) => setState(() => draft = next as SuperIndicatorConfig),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('add-indicator-label')),
      'Badge',
    );
    await tester.pump();
    expect(draft.label, 'Badge');
    expect(configurator.validateDraft(draft), isNull);

    configurator.applyDraft(registry, 'new-ind', draft);
    expect(registry.indicatorController('new-ind').value.label, 'Badge');
  });

  testWidgets(
    'SuperIndicator editor displays visual binding indicators and supports quick clear',
    (tester) async {
      late Directory tempDir;
      late JsonRepositoryStore repoStore;
      late String repoId;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'super_indicator_editor_bind_',
        );
        repoStore = JsonRepositoryStore(tempDir);
        await repoStore.create('Main');
        repoId = await repoStore.idOf('Main');
      });
      addTearDown(() async {
        repoStore.dispose();
        await tempDir.delete(recursive: true);
      });

      SuperIndicatorConfig? saved;
      final initial = SuperIndicatorConfig(
        icon: 'info',
        label: 'Statut',
        propertyBindings: {
          SuperIndicatorProperty.label: JsonTextBinding(
            repositoryId: repoId,
            path: 'ind.label',
          ),
        },
        states: IndicatorConfigStates(
          binding: JsonTextBinding(repositoryId: repoId, path: 'ind.state'),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: JsonRepositoryScope(
            store: repoStore,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await showSuperIndicatorEditor(
                      context: context,
                      config: initial,
                      availableFontFamilies: const ['Roboto'],
                    );
                  },
                  child: const Text('Open Indicator Editor'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Indicator Editor'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-indicator-state-binding-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-indicator-state-binding-banner')),
        findsOneWidget,
      );
      expect(find.text('Lié à : ind.state'), findsOneWidget);

      expect(
        find.byKey(const ValueKey('super-indicator-bind-label-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-indicator-bind-label-bound-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-indicator-bind-label-binding-banner')),
        findsOneWidget,
      );
      expect(find.text('Lié à : ind.label'), findsOneWidget);

      final clearBtn = find.byKey(
        const ValueKey('super-indicator-bind-label-binding-clear'),
      );
      await tester.ensureVisible(clearBtn);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-indicator-bind-label-badge')),
        findsNothing,
      );

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.propertyBindings, isEmpty);
    },
  );
}
