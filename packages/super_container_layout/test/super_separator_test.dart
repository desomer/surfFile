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
      body: Center(child: SizedBox(width: 320, height: 160, child: child)),
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
    'SuperSeparatorConfig serializes, patches, validates and resolves states',
    () {
      final config = SuperSeparatorConfig(
        kind: SuperSeparatorKind.divider,
        axis: Axis.vertical,
        extent: 24,
        thickness: 2,
        indent: 8,
        endIndent: 12,
        lineStyle: SuperSeparatorLineStyle.dashed,
        lineColor: const Color(0xFF445566),
        label: 'Section A',
        labelPosition: SuperSeparatorLabelPosition.start,
        labelSpacing: 10,
        fontFamily: 'Roboto',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        italic: true,
        color: const Color(0xFF112233),
        letterSpacing: 0.4,
        propertyBindings: const {
          SuperSeparatorProperty.label: JsonTextBinding(
            repositoryId: 'pan_model_repository',
            path: 'section.title',
          ),
        },
        states: SeparatorConfigStates(
          binding: const JsonTextBinding(
            repositoryId: 'pan_model_repository',
            path: 'section.mode',
          ),
          named: const {
            'compact': SuperSeparatorConfig(
              kind: SuperSeparatorKind.spacer,
              extent: 8,
            ),
          },
          namedProperties: const {
            'compact': {
              SeparatorStateProperty.content,
              SeparatorStateProperty.extent,
            },
          },
          hover: SeparatorConfigOverride(
            config: const SuperSeparatorConfig(thickness: 4),
            properties: const {SeparatorStateProperty.thickness},
          ),
          selected: SeparatorConfigOverride(
            config: const SuperSeparatorConfig(lineColor: Color(0xFF1976D2)),
            properties: const {SeparatorStateProperty.lineColor},
          ),
        ),
      );

      final json = config.toJson();
      expect(SuperSeparatorConfig.fromJson(json), config);

      final compact = config.toCompactJson();
      expect(SuperSeparatorConfig.fromJson(compact), config);

      final resolved = config.states!.resolve(
        config,
        name: 'compact',
        isHovered: true,
        isSelected: true,
      );
      expect(resolved.kind, SuperSeparatorKind.spacer);
      expect(resolved.extent, 8);
      expect(resolved.thickness, 4);
      expect(resolved.lineColor, const Color(0xFF1976D2));

      final patched = config.patchFromJson({
        'kind': 'space',
        'orientation': 'horizontal',
        'size': 32,
        'text': 'Titre',
      });
      expect(patched.kind, SuperSeparatorKind.spacer);
      expect(patched.axis, Axis.horizontal);
      expect(patched.extent, 32);
      expect(patched.label, 'Titre');

      expect(
        () => SuperSeparatorConfig(extent: -1).validate(),
        throwsArgumentError,
      );
      expect(
        () => SuperSeparatorConfig(thickness: 0).validate(),
        throwsArgumentError,
      );
      expect(
        () => SuperSeparatorConfig(indent: -2).validate(),
        throwsArgumentError,
      );
    },
  );

  testWidgets(
    'SuperSeparator renders horizontal/vertical divider with or without label and spacer',
    (tester) async {
      // 1. Horizontal solid divider without label
      await tester.pumpWidget(
        host(
          const SuperSeparator(
            id: 'sep-h',
            config: SuperSeparatorConfig(
              kind: SuperSeparatorKind.divider,
              axis: Axis.horizontal,
              extent: 20,
              thickness: 2,
            ),
          ),
        ),
      );
      expect(find.byType(Divider), findsOneWidget);

      // 2. Vertical solid divider without label
      await tester.pumpWidget(
        host(
          const SuperSeparator(
            id: 'sep-v',
            config: SuperSeparatorConfig(
              kind: SuperSeparatorKind.divider,
              axis: Axis.vertical,
              extent: 24,
              thickness: 2,
            ),
          ),
        ),
      );
      expect(find.byType(VerticalDivider), findsOneWidget);

      // 3. Horizontal dashed divider with label
      await tester.pumpWidget(
        host(
          const SuperSeparator(
            id: 'sep-labeled',
            config: SuperSeparatorConfig(
              kind: SuperSeparatorKind.divider,
              axis: Axis.horizontal,
              lineStyle: SuperSeparatorLineStyle.dashed,
              label: 'Détails',
              labelPosition: SuperSeparatorLabelPosition.center,
            ),
          ),
        ),
      );
      expect(find.text('Détails'), findsOneWidget);

      // 4. Spacer mode
      await tester.pumpWidget(
        host(
          const SuperSeparator(
            id: 'sep-spacer',
            config: SuperSeparatorConfig(
              kind: SuperSeparatorKind.spacer,
              axis: Axis.horizontal,
              extent: 32,
            ),
          ),
        ),
      );
      expect(find.byType(Divider), findsNothing);
      expect(find.byType(VerticalDivider), findsNothing);
      final box = tester.widget<SizedBox>(
        find.byKey(const ValueKey('super-separator-visual-sep-spacer')),
      );
      expect(box.height, 32);
    },
  );

  testWidgets(
    'SuperSeparator editor updates config, supports undo/redo and persists in Appearance',
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
                child: SuperSeparator(
                  id: 'persisted-separator',
                  config: SuperSeparatorConfig(label: 'Initial'),
                ),
              ),
            ),
          ),
        ),
      );

      StyleEditScope.controllerOf(tester.element(find.byType(SuperSeparator)))!
              .value =
          true;
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SuperSeparator));
      final history = EditorHistoryScope.controllerOf(context)!;
      final appearance = AppearanceScope.controllerOf(context)!;
      final design = registry.separatorController('persisted-separator');

      await tester.tap(
        find.byType(SuperSeparator),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Separator'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-separator-settings')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('super-separator-setting-label')),
        'Section Modifiée',
      );
      await tester.pumpAndSettle();

      expect(find.text('Section Modifiée'), findsWidgets);
      expect(history.canUndo, isFalse);

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      expect(design.value.label, 'Section Modifiée');
      expect(history.canUndo, isTrue);

      final store = AppearanceStore();
      await store.save(appearance.value);
      expect(
        (await store.load())
            .tryComponent<SuperSeparatorConfig>('persisted-separator')
            ?.label,
        'Section Modifiée',
      );

      history.undo();
      await tester.pumpAndSettle();
      expect(design.value.label, 'Initial');

      history.redo();
      await tester.pumpAndSettle();
      expect(design.value.label, 'Section Modifiée');
    },
  );

  test('AppearanceCodec, JsonComponentType and EditorPageGraph handle Separator components', () {
    expect(JsonComponentType.normalize('Separator'), 'registry:Separator');
    expect(JsonComponentType.normalize('SuperSeparator'), 'registry:Separator');
    expect(JsonComponentType.normalize('Divider'), 'registry:Separator');
    expect(JsonComponentType.normalize('Spacer'), 'registry:Separator');
    expect(JsonComponentType.shortName('registry:Separator'), 'Separator');

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
              {'id': 'sep1', 'type': 'Divider'},
            ],
          },
        },
        'sep1': {
          'type': 'separator',
          'kind': 'divider',
          'axis': 'vertical',
          'extent': 24,
          'label': 'OU',
        },
      },
      'pageCatalog': {
        'pages': [
          {'id': 'home', 'name': 'Accueil', 'path': '/'},
        ],
        'homePageId': null,
      },
    });
    final sep1 = appearance.tryComponent<SuperSeparatorConfig>('sep1');
    expect(sep1, isNotNull);
    expect(sep1!.kind, SuperSeparatorKind.divider);
    expect(sep1.axis, Axis.vertical);
    expect(sep1.extent, 24);
    expect(sep1.label, 'OU');

    final duplicated = EditorPageGraph.duplicate(
      appearance: appearance,
      registry: registry,
      sourcePageId: 'home',
      targetPageId: 'copy',
    );
    expect(duplicated.componentsOfType<SuperSeparatorConfig>().length, 2);
  });

  testWidgets('superSeparatorAddConfigurator configures draft in add wizard', (
    tester,
  ) async {
    final registry = Registry()..bootstrap(availableFontFamilies: ['Roboto']);
    final configurator = superSeparatorAddConfigurator(const ['Roboto']);
    var draft = const SuperSeparatorConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => configurator.buildDraft(
              context,
              draft,
              (next) => setState(() => draft = next as SuperSeparatorConfig),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Spacer (espace)'));
    await tester.pumpAndSettle();
    expect(draft.kind, SuperSeparatorKind.spacer);

    await tester.tap(find.text('Vertical'));
    await tester.pumpAndSettle();
    expect(draft.axis, Axis.vertical);

    await tester.enterText(
      find.byKey(const ValueKey('add-separator-label')),
      'Mon Séparateur',
    );
    await tester.pump();
    expect(draft.label, 'Mon Séparateur');
    expect(configurator.validateDraft(draft), isNull);

    configurator.applyDraft(registry, 'new-sep', draft);
    expect(
      registry.separatorController('new-sep').value.kind,
      SuperSeparatorKind.spacer,
    );
    expect(registry.separatorController('new-sep').value.axis, Axis.vertical);
    expect(
      registry.separatorController('new-sep').value.label,
      'Mon Séparateur',
    );
  });
}
