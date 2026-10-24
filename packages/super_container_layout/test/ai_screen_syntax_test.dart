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

  group('1-Phase Hierarchical Screen Modeling (screens & inline nodes)', () {
    test('compiles a full nested screen in 1 phase and round-trips via exportAi', () {
      const repoId = '0123456789abcdef0123456789abcdef';
      final aiJson = jsonEncode({
        'mode': 'dark',
        'accent': '#5268D9',
        'styles': {
          'background': {'color': '#171A23', 'padding': 12},
        },
        'screens': {
          'root': {
            'appBar': {
              'type': 'ApplicationBar',
              'id': 'main-appbar',
              'title': {
                'type': 'Value',
                'id': 'app-title',
                'text': 'Gestion Clients',
                'fontSize': 18,
                'fontWeight': 'semibold',
              },
            },
            'body': {
              'type': 'Layout',
              'id': 'contA',
              'westSize': 260,
              'resizeSides': true,
              'zones': {
                'west': [
                  {
                    'type': 'ListView',
                    'id': 'list-clients',
                    'binding': {'repositoryId': repoId, 'path': 'clients'},
                    'itemExtent': 56,
                    'spacing': 8,
                    'allowAdd': true,
                    'style': {
                      'color': '#FFFFFF',
                      'radius': 10,
                      'padding': 10,
                      'hoverEffect': true,
                    },
                    'template': {
                      'zones': {
                        'center': [
                          {
                            'type': 'Value',
                            'id': 'row-nom',
                            'binding': 'clients[?].nom',
                          },
                        ],
                      },
                    },
                  },
                ],
                'center': [
                  {
                    'type': 'Card',
                    'id': 'card-detail',
                    'style': {
                      'color': '#FFFFFF',
                      'radius': 16,
                      'padding': 20,
                      'elevation': 3,
                    },
                    'child': {
                      'type': 'Layout',
                      'id': 'layout-form',
                      'zones': {
                        'center': [
                          {
                            'type': 'Value',
                            'id': 'input-nom',
                            'mode': 'input',
                            'label': 'Nom complet',
                            'size': {'preferredHeight': '64px', 'padding': 8},
                            'binding': {
                              'repositoryId': repoId,
                              'path': 'clients[?].nom',
                            },
                          },
                        ],
                      },
                    },
                  },
                ],
              },
            },
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

      // West side auto-enabled because `zones.west` has items
      final contA = imported.layout('contA');
      expect(contA.west, isTrue);
      expect(contA.north, isFalse);
      expect(contA.westSize, 260);
      expect(contA.placementsOf(SuperLayoutZone.west), ['list-clients']);
      expect(contA.placementsOf(SuperLayoutZone.center), ['card-detail']);

      // ListView extracted to listComponents, styles, and layouts
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

      // Card extracted to styles and nativeComponents, nested layout and input
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

      // Round-trip through standard AppearanceTransfer.export (which outputs AIJson directly)
      final aiExported = AppearanceTransfer.export(imported, const {
        TransferGroup.styles,
        TransferGroup.layouts,
      });
      final decodedExport = jsonDecode(aiExported) as Map<String, dynamic>;
      final exportedData = decodedExport['data'] as Map<String, dynamic>;
      expect(exportedData['accent'], '#5268D9');
      expect(exportedData, contains('screens'));
      expect(
        ((exportedData['screens'] as Map)['root'] as Map)['body'],
        isA<Map>(),
      );

      final reimported = AppearanceTransfer.import(Appearance(), aiExported, {
        TransferGroup.styles,
        TransferGroup.layouts,
      });
      expect(
        AppearanceStore.encode(reimported),
        AppearanceStore.encode(imported),
      );
    });
  });

  group('Vibe Mode (Step-by-step incremental modeling & ops)', () {
    test('patch compiles a list template and preserves existing settings', () {
      final current = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'screens': {
            'root': {
              'zones': {
                'center': [
                  {
                    'type': 'ListView',
                    'id': 'list-b',
                    'binding': 'b',
                    'spacing': 8,
                    'template': {
                      'westSize': 120,
                      'zones': {
                        'center': [
                          {
                            'type': 'Value',
                            'id': 'item-b-value',
                            'binding': 'b[?].c',
                            'fontSize': 20,
                          },
                        ],
                      },
                    },
                  },
                ],
              },
            },
          },
        }),
      );
      final updated = AppearanceTransfer.applyVibe(current, '''
{
  "ops": [
    {
      "op": "patch",
      "id": "list-b",
      "template": {
        "autoSides": ["east"],
        "zones": {
          "center": [
            {
              "type": "Value",
              "id": "item-b-value",
              "initialText": "Élément",
              "binding": "b[?].c"
            }
          ],
          "east": [
            {
              "type": "Value",
              "id": "item-b-text-a",
              "text": "text A"
            }
          ]
        }
      }
    }
  ]
}
''');
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
      expect(updated.listComponent('list-b'), current.listComponent('list-b'));

      final combined = AppearanceTransfer.applyVibe(
        updated,
        jsonEncode({
          'ops': [
            {
              'op': 'patch',
              'id': 'list-b',
              'list': {'spacing': 12},
              'row': {'eastSize': 100},
            },
          ],
        }),
      );
      expect(combined.listComponent('list-b').spacing, 12);
      expect(combined.layout('list-b').eastSize, 100);
      expect(
        () => AppearanceTransfer.applyVibe(
          current,
          '{"ops":[{"op":"patch","id":"list-b","template":42}]}',
        ),
        throwsFormatException,
      );
    });

    test('builds and refines a screen step-by-step using applyVibe and ops', () {
      var current = Appearance();

      // Étape 1 : Créer la structure de base avec un titre au nord
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'screens': {
            'root': {
              'body': {
                'type': 'Layout',
                'id': 'contA',
                'zones': {
                  'north': [
                    {
                      'type': 'Value',
                      'id': 'header-title',
                      'text': 'Tableau de bord',
                      'fontSize': 22,
                      'fontWeight': 'bold',
                    },
                  ],
                },
              },
            },
          },
        }),
      );
      expect(current.layout('contA').north, isTrue);
      expect(
        current.valueComponent('header-title').initialText,
        'Tableau de bord',
      );

      // Étape 2 : Ajouter une Card contenant un champ de saisie dans `center` via `ops.add`
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'ops': [
            {
              'op': 'add',
              'target': 'contA',
              'zone': 'center',
              'node': {
                'type': 'Card',
                'id': 'card-profile',
                'style': {'color': '#FFFFFF', 'radius': 12, 'padding': 16},
                'child': {
                  'type': 'Value',
                  'id': 'input-username',
                  'mode': 'input',
                  'label': 'Identifiant',
                  'placeholder': 'Votre pseudo',
                },
              },
            },
          ],
        }),
      );
      // Le titre au nord est toujours là !
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
          'ops': [
            {
              'op': 'patch',
              'id': 'card-profile',
              'style': {'radius': 24, 'elevation': 6},
            },
            {
              'op': 'patch',
              'id': 'header-title',
              'text': 'Mon Profil',
              'color': '#5268D9',
            },
          ],
        }),
      );
      expect(current.style('card-profile').radius, 24);
      expect(current.style('card-profile').padding, 16); // conservé !
      expect(current.valueComponent('header-title').initialText, 'Mon Profil');
      expect(current.valueComponent('header-title').fontSize, 22); // conservé !

      // Étape 4 : Déplacer `card-profile` vers `west` et ajouter une nouvelle page
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'ops': [
            {
              'op': 'move',
              'target': 'contA',
              'id': 'card-profile',
              'zone': 'west',
            },
            {
              'op': 'upsertPage',
              'id': 'page-settings',
              'name': 'Paramètres',
              'path': '/settings',
              'body': {
                'type': 'Layout',
                'id': 'layout-settings',
                'zones': {
                  'center': [
                    {
                      'type': 'Value',
                      'id': 'settings-toggle',
                      'mode': 'input',
                      'kind': 'switch',
                      'label': 'Notifications',
                      'value': true,
                    },
                  ],
                },
              },
            },
          ],
        }),
      );
      expect(current.layout('contA').west, isTrue);
      expect(current.layout('contA').placementsOf(SuperLayoutZone.west), [
        'card-profile',
      ]);
      expect(current.pageCatalog.pages.single.id, 'page-settings');
      expect(
        current.valueComponent('settings-toggle').kind,
        SuperValueKind.switchControl,
      );
      expect(current.valueComponent('settings-toggle').initialBool, isTrue);

      // Étape 5 : Supprimer `card-profile`
      current = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'ops': [
            {'op': 'remove', 'target': 'contA', 'id': 'card-profile'},
          ],
        }),
      );
      expect(
        current.layout('contA').placementsOf(SuperLayoutZone.west),
        isEmpty,
      );
      expect(current.styles.containsKey('card-profile'), isFalse);
    });
  });
}
