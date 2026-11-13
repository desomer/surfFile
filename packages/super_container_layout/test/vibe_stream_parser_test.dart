import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/ai/vibe_stream_parser.dart';

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
  });
}
