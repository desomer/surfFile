import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/ai/vibe_stream_parser.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_action_config.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_list_view_config.dart';
import 'package:super_container_layout/models/super_tab_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/appearance/appearance_store.dart';
import 'package:super_container_layout/services/appearance/appearance_transfer.dart';
import 'package:super_container_layout/services/pages/editor_page_router.dart';
import 'package:super_container_layout/services/repositories/json_repository_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/appearance/appearance_scope.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_delta_recovery.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_work_highlight.dart';
import 'package:super_container_layout/widgets/editing/history/editor_history.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/components/super_list_view.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/components/super_tab.dart';

Map<String, Object?> _fileListPatch(String layoutId) => {
  'styles': {
    'background': {'color': '#F8FAFC'},
    'list-files:item': {
      'color': '#FFFFFF',
      'radius': 10,
      'padding': 12,
      'elevation': 1,
      'states': {
        'named': <String, Object?>{},
        'hover': {
          'style': {'color': '#F1F5F9'},
          'properties': ['background'],
        },
      },
    },
  },
  'components': {
    layoutId: {
      'type': 'layout',
      'zoneFlows': {
        'center': {'padding': 16, 'spacing': 12, 'expandSlots': true},
      },
      'placements': {
        'center': [
          {'id': 'list-files', 'type': 'registry:ListView'},
        ],
      },
    },
    'list-files': {
      'type': 'list',
      'binding': 'files',
      'itemExtent': 64,
      'spacing': 8,
      'allowAdd': true,
      'allowRemove': true,
      'emptyText': 'Aucun fichier disponible',
      'template': {
        'west': true,
        'westSize': 48,
        'east': true,
        'eastSize': 120,
        'autoSides': ['west', 'east'],
        'placements': {
          'west': [
            {'id': 'file-icon', 'type': 'registry:Action'},
          ],
          'center': [
            {'id': 'file-name', 'type': 'registry:Value'},
          ],
          'east': [
            {'id': 'file-size', 'type': 'registry:Value'},
          ],
        },
      },
    },
    'file-icon': {
      'type': 'action',
      'kind': 'icon',
      'variant': 'tonal',
      'icon': 'info',
    },
    'file-name': {
      'type': 'value',
      'binding': 'files[?].nom',
      'initialText': 'document.pdf',
      'fontWeight': 'medium',
      'fontSize': 15,
    },
    'file-size': {
      'type': 'value',
      'binding': 'files[?].taille',
      'initialText': '2.4 Mo',
      'fontSize': 13,
      'color': '#64748B',
      'textAlign': 'end',
    },
  },
};

