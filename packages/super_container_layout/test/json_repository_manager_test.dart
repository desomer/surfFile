import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/json.dart' as highlight;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/repositories/json_repository_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/components/internal_widget/code_editor.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_zoom.dart';
import 'package:super_container_layout/widgets/editing/overlay/style_edit_banner.dart';
import 'package:super_container_layout/widgets/editing/repositories/floating_repository_editor.dart';
import 'package:super_container_layout/widgets/editing/repositories/json_repository_manager.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';

class _DelayedRepositoryStore extends JsonRepositoryStore {
  _DelayedRepositoryStore(super.directory);

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> save(
    String name,
    String text, {
    required String expectedText,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.save(name, text, expectedText: expectedText);
  }
}

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('json-manager-test-');
    store = JsonRepositoryStore(directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  }

  Future<void> settle(WidgetTester tester) async {
    // File I/O runs outside the widget test's fake clock.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> editCode(WidgetTester tester, Finder field, String text) async {
    await tester.runAsync(() async {
      await tester.showKeyboard(field);
      final controller = tester.widget<EditableText>(field).controller;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.enterText(field, text);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await settle(tester);
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1100, 850),
    ValueNotifier<Appearance>? appearance,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    JsonRepositoryManager(store: store, appearance: appearance),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Open'));
    await settle(tester);
  }

  testWidgets('code editor replaces a formatted JSON document', (tester) async {
    var document = '{\n  "value": 1\n}\n';
    final error = ValueNotifier<String>('');
    addTearDown(error.dispose);
    final config = CodeEditorConfig(
      mode: highlight.json,
      getText: () => document,
      onChange: (String text, CodeEditorConfig _) => document = text,
      notifError: error,
      type: 'json',
      useLargeTextViewer: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodeEditor(config: config)),
      ),
    );
    await editCode(tester, find.byType(EditableText), '{"value":2}');
    expect(document, '{"value":2}');
  });

  testWidgets('create, edit, validate, save, rename and reopen a repository', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byKey(const ValueKey('repository-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('repository-name')),
      'Clients',
    );
    await tap(tester, find.text('Valider'));
    await settle(tester);
    final editor = find.byKey(const ValueKey('repository-json'));
    expect(editor, findsOneWidget);
    final id = await tester.runAsync(() => store.idOf('Clients'));
    final idLabel = find.byKey(const ValueKey('repository-id'));
    expect(tester.widget<SelectableText>(idLabel).data, 'ID technique : $id');
    expect(tester.widget<TextField>(editor).controller!.text, '{}\n');
    await tester.enterText(editor, '{invalid');
    await tap(tester, find.byKey(const ValueKey('repository-save')));
    await settle(tester);
    expect(find.byKey(const ValueKey('repository-error')), findsOneWidget);
    expect(await tester.runAsync(() => store.read('Clients')), '{}\n');
    await tester.enterText(editor, '{"items":[1,2]}');
    await tap(tester, find.text('Formater'));
    await tester.pump();
    expect(
      tester.widget<TextField>(editor).controller!.text,
      contains('\n  "items"'),
    );
    await tap(tester, find.byKey(const ValueKey('repository-save')));
    await settle(tester);
    expect(find.text('Repository enregistré.'), findsOneWidget);
    await tap(tester, find.text('Renommer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('repository-name')),
      'Contacts',
    );
    await tap(tester, find.text('Valider'));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('repository-entry-Contacts')),
      findsOneWidget,
    );
    expect(tester.widget<SelectableText>(idLabel).data, 'ID technique : $id');
    await tap(tester, find.text('Fermer'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Open'));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('repository-entry-Contacts')));
    await settle(tester);
    expect(
      tester.widget<TextField>(editor).controller!.text,
      contains('"items"'),
    );
    expect(tester.widget<SelectableText>(idLabel).data, 'ID technique : $id');
    expect(await tester.runAsync(() => store.idOf('Contacts')), id);
    expect(tester.takeException(), isNull);
  });

  for (final autoSave in [true, false]) {
    testWidgets('persistent repository editor saves and reloads ($autoSave)', (
      tester,
    ) async {
      const id = 'pan_model_repository';
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      );
      await tester.runAsync(
        () => store.registerPersistentRepository(
          RepositoryImpl(id: id, json: {'name': 'Initial'}),
          autoSave: autoSave,
        ),
      );
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('repository-entry-$id')));
      await settle(tester);

      final editor = find.byKey(const ValueKey('repository-json'));
      await tester.enterText(editor, '{"name":"Saved"}');
      await tap(tester, find.byKey(const ValueKey('repository-save')));
      await settle(tester);
      expect(jsonDecode(await tester.runAsync(file.readAsString) as String), {
        'name': 'Saved',
      });

      await tester.runAsync(() => file.writeAsString('{"name":"External"}'));
      await tester.enterText(editor, '{"name":"Local"}');
      await tap(tester, find.byKey(const ValueKey('repository-save')));
      await settle(tester);
      expect(find.textContaining('modifié sur le disque'), findsOneWidget);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        contains('Local'),
      );
      expect(jsonDecode(await tester.runAsync(file.readAsString) as String), {
        'name': 'External',
      });

      await tap(tester, find.text('Recharger'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Abandonner'));
      await settle(tester);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        contains('External'),
      );
      expect(
        jsonDecode(await tester.runAsync(() => store.read(id)) as String),
        {'name': 'External'},
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'unsaved edits require confirmation before switching or closing',
    (tester) async {
      await tester.runAsync(() async {
        await store.create('A');
        await store.create('B');
      });
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('repository-entry-A')));
      await settle(tester);
      final editor = find.byKey(const ValueKey('repository-json'));
      await tester.enterText(editor, '[42]');
      await tap(tester, find.byKey(const ValueKey('repository-entry-B')));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Conserver'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editor).controller!.text, '[42]');
      await tap(tester, find.text('Fermer'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonRepositoryManager), findsNothing);
      expect(await tester.runAsync(() => store.read('A')), '{}\n');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('file errors are visible and the editor fits a narrow window', (
    tester,
  ) async {
    await tester.runAsync(() => store.create('A'));
    await open(tester, size: const Size(480, 750));
    await tap(tester, find.byKey(const ValueKey('repository-entry-A')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('repository-json')),
      '[42]',
    );
    await tester.runAsync(
      () => File('${directory.path}\\A.json').writeAsString('[99]'),
    );
    await tap(tester, find.byKey(const ValueKey('repository-save')));
    await settle(tester);
    expect(find.textContaining('modifié sur le disque'), findsOneWidget);
    expect(await tester.runAsync(() => store.read('A')), '[99]');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'floating editor remains open and saves valid JSON while preserving invalid drafts',
    (tester) async {
      await tester.runAsync(() => store.create('Clients'));
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('repository-entry-Clients')));
      await settle(tester);
      await tap(tester, find.byKey(const ValueKey('repository-open-floating')));
      await settle(tester);

      final code = find.byKey(const ValueKey('floating-repository-code'));
      expect(code, findsOneWidget);
      expect(find.byType(CodeEditor), findsOneWidget);
      await tap(tester, find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonRepositoryManager), findsNothing);
      expect(code, findsOneWidget);

      final field = find.descendant(
        of: code,
        matching: find.byType(EditableText),
      );
      await editCode(tester, field, '{"nom":"Lyon"}');
      expect(
        jsonDecode(
          await tester.runAsync(() => store.read('Clients')) as String,
        ),
        {'nom': 'Lyon'},
      );

      await editCode(tester, field, '{"nom":');
      expect(
        find.byKey(const ValueKey('floating-repository-error')),
        findsOneWidget,
      );
      expect(
        jsonDecode(
          await tester.runAsync(() => store.read('Clients')) as String,
        ),
        {'nom': 'Lyon'},
      );
      await tap(
        tester,
        find.byKey(const ValueKey('floating-repository-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brouillon non appliqué'), findsOneWidget);
      await tap(tester, find.text('Conserver'));
      await tester.pumpAndSettle();
      await editCode(tester, field, '{"nom":"Paris"}');
      expect(
        jsonDecode(
          await tester.runAsync(() => store.read('Clients')) as String,
        ),
        {'nom': 'Paris'},
      );
      await tap(
        tester,
        find.byKey(const ValueKey('floating-repository-close')),
      );
      await tester.pumpAndSettle();
      expect(code, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('floating editor pauses on external file conflict', (
    tester,
  ) async {
    await tester.runAsync(() => store.create('Clients'));
    await open(tester);
    await tap(tester, find.byKey(const ValueKey('repository-entry-Clients')));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('repository-open-floating')));
    await settle(tester);
    await tap(tester, find.text('Fermer'));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => File('${directory.path}\\Clients.json').writeAsString('{"ext":1}'),
    );
    final code = find.byKey(const ValueKey('floating-repository-code'));
    final field = find.descendant(
      of: code,
      matching: find.byType(EditableText),
    );
    await editCode(tester, field, '{"local":2}');
    expect(find.textContaining('modifié sur le disque'), findsOneWidget);
    expect(await tester.runAsync(() => store.read('Clients')), '{"ext":1}');
    await editCode(tester, field, '{"local":3}');
    expect(await tester.runAsync(() => store.read('Clients')), '{"ext":1}');
    await tap(tester, find.byKey(const ValueKey('floating-repository-reload')));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Abandonner'));
    await settle(tester);
    expect(tester.widget<EditableText>(field).controller.text, '{"ext":1}');
    await tap(tester, find.byKey(const ValueKey('floating-repository-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final autoSave in [null, false, true]) {
    testWidgets('floating editor updates registered repository ($autoSave)', (
      tester,
    ) async {
      final persistent = autoSave != null;
      const id = 'app_repository';
      var callbacks = 0;
      final repository = RepositoryImpl(
        id: id,
        json: {'value': 1},
        onChanged: (_) => callbacks++,
      );
      await tester.runAsync(() async {
        if (persistent) {
          await store.registerPersistentRepository(
            repository,
            autoSave: autoSave,
          );
        } else {
          store.registerRepository(repository);
        }
      });
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('repository-entry-$id')));
      await settle(tester);
      await tap(tester, find.byKey(const ValueKey('repository-open-floating')));
      await settle(tester);
      await tap(tester, find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('aucune sauvegarde sur disque'),
        persistent ? findsNothing : findsOneWidget,
      );
      final field = find.descendant(
        of: find.byKey(const ValueKey('floating-repository-code')),
        matching: find.byType(EditableText),
      );
      if (persistent) {
        await editCode(tester, field, '[1, 2]');
        expect(find.textContaining('doit être un objet JSON'), findsOneWidget);
        expect(callbacks, 0);
      }
      await editCode(tester, field, '{"value":2}');
      expect(
        jsonDecode(await tester.runAsync(() => store.read(id)) as String),
        {'value': 2},
      );
      expect(callbacks, 1);
      final file = File('${directory.path}\\registered\\$id.json');
      if (persistent) {
        expect(jsonDecode(await tester.runAsync(file.readAsString) as String), {
          'value': 2,
        });
      } else {
        expect(await tester.runAsync(file.exists), isFalse);
      }
      await tap(
        tester,
        find.byKey(const ValueKey('floating-repository-close')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('floating editor follows store changes and protects a draft', (
    tester,
  ) async {
    await tester.runAsync(() => store.create('Clients'));
    await open(tester);
    await tap(tester, find.byKey(const ValueKey('repository-entry-Clients')));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('repository-open-floating')));
    await settle(tester);
    await tap(tester, find.text('Fermer'));
    await tester.pumpAndSettle();
    final code = find.byKey(const ValueKey('floating-repository-code'));
    final field = find.descendant(
      of: code,
      matching: find.byType(EditableText),
    );

    await tester.runAsync(() => store.rename('Clients', 'Contacts'));
    await settle(tester);
    expect(find.text('Repository : Contacts'), findsOneWidget);
    await tester.runAsync(
      () => store.save('Contacts', '{"external":1}', expectedText: '{}\n'),
    );
    await settle(tester);
    expect(
      tester.widget<EditableText>(field).controller.text,
      '{"external":1}',
    );

    await editCode(tester, field, '{"local":');
    await tester.runAsync(
      () => store.save(
        'Contacts',
        '{"external":2}',
        expectedText: '{"external":1}',
      ),
    );
    await settle(tester);
    expect(
      find.byKey(const ValueKey('floating-repository-reload')),
      findsOneWidget,
    );
    expect(tester.widget<EditableText>(field).controller.text, '{"local":');
    await tap(tester, find.byKey(const ValueKey('floating-repository-reload')));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Abandonner'));
    await settle(tester);
    expect(
      tester.widget<EditableText>(field).controller.text,
      '{"external":2}',
    );
    await tap(tester, find.byKey(const ValueKey('floating-repository-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('floating editor serializes writes and waits before closing', (
    tester,
  ) async {
    final delayed = _DelayedRepositoryStore(directory);
    store = delayed;
    await tester.runAsync(() => store.create('Clients'));
    await open(tester);
    await tap(tester, find.byKey(const ValueKey('repository-entry-Clients')));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('repository-open-floating')));
    await settle(tester);
    await tap(tester, find.text('Fermer'));
    await tester.pumpAndSettle();
    final code = find.byKey(const ValueKey('floating-repository-code'));
    final field = find.descendant(
      of: code,
      matching: find.byType(EditableText),
    );
    await editCode(tester, field, '{"value":1}');
    expect(delayed.started.isCompleted, isTrue);
    await editCode(tester, field, '{"value":2}');
    await tap(tester, find.byKey(const ValueKey('floating-repository-close')));
    expect(code, findsOneWidget);
    delayed.release.complete();
    await settle(tester);
    expect(await tester.runAsync(() => store.read('Clients')), '{"value":2}');
    expect(code, findsNothing);
  });

  testWidgets('floating editor keeps an owned directory store alive', (
    tester,
  ) async {
    final otherDirectory = Directory('${directory.path}\\alternate');
    final otherStore = JsonRepositoryStore(otherDirectory);
    await tester.runAsync(() => otherStore.create('Clients'));
    otherStore.dispose();
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('repository-directory')),
      otherDirectory.path,
    );
    await tap(tester, find.byTooltip('Charger le dossier'));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('repository-entry-Clients')));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('repository-open-floating')));
    await settle(tester);
    await tap(tester, find.text('Fermer'));
    await tester.pumpAndSettle();
    final code = find.byKey(const ValueKey('floating-repository-code'));
    final field = find.descendant(
      of: code,
      matching: find.byType(EditableText),
    );
    await editCode(tester, field, '{"value":2}');
    final file = File('${otherDirectory.path}\\Clients.json');
    expect(await tester.runAsync(file.readAsString), '{"value":2}');
    await tap(tester, find.byKey(const ValueKey('floating-repository-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating panels move, resize, coexist and remain non-modal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late String firstId;
    late String secondId;
    await tester.runAsync(() async {
      await store.create('First');
      await store.create('Second');
      firstId = await store.idOf('First');
      secondId = await store.idOf('Second');
    });
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => openFloatingRepositoryEditor(
                      context,
                      store: store,
                      repositoryId: firstId,
                      name: 'First',
                      text: '{}\n',
                    ),
                    child: const Text('First window'),
                  ),
                  TextButton(
                    onPressed: () => openFloatingRepositoryEditor(
                      context,
                      store: store,
                      repositoryId: secondId,
                      name: 'Second',
                      text: '{}\n',
                    ),
                    child: const Text('Second window'),
                  ),
                  TextButton(
                    onPressed: () => clicks++,
                    child: const Text('Outside'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('First window'));
    await tester.pumpAndSettle();
    final first = find.byKey(ValueKey('floating-repository-$firstId'));
    final title = find.descendant(
      of: first,
      matching: find.byKey(const ValueKey('floating-repository-title')),
    );
    final resize = find.descendant(
      of: first,
      matching: find.byKey(const ValueKey('floating-repository-resize')),
    );
    final before = tester.getRect(first);
    await tester.drag(title, const Offset(80, 60));
    await tester.pumpAndSettle();
    final moved = tester.getRect(first);
    expect(moved.left, greaterThan(before.left));
    expect(moved.top, greaterThan(before.top));
    await tester.drag(resize, const Offset(-100, -80));
    await tester.pumpAndSettle();
    expect(tester.getSize(first).width, lessThan(moved.width));
    expect(tester.getSize(first).height, lessThan(moved.height));
    await tester.tap(find.text('Second window'));
    await tester.pumpAndSettle();
    expect(find.byType(CodeEditor), findsNWidgets(2));
    await tester.tap(find.text('First window'));
    await tester.pumpAndSettle();
    expect(find.byType(CodeEditor), findsNWidgets(2));
    await tester.tap(find.text('Outside'));
    expect(clicks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delete checks that repository is not bound and asks confirmation',
    (tester) async {
      late String clientsId;
      await tester.runAsync(() async {
        await store.create('Clients');
        await store.create('Articles');
        clientsId = await store.idOf('Clients');
      });
      final appearance = ValueNotifier(
        Appearance().withValueComponent(
          'v1',
          SuperValueConfig(
            binding: JsonTextBinding(repositoryId: clientsId, path: 'nom'),
          ),
        ),
      );
      addTearDown(appearance.dispose);

      await open(tester, appearance: appearance);
      await tap(tester, find.byKey(const ValueKey('repository-entry-Clients')));
      await settle(tester);
      expect(find.byKey(const ValueKey('repository-json')), findsOneWidget);

      // Attempt deletion while bound in Appearance -> blocked with error
      await tap(tester, find.byKey(const ValueKey('repository-delete')));
      await settle(tester);
      expect(find.text('Supprimer le repository ?'), findsNothing);
      expect(find.byKey(const ValueKey('repository-error')), findsOneWidget);
      expect(find.textContaining('encore utilisé par un bind'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('repository-entry-Clients')),
        findsOneWidget,
      );

      // Remove binding -> confirmation dialog is shown
      appearance.value = Appearance();
      await tap(tester, find.byKey(const ValueKey('repository-delete')));
      await settle(tester);
      expect(find.text('Supprimer le repository ?'), findsOneWidget);
      await tap(tester, find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('repository-entry-Clients')),
        findsOneWidget,
      );

      // Confirm deletion
      await tap(tester, find.byKey(const ValueKey('repository-delete')));
      await settle(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('repository-confirm-delete')),
      );
      await settle(tester);

      expect(
        find.byKey(const ValueKey('repository-entry-Clients')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('repository-entry-Articles')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('repository-json')), findsNothing);
      expect(find.text('Repository supprimé.'), findsOneWidget);
      expect(await tester.runAsync(() => store.list()), ['Articles']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('repository dialog docks on the right and zooms out the screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editMode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    final navigatorKey = GlobalKey<NavigatorState>();
    final pageKey = GlobalKey();
    addTearDown(editMode.dispose);
    addTearDown(appearance.dispose);

    Rect screenRect(Finder finder) {
      final box = tester.renderObject<RenderBox>(finder);
      return MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
    }

    await tester.pumpWidget(
      JsonRepositoryScope(
        store: store,
        child: AppearanceScope(
          controller: appearance,
          child: StyleEditScope(
            controller: editMode,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              builder: (context, child) => Stack(
                children: [
                  child!,
                  Positioned.fill(
                    child: StyleEditBanner(navigatorKey: navigatorKey),
                  ),
                ],
              ),
              home: Scaffold(
                body: EditorZoom(
                  child: SizedBox.expand(
                    key: pageKey,
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    final pageFinder = find.byKey(pageKey);
    final before = screenRect(pageFinder);
    expect(before, const Rect.fromLTWH(0, 0, 1400, 900));
    final zoom = EditorZoomScope.controllerOf(pageKey.currentContext!)!;
    zoom.options.value = zoom.options.value.copyWith(
      skipLargeElementsOnDialog: false,
      minDialogScale: .3,
    );

    await tap(
      tester,
      find.byKey(const ValueKey('style-edit-banner-repository')),
    );
    await settle(tester);

    expect(find.byType(JsonRepositoryManager), findsOneWidget);
    final panel = find.byKey(const ValueKey('editor-dialog-panel'));
    expect(panel, findsOneWidget);
    final panelBounds = screenRect(panel);
    expect(panelBounds.right, 1400);
    expect(panelBounds.width, closeTo(770, .01));

    final zoomedOut = screenRect(pageFinder);
    expect(zoomedOut.width, lessThan(before.width));
    expect(zoomedOut.overlaps(panelBounds), isFalse);
    expect(zoomedOut.center.dx, closeTo((1400 - panelBounds.width) / 2, .01));

    await tap(tester, find.text('Fermer'));
    await settle(tester);

    expect(find.byType(JsonRepositoryManager), findsNothing);
    expect(screenRect(pageFinder), before);
    expect(tester.takeException(), isNull);
  });
}
