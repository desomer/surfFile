/// Opérations métier pures sur les [BusinessObjectSpec] ([BusinessObjectOperations]).
///
/// Regroupe les transformations immuables (extraction de tableaux > 200 lignes,
/// normalisation d'identifiants DSL, navigation/édition par chemin d'attributs,
/// filtrage d'arbre et application d'une source YAML Light) sans dépendance UI,
/// testables directement en Dart pur.
library;

import 'package:shortid/shortid.dart';

import '../models/business_object_spec.dart';
import 'spec_schema_dsl_bridge.dart';

/// Services et transformations pures sur une collection d'objets métiers.
abstract final class BusinessObjectOperations {
  /// Transforme [raw] (ex. `lignes`, `order_items`) en nom technique PascalCase singulier.
  static String singularizePascal(String raw) {
    final cleaned = raw
        .trim()
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        );
    final words = cleaned
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'SousEntite';
    final last = words.last;
    if (last.endsWith('s') && last.length > 2) {
      words[words.length - 1] = last.substring(0, last.length - 1);
    }
    final candidate = words
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join();
    return BusinessAttribute.isValidDslIdentifier(candidate)
        ? candidate
        : BusinessAttribute.toPascalCaseDslIdentifier(candidate);
  }

  /// Convertit un identifiant PascalCase en camelCase (repli sur `'parent'`).
  static String toCamel(String pascal) {
    if (pascal.isEmpty) return 'parent';
    return '${pascal[0].toLowerCase()}${pascal.substring(1)}';
  }

  /// Recherche récursivement un [BusinessAttribute] via son chemin [pathIds].
  static BusinessAttribute? findAttributeByPath(
    List<BusinessAttribute> attrs,
    List<String> pathIds,
  ) {
    if (pathIds.isEmpty) return null;
    final head = pathIds.first;
    for (final attr in attrs) {
      if (attr.id == head) {
        if (pathIds.length == 1) return attr;
        return findAttributeByPath(attr.children, pathIds.sublist(1));
      }
    }
    return null;
  }

  /// Résout les noms d'attributs correspondant à [pathIds] pour les fils d'Ariane.
  static List<String> resolveAttributePathNames(
    List<BusinessAttribute> attrs,
    List<String> pathIds,
  ) {
    final names = <String>[];
    var current = attrs;
    for (final id in pathIds) {
      final found = current.where((a) => a.id == id).firstOrNull;
      if (found == null) break;
      names.add(found.name);
      current = found.children;
    }
    return names;
  }

  /// Insère ou met à jour [attribute] dans [object] au chemin parent [parentAttrPath].
  static BusinessObjectSpec upsertAttributeAtPath(
    BusinessObjectSpec object, {
    required List<String> parentAttrPath,
    required BusinessAttribute attribute,
  }) {
    List<BusinessAttribute> upsertRec(
      List<BusinessAttribute> list,
      List<String> remainingParentPath,
    ) {
      if (remainingParentPath.isEmpty) {
        final next = List<BusinessAttribute>.from(list);
        final idx = next.indexWhere((a) => a.id == attribute.id);
        if (idx >= 0) {
          next[idx] = attribute;
        } else {
          next.add(attribute);
        }
        return next;
      }
      final head = remainingParentPath.first;
      return [
        for (final item in list)
          if (item.id == head)
            item.copyWith(
              children: upsertRec(
                item.children,
                remainingParentPath.sublist(1),
              ),
            )
          else
            item,
      ];
    }

    return object.copyWith(
      attributes: upsertRec(object.attributes, parentAttrPath),
    );
  }

  /// Supprime l'attribut identifié par [pathIds] dans [object].
  static BusinessObjectSpec deleteAttributeAtPath(
    BusinessObjectSpec object,
    List<String> pathIds,
  ) {
    if (pathIds.isEmpty) return object;
    return object.copyWith(
      attributes: _removeAttrRec(object.attributes, pathIds),
    );
  }

  /// Remplace un objet existant par [updated] (selon `id`).
  static List<BusinessObjectSpec> replaceObject(
    List<BusinessObjectSpec> objects,
    BusinessObjectSpec updated,
  ) => [
    for (final obj in objects)
      if (obj.id == updated.id) updated else obj,
  ];

  /// Insère ou met à jour [object] dans [objects].
  static List<BusinessObjectSpec> upsertObject(
    List<BusinessObjectSpec> objects,
    BusinessObjectSpec object,
  ) {
    final next = List<BusinessObjectSpec>.from(objects);
    final idx = next.indexWhere((o) => o.id == object.id);
    if (idx >= 0) {
      next[idx] = object;
    } else {
      next.add(object);
    }
    return next;
  }

  /// Supprime l'objet [objectId] de [objects].
  static List<BusinessObjectSpec> removeObject(
    List<BusinessObjectSpec> objects,
    String objectId,
  ) => [
    for (final obj in objects)
      if (obj.id != objectId) obj,
  ];

  /// Extrait un attribut tableau [arrayAttr] (situé à [attrPath] dans [parentObject])
  /// vers un nouvel objet métier dédié relié au parent par une relation `1:N`.
  static List<BusinessObjectSpec> extractArrayToSeparateObject(
    List<BusinessObjectSpec> objects, {
    required BusinessObjectSpec parentObject,
    required List<String> attrPath,
    required BusinessAttribute arrayAttr,
  }) {
    final baseTech = singularizePascal(arrayAttr.name);
    final existingTechs = {
      for (final o in objects) o.technicalName.toLowerCase(),
    };
    var newObjTech = baseTech;
    var suffix = 2;
    while (existingTechs.contains(newObjTech.toLowerCase())) {
      newObjTech = '$baseTech$suffix';
      suffix++;
    }

    final newObjId = 'obj_${shortid.generate()}';
    final parentFkName = '${toCamel(parentObject.technicalName)}Id';
    final extractedAttributes = arrayAttr.children.isNotEmpty
        ? [
            ...arrayAttr.children,
            BusinessAttribute(
              id: 'attr_${shortid.generate()}',
              name: parentFkName,
              type: BusinessAttributeType.reference,
              required: true,
              referenceObjectId: parentObject.id,
              description: 'Référence vers ${parentObject.name}',
            ),
          ]
        : [
            BusinessAttribute(
              id: 'attr_${shortid.generate()}',
              name: 'libelle',
              type: BusinessAttributeType.string,
              required: true,
            ),
            BusinessAttribute(
              id: 'attr_${shortid.generate()}',
              name: parentFkName,
              type: BusinessAttributeType.reference,
              required: true,
              referenceObjectId: parentObject.id,
            ),
          ];

    final extractedObject = BusinessObjectSpec(
      id: newObjId,
      name: newObjTech,
      technicalName: newObjTech,
      description:
          'Objet métier dédié extrait du tableau ${parentObject.technicalName}.${arrayAttr.name} (> 200 lignes).',
      aggregateRoot: true,
      attributes: extractedAttributes,
    );

    final updatedParent = parentObject.copyWith(
      attributes: _removeAttrRec(parentObject.attributes, attrPath),
      relations: [
        ...parentObject.relations,
        BusinessRelation(
          id: 'rel_${shortid.generate()}',
          name: arrayAttr.name,
          targetObjectId: newObjId,
          cardinality: BusinessRelationCardinality.oneToMany,
          required: arrayAttr.required,
          description: arrayAttr.description,
        ),
      ],
    );

    return [
      for (final obj in objects)
        if (obj.id == updatedParent.id) updatedParent else obj,
      extractedObject,
    ];
  }

  /// Normalise tous les identifiants DSL (noms techniques, attributs, sous-attributs
  /// et relations) en assurant leur unicité dans chaque portée.
  static List<BusinessObjectSpec> normalizeAllIdentifiers(
    List<BusinessObjectSpec> objects,
  ) {
    List<BusinessAttribute> normAttrs(List<BusinessAttribute> list) {
      final used = <String>{};
      return [
        for (final attr in list)
          () {
            final base = BusinessAttribute.isValidDslIdentifier(attr.name)
                ? attr.name
                : BusinessAttribute.normalizeDslIdentifier(attr.name);
            var candidate = base;
            var suffix = 2;
            while (!used.add(candidate)) {
              candidate = '${base}_$suffix';
              suffix++;
            }
            return attr.copyWith(
              name: candidate,
              children: attr.children.isEmpty
                  ? const []
                  : normAttrs(attr.children),
            );
          }(),
      ];
    }

    return [
      for (final obj in objects)
        obj.copyWith(
          technicalName:
              BusinessAttribute.isValidDslIdentifier(obj.technicalName)
              ? obj.technicalName
              : BusinessAttribute.toPascalCaseDslIdentifier(obj.technicalName),
          attributes: normAttrs(obj.attributes),
          relations: [
            for (final rel in obj.relations)
              rel.copyWith(
                name: BusinessAttribute.isValidDslIdentifier(rel.name)
                    ? rel.name
                    : BusinessAttribute.normalizeDslIdentifier(
                        rel.name,
                        fallback: 'relation',
                      ),
              ),
          ],
        ),
    ];
  }

  /// Filtre récursivement les nœuds d'arbre `SuperTreeView` selon [query].
  static List<Map<String, Object?>> filterTreeNodes(
    List<Map<String, Object?>> nodes,
    String query,
  ) {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return nodes;
    final result = <Map<String, Object?>>[];
    for (final node in nodes) {
      final name = ((node['displayName'] as String?) ?? '').toLowerCase();
      final type = ((node['displayType'] as String?) ?? '').toLowerCase();
      final attrType = ((node['attrType'] as String?) ?? '').toLowerCase();
      final selfMatches =
          name.contains(lowerQuery) ||
          type.contains(lowerQuery) ||
          attrType.contains(lowerQuery);
      final rawChildren = node['children'];
      final children = rawChildren is List
          ? [
              for (final c in rawChildren)
                if (c is Map<String, Object?>) c,
            ]
          : const <Map<String, Object?>>[];
      final filteredChildren = filterTreeNodes(children, lowerQuery);
      if (selfMatches) {
        result.add(node);
      } else if (filteredChildren.isNotEmpty) {
        result.add(<String, Object?>{
          ...node,
          'children': filteredChildren,
        });
      }
    }
    return result;
  }

  /// Parse une source YAML « JSON Schemas Light » vers une liste d'objets métiers
  /// en conservant les métadonnées des objets [existing].
  static List<BusinessObjectSpec> applyYamlSource(
    String yamlSource, {
    List<BusinessObjectSpec> existing = const <BusinessObjectSpec>[],
  }) => SpecSchemaDslBridge.fromYamlLight(yamlSource, existing: existing);

  static List<BusinessAttribute> _removeAttrRec(
    List<BusinessAttribute> list,
    List<String> remaining,
  ) {
    if (remaining.length == 1) {
      return list.where((a) => a.id != remaining.first).toList();
    }
    final head = remaining.first;
    return [
      for (final attr in list)
        if (attr.id == head)
          attr.copyWith(
            children: _removeAttrRec(attr.children, remaining.sublist(1)),
          )
        else
          attr,
    ];
  }
}
