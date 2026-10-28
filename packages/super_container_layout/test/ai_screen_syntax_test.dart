import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  group('AI JSON primitives (JsonColor, JsonDimension, JsonComponentType)', () {
    test(
      'JsonColor parses hex formats and formats back to #RRGGBB / #AARRGGBB',
      () {
        expect(JsonColor.parse('#5268D9'), const Color(0xFF5268D9));
        expect(JsonColor.parse('#80FFFFFF'), const Color(0x80FFFFFF));
        expect(JsonColor.parse('#FFF'), const Color(0xFFFFFFFF));
        expect(JsonColor.parse('#8FFF'), const Color(0x88FFFFFF));
        expect(JsonColor.parse('0xFF123456'), const Color(0xFF123456));
        expect(JsonColor.parse(0xFF5268D9), const Color(0xFF5268D9));
        expect(JsonColor.toHex(const Color(0xFF5268D9)), '#5268D9');
        expect(JsonColor.toHex(const Color(0x80FFFFFF)), '#80FFFFFF');
        expect(() => JsonColor.parse('not-a-color'), throwsFormatException);
      },
    );

    test('SlotDimension accepts numbers, px/% strings and maps', () {
      expect(
        SlotDimension.fromJson(64),
        const SlotDimension(64, SlotSizeUnit.pixels),
      );
      expect(
        SlotDimension.fromJson('240px'),
        const SlotDimension(240, SlotSizeUnit.pixels),
      );
      expect(
        SlotDimension.fromJson('50%'),
        const SlotDimension(50, SlotSizeUnit.percent),
      );
      expect(
        JsonDimension.format(const SlotDimension(64, SlotSizeUnit.pixels)),
        '64px',
      );
      expect(
        JsonDimension.format(const SlotDimension(50, SlotSizeUnit.percent)),
        '50%',
      );
    });

    test('JsonTextBinding accepts compact path strings and repoId:path', () {
      const repoId = '0123456789abcdef0123456789abcdef';
      final inherited = JsonTextBinding.fromJson('clients[?].nom');
      expect(inherited.repositoryId, isNull);
      expect(inherited.path, 'clients[?].nom');
      expect(inherited.toCompactJson(), 'clients[?].nom');

      final explicit = JsonTextBinding.fromJson('$repoId:clients[?].email');
      expect(explicit.repositoryId, repoId);
      expect(explicit.path, 'clients[?].email');
    });
  });

  group('GenUI Flat Modeling & Incremental Surface Updates (applyVibe)', () {
    test('compiles a full flat GenUI screen and round-trips via exportAi', () {
      const repoId = '0123456789abcdef0123456789abcdef';
      final aiJson = jsonEncode({
        'version': 1,
        'mode': 'dark',
        'accent': '#5268D9',
        'styles': {
          'background': {'color': '#171A23', 'padding': 12},
          'list-clients': {
            'color': '#FFFFFF',
            'radius': 10,
            'padding': 10,
            'hoverEffect': true,
          },
          'card-detail': {
            'color': '#FFFFFF',
            'radius': 16,
            'padding': 20,
            'elevation': 3,
          },
        },
        'components': {
          'root': {
            'type': 'native',
            'regions': {'appBar': true, 'body': true},
            'placements': {
              'appBar': [
                {'id': 'main-appbar', 'type': 'registry:ApplicationBar'},
              ],
              'body': [
                {'id': 'scaffold:body', 'type': 'scaffold:body'},
              ],
            },
          },
          'main-appbar': {
            'type': 'native',
            'regions': {'title': true},
            'placements': {
              'title': [
                {'id': 'app-title', 'type': 'registry:Value'},
              ],
            },
          },
          'app-title': {
            'type': 'value',
            'text': 'Gestion Clients',
            'fontSize': 18,
            'fontWeight': 'semibold',
          },
          'contA': {
            'type': 'layout',
            'west': true,
            'westSize': 260,
            'resizeSides': true,
            'placements': {
              'west': [
                {'id': 'list-clients', 'type': 'registry:ListView'},
              ],
              'center': [
                {'id': 'card-detail', 'type': 'registry:Card'},
              ],
            },
          },
          'list-clients': {
            'type': 'list',
            'binding': {'repositoryId': repoId, 'path': 'clients'},
            'itemExtent': 56,
            'spacing': 8,
            'allowAdd': true,
            'template': {
              'placements': {
                'center': [
                  {'id': 'row-nom', 'type': 'registry:Value'},
                ],
              },
            },
          },
          'row-nom': {'type': 'value', 'binding': 'clients[?].nom'},
          'card-detail': {
            'type': 'native',
            'regions': {'child': true},
            'placements': {
              'child': [
                {'id': 'layout-form', 'type': 'registry:Layout'},
              ],
            },
          },
          'layout-form': {
            'type': 'layout',
            'slotSizeConstraints': {
              'input-nom': {'preferredHeight': '64px', 'padding': 8},
            },
            'placements': {
              'center': [
                {'id': 'input-nom', 'type': 'registry:Value'},
              ],
            },
          },
          'input-nom': {
            'type': 'value',
            'mode': 'input',
            'label': 'Nom complet',
            'binding': {'repositoryId': repoId, 'path': 'clients[?].nom'},
          },
        },
      });

      final imported = AppearanceTransfer.import(Appearance(), aiJson, {
        TransferGroup.styles,
        TransferGroup.layouts,
      });

      expect(imported.mode, ThemeMode.dark);
      expect(imported.accent, const Color(0xFF5268D9));
      expect(imported.backgroundStyle.color, const Color(0xFF171A23));
      expect(imported.nativeComponent('root').slotsOf('appBar'), [
        'main-appbar',
      ]);
      expect(imported.nativeComponent('root').slotsOf('body'), [
        'scaffold:body',
      ]);
      expect(imported.nativeComponent('main-appbar').slotsOf('title'), [
        'app-title',
      ]);
      expect(
        imported.valueComponent('app-title').initialText,
        'Gestion Clients',
      );

      final contA = imported.layout('contA');
      expect(contA.west, isTrue);
      expect(contA.north, isFalse);
      expect(contA.westSize, 260);
      expect(contA.placementsOf(SuperLayoutZone.west), ['list-clients']);
      expect(contA.placementsOf(SuperLayoutZone.center), ['card-detail']);

      expect(imported.listComponent('list-clients').allowAdd, isTrue);
      expect(imported.style('list-clients').radius, 10);
      expect(
        imported.layout('list-clients').placementsOf(SuperLayoutZone.center),
        ['row-nom'],
      );
      expect(
        imported.valueComponent('row-nom').binding,
        const JsonTextBinding(path: 'clients[?].nom'),
      );

      expect(imported.style('card-detail').radius, 16);
      expect(imported.nativeComponent('card-detail').slotsOf('child'), [
        'layout-form',
      ]);
      expect(
        imported
            .layout('layout-form')
            .slotSizeConstraints['input-nom']!
            .preferredHeight,
        const SlotDimension(64, SlotSizeUnit.pixels),
      );

      final aiExported = AppearanceTransfer.export(imported, const {
        TransferGroup.styles,
        TransferGroup.layouts,
      });
      final decodedExport = jsonDecode(aiExported) as Map<String, dynamic>;
      final exportedData = decodedExport['data'] as Map<String, dynamic>;
      expect(exportedData, contains('components'));

      final reimported = AppearanceTransfer.import(Appearance(), aiExported, {
        TransferGroup.styles,
        TransferGroup.layouts,
      });
      expect(
        AppearanceStore.encode(reimported),
        AppearanceStore.encode(imported),
      );
    });

    test('patch updates list template and preserves existing settings', () {
      final current = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'components': {
            'list-b': {
              'type': 'list',
              'binding': 'b',
              'spacing': 8,
              'template': {
                'westSize': 120,
                'placements': {
                  'center': [
                    {'id': 'item-b-value', 'type': 'registry:Value'},
                  ],
                },
              },
            },
            'item-b-value': {
              'type': 'value',
              'binding': 'b[?].c',
              'fontSize': 20,
            },
          },
        }),
      );
      final updated = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'components': {
            'list-b': {
              'template': {
                'east': true,
                'autoSides': ['east'],
                'placements': {
                  'center': [
                    {'id': 'item-b-value', 'type': 'registry:Value'},
                  ],
                  'east': [
                    {'id': 'item-b-text-a', 'type': 'registry:Value'},
                  ],
                },
              },
            },
            'item-b-value': {'initialText': 'Élément'},
            'item-b-text-a': {'type': 'value', 'text': 'text A'},
          },
        }),
      );
      final template = updated.layout('list-b');
      expect(template.east, isTrue);
      expect(template.autoSides, contains(SuperLayoutZone.east));
      expect(template.westSize, 120);
      expect(template.placementsOf(SuperLayoutZone.center), ['item-b-value']);
      expect(template.placementsOf(SuperLayoutZone.east), ['item-b-text-a']);
      expect(updated.valueComponent('item-b-text-a').initialText, 'text A');
      expect(updated.valueComponent('item-b-value').initialText, 'Élément');
      expect(updated.valueComponent('item-b-value').fontSize, 20);
      expect(updated.valueComponent('item-b-value').binding?.path, 'b[?].c');

      final combined = AppearanceTransfer.applyVibe(
        updated,
        jsonEncode({
          'components': {
            'list-b': {
              'spacing': 12,
              'row': {'eastSize': 100},
            },
          },
        }),
      );
      expect(combined.listComponent('list-b').spacing, 12);
      expect(combined.layout('list-b').eastSize, 100);
      expect(
        () => AppearanceTransfer.applyVibe(
          current,
          '{"components":{"list-b":{"template":42}}}',
        ),
        throwsFormatException,
      );
    });

    test('builds, patches and removes components step-by-step via applyVibe', () {
      var current = Appearance();

      // Étape 1 : Créer la structure de base avec un titre au nord
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'components': {
            'contA': {
              'type': 'layout',
              'north': true,
              'placements': {
                'north': [
                  {'id': 'header-title', 'type': 'registry:Value'},
                ],
              },
            },
            'header-title': {
              'type': 'value',
              'text': 'Tableau de bord',
              'fontSize': 22,
              'fontWeight': 'bold',
            },
          },
        }),
      );
      expect(current.layout('contA').north, isTrue);
      expect(
        current.valueComponent('header-title').initialText,
        'Tableau de bord',
      );

      // Étape 2 : Ajouter une Card contenant un champ de saisie dans `center`
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'styles': {
            'card-profile': {'color': '#FFFFFF', 'radius': 12, 'padding': 16},
          },
          'components': {
            'contA': {
              'placements': {
                'north': [
                  {'id': 'header-title', 'type': 'registry:Value'},
                ],
                'center': [
                  {'id': 'card-profile', 'type': 'registry:Card'},
                ],
              },
            },
            'card-profile': {
              'type': 'native',
              'regions': {'child': true},
              'placements': {
                'child': [
                  {'id': 'input-username', 'type': 'registry:Value'},
                ],
              },
            },
            'input-username': {
              'type': 'value',
              'mode': 'input',
              'label': 'Identifiant',
              'placeholder': 'Votre pseudo',
            },
          },
        }),
      );
      expect(current.layout('contA').placementsOf(SuperLayoutZone.north), [
        'header-title',
      ]);
      expect(current.layout('contA').placementsOf(SuperLayoutZone.center), [
        'card-profile',
      ]);
      expect(current.style('card-profile').radius, 12);
      expect(current.valueComponent('input-username').label, 'Identifiant');

      // Étape 3 : Patcher uniquement le style de la carte et le texte du titre
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'styles': {
            'card-profile': {'radius': 24, 'elevation': 6},
          },
          'components': {
            'header-title': {'text': 'Mon Profil', 'color': '#5268D9'},
          },
        }),
      );
      expect(current.style('card-profile').radius, 24);
      expect(current.style('card-profile').padding, 16);
      expect(current.valueComponent('header-title').initialText, 'Mon Profil');
      expect(current.valueComponent('header-title').fontSize, 22);

      // Étape 4 : Supprimer `card-profile` en le passant à `null`
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'components': {'card-profile': null},
        }),
      );
      expect(
        current.layout('contA').placementsOf(SuperLayoutZone.center),
        isEmpty,
      );
      expect(current.styles.containsKey('card-profile'), isFalse);
      expect(current.components.containsKey('card-profile'), isFalse);
    });

    test('attaches direct slotSizeConstraints on a child component to its parent container', () {
      final updated = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'components': {
            'main-appbar': {
              'type': 'native',
              'regions': {'title': true},
              'placements': {
                'title': [
                  {'id': 'logo-illicado', 'type': 'registry:Card'},
                ],
              },
            },
            'logo-illicado': {
              'type': 'native',
              'regions': <String, Object?>{},
              'slotSizeConstraints': {
                'preferredWidth': '110px',
                'preferredHeight': '40px',
              },
              'placements': <String, Object?>{},
            },
          },
        }),
      );

      expect(updated.components.containsKey('logo-illicado'), isTrue);
      expect(
        updated.nativeComponent('logo-illicado').slotSizeConstraints,
        isEmpty,
      );
      final parentConstraints = updated
          .nativeComponent('main-appbar')
          .slotSizeConstraints['logo-illicado'];
      expect(parentConstraints, isNotNull);
      expect(
        parentConstraints!.preferredWidth,
        const SlotDimension(110, SlotSizeUnit.pixels),
      );
      expect(
        parentConstraints.preferredHeight,
        const SlotDimension(40, SlotSizeUnit.pixels),
      );
    });

    test(
      'filterPatchToScope restricts edits to a target component subtree and strips out-of-scope changes',
      () {
        final initial = AppearanceTransfer.applyVibe(
          Appearance(),
          jsonEncode({
            'styles': {
              'background': {'color': '#101418'},
              'card-left': {'color': '#FFFFFF', 'radius': 8},
              'card-right': {'color': '#FFFFFF', 'radius': 8},
            },
            'components': {
              'root-layout': {
                'type': 'layout',
                'west': true,
                'westSize': 220,
                'placements': {
                  'west': [
                    {'id': 'card-left', 'type': 'registry:Card'},
                  ],
                  'center': [
                    {'id': 'card-right', 'type': 'registry:Card'},
                  ],
                },
              },
              'card-left': {
                'type': 'native',
                'regions': {'child': true},
                'placements': {
                  'child': [
                    {'id': 'left-title', 'type': 'registry:Value'},
                  ],
                },
              },
              'left-title': {'type': 'value', 'text': 'Menu gauche'},
              'card-right': {
                'type': 'native',
                'regions': {'child': true},
                'placements': {
                  'child': [
                    {'id': 'right-title', 'type': 'registry:Value'},
                  ],
                },
              },
              'right-title': {'type': 'value', 'text': 'Contenu principal'},
            },
          }),
        );

        const scope = VibeChatScope(
          componentId: 'card-right',
          label: 'Card',
        );

        final aiPatch = <String, dynamic>{
          'mode': 'dark',
          'accent': '#FF0000',
          'pageCatalog': {
            'pages': [
              {'id': 'rogue-page', 'name': 'Rogue', 'path': '/rogue'},
            ],
          },
          'styles': {
            'background': {'color': '#FF00FF'},
            'card-left': {'radius': 30},
            'card-right': {'radius': 20, 'padding': 16},
          },
          'components': {
            'left-title': {'text': 'Piraté'},
            'card-right': {
              'type': 'native',
              'regions': {'child': true},
              'placements': {
                'child': [
                  {'id': 'right-layout', 'type': 'registry:Layout'},
                ],
              },
            },
            'right-layout': {
              'type': 'layout',
              'placements': {
                'center': [
                  {'id': 'right-title', 'type': 'registry:Value'},
                  {'id': 'right-sub', 'type': 'registry:Value'},
                ],
              },
            },
            'right-title': {'text': 'Contenu mis à jour'},
            'right-sub': {'type': 'value', 'text': 'Sous-titre ajouté'},
          },
        };

        final filtered = VibeChatDialog.filterPatchToScope(
          initial,
          aiPatch,
          scope,
        );
        final updated = AppearanceTransfer.applyVibe(
          initial,
          jsonEncode(filtered),
        );

        // Out-of-scope global properties, sibling card, and parent layout stay untouched
        expect(updated.mode, initial.mode);
        expect(updated.accent, initial.accent);
        expect(updated.pageCatalog.pages, isEmpty);
        expect(updated.backgroundStyle.color, const Color(0xFF101418));
        expect(updated.style('card-left').radius, 8);
        expect(updated.valueComponent('left-title').initialText, 'Menu gauche');
        expect(
          updated.layout('root-layout').placementsOf(SuperLayoutZone.west),
          ['card-left'],
        );

        // In-scope component (card-right) and its new/existing children are updated
        expect(updated.style('card-right').radius, 20);
        expect(updated.style('card-right').padding, 16);
        expect(updated.nativeComponent('card-right').slotsOf('child'), [
          'right-layout',
        ]);
        expect(
          updated.layout('right-layout').placementsOf(SuperLayoutZone.center),
          ['right-title', 'right-sub'],
        );
        expect(
          updated.valueComponent('right-title').initialText,
          'Contenu mis à jour',
        );
        expect(
          updated.valueComponent('right-sub').initialText,
          'Sous-titre ajouté',
        );
      },
    );

    test(
      'filterPatchToScope on a specific layout zone preserves all other zones of the same container',
      () {
        final initial = AppearanceTransfer.applyVibe(
          Appearance(),
          jsonEncode({
            'components': {
              'mainLayout': {
                'type': 'layout',
                'north': true,
                'northSize': 70,
                'placements': {
                  'north': [
                    {'id': 'header-val', 'type': 'registry:Value'},
                  ],
                  'center': [
                    {'id': 'center-val', 'type': 'registry:Value'},
                  ],
                },
              },
              'header-val': {'type': 'value', 'text': 'En-tête'},
              'center-val': {'type': 'value', 'text': 'Centre intact'},
            },
          }),
        );

        const westScope = VibeChatScope(
          componentId: 'mainLayout',
          label: 'Layout',
          zoneId: 'west',
          zoneLabel: 'Ouest',
        );

        final aiPatch = <String, dynamic>{
          'components': {
            'mainLayout': {
              'northSize': 200,
              'west': true,
              'westSize': 260,
              'placements': {
                'north': <Object?>[],
                'center': <Object?>[],
                'west': [
                  {'id': 'west-nav', 'type': 'registry:Value'},
                ],
              },
            },
            'header-val': {'text': 'Modifié hors zone'},
            'west-nav': {'type': 'value', 'text': 'Navigation Ouest'},
          },
        };

        final filtered = VibeChatDialog.filterPatchToScope(
          initial,
          aiPatch,
          westScope,
        );
        final updated = AppearanceTransfer.applyVibe(
          initial,
          jsonEncode(filtered),
        );

        final layout = updated.layout('mainLayout');
        // North and Center zones are preserved intact
        expect(layout.north, isTrue);
        expect(layout.northSize, 70);
        expect(layout.placementsOf(SuperLayoutZone.north), ['header-val']);
        expect(layout.placementsOf(SuperLayoutZone.center), ['center-val']);
        expect(updated.valueComponent('header-val').initialText, 'En-tête');
        expect(
          updated.valueComponent('center-val').initialText,
          'Centre intact',
        );

        // West zone is enabled, sized, and populated
        expect(layout.west, isTrue);
        expect(layout.westSize, 260);
        expect(layout.placementsOf(SuperLayoutZone.west), ['west-nav']);
        expect(
          updated.valueComponent('west-nav').initialText,
          'Navigation Ouest',
        );
      },
    );
  });
}
