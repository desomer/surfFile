import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

String document([String text = 'Imported']) => AppearanceTransfer.export(
  Appearance(
    components: {
      'page': ScaffoldPageConfig(
        placements: {
          ScaffoldPageRegion.body: ['text'],
        },
        slotTypes: {'text': 'registry:Value'},
      ),
      'text': SuperValueConfig(initialText: text),
    },
    pageCatalog: EditorPageCatalog(
      homePageId: 'page',
      pages: [EditorPageConfig(id: 'page', name: 'Page', path: '/page')],
    ),
  ),
  {...TransferGroup.values},
);

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('navigation stays within the imported page catalog', (
    tester,
  ) async {
    final initial = AppearanceTransfer.import(Appearance(), document(), {
      ...TransferGroup.values,
    });
    final appearance = initial.copyWith(
      components: {
        ...initial.components,
        'details': ScaffoldPageConfig(
          placements: {
            ScaffoldPageRegion.body: ['detail-text'],
          },
          slotTypes: {'detail-text': 'registry:Value'},
        ),
        'detail-text': const SuperValueConfig(initialText: 'Details'),
      },
      pageCatalog: EditorPageCatalog(
        homePageId: 'page',
        pages: [
          ...initial.pageCatalog.pages,
          EditorPageConfig(id: 'details', name: 'Details', path: '/details'),
        ],
      ),
      behaviors: {
        'text': [
          const ComponentBehavior(
            id: 'navigate',
            trigger: BehaviorTrigger.click,
            action: GoToPageAction(pagePath: '/details'),
          ),
        ],
      },
    );
    await tester.pumpWidget(
      host(
        SuperRenderer(
          source: AppearanceTransfer.export(appearance, {
            ...TransferGroup.values,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imported'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bindings and events use host-owned services', (tester) async {
    const repositoryId = 'pan_model_repository';
    final store = JsonRepositoryStore(Directory.systemTemp)
      ..registerRepository(
        RepositoryImpl(id: repositoryId, json: {'name': 'Bound value'}),
      );
    final bus = SuperEventBus();
    final events = <SuperComponentEvent>[];
    final subscription = bus.on('clicked').listen(events.add);
    addTearDown(() async {
      store.dispose();
      await subscription.cancel();
      await bus.close();
    });
    final appearance = Appearance(
      components: {
        'text': const SuperValueConfig(
          binding: JsonTextBinding(repositoryId: repositoryId, path: 'name'),
        ),
      },
      behaviors: {
        'text': [
          ComponentBehavior(
            id: 'emit',
            trigger: BehaviorTrigger.click,
            action: EmitEventAction(eventId: 'clicked'),
          ),
        ],
      },
    );
    await tester.pumpWidget(
      host(
        SuperRenderer(
          source: AppearanceTransfer.export(appearance, {
            ...TransferGroup.values,
          }),
          repositoryStore: store,
          eventBus: bus,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bound value'), findsOneWidget);
    await tester.tap(find.text('Bound value'));
    await tester.pumpAndSettle();
    expect(events, hasLength(1));
    expect(events.single.componentId, 'text');
    expect(tester.takeException(), isNull);
  });

  testWidgets('context menu exports internal components but not the renderer', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      host(SuperRenderer(source: document(), editMode: true)),
    );
    await tester.pumpAndSettle();
    final target = find.byWidgetPredicate(
      (widget) => widget is EditorSlot && widget.id == 'text',
    );
    final state = tester.state<EditorSlotState>(target.first);
    final menu = state.openMenu(tester.getCenter(target.first));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('style-menu-SuperRenderer')),
      findsNothing,
    );
    final more = find.byKey(ValueKey('style-menu-more-${state.label}'));
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('style-menu-export-${state.label}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-mode')), findsNothing);
    expect(find.byKey(const ValueKey('transfer-import-text')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('transfer-copy')));
    await tester.tap(find.byKey(const ValueKey('transfer-copy')));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    final imported = AppearanceTransfer.import(Appearance(), copied!, {
      ...TransferGroup.values,
    });
    expect(imported.components.containsKey('text'), isTrue);
    expect(imported.components.containsKey('page'), isFalse);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    await menu;

    final renderer = find.byWidgetPredicate(
      (widget) =>
          widget is EditorSlot && widget.eventComponentType == 'renderer',
    );
    final rendererState = tester.state<EditorSlotState>(renderer);
    final outerMenu = rendererState.openMenu(tester.getCenter(renderer));
    await tester.pumpAndSettle();
    final outerMore = find.byKey(
      const ValueKey('style-menu-more-SuperRenderer'),
    );
    if (outerMore.evaluate().isNotEmpty) {
      await tester.tap(outerMore);
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const ValueKey('style-menu-export-SuperRenderer')),
      findsNothing,
    );
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    // Le sous-menu peut absorber le premier clic exterieur.
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    await outerMenu;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit component root and root picker render the selected item',
    (tester) async {
      await tester.pumpWidget(
        host(SuperRenderer(source: document(), rootId: 'text')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Imported'), findsOneWidget);
      final context = tester.element(find.text('Imported'));
      final local = SuperApp.of(context).registry!;
      local.valueController('text').value = const SuperValueConfig(
        initialText: 'Root changed',
      );
      await tester.pumpAndSettle();
      expect(find.text('Root changed'), findsOneWidget);
      expect(local.scaffoldPageConfigById.length, 1);
      await tester.tap(find.byKey(const ValueKey('renderer-select-root')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('page').last);
      await tester.pumpAndSettle();
      expect(find.text('Root changed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('renderer codec, aliases and patches round trip', () {
    final config = SuperRendererConfig(source: document(), rootId: 'page');
    expect(ComponentConfig.fromJson(config.toTypedJson()), config);
    expect(
      config.patchFromJson({'rootId': null, 'showImport': false}),
      config.copyWith(clearRoot: true, showImport: false),
    );
    expect(JsonComponentType.normalize('SuperRenderer'), 'registry:Renderer');
    expect(
      () => SuperRendererConfig.fromJson({'source': '[]'}),
      throwsFormatException,
    );
    expect(
      () => SuperRendererConfig.fromJson({'unknown': true}),
      throwsFormatException,
    );
    final registry = Registry()..bootstrap();
    expect(registry.registry['Renderer']?.addConfigurator, isNotNull);
  });

  testWidgets('renders, updates and preserves content after invalid import', (
    tester,
  ) async {
    Widget renderer(String source) => host(SuperRenderer(source: source));
    await tester.pumpWidget(renderer(document()));
    await tester.pumpAndSettle();
    expect(find.text('Imported'), findsOneWidget);
    await tester.pumpWidget(renderer(document('Updated')));
    await tester.pumpAndSettle();
    expect(find.text('Updated'), findsOneWidget);
    await tester.pumpWidget(renderer('{'));
    await tester.pumpAndSettle();
    expect(find.text('Updated'), findsOneWidget);
    expect(find.byKey(const ValueKey('renderer-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local editing emits a document without mutating the host', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final appearance = ValueNotifier<Appearance>(
      Appearance(
        components: {'text': const SuperValueConfig(initialText: 'Host')},
      ),
    );
    registry.bindAppearance(appearance);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    addTearDown(() {
      registry.unbindAppearance();
      appearance.dispose();
      router.dispose();
    });
    final changes = <String>[];
    await tester.pumpWidget(
      host(
        SuperAppScope(
          app: SuperApp(router: router, registry: registry),
          child: AppearanceScope(
            controller: appearance,
            child: SuperRenderer(
              source: document(),
              editMode: true,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final textContext = tester.element(find.text('Imported').first);
    final local = SuperApp.of(textContext).registry!;
    expect(local, isNot(same(registry)));
    local.valueController('text').value = const SuperValueConfig(
      initialText: 'Edited locally',
    );
    await tester.pumpAndSettle();
    expect(find.text('Edited locally'), findsOneWidget);
    expect(appearance.value.valueComponent('text').initialText, 'Host');
    expect(changes, isNotEmpty);
    final imported = AppearanceTransfer.import(Appearance(), changes.last, {
      ...TransferGroup.values,
    });
    expect(imported.valueComponent('text').initialText, 'Edited locally');
    expect(
      appearance.value.components.values.whereType<SuperRendererConfig>(),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('two renderers with identical IDs remain isolated', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Row(
          children: [
            Expanded(child: SuperRenderer(source: document('First'))),
            Expanded(child: SuperRenderer(source: document('Second'))),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = SuperApp.of(tester.element(find.text('First'))).registry!;
    first.valueController('text').value = const SuperValueConfig(
      initialText: 'Changed',
    );
    await tester.pumpAndSettle();
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import-only interface supports pasted JSON', (tester) async {
    await tester.pumpWidget(host(const SuperRenderer()));
    await tester.tap(find.byKey(const ValueKey('renderer-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-mode')), findsNothing);
    expect(find.byKey(const ValueKey('transfer-copy')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('transfer-import-text')),
      document('Pasted'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Pasted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import-only interface reads a file', (tester) async {
    final directory = Directory.systemTemp.createTempSync('renderer-test-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}appearance.json',
    );
    file.writeAsStringSync(document('From file'));
    addTearDown(() {
      file.deleteSync();
      directory.deleteSync();
    });
    await tester.pumpWidget(host(const SuperRenderer()));
    await tester.tap(find.byKey(const ValueKey('renderer-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transfer-file')),
      file.path,
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('transfer-read')));
      // Attend la lecture reelle, hors de l'horloge simulee des widgets.
      for (var attempt = 0; attempt < 100; attempt++) {
        if (tester
            .widget<TextField>(
              find.byKey(const ValueKey('transfer-import-text')),
            )
            .controller!
            .text
            .isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-apply')));
    await tester.pumpAndSettle();
    expect(find.text('From file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