void main() {
  test(
    'snapshot includes defaults without persisting or losing list types',
    () {
      final registry = Registry();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);
      var notifications = 0;
      appearance.addListener(() => notifications++);
      registry.layoutController('mainLayout');
      registry.listController('files');
      final template = const SuperLayoutConfig().withSlotMoved(
        'name',
        SuperLayoutZone.center,
        type: 'registry:Value',
      );
      registry.layoutController('files', fallback: template);

      final snapshot = registry.appearanceSnapshot(appearance.value);
      expect(snapshot.components['mainLayout'], isA<SuperLayoutConfig>());
      expect(snapshot.components['files'], isA<SuperListViewConfig>());
      expect(snapshot.listComponent('files').template, template);
      expect(appearance.value.components, isEmpty);
      expect(notifications, 0);

      final persisted = appearance.value.withListComponent(
        'files',
        const SuperListViewConfig(itemExtent: 90),
      );
      expect(
        registry.appearanceSnapshot(persisted).listComponent('files'),
        persisted.listComponent('files'),
      );
    },
  );

  Future<void> pumpChat(
    WidgetTester tester,
    ValueNotifier<Appearance> appearance,
    Registry registry,
    Future<String> Function(String) generate,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DefaultAssetBundle(
          bundle: _GuideBundle(),
          child: VibeChatDialog(
            controller: appearance,
            registry: registry,
            codec: const AppearanceCodec(),
            onClose: () {},
            onDrag: (_) {},
            generate: generate,
          ),
        ),
      ),
    ),
  );

  Future<void> send(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('vibe-chat-input')),
      'Ajoute une liste de fichiers.',
    );
    await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('detached file list retries and updates the displayed layout', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final appearance = ValueNotifier(Appearance());
    registry.bindAppearance(appearance);
    addTearDown(appearance.dispose);
    addTearDown(registry.unbindAppearance);
    final layout = registry.layoutController('mainLayout');
    var requests = 0;
    await pumpChat(tester, appearance, registry, (prompt) async {
      requests++;
      expect(prompt, contains('"mainLayout"'));
      if (requests == 2) {
        expect(prompt, contains('CORRECTION REQUISE'));
        expect(prompt, contains('Composants non rattachés'));
        expect(appearance.value.components, isEmpty);
        expect(appearance.value.styles, isEmpty);
      }
      return jsonEncode({
        'message': 'Liste appliquée.',
        'vibe': _fileListPatch(requests == 1 ? 'contA' : 'mainLayout'),
      });
    });
    await send(tester);
    expect(requests, 2);
    expect(find.text('Liste appliquée.'), findsOneWidget);
    expect(layout.value.placementsOf(SuperLayoutZone.center), ['list-files']);
    expect(appearance.value.components.containsKey('contA'), isFalse);
    expect(appearance.value.listComponent('list-files').itemExtent, 64);
    expect(appearance.value.style('list-files:item').radius, 10);
    expect(
      const AppearanceCodec()
          .decode(const AppearanceCodec().encode(appearance.value))
          .layout('mainLayout'),
      layout.value,
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => SuperLayout(config: layout.value),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(
        router: router,
        registry: registry,
        appearanceStore: _MemoryAppearanceStore(appearance.value),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SuperListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final alreadySaved in [false, true]) {
    testWidgets(
      'detached responses are refused (already saved: $alreadySaved)',
      (tester) async {
        final registry = Registry();
        final initial = alreadySaved
            ? const AppearanceCodec().patchFromJson(
                Appearance(),
                _fileListPatch('contA'),
              )
            : Appearance();
        final appearance = ValueNotifier(initial);
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);
        var requests = 0;
        await pumpChat(tester, appearance, registry, (_) async {
          requests++;
          return jsonEncode({
            'message': 'Liste appliquée.',
            'vibe': _fileListPatch('contA'),
          });
        });
        await send(tester);
        expect(requests, 4);
        expect(appearance.value, same(initial));
        expect(find.text('Liste appliquée.'), findsNothing);
        expect(find.textContaining('Composants non rattachés'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a declared new page can own new components', (tester) async {
    final registry = Registry();
    final appearance = ValueNotifier(Appearance());
    addTearDown(appearance.dispose);
    await pumpChat(tester, appearance, registry, (_) async {
      return jsonEncode({
        'message': 'Page créée.',
        'vibe': {
          ..._fileListPatch('files-page'),
          'pageCatalog': {
            'pages': [
              {'id': 'files-page', 'name': 'Fichiers', 'path': '/files'},
            ],
          },
        },
      });
    });
    await send(tester);
    expect(find.text('Page créée.'), findsOneWidget);
    expect(appearance.value.pageCatalog.pages.single.id, 'files-page');
    expect(tester.takeException(), isNull);
  });

  for (final payload in <Map<String, Object?>>[
    {'message': 'Cet écran contient un conteneur principal.'},
    {'message': 'Cet écran contient un conteneur principal.', 'vibe': null},
    {
      'message': 'Cet écran contient un conteneur principal.',
      'vibe': <String, Object?>{},
    },
    {
      'message': 'Cet écran contient un conteneur principal.',
      'vibe': {
        'components': <String, Object?>{},
        'styles': <String, Object?>{},
      },
    },
  ]) {
    testWidgets(
      'question responses display answer without mutating appearance ($payload)',
      (tester) async {
        final registry = Registry();
        final initial = Appearance();
        final appearance = ValueNotifier(initial);
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);
        var notifications = 0;
        appearance.addListener(() => notifications++);
        var validations = 0;
        String? sentPrompt;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _GuideBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  onClose: () {},
                  onDrag: (_) {},
                  validateAppearance: (_) => validations++,
                  generate: (prompt) async {
                    sentPrompt = prompt;
                    return jsonEncode(payload);
                  },
                ),
              ),
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Quels composants sont sur la page ?',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(sentPrompt, contains('"vibe":null'));
        expect(
          find.text('Cet écran contient un conteneur principal.'),
          findsOneWidget,
        );
        expect(appearance.value, same(initial));
        expect(notifications, 0);
        expect(validations, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed generation records the detailed cause and rejected response in chat conversation for next AI turn',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final prompts = <String>[];
      const invalidResponse =
          '{"message":"Raté","vibe":{"components":{"broken-comp":{"type":"unknown_widget"}}}}';

      await pumpChat(tester, appearance, registry, (prompt) async {
        prompts.add(prompt);
        if (prompts.length <= 4) {
          return invalidResponse;
        }
        return jsonEncode({
          'message': 'Corrigé après lecture de la cause.',
          'vibe': _fileListPatch('mainLayout'),
        });
      });

      // Premier envoi : les 4 tentatives échouent sur le composant invalide.
      await send(tester);
      expect(prompts.length, 4);
      // Les tentatives de correction ont reçu la cause précise du composant en erreur.
      expect(prompts[1], contains('CORRECTION REQUISE'));
      expect(prompts[1], contains('Composant "broken-comp"'));
      expect(prompts[1], contains('unknown_widget'));

      // Le chat affiche la cause détaillée à l'utilisateur.
      expect(find.textContaining('Composant "broken-comp"'), findsOneWidget);

      // Deuxième envoi utilisateur : la conversation envoyée à l'IA contient
      // l'erreur détaillée et la réponse précédente invalide.
      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Corrige ton erreur.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(prompts.length, 5);
      expect(prompts[4], contains('Assistant (ERREUR À CORRIGER) :'));
      expect(prompts[4], contains('Composant "broken-comp"'));
      expect(prompts[4], contains(invalidResponse));
      expect(find.text('Corrigé après lecture de la cause.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('VibeChatAttachment detects image and text files and rejects unknown binary', () {
    final pngBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D,
    ]);
    final imageAttachment = VibeChatAttachment.fromBytes(
      pngBytes,
      name: 'maquette.png',
    );
    expect(imageAttachment.isImage, isTrue);
    expect(imageAttachment.isText, isFalse);
    expect(imageAttachment.mimeType, 'image/png');

    final textAttachment = VibeChatAttachment.fromBytes(
      Uint8List.fromList(utf8.encode('# Cahier des charges\nListe de tâches')),
      name: 'spec.md',
    );
    expect(textAttachment.isImage, isFalse);
    expect(textAttachment.isText, isTrue);
    expect(textAttachment.mimeType, 'text/markdown');
    expect(textAttachment.textContent, contains('Cahier des charges'));

    expect(
      () => VibeChatAttachment.fromBytes(
        Uint8List.fromList([0x00, 0x01, 0x02, 0xFF]),
        name: 'archive.bin',
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'attaching image and text files previews them, allows removal, and sends them to AI without requiring text input',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      // 1x1 transparent PNG
      final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      final imageFile = VibeChatAttachment.image(
        name: 'capture.png',
        bytes: pngBytes,
      );
      final textFile = VibeChatAttachment.text(
        name: 'notes.txt',
        content: 'Afficher une liste de fichiers avec icône et taille.',
      );
      final extraFile = VibeChatAttachment.text(
        name: 'ignorer.txt',
        content: 'Ce fichier sera retiré avant envoi.',
      );

      String? receivedPrompt;
      List<VibeChatAttachment>? receivedAttachments;

      Future<String> generateWithAttachments(
        String prompt, {
        List<VibeChatAttachment> attachments = const [],
      }) async {
        receivedPrompt = prompt;
        receivedAttachments = attachments;
        return jsonEncode({
          'message': 'Écran généré depuis les fichiers joints.',
          'vibe': _fileListPatch('mainLayout'),
        });
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                onClose: () {},
                onDrag: (_) {},
                pickAttachments: () async => [extraFile, imageFile, textFile],
                generate: generateWithAttachments,
              ),
            ),
          ),
        ),
      );

      // Clique sur le bouton d'import de fichiers
      await tester.tap(find.byKey(const ValueKey('vibe-chat-attach')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vibe-chat-pending-attachments')),
        findsOneWidget,
      );
      expect(find.text('ignorer.txt'), findsOneWidget);
      expect(find.text('capture.png'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);

      // Retire le premier fichier ("ignorer.txt")
      await tester.tap(
        find.byKey(const ValueKey('vibe-chat-remove-attachment-0')),
      );
      await tester.pumpAndSettle();

      expect(find.text('ignorer.txt'), findsNothing);
      expect(find.text('capture.png'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);

      // Envoie sans saisir de texte dans le champ d'entrée
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vibe-chat-pending-attachments')),
        findsNothing,
      );
      expect(receivedAttachments, isNotNull);
      expect(receivedAttachments!.map((a) => a.name), [
        'capture.png',
        'notes.txt',
      ]);
      expect(
        receivedPrompt,
        contains('[Fichier image joint : "capture.png" (image/png)]'),
      );
      expect(
        receivedPrompt,
        contains('[Fichier texte joint : "notes.txt" (text/plain)]'),
      );
      expect(
        receivedPrompt,
        contains('Afficher une liste de fichiers avec icône et taille.'),
      );
      expect(receivedPrompt, isNot(contains('ignorer.txt')));
      expect(
        find.text('Écran généré depuis les fichiers joints.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pasting attachment from clipboard and handling invalid file format error',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      String? sentPrompt;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                onClose: () {},
                onDrag: (_) {},
                pickAttachments: () async => throw const FormatException(
                  'Format de fichier non pris en charge ("test.exe").',
                ),
                pasteAttachments: () async => [
                  VibeChatAttachment.text(
                    name: 'presse-papiers.json',
                    content: '{"titre":"Mon écran"}',
                    mimeType: 'application/json',
                  ),
                ],
                generate: (prompt) async {
                  sentPrompt = prompt;
                  return jsonEncode({'message': 'Collage bien reçu.'});
                },
              ),
            ),
          ),
        ),
      );

      // Test erreur sur fichier invalide
      await tester.tap(find.byKey(const ValueKey('vibe-chat-attach')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('vibe-chat-attachment-error')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Format de fichier non pris en charge'),
        findsOneWidget,
      );

      // Test collage depuis le presse-papiers
      await tester.tap(
        find.byKey(const ValueKey('vibe-chat-paste-attachment')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('vibe-chat-attachment-error')),
        findsNothing,
      );
      expect(find.text('presse-papiers.json'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(sentPrompt, contains('presse-papiers.json'));
      expect(sentPrompt, contains('{"titre":"Mon écran"}'));
      expect(find.text('Collage bien reçu.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '3-dot context menu exposes "Modifier avec l’IA…", opens VibeChatDialog with scope, and restricts AI changes to that scope',
    (tester) async {
      final registry = Registry()..bootstrap();
      final initialAppearance = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'components': {
            'mainLayout': {
              'type': 'layout',
              'west': true,
              'westSize': 200,
              'placements': {
                'west': [
                  {'id': 'west-label', 'type': 'registry:Value'},
                ],
                'center': [
                  {'id': 'center-label', 'type': 'registry:Value'},
                ],
              },
            },
            'west-label': {'type': 'value', 'text': 'Menu Ouest'},
            'center-label': {'type': 'value', 'text': 'Zone Centrale'},
          },
        }),
      );
      final layout = registry.layoutController(
        'mainLayout',
        fallback: initialAppearance.layout('mainLayout'),
      );
      final store = _MemoryAppearanceStore(initialAppearance);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ValueListenableBuilder<SuperLayoutConfig>(
              valueListenable: layout,
              builder: (_, config, _) => SuperLayout(
                id: 'mainLayout',
                label: 'Principal',
                config: config,
                onChanged: (next) => layout.value = next,
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _GuideBundle(),
          child: SuperApp(
            router: router,
            registry: registry,
            appearanceStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final targetElement = tester.element(find.text('Zone Centrale'));
      StyleEditScope.controllerOf(targetElement)!.value = true;
      await tester.pumpAndSettle();

      // Right-click on 'Zone Centrale' to open the context menu.
      await tester.tap(
        find.text('Zone Centrale'),
        buttons: 2, // kSecondaryMouseButton
      );
      await tester.pumpAndSettle();

      // Open the 3-dot vertical menu on the 'Centre' zone entry.
      final moreCentre = find.byKey(const ValueKey('style-menu-more-Centre'));
      expect(moreCentre, findsOneWidget);
      await tester.tap(moreCentre);
      await tester.pumpAndSettle();

      final aiItem = find.byKey(const ValueKey('style-menu-ai-Centre'));
      expect(aiItem, findsOneWidget);
      expect(find.text('Modifier avec l’IA…'), findsOneWidget);

      await tester.tap(aiItem);
      await tester.pumpAndSettle();

      // VibeChatDialog is now open in StyleEditBanner with the 'Principal — zone Centre' scope banner.
      expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vibe-chat-scope-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('Principal — zone Centre'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scoped VibeChatDialog instructs AI about the scope, retries if AI only edits outside scope, and applies only in-scope changes',
    (tester) async {
      final registry = Registry()..bootstrap();
      final initial = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'components': {
            'outerLayout': {
              'type': 'layout',
              'west': true,
              'westSize': 200,
              'placements': {
                'west': [
                  {'id': 'west-label', 'type': 'registry:Value'},
                ],
              },
            },
            'mainLayout': {
              'type': 'layout',
              'placements': {
                'center': [
                  {'id': 'center-label', 'type': 'registry:Value'},
                ],
              },
            },
            'west-label': {'type': 'value', 'text': 'Menu Ouest'},
            'center-label': {'type': 'value', 'text': 'Zone Centrale'},
          },
        }),
      );
      final appearance = ValueNotifier(initial);
      registry.bindAppearance(appearance);
      registry.layoutController(
        'mainLayout',
        fallback: initial.layout('mainLayout'),
      );
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final prompts = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                scope: const VibeChatScope(
                  componentId: 'mainLayout',
                  label: 'Principal',
                  zoneId: 'center',
                  zoneLabel: 'Centre',
                ),
                onClose: () {},
                onDrag: (_) {},
                generate: (prompt) async {
                  prompts.add(prompt);
                  if (prompts.length == 1) {
                    // Attempt 1 only tries to edit out-of-scope 'west-label' -> rejected!
                    return jsonEncode({
                      'message': 'Hors scope.',
                      'vibe': {
                        'components': {
                          'west-label': {'text': 'Interdit'},
                        },
                      },
                    });
                  }
                  // Attempt 2 edits both in-scope 'center-label' and out-of-scope 'west-label':
                  // 'west-label' is stripped and 'center-label' is applied!
                  return jsonEncode({
                    'message': 'Zone centrale mise à jour.',
                    'vibe': {
                      'components': {
                        'west-label': {'text': 'Toujours interdit'},
                        'center-label': {'text': 'Centre modifié par IA'},
                      },
                    },
                  });
                },
              ),
            ),
          ),
        ),
      );

      await send(tester);

      expect(prompts.length, 2);
      expect(prompts[0], contains('RESTRICTION STRICTE DE SCOPE'));
      expect(prompts[0], contains('"mainLayout"'));
      expect(prompts[0], contains('"center"'));
      expect(prompts[1], contains('CORRECTION REQUISE'));
      expect(prompts[1], contains('Modifications hors du scope autorisé'));

      expect(find.text('Zone centrale mise à jour.'), findsOneWidget);
      expect(
        appearance.value.valueComponent('west-label').initialText,
        'Menu Ouest',
      );
      expect(
        appearance.value.valueComponent('center-label').initialText,
        'Centre modifié par IA',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming generator renders live message, component patch progress, and speed mode selection without overflow at 320px',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final observedModes = <VibeAiSpeedMode>[];
      late StreamController<GeminiStreamEvent> streamController;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 520,
                child: DefaultAssetBundle(
                  bundle: _GuideBundle(),
                  child: VibeChatDialog(
                    controller: appearance,
                    registry: registry,
                    codec: const AppearanceCodec(),
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (_) =>
                        Future.error('Should use streamGenerate instead'),
                    streamGenerate:
                        (
                          prompt, {
                          systemInstruction,
                          staticGuide,
                          attachments = const [],
                          speedMode = VibeAiSpeedMode.fast,
                        }) {
                          observedModes.add(speedMode);
                          expect(
                            systemInstruction,
                            VibeChatDialog.defaultSystemInstruction,
                          );
                          expect(
                            staticGuide,
                            VibeChatDialog.composeStaticGuide(
                              screenGuide: 'Guide de test.',
                              repositoryGuide: 'Repositories de test.',
                              defaultDesignGuide: 'Design de test.',
                            ),
                          );
                          streamController =
                              StreamController<GeminiStreamEvent>();
                          return streamController.stream;
                        },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Select ultraFast speed mode ('Éclair')
      await tester.tap(find.byKey(const ValueKey('vibe-chat-speed-ultraFast')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Ajoute un titre de bienvenue.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();

      expect(observedModes, [VibeAiSpeedMode.ultraFast]);
      expect(
        find.byKey(const ValueKey('vibe-chat-streaming-bubble')),
        findsOneWidget,
      );
      expect(find.text('Génération en cours…'), findsOneWidget);

      // Stream partial message text
      const chunk1 = '{"message":"Création en';
      streamController.add(
        const GeminiStreamEvent(
          deltaText: chunk1,
          accumulatedText: chunk1,
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      expect(find.text('Création en'), findsOneWidget);
      expect(find.textContaining('Construction du patch UI'), findsNothing);

      // Stream completion of message + start of vibe components
      const chunk2 =
          ' direct…","vibe":{"components":{"mainLayout":{"type":"layout","placements":{"center":[{"id":"welcome-val","type":"registry:Value"}]}},"welcome-val":{"type":"value","text":"Bienvenue"}}';
      streamController.add(
        const GeminiStreamEvent(
          deltaText: chunk2,
          accumulatedText: '$chunk1$chunk2',
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      expect(find.text('Création en direct…'), findsOneWidget);
      expect(
        find.text('Construction du patch UI (2 composants)…'),
        findsOneWidget,
      );

      // Finish JSON object and close stream
      const chunk3 = '}}';
      const fullText = '$chunk1$chunk2$chunk3';
      streamController.add(
        const GeminiStreamEvent(
          deltaText: chunk3,
          accumulatedText: fullText,
          isDone: false,
          usedContextCache: true,
        ),
      );
      streamController.add(
        const GeminiStreamEvent(
          deltaText: '',
          accumulatedText: fullText,
          isDone: true,
          usedContextCache: true,
        ),
      );
      await streamController.close();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vibe-chat-streaming-bubble')),
        findsNothing,
      );
      expect(find.text('Création en direct…'), findsOneWidget);
      expect(
        appearance.value.valueComponent('welcome-val').initialText,
        'Bienvenue',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scoped prompt omits global state, exports compact behaviors, and sends binary attachments only for current turn',
    (tester) async {
      final registry = Registry()..bootstrap();
      final base =
          AppearanceTransfer.applyVibe(
            Appearance(),
            jsonEncode({
              'components': {
                'outerLayout': {
                  'type': 'layout',
                  'west': true,
                  'placements': {
                    'west': [
                      {'id': 'global-nav', 'type': 'registry:Value'},
                    ],
                  },
                },
                'mainLayout': {
                  'type': 'layout',
                  'placements': {
                    'center': [
                      {'id': 'scoped-btn', 'type': 'registry:Action'},
                    ],
                  },
                },
                'global-nav': {'type': 'value', 'text': 'Navigation Globale'},
                'scoped-btn': {'type': 'action', 'label': 'Valider'},
              },
            }),
          ).withBehaviors('scoped-btn', [
            ComponentBehavior(
              id: 'b1',
              action: EmitEventAction(eventId: 'submit.click'),
            ),
          ]);

      const scope = VibeChatScope(
        componentId: 'scoped-btn',
        label: 'Bouton Valider',
      );
      final compactScoped = VibeChatDialog.exportScopedAi(base, scope);
      expect(compactScoped.contains('\n'), isFalse);
      expect(compactScoped, contains('"behaviors"'));
      expect(compactScoped, contains('"submit.click"'));
      expect(compactScoped, isNot(contains('global-nav')));

      final appearance = ValueNotifier(base);
      registry.bindAppearance(appearance);
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      final receivedTurnAttachments = <List<String>>[];
      final receivedTurnPrompts = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                scope: scope,
                onClose: () {},
                onDrag: (_) {},
                pickAttachments: () async => [
                  VibeChatAttachment.image(
                    name: 'maquette-tour1.png',
                    bytes: pngBytes,
                  ),
                ],
                generate: (_) => Future.error('Should use streamGenerate'),
                streamGenerate:
                    (
                      prompt, {
                      systemInstruction,
                      staticGuide,
                      attachments = const [],
                      speedMode = VibeAiSpeedMode.fast,
                    }) async* {
                      receivedTurnPrompts.add(prompt);
                      receivedTurnAttachments.add(
                        attachments.map((a) => a.name).toList(),
                      );
                      yield GeminiStreamEvent(
                        deltaText: '{"message":"OK","vibe":null}',
                        accumulatedText: '{"message":"OK","vibe":null}',
                        isDone: true,
                        usedContextCache: false,
                      );
                    },
              ),
            ),
          ),
        ),
      );

      // Turn 1: attach image and send
      await tester.tap(find.byKey(const ValueKey('vibe-chat-attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      // Turn 2: send plain text with NO new attachment
      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Question de suivi sans image.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(receivedTurnAttachments, [
        ['maquette-tour1.png'],
        <String>[],
      ]);
      expect(receivedTurnPrompts[0], contains('ÉTAT DU SCOPE CIBLÉ (JSON)'));
      expect(receivedTurnPrompts[0], isNot(contains('ÉTAT ACTUEL (JSON)')));
      expect(receivedTurnPrompts[0], isNot(contains('global-nav')));
      expect(
        receivedTurnPrompts[0],
        isNot(contains('Décris l’écran à créer ou les changements souhaités.')),
      );
      expect(
        receivedTurnPrompts[1],
        contains('[Fichier image joint : "maquette-tour1.png" (image/png)]'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('AppearanceTransfer.exportCompactAi omits default properties and indentation while keeping default container IDs and round-tripping through applyVibe', () {
    final registry = Registry()..bootstrap();
    final base = AppearanceTransfer.applyVibe(
      Appearance(),
      jsonEncode({
        'styles': {
          'background': {'color': '#0F172A'},
          'default-card': <String, Object?>{},
        },
        'components': {
          'secondaryLayout': {
            'type': 'layout',
            'placements': {
              'center': [
                {'id': 'kpi-title', 'type': 'registry:Value'},
              ],
            },
          },
          'kpi-title': {'type': 'value', 'text': 'Revenus'},
        },
      }),
    );
    final controller = ValueNotifier<Appearance>(base);
    registry.bindAppearance(controller);
    // Instancie mainLayout avec sa configuration par défaut (aucune modification persistée).
    registry.layoutController('mainLayout');
    addTearDown(controller.dispose);
    addTearDown(registry.unbindAppearance);

    final snapshot = registry.appearanceSnapshot(controller.value);
    final compact = AppearanceTransfer.exportCompactAi(snapshot);

    // Minifié sur une seule ligne, sans indentation ni version superflue.
    expect(compact.contains('\n'), isFalse);
    final decoded = jsonDecode(compact) as Map<String, dynamic>;
    expect(decoded.containsKey('version'), isFalse);
    expect(decoded.containsKey('backgroundOpacity'), isFalse);
    expect(decoded.containsKey('windowOpacity'), isFalse);
    expect(decoded.containsKey('windowEffect'), isFalse);

    // Le style identique à ContainerStyle() par défaut est omis, le personnalisé est conservé en hex court.
    final styles = decoded['styles'] as Map<String, dynamic>;
    expect(styles.containsKey('default-card'), isFalse);
    expect(styles['background'], {'color': '#0F172A'});

    // Le conteneur par défaut instancié "mainLayout" reste présent sans ses dimensions/zones par défaut.
    final components = decoded['components'] as Map<String, dynamic>;
    expect(components.containsKey('mainLayout'), isTrue);
    final mainLayoutJson = components['mainLayout'] as Map<String, dynamic>;
    expect(mainLayoutJson['type'], 'layout');
    expect(mainLayoutJson.containsKey('westSize'), isFalse);
    expect(mainLayoutJson.containsKey('placements'), isFalse);
    expect(
      (components['kpi-title'] as Map<String, dynamic>).containsKey('fontSize'),
      isFalse,
    );

    // La sortie compacte reste directement acceptée par AppearanceTransfer.applyVibe.
    final restored = AppearanceTransfer.applyVibe(Appearance(), compact);
    expect(restored.components.containsKey('mainLayout'), isTrue);
    expect(restored.layout('mainLayout'), const SuperLayoutConfig());
    expect(restored.valueComponent('kpi-title').initialText, 'Revenus');
    expect(restored.backgroundStyle.color, const Color(0xFF0F172A));
  });

  testWidgets(
    'speed selector passes VibeAiSpeedMode.reasoning to streamGenerate and global prompt embeds single-line exportCompactAi',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final observedModes = <VibeAiSpeedMode>[];
      final observedPrompts = <String>[];
      final streamRelease = Completer<void>();
      addTearDown(() {
        if (!streamRelease.isCompleted) {
          streamRelease.complete();
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                onClose: () {},
                onDrag: (_) {},
                generate: (_) => Future.error('Should use streamGenerate'),
                streamGenerate:
                    (
                      prompt, {
                      systemInstruction,
                      staticGuide,
                      attachments = const [],
                      speedMode = VibeAiSpeedMode.fast,
                    }) async* {
                      observedModes.add(speedMode);
                      observedPrompts.add(prompt);
                      yield const GeminiStreamEvent(
                        deltaText: '{"message":"Analyse approfondie…",',
                        accumulatedText: '{"message":"Analyse approfondie…",',
                        isDone: false,
                        usedContextCache: true,
                      );
                      await streamRelease.future;
                      yield const GeminiStreamEvent(
                        deltaText: '"vibe":null}',
                        accumulatedText:
                            '{"message":"Analyse approfondie…","vibe":null}',
                        isDone: false,
                        usedContextCache: true,
                      );
                      yield const GeminiStreamEvent(
                        deltaText: '',
                        accumulatedText:
                            '{"message":"Analyse approfondie…","vibe":null}',
                        isDone: true,
                        usedContextCache: true,
                      );
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sélectionne le mode "Précis" (VibeAiSpeedMode.reasoning).
      await tester.tap(find.byKey(const ValueKey('vibe-chat-speed-reasoning')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Vérifie la structure actuelle.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();
      await tester.pump();

      expect(observedModes, [VibeAiSpeedMode.reasoning]);
      expect(find.text('Analyse approfondie…'), findsOneWidget);

      // Les puces de vitesse sont désactivées pendant la génération en cours.
      await tester.tap(find.byKey(const ValueKey('vibe-chat-speed-ultraFast')));
      await tester.pump();

      // Vérifie que l'état global envoyé est minifié sur une seule ligne et contient mainLayout.
      final promptLines = observedPrompts.single.split('\n');
      final stateHeaderIndex = promptLines.indexOf('ÉTAT ACTUEL (JSON) :');
      expect(stateHeaderIndex, greaterThanOrEqualTo(0));
      final compactStateLine = promptLines[stateHeaderIndex + 1];
      final decodedState = jsonDecode(compactStateLine) as Map<String, dynamic>;
      final stateComponents =
          decodedState['components'] as Map<String, dynamic>;
      expect(stateComponents.containsKey('mainLayout'), isTrue);
      expect(
        (stateComponents['mainLayout'] as Map<String, dynamic>)['type'],
        'layout',
      );

      streamRelease.complete();
      await tester.pumpAndSettle();

      expect(find.text('Analyse approfondie…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'askUser card renders pre-selected defaults, collects custom answers including Autre…, locks card, and applies Turn 2 patch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final prompts = <String>[];
      await pumpChat(tester, appearance, registry, (prompt) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          return jsonEncode({
            'message': 'Précise le formulaire B2B :',
            'askUser': {
              'questions': [
                {
                  'id': 'layout',
                  'title': 'Disposition du formulaire',
                  'type': 'single',
                  'options': ['1 colonne', '2 colonnes'],
                  'default': '2 colonnes',
                },
                {
                  'id': 'fields',
                  'title': 'Champs entreprise à inclure',
                  'type': 'multi',
                  'options': ['SIRET', 'TVA', 'IBAN'],
                  'default': ['SIRET'],
                },
                {
                  'id': 'rgpd',
                  'title': 'Case consentement RGPD',
                  'type': 'boolean',
                  'default': false,
                },
                {
                  'id': 'cta',
                  'title': 'Texte du bouton principal',
                  'type': 'text',
                  'default': 'Envoyer',
                },
              ],
            },
            'vibe': null,
          });
        }
        return jsonEncode({
          'message': 'Formulaire B2B généré.',
          'askUser': null,
          'vibe': {
            'components': {
              'mainLayout': {
                'type': 'layout',
                'placements': {
                  'center': [
                    {'id': 'b2b-cta', 'type': 'registry:Action'},
                  ],
                },
              },
              'b2b-cta': {'type': 'action', 'label': 'Demander un devis'},
            },
          },
        });
      });

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Crée un formulaire B2B complet.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      // Turn 1 ne mute pas l'apparence et affiche la carte interactive avec les défauts pré-sélectionnés.
      expect(prompts, hasLength(1));
      expect(appearance.value.components, isEmpty);
      expect(find.text('Précise le formulaire B2B :'), findsOneWidget);
      expect(find.byKey(const ValueKey('vibe-ask-user-card')), findsOneWidget);

      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('vibe-ask-option-layout-0')),
            )
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('vibe-ask-option-layout-1')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('vibe-ask-option-fields-0')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('vibe-ask-option-fields-1')),
            )
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('vibe-ask-switch-rgpd')))
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vibe-ask-text-cta')))
            .controller!
            .text,
        'Envoyer',
      );

      // 1) Single : sélectionne une puce puis bascule sur « Autre… » avec texte personnalisé.
      await tester.tap(find.byKey(const ValueKey('vibe-ask-option-layout-0')));
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('vibe-ask-option-layout-0')),
            )
            .selected,
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey('vibe-ask-other-chip-layout')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('vibe-ask-other-input-layout')),
        'Grille 3 colonnes',
      );

      // 2) Multi : désélectionne SIRET, active TVA et IBAN.
      await tester.tap(find.byKey(const ValueKey('vibe-ask-option-fields-0')));
      await tester.tap(find.byKey(const ValueKey('vibe-ask-option-fields-1')));
      await tester.tap(find.byKey(const ValueKey('vibe-ask-option-fields-2')));
      await tester.pump();

      // 3) Boolean : bascule le Switch RGPD à Oui.
      await tester.tap(find.byKey(const ValueKey('vibe-ask-switch-rgpd')));
      await tester.pump();

      // 4) Text : remplace le texte du bouton principal.
      await tester.enterText(
        find.byKey(const ValueKey('vibe-ask-text-cta')),
        'Demander un devis',
      );
      await tester.pump();

      // Valide via « Générer ».
      final submitButton = find.byKey(const ValueKey('vibe-ask-user-submit'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // La carte est verrouillée à l'état résolu et le tour 2 a appliqué le patch !
      expect(find.byKey(const ValueKey('vibe-ask-user-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('vibe-ask-user-resolved')),
        findsOneWidget,
      );
      expect(find.text('Réponses envoyées'), findsOneWidget);
      expect(find.text('Formulaire B2B généré.'), findsOneWidget);

      expect(prompts, hasLength(2));
      expect(prompts[1], contains('Questions posées :'));
      expect(prompts[1], contains('Réponses aux questions de clarification :'));
      expect(
        prompts[1],
        contains('• Disposition du formulaire : Grille 3 colonnes'),
      );
      expect(prompts[1], contains('• Champs entreprise à inclure : TVA, IBAN'));
      expect(prompts[1], contains('• Case consentement RGPD : Oui'));
      expect(
        prompts[1],
        contains('• Texte du bouton principal : Demander un devis'),
      );
      expect(
        prompts[1],
        contains('sans poser de nouvelles questions ("askUser": null).'),
      );

      expect(
        appearance.value.actionComponent('b2b-cta').label,
        'Demander un devis',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'askUser Passer button skips in 1 click with recommended defaults and streaming bubble shows Préparation des questions…',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final prompts = <String>[];
      final turn1Controller = StreamController<GeminiStreamEvent>();
      addTearDown(() {
        if (!turn1Controller.isClosed) {
          turn1Controller.close();
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                onClose: () {},
                onDrag: (_) {},
                generate: (_) =>
                    Future.error('Should use streamGenerate instead'),
                streamGenerate:
                    (
                      prompt, {
                      systemInstruction,
                      staticGuide,
                      attachments = const [],
                      speedMode = VibeAiSpeedMode.fast,
                    }) {
                      prompts.add(prompt);
                      if (prompts.length == 1) {
                        return turn1Controller.stream;
                      }
                      final turn2Json = jsonEncode({
                        'message': 'Tableau de bord créé avec les défauts.',
                        'askUser': null,
                        'vibe': {
                          'components': {
                            'mainLayout': {
                              'type': 'layout',
                              'placements': {
                                'center': [
                                  {
                                    'id': 'dash-title',
                                    'type': 'registry:Value',
                                  },
                                ],
                              },
                            },
                            'dash-title': {
                              'type': 'value',
                              'text': 'Vue Synthétique',
                            },
                          },
                        },
                      });
                      return Stream<GeminiStreamEvent>.value(
                        GeminiStreamEvent(
                          deltaText: turn2Json,
                          accumulatedText: turn2Json,
                          isDone: true,
                          usedContextCache: true,
                        ),
                      );
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Crée un tableau de bord analytique.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();

      const partialAskUser =
          '{"message":"Quelques choix rapides :","askUser":{"questions":[';
      turn1Controller.add(
        const GeminiStreamEvent(
          deltaText: partialAskUser,
          accumulatedText: partialAskUser,
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      expect(find.text('Quelques choix rapides :'), findsOneWidget);
      expect(find.text('Préparation des questions…'), findsOneWidget);

      const restAskUser =
          '{"id":"view","title":"Vue initiale","type":"single","options":["Synthétique","Détaillée"],"default":"Synthétique"},'
          '{"id":"export","title":"Export PDF","type":"boolean","default":true}]},"vibe":null}';
      const fullTurn1 = '$partialAskUser$restAskUser';
      turn1Controller.add(
        const GeminiStreamEvent(
          deltaText: restAskUser,
          accumulatedText: fullTurn1,
          isDone: true,
          usedContextCache: true,
        ),
      );
      await turn1Controller.close();
      await tester.pumpAndSettle();

      expect(appearance.value.components, isEmpty);
      expect(find.byKey(const ValueKey('vibe-ask-user-card')), findsOneWidget);

      // Clic immédiat sur « Passer » : applique les valeurs par défaut recommandées par l'IA.
      final skipButton = find.byKey(const ValueKey('vibe-ask-user-skip'));
      await tester.ensureVisible(skipButton);
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('vibe-ask-user-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('vibe-ask-user-resolved')),
        findsOneWidget,
      );
      expect(find.text('Valeurs par défaut appliquées'), findsOneWidget);
      expect(
        find.text('Tableau de bord créé avec les défauts.'),
        findsOneWidget,
      );

      expect(prompts, hasLength(2));
      expect(
        prompts[1],
        contains(
          'Réponses aux questions de clarification (valeurs par défaut retenues) :',
        ),
      );
      expect(prompts[1], contains('• Vue initiale : Synthétique'));
      expect(prompts[1], contains('• Export PDF : Oui'));
      expect(prompts[1], contains('("askUser": null)'));
      expect(
        appearance.value.valueComponent('dash-title').initialText,
        'Vue Synthétique',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual text message auto-dismisses an unanswered askUser card', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final appearance = ValueNotifier(Appearance());
    registry.bindAppearance(appearance);
    registry.layoutController('mainLayout');
    addTearDown(appearance.dispose);
    addTearDown(registry.unbindAppearance);

    var turn = 0;
    await pumpChat(tester, appearance, registry, (_) async {
      turn++;
      if (turn == 1) {
        return jsonEncode({
          'message': 'Quel style souhaites-tu ?',
          'askUser': {
            'questions': [
              {
                'id': 'theme',
                'title': 'Ambiance',
                'type': 'single',
                'options': ['Clair', 'Sombre'],
                'default': 'Clair',
              },
            ],
          },
          'vibe': null,
        });
      }
      return jsonEncode({
        'message': 'Titre simple ajouté.',
        'vibe': {
          'components': {
            'mainLayout': {
              'type': 'layout',
              'placements': {
                'center': [
                  {'id': 'simple-title', 'type': 'registry:Value'},
                ],
              },
            },
            'simple-title': {'type': 'value', 'text': 'Bonjour'},
          },
        },
      });
    });

    await tester.enterText(
      find.byKey(const ValueKey('vibe-chat-input')),
      'Crée une page.',
    );
    await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vibe-ask-user-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('vibe-ask-user-resolved')), findsNothing);

    // L'utilisateur ignore la carte et saisit directement un nouveau message.
    await tester.enterText(
      find.byKey(const ValueKey('vibe-chat-input')),
      'Finalement ajoute juste un titre Bonjour.',
    );
    await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
    await tester.pumpAndSettle();

    expect(turn, 2);
    expect(find.byKey(const ValueKey('vibe-ask-user-card')), findsNothing);
    expect(
      find.byKey(const ValueKey('vibe-ask-user-resolved')),
      findsOneWidget,
    );
    expect(find.text('Questionnaire ignoré'), findsOneWidget);
    expect(
      appearance.value.valueComponent('simple-title').initialText,
      'Bonjour',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'questioning level slider updates dynamic turn directive without mutating cached systemInstruction, caps light questions, and rejects askUser at level 0',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final changedLevels = <VibeQuestioningLevel>[];
      final systemInstructions = <String?>[];
      final turnPrompts = <String>[];
      var callIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                onClose: () {},
                onDrag: (_) {},
                onQuestioningLevelChanged: changedLevels.add,
                generate: (_) => Future.error('Should use streamGenerate'),
                streamGenerate:
                    (
                      prompt, {
                      systemInstruction,
                      staticGuide,
                      attachments = const [],
                      speedMode = VibeAiSpeedMode.fast,
                    }) {
                      callIndex++;
                      systemInstructions.add(systemInstruction);
                      turnPrompts.add(prompt);
                      late final String payload;
                      if (callIndex == 1) {
                        // Mode Aucun (0) : l'IA renvoie à tort un askUser -> rejeté puis relancé !
                        payload = jsonEncode({
                          'message': 'Question interdite',
                          'askUser': {
                            'questions': [
                              {'id': 'q1', 'title': 'Interdit', 'type': 'text'},
                            ],
                          },
                          'vibe': null,
                        });
                      } else if (callIndex == 2) {
                        // Relance automatique de la tentative 2 en mode Aucun -> applique le patch !
                        payload = jsonEncode({
                          'message': 'Généré directement sans question.',
                          'vibe': {
                            'components': {
                              'mainLayout': {
                                'type': 'layout',
                                'placements': {
                                  'center': [
                                    {
                                      'id': 'direct-label',
                                      'type': 'registry:Value',
                                    },
                                  ],
                                },
                              },
                              'direct-label': {
                                'type': 'value',
                                'text': 'Mode Aucun OK',
                              },
                            },
                          },
                        });
                      } else if (callIndex == 3) {
                        // Mode Léger (1) : l'IA renvoie 4 questions -> plafonné à 2 !
                        payload = jsonEncode({
                          'message': 'Deux questions rapides :',
                          'askUser': {
                            'questions': [
                              {
                                'id': 'q1',
                                'title': 'Question 1',
                                'type': 'text',
                              },
                              {
                                'id': 'q2',
                                'title': 'Question 2',
                                'type': 'text',
                              },
                              {
                                'id': 'q3',
                                'title': 'Question 3 en trop',
                                'type': 'text',
                              },
                              {
                                'id': 'q4',
                                'title': 'Question 4 en trop',
                                'type': 'text',
                              },
                            ],
                          },
                          'vibe': null,
                        });
                      } else if (callIndex == 4) {
                        // Mode Approfondi (3) : pose un questionnaire
                        payload = jsonEncode({
                          'message': 'Cadrage complet :',
                          'askUser': {
                            'questions': [
                              {
                                'id': 'arch',
                                'title': 'Architecture',
                                'type': 'single',
                                'options': ['Standard', 'Modulaire'],
                                'default': 'Modulaire',
                              },
                            ],
                          },
                          'vibe': null,
                        });
                      } else {
                        // Suite au clic Passer en mode Approfondi -> anti-boucle actif !
                        payload = jsonEncode({
                          'message': 'Écran cadré créé.',
                          'vibe': {
                            'components': {
                              'mainLayout': {
                                'type': 'layout',
                                'placements': {
                                  'center': [
                                    {
                                      'id': 'thorough-label',
                                      'type': 'registry:Value',
                                    },
                                  ],
                                },
                              },
                              'thorough-label': {
                                'type': 'value',
                                'text': 'Modulaire',
                              },
                            },
                          },
                        });
                      }
                      return Stream<GeminiStreamEvent>.value(
                        GeminiStreamEvent(
                          deltaText: payload,
                          accumulatedText: payload,
                          isDone: true,
                          usedContextCache: true,
                        ),
                      );
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Valeur initiale par défaut : Équilibré (2).
      expect(find.text('Équilibré'), findsOneWidget);

      // Déplace le slider sur 0 (Aucun).
      final sliderFinder = find.byKey(
        const ValueKey('vibe-chat-questioning-slider'),
      );
      var slider = tester.widget<Slider>(sliderFinder);
      slider.onChanged!(0);
      await tester.pumpAndSettle();
      expect(find.text('Aucun'), findsOneWidget);
      expect(changedLevels.last, VibeQuestioningLevel.none);

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Crée un formulaire rapide.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      // Tentative 1 rejetée car askUser est interdit au cran 0, tentative 2 appliquée !
      expect(callIndex, 2);
      expect(turnPrompts[0], contains('0/3 (Aucun)'));
      expect(turnPrompts[1], contains('CORRECTION REQUISE'));
      expect(
        turnPrompts[1],
        contains('Le questionnaire "askUser" est désactivé'),
      );
      expect(
        appearance.value.valueComponent('direct-label').initialText,
        'Mode Aucun OK',
      );

      // Passe le slider sur 1 (Léger) : plafonne 4 questions à 2.
      slider = tester.widget<Slider>(sliderFinder);
      slider.onChanged!(1);
      await tester.pumpAndSettle();
      expect(find.text('Léger'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Demande floue.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(turnPrompts[2], contains('1/3 (Léger, max 2 questions)'));
      expect(find.text('Question 1'), findsOneWidget);
      expect(find.text('Question 2'), findsOneWidget);
      expect(find.text('Question 3 en trop'), findsNothing);
      expect(find.text('Question 4 en trop'), findsNothing);

      // Passe le slider sur 3 (Approfondi) et vérifie l'absence de boucle après Passer.
      slider = tester.widget<Slider>(sliderFinder);
      slider.onChanged!(3);
      await tester.pumpAndSettle();
      expect(find.text('Approfondi'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Crée un portail complet.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(turnPrompts[3], contains('3/3 (Approfondi, 4 à 6 questions)'));
      final skipButtons = find.byKey(const ValueKey('vibe-ask-user-skip'));
      await tester.ensureVisible(skipButtons.first);
      await tester.tap(skipButtons.first);
      await tester.pumpAndSettle();

      expect(
        turnPrompts[4],
        contains('Réponses déjà fournies — INTERDICTION d’utiliser "askUser"'),
      );
      expect(
        appearance.value.valueComponent('thorough-label').initialText,
        'Modulaire',
      );

      // L'instruction système mise en cache est restée strictement identique sur les 5 appels !
      expect(systemInstructions.toSet(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live streaming builds zones progressively in real time, persists once on completion, and groups the whole turn into a single Undo entry',
    (tester) async {
      final registry = Registry()..bootstrap();
      final store = _CountingAppearanceStore(Appearance());
      final mainLayout = registry.layoutController('mainLayout');
      addTearDown(registry.unbindAppearance);

      late StreamController<GeminiStreamEvent> streamController;
      late ValueNotifier<Appearance> appAppearance;
      late EditorHistoryController appHistory;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              appHistory = EditorHistoryScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayout,
                      builder: (_, cfg, _) => SuperLayout(config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    height: 560,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) =>
                            Future.error('Should use streamGenerate'),
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) {
                              streamController =
                                  StreamController<GeminiStreamEvent>();
                              return streamController.stream;
                            },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(router: router, appearanceStore: store, registry: registry),
      );
      await tester.pumpAndSettle();

      // Active le mode édition pour que EditorHistoryController enregistre l'historique Undo
      final editScopeContext = tester.element(
        find.byKey(const ValueKey('vibe-chat-input')),
      );
      StyleEditScope.controllerOf(editScopeContext)!.value = true;
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Construis le tableau de bord zone par zone.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();

      var accumulated = '';
      void emitDelta(String delta, {bool isDone = false}) {
        accumulated += delta;
        streamController.add(
          GeminiStreamEvent(
            deltaText: delta,
            accumulatedText: accumulated,
            isDone: isDone,
            usedContextCache: true,
          ),
        );
      }

      // Étape 1 : message + style + conteneur parent mainLayout (avant l'arrivée des composants feuilles)
      emitDelta(
        '{"message":"Construction en direct","vibe":{'
        '"styles":{"background":{"color":"#0F172A"}},'
        '"components":{"mainLayout":{"type":"layout","north":true,"northSize":56,'
        '"placements":{"north":[{"id":"live-header","type":"registry:Value"}],'
        '"center":[{"id":"live-cta","type":"registry:Action"}]}}',
      );
      await tester.pump();
      await tester.pump();

      expect(mainLayout.value.placementsOf(SuperLayoutZone.north), [
        'live-header',
      ]);
      expect(mainLayout.value.placementsOf(SuperLayoutZone.center), [
        'live-cta',
      ]);
      expect(
        appAppearance.value.style('background').color,
        const Color(0xFF0F172A),
      );
      // Aucune écriture disque intermédiaire pendant le streaming !
      expect(store.saveCalls, 0);

      // Étape 2 : le composant de la zone nord se referme -> affiché immédiatement
      emitDelta(',"live-header":{"type":"value","text":"En-tête Temps Réel"}');
      await tester.pump();
      await tester.pump();
      expect(find.text('En-tête Temps Réel'), findsOneWidget);
      expect(find.text('Lancer l’analyse'), findsNothing);
      expect(store.saveCalls, 0);

      // Étape 3 : le composant de la zone centrale se referme -> affiché immédiatement avant la fin du flux
      emitDelta(',"live-cta":{"type":"action","label":"Lancer l’analyse"}');
      await tester.pump();
      await tester.pump();
      expect(find.text('Lancer l’analyse'), findsOneWidget);
      expect(store.saveCalls, 0);

      // Étape 4 : fermeture finale du flux -> sauvegarde unique et une seule entrée Undo
      emitDelta('}}}', isDone: true);
      await streamController.close();
      await tester.pumpAndSettle();

      expect(store.saveCalls, 1);
      expect(appHistory.canUndo, isTrue);

      // Un seul Undo annule l'intégralité du tour streamé !
      appHistory.undo();
      await tester.pumpAndSettle();
      expect(mainLayout.value.placedSlotIds, isEmpty);
      expect(appAppearance.value.components, isEmpty);
      expect(appHistory.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live streaming auto-navigates to newly created page and rolls back route and state on retry',
    (tester) async {
      final registry = Registry()..bootstrap();
      final store = _CountingAppearanceStore(Appearance());
      final pageRouting = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Text('Accueil Initial'),
            ),
          ],
        ),
      );
      addTearDown(pageRouting.dispose);

      var attemptCount = 0;
      late StreamController<GeminiStreamEvent> attempt1Stream;
      late StreamController<GeminiStreamEvent> attempt2Stream;

      final controller = PersistentAppearanceController(
        store,
        (_) {},
        validateAppearance: (value) => pageRouting.validate(value.pageCatalog),
      );
      registry.bindAppearance(controller);
      addTearDown(registry.unbindAppearance);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _GuideBundle(),
          child: SuperAppScope(
            app: SuperApp(
              router: pageRouting.router,
              pageRouting: pageRouting,
              registry: registry,
            ),
            child: AppearanceScope(
              controller: controller,
              child: MaterialApp.router(
                routerConfig: pageRouting.router,
                builder: (context, child) => Scaffold(
                  body: Row(
                    children: [
                      Expanded(child: child!),
                      SizedBox(
                        width: 360,
                        height: 560,
                        child: Overlay(
                          initialEntries: [
                            OverlayEntry(
                              builder: (_) => VibeChatDialog(
                                controller: controller,
                                registry: registry,
                                validateAppearance: (value) =>
                                    pageRouting.validate(value.pageCatalog),
                                codec: const AppearanceCodec(),
                                initialQuestioningLevel:
                                    VibeQuestioningLevel.none,
                                onClose: () {},
                                onDrag: (_) {},
                                generate: (_) =>
                                    Future.error('Should use streamGenerate'),
                                streamGenerate:
                                    (
                                      prompt, {
                                      systemInstruction,
                                      staticGuide,
                                      attachments = const [],
                                      speedMode = VibeAiSpeedMode.fast,
                                    }) {
                                      attemptCount++;
                                      if (attemptCount == 1) {
                                        attempt1Stream =
                                            StreamController<
                                              GeminiStreamEvent
                                            >();
                                        return attempt1Stream.stream;
                                      }
                                      attempt2Stream =
                                          StreamController<GeminiStreamEvent>();
                                      return attempt2Stream.stream;
                                    },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Accueil Initial'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Crée une page /analytics.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();

      // Tentative 1 : émet pageCatalog en tête -> bascule immédiatement sur /analytics en live !
      const attempt1Part1 =
          '{"message":"Création page","vibe":{'
          '"pageCatalog":{"pages":[{"id":"analytics-page","name":"Analytique","path":"/analytics"}]},'
          '"components":{';
      attempt1Stream.add(
        const GeminiStreamEvent(
          deltaText: attempt1Part1,
          accumulatedText: attempt1Part1,
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        pageRouting.router.routeInformationProvider.value.uri.path,
        '/analytics',
      );

      // La fin de la tentative 1 contient un composant orphelin -> rejetée et rollback vers '/' !
      const attempt1Part2 = '"orphan":{"type":"value","text":"Détaché"}}}}';
      const attempt1Full = '$attempt1Part1$attempt1Part2';
      attempt1Stream.add(
        const GeminiStreamEvent(
          deltaText: attempt1Part2,
          accumulatedText: attempt1Full,
          isDone: true,
          usedContextCache: true,
        ),
      );
      await attempt1Stream.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // La tentative 2 a démarré après rollback complet vers '/' et apparence initiale vide !
      expect(attemptCount, 2);
      expect(pageRouting.router.routeInformationProvider.value.uri.path, '/');
      expect(controller.value.components, isEmpty);
      expect(controller.value.pageCatalog.pages, isEmpty);

      // Tentative 2 : émet pageCatalog + scaffold de la page -> bascule live sur /analytics !
      const attempt2Part1 =
          '{"message":"Page Analytique prête.","vibe":{'
          '"pageCatalog":{"pages":[{"id":"analytics-page","name":"Analytique","path":"/analytics"}]},'
          '"components":{"analytics-page":{"type":"scaffold","placements":{"body":[{"id":"analytics-kpi","type":"registry:Value"}]}}';
      attempt2Stream.add(
        const GeminiStreamEvent(
          deltaText: attempt2Part1,
          accumulatedText: attempt2Part1,
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        pageRouting.router.routeInformationProvider.value.uri.path,
        '/analytics',
      );

      // Puis le composant feuille arrive dans le flux -> visible en direct avant isDone !
      const attempt2Part2 =
          ',"analytics-kpi":{"type":"value","text":"CA : 128 k€"}';
      attempt2Stream.add(
        const GeminiStreamEvent(
          deltaText: attempt2Part2,
          accumulatedText: '$attempt2Part1$attempt2Part2',
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('CA : 128 k€'), findsOneWidget);

      // Fin du flux de la tentative 2
      const attempt2Part3 = '}}}';
      attempt2Stream.add(
        const GeminiStreamEvent(
          deltaText: attempt2Part3,
          accumulatedText: '$attempt2Part1$attempt2Part2$attempt2Part3',
          isDone: true,
          usedContextCache: true,
        ),
      );
      await attempt2Stream.close();
      await tester.pumpAndSettle();

      expect(
        pageRouting.router.routeInformationProvider.value.uri.path,
        '/analytics',
      );
      expect(find.text('CA : 128 k€'), findsOneWidget);
      expect(find.text('Page Analytique prête.'), findsOneWidget);
      expect(store.saveCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test('SCREEN_DESIGN_AI_GUIDE.md documents modern Design System rules and its reference JSON recipe applies cleanly', () {
    final guideFile = File('SCREEN_DESIGN_AI_GUIDE.md').existsSync()
        ? File('SCREEN_DESIGN_AI_GUIDE.md')
        : File('packages/super_container_layout/SCREEN_DESIGN_AI_GUIDE.md');
    expect(guideFile.existsSync(), isTrue);
    final content = guideFile.readAsStringSync();

    expect(content, contains('theme:surfaceContainerLowest'));
    expect(content, contains('theme:outlineVariant'));
    expect(content, contains('60 / 30 / 10'));
    expect(content, contains('autoSides'));
    expect(content, contains('expandSlots'));
    expect(content, contains('NIVEAU DE QUESTIONNEMENT'));
    expect(
      content,
      contains(
        'aucune contrainte interdisant de poser des questions selon l\'étape',
      ),
    );

    final jsonBlockMatch = RegExp(r'```json\s*([\s\S]*?)\s*```')
        .firstMatch(content);
    expect(jsonBlockMatch, isNotNull);
    final recipeJson = jsonBlockMatch!.group(1)!;
    final updated = AppearanceTransfer.applyVibe(Appearance(), recipeJson);
    expect(updated.layout('mainLayout').west, isTrue);
    expect(updated.layout('mainLayout').westSize, 320);
    expect(updated.layout('mainLayout').autoSides, isEmpty);
    expect(updated.style('background').padding, 0);
    expect(updated.style('card-detail').borderWidth, 1);
    expect(updated.style('list-items:item').states?.hasSelected, isTrue);
  });

  test('SCREEN_JSON_AI_GUIDE.md documents the mainLayout lateral autoSides prohibition and center expansion rule', () {
    final guideFile = File('SCREEN_JSON_AI_GUIDE.md').existsSync()
        ? File('SCREEN_JSON_AI_GUIDE.md')
        : File('packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md');
    expect(guideFile.existsSync(), isTrue);
    final content = guideFile.readAsStringSync();

    expect(
      content,
      contains("Règle absolue d'auto-dimensionnement sur `mainLayout`"),
    );
    expect(content, contains('westSize'));
    expect(content, contains('eastSize'));
    expect(content, contains('expandSlots: true'));
  });

  test('AI guides and system instruction enforce strict key/value SuperValue atomicity and forbid multiline textarea summaries', () {
    final jsonGuideFile = File('SCREEN_JSON_AI_GUIDE.md').existsSync()
        ? File('SCREEN_JSON_AI_GUIDE.md')
        : File('packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md');
    final designGuideFile = File('SCREEN_DESIGN_AI_GUIDE.md').existsSync()
        ? File('SCREEN_DESIGN_AI_GUIDE.md')
        : File('packages/super_container_layout/SCREEN_DESIGN_AI_GUIDE.md');
    expect(jsonGuideFile.existsSync(), isTrue);
    expect(designGuideFile.existsSync(), isTrue);

    final jsonGuide = jsonGuideFile.readAsStringSync();
    final designGuide = designGuideFile.readAsStringSync();
    const sysInstruction = VibeChatDialog.defaultSystemInstruction;

    for (final doc in [jsonGuide, designGuide, sysInstruction]) {
      expect(doc, contains('explanation'));
      expect(doc, contains('dynamicData'));
      expect(doc, contains('textarea'));
      expect(doc, contains('SuperTable'));
    }
    expect(sysInstruction, contains("Respect strict de la règle d'atomicité"));
    expect(
      sysInstruction,
      contains('préfère systématiquement 1 seul SuperValue avec "label"'),
    );
    expect(
      jsonGuide,
      contains('préférer 1 seul `SuperValue` avec `label` + valeur'),
    );
    expect(designGuide, contains('style de label fort custom'));
  });

  test('loadStaticGuide combines JSON guide, default Design System guide, and optional host overrides', () async {
    final fullBundle = _NamedGuideBundle({
      'SCREEN_JSON_AI_GUIDE.md': 'Grammaire JSON de base.',
      'REPOSITORY_JSON_AI_GUIDE.md': 'Modélisation des repositories JSON.',
      'SCREEN_DESIGN_AI_GUIDE.md': 'Design System moderne par défaut.',
    });
    final withRepoGuide = await VibeChatDialog.loadStaticGuide(fullBundle);
    expect(withRepoGuide, contains('Grammaire JSON de base.'));
    expect(withRepoGuide, contains('GUIDE DE MODÉLISATION DES REPOSITORIES :'));
    expect(withRepoGuide, contains('Modélisation des repositories JSON.'));
    expect(withRepoGuide, contains('GUIDE DE DESIGN SYSTEM :'));
    expect(withRepoGuide, contains('Design System moderne par défaut.'));

    // Repli gracieux lorsque REPOSITORY_JSON_AI_GUIDE.md est absent d'un bundle minimal
    final bundle = _NamedGuideBundle({
      'SCREEN_JSON_AI_GUIDE.md': 'Grammaire JSON de base.',
      'SCREEN_DESIGN_AI_GUIDE.md': 'Design System moderne par défaut.',
    });

    final combined = await VibeChatDialog.loadStaticGuide(bundle);
    expect(combined, contains('Grammaire JSON de base.'));
    expect(
      combined,
      isNot(contains('GUIDE DE MODÉLISATION DES REPOSITORIES :')),
    );
    expect(combined, contains('GUIDE DE DESIGN SYSTEM :'));
    expect(combined, contains('Design System moderne par défaut.'));

    final extended = await VibeChatDialog.loadStaticGuide(
      bundle,
      customDesignGuide: 'Utilise un rayon de 8px sur les cartes.',
    );
    expect(extended, contains('Design System moderne par défaut.'));
    expect(extended, contains('RÈGLES DE DESIGN SPÉCIFIQUES À L’APPLICATION'));
    expect(extended, contains('Utilise un rayon de 8px sur les cartes.'));

    final replaceBundle = _NamedGuideBundle({
      'SCREEN_JSON_AI_GUIDE.md': 'Grammaire JSON de base.',
      'SCREEN_DESIGN_AI_GUIDE.md': 'Design System moderne par défaut.',
    });
    final replaced = await VibeChatDialog.loadStaticGuide(
      replaceBundle,
      customDesignGuide: 'Charte SurfFile exclusive.',
      replaceDefaultDesignGuide: true,
    );
    expect(replaced, contains('Grammaire JSON de base.'));
    expect(replaced, isNot(contains('Design System moderne par défaut.')));
    expect(replaced, contains('GUIDE DE DESIGN SYSTEM DE L’APPLICATION :'));
    expect(replaced, contains('Charte SurfFile exclusive.'));
    expect(replaceBundle.loads, [
      'SCREEN_JSON_AI_GUIDE.md',
      'REPOSITORY_JSON_AI_GUIDE.md',
      'packages/super_container_layout/REPOSITORY_JSON_AI_GUIDE.md',
    ]);
  });

  Future<void> pumpRealAsync(
    WidgetTester tester, {
    bool Function()? until,
    int maxTicks = 120,
  }) async {
    await tester.runAsync(() async {
      for (var i = 0; i < maxTicks; i++) {
        await tester.pump();
        if (until != null && until()) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await tester.pump();
    });
  }

  testWidgets(
    'live SSE streaming creates repository and bound SuperListView together, rewrites alias to 32-hex ID, and supports async Undo/Redo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('vibe_repo_stream_'),
      ))!;
      final repoStore = JsonRepositoryStore(tempDir);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        repoStore.dispose();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final registry = Registry()..bootstrap();
      final store = _CountingAppearanceStore(Appearance());
      final mainLayout = registry.layoutController('mainLayout');
      addTearDown(registry.unbindAppearance);

      String? capturedTurnPrompt;
      StreamController<GeminiStreamEvent>? activeStreamController;
      late ValueNotifier<Appearance> appAppearance;
      late EditorHistoryController appHistory;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              appHistory = EditorHistoryScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayout,
                      builder: (_, cfg, _) => SuperLayout(config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 400,
                    height: 600,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        repositoryStore: repoStore,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) =>
                            Future.error('Should use streamGenerate'),
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) {
                              capturedTurnPrompt = prompt;
                              final controller =
                                  StreamController<GeminiStreamEvent>();
                              activeStreamController = controller;
                              return controller.stream;
                            },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          appearanceStore: store,
          registry: registry,
          repositoryStore: repoStore,
        ),
      );
      await pumpRealAsync(
        tester,
        until: () =>
            find.byKey(const ValueKey('vibe-chat-input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // Active le mode édition pour que EditorHistoryController enregistre l'historique Undo/Redo
      final editScopeContext = tester.element(
        find.byKey(const ValueKey('vibe-chat-input')),
      );
      StyleEditScope.controllerOf(editScopeContext)!.value = true;
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Crée un annuaire CRM Clients avec Alice Martin et Bruno Leroy.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await pumpRealAsync(tester, until: () => activeStreamController != null);
      expect(activeStreamController, isNotNull);
      final streamController = activeStreamController!;

      var accumulated = '';
      void emitDelta(String delta, {bool isDone = false}) {
        accumulated += delta;
        streamController.add(
          GeminiStreamEvent(
            deltaText: delta,
            accumulatedText: accumulated,
            isDone: isDone,
            usedContextCache: true,
          ),
        );
      }

      // Fragment 1 : message
      emitDelta('{"message":"Annuaire CRM prêt.",');
      await tester.pump();

      // Fragment 2 : repositories (création de crm_clients)
      emitDelta(
        '"repositories":{"crm_clients":{"name":"CRM Clients","mode":"merge",'
        '"data":{"clients":[{"nom":"Alice Martin"},{"nom":"Bruno Leroy"}]}}},',
      );
      await pumpRealAsync(tester, maxTicks: 25);

      // Fragment 3 : vibe (mainLayout + SuperListView liée à crm_clients:clients + SuperValue liée à clients[?].nom)
      emitDelta(
        '"vibe":{"components":{'
        '"mainLayout":{"type":"layout","zoneFlows":{"center":{"padding":16,"spacing":8,"expandSlots":true}},'
        '"placements":{"center":[{"id":"list-clients","type":"registry:ListView"}]}},'
        '"list-clients":{"type":"list","binding":"crm_clients:clients","itemExtent":56,"spacing":8,'
        '"template":{"placements":{"center":[{"id":"client-nom","type":"registry:Value"}]}}},'
        '"client-nom":{"type":"value","binding":"clients[?].nom"}'
        '}}}',
        isDone: true,
      );
      unawaited(streamController.close());
      await pumpRealAsync(
        tester,
        until: () =>
            find.text('Annuaire CRM prêt.').evaluate().isNotEmpty &&
            find.text('Alice Martin').evaluate().isNotEmpty &&
            find.text('Bruno Leroy').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(capturedTurnPrompt, isNotNull);
      expect(capturedTurnPrompt, contains('REPOSITORIES DISPONIBLES (JSON)'));
      expect(find.text('Annuaire CRM prêt.'), findsOneWidget);
      expect(find.text('Alice Martin'), findsOneWidget);
      expect(find.text('Bruno Leroy'), findsOneWidget);

      var catalogDone = false;
      List<JsonRepositoryEntry> catalog = const [];
      unawaited(
        repoStore.catalog().then((entries) {
          catalog = entries;
          catalogDone = true;
        }),
      );
      await pumpRealAsync(tester, until: () => catalogDone);
      expect(catalog, hasLength(1));
      expect(catalog.single.name, 'CRM Clients');
      final actualHexId = catalog.single.id;
      expect(actualHexId, matches(RegExp(r'^[0-9a-f]{32}$')));

      final listBinding = appAppearance.value
          .listComponent('list-clients')
          .binding;
      expect(listBinding, isNotNull);
      expect(listBinding!.repositoryId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(listBinding.repositoryId, actualHexId);
      expect(listBinding.path, 'clients');
      expect(appHistory.canUndo, isTrue);

      // Undo : supprime à la fois les composants UI et le repository créé
      var undoDone = false;
      unawaited(appHistory.undoAsync().whenComplete(() => undoDone = true));
      await pumpRealAsync(tester, until: () => undoDone);
      await tester.pumpAndSettle();

      expect(mainLayout.value.placedSlotIds, isEmpty);
      expect(appAppearance.value.components, isEmpty);
      expect(find.text('Alice Martin'), findsNothing);
      expect(find.text('Bruno Leroy'), findsNothing);

      var afterUndoCatalogDone = false;
      List<JsonRepositoryEntry> afterUndoCatalog = const [];
      unawaited(
        repoStore.catalog().then((entries) {
          afterUndoCatalog = entries;
          afterUndoCatalogDone = true;
        }),
      );
      await pumpRealAsync(tester, until: () => afterUndoCatalogDone);
      expect(afterUndoCatalog, isEmpty);
      expect(appHistory.canRedo, isTrue);

      // Redo : restaure l'UI et le repository avec ses données visibles
      var redoDone = false;
      unawaited(appHistory.redoAsync().whenComplete(() => redoDone = true));
      await pumpRealAsync(
        tester,
        until: () =>
            redoDone &&
            find.text('Alice Martin').evaluate().isNotEmpty &&
            find.text('Bruno Leroy').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      var restoredCatalogDone = false;
      List<JsonRepositoryEntry> restoredCatalog = const [];
      unawaited(
        repoStore.catalog().then((entries) {
          restoredCatalog = entries;
          restoredCatalogDone = true;
        }),
      );
      await pumpRealAsync(tester, until: () => restoredCatalogDone);
      expect(restoredCatalog, hasLength(1));
      expect(restoredCatalog.single.id, actualHexId);
      expect(find.text('Alice Martin'), findsOneWidget);
      expect(find.text('Bruno Leroy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'data-only response ("vibe": null) merges into existing RepositoryImpl and updates calculated attributes',
    (tester) async {
      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('vibe_repo_data_only_'),
      ))!;
      final repoStore = JsonRepositoryStore(tempDir);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        repoStore.dispose();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final appState = RepositoryImpl(
        id: 'app_state',
        json: {'compteur': 1, 'titre': 'Initial'},
      );
      appState.addCalculatedAttribute('doubleCompteur', (ctx) async {
        final count = await ctx.getNum('compteur') ?? 0;
        return count * 2;
      });
      repoStore.registerRepository(appState);

      var initialCalcDone = false;
      JsonAttributeValue? initialCalc;
      unawaited(
        repoStore
            .readAttribute(
              const JsonTextBinding(
                repositoryId: 'app_state',
                path: '@doubleCompteur',
              ),
            )
            .then((val) {
              initialCalc = val;
              initialCalcDone = true;
            }),
      );
      await pumpRealAsync(tester, until: () => initialCalcDone);
      expect(initialCalc?.value, 2);

      final appearance = ValueNotifier(Appearance());
      final editMode = ValueNotifier(true);
      final history = EditorHistoryController(
        appearance: appearance,
        editMode: editMode,
      );
      final registry = Registry()..bootstrap();
      registry.bindAppearance(appearance);
      addTearDown(registry.unbindAppearance);
      addTearDown(history.dispose);
      addTearDown(editMode.dispose);
      addTearDown(appearance.dispose);

      String? receivedPrompt;

      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: EditorHistoryScope(
            controller: history,
            child: JsonRepositoryScope(
              store: repoStore,
              child: AppearanceScope(
                controller: appearance,
                child: MaterialApp(
                  home: Scaffold(
                    body: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          receivedPrompt = prompt;
                          return jsonEncode({
                            'message': 'Compteur mis à jour.',
                            'repositories': {
                              'app_state': {
                                'mode': 'merge',
                                'data': {'compteur': 5},
                              },
                            },
                            'vibe': null,
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Passe le compteur à 5.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await pumpRealAsync(
        tester,
        until: () => find.text('Compteur mis à jour.').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(receivedPrompt, isNotNull);
      expect(receivedPrompt, contains('REPOSITORIES DISPONIBLES (JSON)'));
      expect(receivedPrompt, contains('app_state'));
      expect(receivedPrompt, contains('@doubleCompteur'));
      expect(find.text('Compteur mis à jour.'), findsOneWidget);
      expect(appearance.value.components, isEmpty);

      var updatedDocDone = false;
      Object? updatedDoc;
      unawaited(
        repoStore.readDocument('app_state').then((doc) {
          updatedDoc = doc;
          updatedDocDone = true;
        }),
      );
      await pumpRealAsync(tester, until: () => updatedDocDone);
      expect(updatedDoc, {'compteur': 5, 'titre': 'Initial'});

      var updatedCalcDone = false;
      JsonAttributeValue? updatedCalc;
      unawaited(
        repoStore
            .readAttribute(
              const JsonTextBinding(
                repositoryId: 'app_state',
                path: '@doubleCompteur',
              ),
            )
            .then((val) {
              updatedCalc = val;
              updatedCalcDone = true;
            }),
      );
      await pumpRealAsync(tester, until: () => updatedCalcDone);
      expect(updatedCalc?.value, 10);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'auto-correction rolls back newly created repository on error and keeps only corrected repository',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('vibe_repo_rollback_'),
      ))!;
      final repoStore = JsonRepositoryStore(tempDir);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        repoStore.dispose();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final registry = Registry()..bootstrap();
      final store = _CountingAppearanceStore(Appearance());
      final mainLayout = registry.layoutController('mainLayout');
      addTearDown(registry.unbindAppearance);

      var attempt = 0;
      final prompts = <String>[];
      late ValueNotifier<Appearance> appAppearance;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayout,
                      builder: (_, cfg, _) => SuperLayout(config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 400,
                    height: 600,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        repositoryStore: repoStore,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          attempt++;
                          prompts.add(prompt);
                          if (attempt == 1) {
                            // Tentative 1 : crée "temp_repo" sur disque mais échoue sur un composant détaché dans "vibe"
                            return jsonEncode({
                              'message': 'Essai initial invalide.',
                              'repositories': {
                                'temp_repo': {
                                  'name': 'Temp Repo',
                                  'mode': 'merge',
                                  'data': {'statut': 'Brouillon temporaire'},
                                },
                              },
                              'vibe': {
                                'components': {
                                  'orphan-status': {
                                    'type': 'value',
                                    'binding': 'temp_repo:statut',
                                  },
                                },
                              },
                            });
                          }
                          // Tentative 2 : réponse corrigée valide créant "clean_repo" et rattachant le composant à mainLayout
                          return jsonEncode({
                            'message': 'Écran corrigé et prêt.',
                            'repositories': {
                              'clean_repo': {
                                'name': 'Clean Repo',
                                'mode': 'merge',
                                'data': {'statut': 'Donnée validée'},
                              },
                            },
                            'vibe': {
                              'components': {
                                'mainLayout': {
                                  'type': 'layout',
                                  'placements': {
                                    'center': [
                                      {
                                        'id': 'clean-status',
                                        'type': 'registry:Value',
                                      },
                                    ],
                                  },
                                },
                                'clean-status': {
                                  'type': 'value',
                                  'binding': 'clean_repo:statut',
                                },
                              },
                            },
                          });
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          appearanceStore: store,
          registry: registry,
          repositoryStore: repoStore,
        ),
      );
      await pumpRealAsync(
        tester,
        until: () =>
            find.byKey(const ValueKey('vibe-chat-input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Affiche le statut depuis un nouveau repository.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await pumpRealAsync(
        tester,
        until: () =>
            find.text('Écran corrigé et prêt.').evaluate().isNotEmpty &&
            find.text('Donnée validée').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(attempt, 2);
      expect(prompts, hasLength(2));
      expect(prompts[1], contains('CORRECTION REQUISE'));
      expect(prompts[1], contains('orphan-status'));

      // "temp_repo" ("Temp Repo") a été intégralement annulé ; seul "clean_repo" ("Clean Repo") subsiste
      var catalogDone = false;
      List<JsonRepositoryEntry> catalog = const [];
      unawaited(
        repoStore.catalog().then((entries) {
          catalog = entries;
          catalogDone = true;
        }),
      );
      await pumpRealAsync(tester, until: () => catalogDone);
      expect(catalog, hasLength(1));
      expect(catalog.single.name, 'Clean Repo');
      expect(catalog.single.id, matches(RegExp(r'^[0-9a-f]{32}$')));

      final jsonFiles = (await tester.runAsync(() async {
        return tempDir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where(
              (name) => name.endsWith('.json') || name.endsWith('.json.id'),
            )
            .toList();
      }))!;
      expect(
        jsonFiles,
        unorderedEquals(['Clean Repo.json', 'Clean Repo.json.id']),
      );

      expect(find.text('Écran corrigé et prêt.'), findsOneWidget);
      expect(find.text('Donnée validée'), findsOneWidget);
      expect(find.text('Brouillon temporaire'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live streaming highlights active streaming key, pulses added/modified components for 500 ms without pulsing parent layout, and clears on settle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(VibeWorkHighlightController.instance.clearAll);

      final initialAppearance = Appearance(
        components: {
          'mainLayout': SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: const ['kpi-existing'],
            },
            slotTypes: const {'kpi-existing': 'registry:Value'},
          ),
          'kpi-existing': const SuperValueConfig(label: 'Avant'),
        },
      );
      final store = _MemoryAppearanceStore(initialAppearance);
      final registry = Registry()..bootstrap();
      late ValueNotifier<Appearance> appAppearance;

      late StreamController<GeminiStreamEvent> streamCtrl;
      final mainLayoutController = registry.layoutController('mainLayout');
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayoutController,
                      builder: (_, cfg, _) => SuperLayout(config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 380,
                    height: 600,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) =>
                            Future.error('Should use streamGenerate'),
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) {
                              streamCtrl =
                                  StreamController<GeminiStreamEvent>();
                              return streamCtrl.stream;
                            },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(router: router, appearanceStore: store, registry: registry),
      );
      await tester.pumpAndSettle();
      expect(find.text('Avant'), findsOneWidget);
      expect(VibeWorkHighlightController.instance.hasActiveHighlights, isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Mets à jour kpi-existing et ajoute kpi-new.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();

      // Chunk 1 : kpi-existing commence à streamer (objet encore ouvert).
      const part1 =
          '{"message":"Mise à jour live","vibe":{"components":{'
          '"kpi-existing":{"type":"value","text":"En cours';
      streamCtrl.add(
        const GeminiStreamEvent(
          deltaText: part1,
          accumulatedText: part1,
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      expect(VibeWorkHighlightController.instance.streamingIds, {
        'kpi-existing',
      });
      expect(
        VibeWorkHighlightController.instance.stateFor('kpi-existing')?.kind,
        VibeWorkKind.streaming,
      );

      // Chunk 2 : kpi-existing se ferme (modified), mainLayout ajoute kpi-new (parent exclu),
      // et kpi-new se ferme (added).
      const part2 =
          ' — Après"},'
          '"mainLayout":{"type":"layout","placements":{"center":[{"id":"kpi-existing","type":"registry:Value"},{"id":"kpi-new","type":"registry:Value"}]}},'
          '"kpi-new":{"type":"value","text":"Nouveau"}';
      streamCtrl.add(
        const GeminiStreamEvent(
          deltaText: part2,
          accumulatedText: '$part1$part2',
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(VibeWorkHighlightController.instance.streamingIds, isEmpty);
      expect(
        VibeWorkHighlightController.instance.pulsedIds,
        containsAll(['kpi-existing', 'kpi-new']),
      );
      expect(
        VibeWorkHighlightController.instance.pulsedIds,
        isNot(contains('mainLayout')),
      );
      expect(
        VibeWorkHighlightController.instance.stateFor('kpi-existing')?.kind,
        VibeWorkKind.modified,
      );
      expect(
        VibeWorkHighlightController.instance.stateFor('kpi-new')?.kind,
        VibeWorkKind.added,
      );
      expect(find.text('En cours — Après'), findsOneWidget);
      expect(find.text('Nouveau'), findsOneWidget);

      // Fin du flux -> après 500 ms, tout converge proprement.
      const part3 = '}}}';
      streamCtrl.add(
        const GeminiStreamEvent(
          deltaText: part3,
          accumulatedText: '$part1$part2$part3',
          isDone: true,
          usedContextCache: true,
        ),
      );
      await streamCtrl.close();
      await tester.pumpAndSettle();

      expect(VibeWorkHighlightController.instance.hasActiveHighlights, isFalse);
      expect(find.text('Mise à jour live'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live streaming switches SuperTab automatically to show new or updated tab content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(VibeWorkHighlightController.instance.clearAll);

      final initialAppearance = Appearance(
        components: {
          'main-tab': SuperTabConfig(
            placements: {
              SuperTabConfig.tabsZone: const ['tab_overview', 'tab_details'],
              SuperTabConfig.contentZoneFor('tab_overview'): const [
                'overview_val',
              ],
              SuperTabConfig.contentZoneFor('tab_details'): const [
                'details_val',
              ],
            },
            slotTypes: const {
              'tab_overview': 'registry:Action',
              'tab_details': 'registry:Action',
              'overview_val': 'registry:Value',
              'details_val': 'registry:Value',
            },
          ),
          'tab_overview': const SuperActionConfig(label: 'Aperçu'),
          'tab_details': const SuperActionConfig(label: 'Détails'),
          'overview_val': const SuperValueConfig(label: 'Vue Aperçu'),
          'details_val': const SuperValueConfig(label: 'Vue Détails'),
        },
      );
      final store = _MemoryAppearanceStore(initialAppearance);
      final registry = Registry()..bootstrap();
      late ValueNotifier<Appearance> appAppearance;
      late StreamController<GeminiStreamEvent> streamCtrl;
      final tabController = registry.tabController('main-tab');

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperTabConfig>(
                      valueListenable: tabController,
                      builder: (_, cfg, _) =>
                          SuperTab(id: 'main-tab', config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 380,
                    height: 600,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) =>
                            Future.error('Should use streamGenerate'),
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) {
                              streamCtrl =
                                  StreamController<GeminiStreamEvent>();
                              return streamCtrl.stream;
                            },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(router: router, appearanceStore: store, registry: registry),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vue Aperçu'), findsOneWidget);
      expect(find.text('Vue Détails'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Ajoute une info dans l’onglet Détails.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();

      // L'IA place un nouvel élément dans l'onglet Détails puis le streame.
      const part1 =
          '{"message":"Onglet Détails enrichi","vibe":{"components":{'
          '"main-tab":{"type":"tab","placements":{'
          '"tabs":[{"id":"tab_overview","type":"registry:Action"},{"id":"tab_details","type":"registry:Action"}],'
          '"content:tab_overview":[{"id":"overview_val","type":"registry:Value"}],'
          '"content:tab_details":[{"id":"details_val","type":"registry:Value"},{"id":"details_new","type":"registry:Value"}]'
          '}},'
          '"details_new":{"type":"value","text":"Nouveau Détail"}';
      streamCtrl.add(
        const GeminiStreamEvent(
          deltaText: part1,
          accumulatedText: part1,
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // SuperTab a basculé automatiquement sur l'onglet Détails pour montrer le nouvel élément.
      expect(find.text('Vue Détails'), findsOneWidget);
      expect(find.text('Nouveau Détail'), findsOneWidget);

      const part2 = '}}}';
      streamCtrl.add(
        const GeminiStreamEvent(
          deltaText: part2,
          accumulatedText: '$part1$part2',
          isDone: true,
          usedContextCache: true,
        ),
      );
      await streamCtrl.close();
      await tester.pumpAndSettle();

      expect(find.text('Nouveau Détail'), findsOneWidget);
      expect(VibeWorkHighlightController.instance.hasActiveHighlights, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming a Card with multiple children in child region does not crash preview and retries with CORRECTION REQUISE',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final initialAppearance = Appearance(
        components: {
          'mainLayout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['card-1'],
            },
            slotTypes: {'card-1': 'registry:Card'},
          ),
        },
      );
      final store = _MemoryAppearanceStore(initialAppearance);
      final registry = Registry()..bootstrap();
      final mainLayoutController = registry.layoutController('mainLayout');
      late ValueNotifier<Appearance> appAppearance;

      final prompts = <String>[];
      var attempt = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayoutController,
                      builder: (_, cfg, _) => SuperLayout(config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    height: 600,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) =>
                            Future.error('Should use streamGenerate'),
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) async* {
                              prompts.add(prompt);
                              attempt++;
                              if (attempt == 1) {
                                const part1 =
                                    '{"message":"Carte créée","vibe":{"components":{'
                                    '"card-1":{"type":"native","placements":{"child":['
                                    '{"id":"val-1","type":"registry:Value"},'
                                    '{"id":"val-2","type":"registry:Value"}'
                                    ']}},'
                                    '"val-1":{"type":"value","text":"Premier"},'
                                    '"val-2":{"type":"value","text":"Second"}';
                                yield const GeminiStreamEvent(
                                  deltaText: part1,
                                  accumulatedText: part1,
                                  isDone: false,
                                  usedContextCache: true,
                                );
                                const part2 = '}}}';
                                yield const GeminiStreamEvent(
                                  deltaText: part2,
                                  accumulatedText: '$part1$part2',
                                  isDone: true,
                                  usedContextCache: true,
                                );
                              } else {
                                final fixed = jsonEncode({
                                  'message': 'Carte corrigée.',
                                  'vibe': {
                                    'components': {
                                      'card-1': {
                                        'type': 'native',
                                        'placements': {
                                          'child': [
                                            {
                                              'id': 'card-layout',
                                              'type': 'registry:Layout',
                                            },
                                          ],
                                        },
                                      },
                                      'card-layout': {
                                        'type': 'layout',
                                        'placements': {
                                          'center': [
                                            {
                                              'id': 'val-1',
                                              'type': 'registry:Value',
                                            },
                                            {
                                              'id': 'val-2',
                                              'type': 'registry:Value',
                                            },
                                          ],
                                        },
                                      },
                                      'val-1': {
                                        'type': 'value',
                                        'text': 'Premier',
                                      },
                                      'val-2': {
                                        'type': 'value',
                                        'text': 'Second',
                                      },
                                    },
                                  },
                                });
                                yield GeminiStreamEvent(
                                  deltaText: fixed,
                                  accumulatedText: fixed,
                                  isDone: true,
                                  usedContextCache: true,
                                );
                              }
                            },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(router: router, appearanceStore: store, registry: registry),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Mets deux textes dans card-1.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(attempt, 2);
      expect(prompts, hasLength(2));
      expect(prompts[1], contains('CORRECTION REQUISE'));
      expect(prompts[1], contains('card-1'));
      expect(prompts[1], contains('"child"'));
      expect(find.text('Carte corrigée.'), findsOneWidget);
      expect(find.text('Premier'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(appAppearance.value.nativeComponent('card-1').slotsOf('child'), [
        'card-layout',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  test('VibeAudioWavEncoder and VibeSpeechTextInsertion encode WAV, compute RMS, and insert transcripts cleanly', () {
    final pcm = Uint8List(8);
    final bd = ByteData.sublistView(pcm);
    bd.setInt16(0, 16384, Endian.little);
    bd.setInt16(2, -16384, Endian.little);
    bd.setInt16(4, 16384, Endian.little);
    bd.setInt16(6, -16384, Endian.little);

    final rms = VibeAudioWavEncoder.computeNormalizedRms(pcm);
    expect(rms, closeTo(0.5, 0.01));

    final wav = VibeAudioWavEncoder.encodePcm16MonoToWav(
      pcm,
      sampleRate: 16000,
    );
    expect(wav.length, 44 + 8);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
    expect(ascii.decode(wav.sublist(36, 40)), 'data');

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    VibeSpeechTextInsertion.insertTranscript(controller, 'Ajoute un graphique');
    expect(controller.text, 'Ajoute un graphique');

    VibeSpeechTextInsertion.insertTranscript(controller, 'des ventes');
    expect(controller.text, 'Ajoute un graphique des ventes');

    controller.selection = const TextSelection.collapsed(offset: 6);
    VibeSpeechTextInsertion.insertTranscript(controller, 'vite');
    expect(controller.text, 'Ajoute vite un graphique des ventes');
  });

  testWidgets(
    'microphone button in VibeChatDialog input bar and VibeAskUserCard text fields supports auto-stop on silence and second-click stop',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final transcriber = _FakeVibeSpeechTranscriber();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                speechTranscriber: transcriber,
                onClose: () {},
                onDrag: (_) {},
                generate: (_) async => jsonEncode({
                  'message': 'Précise ta demande :',
                  'askUser': {
                    'questions': [
                      {
                        'id': 'style',
                        'title': 'Style visuel',
                        'type': 'single',
                        'options': ['Moderne', ' Compact'],
                        'default': 'Moderne',
                      },
                      {
                        'id': 'subtitle',
                        'title': 'Sous-titre de la page',
                        'type': 'text',
                        'default': '',
                      },
                    ],
                  },
                  'vibe': null,
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final micButton = find.byKey(const ValueKey('vibe-chat-mic'));
      expect(micButton, findsOneWidget);
      expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);

      // 1) Clic 1 sur le micro : démarre l'écoute, puis s'arrête automatiquement après un silence.
      await tester.tap(micButton);
      await tester.pump();
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      transcriber.activeSession!.completeWithTranscript(
        'Crée un écran commercial',
      );
      await tester.pumpAndSettle();

      final inputField = tester.widget<TextField>(
        find.byKey(const ValueKey('vibe-chat-input')),
      );
      expect(inputField.controller!.text, 'Crée un écran commercial');

      // 2) Clic 1 puis 2e clic manuel sur le micro : arrête l'écoute et concatène la suite.
      transcriber.nextManualStopTranscript = 'avec indicateurs mensuels.';
      await tester.tap(micButton);
      await tester.pump();
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      await tester.tap(micButton);
      await tester.pumpAndSettle();
      expect(
        inputField.controller!.text,
        'Crée un écran commercial avec indicateurs mensuels.',
      );

      // Envoie le message pour afficher la carte askUser.
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('vibe-ask-user-card')), findsOneWidget);

      // 3) Dictée vocale dans le champ texte d'une question askUser.
      final textMic = find.byKey(const ValueKey('vibe-ask-text-mic-subtitle'));
      expect(textMic, findsOneWidget);
      await tester.tap(textMic);
      await tester.pump();
      transcriber.activeSession!.completeWithTranscript(
        'Suivi trimestriel B2B',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('vibe-ask-text-subtitle')),
            )
            .controller!
            .text,
        'Suivi trimestriel B2B',
      );

      // 4) Dictée vocale dans le champ « Autre… » d'une question à choix.
      await tester.tap(find.byKey(const ValueKey('vibe-ask-other-chip-style')));
      await tester.pump();
      final otherMic = find.byKey(const ValueKey('vibe-ask-other-mic-style'));
      expect(otherMic, findsOneWidget);
      await tester.tap(otherMic);
      await tester.pump();
      transcriber.activeSession!.completeWithTranscript('Style néomorphique');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('vibe-ask-other-input-style')),
            )
            .controller!
            .text,
        'Style néomorphique',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepts fixed side sizes above 400px (e.g. westSize: 600) and repairs a missing trailing closing brace without retry',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      var callCount = 0;
      final validFull = jsonEncode({
        'message': 'Cartes héro créées.',
        'vibe': {
          'components': {
            'mainLayout': {
              'type': 'layout',
              'placements': {
                'center': [
                  {'id': 'hero-cards', 'type': 'registry:Layout'},
                ],
              },
            },
            'hero-cards': {
              'type': 'layout',
              'west': true,
              'westSize': 600,
              'autoSides': <String>[],
              'zoneFlows': {
                'west': {'expandSlots': true, 'padding': 8},
                'center': {'expandSlots': true, 'padding': 8},
              },
              'slotLabels': {
                'card-solde': 'Vérification de solde',
                'card-offre': 'Offrir une carte',
              },
              'placements': {
                'west': [
                  {'id': 'card-solde', 'type': 'registry:Value'},
                ],
                'center': [
                  {'id': 'card-offre', 'type': 'registry:Value'},
                ],
              },
            },
            'card-solde': {'type': 'value', 'text': 'Solde'},
            'card-offre': {'type': 'value', 'text': 'Offrir'},
          },
          'usages': {
            'card-solde': {
              'kind': 'explanation',
              'translationKey': 'bannerDesc',
            },
          },
        },
      });
      // Simule l'oubli par le LLM de la toute dernière accolade fermante '}' :
      final missingOuterBrace = validFull.substring(0, validFull.length - 1);

      await pumpChat(tester, appearance, registry, (_) async {
        callCount++;
        return missingOuterBrace;
      });

      await send(tester);

      expect(callCount, 1);
      expect(find.text('Cartes héro créées.'), findsOneWidget);
      expect(appearance.value.layout('hero-cards').westSize, 600);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retries past attempt 2 up to 4 attempts when earlier attempts fail with truncation then validation error',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final prompts = <String>[];
      await pumpChat(tester, appearance, registry, (prompt) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          // Tentative 1 : JSON réellement tronqué en pleine chaîne (non réparable).
          return '{"message":"MARQUEUR_ANCIENNE_REPONSE_TENTATIVE_1___________________________fin_tronquee';
        }
        if (prompts.length == 2) {
          // Tentative 2 : JSON complet mais composant inconnu (FormatException).
          return '{"message":"Erreur schéma","vibe":{"components":{"bad":{"type":"unknown_type"}}}}';
        }
        // Tentative 3 : patch valide !
        return jsonEncode({
          'message': 'Corrigé à la tentative 3.',
          'vibe': _fileListPatch('mainLayout'),
        });
      });

      await send(tester);

      expect(prompts, hasLength(3));
      expect(prompts[1], contains('CORRECTION REQUISE'));
      expect(prompts[2], contains('CORRECTION REQUISE'));
      expect(prompts[2], contains('Tentative 1'));
      expect(prompts[2], contains('Tentative 2'));
      expect(prompts[2], contains('unknown_type'));
      // Vérifie que la réponse invalide de la tentative 1 n'est pas réempilée dans la tentative 3.
      expect(
        prompts[2],
        isNot(contains('MARQUEUR_ANCIENNE_REPONSE_TENTATIVE_1')),
      );
      expect(find.text('Corrigé à la tentative 3.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live streaming keeps rendering valid components past a broken entry, preserves the checkpoint on screen, and applies a delta-only retry without regenerating the page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = _CountingAppearanceStore(Appearance());
      final registry = Registry()..bootstrap();
      final mainLayout = registry.layoutController('mainLayout');
      addTearDown(registry.unbindAppearance);
      late ValueNotifier<Appearance> appAppearance;
      late EditorHistoryController appHistory;

      var attemptCount = 0;
      final prompts = <String>[];
      late StreamController<GeminiStreamEvent> attempt1Stream;
      late StreamController<GeminiStreamEvent> attempt2Stream;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              appHistory = EditorHistoryScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayout,
                      builder: (_, cfg, _) => SuperLayout(config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    height: 600,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) =>
                            Future.error('Should use streamGenerate'),
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) {
                              prompts.add(prompt);
                              attemptCount++;
                              if (attemptCount == 1) {
                                attempt1Stream =
                                    StreamController<GeminiStreamEvent>();
                                return attempt1Stream.stream;
                              }
                              attempt2Stream =
                                  StreamController<GeminiStreamEvent>();
                              return attempt2Stream.stream;
                            },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          appearanceStore: store,
          registry: registry,
        ),
      );
      await tester.pumpAndSettle();

      final editScopeContext = tester.element(
        find.byKey(const ValueKey('vibe-chat-input')),
      );
      StyleEditScope.controllerOf(editScopeContext)!.value = true;
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Construis la page avec en-tête, héro et pied de page.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();

      // Palier 1 : mainLayout + header valide + hero-broken invalide (axe inconnu)
      const chunk1 =
          '{"message":"Construction","vibe":{"components":{'
          '"mainLayout":{"type":"layout","north":true,"south":true,'
          '"placements":{'
          '"north":[{"id":"header-title","type":"registry:Value"}],'
          '"center":[{"id":"hero-broken","type":"registry:Layout"}],'
          '"south":[{"id":"footer-note","type":"registry:Value"}]'
          '}},'
          '"header-title":{"type":"value","text":"En-tête Live"},'
          '"hero-broken":{"type":"layout","zoneAxes":{"center":"diagonal"}},';
      attempt1Stream.add(
        const GeminiStreamEvent(
          deltaText: chunk1,
          accumulatedText: chunk1,
          isDone: false,
          usedContextCache: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      // Malgré l'erreur dans hero-broken, header-title est déjà visible en live !
      expect(find.text('En-tête Live'), findsOneWidget);

      // Palier 2 : les composants suivants continuent de s'afficher en direct + styles + enfant de hero-broken !
      const chunk2 =
          '"hero-child":{"type":"value","text":"Contenu Héro Préservé"},'
          '"footer-note":{"type":"value","text":"Pied Live"}'
          '},"styles":{"header-title":{"radius":12}}}}';
      attempt1Stream.add(
        const GeminiStreamEvent(
          deltaText: chunk2,
          accumulatedText: '$chunk1$chunk2',
          isDone: true,
          usedContextCache: true,
        ),
      );
      await attempt1Stream.close();
      await tester.pump();
      await tester.pump();

      // La tentative 2 démarre SANS effacer l'aperçu des composants valides à l'écran !
      expect(attemptCount, 2);
      expect(find.text('En-tête Live'), findsOneWidget);
      expect(find.text('Pied Live'), findsOneWidget);
      expect(store.saveCalls, 0);

      // Le prompt de la tentative 2 est en mode delta et contient déjà header-title, footer-note et hero-child dans l'ÉTAT ACTUEL :
      expect(prompts[1], contains('MODE DELTA INCRÉMENTAL'));
      expect(prompts[1], contains('hero-broken'));
      expect(prompts[1], contains('"header-title"'));
      expect(prompts[1], contains('"hero-child"'));

      // Tentative 2 : l'IA renvoie UNIQUEMENT le delta de hero-broken (sans réémettre mainLayout, header-title, footer-note ni hero-child !)
      final deltaFix = jsonEncode({
        'message': 'Page complète.',
        'vibe': {
          'components': {
            'hero-broken': {
              'type': 'layout',
              'zoneAxes': {'center': 'row'},
              'placements': {
                'center': [
                  {'id': 'hero-child', 'type': 'registry:Value'},
                ],
              },
            },
          },
        },
      });
      attempt2Stream.add(
        GeminiStreamEvent(
          deltaText: deltaFix,
          accumulatedText: deltaFix,
          isDone: true,
          usedContextCache: true,
        ),
      );
      await attempt2Stream.close();
      await tester.pumpAndSettle();

      expect(find.text('Page complète.'), findsOneWidget);
      expect(find.text('En-tête Live'), findsOneWidget);
      expect(find.text('Contenu Héro Préservé'), findsOneWidget);
      expect(find.text('Pied Live'), findsOneWidget);
      expect(appAppearance.value.style('header-title').radius, 12);
      expect(store.saveCalls, 1);

      // Un seul Undo restaure tout le tour d'un bloc :
      expect(appHistory.canUndo, isTrue);
      appHistory.undo();
      await tester.pumpAndSettle();
      expect(appAppearance.value.components, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'truncated SSE stream salvages already streamed components and completes via delta continuation without redoing the whole page',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      final prompts = <String>[];
      var attempt = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: _GuideBundle(),
              child: VibeChatDialog(
                controller: appearance,
                registry: registry,
                codec: const AppearanceCodec(),
                initialQuestioningLevel: VibeQuestioningLevel.none,
                onClose: () {},
                onDrag: (_) {},
                generate: (_) => Future.error('Should use streamGenerate'),
                streamGenerate:
                    (
                      prompt, {
                      systemInstruction,
                      staticGuide,
                      attachments = const [],
                      speedMode = VibeAiSpeedMode.fast,
                    }) async* {
                      prompts.add(prompt);
                      attempt++;
                      if (attempt == 1) {
                        // Flux coupé au milieu de kpi-2 après avoir déjà fermé mainLayout et kpi-1 !
                        const truncated =
                            '{"message":"Tableau","vibe":{"components":{'
                            '"mainLayout":{"type":"layout","placements":{"center":['
                            '{"id":"kpi-1","type":"registry:Value"},'
                            '{"id":"kpi-2","type":"registry:Value"}'
                            ']}},'
                            '"kpi-1":{"type":"value","text":"CA : 240 k€"},'
                            '"kpi-2":{"type":"value","text":"Marge : 32';
                        yield const GeminiStreamEvent(
                          deltaText: truncated,
                          accumulatedText: truncated,
                          isDone: true,
                          usedContextCache: true,
                        );
                      } else {
                        // Tentative 2 : n'émet QUE kpi-2 !
                        final tailOnly = jsonEncode({
                          'message': 'Tableau complété.',
                          'vibe': {
                            'components': {
                              'kpi-2': {'type': 'value', 'text': 'Marge : 32 %'},
                            },
                          },
                        });
                        yield GeminiStreamEvent(
                          deltaText: tailOnly,
                          accumulatedText: tailOnly,
                          isDone: true,
                          usedContextCache: true,
                        );
                      }
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await send(tester);

      expect(attempt, 2);
      expect(prompts[1], contains('MODE DELTA INCRÉMENTAL'));
      expect(prompts[1], contains('"kpi-1"'));
      expect(prompts[1], contains('"kpi-2"'));
      expect(appearance.value.valueComponent('kpi-1').initialText, 'CA : 240 k€');
      expect(
        appearance.value.valueComponent('kpi-2').initialText,
        'Marge : 32 %',
      );
      expect(find.text('Tableau complété.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  group('Mode Reproduire à l’identique — Plan & Lots automatiques', () {
    test('VibeExecutionPlan analyse le JSON et déduplique les IDs de lots', () {
      final plan = VibeExecutionPlan.tryFromJson({
        'title': 'Landing page test',
        'lots': [
          {'id': 'lot-1', 'title': 'Header', 'description': 'Logo et menu'},
          {'id': 'lot-1', 'title': 'Hero', 'description': 'Titre et CTA'},
        ],
      });
      expect(plan, isNotNull);
      expect(plan!.title, 'Landing page test');
      expect(plan.lots.map((l) => l.id).toList(), ['lot-1', 'lot-1_2']);
      expect(plan.status, VibePlanStatus.awaitingConfirmation);
      expect(plan.formatLotContextPrompt(1), contains('>>> À EXÉCUTER MAINTENANT'));
    });

    test('VibeIncrementalStreamParser détecte hasPlanObject en streaming', () {
      final parser = VibeIncrementalStreamParser();
      final snap = parser.addChunk(
        '{"message":"Plan prêt.","plan":{"title":"P","lots":[]},"vibe":null}',
      );
      expect(snap.isMessageComplete, isTrue);
      expect(snap.hasPlanObject, isTrue);
      expect(snap.hasVibeObject, isFalse);
      expect(snap.hasAskUserObject, isFalse);
    });

    testWidgets(
      'activer À l’identique verrouille Questions sur Aucun, masque Design System et injecte les directives exactes',
      (tester) async {
        final appearance = ValueNotifier(Appearance());
        addTearDown(appearance.dispose);
        final prompts = <String>[];

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(
                body: DefaultAssetBundle(
                  bundle: _GuideBundle(),
                  child: VibeChatDialog(
                    controller: appearance,
                    codec: const AppearanceCodec(),
                    initialQuestioningLevel: VibeQuestioningLevel.balanced,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (prompt) async {
                      prompts.add(prompt);
                      return jsonEncode({
                        'message': 'Plan généré.',
                        'plan': {
                          'title': 'Page test',
                          'lots': [
                            {'id': 'lot-1', 'title': 'Header'},
                          ],
                        },
                        'vibe': null,
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('vibe-chat-design-system-button')), findsOneWidget);
        expect(find.text('Équilibré'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('vibe-chat-reproduce-exact')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('vibe-chat-exact-design-notice')), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-chat-design-system-button')), findsNothing);
        expect(find.text('Aucun'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Reproduis cette page',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(prompts, hasLength(1));
        expect(prompts.single, contains('MODE « REPRODUIRE À L’IDENTIQUE »'));
        expect(prompts.single, contains('PHASE 1 — PLANIFICATION EN LOTS'));
        expect(find.byKey(const ValueKey('vibe-plan-card')), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-plan-start')), findsOneWidget);

        // Désactiver le mode restaure le niveau de questionnement précédent.
        await tester.tap(find.byKey(const ValueKey('vibe-chat-reproduce-exact')));
        await tester.pumpAndSettle();
        expect(find.text('Équilibré'), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-chat-design-system-button')), findsOneWidget);
      },
    );

    testWidgets(
      'confirme le plan, exécute automatiquement tous les lots avec pièces jointes et regroupe en 1 Undo',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        final editMode = ValueNotifier(true);
        final history = EditorHistoryController(
          appearance: appearance,
          editMode: editMode,
        );
        addTearDown(history.dispose);
        addTearDown(editMode.dispose);
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final capturedPrompts = <String>[];
        final capturedAttachments = <List<VibeChatAttachment>>[];
        var callCount = 0;

        final mdAttachment = VibeChatAttachment.text(
          name: 'blueprint.md',
          content: '# Blueprint\nhttps://example.com/logo.svg',
        );

        await tester.pumpWidget(
          StyleEditScope(
            controller: editMode,
            child: EditorHistoryScope(
              controller: history,
              child: AppearanceScope(
                controller: appearance,
                child: MaterialApp(
                  home: Scaffold(
                    body: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialReproduceExactMode: true,
                        pickAttachments: () async => [mdAttachment],
                        onClose: () {},
                        onDrag: (_) {},
                        streamGenerate: (
                          prompt, {
                          systemInstruction,
                          staticGuide,
                          attachments = const [],
                          speedMode = VibeAiSpeedMode.fast,
                        }) async* {
                          callCount++;
                          capturedPrompts.add(prompt);
                          capturedAttachments.add(attachments);
                          late final String payload;
                          if (callCount == 1) {
                            payload = jsonEncode({
                              'message': 'Voici le plan en 2 lots.',
                              'plan': {
                                'title': 'Reproduction Blueprint',
                                'lots': [
                                  {
                                    'id': 'lot-1',
                                    'title': 'Lot Header',
                                    'description': 'Logo et titre',
                                  },
                                  {
                                    'id': 'lot-2',
                                    'title': 'Lot Hero',
                                    'description': 'Sous-titre',
                                  },
                                ],
                              },
                              'vibe': null,
                            });
                          } else if (callCount == 2) {
                            payload = jsonEncode({
                              'message': 'Lot 1 appliqué.',
                              'vibe': {
                                'components': {
                                  'mainLayout': {
                                    'type': 'layout',
                                    'slotLabels': {'hero-title': 'Titre'},
                                    'placements': {
                                      'center': [
                                        {
                                          'id': 'hero-title',
                                          'type': 'registry:Value',
                                        },
                                      ],
                                    },
                                  },
                                  'hero-title': {
                                    'type': 'value',
                                    'text': 'Bienvenue',
                                  },
                                },
                                'usages': {
                                  'hero-title': {
                                    'kind': 'explanation',
                                    'translationKey': 'heroTitle',
                                  },
                                },
                              },
                            });
                          } else {
                            payload = jsonEncode({
                              'message': 'Lot 2 appliqué.',
                              'vibe': {
                                'components': {
                                  'mainLayout': {
                                    'type': 'layout',
                                    'slotLabels': {
                                      'hero-title': 'Titre',
                                      'hero-sub': 'Sous-titre',
                                    },
                                    'placements': {
                                      'center': [
                                        {
                                          'id': 'hero-title',
                                          'type': 'registry:Value',
                                        },
                                        {
                                          'id': 'hero-sub',
                                          'type': 'registry:Value',
                                        },
                                      ],
                                    },
                                  },
                                  'hero-sub': {
                                    'type': 'value',
                                    'text': 'Description exacte',
                                  },
                                },
                                'usages': {
                                  'hero-sub': {
                                    'kind': 'explanation',
                                    'translationKey': 'heroSub',
                                  },
                                },
                              },
                            });
                          }
                          yield GeminiStreamEvent(
                            deltaText: payload,
                            accumulatedText: payload,
                            isDone: true,
                            usedContextCache: true,
                          );
                        },
                        generate: (_) async => '',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('vibe-chat-attach')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Reproduis la page',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        // Phase 1 : le plan est affiché sans modifier l'écran.
        expect(callCount, 1);
        expect(appearance.value.components.containsKey('hero-title'), isFalse);
        expect(find.byKey(const ValueKey('vibe-plan-start')), findsOneWidget);

        // Phase 2 : clic sur « Exécuter les 2 lots » -> enchaînement automatique.
        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await tester.pumpAndSettle();

        expect(callCount, 3);
        expect(capturedPrompts[1], contains('PHASE 2 — EXÉCUTION DU LOT 1/2'));
        expect(capturedPrompts[2], contains('PHASE 2 — EXÉCUTION DU LOT 2/2'));
        expect(capturedAttachments[1].single.name, 'blueprint.md');
        expect(capturedAttachments[2].single.name, 'blueprint.md');

        expect(appearance.value.valueComponent('hero-title').initialText, 'Bienvenue');
        expect(
          appearance.value.valueComponent('hero-sub').initialText,
          'Description exacte',
        );
        expect(find.text('Reproduction terminée : 2/2 lots appliqués.'), findsOneWidget);

        // 1 seul Undo annule tout le plan.
        expect(history.canUndo, isTrue);
        history.undo();
        expect(appearance.value.components.containsKey('hero-title'), isFalse);
        expect(appearance.value.components.containsKey('hero-sub'), isFalse);
        expect(history.canUndo, isFalse);
      },
    );

    testWidgets(
      'met le plan en pause sur erreur d’un lot en conservant les lots précédents et permet Réessayer / Ignorer',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        final editMode = ValueNotifier(true);
        final history = EditorHistoryController(
          appearance: appearance,
          editMode: editMode,
        );
        addTearDown(history.dispose);
        addTearDown(editMode.dispose);
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        var lot2ShouldFail = true;
        var lot2Attempts = 0;
        var lot3Called = false;

        await tester.pumpWidget(
          StyleEditScope(
            controller: editMode,
            child: EditorHistoryScope(
              controller: history,
              child: AppearanceScope(
                controller: appearance,
                child: MaterialApp(
                  home: Scaffold(
                    body: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialReproduceExactMode: true,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          if (prompt.contains('PHASE 1 — PLANIFICATION')) {
                            return jsonEncode({
                              'message': 'Plan prêt.',
                              'plan': {
                                'title': 'Plan résilient',
                                'lots': [
                                  {'id': 'lot-1', 'title': 'Lot 1'},
                                  {'id': 'lot-2', 'title': 'Lot 2'},
                                  {'id': 'lot-3', 'title': 'Lot 3'},
                                ],
                              },
                              'vibe': null,
                            });
                          }
                          if (prompt.contains('LOT 1/3')) {
                            return jsonEncode({
                              'message': 'Lot 1 ok',
                              'vibe': {
                                'components': {
                                  'mainLayout': {
                                    'type': 'layout',
                                    'slotLabels': {'lot1-val': 'Val 1'},
                                    'placements': {
                                      'center': [
                                        {
                                          'id': 'lot1-val',
                                          'type': 'registry:Value',
                                        },
                                      ],
                                    },
                                  },
                                  'lot1-val': {'type': 'value', 'text': 'Un'},
                                },
                                'usages': {
                                  'lot1-val': {
                                    'kind': 'explanation',
                                    'translationKey': 'valOne',
                                  },
                                },
                              },
                            });
                          }
                          if (prompt.contains('LOT 2/3')) {
                            lot2Attempts++;
                            if (lot2ShouldFail) {
                              // JSON invalide non récupérable -> épuise les tentatives delta.
                              return 'not-json-at-all';
                            }
                            return jsonEncode({
                              'message': 'Lot 2 ok',
                              'vibe': {
                                'components': {
                                  'mainLayout': {
                                    'type': 'layout',
                                    'slotLabels': {
                                      'lot1-val': 'Val 1',
                                      'lot2-val': 'Val 2',
                                    },
                                    'placements': {
                                      'center': [
                                        {
                                          'id': 'lot1-val',
                                          'type': 'registry:Value',
                                        },
                                        {
                                          'id': 'lot2-val',
                                          'type': 'registry:Value',
                                        },
                                      ],
                                    },
                                  },
                                  'lot2-val': {'type': 'value', 'text': 'Deux'},
                                },
                                'usages': {
                                  'lot2-val': {
                                    'kind': 'explanation',
                                    'translationKey': 'valTwo',
                                  },
                                },
                              },
                            });
                          }
                          lot3Called = true;
                          return jsonEncode({
                            'message': 'Lot 3 ok',
                            'vibe': {
                              'components': {
                                'mainLayout': {
                                  'type': 'layout',
                                  'slotLabels': {
                                    'lot1-val': 'Val 1',
                                    'lot2-val': 'Val 2',
                                    'lot3-val': 'Val 3',
                                  },
                                  'placements': {
                                    'center': [
                                      {
                                        'id': 'lot1-val',
                                        'type': 'registry:Value',
                                      },
                                      {
                                        'id': 'lot2-val',
                                        'type': 'registry:Value',
                                      },
                                      {
                                        'id': 'lot3-val',
                                        'type': 'registry:Value',
                                      },
                                    ],
                                  },
                                },
                                'lot3-val': {'type': 'value', 'text': 'Trois'},
                              },
                              'usages': {
                                'lot3-val': {
                                  'kind': 'explanation',
                                  'translationKey': 'valThree',
                                },
                              },
                            },
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Go',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await tester.pumpAndSettle();

        // Pause sur erreur du Lot 2, mais Lot 1 reste appliqué.
        expect(lot2Attempts, 4);
        expect(lot3Called, isFalse);
        expect(appearance.value.valueComponent('lot1-val').initialText, 'Un');
        expect(find.byKey(const ValueKey('vibe-plan-retry-lot')), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-plan-skip-lot')), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-plan-stop')), findsOneWidget);

        // On corrige le générateur et on clique sur « Réessayer ce lot ».
        lot2ShouldFail = false;
        await tester.tap(find.byKey(const ValueKey('vibe-plan-retry-lot')));
        await tester.pumpAndSettle();

        expect(lot3Called, isTrue);
        expect(appearance.value.valueComponent('lot2-val').initialText, 'Deux');
        expect(appearance.value.valueComponent('lot3-val').initialText, 'Trois');
        expect(find.text('Reproduction terminée : 3/3 lots appliqués.'), findsOneWidget);

        // 1 seul Undo global annule tout le plan même après pause/reprise.
        history.undo();
        expect(appearance.value.components.containsKey('lot1-val'), isFalse);
        expect(appearance.value.components.containsKey('lot2-val'), isFalse);
        expect(appearance.value.components.containsKey('lot3-val'), isFalse);
      },
    );

    testWidgets(
      'permet d’ignorer un lot en échec puis de terminer ou d’arrêter le plan',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(
                body: DefaultAssetBundle(
                  bundle: _GuideBundle(),
                  child: VibeChatDialog(
                    controller: appearance,
                    registry: registry,
                    codec: const AppearanceCodec(),
                    initialReproduceExactMode: true,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (prompt) async {
                      if (prompt.contains('PHASE 1 — PLANIFICATION')) {
                        return jsonEncode({
                          'message': 'Plan prêt.',
                          'plan': {
                            'title': 'Plan skip',
                            'lots': [
                              {'id': 'lot-1', 'title': 'Lot 1'},
                              {'id': 'lot-2', 'title': 'Lot 2'},
                            ],
                          },
                          'vibe': null,
                        });
                      }
                      if (prompt.contains('LOT 1/2')) {
                        return 'invalid-json';
                      }
                      return jsonEncode({
                        'message': 'Lot 2 ok',
                        'vibe': {
                          'components': {
                            'mainLayout': {
                              'type': 'layout',
                              'slotLabels': {'lot2-val': 'Val 2'},
                              'placements': {
                                'center': [
                                  {'id': 'lot2-val', 'type': 'registry:Value'},
                                ],
                              },
                            },
                            'lot2-val': {'type': 'value', 'text': 'Deux'},
                          },
                          'usages': {
                            'lot2-val': {
                              'kind': 'explanation',
                              'translationKey': 'valTwo',
                            },
                          },
                        },
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Go',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('vibe-plan-skip-lot')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('vibe-plan-skip-lot')));
        await tester.pumpAndSettle();

        expect(appearance.value.valueComponent('lot2-val').initialText, 'Deux');
        expect(
          find.text('Reproduction terminée : 1/2 lots appliqués (1 ignoré(s)).'),
          findsOneWidget,
        );
      },
    );
  });

  group('Layout styles rejection and delta recovery', () {
    test(
      'findIneffectiveLayoutStyleViolations flags styles targeting registry:Layout or mainLayout, and allows IterableContent, Card, list items and deletions',
      () {
        final base = Appearance(
          components: {
            'mainLayout': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['footer-container', 'card-1'],
              },
              slotTypes: {
                'footer-container': 'registry:Layout',
                'card-1': 'registry:Card',
              },
            ),
            'footer-container': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['footer-bottom-row'],
              },
              slotTypes: {
                'footer-bottom-row': 'registry:IterableContent',
              },
            ),
            'footer-bottom-row': const SuperLayoutConfig(),
          },
        );

        final withLayoutStyle = base.copyWith(
          styles: {
            'background': const ContainerStyle(color: Color(0xFFFFFFFF)),
            'mainLayout': const ContainerStyle(color: Color(0xFF000000)),
            'footer-container': const ContainerStyle(color: Color(0xFF1A365D)),
            'footer-bottom-row': const ContainerStyle(color: Color(0xFF152B4B)),
            'card-1': const ContainerStyle(color: Color(0xFFEEEEEE)),
            'list-1:item': const ContainerStyle(color: Color(0xFFDDDDDD)),
          },
        );

        final violations =
            AppearanceTransfer.findIneffectiveLayoutStyleViolations(
              withLayoutStyle,
              previous: base,
            );
        expect(violations.keys.toSet(), {'mainLayout', 'footer-container'});
        expect(violations['footer-container'], contains('registry:IterableContent'));
        expect(violations['mainLayout'], contains('background'));
        expect(violations.containsKey('footer-bottom-row'), isFalse);
        expect(violations.containsKey('card-1'), isFalse);
        expect(violations.containsKey('list-1:item'), isFalse);
        expect(violations.containsKey('background'), isFalse);

        // Supprimer un style existant via null reste toujours autorisé.
        final afterDeletion = withLayoutStyle.copyWith(
          styles: Map<String, ContainerStyle>.of(withLayoutStyle.styles)
            ..remove('footer-container')
            ..remove('mainLayout'),
        );
        expect(
          AppearanceTransfer.findIneffectiveLayoutStyleViolations(
            afterDeletion,
            previous: withLayoutStyle,
            patchedStyleIds: const {'footer-container', 'mainLayout'},
          ),
          isEmpty,
        );
      },
    );

    test(
      'VibeDeltaRecovery.salvageFailedAttempt rejects styles targeting registry:Layout while preserving valid components',
      () {
        final base = Appearance(
          components: {
            'mainLayout': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['footer-container'],
              },
              slotTypes: {'footer-container': 'registry:Layout'},
            ),
            'footer-container': const SuperLayoutConfig(),
          },
        );

        final outcome = VibeDeltaRecovery.salvageFailedAttempt(
          initialAppearance: base,
          workingAppearance: base,
          initialPageIds: const {},
          instantiatedIds: const {'mainLayout'},
          hasRegistry: true,
          scope: null,
          codec: const AppearanceCodec(),
          validateAppearance: null,
          effectiveVibePatch: {
            'styles': {
              'footer-container': {'color': '#1A365D'},
            },
            'components': {
              'footer-note': {'type': 'value', 'text': 'Mentions légales'},
              'footer-container': {
                'type': 'layout',
                'slotLabels': {'footer-note': 'Mentions'},
                'placements': {
                  'center': [
                    {'id': 'footer-note', 'type': 'registry:Value'},
                  ],
                },
              },
            },
          },
          rejectedRepoEntries: const [],
          appliedRepoKeys: const {},
          wasTruncated: false,
        );

        expect(outcome.hasCheckpoint, isTrue);
        expect(
          outcome.checkpointAppearance.styles.containsKey('footer-container'),
          isFalse,
        );
        expect(
          outcome.checkpointAppearance.valueComponent('footer-note').initialText,
          'Mentions légales',
        );
        expect(outcome.rejectedEntries, hasLength(1));
        expect(outcome.rejectedEntries.single.section, 'styles');
        expect(outcome.rejectedEntries.single.key, 'footer-container');

        final retryPrompt = VibeDeltaRecovery.buildDeltaRetryPrompt(
          refreshedTurnPrompt: 'ÉTAT ACTUEL',
          priorCauses: const ['Style "footer-container" ignoré au rendu'],
          salvage: outcome,
          pendingRequiredComponentIds: outcome.pendingRequiredComponentIds,
        );
        expect(retryPrompt, contains('styles["footer-container"]'));
        expect(retryPrompt, contains('registry:IterableContent'));
      },
    );

    testWidgets(
      'VibeChatDialog rejects styles targeting registry:Layout, retries with guidance, and applies once promoted to registry:IterableContent',
      (tester) async {
        final initialAppearance = Appearance(
          components: {
            'mainLayout': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['footer-container'],
              },
              slotTypes: {'footer-container': 'registry:Layout'},
            ),
            'footer-container': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['footer-bottom-row'],
              },
              slotTypes: {'footer-bottom-row': 'registry:Layout'},
            ),
            'footer-bottom-row': const SuperLayoutConfig(),
          },
        );
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(initialAppearance);
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final prompts = <String>[];
        var attempt = 0;

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(
                body: DefaultAssetBundle(
                  bundle: _GuideBundle(),
                  child: VibeChatDialog(
                    controller: appearance,
                    registry: registry,
                    codec: const AppearanceCodec(),
                    initialQuestioningLevel: VibeQuestioningLevel.none,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (prompt) async {
                      prompts.add(prompt);
                      attempt++;
                      if (attempt == 1) {
                        return jsonEncode({
                          'message': 'Couleurs appliquées.',
                          'vibe': {
                            'styles': {
                              'footer-container': {
                                'color': '#1A365D',
                                'radii': [0.0, 0.0, 0.0, 0.0],
                                'paddingInsets': [56.0, 0.0, 0.0, 0.0],
                              },
                              'footer-bottom-row': {
                                'color': '#152B4B',
                                'borderColor': '#2D4A77',
                                'borderWidths': [1.0, 0.0, 0.0, 0.0],
                                'paddingInsets': [20.0, 0.0, 20.0, 0.0],
                              },
                            },
                          },
                        });
                      }
                      return jsonEncode({
                        'message': 'Footer converti en IterableContent et coloré.',
                        'vibe': {
                          'styles': {
                            'footer-container': {
                              'color': '#1A365D',
                              'radii': [0.0, 0.0, 0.0, 0.0],
                              'paddingInsets': [56.0, 0.0, 0.0, 0.0],
                            },
                            'footer-bottom-row': {
                              'color': '#152B4B',
                              'borderColor': '#2D4A77',
                              'borderWidths': [1.0, 0.0, 0.0, 0.0],
                              'paddingInsets': [20.0, 0.0, 20.0, 0.0],
                            },
                          },
                          'components': {
                            'mainLayout': {
                              'type': 'layout',
                              'placements': {
                                'center': [
                                  {
                                    'id': 'footer-container',
                                    'type': 'registry:IterableContent',
                                  },
                                ],
                              },
                            },
                            'footer-container': {
                              'type': 'layout',
                              'placements': {
                                'center': [
                                  {
                                    'id': 'footer-bottom-row',
                                    'type': 'registry:IterableContent',
                                  },
                                ],
                              },
                            },
                          },
                        },
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Colore le pied de page.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(attempt, 2);
        expect(prompts, hasLength(2));
        expect(prompts[1], contains('CORRECTION REQUISE'));
        expect(prompts[1], contains('footer-container'));
        expect(prompts[1], contains('registry:IterableContent'));
        expect(
          appearance.value.layout('mainLayout').slotTypeOf('footer-container'),
          'registry:IterableContent',
        );
        expect(
          appearance.value
              .layout('footer-container')
              .slotTypeOf('footer-bottom-row'),
          'registry:IterableContent',
        );
        expect(
          appearance.value.styles['footer-container']?.color,
          const Color(0xFF1A365D),
        );
        expect(
          appearance.value.styles['footer-bottom-row']?.color,
          const Color(0xFF152B4B),
        );
        expect(
          find.text('Footer converti en IterableContent et coloré.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'streaming styles before components succeeds when the same turn promotes placement to registry:IterableContent',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        final store = _MemoryAppearanceStore(
          Appearance(
            components: {
              'mainLayout': const SuperLayoutConfig(
                placements: {
                  SuperLayoutZone.center: ['footer-container'],
                },
                slotTypes: {'footer-container': 'registry:Layout'},
              ),
              'footer-container': const SuperLayoutConfig(),
            },
          ),
        );
        final mainLayout = registry.layoutController('mainLayout');
        late ValueNotifier<Appearance> appAppearance;
        var streamCalls = 0;

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (routeContext, _) {
                appAppearance = AppearanceScope.controllerOf(routeContext)!;
                return Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<SuperLayoutConfig>(
                        valueListenable: mainLayout,
                        builder: (_, cfg, _) => SuperLayout(config: cfg),
                      ),
                    ),
                    SizedBox(
                      width: 420,
                      height: 600,
                      child: DefaultAssetBundle(
                        bundle: _GuideBundle(),
                        child: VibeChatDialog(
                          controller: appAppearance,
                          registry: registry,
                          codec: const AppearanceCodec(),
                          initialQuestioningLevel: VibeQuestioningLevel.none,
                          onClose: () {},
                          onDrag: (_) {},
                          generate: (_) =>
                              Future.error('Should use streamGenerate'),
                          streamGenerate: (
                            prompt, {
                            systemInstruction,
                            staticGuide,
                            attachments = const [],
                            speedMode = VibeAiSpeedMode.fast,
                          }) {
                            streamCalls++;
                            final ctrl = StreamController<GeminiStreamEvent>();
                            const part1 =
                                '{"message":"Footer stylisé.","vibe":{"styles":{"footer-container":{"color":"#1A365D"}},';
                            const part2 =
                                '"components":{"mainLayout":{"type":"layout","placements":{"center":[{"id":"footer-container","type":"registry:IterableContent"}]}}}}}';
                            Future<void>(() async {
                              ctrl.add(
                                const GeminiStreamEvent(
                                  deltaText: part1,
                                  accumulatedText: part1,
                                  isDone: false,
                                  usedContextCache: true,
                                ),
                              );
                              await Future<void>.delayed(Duration.zero);
                              ctrl.add(
                                const GeminiStreamEvent(
                                  deltaText: part2,
                                  accumulatedText: '$part1$part2',
                                  isDone: true,
                                  usedContextCache: true,
                                ),
                              );
                              await ctrl.close();
                            });
                            return ctrl.stream;
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          SuperApp(
            router: router,
            appearanceStore: store,
            registry: registry,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Mets un fond bleu au footer.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(streamCalls, 1);
        expect(
          appAppearance.value.layout('mainLayout').slotTypeOf('footer-container'),
          'registry:IterableContent',
        );
        expect(
          appAppearance.value.styles['footer-container']?.color,
          const Color(0xFF1A365D),
        );
        expect(find.text('Footer stylisé.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _FakeVibeSpeechTranscriber extends VibeSpeechTranscriber {
  ControllableVibeSpeechSession? activeSession;
  String nextManualStopTranscript = '';

  @override
  Future<VibeSpeechSession> startListening() async {
    final session = ControllableVibeSpeechSession(
      onStopAndTranscribe: () async => nextManualStopTranscript,
    );
    activeSession = session;
    return session;
  }
}

class _NamedGuideBundle extends CachingAssetBundle {
  _NamedGuideBundle(this.assets);

  final Map<String, String> assets;
  final List<String> loads = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    final value = assets[key];
    if (value == null) {
      throw FlutterError('Asset "$key" not found.');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

class _GuideBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final text = key.contains('DESIGN')
        ? 'Design de test.'
        : key.contains('REPOSITORY')
        ? 'Repositories de test.'
        : 'Guide de test.';
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

class _MemoryAppearanceStore extends AppearanceStore {
  _MemoryAppearanceStore(this.initial);

  final Appearance initial;

  @override
  Future<Appearance> load() async => initial;

  @override
  Future<void> save(Appearance appearance) async {}
}

class _CountingAppearanceStore extends AppearanceStore {
  _CountingAppearanceStore(this.initial);

  final Appearance initial;
  int saveCalls = 0;

  @override
  Future<Appearance> load() async => initial;

  @override
  Future<void> saveEncoded(String encoded) async {
    saveCalls++;
  }
}
