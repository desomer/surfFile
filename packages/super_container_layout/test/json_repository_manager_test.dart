import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/repositories/json_repository_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_zoom.dart';
import 'package:super_container_layout/widgets/editing/overlay/style_edit_banner.dart';
import 'package:super_container_layout/widgets/editing/repositories/json_repository_manager.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';

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

  testWidgets(
    'repository dialog docks on the right and zooms out the screen',
    (tester) async {
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

      await tap(tester, find.byKey(const ValueKey('style-edit-banner-repository')));
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
    },
  );
}
