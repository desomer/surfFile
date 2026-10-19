import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = '0123456789abcdef0123456789abcdef';

  test(
    'binding configuration is strict, immutable and backwards compatible',
    () {
      const binding = JsonTextBinding(
        repositoryId: id,
        path: 'clients[0].name',
      );
      const config = SuperTextConfig(binding: binding);
      final restored = SuperTextConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())),
      );
      expect(restored, config);
      expect(restored.hashCode, config.hashCode);
      expect(restored.copyWith(clearBinding: true).binding, isNull);
      expect(SuperTextConfig.fromJson(<String, dynamic>{}).binding, isNull);
      for (final json in [
        {'repositoryId': id, 'path': 'client..name'},
        {'repositoryId': 'invalid', 'path': 'name'},
        {'repositoryId': id, 'path': 'name', 'extra': true},
      ]) {
        expect(() => JsonTextBinding.fromJson(json), throwsFormatException);
      }
    },
  );

  test('path reads and creates objects without changing the original tree', () {
    final root = <String, dynamic>{'untouched': 42};
    final path = JsonAttributePath('client.address.name');
    expect(path.read(root), isNull);
    final updated = path.write(root, 'Alice', null);
    expect(path.read(updated), 'Alice');
    expect(updated, {
      'untouched': 42,
      'client': {
        'address': {'name': 'Alice'},
      },
    });
    expect(root, {'untouched': 42});
    expect(
      JsonAttributePath('[0].name').read([
        {'name': 'Root array'},
      ]),
      'Root array',
    );
  });

  test('paths and array indices are strictly validated', () {
    for (final path in [
      '',
      '.',
      '.name',
      'a..b',
      'a.',
      'a[',
      'a[-1]',
      'a[1.2]',
      'a[]',
      'a[0]b',
      'a.[0]',
      'a b',
      'a[99999999999999999999999999]',
    ]) {
      expect(
        () => JsonAttributePath(path),
        throwsFormatException,
        reason: path,
      );
    }
    final path = JsonAttributePath('clients[0].name');
    final root = {
      'clients': <Object?>[null],
    };
    expect(path.read(root), isNull);
    expect(path.read(path.write(root, 'A', null)), 'A');
    for (final invalid in [
      <String, dynamic>{},
      {'clients': []},
      {'clients': 'scalar'},
      {
        'clients': [42],
      },
    ]) {
      expect(() => path.read(invalid), throwsFormatException);
      expect(() => path.write(invalid, 'A', null), throwsFormatException);
    }
    expect(
      () => JsonAttributePath('a.b').read({'a': true}),
      throwsFormatException,
    );
    expect(() => JsonAttributePath('a').read({'a': {}}), throwsFormatException);
  });

  test(
    'scalar writes preserve types and reject invalid input without mutation',
    () {
      final root = <String, dynamic>{
        'number': 12,
        'flag': true,
        'text': 'false',
      };
      expect(JsonAttributePath('number').write(root, '13.5', 12), {
        'number': 13.5,
        'flag': true,
        'text': 'false',
      });
      expect(JsonAttributePath('flag').write(root, 'false', true), {
        'number': 12,
        'flag': false,
        'text': 'false',
      });
      expect(JsonAttributePath('text').write(root, '42', 'false'), {
        'number': 12,
        'flag': true,
        'text': '42',
      });
      for (final value in ['-', 'NaN', '"42"', 'true', '[]', 'null']) {
        expect(
          () => JsonAttributePath('number').write(root, value, 12),
          throwsFormatException,
        );
      }
      for (final value in ['False', '1', '"true"', 'null']) {
        expect(
          () => JsonAttributePath('flag').write(root, value, true),
          throwsFormatException,
        );
      }
      expect(root['number'], 12);
      expect(root['flag'], true);
    },
  );

  group('repository session', () {
    late Directory directory;
    late JsonRepositoryStore store;
    late JsonTextBinding binding;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('text-binding-test-');
      store = JsonRepositoryStore(directory);
      await store.create('People');
      binding = JsonTextBinding(
        repositoryId: await store.idOf('People'),
        path: 'client.name',
      );
    });
    tearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    test(
      'ID resolution survives rename and writes only the target attribute',
      () async {
        await store.rename('People', 'Clients');
        await store.writeAttribute(binding, 'Alice', expectedValue: null);
        final json =
            jsonDecode(await store.read('Clients')) as Map<String, dynamic>;
        json['other'] = 42;
        await store.save(
          'Clients',
          jsonEncode(json),
          expectedText: await store.read('Clients'),
        );
        await store.writeAttribute(binding, 'Bob', expectedValue: 'Alice');
        expect(jsonDecode(await store.read('Clients')), {
          'client': {'name': 'Bob'},
          'other': 42,
        });
        expect((await store.readAttribute(binding)).text, 'Bob');
        final restored = JsonRepositoryStore(directory);
        expect((await restored.readAttribute(binding)).text, 'Bob');
        restored.dispose();
      },
    );

    test(
      'serial writes preserve distinct attributes and detect target conflicts',
      () async {
        final other = JsonTextBinding(
          repositoryId: binding.repositoryId,
          path: 'other',
        );
        await Future.wait([
          store.writeAttribute(binding, 'Alice', expectedValue: null),
          store.writeAttribute(other, '42', expectedValue: null),
        ]);
        await expectLater(
          store.writeAttribute(binding, 'Bob', expectedValue: null),
          throwsFormatException,
        );
        expect((await store.readAttribute(binding)).text, 'Alice');
        expect((await store.readAttribute(other)).text, '42');
      },
    );

    test('missing and duplicate IDs are explicit errors', () async {
      await expectLater(
        store.readAttribute(
          const JsonTextBinding(repositoryId: id, path: 'name'),
        ),
        throwsFormatException,
      );
      await store.create('Copy');
      await File('${directory.path}\\Copy.json.id')
          .writeAsString(binding.repositoryId!);
      await expectLater(store.catalog(), throwsFormatException);
      await expectLater(store.readAttribute(binding), throwsFormatException);
    });

    test('invalid document errors never expose repository content', () async {
      await File('${directory.path}\\People.json')
          .writeAsString('{"secret":"hidden"');
      try {
        await store.readAttribute(binding);
        fail('Expected invalid JSON error');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('hidden')));
        expect(error.source, isNull);
      }
    });

    test(
      'two controllers synchronize and selection-only edits never write',
      () async {
        final first = TextEditingController();
        final second = TextEditingController();
        final a = JsonTextControllerBinding(
          store: store,
          binding: binding,
          controller: first,
        );
        final b = JsonTextControllerBinding(
          store: store,
          binding: binding,
          controller: second,
        );
        await Future.wait([a.reload(), b.reload()]);
        first.text = 'Alice';
        await a.flush();
        await b.reload();
        expect(second.text, 'Alice');
        var writes = 0;
        store.addListener(() => writes++);
        first.selection = const TextSelection.collapsed(offset: 2);
        await a.flush();
        expect(writes, 0);
        expect(first.selection.baseOffset, 2);
        a.dispose();
        b.dispose();
        first.dispose();
        second.dispose();
      },
    );

    test(
      'dirty controllers retain drafts and surface conflicts with recovery',
      () async {
        await store.writeAttribute(binding, 'Alice', expectedValue: null);
        final controller = TextEditingController();
        final runtime = JsonTextControllerBinding(
          store: store,
          binding: binding,
          controller: controller,
        );
        await runtime.reload();
        controller.text = 'Draft';
        await store.writeAttribute(binding, 'Remote', expectedValue: 'Alice');
        await runtime.reload();
        expect(controller.text, 'Draft');
        expect(runtime.error, isNotNull);
        await runtime.flush();
        expect((await store.readAttribute(binding)).text, 'Remote');
        await runtime.discardAndReload();
        expect(controller.text, 'Remote');
        expect(runtime.error, isNull);
        runtime.dispose();
        controller.dispose();
      },
    );

    test('dispose flushes the final edit to its captured target', () async {
      final controller = TextEditingController();
      final runtime = JsonTextControllerBinding(
        store: store,
        binding: binding,
        controller: controller,
      );
      await runtime.reload();
      controller.text = 'Final';
      runtime.dispose();
      controller.dispose();
      await store.catalog();
      // flush enqueues its write on the next microtask.
      await Future<void>.delayed(Duration.zero);
      expect((await store.readAttribute(binding)).text, 'Final');
    });

    test('IME composition saves only when committed', () async {
      final controller = TextEditingController();
      final runtime = JsonTextControllerBinding(
        store: store,
        binding: binding,
        controller: controller,
      );
      await runtime.reload();
      controller.value = const TextEditingValue(
        text: 'Alice',
        composing: TextRange(start: 0, end: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect((await store.readAttribute(binding)).value, isNull);
      controller.value = controller.value.copyWith(composing: TextRange.empty);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect((await store.readAttribute(binding)).text, 'Alice');
      runtime.dispose();
      controller.dispose();
    });

    test(
      'reverting text while a write is queued still persists the last edit',
      () async {
        await store.writeAttribute(binding, 'Original', expectedValue: null);
        final controller = TextEditingController();
        final runtime = JsonTextControllerBinding(
          store: store,
          binding: binding,
          controller: controller,
        );
        await runtime.reload();
        controller.text = 'Intermediate';
        final first = runtime.flush();
        controller.text = 'Original';
        final last = runtime.flush();
        await Future.wait([first, last]);
        expect((await store.readAttribute(binding)).text, 'Original');
        expect(runtime.dirty, isFalse);
        runtime.dispose();
        controller.dispose();
      },
    );
  });
}
