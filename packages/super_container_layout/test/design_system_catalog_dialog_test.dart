import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/appearance/appearance_store.dart';
import 'package:super_container_layout/services/appearance/appearance_transfer.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/appearance/appearance_scope.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';
import 'package:super_container_layout/widgets/editing/history/editor_history.dart';
import 'package:super_container_layout/widgets/editing/overlay/style_edit_banner.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';

const String _kLinearDesignMd = '''
---
name: Linear
slug: linear
category: productivity-saas
mode: dark
accent: "#5E6AD2"
---

# Linear Design System

## Visual Theme & Atmosphere
Signature #5E6AD2 graphite workspace with crisp 1px hairlines for high-velocity teams.
''';

const String _kImportedAcmeDesignMd = '''
---
version: alpha
name: Acme-design-analysis
description: "High-contrast dark cockpit with neon rose (#EC4899) accents."
---

# Acme-design-analysis

## Overview
High-contrast dark cockpit crafted for realtime operational telemetry.

## Colors
- **Page Background**: `#0B0C10`
- **Card Surface**: `#14161F`
- **Brand Primary**: `#EC4899`
- **Primary Text**: `#F9FAFB`
- **Muted Text**: `#9CA3AF`
- **Hairline Border**: `#262938`
''';

const String _kPastedNebulaDesignMd = '''
# Nebula Studio

## Overview
Dark cosmic workspace with violet interactive accents.

## Color Palette
- **Page Background**: #090A0F
- **Card Surface**: #131520
- **Brand Accent**: #8B5CF6
- **Primary Text**: #F8FAFC
- **Secondary Text**: #94A3B8
- **Divider Border**: #1E293B
''';

