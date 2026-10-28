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
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';
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
