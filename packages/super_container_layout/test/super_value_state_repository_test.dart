import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _DelayedStore extends JsonRepositoryStore {
  _DelayedStore(super.directory);
  Completer<void>? nextWrite;
  Completer<void>? nextRead;

  @override
  Future<JsonAttributeValue> readAttribute(JsonTextBinding binding) async {
    final pending = nextRead;
    nextRead = null;
    if (pending != null) await pending.future;
    return super.readAttribute(binding);
  }

  @override
  Future<JsonAttributeValue> writeAttribute(
    JsonTextBinding binding,
    String text, {
    required Object? expectedValue,
    bool asBool = false,
  }) async {
    final pending = nextWrite;
    nextWrite = null;
    if (pending != null) await pending.future;
    return super.writeAttribute(
      binding,
      text,
      expectedValue: expectedValue,
      asBool: asBool,
    );
  }
}

void main() {
  late Directory directory;
  late _DelayedStore store;
  late String repository;
  JsonTextBinding binding(String path) =>
      JsonTextBinding(repositoryId: repository, path: path);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('text-states-');
    store = _DelayedStore(directory);
    await store.create('States');
    repository = await store.idOf('States');
    await store.save(
      'States',
      jsonEncode({'status': 'default', 'a': 'Alice', 'b': 'Bob', 'size': 22}),
      expectedText: await store.read('States'),
    );
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> real(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    SuperValueConfig config, {
    ValueChanged<String>? onChanged,
  }) async {
    await real(
      tester,
      () => tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 100,
                  child: SuperValue(
                    id: 'state',
                    config: config,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> close(WidgetTester tester) async {
    await real(tester, () => tester.pumpWidget(const SizedBox()));
    await real(tester, store.flushBindings);
  }

  final field = find.byKey(const ValueKey('super-value-input-state'));
  String text(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.text;

  testWidgets(
    'empty hover keeps bound text, enabled style and focus stable during each reload',
    (tester) async {
      final changes = <String>[];
      await mount(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          binding: binding('a'),
          states: ValueConfigStates(hover: ValueConfigOverride()),
        ),
        onChanged: changes.add,
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(field).controller!;
      final observed = <String>[];
      void observe() => observed.add(controller.text);
      controller.addListener(observe);
      final before = await tester.runAsync(() => store.read('States'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final position in [tester.getCenter(field), Offset.zero]) {
        final blocked = Completer<void>();
        store.nextRead = blocked;
        addTearDown(() {
          if (!blocked.isCompleted) blocked.complete();
        });
        await real(tester, () => mouse.moveTo(position));
        expect(
          store.nextRead,
          isNull,
          reason: 'The state still reloads its content binding',
        );
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final input = tester.widget<TextField>(field);
          expect(input.enabled, isTrue);
          expect(input.focusNode!.hasFocus, isTrue);
          expect(input.controller, same(controller));
          expect(input.controller!.text, 'Alice');
        }
        await real(tester, () async {
          blocked.complete();
        });
        expect(observed, isEmpty);
        expect(changes, isEmpty);
      }
      controller.removeListener(observe);
      expect(await tester.runAsync(() => store.read('States')), before);
      await mouse.removePointer();
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'JSON states change content binding and property bindings reactively',
    (tester) async {
      await mount(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          binding: binding('a'),
          states: ValueConfigStates(
            binding: binding('status'),
            named: {
              'second': SuperValueConfig(
                mode: SuperValueMode.input,
                binding: binding('b'),
                propertyBindings: {SuperValueProperty.fontSize: binding('size')},
              ),
            },
            namedProperties: {
              'second': {ValueStateProperty.binding, ValueStateProperty.fontSize},
            },
          ),
        ),
      );
      expect(text(tester), 'Alice');
      await real(tester, () async {
        await store.writeAttribute(
          binding('status'),
          'second',
          expectedValue: 'default',
        );
      });
      expect(text(tester), 'Bob');
      expect(tester.widget<TextField>(field).style!.fontSize, 22);
      await real(tester, () async {
        await store.writeAttribute(binding('size'), '28', expectedValue: 22);
      });
      expect(tester.widget<TextField>(field).style!.fontSize, 28);
      await real(tester, () async {
        await store.writeAttribute(
          binding('status'),
          'unknown',
          expectedValue: 'second',
        );
      });
      expect(text(tester), 'Alice');
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hover never writes and captures pending edits to the old binding before reset',
    (tester) async {
      final changes = <String>[];
      await mount(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          binding: binding('a'),
          states: ValueConfigStates(
            hover: ValueConfigOverride(
              config: SuperValueConfig(binding: binding('b')),
              properties: {ValueStateProperty.binding},
            ),
          ),
        ),
        onChanged: changes.add,
      );
      final before = await tester.runAsync(() => store.read('States'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await real(tester, () => mouse.moveTo(tester.getCenter(field)));
      expect(text(tester), 'Bob');
      expect(await tester.runAsync(() => store.read('States')), before);
      expect(changes, isEmpty);
      await real(tester, () => mouse.moveTo(Offset.zero));
      expect(text(tester), 'Alice');
      await tester.enterText(field, 'Edited Alice');
      await tester.pump();
      await real(tester, () => mouse.moveTo(tester.getCenter(field)));
      expect(text(tester), 'Bob');
      expect(
        (await tester.runAsync(() => store.readAttribute(binding('a'))))!.text,
        'Edited Alice',
      );
      expect(
        (await tester.runAsync(() => store.readAttribute(binding('b'))))!.text,
        'Bob',
      );
      await mouse.removePointer();
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same content binding is reloaded without writing on a hover-only property transition',
    (tester) async {
      await mount(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          binding: binding('a'),
          states: ValueConfigStates(
            hover: ValueConfigOverride(
              config: const SuperValueConfig(fontSize: 24),
              properties: {ValueStateProperty.fontSize},
            ),
          ),
        ),
      );
      final before = await tester.runAsync(() => store.read('States'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await real(tester, () => mouse.moveTo(tester.getCenter(field)));
      expect(text(tester), 'Alice');
      expect(tester.widget<TextField>(field).style!.fontSize, 24);
      expect(await tester.runAsync(() => store.read('States')), before);
      await mouse.removePointer();
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid transitions wait for a previously detached pending write',
    (tester) async {
      await mount(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          binding: binding('a'),
          states: ValueConfigStates(
            hover: ValueConfigOverride(
              config: SuperValueConfig(binding: binding('b')),
              properties: {ValueStateProperty.binding},
            ),
          ),
        ),
      );
      final blocked = Completer<void>();
      store.nextWrite = blocked;
      addTearDown(() {
        if (!blocked.isCompleted) blocked.complete();
      });
      await tester.enterText(field, 'Pending Alice');
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await real(tester, () => mouse.moveTo(tester.getCenter(field)));
      await real(tester, () => mouse.moveTo(Offset.zero));
      expect(text(tester), 'Pending Alice');
      await real(tester, () async {
        blocked.complete();
      });
      expect(text(tester), 'Pending Alice');
      expect(
        (await tester.runAsync(() => store.readAttribute(binding('a'))))!.text,
        'Pending Alice',
      );
      expect(
        (await tester.runAsync(() => store.readAttribute(binding('b'))))!.text,
        'Bob',
      );
      await mouse.removePointer();
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live editor state preview stays detached from writable bindings',
    (tester) async {
      final changes = <String>[];
      await mount(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          binding: binding('a'),
          states: ValueConfigStates(
            binding: binding('status'),
            named: {
              'second': SuperValueConfig(
                mode: SuperValueMode.input,
                initialText: 'Second preview',
                binding: binding('b'),
              ),
            },
          ),
        ),
        onChanged: changes.add,
      );
      final before = await tester.runAsync(() => store.read('States'));
      final editing = tester
          .widget<EditorSlot>(find.byType(EditorSlot))
          .onEdit!();
      await real(tester, () async {
        await tester.pump();
      });
      for (final key in ['second', ValueConfigStates.hoverKey, '']) {
        final chip = find.byKey(ValueKey('value-state-choice-$key'));
        if (key == ValueConfigStates.hoverKey) {
          final add = find.byKey(const ValueKey('value-state-add'));
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('value-state-add-hover')));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await real(tester, () async {
          await tester.pump();
        });
      }
      final label = find.byKey(const ValueKey('super-value-setting-label'));
      await tester.ensureVisible(label);
      await tester.enterText(label, 'Only a draft');
      await real(tester, () async {
        await tester.pump();
      });
      expect(await tester.runAsync(() => store.read('States')), before);
      expect(changes, isEmpty);
      await tester.tap(find.text('Annuler').last);
      await real(tester, () async {
        await editing;
      });
      expect(text(tester), 'Alice');
      expect(await tester.runAsync(() => store.read('States')), before);
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focus transitions reload content without writes and JSON controls disabled trigger',
    (tester) async {
      final changes = <String>[];
      await mount(
        tester,
        SuperValueConfig(
          mode: SuperValueMode.input,
          binding: binding('a'),
          states: ValueConfigStates(
            binding: binding('status'),
            named: {
              'locked': SuperValueConfig(
                mode: SuperValueMode.input,
                enabled: false,
                binding: binding('a'),
              ),
            },
            namedProperties: {
              'locked': {ValueStateProperty.enabled},
            },
            automatic: {
              AutomaticState.focused: ValueConfigOverride(
                config: const SuperValueConfig(fontSize: 25),
                properties: {ValueStateProperty.fontSize},
              ),
              AutomaticState.disabled: ValueConfigOverride(
                config: const SuperValueConfig(color: Colors.red),
                properties: {ValueStateProperty.color},
              ),
            },
          ),
        ),
        onChanged: changes.add,
      );
      final before = await tester.runAsync(() => store.read('States'));
      await real(tester, () => tester.tap(field));
      expect(text(tester), 'Alice');
      expect(tester.widget<TextField>(field).style!.fontSize, 25);
      await real(tester, () async {
        tester.widget<TextField>(field).focusNode!.unfocus();
      });
      expect(text(tester), 'Alice');
      expect(changes, isEmpty);
      expect(await tester.runAsync(() => store.read('States')), before);
      await real(tester, () async {
        await store.writeAttribute(
          binding('status'),
          'locked',
          expectedValue: 'default',
        );
      });
      expect(tester.widget<TextField>(field).enabled, isFalse);
      expect(
        tester.widget<TextField>(field).style!.color!.toARGB32(),
        Colors.red.toARGB32(),
      );
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
