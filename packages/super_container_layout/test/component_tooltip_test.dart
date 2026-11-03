import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _Extension extends SuperComponentExtension {
  @override
  String get registryType => 'TestExtension';
  @override
  void registerCodecs() {}
  @override
  void register(
    Registry registry, {
    List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
  }) {
    registry.registry[registryType] = ComponentBuilderDynamic(
      dynamicBuilder: (_) => const ColoredBox(
        color: Colors.blue,
        child: SizedBox(width: 100, height: 60),
      ),
    );
  }
}

class _Probe extends StatefulWidget {
  const _Probe(this.onInit);
  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 100, height: 60);
}

void main() {
  ComponentBehavior tooltip(
    String message, {
    bool enabled = true,
    JsonTextBinding? binding,
  }) => ComponentBehavior(
    id: 'tooltip-$message',
    trigger: BehaviorTrigger.hover,
    action: TooltipAction(message: message, binding: binding),
    enabled: enabled,
  );

  test('tooltip model, compact binding and appearance round-trip', () {
    const repositoryId = '0123456789abcdef0123456789abcdef';
    for (final binding in [
      null,
      const JsonTextBinding(path: 'rows[?].description'),
      const JsonTextBinding(repositoryId: repositoryId, path: 'description'),
    ]) {
      final behavior = tooltip('Description', binding: binding);
      for (final json in [behavior.toJson(), behavior.toCompactJson()]) {
        final decoded = ComponentBehavior.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
        );
        expect(decoded, behavior);
        expect(decoded.hashCode, behavior.hashCode);
      }
      const codec = AppearanceCodec();
      final restored = codec.decode(
        codec.encode(
          Appearance(
            behaviors: {
              'target': [behavior],
            },
          ),
        ),
      );
      expect(restored.behaviorsFor('target'), [behavior]);
      expect(
        (behavior.action as TooltipAction).copyWith(clearBinding: true),
        const TooltipAction(message: 'Description'),
      );
    }
    expect(BehaviorCatalog.items, contains(BehaviorCatalog.onTooltip));
    expect(BehaviorTrigger.gestures, isNot(contains(BehaviorTrigger.hover)));
    expect(
      () => TooltipAction.fromJson({'message': ''}),
      throwsFormatException,
    );
    expect(
      () => TooltipAction.fromJson({'message': 42}),
      throwsFormatException,
    );
    expect(
      () => TooltipAction.fromJson({
        'binding': {'path': 'invalid..path'},
      }),
      throwsFormatException,
    );
    expect(
      () => ComponentBehavior.fromJson({
        'id': 'wrong',
        'trigger': 'click',
        'action': {'type': 'onTooltip', 'message': 'Wrong trigger'},
      }),
      throwsFormatException,
    );
  });

  late ValueNotifier<Appearance> appearance;
  late ValueNotifier<bool> editing;

  setUp(() {
    appearance = ValueNotifier(Appearance());
    editing = ValueNotifier(false);
  });

  tearDown(() {
    appearance.dispose();
    editing.dispose();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    JsonRepositoryStore? store,
    Duration wait = Duration.zero,
  }) {
    final app = MaterialApp(
      theme: ThemeData(
        tooltipTheme: TooltipThemeData(
          waitDuration: wait,
          excludeFromSemantics: true,
        ),
      ),
      home: Scaffold(body: Center(child: child)),
    );
    return tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: StyleEditScope(
          controller: editing,
          child: store == null
              ? app
              : JsonRepositoryScope(store: store, child: app),
        ),
      ),
    );
  }

  Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(finder));
    await tester.pumpAndSettle();
    return mouse;
  }

  testWidgets(
    'first enabled wins, honors wait, edit mode and native priority',
    (tester) async {
      appearance.value = Appearance(
        behaviors: {
          'target': [
            tooltip('Disabled', enabled: false),
            tooltip('First'),
            tooltip('Second'),
          ],
        },
      );
      await mount(
        tester,
        const EditorSlot(
          id: 'target',
          child: Tooltip(
            message: 'Native',
            child: SizedBox(width: 100, height: 60),
          ),
        ),
        wait: const Duration(milliseconds: 400),
      );
      await tester.longPress(find.byType(EditorSlot));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(EditorSlot)));
      await tester.pump(const Duration(milliseconds: 399));
      expect(find.text('First'), findsNothing);
      await tester.pump(const Duration(milliseconds: 201));
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Native'), findsNothing);
      expect(find.text('Disabled'), findsNothing);
      expect(find.text('Second'), findsNothing);

      editing.value = true;
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      editing.value = false;
      appearance.value = Appearance();
      await tester.pumpAndSettle();
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(EditorSlot)));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.text('Native'), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.text('Native'), findsNothing);
    },
  );

  testWidgets(
    'same ID is deduplicated and child native tooltips remain usable',
    (tester) async {
      appearance.value = Appearance(
        behaviors: {
          'parent': [tooltip('Parent')],
        },
      );
      await mount(
        tester,
        ComponentTooltip(
          componentId: 'parent',
          child: const EditorSlot(
            id: 'parent',
            child: SizedBox(
              width: 200,
              height: 150,
              child: Center(
                child: EditorSlot(
                  id: 'child',
                  child: Tooltip(
                    message: 'Child native',
                    child: SizedBox(width: 60, height: 40),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == 'Parent',
        ),
        findsOneWidget,
      );
      final child = find.byWidgetPredicate(
        (widget) => widget is EditorSlot && widget.id == 'child',
      );
      final mouse = await hover(tester, child);
      expect(find.text('Child native'), findsOneWidget);
      expect(find.text('Parent'), findsNothing);
      await mouse.removePointer();
      await tester.pumpAndSettle();

      appearance.value = Appearance(
        behaviors: {
          'parent': [tooltip('Parent')],
          'child': [tooltip('Child behavior')],
        },
      );
      await tester.pumpAndSettle();
      final nextMouse = await hover(tester, child);
      expect(find.text('Child behavior'), findsOneWidget);
      expect(find.text('Child native'), findsNothing);
      expect(find.text('Parent'), findsNothing);
      await nextMouse.removePointer();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('registered extension and host slots need no tooltip code', (
    tester,
  ) async {
    final registry = Registry()..registerExtension(_Extension());
    appearance.value = Appearance(
      behaviors: {
        'extension': [tooltip('Extension tooltip')],
        'host': [tooltip('Host tooltip')],
      },
    );
    await mount(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuilderSlot(
            id: 'extension',
            label: 'Extension',
            builder: (_) => registry.getWidget(
              'TestExtension',
              XuiBuildCtx(id: 'extension'),
            ),
          ),
          BuilderSlot(
            id: 'host',
            label: 'Host',
            builder: (_) => const SizedBox(width: 100, height: 60),
          ),
        ],
      ),
    );
    for (final id in ['extension', 'host']) {
      final mouse = await hover(tester, find.byKey(ValueKey('slot-$id')));
      expect(
        find.text(id == 'host' ? 'Host tooltip' : 'Extension tooltip'),
        findsOneWidget,
      );
      await mouse.removePointer();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('tooltip changes preserve state and nested code overrides win', (
    tester,
  ) async {
    var initializations = 0;
    await mount(
      tester,
      ComponentTooltip(
        componentId: 'target',
        child: _Probe(() => initializations++),
      ),
    );
    appearance.value = Appearance(
      behaviors: {
        'target': [tooltip('New')],
      },
    );
    await tester.pumpAndSettle();
    appearance.value = Appearance();
    await tester.pumpAndSettle();
    expect(initializations, 1);
    appearance.value = Appearance(
      behaviors: {
        'target': [tooltip('Stored')],
      },
    );
    await mount(
      tester,
      BuilderSlot(
        id: 'target',
        label: 'Target',
        builder: (_) => Builder(
          builder: (_) => const EditorSlot(
            id: 'target',
            behaviors: [],
            child: SizedBox(width: 100, height: 60),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets(
    'sliver tooltip preserves scrolling geometry and closes on exit',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      appearance.value = Appearance(
        behaviors: {
          'sliver': [tooltip('Sliver')],
        },
      );
      await mount(
        tester,
        SizedBox(
          width: 300,
          height: 200,
          child: CustomScrollView(
            controller: controller,
            slivers: [
              SliverSlotScope(
                child: const EditorSlot(
                  id: 'sliver',
                  child: SliverToBoxAdapter(
                    child: SizedBox(
                      key: ValueKey('sliver-content'),
                      height: 500,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      expect(controller.position.maxScrollExtent, 300);
      final mouse = await hover(tester, find.byType(CustomScrollView));
      await tester.pumpAndSettle();
      expect(find.text('Sliver'), findsOneWidget);
      expect(controller.position.maxScrollExtent, 300);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.text('Sliver'), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  group('repository tooltips', () {
    late Directory directory;
    late JsonRepositoryStore store;
    late String repositoryId;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('component-tooltip-');
      store = JsonRepositoryStore(directory);
      await store.create('Tooltips');
      repositoryId = await store.idOf('Tooltips');
    });

    tearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    Future<void> save(WidgetTester tester, Object value) async {
      await tester.runAsync(() async {
        final before = await store.read('Tooltips');
        await store.save('Tooltips', jsonEncode(value), expectedText: before);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    Future<void> settleRead(WidgetTester tester) async {
      await tester.runAsync(() async {
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      });
      await tester.pumpAndSettle();
    }

    for (final linked in [false, true]) {
      testWidgets(
        'wizard saves ${linked ? 'binding' : 'text'} and supports undo',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1200, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          editing.value = true;
          final history = EditorHistoryController(
            appearance: appearance,
            editMode: editing,
          );
          addTearDown(history.dispose);
          await mount(
            tester,
            EditorHistoryScope(
              controller: history,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showComponentBehaviorWizard(
                    context: context,
                    targets: const [
                      BehaviorTargetElement(
                        id: 'custom-component',
                        label: 'Custom',
                      ),
                    ],
                  ),
                  child: const Text('Open wizard'),
                ),
              ),
            ),
            store: store,
          );
          await tester.tap(find.text('Open wizard'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
          await tester.pumpAndSettle();
          final catalogItem = find.byKey(
            const ValueKey('behavior-catalog-onTooltip'),
          );
          await tester.ensureVisible(catalogItem);
          await tester.tap(catalogItem);
          await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
          await settleRead(tester);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('behavior-add-next')),
                )
                .onPressed,
            isNull,
          );
          if (linked) {
            await tester.tap(
              find.byKey(const ValueKey('behavior-tooltip-binding-repository')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Tooltips').last);
            await tester.pumpAndSettle();
            final path = find.byKey(
              const ValueKey('behavior-tooltip-binding-repository-path'),
            );
            await tester.enterText(path, 'invalid..path');
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('behavior-add-next')),
                  )
                  .onPressed,
              isNull,
            );
            await tester.enterText(path, 'description');
          } else {
            await tester.enterText(
              find.byKey(const ValueKey('behavior-tooltip-message')),
              'Wizard tooltip',
            );
          }
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
          await tester.pumpAndSettle();
          expect(
            find.text(
              linked ? '$repositoryId : description' : 'Wizard tooltip',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
          await tester.pumpAndSettle();
          final saved = appearance.value
              .behaviorsFor('custom-component')
              .single;
          expect(saved.trigger, BehaviorTrigger.hover);
          final action = saved.action as TooltipAction;
          expect(
            action.binding,
            linked
                ? JsonTextBinding(
                    repositoryId: repositoryId,
                    path: 'description',
                  )
                : null,
          );
          expect(history.canUndo, isTrue);
          history.undo();
          expect(appearance.value.behaviorsFor('custom-component'), isEmpty);
          history.redo();
          expect(appearance.value.behaviorsFor('custom-component'), [saved]);
        },
      );
    }

    testWidgets('reacts to data, selection, empty values and errors', (
      tester,
    ) async {
      await save(tester, {
        'rows': [
          {'description': 'First row'},
          {'description': 'Second row'},
        ],
      });
      appearance.value = Appearance(
        behaviors: {
          'target': [
            tooltip(
              'Not a fallback',
              binding: JsonTextBinding(
                repositoryId: repositoryId,
                path: 'rows[?].description',
              ),
            ),
          ],
        },
      );
      await mount(
        tester,
        const EditorSlot(id: 'target', child: SizedBox(width: 100, height: 60)),
        store: store,
      );
      await settleRead(tester);
      expect(find.byType(Tooltip), findsNothing);
      store.bindingOf(repositoryId).array('rows').select([], 1);
      await settleRead(tester);
      final mouse = await hover(tester, find.byType(EditorSlot));
      expect(find.text('Second row'), findsOneWidget);
      await save(tester, {
        'rows': [
          {'description': 'First row'},
          {'description': 'Updated row'},
        ],
      });
      expect(find.text('Updated row'), findsOneWidget);
      await save(tester, {
        'rows': [
          {'description': 'First row'},
          {'description': null},
        ],
      });
      expect(find.text('Updated row'), findsNothing);
      expect(find.text('Not a fallback'), findsNothing);
      await save(tester, {
        'rows': [
          {'description': 'First row'},
          {'description': 42},
        ],
      });
      expect(store.errors.value, contains('La valeur liée doit être un texte'));
      expect(find.text('Not a fallback'), findsNothing);
      store.bindingOf(repositoryId).array('rows').clear();
      await settleRead(tester);
      expect(find.byType(Tooltip), findsNothing);
      await mouse.removePointer();
      await tester.pumpAndSettle();
    });

    testWidgets('inherited row scope changes and placeholder skip reads', (
      tester,
    ) async {
      await save(tester, {
        'rows': [
          {'description': 'First row'},
          {'description': 'Second row'},
        ],
      });
      appearance.value = Appearance(
        behaviors: {
          'target': [
            tooltip(
              '',
              binding: const JsonTextBinding(path: 'rows[?].description'),
            ),
          ],
        },
      );
      Widget row(int index, {bool placeholder = false}) => JsonListScope(
        repositoryId: repositoryId,
        indices: [index],
        placeholder: placeholder,
        child: const EditorSlot(
          id: 'target',
          child: SizedBox(width: 100, height: 60),
        ),
      );
      await mount(tester, row(0), store: store);
      await settleRead(tester);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'First row');
      await mount(tester, row(1), store: store);
      await settleRead(tester);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Second row',
      );
      await mount(tester, row(1, placeholder: true), store: store);
      await settleRead(tester);
      expect(find.byType(Tooltip), findsNothing);
      expect(store.errors.value, isNull);
    });
  });
}
