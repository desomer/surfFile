import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/ai/call_gemini.dart';
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
    'pasting image from clipboard button and Ctrl+V deduplicates names and forwards binary image attachment',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier(Appearance());
      registry.bindAppearance(appearance);
      registry.layoutController('mainLayout');
      addTearDown(appearance.dispose);
      addTearDown(registry.unbindAppearance);

      // Génère un PNG 1x1 valide à partir d'un DIB 24 bits.
      final dib1x1 = Uint8List(40 + 4);
      ByteData.sublistView(dib1x1)
        ..setUint32(0, 40, Endian.little)
        ..setInt32(4, 1, Endian.little)
        ..setInt32(8, 1, Endian.little)
        ..setUint16(12, 1, Endian.little)
        ..setUint16(14, 24, Endian.little);
      dib1x1.setAll(40, [0xCC, 0x88, 0x44, 0x00]);
      final pngBytes = VibeChatAttachment.encodeDibToPng(dib1x1)!;

      var hasMediaInClipboard = true;
      List<VibeChatAttachment>? receivedAttachments;

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
                hasClipboardMedia: () => hasMediaInClipboard,
                pasteAttachments: () async => [
                  VibeChatAttachment.image(
                    name: 'presse-papiers.png',
                    bytes: pngBytes,
                  ),
                ],
                generate: (_) async => jsonEncode({'message': 'OK'}),
                streamGenerate:
                    (
                      prompt, {
                      systemInstruction,
                      staticGuide,
                      attachments = const [],
                      speedMode = VibeAiSpeedMode.fast,
                    }) async* {
                      receivedAttachments = attachments;
                      const payload =
                          '{"message":"Images bien reçues.","vibe":null}';
                      yield const GeminiStreamEvent(
                        deltaText: payload,
                        accumulatedText: payload,
                        isDone: true,
                        usedContextCache: false,
                      );
                    },
              ),
            ),
          ),
        ),
      );

      // 1. Clic sur le bouton presse-papiers du wizard Vibe IA.
      await tester.tap(
        find.byKey(const ValueKey('vibe-chat-paste-attachment')),
      );
      await tester.pumpAndSettle();
      expect(find.text('presse-papiers.png'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('vibe-chat-pending-attachment-0')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      // 2. Ctrl+V dans le champ de prompt lorsqu'une image est dans le presse-papiers :
      //    ajoute une 2e pièce jointe numérotée sans polluer le champ texte.
      await tester.tap(find.byKey(const ValueKey('vibe-chat-input')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('presse-papiers-2.png'), findsOneWidget);
      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('vibe-chat-input')),
      );
      expect(textField.controller!.text, isEmpty);

      // 3. Lorsque le presse-papiers ne contient pas de média, Ctrl+V n'ajoute pas de 3e image.
      hasMediaInClipboard = false;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('presse-papiers-3.png'), findsNothing);

      // 4. Envoi direct des images jointes sans texte obligatoire : vérifie les octets transmis.
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      expect(receivedAttachments, isNotNull);
      expect(receivedAttachments, hasLength(2));
      expect(receivedAttachments![0].name, 'presse-papiers.png');
      expect(receivedAttachments![0].mimeType, 'image/png');
      expect(receivedAttachments![0].isImage, isTrue);
      expect(receivedAttachments![0].bytes, pngBytes);
      expect(receivedAttachments![1].name, 'presse-papiers-2.png');
      expect(receivedAttachments![1].bytes, pngBytes);
      expect(find.text('Images bien reçues.'), findsOneWidget);
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
      expect(turnPrompts[0], contains('0/4 (Aucun)'));
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

      expect(turnPrompts[2], contains('1/4 (Léger, max 2 questions)'));
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

      expect(turnPrompts[3], contains('3/4 (Approfondi, 4 à 6 questions)'));
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
    expect(content, contains('right >= 38'));
  });

  test('AI guides and system instruction require right padding >= 38px when SuperListView allowRemove is true', () {
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

    expect(jsonGuide, contains('allowRemove: true'));
    expect(jsonGuide, contains('paddingInsets'));
    expect(jsonGuide, contains('38'));
    expect(designGuide, contains('allowRemove: true'));
    expect(designGuide, contains('38'));
    expect(sysInstruction, contains('allowRemove'));
    expect(sysInstruction, contains('38'));
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
      'BEHAVIOR_JSON_AI_GUIDE.md': 'Modélisation des comportements.',
      'SCREEN_DESIGN_AI_GUIDE.md': 'Design System moderne par défaut.',
    });
    final withRepoGuide = await VibeChatDialog.loadStaticGuide(fullBundle);
    expect(withRepoGuide, contains('Grammaire JSON de base.'));
    expect(withRepoGuide, contains('GUIDE DE MODÉLISATION DES REPOSITORIES :'));
    expect(withRepoGuide, contains('Modélisation des repositories JSON.'));
    expect(
      withRepoGuide,
      contains(
        'GUIDE DES COMPORTEMENTS (BEHAVIORS, EVENTS, VALIDATORS & ACTIONS) :',
      ),
    );
    expect(withRepoGuide, contains('Modélisation des comportements.'));
    expect(withRepoGuide, contains('GUIDE DE DESIGN SYSTEM :'));
    expect(withRepoGuide, contains('Design System moderne par défaut.'));

    // Repli gracieux lorsque REPOSITORY_JSON_AI_GUIDE.md et BEHAVIOR_JSON_AI_GUIDE.md sont absents d'un bundle minimal
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
    expect(
      combined,
      isNot(
        contains(
          'GUIDE DES COMPORTEMENTS (BEHAVIORS, EVENTS, VALIDATORS & ACTIONS) :',
        ),
      ),
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
      'BEHAVIOR_JSON_AI_GUIDE.md',
      'packages/super_container_layout/BEHAVIOR_JSON_AI_GUIDE.md',
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
        SuperApp(router: router, appearanceStore: store, registry: registry),
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
                              'kpi-2': {
                                'type': 'value',
                                'text': 'Marge : 32 %',
                              },
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
      expect(
        appearance.value.valueComponent('kpi-1').initialText,
        'CA : 240 k€',
      );
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
      expect(plan.reproduceExact, isFalse);
      expect(plan.lots.map((l) => l.id).toList(), ['lot-1', 'lot-1_2']);
      expect(plan.status, VibePlanStatus.awaitingConfirmation);
      expect(plan.actionableCount, 2);
      final withDisabledLot = plan.withLotAt(
        0,
        (lot) => lot.copyWith(status: VibeLotStatus.disabled),
      );
      expect(withDisabledLot.actionableCount, 1);
      expect(withDisabledLot.finishedCount, 0);
      expect(withDisabledLot.nextActionableIndex, 1);
      expect(
        withDisabledLot.copyWith(status: VibePlanStatus.running).finishedCount,
        1,
      );
      expect(withDisabledLot.formatLotContextPrompt(1), contains('Désactivé'));
      expect(
        plan.formatLotContextPrompt(1),
        contains('>>> À EXÉCUTER MAINTENANT'),
      );

      final exactPlan = VibeExecutionPlan.tryFromJson({
        'lots': [
          {'id': 'lot-1', 'title': 'Header'},
        ],
      }, reproduceExact: true);
      expect(exactPlan, isNotNull);
      expect(exactPlan!.reproduceExact, isTrue);
      expect(exactPlan.title, 'Plan de reproduction à l’identique');
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
      'activer À l’identique seul verrouille Questions sur Aucun, masque Design System et génère en 1 passe sans Phase 1 Plan',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
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
                    registry: registry,
                    codec: const AppearanceCodec(),
                    initialQuestioningLevel: VibeQuestioningLevel.balanced,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (prompt) async {
                      prompts.add(prompt);
                      return jsonEncode({
                        'message': 'Reproduction directe appliquée.',
                        'vibe': {
                          'components': {
                            'mainLayout': {
                              'type': 'layout',
                              'slotLabels': {'exact-val': 'Exact'},
                              'placements': {
                                'center': [
                                  {'id': 'exact-val', 'type': 'registry:Value'},
                                ],
                              },
                            },
                            'exact-val': {'type': 'value', 'text': 'Exact'},
                          },
                          'usages': {
                            'exact-val': {
                              'kind': 'explanation',
                              'translationKey': 'exactVal',
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

        expect(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
          findsOneWidget,
        );
        expect(find.text('Équilibré'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-reproduce-exact')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('vibe-chat-exact-design-notice')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
          findsNothing,
        );
        expect(find.text('Aucun'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Reproduis cette page',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(prompts, hasLength(1));
        expect(prompts.single, contains('MODE « REPRODUIRE À L’IDENTIQUE »'));
        expect(
          prompts.single,
          isNot(contains('PHASE 1 — PLANIFICATION EN LOTS')),
        );
        expect(find.byKey(const ValueKey('vibe-plan-card')), findsNothing);
        expect(
          appearance.value.valueComponent('exact-val').initialText,
          'Exact',
        );

        // Désactiver le mode restaure le niveau de questionnement précédent.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-reproduce-exact')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Équilibré'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'affiche la puce Plan à côté de Précis, autorise askUser avant le plan et exécute les lots avec Design System et repositories',
      (tester) async {
        final tempDir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('vibe_plan_repo_'),
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
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final mdAttachment = VibeChatAttachment.text(
          name: 'cahier.md',
          content: '# Cahier CRM\nListe clients + statut',
        );
        final prompts = <String>[];
        final attachmentsPerCall = <List<VibeChatAttachment>>[];
        final planModeChanges = <bool>[];
        var callCount = 0;

        await tester.pumpWidget(
          JsonRepositoryScope(
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
                      repositoryStore: repoStore,
                      codec: const AppearanceCodec(),
                      initialQuestioningLevel: VibeQuestioningLevel.balanced,
                      onPlanModeChanged: planModeChanges.add,
                      pickAttachments: () async => [mdAttachment],
                      onClose: () {},
                      onDrag: (_) {},
                      generate: (prompt) async {
                        fail(
                          'generate ne doit pas être appelé quand streamGenerate est fourni',
                        );
                      },
                      streamGenerate:
                          (
                            prompt, {
                            systemInstruction,
                            staticGuide,
                            attachments = const [],
                            speedMode = VibeAiSpeedMode.fast,
                          }) async* {
                            callCount++;
                            prompts.add(prompt);
                            attachmentsPerCall.add(attachments);
                            late final String payload;
                            if (callCount == 1) {
                              payload = jsonEncode({
                                'message': 'Précisons d’abord le CRM :',
                                'askUser': {
                                  'questions': [
                                    {
                                      'id': 'density',
                                      'title': 'Densité souhaitée ?',
                                      'type': 'single',
                                      'options': ['Compact', 'Aéré'],
                                      'default': 'Compact',
                                    },
                                  ],
                                },
                                'vibe': null,
                              });
                            } else if (callCount == 2) {
                              payload = jsonEncode({
                                'message': 'Voici le plan en 2 lots.',
                                'plan': {
                                  'title': 'Plan CRM',
                                  'lots': [
                                    {
                                      'id': 'lot-1',
                                      'title': 'Repository & En-tête',
                                      'description':
                                          'Créer le repo clients et le titre',
                                    },
                                    {
                                      'id': 'lot-2',
                                      'title': 'Détail',
                                      'description': 'Ajouter le sous-titre',
                                    },
                                  ],
                                },
                                'vibe': null,
                              });
                            } else if (callCount == 3) {
                              payload = jsonEncode({
                                'message': 'Lot 1 terminé.',
                                'repositories': {
                                  'crm_clients': {
                                    'name': 'Clients CRM',
                                    'mode': 'merge',
                                    'data': {'title': 'Portefeuille Clients'},
                                  },
                                },
                                'vibe': {
                                  'components': {
                                    'mainLayout': {
                                      'type': 'layout',
                                      'slotLabels': {'crm-title': 'Titre CRM'},
                                      'placements': {
                                        'center': [
                                          {
                                            'id': 'crm-title',
                                            'type': 'registry:Value',
                                          },
                                        ],
                                      },
                                    },
                                    'crm-title': {
                                      'type': 'value',
                                      'binding': 'crm_clients:title',
                                    },
                                  },
                                  'usages': {
                                    'crm-title': {'kind': 'dynamicData'},
                                  },
                                },
                              });
                            } else {
                              payload = jsonEncode({
                                'message': 'Lot 2 terminé.',
                                'vibe': {
                                  'components': {
                                    'mainLayout': {
                                      'type': 'layout',
                                      'slotLabels': {
                                        'crm-title': 'Titre CRM',
                                        'crm-sub': 'Sous-titre',
                                      },
                                      'placements': {
                                        'center': [
                                          {
                                            'id': 'crm-title',
                                            'type': 'registry:Value',
                                          },
                                          {
                                            'id': 'crm-sub',
                                            'type': 'registry:Value',
                                          },
                                        ],
                                      },
                                    },
                                    'crm-sub': {
                                      'type': 'value',
                                      'text': 'Vue consolidée',
                                    },
                                  },
                                  'usages': {
                                    'crm-sub': {
                                      'kind': 'explanation',
                                      'translationKey': 'crmSub',
                                    },
                                  },
                                },
                              });
                            }
                            yield GeminiStreamEvent(
                              deltaText: payload,
                              accumulatedText: payload,
                              isDone: true,
                              usedContextCache: false,
                            );
                          },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Vérifie le séparateur vertical entre la dernière puce vitesse (« Précis »)
        // et « Plan », puis le passage de « À l’identique » et des actions suivantes
        // sur la ligne du dessous.
        final reasoningRect = tester.getRect(
          find.byKey(const ValueKey('vibe-chat-speed-reasoning')),
        );
        final dividerRect = tester.getRect(
          find.byKey(const ValueKey('vibe-chat-speed-plan-divider')),
        );
        final planRect = tester.getRect(
          find.byKey(const ValueKey('vibe-chat-plan-mode')),
        );
        final exactRect = tester.getRect(
          find.byKey(const ValueKey('vibe-chat-reproduce-exact')),
        );
        final reactiveRect = tester.getRect(
          find.byKey(const ValueKey('vibe-chat-reactive-values')),
        );
        final auditRect = tester.getRect(
          find.byKey(const ValueKey('vibe-chat-audit-page')),
        );
        expect(dividerRect.left, greaterThanOrEqualTo(reasoningRect.right));
        expect(planRect.left, greaterThanOrEqualTo(dividerRect.right));
        expect(
          (planRect.center.dy - reasoningRect.center.dy).abs(),
          lessThan(4),
        );
        expect(exactRect.top, greaterThanOrEqualTo(planRect.bottom));
        expect(reactiveRect.top, greaterThanOrEqualTo(planRect.bottom));
        expect(auditRect.top, greaterThanOrEqualTo(planRect.bottom));
        expect(reactiveRect.left, greaterThan(exactRect.right));
        expect(auditRect.left, greaterThan(reactiveRect.right));

        await tester.tap(find.byKey(const ValueKey('vibe-chat-plan-mode')));
        await tester.pumpAndSettle();
        expect(planModeChanges, [true]);

        // Le Design System et le curseur Questions restent actifs en mode Plan seul.
        expect(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
          findsOneWidget,
        );
        expect(find.text('Équilibré'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('vibe-chat-attach')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Crée un écran CRM',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await pumpRealAsync(
          tester,
          until: () => find
              .byKey(const ValueKey('vibe-ask-user-card'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();

        // Tour 1 : askUser posé en amont du plan.
        expect(callCount, 1);
        expect(prompts[0], contains('PHASE 1 — PLANIFICATION EN LOTS'));
        expect(
          prompts[0],
          isNot(contains('MODE « REPRODUIRE À L’IDENTIQUE »')),
        );
        expect(prompts[0], contains('de proposer le plan par lots ("plan")'));
        expect(
          find.byKey(const ValueKey('vibe-ask-user-card')),
          findsOneWidget,
        );

        // Validation du questionnaire -> Tour 2 produit le plan.
        await tester.tap(find.byKey(const ValueKey('vibe-ask-user-submit')));
        await pumpRealAsync(
          tester,
          until: () => find
              .byKey(const ValueKey('vibe-plan-start'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();

        expect(callCount, 2);
        expect(
          prompts[1],
          contains(
            'Génère directement le plan par lots ("plan") correspondant',
          ),
        );
        expect(find.byKey(const ValueKey('vibe-plan-card')), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-plan-start')), findsOneWidget);

        // Exécution des lots -> conserve demande initiale + réponses askUser + pièce jointe,
        // et n'injecte PAS le mode pixel-perfect.
        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await pumpRealAsync(
          tester,
          until: () => find
              .text('Plan terminé : 2/2 lots appliqués.')
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();

        expect(callCount, 4);
        expect(
          prompts[2],
          isNot(contains('MODE « REPRODUIRE À L’IDENTIQUE »')),
        );
        expect(prompts[2], contains('Crée un écran CRM'));
        expect(prompts[2], contains('Densité souhaitée'));
        expect(attachmentsPerCall[2], [mdAttachment]);
        expect(attachmentsPerCall[3], [mdAttachment]);

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
        expect(
          appearance.value.valueComponent('crm-sub').initialText,
          'Vue consolidée',
        );
        expect(find.text('Plan terminé : 2/2 lots appliqués.'), findsOneWidget);
      },
    );

    testWidgets(
      'désactive un lot avant exécution, conserve les pièces jointes et regroupe en 1 Undo',
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
                        initialPlanMode: true,
                        initialReproduceExactMode: true,
                        pickAttachments: () async => [mdAttachment],
                        onClose: () {},
                        onDrag: (_) {},
                        streamGenerate:
                            (
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

        await tester.tap(
          find.byKey(const ValueKey('vibe-plan-lot-toggle-lot-2')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Exécuter le lot'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('vibe-plan-lot-toggle-lot-1')),
        );
        await tester.pumpAndSettle();
        final startButton = tester.widget<FilledButton>(
          find.byKey(const ValueKey('vibe-plan-start')),
        );
        expect(startButton.onPressed, isNull);
        expect(find.text('Aucun lot activé'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('vibe-plan-lot-toggle-lot-1')),
        );
        await tester.pumpAndSettle();

        // Le lot désactivé reste dans le plan, mais n'est pas exécuté.
        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await pumpRealAsync(
          tester,
          until: () => find
              .text(
                'Reproduction terminée : 1/2 lots appliqués (1 désactivé(s)).',
              )
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();

        expect(callCount, 2);
        expect(capturedPrompts[1], contains('PHASE 2 — EXÉCUTION DU LOT 1/2'));
        expect(capturedAttachments[1].single.name, 'blueprint.md');

        expect(
          appearance.value.valueComponent('hero-title').initialText,
          'Bienvenue',
        );
        expect(appearance.value.components.containsKey('hero-sub'), isFalse);
        expect(
          find.text(
            'Reproduction terminée : 1/2 lots appliqués (1 désactivé(s)).',
          ),
          findsOneWidget,
        );

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
                        initialPlanMode: true,
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
        expect(
          find.byKey(const ValueKey('vibe-plan-retry-lot')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-skip-lot')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('vibe-plan-stop')), findsOneWidget);

        // On corrige le générateur et on clique sur « Réessayer ce lot ».
        lot2ShouldFail = false;
        await tester.tap(find.byKey(const ValueKey('vibe-plan-retry-lot')));
        await tester.pumpAndSettle();

        expect(lot3Called, isTrue);
        expect(appearance.value.valueComponent('lot2-val').initialText, 'Deux');
        expect(
          appearance.value.valueComponent('lot3-val').initialText,
          'Trois',
        );
        expect(
          find.text('Reproduction terminée : 3/3 lots appliqués.'),
          findsOneWidget,
        );

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
                    initialPlanMode: true,
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

        expect(
          find.byKey(const ValueKey('vibe-plan-skip-lot')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('vibe-plan-skip-lot')));
        await tester.pumpAndSettle();

        expect(appearance.value.valueComponent('lot2-val').initialText, 'Deux');
        expect(
          find.text(
            'Reproduction terminée : 1/2 lots appliqués (1 ignoré(s)).',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'affiche les traces timées Phase 1 / lots / outils et supporte Retry partiel (checkpoint) et Retry complet (lot & plan)',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        var phase1Attempts = 0;
        var lot1Calls = 0;
        var lot2Calls = 0;
        final lot2Prompts = <String>[];
        var lot2ShouldFail = true;
        var lot2Mode = 'partial';

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
                    initialPlanMode: true,
                    onClose: () {},
                    onDrag: (_) {},
                    streamGenerate:
                        (
                          prompt, {
                          systemInstruction,
                          staticGuide,
                          attachments = const [],
                          speedMode = VibeAiSpeedMode.fast,
                        }) async* {
                          if (prompt.contains('PHASE 1 — PLANIFICATION')) {
                            phase1Attempts++;
                            if (phase1Attempts == 1) {
                              throw const GeminiApiException(
                                statusCode: 503,
                                message: 'Service unavailable',
                              );
                            }
                            final planPayload = jsonEncode({
                              'message': 'Plan prêt en 2 lots.',
                              'plan': {
                                'title': 'Page CRM',
                                'lots': [
                                  {'id': 'lot-1', 'title': 'En-tête'},
                                  {'id': 'lot-2', 'title': 'Corps'},
                                ],
                              },
                              'vibe': null,
                            });
                            yield GeminiStreamEvent(
                              deltaText: planPayload,
                              accumulatedText: planPayload,
                              isDone: true,
                              usedContextCache: true,
                            );
                            return;
                          }

                          if (prompt.contains('LOT 1/2')) {
                            lot1Calls++;
                            final lot1Payload = jsonEncode({
                              'message': 'Lot 1 ok',
                              'vibe': {
                                'components': {
                                  'mainLayout': {
                                    'type': 'layout',
                                    'slotLabels': {'hdr-title': 'Titre'},
                                    'placements': {
                                      'center': [
                                        {
                                          'id': 'hdr-title',
                                          'type': 'registry:Value',
                                        },
                                      ],
                                    },
                                  },
                                  'hdr-title': {
                                    'type': 'value',
                                    'text': 'CRM v$lot1Calls',
                                  },
                                },
                                'usages': {
                                  'hdr-title': {
                                    'kind': 'explanation',
                                    'translationKey': 'hdrTitle',
                                  },
                                },
                              },
                            });
                            yield GeminiStreamEvent(
                              deltaText: lot1Payload,
                              accumulatedText: lot1Payload,
                              isDone: true,
                              usedContextCache: true,
                            );
                            return;
                          }

                          lot2Calls++;
                          lot2Prompts.add(prompt);
                          if (lot2ShouldFail) {
                            // Simule une coupure réseau en plein streaming SSE après avoir
                            // déjà reçu un composant valide (lot2-ok) mais avant lot2-bad.
                            const partialChunk =
                                '{"message":"Lot 2 partiel","vibe":{"components":{'
                                '"mainLayout":{"type":"layout","slotLabels":{"hdr-title":"Titre","lot2-ok":"OK","lot2-bad":"KO"},'
                                '"placements":{"center":[{"id":"hdr-title","type":"registry:Value"},'
                                '{"id":"lot2-ok","type":"registry:Value"},'
                                '{"id":"lot2-bad","type":"registry:Value"}]}},'
                                '"lot2-ok":{"type":"value","text":"Sauvegardé"},';
                            yield const GeminiStreamEvent(
                              deltaText: partialChunk,
                              accumulatedText: partialChunk,
                              isDone: false,
                              usedContextCache: true,
                            );
                            throw const GeminiApiException(
                              statusCode: 503,
                              message: 'Stream interrupted',
                            );
                          }

                          final completionPayload = lot2Mode == 'partial'
                              ? jsonEncode({
                                  'message': 'Delta lot 2 ok',
                                  'vibe': {
                                    'components': {
                                      'lot2-bad': {
                                        'type': 'value',
                                        'text': 'Complété',
                                      },
                                    },
                                    'usages': {
                                      'lot2-ok': {
                                        'kind': 'explanation',
                                        'translationKey': 'lot2Ok',
                                      },
                                      'lot2-bad': {
                                        'kind': 'explanation',
                                        'translationKey': 'lot2Bad',
                                      },
                                    },
                                  },
                                })
                              : jsonEncode({
                                  'message': 'Lot 2 complet ok',
                                  'vibe': {
                                    'components': {
                                      'mainLayout': {
                                        'type': 'layout',
                                        'slotLabels': {
                                          'hdr-title': 'Titre',
                                          'lot2-full': 'Complet',
                                        },
                                        'placements': {
                                          'center': [
                                            {
                                              'id': 'hdr-title',
                                              'type': 'registry:Value',
                                            },
                                            {
                                              'id': 'lot2-full',
                                              'type': 'registry:Value',
                                            },
                                          ],
                                        },
                                      },
                                      'lot2-full': {
                                        'type': 'value',
                                        'text': 'Régénéré complet',
                                      },
                                    },
                                    'usages': {
                                      'lot2-full': {
                                        'kind': 'explanation',
                                        'translationKey': 'lot2Full',
                                      },
                                    },
                                  },
                                });
                          yield GeminiStreamEvent(
                            deltaText: completionPayload,
                            accumulatedText: completionPayload,
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
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Construis le CRM',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        // Phase 1 a récupéré automatiquement après la 503 et affiche ses traces timées.
        expect(phase1Attempts, 2);
        expect(
          find.byKey(const ValueKey('vibe-plan-duration-badge')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-planning-traces')),
          findsOneWidget,
        );

        // Démarre l'exécution : Lot 1 passe, Lot 2 échoue avec checkpoint partiel préservé.
        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await tester.pumpAndSettle();

        expect(lot1Calls, 1);
        expect(lot2Calls, 4);
        // L'écran reste propre sur Lot 1 en pause (lot2-ok pas encore commité).
        expect(
          appearance.value.valueComponent('hdr-title').initialText,
          'CRM v1',
        );
        expect(appearance.value.components.containsKey('lot2-ok'), isFalse);

        // Traces timées & badge checkpoint partiel + boutons Retry partiel / complet.
        expect(
          find.byKey(const ValueKey('vibe-plan-lot-duration-lot-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-lot-traces-lot-2')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('vibe-plan-lot-traces-lot-2')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('checkpoint partiel'),
          findsAtLeastNWidgets(1),
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-lot-checkpoint-lot-2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-retry-lot-partial')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-retry-lot')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-retry-all')),
          findsOneWidget,
        );

        // 1. Retry partiel du lot 2 : reprend depuis le checkpoint sans régénérer lot2-ok.
        lot2ShouldFail = false;
        lot2Mode = 'partial';
        await tester.tap(
          find.byKey(const ValueKey('vibe-plan-retry-lot-partial')),
        );
        await tester.pumpAndSettle();

        expect(lot2Prompts.last, contains('MODE DELTA INCRÉMENTAL'));
        expect(lot2Prompts.last, contains('lot2-ok'));
        expect(
          appearance.value.valueComponent('lot2-ok').initialText,
          'Sauvegardé',
        );
        expect(
          appearance.value.valueComponent('lot2-bad').initialText,
          'Complété',
        );
        expect(find.text('Plan terminé : 2/2 lots appliqués.'), findsOneWidget);

        // 2. Retry complet du plan après complétion : ré-exécute Lot 1 puis Lot 2 depuis zéro.
        lot2Mode = 'full';
        await tester.tap(find.byKey(const ValueKey('vibe-plan-retry-all')));
        await tester.pumpAndSettle();

        expect(lot1Calls, 2);
        expect(
          appearance.value.valueComponent('hdr-title').initialText,
          'CRM v2',
        );
        expect(appearance.value.components.containsKey('lot2-ok'), isFalse);
        expect(
          appearance.value.valueComponent('lot2-full').initialText,
          'Régénéré complet',
        );
      },
    );
  });

  group('Layout styles rejection and delta recovery', () {
    test('findIneffectiveLayoutStyleViolations flags styles targeting registry:Layout or mainLayout, and allows IterableContent, Card, list items and deletions', () {
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
            slotTypes: {'footer-bottom-row': 'registry:IterableContent'},
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
      expect(
        violations['footer-container'],
        contains('registry:IterableContent'),
      );
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
    });

    test('VibeDeltaRecovery.salvageFailedAttempt rejects styles targeting registry:Layout while preserving valid components', () {
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
    });

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
                        'message':
                            'Footer converti en IterableContent et coloré.',
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
                          streamGenerate:
                              (
                                prompt, {
                                systemInstruction,
                                staticGuide,
                                attachments = const [],
                                speedMode = VibeAiSpeedMode.fast,
                              }) {
                                streamCalls++;
                                final ctrl =
                                    StreamController<GeminiStreamEvent>();
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
          SuperApp(router: router, appearanceStore: store, registry: registry),
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
          appAppearance.value
              .layout('mainLayout')
              .slotTypeOf('footer-container'),
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

  group('+ de questions et niveau Exhaustif', () {
    testWidgets(
      'le bouton « + de questions » de VibeAskUserCard enchaîne une série complémentaire plafonnée à 4 questions avant génération',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final prompts = <String>[];
        var turn = 0;

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
                    initialQuestioningLevel: VibeQuestioningLevel.exhaustive,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (prompt) async {
                      prompts.add(prompt);
                      turn++;
                      if (turn == 1) {
                        return jsonEncode({
                          'message': 'Première série exhaustive :',
                          'askUser': {
                            'questions': [
                              for (var i = 1; i <= 8; i++)
                                {
                                  'id': 'q_$i',
                                  'title': 'Question initiale $i',
                                  'type': 'single',
                                  'options': ['Option A', 'Option B'],
                                  'default': 'Option A',
                                },
                            ],
                          },
                          'vibe': null,
                        });
                      }
                      if (turn == 2) {
                        return jsonEncode({
                          'message': 'Questions complémentaires :',
                          'askUser': {
                            'questions': [
                              for (var i = 1; i <= 6; i++)
                                {
                                  'id': 'more_$i',
                                  'title': 'Question complémentaire $i',
                                  'type': 'boolean',
                                  'default': true,
                                },
                            ],
                          },
                          'vibe': null,
                        });
                      }
                      return jsonEncode({
                        'message': 'Écran généré après approfondissement.',
                        'vibe': {
                          'components': {
                            'mainLayout': {
                              'type': 'layout',
                              'slotLabels': {'done-label': 'Titre'},
                              'placements': {
                                'center': [
                                  {
                                    'id': 'done-label',
                                    'type': 'registry:Value',
                                  },
                                ],
                              },
                            },
                            'done-label': {
                              'type': 'value',
                              'text': 'Approfondi OK',
                            },
                          },
                          'usages': {
                            'done-label': {
                              'kind': 'explanation',
                              'translationKey': 'doneTitle',
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

        // Le cran Exhaustif (4/4) accepte plus de 6 questions (ici 8).
        expect(find.text('Exhaustif'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Crée un CRM complet.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(prompts[0], contains('4/4 (Exhaustif, 6 à 10 questions)'));
        expect(find.text('Question initiale 1'), findsOneWidget);
        expect(find.text('Question initiale 8'), findsOneWidget);

        // Clic sur « + de questions » sur la carte : enregistre les choix et demande 2 à 4 questions.
        final moreBtn = find.byKey(const ValueKey('vibe-ask-user-more'));
        await tester.ensureVisible(moreBtn);
        await tester.tap(moreBtn);
        await tester.pumpAndSettle();

        expect(
          prompts[1],
          contains(
            '+ de questions demandé (2 à 4 questions complémentaires OBLIGATOIRES)',
          ),
        );
        expect(prompts[1], contains('Réponses enregistrées pour cette étape'));
        expect(
          find.text('Questions complémentaires demandées'),
          findsOneWidget,
        );
        // Plafonné à 4 questions complémentaires même si le modèle en a renvoyé 6.
        expect(find.text('Question complémentaire 1'), findsOneWidget);
        expect(find.text('Question complémentaire 4'), findsOneWidget);
        expect(find.text('Question complémentaire 5'), findsNothing);

        // Puis clic sur « Générer » applique le patch avec blocage anti-boucle.
        final submitBtn = find.byKey(const ValueKey('vibe-ask-user-submit'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        expect(prompts[2], contains('Réponses déjà fournies — INTERDICTION'));
        expect(
          appearance.value.valueComponent('done-label').initialText,
          'Approfondi OK',
        );
        // Après génération, la bulle assistant expose l'action « + de questions ».
        expect(
          find.byKey(const ValueKey('vibe-message-more-questions')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'les boutons « + de questions » de la barre de saisie et du message assistant fonctionnent même avec le slider sur Aucun et relancent si askUser manque',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final prompts = <String>[];
        var callCount = 0;

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
                      callCount++;
                      if (callCount == 1) {
                        // Omet askUser au 1er essai : doit être rejeté et relancé !
                        return jsonEncode({
                          'message': 'Pas de questions.',
                          'vibe': null,
                        });
                      }
                      if (callCount == 2) {
                        return jsonEncode({
                          'message': 'Précisons votre demande :',
                          'askUser': {
                            'questions': [
                              {
                                'id': 'style',
                                'title': 'Style de tableau ?',
                                'type': 'single',
                                'options': ['Compact', 'Aéré'],
                                'default': 'Compact',
                              },
                            ],
                          },
                          'vibe': null,
                        });
                      }
                      if (callCount == 3) {
                        return jsonEncode({
                          'message': 'Tableau créé.',
                          'vibe': {
                            'components': {
                              'mainLayout': {
                                'type': 'layout',
                                'slotLabels': {'tbl-title': 'Titre'},
                                'placements': {
                                  'center': [
                                    {
                                      'id': 'tbl-title',
                                      'type': 'registry:Value',
                                    },
                                  ],
                                },
                              },
                              'tbl-title': {
                                'type': 'value',
                                'text': 'Tableau Compact',
                              },
                            },
                            'usages': {
                              'tbl-title': {
                                'kind': 'explanation',
                                'translationKey': 'tblTitle',
                              },
                            },
                          },
                        });
                      }
                      return jsonEncode({
                        'message': 'Affinons le tableau créé :',
                        'askUser': {
                          'questions': [
                            {
                              'id': 'export',
                              'title': 'Ajouter un export CSV ?',
                              'type': 'boolean',
                              'default': true,
                            },
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

        expect(find.text('Aucun'), findsOneWidget);
        // Sur le message d'accueil initial, pas de puce vides sous la bulle.
        expect(
          find.byKey(const ValueKey('vibe-message-more-questions')),
          findsNothing,
        );

        // Saisit un brouillon et clique sur « + de questions » dans la barre de saisie.
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Ajoute un tableau de factures',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-ask-more')));
        await tester.pumpAndSettle();

        // Appel 1 rejeté (pas d'askUser), appel 2 renvoie la carte !
        expect(callCount, 2);
        expect(prompts[1], contains('CORRECTION REQUISE'));
        expect(
          find.byKey(const ValueKey('vibe-ask-user-card')),
          findsOneWidget,
        );
        expect(find.text('Style de tableau ?'), findsOneWidget);

        // Valide la carte -> génère le tableau.
        await tester.tap(find.byKey(const ValueKey('vibe-ask-user-submit')));
        await tester.pumpAndSettle();
        expect(
          appearance.value.valueComponent('tbl-title').initialText,
          'Tableau Compact',
        );

        // Clique ensuite sur « + de questions » directement sous la réponse de l'assistant.
        final msgMoreBtn = find.byKey(
          const ValueKey('vibe-message-more-questions'),
        );
        expect(msgMoreBtn, findsOneWidget);
        await tester.ensureVisible(msgMoreBtn);
        await tester.tap(msgMoreBtn);
        await tester.pumpAndSettle();

        expect(callCount, 4);
        expect(find.text('Ajouter un export CSV ?'), findsOneWidget);
      },
    );

    testWidgets(
      'déclenche une alerte sonore et un retour visuel à la fin d’une tâche IA (succès, erreur et mode muet)',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final soundPlayer = _RecordingVibeSoundPlayer();
        final completionController = VibeTaskCompletionController();
        addTearDown(completionController.dispose);

        var callCount = 0;
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
                    completionController: completionController,
                    soundPlayer: soundPlayer,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (_) async {
                      callCount++;
                      if (callCount == 1) {
                        return jsonEncode({
                          'message': 'Carte ajoutée.',
                          'vibe': {'accent': '#10B981'},
                        });
                      }
                      if (callCount == 2) {
                        return 'réponse invalide non JSON';
                      }
                      return jsonEncode({
                        'message': 'Réponse silencieuse prête.',
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

        expect(
          find.byKey(const ValueKey('vibe-chat-completion-alert')),
          findsNothing,
        );

        // 1. Tâche réussie -> alerte sonore success + bandeau + badge d'en-tête.
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Passe en vert émeraude',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(soundPlayer.outcomes, [VibeTaskOutcome.success]);
        expect(
          find.byKey(const ValueKey('vibe-chat-completion-alert')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-chat-header-completion-badge')),
          findsOneWidget,
        );
        expect(find.text('Tâche IA terminée'), findsOneWidget);
        expect(find.text('Carte ajoutée.'), findsAtLeastNWidgets(1));

        // Fermeture manuelle de l'alerte visuelle.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-completion-dismiss')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('vibe-chat-completion-alert')),
          findsNothing,
        );

        // 2. Tâche en erreur -> alerte sonore error + bandeau erreur.
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Provoque une erreur',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(soundPlayer.outcomes, [
          VibeTaskOutcome.success,
          VibeTaskOutcome.error,
        ]);
        expect(
          find.byKey(const ValueKey('vibe-chat-completion-alert')),
          findsOneWidget,
        );
        expect(find.text('Tâche IA échouée'), findsOneWidget);

        // 3. Coupure du son via le bouton de l'en-tête -> la 3e tâche n'émet aucun son
        // tout en conservant le retour visuel.
        await tester.tap(find.byKey(const ValueKey('vibe-chat-sound-toggle')));
        await tester.pumpAndSettle();
        expect(completionController.soundEnabled, isFalse);

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Simple question',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(soundPlayer.outcomes, [
          VibeTaskOutcome.success,
          VibeTaskOutcome.error,
        ]);
        expect(
          find.byKey(const ValueKey('vibe-chat-completion-alert')),
          findsOneWidget,
        );
        expect(find.text('Réponse IA prête'), findsOneWidget);
      },
    );

    test('VibeDeltaRecovery.salvageFailedAttempt isolates invalid pageCatalog entries and keeps valid pages', () {
      final router = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
          ],
        ),
      );
      addTearDown(router.dispose);

      final base = Appearance();
      final outcome = VibeDeltaRecovery.salvageFailedAttempt(
        initialAppearance: base,
        workingAppearance: base,
        initialPageIds: const {},
        instantiatedIds: const {},
        hasRegistry: false,
        scope: null,
        codec: const AppearanceCodec(),
        validateAppearance: (a) => router.validate(a.pageCatalog),
        effectiveVibePatch: {
          'pageCatalog': {
            'pages': [
              {'id': 'page-home', 'name': 'Accueil', 'path': '/'},
              {'id': 'page-clients', 'name': 'Clients', 'path': '/clients'},
            ],
            'homePageId': 'page-home',
          },
          'components': {
            'page-home': {
              'type': 'scaffold',
              'placements': {
                'body': [
                  {'id': 'home-title', 'type': 'registry:Value'},
                ],
              },
            },
            'home-title': {'type': 'value', 'text': 'Accueil'},
            'page-clients': {
              'type': 'scaffold',
              'placements': {
                'body': [
                  {'id': 'clients-title', 'type': 'registry:Value'},
                ],
              },
            },
            'clients-title': {'type': 'value', 'text': 'Clients'},
          },
        },
        rejectedRepoEntries: const [],
        appliedRepoKeys: const {},
        wasTruncated: false,
      );

      expect(outcome.hasCheckpoint, isTrue);
      expect(outcome.checkpointAppearance.pageCatalog.pages.map((p) => p.id), [
        'page-clients',
      ]);
      expect(outcome.checkpointAppearance.pageCatalog.homePageId, isNull);
      expect(
        outcome.checkpointAppearance
            .valueComponent('clients-title')
            .initialText,
        'Clients',
      );
      expect(outcome.rejectedEntries, hasLength(1));
      expect(outcome.rejectedEntries.single.section, 'pageCatalog');
      expect(outcome.rejectedEntries.single.key, 'page-home');
      expect(outcome.rejectedEntries.single.message, contains('page-home'));

      final retryPrompt = VibeDeltaRecovery.buildDeltaRetryPrompt(
        refreshedTurnPrompt: 'ÉTAT ACTUEL',
        priorCauses: const ['Chemin invalide'],
        salvage: outcome,
        pendingRequiredComponentIds: outcome.pendingRequiredComponentIds,
      );
      expect(retryPrompt, contains('pageCatalog["page-home"]'));
      expect(retryPrompt, contains('Rappel sur "pageCatalog"'));
      expect(retryPrompt, contains('"root" / "mainLayout"'));
    });

    testWidgets(
      'Plan mode passes coded routes and recovers when Lot 1 emits pageCatalog with "/"',
      (tester) async {
        final router = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
            ],
          ),
        );
        addTearDown(router.dispose);

        final appearance = ValueNotifier(
          Appearance(components: {'mainLayout': const SuperLayoutConfig()}),
        );
        addTearDown(appearance.dispose);

        final prompts = <String>[];
        var callIndex = 0;

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(
                body: DefaultAssetBundle(
                  bundle: _GuideBundle(),
                  child: VibeChatDialog(
                    controller: appearance,
                    pageRouting: router,
                    validateAppearance: (a) => router.validate(a.pageCatalog),
                    codec: const AppearanceCodec(),
                    initialQuestioningLevel: VibeQuestioningLevel.none,
                    initialPlanMode: true,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (prompt) async {
                      prompts.add(prompt);
                      callIndex++;
                      if (callIndex == 1) {
                        return jsonEncode({
                          'message': 'Voici le plan.',
                          'plan': {
                            'title': 'Application CRM',
                            'lots': [
                              {
                                'id': 'lot-1',
                                'title': 'Shell et accueil',
                                'description': 'Configurer la page accueil.',
                              },
                            ],
                          },
                          'vibe': null,
                        });
                      }
                      if (callIndex == 2) {
                        return jsonEncode({
                          'message': 'Lot 1 généré.',
                          'vibe': {
                            'pageCatalog': {
                              'pages': [
                                {
                                  'id': 'page-home',
                                  'name': 'Accueil',
                                  'path': '/',
                                },
                              ],
                              'homePageId': 'page-home',
                            },
                            'components': {
                              'page-home': {
                                'type': 'scaffold',
                                'placements': {
                                  'body': [
                                    {
                                      'id': 'home-title',
                                      'type': 'registry:Value',
                                    },
                                  ],
                                },
                              },
                              'home-title': {
                                'type': 'value',
                                'text': 'Bienvenue',
                              },
                            },
                          },
                        });
                      }
                      return jsonEncode({
                        'message': 'Lot 1 corrigé sans page "/" redondante.',
                        'vibe': {
                          'components': {
                            'mainLayout': {
                              'type': 'layout',
                              'slotLabels': {'home-title': 'Titre accueil'},
                              'placements': {
                                'center': [
                                  {
                                    'id': 'home-title',
                                    'type': 'registry:Value',
                                  },
                                ],
                              },
                            },
                            'home-title': {
                              'type': 'value',
                              'text': 'Bienvenue',
                            },
                          },
                          'usages': {
                            'home-title': {
                              'kind': 'explanation',
                              'translationKey': 'welcomeTitle',
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
          'Crée un CRM.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(callIndex, 1);
        expect(prompts[0], contains('Routes codées existantes'));
        expect(prompts[0], contains('["/"]'));

        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await tester.pumpAndSettle();

        expect(callIndex, 3);
        expect(prompts[1], contains('Routes codées existantes'));
        expect(prompts[2], contains('page-home'));
        expect(prompts[2], contains('root'));
        expect(appearance.value.pageCatalog.pages, isEmpty);
        expect(
          appearance.value.valueComponent('home-title').initialText,
          'Bienvenue',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'émet des traces console détaillées lors d’un appel IA de patch de composant (scope, preview, outils, diff et post-rendu)',
      (tester) async {
        final logs = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        addTearDown(() => debugPrint = previousDebugPrint);

        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(
          Appearance(
            components: {
              'mainLayout': const SuperLayoutConfig(
                placements: {
                  SuperLayoutZone.center: ['card-title'],
                },
                slotTypes: {'card-title': 'registry:Value'},
              ),
              'card-title': const SuperValueConfig(initialText: 'Ancien titre'),
            },
          ),
        );
        registry.bindAppearance(appearance);
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final customTools = VibeAppToolRegistry([
          VibeRegisteredTool(
            declaration: const VibeToolDeclaration(
              name: 'validate_or_list_icons',
              description: 'Valide les icônes',
              parametersSchema: {'type': 'object', 'properties': {}},
            ),
            handler: (call) async => VibeToolResult(
              callId: call.id,
              name: call.name,
              data: const {'ok': true, 'validCount': 1, 'invalidCount': 0},
            ),
          ),
        ]);

        var streamCall = 0;
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
                    toolRegistry: customTools,
                    scope: const VibeChatScope(
                      componentId: 'card-title',
                      label: 'Titre carte',
                    ),
                    initialQuestioningLevel: VibeQuestioningLevel.none,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (_) async => '',
                    streamGenerate:
                        (
                          prompt, {
                          systemInstruction,
                          staticGuide,
                          attachments = const [],
                          speedMode = VibeAiSpeedMode.fast,
                        }) async* {
                          streamCall++;
                          if (streamCall == 1) {
                            final toolReq = jsonEncode({
                              'message': 'Vérification icône…',
                              'toolCalls': [
                                {
                                  'id': 't1',
                                  'name': 'validate_or_list_icons',
                                  'arguments': {
                                    'icons': ['check'],
                                  },
                                },
                              ],
                              'vibe': null,
                            });
                            yield GeminiStreamEvent(
                              deltaText: toolReq,
                              accumulatedText: toolReq,
                              isDone: true,
                              usedContextCache: true,
                            );
                            return;
                          }
                          if (streamCall == 2) {
                            const chunk1 =
                                '{"message":"Titre mis à jour.","verifyRender":true,"vibe":{"components":{"card-title":{"type":"value","text":"Nouveau titre"}},';
                            const chunk2 =
                                '"styles":{"card-title":{"color":"#EEF2FF"}}}}';
                            yield const GeminiStreamEvent(
                              deltaText: chunk1,
                              accumulatedText: chunk1,
                              isDone: false,
                              usedContextCache: true,
                            );
                            await Future<void>.delayed(
                              const Duration(milliseconds: 20),
                            );
                            yield const GeminiStreamEvent(
                              deltaText: chunk2,
                              accumulatedText: '$chunk1$chunk2',
                              isDone: true,
                              usedContextCache: true,
                            );
                            return;
                          }
                          final verifyResp = jsonEncode({
                            'message': 'Rendu vérifié.',
                            'vibe': null,
                          });
                          yield GeminiStreamEvent(
                            deltaText: verifyResp,
                            accumulatedText: verifyResp,
                            isDone: true,
                            usedContextCache: true,
                          );
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
          'Change le titre en Nouveau titre',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await pumpRealAsync(
          tester,
          until: () => logs.any((l) => l.contains('Apparence mise à jour')),
        );
        await tester.pumpAndSettle();

        expect(
          appearance.value.valueComponent('card-title').initialText,
          'Nouveau titre',
        );
        final joined = logs.join('\n');
        expect(joined, contains('scope: "Titre carte" [card-title]'));
        expect(joined, contains('[Outil] validate_or_list_icons'));
        expect(joined, contains('[Vibe IA][Preview] Palier #'));
        expect(joined, contains('[Vibe IA][Tour] Patch à appliquer'));
        expect(joined, contains('Diff composants appliqué'));
        expect(joined, contains('~comp(1): [card-title]'));
        expect(joined, contains('styles(1): [card-title]'));
        expect(
          joined,
          contains('[PostVerify] Démarrage passe de vérification'),
        );
        expect(joined, contains('[PostVerify] Rendu conforme'));
      },
    );

    testWidgets(
      'annule un appel IA streaming en cours depuis le bouton de saisie, rollback la prévisualisation et permet de réessayer',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final completionController = VibeTaskCompletionController();
        addTearDown(completionController.dispose);
        final soundPlayer = _RecordingVibeSoundPlayer();

        var streamCallCount = 0;
        var firstStreamCancelled = false;
        late StreamController<GeminiStreamEvent> firstStreamController;

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
                    completionController: completionController,
                    soundPlayer: soundPlayer,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (_) async => fail('Should use streamGenerate'),
                    streamGenerate:
                        (
                          prompt, {
                          systemInstruction,
                          staticGuide,
                          attachments = const [],
                          speedMode = VibeAiSpeedMode.fast,
                        }) {
                          streamCallCount++;
                          if (streamCallCount == 1) {
                            firstStreamController =
                                StreamController<GeminiStreamEvent>(
                                  onCancel: () {
                                    firstStreamCancelled = true;
                                  },
                                );
                            return firstStreamController.stream;
                          }
                          final okPayload = jsonEncode({
                            'message': 'Titre appliqué après reprise.',
                            'vibe': {
                              'components': {
                                'mainLayout': {
                                  'type': 'layout',
                                  'placements': {
                                    'center': [
                                      {
                                        'id': 'retry-title',
                                        'type': 'registry:Value',
                                      },
                                    ],
                                  },
                                },
                                'retry-title': {
                                  'type': 'value',
                                  'text': 'Bonjour',
                                },
                              },
                            },
                          });
                          return Stream<GeminiStreamEvent>.value(
                            GeminiStreamEvent(
                              deltaText: okPayload,
                              accumulatedText: okPayload,
                              isDone: true,
                              usedContextCache: false,
                            ),
                          );
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
          'Ajoute un titre Bonjour',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pump();

        expect(find.byKey(const ValueKey('vibe-chat-cancel')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vibe-chat-streaming-cancel')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('vibe-chat-send')), findsNothing);

        // Envoie un aperçu partiel en direct qui devra être annulé (rollback).
        const partialChunk =
            '{"message":"Création en cours…","vibe":{"accent":"#EF4444","components":{"mainLayout":{"type":"layout","placements":{"center":[{"id":"temp-title","type":"registry:Value"}]}},"temp-title":{"type":"value","text":"Temporaire"}},';
        firstStreamController.add(
          const GeminiStreamEvent(
            deltaText: partialChunk,
            accumulatedText: partialChunk,
            isDone: false,
            usedContextCache: false,
          ),
        );
        await tester.pump();
        expect(appearance.value.components.containsKey('temp-title'), isTrue);

        // Clique sur le bouton d'annulation dans la barre de saisie.
        await tester.tap(find.byKey(const ValueKey('vibe-chat-cancel')));
        await tester.pumpAndSettle();

        expect(firstStreamCancelled, isTrue);
        expect(appearance.value.components.containsKey('temp-title'), isFalse);
        expect(find.byKey(const ValueKey('vibe-chat-send')), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-chat-cancel')), findsNothing);
        expect(find.text('Appel IA annulé.'), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-message-retry')), findsOneWidget);
        expect(soundPlayer.outcomes, isEmpty);

        // Relance le tour annulé via « Réessayer ».
        await tester.tap(find.byKey(const ValueKey('vibe-message-retry')));
        await tester.pumpAndSettle();

        expect(streamCallCount, 2);
        expect(
          appearance.value.valueComponent('retry-title').initialText,
          'Bonjour',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'annule un appel IA non-streaming en attente depuis la bulle ou la touche Échap sans attendre la réponse tardive',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        final pendingResponse = Completer<String>();
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
                    generate: (_) => pendingResponse.future,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Appel bloqué',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('vibe-chat-streaming-cancel')),
          findsOneWidget,
        );

        // Annulation via le bouton de la bulle de streaming.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-streaming-cancel')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Appel IA annulé.'), findsOneWidget);
        expect(find.byKey(const ValueKey('vibe-chat-send')), findsOneWidget);

        // Une réponse tardive ne doit ni muter l'apparence ni provoquer d'erreur.
        pendingResponse.complete(
          jsonEncode({
            'message': 'Réponse tardive',
            'vibe': {'accent': '#EF4444'},
          }),
        );
        await tester.pumpAndSettle();
        expect(appearance.value.accent, isNot(const Color(0xFFEF4444)));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'annule un lot en cours d’un plan via le bouton du chat, conserve les lots terminés et permet la reprise partielle',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        var callIndex = 0;
        var lot2Cancelled = false;
        late StreamController<GeminiStreamEvent> lot2Controller;

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
                    initialPlanMode: true,
                    initialQuestioningLevel: VibeQuestioningLevel.none,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (_) async => fail('Should use streamGenerate'),
                    streamGenerate:
                        (
                          prompt, {
                          systemInstruction,
                          staticGuide,
                          attachments = const [],
                          speedMode = VibeAiSpeedMode.fast,
                        }) {
                          callIndex++;
                          if (callIndex == 1) {
                            final planJson = jsonEncode({
                              'message': 'Plan prêt.',
                              'plan': {
                                'title': 'Plan 2 lots',
                                'lots': [
                                  {
                                    'id': 'lot-1',
                                    'title': 'Lot 1',
                                    'description': 'Ajoute lot1-val',
                                  },
                                  {
                                    'id': 'lot-2',
                                    'title': 'Lot 2',
                                    'description': 'Ajoute lot2-val',
                                  },
                                ],
                              },
                              'vibe': null,
                            });
                            return Stream<GeminiStreamEvent>.value(
                              GeminiStreamEvent(
                                deltaText: planJson,
                                accumulatedText: planJson,
                                isDone: true,
                                usedContextCache: false,
                              ),
                            );
                          }
                          if (callIndex == 2) {
                            final lot1Json = jsonEncode({
                              'message': 'Lot 1 appliqué.',
                              'vibe': {
                                'components': {
                                  'mainLayout': {
                                    'type': 'layout',
                                    'placements': {
                                      'center': [
                                        {
                                          'id': 'lot1-val',
                                          'type': 'registry:Value',
                                        },
                                      ],
                                    },
                                  },
                                  'lot1-val': {
                                    'type': 'value',
                                    'text': 'Lot 1 OK',
                                  },
                                },
                              },
                            });
                            return Stream<GeminiStreamEvent>.value(
                              GeminiStreamEvent(
                                deltaText: lot1Json,
                                accumulatedText: lot1Json,
                                isDone: true,
                                usedContextCache: false,
                              ),
                            );
                          }
                          if (callIndex == 3) {
                            lot2Controller =
                                StreamController<GeminiStreamEvent>(
                                  onCancel: () {
                                    lot2Cancelled = true;
                                  },
                                );
                            return lot2Controller.stream;
                          }
                          final lot2Json = jsonEncode({
                            'message': 'Lot 2 repris et appliqué.',
                            'vibe': {
                              'components': {
                                'mainLayout': {
                                  'type': 'layout',
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
                                'lot2-val': {
                                  'type': 'value',
                                  'text': 'Lot 2 OK',
                                },
                              },
                            },
                          });
                          return Stream<GeminiStreamEvent>.value(
                            GeminiStreamEvent(
                              deltaText: lot2Json,
                              accumulatedText: lot2Json,
                              isDone: true,
                              usedContextCache: false,
                            ),
                          );
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
          'Construis un écran en 2 lots',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        await tester.pump();
        await tester.pump();

        // Lot 1 est terminé et Lot 2 attend le flux IA.
        expect(
          appearance.value.valueComponent('lot1-val').initialText,
          'Lot 1 OK',
        );
        expect(find.byKey(const ValueKey('vibe-chat-cancel')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('vibe-chat-cancel')));
        await tester.pumpAndSettle();

        expect(lot2Cancelled, isTrue);
        expect(
          appearance.value.valueComponent('lot1-val').initialText,
          'Lot 1 OK',
        );
        expect(appearance.value.components.containsKey('lot2-val'), isFalse);
        expect(
          find.text('Exécution du plan arrêtée (1/2 lots appliqués).'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vibe-plan-resume-partial')),
          findsOneWidget,
        );

        // Reprendre (partiel) termine uniquement le Lot 2.
        await tester.tap(find.byKey(const ValueKey('vibe-plan-resume-partial')));
        await tester.pumpAndSettle();

        expect(
          appearance.value.valueComponent('lot2-val').initialText,
          'Lot 2 OK',
        );
        expect(
          find.text('Plan terminé : 2/2 lots appliqués.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'fermer le chat pendant un appel IA en cours annule le flux sans erreur de ValueNotifier disposé',
      (tester) async {
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(registry.unbindAppearance);
        addTearDown(appearance.dispose);

        var streamCancelled = false;
        final controller = StreamController<GeminiStreamEvent>(
          onCancel: () {
            streamCancelled = true;
          },
        );

        var closed = false;
        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(
                body: DefaultAssetBundle(
                  bundle: _GuideBundle(),
                  child: StatefulBuilder(
                    builder: (context, setHostState) => closed
                        ? const SizedBox.shrink()
                        : VibeChatDialog(
                            controller: appearance,
                            registry: registry,
                            codec: const AppearanceCodec(),
                            initialQuestioningLevel: VibeQuestioningLevel.none,
                            onClose: () => setHostState(() => closed = true),
                            onDrag: (_) {},
                            generate: (_) async =>
                                fail('Should use streamGenerate'),
                            streamGenerate:
                                (
                                  prompt, {
                                  systemInstruction,
                                  staticGuide,
                                  attachments = const [],
                                  speedMode = VibeAiSpeedMode.fast,
                                }) => controller.stream,
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
          'Génère un écran',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('vibe-chat-close')));
        await tester.pumpAndSettle();

        expect(closed, isTrue);
        expect(streamCancelled, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _RecordingVibeSoundPlayer extends VibeTaskSoundPlayer {
  final List<VibeTaskOutcome> outcomes = <VibeTaskOutcome>[];

  @override
  Future<void> play(VibeTaskOutcome outcome) async {
    outcomes.add(outcome);
  }
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