class _CatalogTestBundle extends CachingAssetBundle {
  _CatalogTestBundle([Map<String, String> extraAssets = const {}])
    : _assets = <String, String>{
        'SCREEN_JSON_AI_GUIDE.md': 'Guide JSON GenUI de test.',
        'SCREEN_DESIGN_AI_GUIDE.md':
            'Guide Design System Material 3 par défaut.',
        'assets/design_systems/linear.md': _kLinearDesignMd,
        ...extraAssets,
      };

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final content =
        _assets[key] ??
        (key.contains('design_systems/')
            ? '# Mock Preset\n\nContenu DESIGN.md simulé pour $key.'
            : null);
    if (content == null) {
      throw FlutterError('Asset "$key" introuvable dans _CatalogTestBundle.');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(DesignSystemCatalog.clearCache);

  group('DesignSystemCatalogDialog & VibeChatDialog integration', () {
    testWidgets(
      'ouvre la galerie sur desktop large (1280x860) et mobile étroit (420x700) sans overflow, filtre par catégorie/mode/recherche et inspecte le DESIGN.md',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);

        // 1. Viewport étroit (420x700) : aucun RenderFlex overflow à l'ouverture ni dans la galerie responsive.
        await tester.binding.setSurfaceSize(const Size(420, 700));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  onClose: () {},
                  onDrag: (_) {},
                  generate: (_) async => '{"message":"OK","vibe":null}',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Catalogue DESIGN.md'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-catalog-category-wrap')),
          findsOneWidget,
        );
        // Sur viewport étroit (420px), toutes les familles se répartissent sur plusieurs lignes
        // et restent intégralement visibles horizontalement sans scroll caché.
        final allChipRect = tester.getRect(
          find.byKey(const ValueKey('design-catalog-category-all')),
        );
        final lastChipRect = tester.getRect(
          find.byKey(const ValueKey('design-catalog-category-special-retro')),
        );
        expect(lastChipRect.top, greaterThan(allChipRect.top));
        for (final category in DesignSystemCategory.values) {
          if (category == DesignSystemCategory.custom) continue;
          final rect = tester.getRect(
            find.byKey(ValueKey('design-catalog-category-${category.id}')),
          );
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(420));
        }

        await tester.tap(find.byKey(const ValueKey('design-catalog-close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 2. Viewport desktop large (1280x860) : filtrage combiné et inspecteur DESIGN.md.
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(
          find.byKey(const ValueKey('design-system-card-default')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-linear')),
          findsOneWidget,
        );

        // Filtre par catégorie Fintech & Banque (4 systèmes : Stripe, Wise clairs ; Mercury, Revolut sombres).
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-category-fintech')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-system-card-default')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-linear')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-stripe')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-revolut')),
          findsOneWidget,
        );

        // Filtre par mode Sombre au sein de Fintech.
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-mode-dark')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-system-card-mercury')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-revolut')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-stripe')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-wise')),
          findsNothing,
        );

        // Filtre par mode Clair au sein de Fintech.
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-mode-light')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-system-card-stripe')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-wise')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-mercury')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-revolut')),
          findsNothing,
        );

        // Réinitialise catégorie + mode, puis filtre par recherche plein texte.
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-category-all')),
        );
        await tester.tap(find.byKey(const ValueKey('design-catalog-mode-all')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('design-catalog-search')),
          'neumorphism',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-system-card-neumorphic-soft')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-linear')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const ValueKey('design-catalog-search')),
          'Linear',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-system-card-linear')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-neumorphic-soft')),
          findsNothing,
        );

        // Ouvre l'inspecteur DESIGN.md de Linear, vérifie le Markdown nettoyé, puis revient à la galerie.
        await tester.tap(
          find.byKey(const ValueKey('design-system-inspect-linear')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-catalog-inspector')),
          findsOneWidget,
        );
        expect(find.textContaining('# Linear Design System'), findsOneWidget);
        expect(
          find.textContaining('Signature #5E6AD2 graphite workspace'),
          findsOneWidget,
        );
        expect(find.textContaining('slug: linear'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-inspector-back')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-catalog-inspector')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-linear')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'importe un fichier DESIGN.md externe, conserve le preset personnalisé à la réouverture et supporte le collage presse-papiers',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);

        final observedPresets = <DesignSystemPreset?>[];
        List<DesignSystemPreset> latestCustoms = const [];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  onClose: () {},
                  onDrag: (_) {},
                  onDesignSystemChanged: observedPresets.add,
                  onCustomDesignSystemsChanged: (list) => latestCustoms = list,
                  pickAttachments: () async => [
                    VibeChatAttachment.text(
                      name: 'acme-DESIGN.md',
                      content: _kImportedAcmeDesignMd,
                    ),
                  ],
                  readClipboardText: () async => _kPastedNebulaDesignMd,
                  generate: (_) async => '{"message":"OK","vibe":null}',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Import d'un fichier DESIGN.md (format getdesign.md) via 'Importer .md'.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-import-file')),
        );
        await tester.pumpAndSettle();

        expect(find.text('25 systèmes'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-catalog-category-custom')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-card-custom:acme')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-confirm-use')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Design : Acme'), findsOneWidget);
        expect(observedPresets.last?.id, 'custom:acme');
        expect(latestCustoms.map((p) => p.id), ['custom:acme']);
        expect(appearance.value.mode, ThemeMode.dark);
        expect(appearance.value.accent, const Color(0xFFEC4899));

        // 2. Réouverture du catalogue : le preset importé 'custom:acme' est préservé et sélectionné.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('25 systèmes'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-system-card-custom:acme')),
          findsOneWidget,
        );

        // 3. Collage depuis le presse-papiers via 'Coller DESIGN.md'.
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-paste-markdown')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-paste-clipboard-btn')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-paste-confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.text('26 systèmes'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-system-card-custom:nebula-studio')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-confirm-use')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Design : Nebula Studio'), findsOneWidget);
        expect(observedPresets.last?.id, 'custom:nebula-studio');
        expect(
          latestCustoms.map((p) => p.id),
          containsAll(<String>['custom:nebula-studio', 'custom:acme']),
        );
        expect(appearance.value.accent, const Color(0xFF8B5CF6));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'synchronise mode/accent avec Undo propre, injecte le DESIGN.md actif dans generate, puis réinitialise vers Material 3 (Défaut)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const initialAccent = Color(0xFF0EA5E9);
        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(
          Appearance(mode: ThemeMode.light, accent: initialAccent),
        );
        final editMode = ValueNotifier<bool>(true);
        final history = EditorHistoryController(
          appearance: appearance,
          editMode: editMode,
        );
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(history.dispose);
        addTearDown(editMode.dispose);
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);

        final capturedPrompts = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: EditorHistoryScope(
                  controller: history,
                  child: VibeChatDialog(
                    controller: appearance,
                    registry: registry,
                    codec: const AppearanceCodec(),
                    initialQuestioningLevel: VibeQuestioningLevel.none,
                    onClose: () {},
                    onDrag: (_) {},
                    generate: (prompt) async {
                      capturedPrompts.add(prompt);
                      return '{"message":"Réponse OK","vibe":null}';
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Design : Material 3 (Défaut)'), findsOneWidget);

        // Sélectionne Linear et confirme avec synchronisation immédiate activée.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('design-system-card-linear')),
        );
        await tester.pumpAndSettle();

        final syncCheckbox = tester.widget<Checkbox>(
          find.byKey(const ValueKey('design-catalog-sync-theme-checkbox')),
        );
        expect(syncCheckbox.value, isTrue);

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-confirm-use')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Design : Linear'), findsOneWidget);
        expect(appearance.value.mode, ThemeMode.dark);
        expect(appearance.value.accent, const Color(0xFF5E6AD2));
        expect(history.canUndo, isTrue);

        // Undo annule proprement la mutation immédiate de mode et accent.
        history.undo();
        await tester.pumpAndSettle();
        expect(appearance.value.mode, ThemeMode.light);
        expect(appearance.value.accent, initialAccent);

        // L'envoi d'un message injecte l'en-tête prioritaire et le contenu DESIGN.md de Linear.
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Crée une vue de suivi des tickets.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(capturedPrompts, hasLength(1));
        expect(
          capturedPrompts[0],
          contains(
            'SYSTÈME DE DESIGN ACTIF (Linear — PRIORITÉ ESTHÉTIQUE ABSOLUE)',
          ),
        );
        expect(
          capturedPrompts[0],
          contains('Signature #5E6AD2 graphite workspace'),
        );

        // Efface le système de design actif -> retour à Material 3 (Défaut).
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-clear-design-system')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Design : Material 3 (Défaut)'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vibe-chat-restyle-screen')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Ajoute un filtre par statut.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(capturedPrompts, hasLength(2));
        expect(capturedPrompts[1], isNot(contains('SYSTÈME DE DESIGN ACTIF')));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'le restylage en 1 clic (depuis le catalogue ou la barre du chat) court-circuite askUser même au niveau Approfondi et applique le patch',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        final baseAppearance = AppearanceTransfer.applyVibe(
          Appearance(mode: ThemeMode.light, accent: const Color(0xFF2563EB)),
          jsonEncode({
            'components': {
              'mainLayout': {
                'type': 'layout',
                'placements': {
                  'center': [
                    {'id': 'hero-title', 'type': 'registry:Value'},
                  ],
                },
              },
              'hero-title': {'type': 'value', 'text': 'Tableau de bord'},
            },
          }),
        );
        final appearance = ValueNotifier(baseAppearance);
        registry.bindAppearance(appearance);
        registry.layoutController('mainLayout');
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);

        final prompts = <String>[];
        var callCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  initialQuestioningLevel: VibeQuestioningLevel.thorough,
                  onClose: () {},
                  onDrag: (_) {},
                  generate: (prompt) async {
                    callCount++;
                    prompts.add(prompt);
                    if (callCount == 1) {
                      // Même si le modèle tente un askUser au niveau Approfondi, le tour de restylage le rejette !
                      return jsonEncode({
                        'message': 'Questions interdites pendant un restylage',
                        'askUser': {
                          'questions': [
                            {
                              'id': 'q1',
                              'title': 'Préférez-vous des cartes compactes ?',
                              'type': 'boolean',
                              'default': true,
                            },
                          ],
                        },
                        'vibe': null,
                      });
                    }
                    if (callCount == 2) {
                      return jsonEncode({
                        'message': 'Écran restylé selon Linear.',
                        'vibe': {
                          'mode': 'dark',
                          'accent': '#5E6AD2',
                          'styles': {
                            'background': {'color': '#08090A'},
                          },
                          'components': {
                            'hero-title': {
                              'type': 'value',
                              'text': 'Tableau de bord',
                              'color': '#F7F8F8',
                            },
                          },
                        },
                      });
                    }
                    return jsonEncode({
                      'message': 'Second restylage direct appliqué.',
                      'vibe': {
                        'styles': {
                          'background': {'color': '#111215'},
                        },
                      },
                    });
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. 'Appliquer et restyler' depuis le catalogue DESIGN.md.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('design-system-card-linear')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-confirm-restyle')),
        );
        await tester.pumpAndSettle();

        expect(callCount, 2);
        expect(prompts[0], contains('Ne pose pas de questionnaire "askUser"'));
        expect(prompts[0], contains('INTERDICTION d’utiliser "askUser"'));
        expect(find.byType(VibeAskUserCard), findsNothing);
        expect(appearance.value.mode, ThemeMode.dark);
        expect(appearance.value.accent, const Color(0xFF5E6AD2));
        expect(
          appearance.value.style('background').color,
          const Color(0xFF08090A),
        );
        expect(
          appearance.value.valueComponent('hero-title').color,
          const Color(0xFFF7F8F8),
        );

        // 2. Bouton 'Restyler' directement depuis la barre VibeDesignSystemBar.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-restyle-screen')),
        );
        await tester.pumpAndSettle();

        expect(callCount, 3);
        expect(prompts[2], contains('INTERDICTION d’utiliser "askUser"'));
        expect(
          appearance.value.style('background').color,
          const Color(0xFF111215),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'protège le thème global et les composants hors périmètre lorsqu’un VibeChatScope est actif',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const initialAccent = Color(0xFF0EA5E9);
        final registry = Registry()..bootstrap();
        final baseAppearance = AppearanceTransfer.applyVibe(
          Appearance(mode: ThemeMode.light, accent: initialAccent),
          jsonEncode({
            'styles': {
              'background': {'color': '#FFFFFF'},
              'scoped-card': {'color': '#F8FAFC', 'radius': 12},
            },
            'components': {
              'rootLayout': {
                'type': 'layout',
                'west': true,
                'westSize': 220,
                'placements': {
                  'west': [
                    {'id': 'sidebarLayout', 'type': 'registry:Layout'},
                  ],
                  'center': [
                    {'id': 'mainPanel', 'type': 'registry:Layout'},
                  ],
                },
              },
              'sidebarLayout': {
                'type': 'layout',
                'placements': {
                  'center': [
                    {'id': 'global-nav-title', 'type': 'registry:Value'},
                  ],
                },
              },
              'mainPanel': {
                'type': 'layout',
                'placements': {
                  'center': [
                    {'id': 'scoped-card', 'type': 'registry:Layout'},
                  ],
                },
              },
              'scoped-card': {
                'type': 'layout',
                'placements': {
                  'center': [
                    {'id': 'scoped-title', 'type': 'registry:Value'},
                  ],
                },
              },
              'global-nav-title': {
                'type': 'value',
                'text': 'Navigation Globale',
                'color': '#111827',
              },
              'scoped-title': {
                'type': 'value',
                'text': 'Section Ciblée',
                'color': '#334155',
              },
            },
          }),
        );

        final appearance = ValueNotifier(baseAppearance);
        registry.bindAppearance(appearance);
        registry.layoutController('rootLayout');
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);

        const activeScope = VibeChatScope(
          componentId: 'scoped-card',
          label: 'Carte Ciblée',
        );
        final capturedPrompts = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  scope: activeScope,
                  onClose: () {},
                  onDrag: (_) {},
                  generate: (prompt) async {
                    capturedPrompts.add(prompt);
                    // Simule une réponse IA qui tente aussi de modifier le thème global et un composant hors scope.
                    return jsonEncode({
                      'message': 'Carte restylée selon Linear.',
                      'vibe': {
                        'mode': 'dark',
                        'accent': '#5E6AD2',
                        'styles': {
                          'background': {'color': '#08090A'},
                          'scoped-card': {
                            'color': '#111215',
                            'radius': 8,
                            'borderWidth': 1,
                            'borderColor': '#23252A',
                          },
                        },
                        'components': {
                          'global-nav-title': {
                            'type': 'value',
                            'text': 'Navigation Piratée',
                            'color': '#FF0000',
                          },
                          'scoped-title': {
                            'type': 'value',
                            'text': 'Section Ciblée',
                            'color': '#F7F8F8',
                          },
                        },
                      },
                    });
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ouvre le catalogue avec un scope actif : la case de synchronisation globale est désactivée.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('design-system-card-linear')),
        );
        await tester.pumpAndSettle();

        final syncCheckbox = tester.widget<Checkbox>(
          find.byKey(const ValueKey('design-catalog-sync-theme-checkbox')),
        );
        expect(syncCheckbox.value, isFalse);
        expect(syncCheckbox.onChanged, isNull);
        expect(
          find.text('Désactivé lorsqu’un scope partiel est actif'),
          findsOneWidget,
        );

        // Confirme avec 'Utiliser pour le chat' -> ni mode ni accent global ne changent.
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-confirm-use')),
        );
        await tester.pumpAndSettle();

        expect(appearance.value.mode, ThemeMode.light);
        expect(appearance.value.accent, initialAccent);

        // Lance le restylage ciblé via 'Restyler' -> seul le sous-arbre du scope est modifié !
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-restyle-screen')),
        );
        await tester.pumpAndSettle();

        expect(capturedPrompts, hasLength(1));
        expect(
          capturedPrompts.single,
          contains('RESTYLAGE DU PÉRIMÈTRE "Carte Ciblée"'),
        );

        // Le thème global et la navigation hors scope sont intacts :
        expect(appearance.value.mode, ThemeMode.light);
        expect(appearance.value.accent, initialAccent);
        expect(
          appearance.value.style('background').color,
          const Color(0xFFFFFFFF),
        );
        expect(
          appearance.value.valueComponent('global-nav-title').initialText,
          'Navigation Globale',
        );
        expect(
          appearance.value.valueComponent('global-nav-title').color,
          const Color(0xFF111827),
        );

        // Le périmètre ciblé a bien reçu le restylage Linear :
        expect(
          appearance.value.style('scoped-card').color,
          const Color(0xFF111215),
        );
        expect(appearance.value.style('scoped-card').radius, 8);
        expect(
          appearance.value.valueComponent('scoped-title').color,
          const Color(0xFFF7F8F8),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ouvre le catalogue et ses sous-dialogues sans Navigator ancêtre (StyleEditBanner dans MaterialApp.builder)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final editMode = ValueNotifier<bool>(true);
        final appearance = ValueNotifier(Appearance());
        addTearDown(editMode.dispose);
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: _CatalogTestBundle(),
            child: StyleEditScope(
              controller: editMode,
              child: AppearanceScope(
                controller: appearance,
                child: AppearanceServicesScope(
                  codec: const AppearanceCodec(),
                  child: MaterialApp(
                    builder: (context, child) => Stack(
                      children: [
                        child!,
                        Positioned.fill(
                          child: StyleEditBanner(
                            aiResponseGenerator: (_) async =>
                                '{"message":"OK","vibe":null}',
                          ),
                        ),
                      ],
                    ),
                    home: const Scaffold(body: SizedBox.expand()),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ouvre le panneau Vibe IA depuis la bannière située au-dessus du Navigator.
        await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
        await tester.pumpAndSettle();

        // Ouvre la galerie DESIGN.md sans lever d'exception Navigator.of.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Catalogue DESIGN.md'), findsOneWidget);

        // Vérifie aussi que le sous-dialogue 'Coller DESIGN.md' s'ouvre et se referme au-dessus de la galerie.
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-paste-markdown')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-catalog-paste-input')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('design-catalog-paste-input')),
          _kPastedNebulaDesignMd,
        );
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-paste-confirm')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-system-card-custom:nebula-studio')),
          findsOneWidget,
        );

        // Valide la sélection -> la modale se referme et met à jour VibeChatDialog.
        await tester.tap(
          find.byKey(const ValueKey('design-catalog-confirm-use')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Catalogue DESIGN.md'), findsNothing);
        expect(find.text('Design : Nebula Studio'), findsOneWidget);
        expect(appearance.value.accent, const Color(0xFF8B5CF6));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'le bouton rapide « Générer DESIGN.md » sur une pièce jointe appelle register_design_system, ajoute le DESIGN.md au catalogue, l’active et le persiste sur disque',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tempDir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('vibe_gen_ds_'),
        ))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          });
        });
        final dsStore = CustomDesignSystemStore(tempDir);

        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);

        final capturedPrompts = <String>[];
        final capturedAttachments = <List<VibeChatAttachment>>[];
        final observedPresets = <DesignSystemPreset?>[];
        var latestCustoms = <DesignSystemPreset>[];
        var genCall = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  customDesignSystemStore: dsStore,
                  initialQuestioningLevel: VibeQuestioningLevel.none,
                  onClose: () {},
                  onDrag: (_) {},
                  onDesignSystemChanged: observedPresets.add,
                  onCustomDesignSystemsChanged: (list) => latestCustoms = list,
                  pickAttachments: () async => [
                    VibeChatAttachment.text(
                      name: 'aurora-theme.css',
                      content:
                          ':root { --bg: #0B1020; --card: #131B2E; --accent: #22D3EE; --text: #F8FAFC; }',
                    ),
                  ],
                  generate: (
                    String prompt, {
                    List<VibeChatAttachment> attachments = const [],
                  }) async {
                    genCall++;
                    capturedPrompts.add(prompt);
                    capturedAttachments.add(attachments);
                    if (genCall == 1) {
                      return jsonEncode({
                        'message': 'Extraction de la charte depuis aurora-theme.css…',
                        'toolCalls': [
                          {
                            'id': 'reg-ds-1',
                            'name': 'register_design_system',
                            'arguments': {
                              'name': 'Aurora Cyan',
                              'slug': 'aurora-cyan',
                              'category': 'ai-platforms',
                              'tagline': 'Cyan lumineux sur nuit abyssale',
                              'mode': 'dark',
                              'accent': '#22D3EE',
                              'canvasColor': '#0B1020',
                              'surfaceColor': '#131B2E',
                              'textColor': '#F8FAFC',
                              'mutedTextColor': '#94A3B8',
                              'borderColor': '#1E293B',
                              'cardRadius': 12,
                              'surfaceSystem': 'material',
                              'fontFamily': 'Inter',
                              'logo': '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#22D3EE"/></svg>',
                              'select': true,
                              'markdown': '''
## 1. Visual Theme & Atmosphere
Interface nocturne inspirée de `aurora-theme.css` avec accent cyan `#22D3EE`.

## 2. Color Palette & Roles
- Canvas `#0B1020`, Surface `#131B2E`, Accent `#22D3EE`
''',
                            },
                          },
                        ],
                        'vibe': null,
                      });
                    }
                    return jsonEncode({
                      'message':
                          'Design System « Aurora Cyan » généré, ajouté au catalogue et activé.',
                      'vibe': null,
                    });
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Avant d'ajouter une pièce jointe, le bouton rapide est masqué.
        expect(
          find.byKey(const ValueKey('vibe-chat-generate-design-md')),
          findsNothing,
        );

        // Ajoute la pièce jointe dans le chat.
        await tester.tap(find.byKey(const ValueKey('vibe-chat-attach')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('vibe-chat-generate-design-md')),
          findsOneWidget,
        );

        // Déclenche la génération de DESIGN.md en 1 clic.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-generate-design-md')),
        );
        await tester.pumpAndSettle();

        expect(genCall, 2);
        expect(
          capturedAttachments.first.map((a) => a.name),
          contains('aurora-theme.css'),
        );
        expect(
          capturedPrompts.first,
          contains('register_design_system'),
        );
        expect(
          capturedPrompts.first,
          contains('RÉCUPÉRER UN LOGO'),
        );
        expect(find.text('Design : Aurora Cyan'), findsOneWidget);
        expect(observedPresets.last?.id, 'custom:aurora-cyan');
        expect(observedPresets.last?.logo, contains('<svg'));
        expect(latestCustoms.map((p) => p.id), ['custom:aurora-cyan']);
        expect(
          find.text(
            'Design System « Aurora Cyan » généré, ajouté au catalogue et activé.',
          ),
          findsWidgets,
        );
        expect(
          find.text('1 outil utilisé : register_design_system'),
          findsOneWidget,
        );

        // Ouvre la galerie DESIGN.md : Aurora Cyan apparaît dans la liste des choix possibles.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('25 systèmes'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-system-card-custom:aurora-cyan')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-system-logo-custom:aurora-cyan')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('design-catalog-close')));
        await tester.pumpAndSettle();

        // Vérifie la persistance disque et le rechargement automatique dans une nouvelle instance de VibeChatDialog.
        final reloadedFromDisk = await dsStore.loadAll();
        expect(reloadedFromDisk, hasLength(1));
        expect(reloadedFromDisk.single.id, 'custom:aurora-cyan');

        var reloadedCustoms = <DesignSystemPreset>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: VibeChatDialog(
                  key: const ValueKey('reloaded-vibe-chat'),
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  customDesignSystemStore: dsStore,
                  onClose: () {},
                  onDrag: (_) {},
                  onCustomDesignSystemsChanged: (list) => reloadedCustoms = list,
                  generate: (_) async => '{"message":"OK","vibe":null}',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(reloadedCustoms.map((p) => p.id), ['custom:aurora-cyan']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'permet de supprimer un Design System importé depuis sa carte ou depuis l’inspecteur et le supprime du store disque',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tempDir = Directory.systemTemp.createTempSync('vibe_del_ds_');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final dsStore = CustomDesignSystemStore(tempDir);

        final acme = DesignMdParser.parseExternal(
          _kImportedAcmeDesignMd,
          fileName: 'acme-DESIGN.md',
        );
        final nebula = DesignMdParser.parseExternal(
          _kPastedNebulaDesignMd,
          fileName: 'nebula-DESIGN.md',
        );
        await dsStore.save(acme);
        await dsStore.save(nebula);

        final registry = Registry()..bootstrap();
        final appearance = ValueNotifier(Appearance());
        registry.bindAppearance(appearance);
        addTearDown(appearance.dispose);
        addTearDown(registry.unbindAppearance);

        final observedPresets = <DesignSystemPreset?>[];
        var latestCustoms = <DesignSystemPreset>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _CatalogTestBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  registry: registry,
                  codec: const AppearanceCodec(),
                  customDesignSystemStore: dsStore,
                  initialDesignSystem: acme,
                  customDesignSystems: [acme, nebula],
                  onClose: () {},
                  onDrag: (_) {},
                  onDesignSystemChanged: observedPresets.add,
                  onCustomDesignSystemsChanged: (list) => latestCustoms = list,
                  generate: (_) async => '{"message":"OK","vibe":null}',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Design : Acme'), findsOneWidget);

        // Ouvre le catalogue : 26 systèmes (24 intégrés + 2 importés).
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-design-system-button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('26 systèmes'), findsOneWidget);

        // Aucun bouton de suppression sur un préréglage intégré.
        expect(
          find.byKey(const ValueKey('design-system-delete-linear')),
          findsNothing,
        );

        // 1. Supprime 'custom:acme' (actuellement sélectionné) depuis sa carte.
        await tester.tap(
          find.byKey(const ValueKey('design-system-delete-custom:acme')),
        );
        await tester.pumpAndSettle();

        expect(find.text('25 systèmes'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-system-card-custom:acme')),
          findsNothing,
        );
        expect(latestCustoms.map((p) => p.id), ['custom:nebula-studio']);
        expect(observedPresets.last, isNull);

        // 2. Ouvre l'inspecteur sur 'custom:nebula-studio' et le supprime depuis l'inspecteur.
        await tester.tap(
          find.byKey(
            const ValueKey('design-system-inspect-custom:nebula-studio'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-catalog-inspector')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('design-catalog-inspector-delete')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('design-catalog-inspector')),
          findsNothing,
        );
        expect(find.text('24 systèmes'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey('design-system-card-custom:nebula-studio'),
          ),
          findsNothing,
        );
        expect(latestCustoms, isEmpty);

        // Même en fermant via la croix, la suppression reste effective et persistée.
        await tester.tap(find.byKey(const ValueKey('design-catalog-close')));
        await tester.pumpAndSettle();

        expect(find.text('Design : Material 3 (Défaut)'), findsOneWidget);
        final remainingOnDisk = await dsStore.loadAll();
        expect(remainingOnDisk, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
