import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_list_view_config.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/appearance/appearance_store.dart';
import 'package:super_container_layout/services/appearance/appearance_transfer.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/components/super_list_view.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';

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
        expect(requests, 2);
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
        if (prompts.length <= 2) {
          return invalidResponse;
        }
        return jsonEncode({
          'message': 'Corrigé après lecture de la cause.',
          'vibe': _fileListPatch('mainLayout'),
        });
      });

      // Premier envoi : les 2 tentatives échouent sur le composant invalide.
      await send(tester);
      expect(prompts.length, 2);
      // La tentative 2 a déjà reçu la cause précise du composant en erreur.
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

      expect(prompts.length, 3);
      expect(prompts[2], contains('Assistant (ERREUR À CORRIGER) :'));
      expect(prompts[2], contains('Composant "broken-comp"'));
      expect(prompts[2], contains(invalidResponse));
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
                          expect(staticGuide, 'Guide de test.');
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
}

class _GuideBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode('Guide de test.')));
}

class _MemoryAppearanceStore extends AppearanceStore {
  _MemoryAppearanceStore(this.initial);

  final Appearance initial;

  @override
  Future<Appearance> load() async => initial;

  @override
  Future<void> save(Appearance appearance) async {}
}
