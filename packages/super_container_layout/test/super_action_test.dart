import 'dart:convert';
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

  test('SuperActionConfig serializes, patches and validates', () {
    final config = SuperActionConfig(
      kind: SuperActionKind.textAndIcon,
      variant: SuperActionVariant.outlined,
      label: 'Enregistrer',
      tooltip: 'Sauvegarder les changements',
      icon: 'save',
      iconPosition: SuperActionIconPosition.trailing,
      iconSize: 22,
      iconSpacing: 10,
      enabled: true,
      fontFamily: 'Roboto',
      fontSize: 16,
      fontWeight: FontWeight.w600,
      italic: true,
      color: const Color(0xFF112233),
      iconColor: const Color(0xFF445566),
      backgroundColor: const Color(0xFFAA00BB),
      borderColor: const Color(0xFFCC00DD),
      radius: 14,
      borderWidth: 2,
      elevation: 4,
      horizontalPadding: 20,
      verticalPadding: 12,
      textAlign: TextAlign.end,
      letterSpacing: 0.5,
      style: const ContainerStyle(hoverEffect: true),
      propertyBindings: const {
        SuperActionProperty.label: JsonTextBinding(
          repositoryId: '0123456789abcdef0123456789abcdef',
          path: 'action.label',
        ),
      },
      states: ActionConfigStates(
        hover: ActionConfigOverride(
          config: const SuperActionConfig(label: 'Survolé'),
          properties: const {ActionStateProperty.textLabel},
        ),
      ),
    );

    final json = config.toJson();
    expect(SuperActionConfig.fromJson(json), config);

    final compact = config.toCompactJson();
    expect(SuperActionConfig.fromJson(compact), config);

    final patched = config.patchFromJson({
      'kind': 'icon',
      'icon': 'delete',
      'enabled': false,
    });
    expect(patched.kind, SuperActionKind.icon);
    expect(patched.icon, 'delete');
    expect(patched.enabled, isFalse);
    expect(patched.label, 'Enregistrer');

    expect(
      () => SuperActionConfig(icon: 'unknown_icon').validate(),
      throwsArgumentError,
    );
    expect(
      () => SuperActionConfig(fontSize: 0).validate(),
      throwsArgumentError,
    );
    expect(() => SuperActionConfig(radius: -1).validate(), throwsArgumentError);
  });

  testWidgets(
    'SuperAction renders text, icon and textAndIcon and triggers onPressed',
    (tester) async {
      var clicks = 0;
      await tester.pumpWidget(
        host(
          SuperAction(
            id: 'btn-text',
            config: const SuperActionConfig(
              kind: SuperActionKind.text,
              variant: SuperActionVariant.filled,
              label: 'Valider',
            ),
            onPressed: () => clicks++,
          ),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Valider'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('super-action-button-btn-text')),
      );
      await tester.pump();
      expect(clicks, 1);

      await tester.pumpWidget(
        host(
          SuperAction(
            id: 'btn-icon',
            config: const SuperActionConfig(
              kind: SuperActionKind.icon,
              variant: SuperActionVariant.icon,
              icon: 'add',
            ),
            onPressed: () => clicks++,
          ),
        ),
      );
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('super-action-button-btn-icon')),
      );
      await tester.pump();
      expect(clicks, 2);

      await tester.pumpWidget(
        host(
          SuperAction(
            id: 'btn-both',
            config: const SuperActionConfig(
              kind: SuperActionKind.textAndIcon,
              variant: SuperActionVariant.outlined,
              label: 'Supprimer',
              icon: 'delete',
              enabled: false,
            ),
            onPressed: () => clicks++,
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('super-action-button-btn-both')),
      );
      await tester.pump();
      expect(clicks, 2);
    },
  );

  testWidgets(
    'SuperAction editor updates config, supports undo/redo and persists in Appearance',
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
                child: SuperAction(
                  id: 'persisted-action',
                  config: SuperActionConfig(label: 'Initial Action'),
                ),
              ),
            ),
          ),
        ),
      );

      StyleEditScope.controllerOf(tester.element(find.byType(SuperAction)))!
              .value =
          true;
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SuperAction));
      final history = EditorHistoryScope.controllerOf(context)!;
      final appearance = AppearanceScope.controllerOf(context)!;
      final design = registry.actionController('persisted-action');

      await tester.tap(
        find.byType(SuperAction),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-action-settings')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('super-action-setting-label')),
        'Bouton Modifié',
      );
      await tester.pumpAndSettle();

      // Live preview updates the button on screen before saving
      expect(find.text('Bouton Modifié'), findsWidgets);
      expect(history.canUndo, isFalse);

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      expect(design.value.label, 'Bouton Modifié');
      expect(history.canUndo, isTrue);

      final store = AppearanceStore();
      await store.save(appearance.value);
      expect(
        (await store.load()).tryComponent<SuperActionConfig>('persisted-action')?.label,
        'Bouton Modifié',
      );

      history.undo();
      await tester.pumpAndSettle();
      expect(design.value.label, 'Initial Action');

      history.redo();
      await tester.pumpAndSettle();
      expect(design.value.label, 'Bouton Modifié');
    },
  );

  testWidgets('SuperAction resolves repository property bindings and states', (
    tester,
  ) async {
    late Directory tempDir;
    late JsonRepositoryStore repoStore;
    late String repoId;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('super_action_repo_');
      repoStore = JsonRepositoryStore(tempDir);
      await repoStore.create('Main');
      repoId = (await repoStore.idOf('Main'));
      await repoStore.writeAttribute(
        JsonTextBinding(repositoryId: repoId, path: 'btn.label'),
        'Depuis Repo',
        expectedValue: null,
      );
      await repoStore.writeAttribute(
        JsonTextBinding(repositoryId: repoId, path: 'btn.icon'),
        'star',
        expectedValue: null,
      );
      await repoStore.writeAttribute(
        JsonTextBinding(repositoryId: repoId, path: 'status'),
        'vip',
        expectedValue: null,
      );
    });
    addTearDown(() async {
      repoStore.dispose();
      await tempDir.delete(recursive: true);
    });

    final config = SuperActionConfig(
      kind: SuperActionKind.textAndIcon,
      label: 'Fallback',
      icon: 'add',
      propertyBindings: {
        SuperActionProperty.label: JsonTextBinding(
          repositoryId: repoId,
          path: 'btn.label',
        ),
        SuperActionProperty.icon: JsonTextBinding(
          repositoryId: repoId,
          path: 'btn.icon',
        ),
      },
      states: ActionConfigStates(
        binding: JsonTextBinding(repositoryId: repoId, path: 'status'),
        named: const {
          'vip': SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            variant: SuperActionVariant.tonal,
          ),
        },
        namedProperties: const {
          'vip': {ActionStateProperty.content},
        },
      ),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        JsonRepositoryScope(
          store: repoStore,
          child: host(SuperAction(id: 'bound-action', config: config)),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(find.text('Depuis Repo'), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
  });

  test('ScreenTreeCodec and EditorPageGraph handle Action components', () {
    final registry = Registry()..bootstrap();
    final expanded = ScreenTreeCodec.expandToCanonicalJson({
      'screens': {
        'home': {
          'title': 'Accueil',
          'path': '/',
          'body': {
            'zones': {
              'center': [
                {
                  'id': 'act1',
                  'type': 'Action',
                  'kind': 'textAndIcon',
                  'variant': 'outlined',
                  'label': 'Cliquer',
                  'icon': 'send',
                },
              ],
            },
          },
        },
      },
    });

    final appearance = const AppearanceCodec().fromJson(expanded);
    final act1 = appearance.tryComponent<SuperActionConfig>('act1');
    expect(act1, isNotNull);
    expect(act1!.kind, SuperActionKind.textAndIcon);
    expect(act1.variant, SuperActionVariant.outlined);
    expect(act1.label, 'Cliquer');
    expect(act1.icon, 'send');

    final duplicated = EditorPageGraph.duplicate(
      appearance: appearance,
      registry: registry,
      sourcePageId: 'home',
      targetPageId: 'copy',
    );
    expect(
      duplicated.componentsOfType<SuperActionConfig>().length,
      2,
    );
  });

  testWidgets('superActionAddConfigurator configures draft in add wizard and surface variant renders StyledSurface', (
    tester,
  ) async {
    final registry = Registry()..bootstrap(availableFontFamilies: ['Roboto']);
    final configurator = superActionAddConfigurator(const ['Roboto']);
    var draft = const SuperActionConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => configurator.buildDraft(
              context,
              draft,
              (next) => setState(() => draft = next as SuperActionConfig),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Texte + Icône'));
    await tester.pumpAndSettle();
    expect(draft.kind, SuperActionKind.textAndIcon);

    await tester.enterText(
      find.byKey(const ValueKey('add-action-label')),
      'Nouveau Bouton',
    );
    await tester.pump();
    expect(draft.label, 'Nouveau Bouton');
    expect(configurator.validateDraft(draft), isNull);

    configurator.applyDraft(registry, 'new-act', draft);
    expect(registry.actionController('new-act').value.label, 'Nouveau Bouton');
    expect(
      registry.actionController('new-act').value.kind,
      SuperActionKind.textAndIcon,
    );

    // Render surface variant with custom style
    await tester.pumpWidget(
      host(
        SuperAction(
          id: 'surface-act',
          config: const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            variant: SuperActionVariant.surface,
            label: 'Surface Action',
            icon: 'check',
            radius: 20,
            style: ContainerStyle(hoverEffect: true),
          ),
        ),
      ),
    );
    expect(find.byType(StyledSurface), findsOneWidget);
    expect(find.text('Surface Action'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  test('Unified Appearance.components map and ComponentConfig polymorphism round-trip through codec', () {
    final appearance = Appearance(
      components: {
        'v1': const SuperValueConfig(initialText: 'Hello'),
        'a1': const SuperActionConfig(
          kind: SuperActionKind.icon,
          icon: 'search',
        ),
        'l1': const SuperListViewConfig(itemExtent: 72),
        'n1': NativeComponentConfig(
          placements: {
            'child': ['v1'],
          },
          slotTypes: {'v1': 'registry:Value'},
        ),
        's1': ScaffoldPageConfig(
          placements: {
            ScaffoldPageRegion.body: ['l1'],
          },
          slotTypes: {'l1': 'registry:ListView'},
        ),
      },
    );

    for (final entry in appearance.components.entries) {
      expect(entry.value, isA<ComponentConfig>());
    }

    const codec = AppearanceCodec();
    final json = codec.toJson(appearance);
    expect(json.containsKey('components'), isTrue);
    expect(json.containsKey('valueComponents'), isFalse);
    expect(json.containsKey('actionComponents'), isFalse);
    expect(json.containsKey('listComponents'), isFalse);
    expect(json.containsKey('nativeComponents'), isFalse);
    expect(json.containsKey('scaffoldPages'), isFalse);

    final compsJson = json['components'] as Map<String, Object?>;
    expect((compsJson['v1'] as Map)['type'], 'value');
    expect((compsJson['a1'] as Map)['type'], 'action');
    expect((compsJson['l1'] as Map)['type'], 'list');
    expect((compsJson['n1'] as Map)['type'], 'native');
    expect((compsJson['s1'] as Map)['type'], 'scaffold');

    final decoded = codec.decode(codec.encode(appearance));
    expect(decoded.components.keys, appearance.components.keys);
    expect(decoded.valueComponent('v1').initialText, 'Hello');
    expect(decoded.actionComponent('a1').icon, 'search');
    expect(decoded.listComponent('l1').itemExtent, 72);
    expect(decoded.nativeComponent('n1').slotsOf('child'), ['v1']);
    expect(decoded.scaffoldPage('s1').slotsOf(ScaffoldPageRegion.body), ['l1']);
  });
}
