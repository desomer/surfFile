import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
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
