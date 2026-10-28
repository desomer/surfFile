import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];
  const hostKey = ValueKey('extract-host');

  String? clipboardText;

  setUp(() {
    clipboardText = null;
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            clipboardText = args['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'extracts SuperValue names and current runtime values to JSON from 3-dot context menu and saves repository',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('super_value_extract_test_'),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });
      final repoStore = JsonRepositoryStore(tempDir);
      addTearDown(repoStore.dispose);

      final registry = Registry()..bootstrap();
      const initialLayout = SuperLayoutConfig(
        north: true,
        south: false,
        west: false,
        east: false,
        placements: {
          SuperLayoutZone.center: ['v_renamed', 'v_labeled', 'v_id', 'v_dup'],
        },
        slotTypes: {
          'v_renamed': 'factory:Value',
          'v_labeled': 'factory:Value',
          'v_id': 'factory:Value',
          'v_dup': 'factory:Value',
        },
        // Only v_renamed has a customized slot label; others use default 'Value'.
        slotLabels: {'v_renamed': 'NomClient'},
      );
      final layoutController = registry.layoutController(
        'root',
        fallback: initialLayout,
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => JsonRepositoryScope(
              store: repoStore,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    key: hostKey,
                    width: 800,
                    height: 600,
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: layoutController,
                      builder: (_, config, _) => SuperLayout(
                        label: 'Formulaire',
                        config: config,
                        onChanged: (value) => layoutController.value = value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(hostKey));
      final appearance = AppearanceScope.controllerOf(context)!;
      appearance.value = appearance.value.copyWith(
        layouts: {'root': initialLayout},
        components: const {
          'v_renamed': SuperValueConfig(
            mode: SuperValueMode.input,
            initialText: 'Alice',
            label: 'IgnoredBecauseRenamed',
          ),
          'v_labeled': SuperValueConfig(
            kind: SuperValueKind.checkbox,
            mode: SuperValueMode.input,
            initialBool: true,
            label: 'Actif',
          ),
          'v_id': SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: '42',
          ),
          'v_dup': SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Bob',
            label: 'NomClient',
          ),
        },
      );
      await tester.pumpAndSettle();

      // Update runtime input of v_renamed before entering edit mode.
      await tester.enterText(
        find.byKey(const ValueKey('super-value-input-v_renamed')),
        'Alice Martin',
      );
      await tester.pumpAndSettle();

      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      // Empty North zone has no SuperValue and no wrap actions (only AI edit).
      await tester.tapAt(
        tester.getTopLeft(find.byKey(hostKey)) + const Offset(100, 15),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-more-Nord')));
      await tester.pumpAndSettle();
      expect(find.text('Extraire en JSON…'), findsNothing);
      expect(find.text('Modifier avec l’IA…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('style-menu-more-Nord')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byKey(hostKey))).pop();
      await tester.pumpAndSettle();

      // Right-click on the first SuperValue to open the context menu.
      await tester.tap(
        find.byKey(const ValueKey('super-value-field-v_renamed')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Both the SuperValue row ('NomClient') and the parent zone ('Centre') and layout ('Formulaire')
      // expose the 3-dot button. Open the zone's 3-dot menu to extract all SuperValues in 'Centre'.
      expect(
        find.byKey(const ValueKey('style-menu-more-NomClient')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-menu-more-Centre')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-menu-more-Formulaire')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('style-menu-more-Centre')));
      await tester.pumpAndSettle();

      expect(find.text('Extraire en JSON…'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('style-menu-extract-super-values-Centre')),
      );
      await tester.pumpAndSettle();

      // Verify the dialog opens with the expected JSON.
      expect(
        find.byKey(const ValueKey('super-value-extract-dialog')),
        findsOneWidget,
      );
      final jsonField = tester.widget<TextField>(
        find.byKey(const ValueKey('super-value-extract-json')),
      );
      final decoded =
          jsonDecode(jsonField.controller!.text) as Map<String, Object?>;
      expect(decoded, {
        'NomClient': 'Alice Martin',
        'Actif': true,
        'v_id': '42',
        'NomClient_2': 'Bob',
      });

      // Test copying to clipboard.
      await tester.tap(find.byKey(const ValueKey('super-value-extract-copy')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-value-extract-status')),
        findsOneWidget,
      );
      expect(jsonDecode(clipboardText!), decoded);

      // Test creating a repository from the extracted JSON.
      await tester.enterText(
        find.byKey(const ValueKey('super-value-extract-repo-name')),
        'clients_export',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('super-value-extract-create-repo')),
        );
        await tester.pump();
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
                  .text(
                    'Repository « clients_export » enregistré et liaisons appliquées.',
                  )
                  .evaluate()
                  .isNotEmpty ||
              find
                  .byKey(const ValueKey('super-value-extract-error'))
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();

      final list = await tester.runAsync(() => repoStore.list());
      expect(list, contains('clients_export'));
      final rawSaved = await tester.runAsync(
        () => repoStore.read('clients_export'),
      );
      final savedRepoJson = jsonDecode(rawSaved!) as Map<String, Object?>;
      expect(savedRepoJson, decoded);

      await tester.tap(find.byKey(const ValueKey('super-value-extract-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-value-extract-dialog')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'extracting from a single SuperValue 3-dot menu extracts only that SuperValue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final registry = Registry()..bootstrap();
      const initialLayout = SuperLayoutConfig(
        north: false,
        south: false,
        west: false,
        east: false,
        placements: {
          SuperLayoutZone.center: ['first', 'second'],
        },
        slotTypes: {'first': 'factory:Value', 'second': 'factory:Value'},
        slotLabels: {'first': 'Email', 'second': 'Ville'},
      );
      final layoutController = registry.layoutController(
        'root',
        fallback: initialLayout,
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: SizedBox(
                  key: hostKey,
                  width: 800,
                  height: 600,
                  child: ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: layoutController,
                    builder: (_, config, _) => SuperLayout(
                      label: 'Root',
                      config: config,
                      onChanged: (value) => layoutController.value = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(hostKey));
      final appearance = AppearanceScope.controllerOf(context)!;
      appearance.value = appearance.value.copyWith(
        layouts: {'root': initialLayout},
        components: const {
          'first': SuperValueConfig(initialText: 'contact@example.com'),
          'second': SuperValueConfig(initialText: 'Paris'),
        },
      );
      await tester.pumpAndSettle();
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('contact@example.com'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('style-menu-more-Email')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('style-menu-extract-super-values-Email')),
      );
      await tester.pumpAndSettle();

      final jsonField = tester.widget<TextField>(
        find.byKey(const ValueKey('super-value-extract-json')),
      );
      final decoded =
          jsonDecode(jsonField.controller!.text) as Map<String, Object?>;
      expect(decoded, {'Email': 'contact@example.com'});
      await tester.tap(find.byKey(const ValueKey('super-value-extract-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'proposes existing properties for SuperValue and SuperAction and automatically binds them after validation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir =
          (await tester.runAsync(
            () => Directory.systemTemp.createTemp(
              'super_action_value_extract_test_',
            ),
          ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });
      final repoStore = JsonRepositoryStore(tempDir);
      addTearDown(repoStore.dispose);

      final registry = Registry()..bootstrap();
      const initialLayout = SuperLayoutConfig(
        north: false,
        south: false,
        west: false,
        east: false,
        placements: {
          SuperLayoutZone.center: ['val_user', 'act_submit'],
        },
        slotTypes: {'val_user': 'factory:Value', 'act_submit': 'factory:Action'},
        slotLabels: {'val_user': 'Utilisateur', 'act_submit': 'BoutonValider'},
      );
      final layoutController = registry.layoutController(
        'root',
        fallback: initialLayout,
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => JsonRepositoryScope(
              store: repoStore,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    key: hostKey,
                    width: 800,
                    height: 600,
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: layoutController,
                      builder: (_, config, _) => SuperLayout(
                        label: 'Formulaire',
                        config: config,
                        onChanged: (value) => layoutController.value = value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(hostKey));
      final appearance = AppearanceScope.controllerOf(context)!;
      appearance.value = appearance.value.copyWith(
        layouts: {'root': initialLayout},
        components: const {
          'val_user': SuperValueConfig(
            mode: SuperValueMode.input,
            initialText: 'Jean Dupont',
            label: 'Nom complet',
            // placeholder is empty -> should not be offered
          ),
          'act_submit': SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Enregistrer',
            tooltip: 'Valider le formulaire',
            icon: 'check',
          ),
        },
      );
      await tester.pumpAndSettle();

      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();

      // Right-click on the SuperAction and open the Centre zone's 3-dot menu.
      await tester.tap(
        find.text('Enregistrer'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Both the SuperAction row ('BoutonValider') and the zone ('Centre') have the 3-dot menu.
      expect(
        find.byKey(const ValueKey('style-menu-more-BoutonValider')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('style-menu-more-Centre')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-extract-super-values-Centre')),
      );
      await tester.pumpAndSettle();

      // Verify only existing properties are proposed as FilterChips.
      expect(
        find.byKey(const ValueKey('super-value-extract-prop-val_user-value')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-value-extract-prop-val_user-label')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('super-value-extract-prop-val_user-placeholder'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('super-value-extract-prop-act_submit-label')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('super-value-extract-prop-act_submit-tooltip'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-value-extract-prop-act_submit-icon')),
        findsOneWidget,
      );

      // By default, 'value' on SuperValue and 'label' on SuperAction are selected (flat JSON).
      final jsonField = tester.widget<TextField>(
        find.byKey(const ValueKey('super-value-extract-json')),
      );
      expect(jsonDecode(jsonField.controller!.text), {
        'Utilisateur': 'Jean Dupont',
        'BoutonValider': 'Enregistrer',
      });

      // Also select 'label' on val_user and 'tooltip' on act_submit.
      await tester.tap(
        find.byKey(const ValueKey('super-value-extract-prop-val_user-label')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('super-value-extract-prop-act_submit-tooltip'),
        ),
      );
      await tester.pumpAndSettle();

      // Now both components have 2 selected properties -> nested JSON object per component.
      expect(jsonDecode(jsonField.controller!.text), {
        'Utilisateur': {'value': 'Jean Dupont', 'label': 'Nom complet'},
        'BoutonValider': {
          'label': 'Enregistrer',
          'tooltip': 'Valider le formulaire',
        },
      });

      // Validate and automatically bind to repository 'ui_texts'.
      await tester.enterText(
        find.byKey(const ValueKey('super-value-extract-repo-name')),
        'ui_texts',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('super-value-extract-create-repo')),
        );
        await tester.pump();
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
                  .byKey(const ValueKey('super-value-extract-status'))
                  .evaluate()
                  .isNotEmpty ||
              find
                  .byKey(const ValueKey('super-value-extract-error'))
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();

      final repoId = (await tester.runAsync(
        () => repoStore.idOf('ui_texts'),
      ))!;

      // Verify automatic bindings were applied to both SuperValueConfig and SuperActionConfig!
      final updatedValueConfig = appearance.value.valueComponent('val_user');
      expect(
        updatedValueConfig.binding,
        JsonTextBinding(repositoryId: repoId, path: 'Utilisateur.value'),
      );
      expect(updatedValueConfig.propertyBindings[SuperValueProperty.label],
          JsonTextBinding(repositoryId: repoId, path: 'Utilisateur.label'));

      final updatedActionConfig = appearance.value.actionComponent('act_submit');
      expect(updatedActionConfig.propertyBindings[SuperActionProperty.label],
          JsonTextBinding(repositoryId: repoId, path: 'BoutonValider.label'));
      expect(updatedActionConfig.propertyBindings[SuperActionProperty.tooltip],
          JsonTextBinding(repositoryId: repoId, path: 'BoutonValider.tooltip'));

      await tester.tap(find.byKey(const ValueKey('super-value-extract-close')));
      await tester.pumpAndSettle();

      // Undo reverts both bindings in a single history transaction.
      expect(history.canUndo, isTrue);
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value.valueComponent('val_user').binding, isNull);
      expect(
        appearance.value.valueComponent('val_user').propertyBindings,
        isEmpty,
      );
      expect(
        appearance.value.actionComponent('act_submit').propertyBindings,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Card with an image exposes Extraire en JSON… and automatically binds propertyBindings.imageUrl',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('surface_extract_test_'),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });
      final repoStore = JsonRepositoryStore(tempDir);
      addTearDown(repoStore.dispose);

      final registry = Registry()..bootstrap();
      const initialLayout = SuperLayoutConfig(
        north: false,
        south: false,
        west: false,
        east: false,
        placements: {
          SuperLayoutZone.center: ['card_avatar'],
        },
        slotTypes: {'card_avatar': 'factory:Card'},
        slotLabels: {'card_avatar': 'AvatarClient'},
      );
      final layoutController = registry.layoutController(
        'root',
        fallback: initialLayout,
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => JsonRepositoryScope(
              store: repoStore,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    key: hostKey,
                    width: 800,
                    height: 600,
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: layoutController,
                      builder: (_, config, _) => SuperLayout(
                        label: 'Fiche',
                        config: config,
                        onChanged: (value) => layoutController.value = value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(hostKey));
      final appearance = AppearanceScope.controllerOf(context)!;
      appearance.value = appearance.value.copyWith(
        layouts: {'root': initialLayout},
        styles: const {
          'card_avatar': ContainerStyle(
            fill: ContainerFill(imageUrl: 'https://example.com/avatar.png'),
          ),
        },
      );
      await tester.pumpAndSettle();

      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();

      // Right-click on the Card and open its 3-dot menu ('AvatarClient').
      await tester.tapAt(
        tester.getCenter(find.byKey(hostKey)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final cardMore = find.byKey(const ValueKey('style-menu-more-AvatarClient'));
      expect(cardMore, findsOneWidget);
      await tester.tap(cardMore);
      await tester.pumpAndSettle();

      expect(find.text('Extraire en JSON…'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-extract-super-values-AvatarClient'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('super-value-extract-prop-card_avatar-imageUrl'),
        ),
        findsOneWidget,
      );
      final jsonField = tester.widget<TextField>(
        find.byKey(const ValueKey('super-value-extract-json')),
      );
      expect(jsonDecode(jsonField.controller!.text), {
        'AvatarClient': 'https://example.com/avatar.png',
      });

      await tester.enterText(
        find.byKey(const ValueKey('super-value-extract-repo-name')),
        'avatars',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('super-value-extract-create-repo')),
        );
        await tester.pump();
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
                  .byKey(const ValueKey('super-value-extract-status'))
                  .evaluate()
                  .isNotEmpty ||
              find
                  .byKey(const ValueKey('super-value-extract-error'))
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();

      final repoId = (await tester.runAsync(
        () => repoStore.idOf('avatars'),
      ))!;
      final updatedStyle = appearance.value.style('card_avatar');
      expect(
        updatedStyle.propertyBindings[ContainerStyleProperty.imageUrl],
        JsonTextBinding(repositoryId: repoId, path: 'AvatarClient'),
      );

      await tester.tap(find.byKey(const ValueKey('super-value-extract-close')));
      await tester.pumpAndSettle();

      expect(history.canUndo, isTrue);
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value.style('card_avatar').propertyBindings, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
