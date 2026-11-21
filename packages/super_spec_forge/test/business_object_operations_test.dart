import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('BusinessObjectOperations — TDD unité pure', () {
    test('singularizePascal et toCamel produisent des identifiants DSL propres', () {
      expect(BusinessObjectOperations.singularizePascal('lignes'), 'Ligne');
      expect(
        BusinessObjectOperations.singularizePascal('order_items'),
        'OrderItem',
      );
      expect(BusinessObjectOperations.singularizePascal('   '), 'SousEntite');
      expect(BusinessObjectOperations.toCamel('FactureClient'), 'factureClient');
      expect(BusinessObjectOperations.toCamel(''), 'parent');
    });

    test('findAttributeByPath et resolveAttributePathNames naviguent récursivement', () {
      final attrs = [
        BusinessAttribute(
          id: 'a_adr',
          name: 'adresse',
          type: BusinessAttributeType.object,
          children: [
            BusinessAttribute(
              id: 'a_cp',
              name: 'codePostal',
              type: BusinessAttributeType.string,
            ),
          ],
        ),
      ];

      final found = BusinessObjectOperations.findAttributeByPath(
        attrs,
        const ['a_adr', 'a_cp'],
      );
      expect(found?.id, 'a_cp');
      expect(
        BusinessObjectOperations.resolveAttributePathNames(
          attrs,
          const ['a_adr', 'a_cp'],
        ),
        ['adresse', 'codePostal'],
      );
      expect(
        BusinessObjectOperations.findAttributeByPath(attrs, const ['inexistant']),
        isNull,
      );
      expect(
        BusinessObjectOperations.findAttributeByPath(attrs, const []),
        isNull,
      );
    });

    test('upsertAttributeAtPath et deleteAttributeAtPath modifient racine et sous-attributs', () {
      final obj = BusinessObjectSpec(
        id: 'obj_1',
        name: 'Facture',
        technicalName: 'Facture',
        attributes: [
          BusinessAttribute(
            id: 'a_adr',
            name: 'adresse',
            type: BusinessAttributeType.object,
            children: [
              BusinessAttribute(id: 'a_rue', name: 'rue'),
            ],
          ),
        ],
      );

      final added = BusinessObjectOperations.upsertAttributeAtPath(
        obj,
        parentAttrPath: const ['a_adr'],
        attribute: BusinessAttribute(id: 'a_ville', name: 'ville', required: true),
      );
      expect(added.attributes.single.children.length, 2);
      expect(added.attributes.single.children[1].name, 'ville');

      final updated = BusinessObjectOperations.upsertAttributeAtPath(
        added,
        parentAttrPath: const ['a_adr'],
        attribute: BusinessAttribute(id: 'a_ville', name: 'commune', required: true),
      );
      expect(updated.attributes.single.children.length, 2);
      expect(updated.attributes.single.children[1].name, 'commune');

      final deleted = BusinessObjectOperations.deleteAttributeAtPath(
        updated,
        const ['a_adr', 'a_rue'],
      );
      expect(deleted.attributes.single.children.length, 1);
      expect(deleted.attributes.single.children.single.id, 'a_ville');
    });

    test('extractArrayToSeparateObject extrait un tableau avec enfants vers un objet lié 1:N', () {
      final arrayAttr = BusinessAttribute(
        id: 'a_lignes',
        name: 'lignes',
        type: BusinessAttributeType.object,
        isArray: true,
        required: true,
        estimatedMaxRows: 350,
        description: 'Lignes de facturation',
        children: [
          BusinessAttribute(
            id: 'a_lib',
            name: 'libelle',
            type: BusinessAttributeType.string,
            required: true,
          ),
        ],
      );
      final parent = BusinessObjectSpec(
        id: 'obj_facture',
        name: 'Facture',
        technicalName: 'Facture',
        attributes: [
          BusinessAttribute(id: 'a_num', name: 'numero', required: true),
          arrayAttr,
        ],
      );

      final result = BusinessObjectOperations.extractArrayToSeparateObject(
        [parent],
        parentObject: parent,
        attrPath: const ['a_lignes'],
        arrayAttr: arrayAttr,
      );

      expect(result.length, 2);
      final updatedParent = result[0];
      final extracted = result[1];

      expect(updatedParent.attributes.map((a) => a.id), ['a_num']);
      expect(updatedParent.relations.length, 1);
      expect(updatedParent.relations.single.name, 'lignes');
      expect(updatedParent.relations.single.targetObjectId, extracted.id);
      expect(
        updatedParent.relations.single.cardinality,
        BusinessRelationCardinality.oneToMany,
      );
      expect(updatedParent.relations.single.required, isTrue);

      expect(extracted.technicalName, 'Ligne');
      expect(extracted.aggregateRoot, isTrue);
      expect(extracted.attributes.map((a) => a.name), ['libelle', 'factureId']);
      expect(extracted.attributes[1].referenceObjectId, 'obj_facture');
    });

    test('extractArrayToSeparateObject gère un tableau scalaire sans enfants et l’imbrication', () {
      final nestedArray = BusinessAttribute(
        id: 'a_tags',
        name: 'tags',
        type: BusinessAttributeType.string,
        isArray: true,
      );
      final parent = BusinessObjectSpec(
        id: 'obj_cmd',
        name: 'Commande',
        technicalName: 'Commande',
        attributes: [
          BusinessAttribute(
            id: 'a_meta',
            name: 'meta',
            type: BusinessAttributeType.object,
            children: [nestedArray],
          ),
        ],
      );

      final result = BusinessObjectOperations.extractArrayToSeparateObject(
        [parent],
        parentObject: parent,
        attrPath: const ['a_meta', 'a_tags'],
        arrayAttr: nestedArray,
      );

      expect(result[0].attributes.single.children, isEmpty);
      expect(result[1].technicalName, 'Tag');
      expect(result[1].attributes.map((a) => a.name), ['libelle', 'commandeId']);
    });

    test('normalizeAllIdentifiers corrige objets, attributs imbriqués, doublons et relations', () {
      final dirty = BusinessObjectSpec(
        id: 'obj_dirty',
        name: 'Client Final',
        technicalName: 'Client Final',
        attributes: [
          BusinessAttribute(id: 'a1', name: 'nom complet'),
          BusinessAttribute(id: 'a2', name: 'nom complet'),
          BusinessAttribute(
            id: 'a3',
            name: 'détails',
            type: BusinessAttributeType.object,
            children: [
              BusinessAttribute(id: 'a4', name: 'code postal'),
            ],
          ),
        ],
        relations: [
          BusinessRelation(
            id: 'r1',
            name: 'mes commandes',
            targetObjectId: 'obj_cmd',
          ),
        ],
      );

      final normalized = BusinessObjectOperations.normalizeAllIdentifiers([dirty]);
      final obj = normalized.single;
      obj.validate();
      expect(BusinessAttribute.isValidDslIdentifier(obj.technicalName), isTrue);
      expect(obj.attributes[0].name, isNot(obj.attributes[1].name));
      expect(BusinessAttribute.isValidDslIdentifier(obj.attributes[0].name), isTrue);
      expect(
        BusinessAttribute.isValidDslIdentifier(obj.attributes[2].children.single.name),
        isTrue,
      );
      expect(BusinessAttribute.isValidDslIdentifier(obj.relations.single.name), isTrue);
    });

    test('filterTreeNodes filtre récursivement parents et feuilles', () {
      final nodes = <Map<String, Object?>>[
        {
          'displayName': 'client',
          'displayType': 'object',
          'attrType': 'object',
          'children': [
            {
              'displayName': 'email',
              'displayType': 'email',
              'attrType': 'email',
              'children': <Map<String, Object?>>[],
            },
            {
              'displayName': 'telephone',
              'displayType': 'string',
              'attrType': 'string',
              'children': <Map<String, Object?>>[],
            },
          ],
        },
        {
          'displayName': 'statut',
          'displayType': 'enum',
          'attrType': 'enumeration',
          'children': <Map<String, Object?>>[],
        },
      ];

      expect(BusinessObjectOperations.filterTreeNodes(nodes, '').length, 2);

      final filteredLeaf = BusinessObjectOperations.filterTreeNodes(nodes, 'email');
      expect(filteredLeaf.length, 1);
      final filteredChildren = filteredLeaf.single['children'] as List;
      expect(filteredChildren.length, 1);
      expect((filteredChildren.single as Map)['displayName'], 'email');

      final filteredParent = BusinessObjectOperations.filterTreeNodes(nodes, 'client');
      expect(filteredParent.length, 1);
      expect((filteredParent.single['children'] as List).length, 2);
    });

    test('applyYamlSource parse le YAML en préservant les métadonnées existantes', () {
      final existing = [
        BusinessObjectSpec(
          id: 'obj_facture',
          name: 'Facture client',
          technicalName: 'Facture',
          description: 'Facture émise',
          attributes: [
            BusinessAttribute(id: 'a_num', name: 'numero', required: true),
          ],
        ),
      ];

      final next = BusinessObjectOperations.applyYamlSource(
        '''
Facture:
  numero: string!
  client:
    nom: string!
    email: email
''',
        existing: existing,
      );

      expect(next.length, 1);
      expect(next.single.id, 'obj_facture');
      expect(next.single.description, 'Facture émise');
      expect(next.single.attributes.length, 2);
      expect(next.single.attributes[1].name, 'client');
      expect(next.single.attributes[1].type, BusinessAttributeType.object);
      expect(next.single.attributes[1].children.length, 2);
    });
  });
}
