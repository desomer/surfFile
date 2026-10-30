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
      expect(find.text('Extraire & lier en JSON…'), findsNothing);
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

      expect(find.text('Extraire & lier en JSON…'), findsOneWidget);
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

      final tempDir = (await tester.runAsync(
        () =>
            Directory.systemTemp.createTemp('super_action_value_extract_test_'),
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
        slotTypes: {
          'val_user': 'factory:Value',
          'act_submit': 'factory:Action',
        },
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

      final repoId = (await tester.runAsync(() => repoStore.idOf('ui_texts')))!;

      // Verify automatic bindings were applied to both SuperValueConfig and SuperActionConfig!
      final updatedValueConfig = appearance.value.valueComponent('val_user');
      expect(
        updatedValueConfig.binding,
        JsonTextBinding(repositoryId: repoId, path: 'Utilisateur.value'),
      );
      expect(
        updatedValueConfig.propertyBindings[SuperValueProperty.label],
        JsonTextBinding(repositoryId: repoId, path: 'Utilisateur.label'),
      );

      final updatedActionConfig = appearance.value.actionComponent(
        'act_submit',
      );
      expect(
        updatedActionConfig.propertyBindings[SuperActionProperty.label],
        JsonTextBinding(repositoryId: repoId, path: 'BoutonValider.label'),
      );
      expect(
        updatedActionConfig.propertyBindings[SuperActionProperty.tooltip],
        JsonTextBinding(repositoryId: repoId, path: 'BoutonValider.tooltip'),
      );

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

      final cardMore = find.byKey(
        const ValueKey('style-menu-more-AvatarClient'),
      );
      expect(cardMore, findsOneWidget);
      await tester.tap(cardMore);
      await tester.pumpAndSettle();

      expect(find.text('Extraire & lier en JSON…'), findsOneWidget);
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

      final repoId = (await tester.runAsync(() => repoStore.idOf('avatars')))!;
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

  testWidgets(
    'detects recurring Card blocks, builds JSON array with divergent properties, replaces duplicates with SuperListView, and supports Undo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('recurring_listview_extract_'),
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
      const rootLayout = SuperLayoutConfig(
        north: false,
        south: false,
        west: false,
        east: false,
        placements: {
          SuperLayoutZone.center: ['header_val', 'card_1', 'card_2', 'card_3'],
        },
        slotTypes: {
          'header_val': 'factory:Value',
          'card_1': 'registry:Card',
          'card_2': 'registry:Card',
          'card_3': 'registry:Card',
        },
        slotLabels: {
          'header_val': 'TitreCatalogue',
          'card_1': 'Produit 1',
          'card_2': 'Produit 2',
          'card_3': 'Produit 3',
        },
      );

      const layout1 = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['nom_1', 'prix_1', 'btn_1'],
        },
        slotTypes: {
          'nom_1': 'factory:Value',
          'prix_1': 'factory:Value',
          'btn_1': 'factory:Action',
        },
        slotLabels: {'nom_1': 'Nom', 'prix_1': 'Prix', 'btn_1': 'Action'},
      );
      const layout2 = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['nom_2', 'prix_2', 'btn_2'],
        },
        slotTypes: {
          'nom_2': 'factory:Value',
          'prix_2': 'factory:Value',
          'btn_2': 'factory:Action',
        },
        slotLabels: {'nom_2': 'Nom', 'prix_2': 'Prix', 'btn_2': 'Action'},
      );
      const layout3 = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['nom_3', 'prix_3', 'btn_3'],
        },
        slotTypes: {
          'nom_3': 'factory:Value',
          'prix_3': 'factory:Value',
          'btn_3': 'factory:Action',
        },
        slotLabels: {'nom_3': 'Nom', 'prix_3': 'Prix', 'btn_3': 'Action'},
      );

      final rootController = registry.layoutController(
        'root',
        fallback: rootLayout,
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
                    width: 900,
                    height: 700,
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: rootController,
                      builder: (_, config, _) => SuperLayout(
                        id: 'root',
                        label: 'Catalogue',
                        config: config,
                        onChanged: (value) => rootController.value = value,
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
        layouts: {
          'root': rootLayout,
          'l_1': layout1,
          'l_2': layout2,
          'l_3': layout3,
        },
        components: {
          'card_1': NativeComponentConfig(
            placements: {
              'child': ['l_1'],
            },
            slotTypes: {'l_1': 'registry:Layout'},
          ),
          'card_2': NativeComponentConfig(
            placements: {
              'child': ['l_2'],
            },
            slotTypes: {'l_2': 'registry:Layout'},
          ),
          'card_3': NativeComponentConfig(
            placements: {
              'child': ['l_3'],
            },
            slotTypes: {'l_3': 'registry:Layout'},
          ),
          'header_val': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Nos Offres',
          ),
          'nom_1': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Clavier',
          ),
          'prix_1': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: '49 €',
          ),
          'btn_1': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Acheter',
            icon: 'add',
          ),
          'nom_2': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Souris',
          ),
          'prix_2': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: '29 €',
          ),
          'btn_2': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Acheter',
            icon: 'check', // Divergent icon across occurrences!
          ),
          'nom_3': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Écran',
          ),
          'prix_3': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: '199 €',
          ),
          'btn_3': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Commander',
            icon: 'star',
          ),
        },
      );
      await tester.pumpAndSettle();

      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();

      // Right-click on the header value and open the Centre zone's 3-dot menu.
      await tester.tap(find.text('Nos Offres'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('style-menu-more-Centre')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-extract-super-values-Centre')),
      );
      await tester.pumpAndSettle();

      // Verify the recurring group 'Produit' (3 occurrences) is detected!
      expect(
        find.byKey(
          const ValueKey('super-value-extract-group-root_center_card_1'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('3 × Produit 1'), findsOneWidget);

      // Verify the extracted JSON has 'TitreCatalogue' at root and 'Produit' as an array of 3 objects,
      // with 'icon' auto-selected on Action because it varies across the 3 cards ('add', 'check', 'star').
      final jsonField = tester.widget<TextField>(
        find.byKey(const ValueKey('super-value-extract-json')),
      );
      final decoded =
          jsonDecode(jsonField.controller!.text) as Map<String, Object?>;
      expect(decoded, {
        'TitreCatalogue': 'Nos Offres',
        'Produit': [
          {
            'Nom': 'Clavier',
            'Prix': '49 €',
            'Action': {'label': 'Acheter', 'icon': 'add'},
          },
          {
            'Nom': 'Souris',
            'Prix': '29 €',
            'Action': {'label': 'Acheter', 'icon': 'check'},
          },
          {
            'Nom': 'Écran',
            'Prix': '199 €',
            'Action': {'label': 'Commander', 'icon': 'star'},
          },
        ],
      });

      // Open similarity settings panel and verify controls are present.
      await tester.tap(
        find.byKey(
          const ValueKey('super-value-extract-recurrence-settings-toggle'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-value-extract-recurrence-panel')),
        findsOneWidget,
      );

      // Validate and automatically bind + replace with SuperListView!
      await tester.enterText(
        find.byKey(const ValueKey('super-value-extract-repo-name')),
        'catalogue_produits',
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

      expect(find.textContaining('1 ListView créée'), findsOneWidget);

      final repoId = (await tester.runAsync(
        () => repoStore.idOf('catalogue_produits'),
      ))!;

      // Verify root layout now has only 2 slots in center: 'header_val' and the new ListView!
      final updatedRoot = appearance.value.layout('root');
      final centerSlots = updatedRoot.placementsOf(SuperLayoutZone.center);
      expect(centerSlots.length, 2);
      expect(centerSlots.first, 'header_val');
      final listId = centerSlots[1];
      expect(updatedRoot.slotTypeOf(listId), 'registry:ListView');
      expect(updatedRoot.slotLabels[listId], 'Produit');

      // Verify the SuperListViewConfig is bound to 'Produit' on the created repository
      // and its template contains 'card_1'.
      final listConfig = appearance.value.listComponent(listId);
      expect(
        listConfig.binding,
        JsonTextBinding(repositoryId: repoId, path: 'Produit'),
      );
      expect(listConfig.template.placementsOf(SuperLayoutZone.center), [
        'card_1',
      ]);

      // Verify the template card's components ('nom_1', 'prix_1', 'btn_1') are bound with '[?]'
      // and inherited repository (repositoryId: null).
      expect(
        appearance.value.valueComponent('nom_1').binding,
        const JsonTextBinding(path: 'Produit[?].Nom'),
      );
      expect(
        appearance.value.valueComponent('prix_1').binding,
        const JsonTextBinding(path: 'Produit[?].Prix'),
      );
      expect(
        appearance.value
            .actionComponent('btn_1')
            .propertyBindings[SuperActionProperty.label],
        const JsonTextBinding(path: 'Produit[?].Action.label'),
      );
      expect(
        appearance.value
            .actionComponent('btn_1')
            .propertyBindings[SuperActionProperty.icon],
        const JsonTextBinding(path: 'Produit[?].Action.icon'),
      );

      // Verify duplicate cards ('card_2', 'card_3') and their children ('nom_2', 'nom_3') were purged!
      expect(appearance.value.components.containsKey('card_2'), isFalse);
      expect(appearance.value.components.containsKey('card_3'), isFalse);
      expect(appearance.value.components.containsKey('nom_2'), isFalse);
      expect(appearance.value.components.containsKey('nom_3'), isFalse);

      await tester.tap(find.byKey(const ValueKey('super-value-extract-close')));
      await tester.pumpAndSettle();

      // Verify a single Undo restores the 3 original Cards and removes the ListView!
      expect(history.canUndo, isTrue);
      history.undo();
      await tester.pumpAndSettle();

      final restoredRoot = appearance.value.layout('root');
      expect(restoredRoot.placementsOf(SuperLayoutZone.center), [
        'header_val',
        'card_1',
        'card_2',
        'card_3',
      ]);
      expect(appearance.value.components.containsKey('card_2'), isTrue);
      expect(appearance.value.components.containsKey('card_3'), isTrue);
      expect(appearance.value.valueComponent('nom_1').binding, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'supports flexible similarity tolerance, unwrapContainer template mode, and in-place indexed bindings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('flexible_recurring_extract_'),
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
      // Card 1 has 2 SuperValues + 1 SuperAction; Card 2 has only 2 SuperValues (missing Action).
      // In structural mode they differ (3 vs 2 components), but in flexible mode they match!
      const rootLayout = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['c_1', 'c_2'],
        },
        slotTypes: {'c_1': 'registry:Card', 'c_2': 'registry:Card'},
        slotLabels: {'c_1': 'Ligne 1', 'c_2': 'Ligne 2'},
      );
      const subLayout1 = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['t_1', 's_1', 'a_1'],
        },
        slotTypes: {
          't_1': 'factory:Value',
          's_1': 'factory:Value',
          'a_1': 'factory:Action',
        },
        slotLabels: {'t_1': 'Titre', 's_1': 'SousTitre', 'a_1': 'Detail'},
      );
      const subLayout2 = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['t_2', 's_2'],
        },
        slotTypes: {'t_2': 'factory:Value', 's_2': 'factory:Value'},
        slotLabels: {'t_2': 'Titre', 's_2': 'SousTitre'},
      );

      final rootController = registry.layoutController(
        'root',
        fallback: rootLayout,
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
                    width: 900,
                    height: 700,
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: rootController,
                      builder: (_, config, _) => SuperLayout(
                        id: 'root',
                        label: 'Lignes',
                        config: config,
                        onChanged: (value) => rootController.value = value,
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
        layouts: {'root': rootLayout, 'sub_1': subLayout1, 'sub_2': subLayout2},
        styles: const {
          'c_1': ContainerStyle(radius: 14),
          'c_2': ContainerStyle(radius: 14),
        },
        components: {
          'c_1': NativeComponentConfig(
            placements: {
              'child': ['sub_1'],
            },
            slotTypes: {'sub_1': 'registry:Layout'},
          ),
          'c_2': NativeComponentConfig(
            placements: {
              'child': ['sub_2'],
            },
            slotTypes: {'sub_2': 'registry:Layout'},
          ),
          't_1': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Titre A',
          ),
          's_1': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Sous A',
          ),
          'a_1': const SuperActionConfig(
            kind: SuperActionKind.text,
            label: 'Ouvrir',
          ),
          't_2': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Titre B',
          ),
          's_2': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Sous B',
          ),
        },
      );
      await tester.pumpAndSettle();

      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Titre A'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-more-Lignes')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-extract-super-values-Lignes')),
      );
      await tester.pumpAndSettle();

      // In default structural mode, c_1 (3 targets) and c_2 (2 targets) are not grouped.
      expect(
        find.byKey(const ValueKey('super-value-extract-group-root_center_c_1')),
        findsNothing,
      );

      // Open similarity settings and switch to 'Tolérante' (flexible) mode!
      await tester.tap(
        find.byKey(
          const ValueKey('super-value-extract-recurrence-settings-toggle'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tolérante'));
      await tester.pumpAndSettle();

      // Now the recurring group is detected with flexible similarity!
      expect(
        find.byKey(const ValueKey('super-value-extract-group-root_center_c_1')),
        findsOneWidget,
      );

      // Switch template mode from 'Conserver le bloc' to 'Fusionner conteneur' (unwrapContainer)
      await tester.tap(
        find.byKey(
          const ValueKey(
            'super-value-extract-group-template-mode-root_center_c_1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Validate and create repository
      await tester.enterText(
        find.byKey(const ValueKey('super-value-extract-repo-name')),
        'lignes_flex',
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

      final updatedRoot = appearance.value.layout('root');
      final listId = updatedRoot.placementsOf(SuperLayoutZone.center).single;
      final listConfig = appearance.value.listComponent(listId);

      // Because unwrapContainer was chosen, the ListView's template directly has
      // sub_1's placements ['t_1', 's_1', 'a_1'] and its row style inherited c_1's radius (14)!
      expect(listConfig.template.placementsOf(SuperLayoutZone.center), [
        't_1',
        's_1',
        'a_1',
      ]);
      expect(appearance.value.style(listId).radius, 14);

      await tester.tap(find.byKey(const ValueKey('super-value-extract-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'converts recurring blocks in a horizontal or non-expanding zone into a visible SuperListView without infinite-width constraint error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('horizontal_zone_listview_test_'),
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
      const rootLayout = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['h_card_1', 'h_card_2'],
        },
        slotTypes: {'h_card_1': 'registry:Card', 'h_card_2': 'registry:Card'},
        zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
        zoneFlows: {
          SuperLayoutZone.center: ZoneFlowConfig(
            scrollable: true,
            expandSlots: false,
            spacing: 12,
          ),
        },
      );
      const sub1 = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['hv_1'],
        },
        slotTypes: {'hv_1': 'factory:Value'},
        slotLabels: {'hv_1': 'Label'},
      );
      const sub2 = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['hv_2'],
        },
        slotTypes: {'hv_2': 'factory:Value'},
        slotLabels: {'hv_2': 'Label'},
      );

      final rootController = registry.layoutController(
        'mainLayout',
        fallback: rootLayout,
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => JsonRepositoryScope(
              store: repoStore,
              child: SuperPage(
                child: SizedBox(
                  key: hostKey,
                  width: 900,
                  height: 276,
                  child: ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: rootController,
                    builder: (_, config, _) => SuperLayout(
                      label: 'Main Layout',
                      config: config,
                      onChanged: (value) => rootController.value = value,
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
        layouts: {'mainLayout': rootLayout, 'h_sub_1': sub1, 'h_sub_2': sub2},
        components: {
          'h_card_1': NativeComponentConfig(
            placements: {
              'child': ['h_sub_1'],
            },
            slotTypes: {'h_sub_1': 'registry:Layout'},
          ),
          'h_card_2': NativeComponentConfig(
            placements: {
              'child': ['h_sub_2'],
            },
            slotTypes: {'h_sub_2': 'registry:Layout'},
          ),
          'hv_1': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Carte Alpha',
          ),
          'hv_2': const SuperValueConfig(
            mode: SuperValueMode.display,
            initialText: 'Carte Beta',
          ),
        },
      );
      await tester.pumpAndSettle();

      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Carte Alpha'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-more-Main Layout')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-extract-super-values-Main Layout'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('super-value-extract-repo-name')),
        'horiz_cards',
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

      await tester.tap(find.byKey(const ValueKey('super-value-extract-close')));
      await tester.pumpAndSettle();

      // Pump async reload of SuperListView items from the repository
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SuperListView), findsOneWidget);
      expect(find.text('Carte Alpha'), findsOneWidget);
      expect(find.text('Carte Beta'), findsOneWidget);
    },
  );
}
