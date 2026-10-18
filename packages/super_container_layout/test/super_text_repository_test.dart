import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/super_text_editor.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late JsonTextBinding binding;

  setUp(() async {
    StyleEditorPanel.preferredDense = false;
    directory = await Directory.systemTemp.createTemp('super-text-repository-');
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

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await real(
      tester,
      () => tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: Center(child: SizedBox(width: 500, child: child)),
            ),
          ),
        ),
      ),
    );
  }

  Finder input(String id) => find.byKey(ValueKey('super-text-input-$id'));
  String text(WidgetTester tester, String id) =>
      tester.widget<TextField>(input(id)).controller!.text;

  testWidgets(
    'internal controllers load, save and synchronize with the manager',
    (tester) async {
      var changed = 0;
      await mount(
        tester,
        Column(
          children: [
            SuperText(
              id: 'input',
              config: SuperTextConfig(
                mode: SuperTextMode.input,
                binding: binding,
              ),
              onChanged: (_) => changed++,
            ),
            SuperText(
              id: 'display',
              config: SuperTextConfig(binding: binding),
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
        SuperTextConfig(
          mode: SuperTextMode.input,
          initialText: 'Never written',
          binding: binding,
        ),
      );
      addTearDown(config.dispose);
      await mount(
        tester,
        ValueListenableBuilder<SuperTextConfig>(
          valueListenable: config,
          builder: (_, value, _) => SuperText(id: 'text', config: value),
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
          mode: SuperTextMode.display,
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
      SuperText(
        id: 'missing',
        config: SuperTextConfig(
          mode: SuperTextMode.input,
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
    final config = SuperTextConfig(
      mode: SuperTextMode.input,
      obscureText: true,
      binding: binding,
    );
    await mount(tester, SuperText(id: 'password', config: config));
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
                  child: SuperText(
                    id: 'app',
                    config: SuperTextConfig(
                      mode: SuperTextMode.input,
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
        final design = registry.textController('app');
        design.value = design.value.copyWith(fontSize: 16);
      });
      final context = tester.element(find.byType(SuperText));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final history = EditorHistoryScope.controllerOf(context)!;
      await real(tester, () async {
        final design = registry.textController('app');
        design.value = design.value.copyWith(clearBinding: true);
      });
      expect(text(tester, 'app'), '');
      await real(tester, () async => history.undo());
      expect(text(tester, 'app'), 'Alice');
      expect(registry.textController('app').value.binding, binding);
      final appearance = AppearanceScope.controllerOf(context)!.value;
      final decoded = const AppearanceCodec().decode(
        const AppearanceCodec().encode(appearance),
      );
      expect(decoded.textComponents['app']!.binding, binding);
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
        SuperTextConfig(mode: SuperTextMode.input, binding: binding),
      );
      addTearDown(config.dispose);
      await mount(
        tester,
        ValueListenableBuilder<SuperTextConfig>(
          valueListenable: config,
          builder: (_, value, _) => SuperText(id: 'switch', config: value),
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
          SuperText(
            id: 'external',
            controller: controlled ? null : controller,
            value: controlled ? 'External' : null,
            config: SuperTextConfig(
              mode: SuperTextMode.input,
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
        SuperText(
          id: 'numeric',
          config: SuperTextConfig(
            mode: SuperTextMode.input,
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
    SuperTextConfig config = const SuperTextConfig(),
    bool allowBinding = true,
    required ValueChanged<SuperTextConfig?> result,
  }) => mount(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () async => result(
          await showSuperTextEditor(
            context: context,
            config: config,
            availableFontFamilies: const [],
            allowBinding: allowBinding,
          ),
        ),
        child: const Text('Edit'),
      ),
    ),
  );

  testWidgets(
    'field styles and limits never rewrite repository values; clear does',
    (tester) async {
      final config = ValueNotifier(
        SuperTextConfig(mode: SuperTextMode.input, binding: binding),
      );
      addTearDown(config.dispose);
      await mount(
        tester,
        ValueListenableBuilder<SuperTextConfig>(
          valueListenable: config,
          builder: (_, value, _) => SuperText(id: 'decorated', config: value),
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
    final dropdown = find.byKey(const ValueKey('super-text-repository-null'));
    await real(tester, () => tester.ensureVisible(dropdown));
    await real(tester, () => tester.tap(dropdown));
    await real(
      tester,
      () => tester.tap(find.text('People (${binding.repositoryId})').last),
    );
    final path = find.byKey(const ValueKey('super-text-repository-path'));
    await real(tester, () => tester.ensureVisible(path));
    await tester.enterText(path, 'new.attribute');
    await tester.pump();
  }

  testWidgets(
    'editor selects stable ID and path; applying never creates an attribute',
    (tester) async {
      SuperTextConfig? result;
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
    'editor cancel never changes the document or publishes a binding',
    (tester) async {
      SuperTextConfig? result;
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
      final config = SuperTextConfig(obscureText: true, binding: binding);
      expect(jsonEncode(config.toJson()), isNot(contains('Alice')));
      await editorHost(tester, config: config, result: (_) {});
      await real(tester, () => tester.tap(find.text('Edit')));
      expect(
        find.byKey(const ValueKey('super-text-repository-plaintext-warning')),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
