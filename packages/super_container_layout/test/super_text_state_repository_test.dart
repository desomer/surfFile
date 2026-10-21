import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repository;
  JsonTextBinding binding(String path) =>
      JsonTextBinding(repositoryId: repository, path: path);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('text-states-');
    store = JsonRepositoryStore(directory);
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
    SuperTextConfig config, {
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
                  child: SuperText(
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

  final field = find.byKey(const ValueKey('super-text-input-state'));
  String text(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.text;

  testWidgets(
    'JSON states change content binding and property bindings reactively',
    (tester) async {
      await mount(
        tester,
        SuperTextConfig(
          mode: SuperTextMode.input,
          binding: binding('a'),
          states: TextConfigStates(
            binding: binding('status'),
            named: {
              'second': SuperTextConfig(
                mode: SuperTextMode.input,
                binding: binding('b'),
                propertyBindings: {SuperTextProperty.fontSize: binding('size')},
              ),
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
        SuperTextConfig(
          mode: SuperTextMode.input,
          binding: binding('a'),
          states: TextConfigStates(
            hover: TextConfigOverride(
              config: SuperTextConfig(binding: binding('b')),
              properties: {TextStateProperty.binding},
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
        SuperTextConfig(
          mode: SuperTextMode.input,
          binding: binding('a'),
          states: TextConfigStates(
            hover: TextConfigOverride(
              config: const SuperTextConfig(fontSize: 24),
              properties: {TextStateProperty.fontSize},
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
}
