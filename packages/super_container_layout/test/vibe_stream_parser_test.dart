import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/ai/vibe_stream_parser.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/appearance/appearance_transfer.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_incremental_preview.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_context_menu.dart';

void main() {
  group('VibeIncrementalStreamParser', () {
    test(
      'décode caractère par caractère (chunks de 1 char) le champ "message" avec échappements JSON et paire de substitution UTF-16 coupée',
      () {
        const expectedMessage =
            'Ligne 1\nLigne 2\t"citation" \\ barre / accent éÉ fusée 🚀 fin!';
        const rawJson =
            '{"message":"Ligne 1\\nLigne 2\\t\\"citation\\" \\\\ barre \\/ accent \\u00e9\\u00C9 fusée \\uD83D\\uDE80 fin!","vibe":null}';

        expect(
          (jsonDecode(rawJson) as Map<String, dynamic>)['message'],
          expectedMessage,
        );

        final parser = VibeIncrementalStreamParser();
        expect(parser.current, VibeStreamSnapshot.empty);
        expect(parser.rawBuffer, isEmpty);

        final valueQuoteIndex = rawJson.indexOf(':"') + 1;
        var sawIncompleteAfterEscapedQuote = false;
        int? completedAtIndex;

        for (var i = 0; i < rawJson.length; i++) {
          final snapshot = parser.addChunk(rawJson[i]);
          expect(snapshot.receivedChars, i + 1);
          if (i < valueQuoteIndex) {
            expect(snapshot.message, isNull);
            expect(snapshot.isMessageComplete, isFalse);
          } else if (i == valueQuoteIndex) {
            expect(snapshot.message, '');
            expect(snapshot.isMessageComplete, isFalse);
          }
          if (snapshot.message != null &&
              snapshot.message!.contains('"citation"') &&
              !snapshot.isMessageComplete) {
            sawIncompleteAfterEscapedQuote = true;
          }
          if (snapshot.isMessageComplete && completedAtIndex == null) {
            completedAtIndex = i;
          }
        }

        expect(sawIncompleteAfterEscapedQuote, isTrue);
        expect(completedAtIndex, isNotNull);
        expect(completedAtIndex, lessThan(rawJson.length - 1));
        expect(parser.current.message, expectedMessage);
        expect(parser.current.isMessageComplete, isTrue);
        expect(parser.current.hasVibeObject, isFalse);
        expect(parser.current.estimatedComponentCount, 0);
        expect(parser.rawBuffer, rawJson);
      },
    );

    test(
      'reconstitue une paire de substitution UTF-16 (\\uD83D\\uDE80) coupée au milieu de la séquence entre plusieurs fragments',
      () {
        final parser = VibeIncrementalStreamParser();

        var snap = parser.addChunk('{"message":"Décollage \\uD8');
        expect(snap.message, 'Décollage ');
        expect(snap.isMessageComplete, isFalse);

        // Le haut substitut est complet mais le bas substitut n'est que partiel :
        // aucun caractère corrompu ne doit être émis prématurément.
        snap = parser.addChunk('3D\\uDE');
        expect(snap.message, 'Décollage ');
        expect(snap.isMessageComplete, isFalse);

        snap = parser.addChunk('80 réussi\\n\\t\\"OK\\"\\\\fin"');
        expect(snap.message, 'Décollage 🚀 réussi\n\t"OK"\\fin');
        expect(snap.isMessageComplete, isTrue);

        snap = parser.addChunk(',"vibe":null}');
        expect(snap.message, 'Décollage 🚀 réussi\n\t"OK"\\fin');
        expect(snap.hasVibeObject, isFalse);
      },
    );

    test(
      'ignore les blocs Markdown ```json et ``` en tête ou en fin de flux même découpés caractère par caractère',
      () {
        const fenced =
            '  \n```json\n{"message":"Depuis bloc Markdown","vibe":{"components":{"c1":{"type":"value"}}}}\n```';
        final parser = VibeIncrementalStreamParser();

        for (var i = 0; i < fenced.length; i++) {
          parser.addChunk(fenced[i]);
        }

        expect(parser.current.message, 'Depuis bloc Markdown');
        expect(parser.current.isMessageComplete, isTrue);
        expect(parser.current.hasVibeObject, isTrue);
        expect(parser.current.estimatedComponentCount, 1);

        // Vérifie aussi un bloc ``` sans identifiant de langage après reset().
        parser.reset();
        expect(parser.current, VibeStreamSnapshot.empty);
        expect(parser.rawBuffer, isEmpty);

        parser.addChunk('```\n{"message":"Sans tag","vibe":null}\n```');
        expect(parser.current.message, 'Sans tag');
        expect(parser.current.isMessageComplete, isTrue);
        expect(parser.current.hasVibeObject, isFalse);
      },
    );

    test(
      'les champs "message" imbriqués dans "vibe" (ex. info-bulle de behavior) n\'écrasent jamais le "message" de premier niveau',
      () {
        final payload = jsonEncode({
          'message': 'Résumé principal affiché à l’utilisateur.',
          'vibe': {
            'behaviors': {
              'save-btn': [
                {
                  'id': 'tip-1',
                  'trigger': 'hover',
                  'action': {'type': 'tooltip', 'message': 'Infobulle'},
                },
              ],
            },
            'components': {
              'mainLayout': {
                'type': 'layout',
                'placements': {
                  'center': [
                    {'id': 'save-btn', 'type': 'registry:Action'},
                  ],
                },
              },
              'save-btn': {
                'type': 'action',
                'label': 'Enregistrer',
                'message': 'Champ interne ignoré',
              },
            },
          },
        });

        final parser = VibeIncrementalStreamParser();
        for (var i = 0; i < payload.length; i++) {
          final snap = parser.addChunk(payload[i]);
          if (snap.isMessageComplete) {
            expect(snap.message, 'Résumé principal affiché à l’utilisateur.');
          }
        }

        expect(
          parser.current.message,
          'Résumé principal affiché à l’utilisateur.',
        );
        expect(parser.current.isMessageComplete, isTrue);
        expect(parser.current.hasVibeObject, isTrue);
        expect(parser.current.estimatedComponentCount, 2);

        // Même si "vibe" précède le "message" racine, le "message" imbriqué est ignoré
        // et seul le "message" de premier niveau est retenu.
        const reversedOrder =
            '{"vibe":{"behaviors":{"b1":[{"action":{"type":"tooltip","message":"Infobulle"}}]}},"message":"Message racine tardif"}';
        parser.reset();
        final midIndex = reversedOrder.indexOf(',"message"');
        final beforeRootMsg = parser.addChunk(
          reversedOrder.substring(0, midIndex),
        );
        expect(beforeRootMsg.message, isNull);
        expect(beforeRootMsg.hasVibeObject, isTrue);

        final afterRootMsg = parser.addChunk(reversedOrder.substring(midIndex));
        expect(afterRootMsg.message, 'Message racine tardif');
        expect(afterRootMsg.isMessageComplete, isTrue);
      },
    );

    test(
      'suit précisément hasVibeObject et estimatedComponentCount sur les clés directes de vibe.components et vibe.data.components',
      () {
        final parser = VibeIncrementalStreamParser();

        // Cas 1 : "vibe" omis -> hasVibeObject == false, 0 composant.
        parser.addChunk('{"message":"Question simple"}');
        expect(parser.current.hasVibeObject, isFalse);
        expect(parser.current.estimatedComponentCount, 0);

        // Cas 2 : "vibe": null -> hasVibeObject == false, 0 composant.
        parser.reset();
        parser.addChunk('{"message":"Aucune modif","vibe":null}');
        expect(parser.current.hasVibeObject, isFalse);
        expect(parser.current.estimatedComponentCount, 0);

        // Cas 3 : "vibe": { ... } avec propriétés imbriquées riches ->
        // hasVibeObject passe à true dès "{", et seules les clés directes de components comptent.
        parser.reset();
        var snap = parser.addChunk('{"message":"Création","vibe":');
        expect(snap.hasVibeObject, isFalse);

        snap = parser.addChunk('{');
        expect(snap.hasVibeObject, isTrue);
        expect(snap.estimatedComponentCount, 0);

        snap = parser.addChunk(
          '"styles":{"background":{"color":"#112233","states":{"hover":{"color":"#223344"}}}},'
          '"components":{',
        );
        expect(snap.estimatedComponentCount, 0);

        snap = parser.addChunk(
          '"mainLayout":{"type":"layout","zoneFlows":{"center":{"padding":16,"spacing":8}},'
          '"placements":{"center":[{"id":"list-users","type":"registry:ListView"}]}},',
        );
        expect(snap.estimatedComponentCount, 1);

        snap = parser.addChunk(
          '"list-users":{"type":"list","binding":"users","template":{"west":true,"placements":{"west":["avatar"],"center":["name"]}}},'
          '"name":{"type":"value","binding":"users[?].name","states":{"named":{"active":{"color":"#00FF00"}}}}}}',
        );
        expect(snap.hasVibeObject, isTrue);
        expect(snap.estimatedComponentCount, 3);

        // Cas 4 : enveloppe "vibe": { "data": { "components": { ... } } }
        parser.reset();
        final wrapped = jsonEncode({
          'message': 'Enveloppe data',
          'vibe': {
            'format': 'super_container_layout.appearance',
            'data': {
              'components': {
                'rootLayout': {
                  'type': 'layout',
                  'placements': {
                    'center': [
                      {'id': 'kpi-1', 'type': 'registry:Value'},
                    ],
                  },
                },
                'kpi-1': {
                  'type': 'value',
                  'text': '42',
                  'propertyBindings': {'text': 'metrics.total'},
                },
              },
            },
          },
        });
        for (final rune in wrapped.split('')) {
          parser.addChunk(rune);
        }
        expect(parser.current.hasVibeObject, isTrue);
        expect(parser.current.estimatedComponentCount, 2);
      },
    );

    test(
      'active hasAskUserObject dès le début de "askUser": { ou "askUser": [ au niveau racine, mais reste false pour null ou un "askUser" imbriqué dans "vibe"',
      () {
        final parser = VibeIncrementalStreamParser();

        // Cas 1 : "askUser": { ... } au premier niveau -> passe à true dès '{'.
        var snap = parser.addChunk('{"message":"Précisions :","askUser": ');
        expect(snap.message, 'Précisions :');
        expect(snap.isMessageComplete, isTrue);
        expect(snap.hasAskUserObject, isFalse);

        snap = parser.addChunk('{');
        expect(snap.hasAskUserObject, isTrue);
        expect(snap.hasVibeObject, isFalse);

        snap = parser.addChunk(
          '"questions":[{"id":"q1","title":"Choix ?","options":["A","B"]}]},"vibe":null}',
        );
        expect(snap.hasAskUserObject, isTrue);
        expect(snap.hasVibeObject, isFalse);

        // Cas 2 : "askUser": [ ... ] au premier niveau -> passe à true dès '[' après reset().
        parser.reset();
        expect(parser.current.hasAskUserObject, isFalse);

        snap = parser.addChunk('{"message":"Questions","askUser":');
        expect(snap.hasAskUserObject, isFalse);

        snap = parser.addChunk('[');
        expect(snap.hasAskUserObject, isTrue);

        snap = parser.addChunk('{"title":"Nom ?"}],"vibe":null}');
        expect(snap.hasAskUserObject, isTrue);

        // Cas 3 : "askUser": null ou booléen -> reste false.
        parser.reset();
        parser.addChunk('{"message":"Direct","askUser":null,"vibe":null}');
        expect(parser.current.hasAskUserObject, isFalse);

        parser.reset();
        parser.addChunk('{"message":"Direct","askUser":false,"vibe":null}');
        expect(parser.current.hasAskUserObject, isFalse);

        // Cas 4 : clé "askUser" imbriquée à l'intérieur de "vibe" -> reste false.
        parser.reset();
        final nestedPayload = jsonEncode(<String, Object?>{
          'message': 'Patch avec clé métier interne',
          'vibe': <String, Object?>{
            'components': <String, Object?>{
              'askUser': <String, Object?>{'type': 'value', 'text': 'Ignoré'},
            },
            'behaviors': <String, Object?>{
              'btn': <Object?>[
                <String, Object?>{
                  'id': 'b1',
                  'askUser': <String, Object?>{'questions': <Object?>[]},
                },
              ],
            },
          },
        });
        for (var i = 0; i < nestedPayload.length; i++) {
          parser.addChunk(nestedPayload[i]);
        }
        expect(parser.current.hasVibeObject, isTrue);
        expect(parser.current.hasAskUserObject, isFalse);
        expect(parser.current.estimatedComponentCount, 1);
      },
    );

    test(
      'extrait incrémentalement partialVibePatch et patchRevision à chaque entrée fermée de vibe (thème, pageCatalog, styles, components, null, behaviors, usages)',
      () {
        final parser = VibeIncrementalStreamParser();

        var snap = parser.addChunk('{"message":"Construction live","vibe":{');
        expect(snap.partialVibePatch, isNull);
        expect(snap.patchRevision, 0);

        // 1. Scalaires de thème et pageCatalog
        snap = parser.addChunk(
          '"mode":"dark","backgroundOpacity":0.85,'
          '"pageCatalog":{"pages":[{"id":"dash","name":"Dashboard","path":"/dash"}]},',
        );
        expect(snap.patchRevision, 3);
        expect(snap.partialVibePatch!['mode'], 'dark');
        expect(snap.partialVibePatch!['backgroundOpacity'], 0.85);
        expect(
          (snap.partialVibePatch!['pageCatalog'] as Map)['pages'],
          hasLength(1),
        );

        // 2. Styles : la première entrée est fermée, la seconde est encore ouverte
        snap = parser.addChunk(
          '"styles":{"card-1":{"color":"#1E293B","radius":12},"card-2":{"color":"#',
        );
        expect(snap.patchRevision, 4);
        final stylesStep1 =
            snap.partialVibePatch!['styles'] as Map<String, dynamic>;
        expect(stylesStep1.keys, ['card-1']);
        expect((stylesStep1['card-1'] as Map)['radius'], 12);

        // Fermeture de card-2 et ouverture de components avec suppression null + accolade dans texte échappé
        snap = parser.addChunk(
          '334155"}},'
          '"components":{"legacy-slot":null,'
          '"dash":{"type":"scaffold","placements":{"body":[{"id":"kpi","type":"registry:Value"}]}},'
          '"kpi":{"type":"value","text":"Valeur {A} \\"OK\\" 🚀',
        );
        expect(snap.patchRevision, 7);
        final componentsStep1 =
            snap.partialVibePatch!['components'] as Map<String, dynamic>;
        expect(componentsStep1.containsKey('legacy-slot'), isTrue);
        expect(componentsStep1['legacy-slot'], isNull);
        expect(componentsStep1.containsKey('dash'), isTrue);
        // "kpi" n'est pas encore fermé : il ne doit pas encore figurer dans partialVibePatch
        expect(componentsStep1.containsKey('kpi'), isFalse);
        // En revanche son ID a déjà été compté dans estimatedComponentCount
        expect(snap.estimatedComponentCount, 3);

        // Fermeture de "kpi", puis behaviors et usages caractère par caractère
        const tail =
            '"}},'
            '"behaviors":{"kpi":[{"id":"b1","trigger":"tap","action":{"type":"emitEvent","eventId":"kpi.tap"}}]},'
            '"usages":{"kpi":{"kind":"staticData"}}}}';
        for (var i = 0; i < tail.length; i++) {
          snap = parser.addChunk(tail[i]);
        }

        expect(snap.patchRevision, 10);
        final finalComponents =
            snap.partialVibePatch!['components'] as Map<String, dynamic>;
        expect(
          (finalComponents['kpi'] as Map)['text'],
          'Valeur {A} "OK" 🚀',
        );
        expect(
          (snap.partialVibePatch!['behaviors'] as Map).containsKey('kpi'),
          isTrue,
        );
        expect(
          ((snap.partialVibePatch!['usages'] as Map)['kpi'] as Map)['kind'],
          'staticData',
        );

        parser.reset();
        expect(parser.current.partialVibePatch, isNull);
        expect(parser.current.patchRevision, 0);
      },
    );

    test(
      'capture caractère par caractère "message" puis "repositories" (plusieurs entrées) puis "vibe" avec révisions indépendantes',
      () {
        const rawJson =
            '{"message":"Création CRM",'
            '"repositories":{'
            '"crm_clients":{"name":"CRM Clients","mode":"merge","data":{"clients":[{"id":"C1","nom":"Alice"}]}},'
            '"app_settings":{"ui":{"westWidth":320}}'
            '},'
            '"vibe":{'
            '"mode":"dark",'
            '"styles":{"card-1":{"color":"#1E293B","radius":12}},'
            '"components":{"kpi":{"type":"value","binding":"crm_clients:clients[?].nom","repositories":{"ignored":true}}}'
            '}}';

        final parser = VibeIncrementalStreamParser();

        final repoBraceIndex = rawJson.indexOf('"repositories":{') +
            '"repositories":'.length;
        final firstRepoEndIndex = rawJson.indexOf(',"app_settings"') - 1;
        final secondRepoEndIndex = rawJson.indexOf('},"vibe"') - 1;
        final vibeBraceIndex = rawJson.indexOf('"vibe":{') + '"vibe":'.length;

        for (var i = 0; i < rawJson.length; i++) {
          final snap = parser.addChunk(rawJson[i]);

          if (i < repoBraceIndex) {
            expect(snap.hasRepositoriesObject, isFalse);
            expect(snap.hasVibeObject, isFalse);
            expect(snap.repositoriesRevision, 0);
            expect(snap.partialRepositoriesPatch, isNull);
            expect(snap.patchRevision, 0);
            expect(snap.partialVibePatch, isNull);
          } else if (i == repoBraceIndex) {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isFalse);
            expect(snap.repositoriesRevision, 0);
            expect(snap.partialRepositoriesPatch, isNull);
            expect(snap.patchRevision, 0);
          } else if (i < firstRepoEndIndex) {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isFalse);
            expect(snap.repositoriesRevision, 0);
            expect(snap.partialRepositoriesPatch, isNull);
            expect(snap.patchRevision, 0);
          } else if (i == firstRepoEndIndex) {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isFalse);
            expect(snap.repositoriesRevision, 1);
            expect(snap.partialRepositoriesPatch!.keys, ['crm_clients']);
            expect(
              (snap.partialRepositoriesPatch!['crm_clients'] as Map)['name'],
              'CRM Clients',
            );
            expect(snap.patchRevision, 0);
            expect(snap.partialVibePatch, isNull);
          } else if (i < secondRepoEndIndex) {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isFalse);
            expect(snap.repositoriesRevision, 1);
            expect(snap.patchRevision, 0);
          } else if (i == secondRepoEndIndex) {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isFalse);
            expect(snap.repositoriesRevision, 2);
            expect(
              snap.partialRepositoriesPatch!.keys,
              ['crm_clients', 'app_settings'],
            );
            expect(
              ((snap.partialRepositoriesPatch!['app_settings'] as Map)['ui']
                  as Map)['westWidth'],
              320,
            );
            expect(snap.patchRevision, 0);
            expect(snap.partialVibePatch, isNull);
          } else if (i < vibeBraceIndex) {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isFalse);
            expect(snap.repositoriesRevision, 2);
            expect(snap.patchRevision, 0);
          } else if (i == vibeBraceIndex) {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isTrue);
            expect(snap.repositoriesRevision, 2);
            expect(snap.patchRevision, 0);
            expect(snap.partialVibePatch, isNull);
          } else {
            expect(snap.hasRepositoriesObject, isTrue);
            expect(snap.hasVibeObject, isTrue);
            expect(snap.repositoriesRevision, 2);
          }
        }

        final finalSnap = parser.current;
        expect(finalSnap.message, 'Création CRM');
        expect(finalSnap.isMessageComplete, isTrue);
        expect(finalSnap.hasRepositoriesObject, isTrue);
        expect(finalSnap.repositoriesRevision, 2);
        expect(
          finalSnap.partialRepositoriesPatch!.keys,
          ['crm_clients', 'app_settings'],
        );
        expect(finalSnap.hasVibeObject, isTrue);
        expect(finalSnap.patchRevision, 3);
        expect(finalSnap.estimatedComponentCount, 1);
        expect(finalSnap.partialVibePatch!['mode'], 'dark');
        expect(
          ((finalSnap.partialVibePatch!['components'] as Map)['kpi']
              as Map)['binding'],
          'crm_clients:clients[?].nom',
        );
      },
    );

    test(
      'maintient hasRepositoriesObject à false et partialRepositoriesPatch à null pour "repositories": null, et remet tout à zéro sur reset()',
      () {
        final parser = VibeIncrementalStreamParser();

        const nullReposJson =
            '{"message":"Aucune donnée modifiée","repositories":null,"vibe":null}';
        for (var i = 0; i < nullReposJson.length; i++) {
          final snap = parser.addChunk(nullReposJson[i]);
          expect(snap.hasRepositoriesObject, isFalse);
          expect(snap.partialRepositoriesPatch, isNull);
          expect(snap.repositoriesRevision, 0);
        }
        expect(parser.current.message, 'Aucune donnée modifiée');
        expect(parser.current.isMessageComplete, isTrue);
        expect(parser.current.hasRepositoriesObject, isFalse);
        expect(parser.current.partialRepositoriesPatch, isNull);
        expect(parser.current.repositoriesRevision, 0);

        parser.reset();
        parser.addChunk(
          '{"message":"Avec repo","repositories":{"demo":{"items":[1,2]}},"vibe":{"mode":"light"}}',
        );
        expect(parser.current.hasRepositoriesObject, isTrue);
        expect(parser.current.repositoriesRevision, 1);
        expect(parser.current.partialRepositoriesPatch, isNotNull);
        expect(parser.current.hasVibeObject, isTrue);
        expect(parser.current.patchRevision, 1);

        parser.reset();
        expect(parser.current, VibeStreamSnapshot.empty);
        expect(parser.current.hasRepositoriesObject, isFalse);
        expect(parser.current.partialRepositoriesPatch, isNull);
        expect(parser.current.repositoriesRevision, 0);
        expect(parser.current.hasVibeObject, isFalse);
        expect(parser.current.partialVibePatch, isNull);
        expect(parser.current.patchRevision, 0);
        expect(parser.rawBuffer, isEmpty);
      },
    );

    test(
      'expose activeSection et activeEntryKey en direct pendant le streaming d’une entrée vibe puis les réinitialise à sa fermeture',
      () {
        final parser = VibeIncrementalStreamParser();

        // Pendant le streaming de "repositories", activeSection/activeEntryKey restent nuls.
        var snap = parser.addChunk(
          '{"message":"MAJ","repositories":{"repo1":{"items":[1',
        );
        expect(snap.activeSection, isNull);
        expect(snap.activeEntryKey, isNull);

        // Dès l'ouverture du style "card-1", activeSection et activeEntryKey sont exposés.
        snap = parser.addChunk(']}},"vibe":{"styles":{"card-1":{"color":"#');
        expect(snap.activeSection, 'styles');
        expect(snap.activeEntryKey, 'card-1');

        // À la fermeture de "card-1" et de "styles", ils repassent à null.
        snap = parser.addChunk('112233"}},');
        expect(snap.activeSection, isNull);
        expect(snap.activeEntryKey, isNull);

        // Pendant le streaming du composant "kpi-1", ils indiquent components / kpi-1.
        snap = parser.addChunk('"components":{"kpi-1":{"type":"value","text":"4');
        expect(snap.activeSection, 'components');
        expect(snap.activeEntryKey, 'kpi-1');

        // Puis repassent à null à la fermeture.
        snap = parser.addChunk('2"}}}');
        expect(snap.activeSection, isNull);
        expect(snap.activeEntryKey, isNull);
      },
    );

    test(
      'maintient nonUsagesPatchRevision stable lorsque seuls des usages streament et expose patchEntries dans l’ordre exact',
      () {
        final parser = VibeIncrementalStreamParser();

        var snap = parser.addChunk(
          '{"message":"OK","vibe":{"mode":"dark","components":{"kpi":{"type":"value","text":"10"}},',
        );
        expect(snap.patchRevision, 2);
        expect(snap.nonUsagesPatchRevision, 2);
        expect(snap.patchEntries, hasLength(2));
        expect(snap.patchEntries[0].section, isNull);
        expect(snap.patchEntries[0].key, 'mode');
        expect(snap.patchEntries[1].section, 'components');
        expect(snap.patchEntries[1].key, 'kpi');
        expect(snap.patchEntries[1].isUsageEntry, isFalse);

        // Les entrées "usages" incrémentent patchRevision mais PAS nonUsagesPatchRevision.
        snap = parser.addChunk(
          '"usages":{"kpi":{"kind":"staticData"},"root":{"kind":"layout"}}}}',
        );
        expect(snap.patchRevision, 4);
        expect(snap.nonUsagesPatchRevision, 2);
        expect(snap.patchEntries, hasLength(4));
        expect(snap.patchEntries[2].isUsageEntry, isTrue);
        expect(snap.patchEntries[3].isUsageEntry, isTrue);
      },
    );

    test(
      'VibeIncrementalPreviewApplier décode en O(N) sur tout le flux et gère les enfants reçus avant leur parent (selfConstraints & scope)',
      () {
        final base = Appearance(
          components: {
            'scoped-card': const SuperLayoutConfig(
              placements: {SuperLayoutZone.center: ['existing-title']},
              slotTypes: {'existing-title': 'registry:Value'},
            ),
            'existing-title': const SuperValueConfig(initialText: 'Initial'),
            'outside-box': const SuperValueConfig(initialText: 'Externe'),
          },
        );
        const scope = VibeChatScope(
          componentId: 'scoped-card',
          label: 'Carte ciblée',
        );

        final parser = VibeIncrementalStreamParser();
        final applier = VibeIncrementalPreviewApplier(baseAppearance: base);

        // Palier 1 : style d'un nouvel enfant "new-badge" (pas encore rattaché à scoped-card -> différé)
        // + composant "new-badge" avec slotSizeConstraints directes avant son parent !
        var snap = parser.addChunk(
          '{"message":"Maj","vibe":{'
          '"styles":{"new-badge":{"padding":10},"outside-box":{"padding":99}},'
          '"components":{"new-badge":{"type":"value","text":"Nouveau","slotSizeConstraints":{"preferredWidth":140,"fitContent":false}},',
        );
        final step1 = applier.applyStep(snapshot: snap, scope: scope);
        expect(step1, isNotNull);
        // "outside-box" est filtré hors scope.
        expect(step1!.appearance.styles.containsKey('outside-box'), isFalse);
        // "new-badge" n'étant pas encore placé sous scoped-card, son style était hors allowedSubtreeIds au palier 1.
        expect(step1.appearance.styles.containsKey('new-badge'), isFalse);

        // Palier 2 : "scoped-card" place maintenant "new-badge" -> rattache selfConstraints ET débloque styles["new-badge"] sans re-décoder "new-badge" !
        snap = parser.addChunk(
          '"scoped-card":{"type":"layout","placements":{"center":["existing-title","new-badge"]},"slotTypes":{"existing-title":"registry:Value","new-badge":"registry:Value"}}}}}',
        );
        final step2 = applier.applyStep(snapshot: snap, scope: scope);
        expect(step2, isNotNull);
        expect(step2!.appearance.styles['new-badge']?.padding, 10);
        final updatedLayout =
            step2.appearance.components['scoped-card'] as SuperLayoutConfig;
        expect(
          updatedLayout.slotSizeConstraints['new-badge']?.preferredWidth?.value,
          140,
        );
        expect(
          updatedLayout.slotSizeConstraints['new-badge']?.fitContent,
          isFalse,
        );

        // Vérifie l'équivalence exacte avec une application cumulative complète depuis `base`.
        final fullEffective = VibeScopeHelpersOnTest.filterScoped(
          base,
          snap.partialVibePatch!,
          scope,
        );
        final expected = AppearanceTransfer.applyVibeMapPartial(
          base,
          fullEffective,
        ).appearance;
        expect(
          const AppearanceCodec().toJson(step2.appearance),
          const AppearanceCodec().toJson(expected),
        );
        // 3 entrées effectives décodées au total (new-badge component, scoped-card component, new-badge style) -> pas de re-décodage cumulatif !
        expect(applier.debugTotalDecodedEntries, 3);
      },
    );
  });
}

abstract final class VibeScopeHelpersOnTest {
  static Map<String, dynamic> filterScoped(
    Appearance base,
    Map<String, dynamic> patch,
    VibeChatScope scope,
  ) => VibeIncrementalPreviewApplier(baseAppearance: base)
      .buildEffectiveCumulativePatch(
        snapshot: VibeStreamSnapshot(partialVibePatch: patch, patchRevision: 1),
        scope: scope,
      )!;
}
