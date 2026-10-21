/// Tests de widget de `SuperListView` sur un vrai repository temporaire :
/// lignes et sous-lignes, saisie, ajout / suppression, fenêtre de réglage,
/// gabarit en mode édition, et maître / détail (sélection au clic lue par des
/// `SuperText` et une liste placés hors de la liste).
///
/// Les lectures et écritures de fichiers ont lieu en temps réel : les
/// interactions passent par `real`, qui exécute l'action dans
/// `tester.runAsync` puis laisse plusieurs images se charger.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repository;

  setUp(() async {
    StyleEditorPanel.preferredDense = false;
    directory = await Directory.systemTemp.createTemp('super-list-view-');
    store = JsonRepositoryStore(directory);
    await store.create('Shop');
    repository = await store.idOf('Shop');
    await store.save(
      'Shop',
      jsonEncode({
        'clients': [
          {
            'name': 'Alice',
            'orders': [
              {'label': 'A1'},
              {'label': 'A2'},
            ],
          },
          {
            'name': 'Bob',
            'orders': [
              {'label': 'B1'},
            ],
          },
        ],
      }),
      expectedText: await store.read('Shop'),
    );
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
      // Nested lists and their texts load in successive frames: keep them in
      // real time so their file reads complete.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Registry? registry,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget app = MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 500, height: 900, child: child)),
      ),
    );
    if (registry != null) {
      SharedPreferences.setMockInitialValues({});
      for (final channel in [
        const MethodChannel('com.alexmercerind/flutter_acrylic'),
        WindowTransparency.channel,
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
      }
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: SizedBox(width: 500, height: 900, child: child),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      app = SuperApp(
        router: router,
        registry: registry,
        repositoryStore: store,
      );
    }
    await real(
      tester,
      () => tester.pumpWidget(JsonRepositoryScope(store: store, child: app)),
    );
  }

  Future<Map<String, dynamic>> document(WidgetTester tester) async =>
      jsonDecode((await tester.runAsync(() => store.read('Shop')))!)
          as Map<String, dynamic>;

  SlotImplementation text(
    String id,
    String path, {
    SuperTextMode mode = SuperTextMode.display,
  }) => BuilderSlot(
    id: id,
    label: id,
    showLabel: false,
    builder: (_) => SuperText(
      id: id,
      config: SuperTextConfig(
        mode: mode,
        binding: JsonTextBinding(path: path),
      ),
    ),
  );

  SuperLayoutConfig center(List<String> ids) =>
      SuperLayoutConfig(placements: {SuperLayoutZone.center: ids});

  Finder row(String list, Object index) =>
      find.byKey(ValueKey('super-list-row-$list-$index'));

  testWidgets(
    'rows share IterableContent style and layout without a registry',
    (tester) async {
      await mount(
        tester,
        SuperListView(
          id: 'clients',
          config: SuperListViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
            itemExtent: 150,
          ),
          template: center(['name']),
          slots: [text('name', 'clients[?].name')],
        ),
      );
      expect(find.byType(IterableContent), findsNWidgets(2));
      final first = tester.widget<IterableContent>(
        find.descendant(
          of: row('clients', 0),
          matching: find.byType(IterableContent),
        ),
      );
      const style = ContainerStyle(color: Colors.blue, padding: 7, radius: 9);
      first.onStyleChanged!(style);
      first.onChanged!(
        first.config.withAxis(SuperLayoutZone.center, Axis.horizontal),
      );
      await tester.pumpAndSettle();
      for (final content in tester.widgetList<IterableContent>(
        find.byType(IterableContent),
      )) {
        expect(content.style, same(style));
        expect(content.config.axisOf(SuperLayoutZone.center), Axis.horizontal);
      }
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registry row style changes propagate to all rows and undo together',
    (tester) async {
      final registry = Registry()..bootstrap();
      await mount(
        tester,
        SuperListView(
          id: 'clients',
          config: SuperListViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
            itemExtent: 150,
          ),
          template: center(['name']),
          slots: [text('name', 'clients[?].name')],
        ),
        registry: registry,
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      final context = tester.element(find.byType(SuperListView));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final appearance = AppearanceScope.controllerOf(context)!;
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();
      final before = appearance.value;
      tester
          .widget<IterableContent>(find.byType(IterableContent).first)
          .onStyleChanged!(
        const ContainerStyle(color: Colors.orange, radius: 10),
      );
      await tester.pumpAndSettle();
      expect(appearance.value.styles['clients']!.radius, 10);
      expect(find.byType(IterableContent), findsNWidgets(2));
      for (final content in tester.widgetList<IterableContent>(
        find.byType(IterableContent),
      )) {
        expect(content.style.radius, 10);
      }
      await real(tester, () async => history.undo());
      expect(appearance.value, same(before));
      expect(history.canUndo, isFalse);
      for (final content in tester.widgetList<IterableContent>(
        find.byType(IterableContent),
      )) {
        expect(content.style.radius, 0);
      }
      await real(tester, () async => history.redo());
      for (final content in tester.widgetList<IterableContent>(
        find.byType(IterableContent),
      )) {
        expect(content.style.radius, 10);
      }
      expect(await document(tester), containsPair('clients', hasLength(2)));
      expect(tester.takeException(), isNull);
      await real(tester, store.flushBindings);
      await real(tester, () => tester.pumpWidget(const SizedBox()));
    },
  );

  testWidgets('rows and nested rows resolve [?] with inherited repository', (
    tester,
  ) async {
    await mount(
      tester,
      SuperListView(
        id: 'clients',
        config: SuperListViewConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          itemExtent: 200,
        ),
        template: center(['name', 'orders']),
        slots: [
          text('name', 'clients[?].name'),
          BuilderSlot(
            id: 'orders',
            label: 'orders',
            showLabel: false,
            builder: (_) => SuperListView(
              id: 'orders',
              config: const SuperListViewConfig(
                binding: JsonTextBinding(path: 'clients[?].orders'),
                itemExtent: 40,
              ),
              template: center(['label']),
              slots: [text('label', 'clients[?].orders[?].label')],
            ),
          ),
        ],
      ),
    );
    expect(row('clients', 0), findsOneWidget);
    expect(row('clients', 1), findsOneWidget);
    for (final label in ['Alice', 'Bob', 'A1', 'A2', 'B1']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(
      find.descendant(of: row('clients', 1), matching: find.text('B1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('clients', 1), matching: find.text('A1')),
      findsNothing,
    );
  });

  testWidgets(
    'horizontal rows retain their extent and spacing with IterableContent',
    (tester) async {
      await mount(
        tester,
        SuperListView(
          id: 'clients',
          config: SuperListViewConfig(
            axis: Axis.horizontal,
            spacing: 12,
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
            itemExtent: 180,
          ),
          templateStyle: const ContainerStyle(
            padding: 5,
            margin: 3,
            color: Colors.blue,
          ),
          template: center(['name']),
          slots: [text('name', 'clients[?].name')],
        ),
      );
      expect(find.byType(IterableContent), findsNWidgets(2));
      expect(tester.getSize(row('clients', 0)).width, 192);
      expect(
        tester.getTopLeft(row('clients', 1)).dx -
            tester.getTopLeft(row('clients', 0)).dx,
        192,
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a text field in a row writes its own element', (tester) async {
    await mount(
      tester,
      SuperListView(
        id: 'clients',
        config: SuperListViewConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          itemExtent: 80,
        ),
        template: center(['name']),
        slots: [text('name', 'clients[?].name', mode: SuperTextMode.input)],
      ),
    );
    final field = find.descendant(
      of: row('clients', 1),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, 'Bob');
    await real(tester, () => tester.enterText(field, 'Bobby'), save: true);
    final clients = (await document(tester))['clients'] as List;
    expect(clients[1]['name'], 'Bobby');
    expect(clients[0]['name'], 'Alice');
  });

  testWidgets('rows can be added and removed', (tester) async {
    await mount(
      tester,
      SuperListView(
        id: 'clients',
        config: SuperListViewConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          itemExtent: 60,
          allowAdd: true,
          allowRemove: true,
        ),
        template: center(['name']),
        slots: [text('name', 'clients[?].name')],
      ),
    );
    await real(
      tester,
      () => tester.tap(find.byKey(const ValueKey('super-list-add-clients'))),
      save: true,
    );
    expect(row('clients', 2), findsOneWidget);
    var clients = (await document(tester))['clients'] as List;
    expect(clients, hasLength(3));
    expect(clients[2], {'name': '', 'orders': []});

    await real(
      tester,
      () =>
          tester.tap(find.byKey(const ValueKey('super-list-remove-clients-0'))),
    );
    await real(
      tester,
      () => tester.tap(find.widgetWithText(FilledButton, 'Supprimer')),
      save: true,
    );
    clients = (await document(tester))['clients'] as List;
    expect(clients.map((client) => client['name']), ['Bob', '']);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('unbound and empty lists explain their state', (tester) async {
    await mount(tester, const SuperListView(id: 'unbound'));
    expect(
      find.byKey(const ValueKey('super-list-message-unbound')),
      findsOneWidget,
    );
    await mount(
      tester,
      SuperListView(
        id: 'empty',
        config: SuperListViewConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'none'),
          emptyText: 'Vide !',
        ),
      ),
    );
    expect(find.text('Vide !'), findsOneWidget);
  });

  testWidgets('the editor rebinds the list and validates paths', (
    tester,
  ) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await mount(
      tester,
      StyleEditScope(
        controller: editing,
        child: SuperListView(
          id: 'clients',
          config: SuperListViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          ),
          template: center(['name']),
          slots: [text('name', 'clients[?].name')],
        ),
      ),
    );
    await real(
      tester,
      () => tester.tap(row('clients', 0), buttons: kSecondaryMouseButton),
    );
    await real(
      tester,
      () => tester.tap(find.byKey(const ValueKey('style-menu-Liste'))),
    );
    final path = find.byKey(const ValueKey('super-list-path'));
    await tester.enterText(path, 'clients[');
    await real(
      tester,
      () => tester.tap(find.byKey(const ValueKey('super-list-apply'))),
    );
    expect(find.byKey(const ValueKey('super-list-apply')), findsOneWidget);
    expect(find.textContaining('Chemin JSON invalide'), findsWidgets);
    await tester.enterText(path, 'clients[0].orders');
    await real(
      tester,
      () => tester.tap(find.byKey(const ValueKey('super-list-apply'))),
    );
    expect(find.byKey(const ValueKey('super-list-apply')), findsNothing);
    expect(row('clients', 1), findsOneWidget);
    expect(row('clients', 2), findsNothing);
  });

  testWidgets('edit mode shows a template row for empty arrays', (
    tester,
  ) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await mount(
      tester,
      StyleEditScope(
        controller: editing,
        child: SuperListView(
          id: 'empty',
          config: SuperListViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'none'),
          ),
          template: center(['inner', 'value']),
          slots: [
            text('value', 'none[?].value'),
            BuilderSlot(
              id: 'inner',
              label: 'inner',
              showLabel: false,
              builder: (_) => const SuperListView(
                id: 'inner',
                config: SuperListViewConfig(
                  binding: JsonTextBinding(path: 'none[?].children'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    expect(row('empty', 'template'), findsOneWidget);
    expect(row('inner', 'template'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('super-list-message-inner')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('super-text-value-error')), findsNothing);
  });

  group('master/detail', () {
    Widget outside(String id, String path) => SuperText(
      id: id,
      config: SuperTextConfig(
        mode: SuperTextMode.input,
        binding: JsonTextBinding(repositoryId: repository, path: path),
      ),
    );

    // The detail is not a component: plain SuperTexts and a list placed
    // outside the master read the selected rows through their [?].
    Widget page({bool allowChanges = false}) => Column(
      children: [
        SizedBox(
          height: 360,
          child: SuperListView(
            id: 'clients',
            config: SuperListViewConfig(
              binding: JsonTextBinding(
                repositoryId: repository,
                path: 'clients',
              ),
              itemExtent: 140,
              allowAdd: allowChanges,
              allowRemove: allowChanges,
            ),
            template: center(['name', 'orders']),
            slots: [
              text('name', 'clients[?].name'),
              BuilderSlot(
                id: 'orders',
                label: 'orders',
                showLabel: false,
                builder: (_) => SuperListView(
                  id: 'orders',
                  config: const SuperListViewConfig(
                    binding: JsonTextBinding(path: 'clients[?].orders'),
                    itemExtent: 32,
                  ),
                  template: center(['label']),
                  slots: [text('label', 'clients[?].orders[?].label')],
                ),
              ),
            ],
          ),
        ),
        outside('detailName', 'clients[?].name'),
        SizedBox(
          height: 120,
          child: SuperListView(
            id: 'detailOrders',
            config: SuperListViewConfig(
              binding: JsonTextBinding(
                repositoryId: repository,
                path: 'clients[?].orders',
              ),
              itemExtent: 32,
            ),
            template: center(['detailLabel']),
            slots: [text('detailLabel', 'clients[?].orders[?].label')],
          ),
        ),
        outside('orderLabel', 'clients[?].orders[?].label'),
      ],
    );

    Finder selected(String list, int index) =>
        find.byKey(ValueKey('super-list-selected-$list-$index'));
    Finder input(String id) => find.byKey(ValueKey('super-text-input-$id'));
    TextField field(WidgetTester tester, String id) =>
        tester.widget<TextField>(input(id));
    Future<void> select(WidgetTester tester, Finder target) =>
        real(tester, () => tester.tap(target));

    testWidgets('clicking a row shows it in bindings outside the list', (
      tester,
    ) async {
      await mount(tester, page());
      expect(field(tester, 'detailName').controller!.text, '');
      expect(field(tester, 'detailName').readOnly, isTrue);
      expect(find.text('Aucune ligne sélectionnée.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('super-text-detailName-error')),
        findsNothing,
      );

      await select(
        tester,
        find.descendant(of: row('clients', 1), matching: find.text('Bob')),
      );
      expect(selected('clients', 1), findsOneWidget);
      expect(selected('clients', 0), findsNothing);
      expect(field(tester, 'detailName').controller!.text, 'Bob');
      expect(field(tester, 'detailName').readOnly, isFalse);
      expect(row('detailOrders', 0), findsOneWidget);
      expect(row('detailOrders', 1), findsNothing);
      expect(
        find.descendant(of: row('detailOrders', 0), matching: find.text('B1')),
        findsOneWidget,
      );
      expect(field(tester, 'orderLabel').controller!.text, '');

      await select(
        tester,
        find.descendant(of: row('clients', 0), matching: find.text('A2')),
      );
      expect(selected('clients', 0), findsOneWidget);
      expect(field(tester, 'detailName').controller!.text, 'Alice');
      // The click selected the order too: [client 0, order 1], also
      // highlighted in the outside list of the same array template.
      expect(selected('orders', 1), findsOneWidget);
      expect(selected('detailOrders', 1), findsOneWidget);
      expect(field(tester, 'orderLabel').controller!.text, 'A2');

      // Selecting in the outside list updates the order binding.
      await select(
        tester,
        find.descendant(of: row('detailOrders', 0), matching: find.text('A1')),
      );
      expect(field(tester, 'orderLabel').controller!.text, 'A1');
      expect(selected('orders', 0), findsOneWidget);

      // Another client: its orders have no selection.
      await select(
        tester,
        find.descendant(of: row('clients', 1), matching: find.text('Bob')),
      );
      expect(field(tester, 'orderLabel').controller!.text, '');
      expect(field(tester, 'orderLabel').readOnly, isTrue);

      // The outside binding writes the selected element; the master follows.
      await real(
        tester,
        () => tester.enterText(input('detailName'), 'Bobby'),
        save: true,
      );
      expect(
        find.descendant(of: row('clients', 1), matching: find.text('Bobby')),
        findsOneWidget,
      );
      final clients = (await document(tester))['clients'] as List;
      expect(clients[0]['name'], 'Alice');
      expect(clients[1]['name'], 'Bobby');
    });

    testWidgets('selection follows additions and removals', (tester) async {
      await mount(tester, page(allowChanges: true));
      await select(
        tester,
        find.descendant(of: row('clients', 1), matching: find.text('Bob')),
      );
      await real(
        tester,
        () => tester.tap(
          find.byKey(const ValueKey('super-list-remove-clients-0')),
        ),
      );
      await real(
        tester,
        () => tester.tap(find.widgetWithText(FilledButton, 'Supprimer')),
        save: true,
      );
      expect(selected('clients', 0), findsOneWidget);
      expect(field(tester, 'detailName').controller!.text, 'Bob');

      await tester.drag(
        find.byKey(const ValueKey('super-list-clients')),
        const Offset(0, -400),
      );
      await real(
        tester,
        () => tester.tap(find.byKey(const ValueKey('super-list-add-clients'))),
        save: true,
      );
      expect(selected('clients', 1), findsOneWidget);
      expect(field(tester, 'detailName').controller!.text, '');
      expect(field(tester, 'detailName').readOnly, isFalse);

      await real(
        tester,
        () => tester.tap(
          find.byKey(const ValueKey('super-list-remove-clients-1')),
        ),
      );
      await real(
        tester,
        () => tester.tap(find.widgetWithText(FilledButton, 'Supprimer')),
        save: true,
      );
      expect(selected('clients', 0), findsNothing);
      expect(field(tester, 'detailName').readOnly, isTrue);
    });

    testWidgets('the selection is shared by the repository, not the list', (
      tester,
    ) async {
      await mount(tester, page());
      // A selection made elsewhere (another list on the same array).
      store.bindingOf(repository).array('clients').select(const [], 1);
      await real(tester, () async {});
      expect(selected('clients', 1), findsOneWidget);
      expect(field(tester, 'detailName').controller!.text, 'Bob');
      // A file change removing the row clears the selection.
      await real(
        tester,
        () async => store.save(
          'Shop',
          jsonEncode({
            'clients': [
              {'name': 'Alice', 'orders': []},
            ],
          }),
          expectedText: await store.read('Shop'),
        ),
        save: true,
      );
      expect(store.bindingOf(repository).array('clients').selection, isNull);
      expect(field(tester, 'detailName').readOnly, isTrue);
    });
  });
}
