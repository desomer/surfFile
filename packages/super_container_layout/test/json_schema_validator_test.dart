import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  group('JsonSchemaValidator', () {
    test('valide les types, propriétés requises, additionalProperties et formats', () {
      const schema = <String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'required': ['clients'],
        'additionalProperties': false,
        'properties': {
          'clients': {
            'type': 'array',
            'minItems': 1,
            'items': {
              'type': 'object',
              'required': ['id', 'email', 'age', 'statut'],
              'additionalProperties': false,
              'properties': {
                'id': {'type': 'string', 'format': 'uuid'},
                'email': {'type': 'string', 'format': 'email'},
                'age': {'type': 'integer', 'minimum': 18, 'maximum': 120},
                'statut': {
                  'type': 'string',
                  'enum': ['actif', 'suspendu'],
                },
              },
            },
          },
        },
      };

      final validDoc = <String, Object?>{
        'clients': [
          {
            'id': '123e4567-e89b-12d3-a456-426614174000',
            'email': 'claire@exemple.fr',
            'age': 34,
            'statut': 'actif',
          },
        ],
      };
      expect(JsonSchemaValidator.validate(validDoc, schema).isValid, isTrue);

      final invalidDoc = <String, Object?>{
        'extra': 123,
        'clients': [
          {
            'id': 'pas-un-uuid',
            'email': 'invalide',
            'age': 15,
            'statut': 'inconnu',
          },
        ],
      };
      final result = JsonSchemaValidator.validate(invalidDoc, schema);
      expect(result.isValid, isFalse);
      expect(
        result.issues.map((i) => '${i.instancePath}:${i.keyword}'),
        containsAll([
          'extra:additionalProperties',
          'clients[0].id:format',
          'clients[0].email:format',
          'clients[0].age:minimum',
          'clients[0].statut:enum',
        ]),
      );
    });

    test(r'supporte $defs/$ref locaux avec protection contre les cycles et compositions logiques', () {
      const schema = <String, Object?>{
        r'$defs': {
          'node': {
            'type': 'object',
            'required': ['nom'],
            'properties': {
              'nom': {'type': 'string', 'minLength': 2},
              'children': {
                'type': 'array',
                'items': {r'$ref': r'#/$defs/node'},
              },
            },
          },
        },
        'type': 'object',
        'required': ['racine', 'paiement'],
        'properties': {
          'racine': {r'$ref': r'#/$defs/node'},
          'paiement': {
            'oneOf': [
              {
                'type': 'object',
                'required': ['iban'],
                'properties': {'iban': {'type': 'string'}},
                'additionalProperties': false,
              },
              {
                'type': 'object',
                'required': ['carte'],
                'properties': {'carte': {'type': 'string'}},
                'additionalProperties': false,
              },
            ],
          },
        },
      };

      final valid = <String, Object?>{
        'racine': {
          'nom': 'Root',
          'children': [
            {'nom': 'Enfant'},
          ],
        },
        'paiement': {'iban': 'FR761234'},
      };
      expect(JsonSchemaValidator.validate(valid, schema).isValid, isTrue);

      final invalid = <String, Object?>{
        'racine': {
          'nom': 'Root',
          'children': [
            {'nom': 'A'},
          ],
        },
        'paiement': {'iban': 'FR76', 'carte': '4111'},
      };
      final res = JsonSchemaValidator.validate(invalid, schema);
      expect(res.isValid, isFalse);
      expect(
        res.issues.map((i) => '${i.instancePath}:${i.keyword}'),
        containsAll([
          'racine.children[0].nom:minLength',
          'paiement:oneOf',
        ]),
      );
    });

    test('supporte if/then/else, multipleOf, uniqueItems et prefixItems', () {
      const schema = <String, Object?>{
        'type': 'object',
        'properties': {
          'pays': {'type': 'string'},
          'tva': {'type': 'number', 'multipleOf': 0.5},
          'tags': {'type': 'array', 'uniqueItems': true},
          'paire': {
            'type': 'array',
            'prefixItems': [
              {'type': 'string'},
              {'type': 'integer'},
            ],
          },
        },
        'if': {
          'properties': {
            'pays': {'const': 'FR'},
          },
          'required': ['pays'],
        },
        'then': {
          'required': ['siret'],
          'properties': {
            'siret': {'type': 'string', 'pattern': r'^\d{14}$'},
          },
        },
      };

      expect(
        JsonSchemaValidator.validate({
          'pays': 'FR',
          'siret': '12345678901234',
          'tva': 5.5,
          'tags': ['a', 'b'],
          'paire': ['ok', 42],
        }, schema).isValid,
        isTrue,
      );

      final bad = JsonSchemaValidator.validate({
        'pays': 'FR',
        'tva': 5.3,
        'tags': ['a', 'a'],
        'paire': ['ok', 'not-int'],
      }, schema);
      expect(bad.isValid, isFalse);
      expect(
        bad.issues.map((i) => i.keyword),
        containsAll(['required', 'multipleOf', 'uniqueItems', 'type']),
      );
    });

    test(r'rejette une définition de schéma invalide ($ref inexistant, regex cassée, type inconnu)', () {
      expect(
        () => JsonSchemaValidator.validateSchemaDefinition({
          'type': 'inconnu',
        }),
        throwsFormatException,
      );
      expect(
        () => JsonSchemaValidator.validateSchemaDefinition({
          'pattern': '[non-ferme',
        }),
        throwsFormatException,
      );
      expect(
        () => JsonSchemaValidator.validateSchemaDefinition({
          r'$ref': r'#/$defs/absent',
        }),
        throwsFormatException,
      );
    });

    test('inferSchema produit un schéma valide pour le document source', () {
      final doc = <String, Object?>{
        'titre': 'Facture',
        'articles': [
          {'nom': 'Stylo', 'quantite': 2},
          {'nom': 'Cahier', 'quantite': 1, 'remise': 0.5},
        ],
      };
      final inferred = JsonSchemaValidator.inferSchema(doc, title: 'Facture');
      expect(JsonSchemaValidator.validate(doc, inferred).isValid, isTrue);
    });
  });
}
