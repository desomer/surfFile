import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_value_editor.dart';


void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late JsonTextBinding binding;

  setUp(() async {
    StyleEditorPanel.preferredDense = false;
    directory = await Directory.systemTemp.createTemp('super-value-repository-');
    store = JsonRepositoryStore(directory);
    await store.create('People');
    binding = JsonTextBinding(
      repositoryId: await store.idOf('People'),
      path: 'client.name',
    );
    await store.writeAttribute(binding, 'Alice', expectedValue: null);
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> real(
    WidgetTester tester,
    Future<void> Function() action, {
    bool save = false,
  }) async {
    await tester.runAsync(() async {
      await action();
      await tester.pump();
      await Future<void>.delayed(Duration(milliseconds: save ? 500 : 120));
    });
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    bool repositoryScopeAboveNavigator = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await real(
      tester,
      () => tester.pumpWidget(
        repositoryScopeAboveNavigator
            ? JsonRepositoryScope(
                store: store,
                child: MaterialApp(
                  home: Scaffold(
                    body: Center(child: SizedBox(width: 500, child: child)),
                  ),
                ),
              )
            : MaterialApp(
                home: JsonRepositoryScope(
                  store: store,
                  child: Scaffold(
                    body: Center(child: SizedBox(width: 500, child: child)),
                  ),
                ),
              ),
      ),
    );
  }

  Finder input(String id) => find.byKey(ValueKey('super-value-input-$id'));
  String text(WidgetTester tester, String id) =>
      tester.widget<TextField>(input(id)).controller!.text;

  testWidgets(
    'live editor changes rendering without writing or rebinding repositories',
    (tester) async {
      var changes = 0;
      await mount(
        tester,
        SuperValue(
          id: 'live',
          config: SuperValueConfig(mode: SuperValueMode.input, binding: binding),
          onChanged: (_) => changes++,
        ),
      );
      final before = await tester.runAsync(() => store.read('People'));
      final initialChanges = changes;
      await real(
        tester,
        () => tester.tap(input('live'), buttons: kSecondaryMouseButton),
      );
      await real(
        tester,
        () => tester.tap(find.byKey(const ValueKey('style-menu-Valeur'))),
      );
      final radius = find.byKey(const ValueKey('text-field-setting-radius'));
      await tester.ensureVisible(radius);
      await tester.enterText(radius, '23');
      await tester.pumpAndSettle();
      expect(
        (tester.widget<TextField>(input('live')).decoration!.border
                as UnderlineInputBorder)
            .borderRadius,
        BorderRadius.circular(23),
      );
      await tester.enterText(radius, '-1');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-value-live-error')),
        findsOneWidget,
      );
      expect(
        (tester.widget<TextField>(input('live')).decoration!.border
                as UnderlineInputBorder)
            .borderRadius,
        BorderRadius.circular(23),
      );
      final path = find.byKey(const ValueKey('super-value-repository-path'));
      await tester.ensureVisible(path);
      await tester.enterText(path, 'client.other');
      await tester.pumpAndSettle();
      await real(tester, () async {}, save: true);
      expect(text(tester, 'live'), 'Alice');
      expect(changes, initialChanges);
      expect(await tester.runAsync(() => store.read('People')), before);
      await real(tester, () => tester.tap(find.text('Annuler')));
      expect(text(tester, 'live'), 'Alice');
      expect(changes, initialChanges);
      expect(await tester.runAsync(() => store.read('People')), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'internal controllers load, save and synchronize with the manager',
    (tester) async {
      var changed = 0;
      await mount(
        tester,
        Column(
          children: [
            SuperValue(
              id: 'input',
              config: SuperValueConfig(
                mode: SuperValueMode.input,
                binding: binding,
              ),
              onChanged: (_) => changed++,
            ),
            SuperValue(
              id: 'display',
              config: SuperValueConfig(binding: binding),
            ),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => JsonRepositoryManager.show(context),
                child: const Text('Manage'),
              ),
            ),
          ],
        ),
      );

      expect(text(tester, 'input'), 'Alice');
      expect(find.text('Alice'), findsNWidgets(2));
      final previousChanges = changed;
      await real(
        tester,
        () => tester.enterText(input('input'), 'Bob'),
        save: true,
      );
      expect(await tester.runAsync(() => store.readAttribute(binding)), (
        value: 'Bob',
        text: 'Bob',
      ));
      expect(find.text('Bob'), findsNWidgets(2));
      expect(changed, previousChanges + 1);
      final controller = tester.widget<TextField>(input('input')).controller!;

      await real(tester, () => tester.tap(find.text('Manage')));
      await real(
        tester,
        () => tester.tap(find.byKey(const ValueKey('repository-entry-People'))),
      );
      final editor = find.byKey(const ValueKey('repository-json'));
      await real(tester, () async {
        controller.text = 'Updated while manager is open';
      }, save: true);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        contains('Updated while manager is open'),
      );
      await real(
        tester,
        () => tester.enterText(editor, '{"client":{"name":"Carol"}}'),
      );
      await real(
        tester,
        () => tester.tap(find.byKey(const ValueKey('repository-save'))),
      );
      await real(tester, () => tester.tap(find.text('Fermer')));
      expect(text(tester, 'input'), 'Carol');
      expect(find.text('Carol'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'programmatic controller edits persist and mode changes do not reset data',
    (tester) async {
      final config = ValueNotifier(
        SuperValueConfig(
          mode: SuperValueMode.input,
          initialText: 'Never written',
          binding: binding,
        ),
      );
      addTearDown(config.dispose);
      await mount(
        tester,
        ValueListenableBuilder<SuperValueConfig>(
          valueListenable: config,
          builder: (_, value, _) => SuperValue(id: 'text', config: value),
        ),
      );
      final controller = tester.widget<TextField>(input('text')).controller!;
      await real(tester, () async {
        controller.text = 'Programmatic';
      }, save: true);
      expect(
        (await tester.runAsync(() => store.readAttribute(binding)))!.text,
        'Programmatic',
      );
      await real(tester, () async {
        config.value = config.value.copyWith(
          mode: SuperValueMode.display,
          initialText: 'Do not reset',
        );
      });
      expect(find.text('Programmatic'), findsOneWidget);
      expect(
        (await tester.runAsync(() => store.readAttribute(binding)))!.text,
        'Programmatic',
      );
      await real(tester, () async {
        config.value = config.value.copyWith(clearBinding: true);
      });
      expect(find.text('Do not reset'), findsOneWidget);
      expect(
        (await tester.runAsync(() => store.readAttribute(binding)))!.text,
        'Programmatic',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing attributes stay absent until the first edit', (
    tester,
  ) async {
    final missing = JsonTextBinding(
      repositoryId: binding.repositoryId,
      path: 'address.city',
    );
    await mount(
      tester,
      SuperValue(
        id: 'missing',
        config: SuperValueConfig(
          mode: SuperValueMode.input,
          initialText: 'Fallback',
          binding: missing,
        ),
      ),
    );
    expect(text(tester, 'missing'), '');
    var document = jsonDecode(
      (await tester.runAsync(() => store.read('People')))!,
    );
    expect(document['address'], isNull);
    await real(
      tester,
      () => tester.enterText(input('missing'), 'Paris'),
      save: true,
    );
    document = jsonDecode((await tester.runAsync(() => store.read('People')))!);
    expect(document['address'], {'city': 'Paris'});
    expect(document['client'], {'name': 'Alice'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('masked runtime data is saved only in the repository', (
    tester,
  ) async {
    final config = SuperValueConfig(
      mode: SuperValueMode.input,
      obscureText: true,
      binding: binding,
    );
    await mount(tester, SuperValue(id: 'password', config: config));
    expect(tester.widget<TextField>(input('password')).obscureText, isTrue);
    await real(
      tester,
      () => tester.enterText(input('password'), 'private-value'),
      save: true,
    );
    expect(
      (await tester.runAsync(() => store.readAttribute(binding)))!.text,
      'private-value',
    );
    expect(jsonEncode(config.toJson()), isNot(contains('private-value')));
    expect(store.errors.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SuperApp shares the store and appearance undo restores the binding',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final channel in [
        WindowTransparency.channel,
        const MethodChannel('com.alexmercerind/flutter_acrylic'),
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      final registry = Registry()..bootstrap();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => SuperPage(
              child: Center(
                child: SizedBox(
                  width: 400,
                  height: 200,
                  child: SuperValue(
                    id: 'app',
                    config: SuperValueConfig(
                      mode: SuperValueMode.input,
                      binding: binding,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await real(
        tester,
        () => tester.pumpWidget(
          SuperApp(router: router, registry: registry, repositoryStore: store),
        ),
      );
      await real(tester, () async {});
      expect(text(tester, 'app'), 'Alice');
      await real(tester, () async {
        final design = registry.valueController('app');
        design.value = design.value.copyWith(fontSize: 16);
      });
      final context = tester.element(find.byType(SuperValue));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final history = EditorHistoryScope.controllerOf(context)!;
      await real(tester, () async {
        final design = registry.valueController('app');
        design.value = design.value.copyWith(clearBinding: true);
      });
      expect(text(tester, 'app'), '');
      await real(tester, () async => history.undo());
      expect(text(tester, 'app'), 'Alice');
      expect(registry.valueController('app').value.binding, binding);
      final appearance = AppearanceScope.controllerOf(context)!.value;
      final decoded = const AppearanceCodec().decode(
        const AppearanceCodec().encode(appearance),
      );
      expect(decoded.valueComponents['app']!.binding, binding);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching bindings flushes the old target without writing into the new one',
    (tester) async {
      final other = JsonTextBinding(
        repositoryId: binding.repositoryId,
        path: 'other',
      );
      await tester.runAsync(
        () => store.writeAttribute(other, 'Original', expectedValue: null),
      );
      final config = ValueNotifier(
        SuperValueConfig(mode: SuperValueMode.input, binding: binding),
      );
      addTearDown(config.dispose);
      await mount(
        tester,
        ValueListenableBuilder<SuperValueConfig>(
          valueListenable: config,
          builder: (_, value, _) => SuperValue(id: 'switch', config: value),
        ),
      );
      await real(tester, () async {
        tester.widget<TextField>(input('switch')).controller!.text =
            'Final old edit';
        config.value = config.value.copyWith(binding: other);
      });
      expect(text(tester, 'switch'), 'Original');
      expect(
        (await tester.runAsync(() => store.readAttribute(binding)))!.text,
        'Final old edit',
      );
      expect(
        (await tester.runAsync(() => store.readAttribute(other)))!.text,
        'Original',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final controlled in [false, true]) {
    testWidgets(
      'external ${controlled ? 'value' : 'controller'} refuses binding',
      (tester) async {
        final controller = TextEditingController(text: 'External');
        addTearDown(controller.dispose);
        await mount(
          tester,
          SuperValue(
            id: 'external',
            controller: controlled ? null : controller,
            value: controlled ? 'External' : null,
            config: SuperValueConfig(
              mode: SuperValueMode.input,
              binding: binding,
            ),
          ),
        );
        expect(
          tester.widget<TextField>(input('external')).decoration!.errorText,
          contains('contrôleur interne'),
        );
        expect(text(tester, 'external'), 'External');
        expect(
          (await tester.runAsync(() => store.readAttribute(binding)))!.text,
          'Alice',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'errors are visible, failed writes retain input and reload can recover',
    (tester) async {
      await tester.runAsync(() async {
        await store.save(
          'People',
          '{"client":{"name":12}}',
          expectedText: await store.read('People'),
        );
      });
      await mount(
        tester,
        SuperValue(
          id: 'numeric',
          config: SuperValueConfig(
            mode: SuperValueMode.input,
            binding: binding,
            field: const SuperTextFieldConfig(errorText: 'Manual error'),
          ),
        ),
      );
      expect(text(tester, 'numeric'), '12');
      await real(
        tester,
        () => tester.enterText(input('numeric'), '-'),
        save: true,
      );
      expect(text(tester, 'numeric'), '-');
      expect(
        tester.widget<TextField>(input('numeric')).decoration!.errorText,
        isNotNull,
      );
      expect(
        tester.widget<TextField>(input('numeric')).decoration!.errorText,
        isNot('Manual error'),
      );
      expect(
        (await tester.runAsync(() => store.readAttribute(binding)))!.value,
        12,
      );
      await real(tester, () => tester.tap(find.text('Recharger la liaison')));
      await real(tester, () => tester.tap(find.text('Recharger')));
      expect(text(tester, 'numeric'), '12');
      expect(
        tester.widget<TextField>(input('numeric')).decoration!.errorText,
        'Manual error',
      );
      await real(
        tester,
        () => tester.enterText(input('numeric'), '42'),
        save: true,
      );
      expect(
        (await tester.runAsync(() => store.readAttribute(binding)))!.value,
        42,
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> editorHost(
    WidgetTester tester, {
    SuperValueConfig config = const SuperValueConfig(),
    bool allowBinding = true,
    bool repositoryScopeAboveNavigator = true,
    required ValueChanged<SuperValueConfig?> result,
  }) => mount(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () async => result(
          await showSuperValueEditor(
            context: context,
            config: config,
            availableFontFamilies: const [],
            allowBinding: allowBinding,
          ),
        ),
        child: const Text('Edit'),
      ),
    ),
    repositoryScopeAboveNavigator: repositoryScopeAboveNavigator,
  );

  testWidgets(
    'field styles and limits never rewrite repository values; clear does',
    (tester) async {
      final config = ValueNotifier(
        SuperValueConfig(mode: SuperValueMode.input, binding: binding),
      );
      addTearDown(config.dispose);
      await mount(
        tester,
        ValueListenableBuilder<SuperValueConfig>(
          valueListenable: config,
          builder: (_, value, _) => SuperValue(id: 'decorated', config: value),
        ),
      );
      final original = await tester.runAsync(() => store.read('People'));
      await real(tester, () async {
        config.value = config.value.copyWith(
          field: const SuperTextFieldConfig(
            variant: TextFieldVariant.outlined,
            maxLength: 2,
            filter: TextFieldFilter.digits,
            suffix: TextFieldSuffix.clear,
          ),
        );
      }, save: true);
      expect(text(tester, 'decorated'), 'Alice');
      expect(await tester.runAsync(() => store.read('People')), original);
      await real(
        tester,
        () => tester.tap(find.byTooltip('Effacer')),
        save: true,
      );
      expect(
        (await tester.runAsync(() => store.readAttribute(binding)))!.text,
        '',
      );
      expect(text(tester, 'decorated'), '');
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> choose(WidgetTester tester) async {
    final dropdown = find.byKey(const ValueKey('super-value-repository-null'));
    await real(tester, () => tester.ensureVisible(dropdown));
    await real(tester, () => tester.tap(dropdown));
    await real(
      tester,
      () => tester.tap(find.text('People (${binding.repositoryId})').last),
    );
    final path = find.byKey(const ValueKey('super-value-repository-path'));
    await real(tester, () => tester.ensureVisible(path));
    await tester.enterText(path, 'new.attribute');
    await tester.pump();
  }

  testWidgets(
    'editor selects stable ID and path; applying never creates an attribute',
    (tester) async {
      SuperValueConfig? result;
      final before = await tester.runAsync(() => store.read('People'));
      await editorHost(tester, result: (value) => result = value);
      await real(tester, () => tester.tap(find.text('Edit')));
      await choose(tester);
      await real(tester, () => tester.tap(find.text('Appliquer')));
      expect(
        result?.binding,
        JsonTextBinding(
          repositoryId: binding.repositoryId,
          path: 'new.attribute',
        ),
      );
      expect(await tester.runAsync(() => store.read('People')), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'property binding icon opens shared selector and applies the chosen path',
    (tester) async {
      SuperValueConfig? result;
      await editorHost(
        tester,
        config: const SuperValueConfig(label: 'Configured label'),
        repositoryScopeAboveNavigator: false,
        result: (value) => result = value,
      );
      await real(tester, () => tester.tap(find.text('Edit')));
      final bind = find.byKey(const ValueKey('super-value-bind-label'));
      await real(tester, () => tester.ensureVisible(bind));
      await real(tester, () => tester.tap(bind));
      final repository = find.byKey(
        const ValueKey('super-value-property-label-repository'),
      );
      await real(tester, () => tester.tap(repository));
      await real(tester, () => tester.tap(find.text('People').last));
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: repository,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .value,
        binding.repositoryId,
      );
      final path = find.byKey(
        const ValueKey('super-value-property-label-repository-path'),
      );
      await real(tester, () => tester.ensureVisible(path));
      await real(tester, () => tester.enterText(path, 'client.name'));
      await real(
        tester,
        () => tester.tap(
          find.byKey(const ValueKey('super-value-property-label-apply')),
        ),
      );
      expect(
        find.byKey(const ValueKey('super-value-bind-label')),
        findsOneWidget,
      );
      await real(tester, () => tester.tap(find.text('Appliquer').last));
      expect(
        result?.propertyBindings[SuperValueProperty.label],
        JsonTextBinding(
          repositoryId: binding.repositoryId,
          path: 'client.name',
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'property bindings update styles read-only while content binding stays separate',
    (tester) async {
      await tester.runAsync(() async {
        final previous = await store.read('People');
        await store.save(
          'People',
          '{"client":{"name":"Alice","label":"Person","color":"#123456","size":24,"font":"Roboto","weight":"bold","italic":true,"align":"center"}}',
          expectedText: previous,
        );
      });
      final original = await tester.runAsync(() => store.read('People'));
      await mount(
        tester,
        SuperValue(
          id: 'bound-style',
          config: SuperValueConfig(
            binding: binding,
            label: 'Configured label',
            color: const Color(0xFFFF0000),
            propertyBindings: {
              SuperValueProperty.label: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.label',
              ),
              SuperValueProperty.color: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.color',
              ),
              SuperValueProperty.fontSize: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.size',
              ),
              SuperValueProperty.fontFamily: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.font',
              ),
              SuperValueProperty.fontWeight: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.weight',
              ),
              SuperValueProperty.italic: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.italic',
              ),
              SuperValueProperty.textAlign: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.align',
              ),
            },
          ),
        ),
      );
      await real(tester, () async {});
      final display = tester.widget<Text>(
        find.byKey(const ValueKey('super-value-display-bound-style')),
      );
      expect(display.style?.color, const Color(0xFF123456));
      expect(display.style?.fontSize, 24);
      expect(display.style?.fontFamily, 'Roboto');
      expect(display.style?.fontWeight, FontWeight.w700);
      expect(display.style?.fontStyle, FontStyle.italic);
      expect(display.textAlign, TextAlign.center);
      expect(find.text('Person'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(await tester.runAsync(() => store.read('People')), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refreshing bound styles keeps the last value until the new value loads',
    (tester) async {
      await tester.runAsync(() async {
        final previous = await store.read('People');
        await store.save(
          'People',
          '{"client":{"name":"Alice","label":"Person","color":"#123456"}}',
          expectedText: previous,
        );
      });
      await mount(
        tester,
        SuperValue(
          id: 'refresh-style',
          config: SuperValueConfig(
            label: 'Fallback label',
            color: const Color(0xFFFF0000),
            propertyBindings: {
              SuperValueProperty.label: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.label',
              ),
              SuperValueProperty.color: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.color',
              ),
            },
          ),
        ),
      );
      await real(tester, () async {});

      InputDecorator decorator() =>
          tester.widget<InputDecorator>(find.byType(InputDecorator));
      Text display() => tester.widget<Text>(
        find.byKey(const ValueKey('super-value-display-refresh-style')),
      );
      expect(decorator().decoration.labelText, 'Person');
      expect(display().style?.color, const Color(0xFF123456));

      final labelBinding = JsonTextBinding(
        repositoryId: binding.repositoryId,
        path: 'client.label',
      );
      await tester.runAsync(
        () => store.writeAttribute(
          labelBinding,
          'Updated',
          expectedValue: 'Person',
        ),
      );
      await tester.pump();
      expect(decorator().decoration.labelText, 'Person');
      expect(display().style?.color, const Color(0xFF123456));
      await real(tester, () async {}, save: true);
      expect(decorator().decoration.labelText, 'Updated');

      final colorBinding = JsonTextBinding(
        repositoryId: binding.repositoryId,
        path: 'client.color',
      );
      await tester.runAsync(
        () => store.writeAttribute(
          colorBinding,
          '#654321',
          expectedValue: '#123456',
        ),
      );
      await tester.pump();
      expect(display().style?.color, const Color(0xFF123456));
      await real(tester, () async {}, save: true);
      expect(display().style?.color, const Color(0xFF654321));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid property value retains configured style and exposes an error',
    (tester) async {
      await tester.runAsync(() async {
        final previous = await store.read('People');
        await store.save(
          'People',
          '{"client":{"name":"Alice","color":"not-a-color"}}',
          expectedText: previous,
        );
      });
      final original = await tester.runAsync(() => store.read('People'));
      await mount(
        tester,
        SuperValue(
          id: 'bad-style',
          config: SuperValueConfig(
            color: const Color(0xFFFF0000),
            propertyBindings: {
              SuperValueProperty.color: JsonTextBinding(
                repositoryId: binding.repositoryId,
                path: 'client.color',
              ),
            },
          ),
        ),
      );
      await real(tester, () async {});
      final display = tester.widget<Text>(
        find.byKey(const ValueKey('super-value-display-bad-style')),
      );
      expect(display.style?.color, const Color(0xFFFF0000));
      expect(
        find.byKey(
          const ValueKey('super-value-property-binding-error-color-bad-style'),
        ),
        findsOneWidget,
      );
      expect(await tester.runAsync(() => store.read('People')), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'property bindings resolve inherited repositories and list indices',
    (tester) async {
      await tester.runAsync(() async {
        final previous = await store.read('People');
        await store.save(
          'People',
          '{"clients":[{"label":"First client"}]}',
          expectedText: previous,
        );
      });
      await mount(
        tester,
        JsonListScope(
          repositoryId: binding.repositoryId,
          indices: const [0],
          child: SuperValue(
            id: 'inherited-style',
            config: const SuperValueConfig(
              label: 'Configured label',
              propertyBindings: {
                SuperValueProperty.label: JsonTextBinding(
                  path: 'clients[?].label',
                ),
              },
            ),
          ),
        ),
      );
      await real(tester, () async {});
      expect(find.text('First client'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'super-value-property-binding-error-label-inherited-style',
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor cancel never changes the document or publishes a binding',
    (tester) async {
      SuperValueConfig? result;
      final before = await tester.runAsync(() => store.read('People'));
      await editorHost(tester, result: (value) => result = value);
      await real(tester, () => tester.tap(find.text('Edit')));
      await choose(tester);
      await real(tester, () => tester.tap(find.text('Annuler')));
      expect(result, isNull);
      expect(await tester.runAsync(() => store.read('People')), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'masked binding warns about plaintext without previewing repository values',
    (tester) async {
      final config = SuperValueConfig(obscureText: true, binding: binding);
      expect(jsonEncode(config.toJson()), isNot(contains('Alice')));
      await editorHost(tester, config: config, result: (_) {});
      await real(tester, () => tester.tap(find.text('Edit')));
      expect(
        find.byKey(const ValueKey('super-value-repository-plaintext-warning')),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'checkbox and switch bind to JSON booleans and default missing attributes to false',
    (tester) async {
      final activeBinding = JsonTextBinding(
        repositoryId: binding.repositoryId,
        path: 'client.active',
      );
      final boolEvents = <bool>[];
      await mount(
        tester,
        Column(
          children: [
            SuperValue(
              id: 'cb',
              config: SuperValueConfig(
                mode: SuperValueMode.input,
                kind: SuperValueKind.checkbox,
                binding: activeBinding,
              ),
              onBoolChanged: boolEvents.add,
            ),
            SuperValue(
              id: 'sw',
              config: SuperValueConfig(
                mode: SuperValueMode.display,
                kind: SuperValueKind.switchControl,
                binding: activeBinding,
              ),
            ),
          ],
        ),
      );
      final cbFinder = find.byKey(const ValueKey('super-value-checkbox-cb'));
      final swFinder = find.byKey(const ValueKey('super-value-switch-sw'));
      expect(tester.widget<Checkbox>(cbFinder).value, isFalse);
      expect(tester.widget<Switch>(swFinder).value, isFalse);
      var doc =
          jsonDecode((await tester.runAsync(() => store.read('People')))!)
              as Map<String, dynamic>;
      expect((doc['client'] as Map).containsKey('active'), isFalse);

      await real(tester, () => tester.tap(cbFinder), save: true);
      expect(tester.widget<Checkbox>(cbFinder).value, isTrue);
      expect(tester.widget<Switch>(swFinder).value, isTrue);
      expect(boolEvents, contains(true));
      doc =
          jsonDecode((await tester.runAsync(() => store.read('People')))!)
              as Map<String, dynamic>;
      expect((doc['client'] as Map)['active'], isTrue);

      await real(tester, () => tester.tap(cbFinder), save: true);
      expect(tester.widget<Checkbox>(cbFinder).value, isFalse);
      expect(tester.widget<Switch>(swFinder).value, isFalse);
      doc =
          jsonDecode((await tester.runAsync(() => store.read('People')))!)
              as Map<String, dynamic>;
      expect((doc['client'] as Map)['active'], isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('boolean binding reports an error when JSON value is not a bool', (
    tester,
  ) async {
    await mount(
      tester,
      SuperValue(
        id: 'bad-bool',
        config: SuperValueConfig(
          mode: SuperValueMode.input,
          kind: SuperValueKind.switchControl,
          binding: binding,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('super-value-binding-error-bad-bool')),
      findsOneWidget,
    );
    expect(find.text('L’attribut lié doit être un booléen.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
