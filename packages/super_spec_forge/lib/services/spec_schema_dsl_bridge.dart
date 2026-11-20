/// Pont bidirectionnel entre [BusinessObjectSpec], le DSL YAML « JSON Schemas Light »
/// ([Yaml2JsonSchemasParser]) et l'arbre `nodes` affiché dans `SuperTreeView` ([SpecSchemaDslBridge]).
library;

import 'package:shortid/shortid.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_spec.dart';
import '../models/spec_forge_project.dart';
import 'exporters/spec_super_designer_exporter.dart';

/// Convertit les objets métiers structurés vers/depuis `Yaml2JsonSchemasParser` et `SuperTreeView`.
abstract final class SpecSchemaDslBridge {
  /// Génère la source YAML « JSON Schemas Light » à partir des objets métiers du projet.
  static String toYamlLight(SpecForgeProject project) =>
      SpecSuperDesignerExporter.toYamlLightSchema(project);

  /// Parse [project.businessObjects] via [Yaml2JsonSchemasParser] et retourne
  /// la liste hiérarchique de cartes JSON prêtes pour le `SuperTreeView` (`nodes`).
  static List<Map<String, Object?>> buildTreeNodes(SpecForgeProject project) {
    if (project.businessObjects.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    final yaml = toYamlLight(project);
    final parsedNodes = Yaml2JsonSchemasParser().parse(yaml);
    final objectsByTech = <String, BusinessObjectSpec>{
      for (final obj in project.businessObjects) obj.technicalName: obj,
    };

    return [
      for (final root in parsedNodes)
        _enrichRootNode(root, objectsByTech[root.name]),
    ];
  }

  /// Convertit une source YAML « JSON Schemas Light » éditée manuellement en
  /// liste de [BusinessObjectSpec], en conservant les métadonnées des objets
  /// [existing] (IDs, descriptions, relations, `estimatedMaxRows`, cycles de vie).
  static List<BusinessObjectSpec> fromYamlLight(
    String yaml, {
    List<BusinessObjectSpec> existing = const <BusinessObjectSpec>[],
  }) {
    final parsedNodes = Yaml2JsonSchemasParser().parse(yaml);
    final existingByTech = <String, BusinessObjectSpec>{
      for (final obj in existing) obj.technicalName.toLowerCase(): obj,
    };
    final existingByName = <String, BusinessObjectSpec>{
      for (final obj in existing) obj.name.toLowerCase(): obj,
    };
    final knownTypeNames = {
      for (final node in parsedNodes)
        if (node.type != Yaml2JsonSchemasParser.endpointType) node.name,
    };

    final result = <BusinessObjectSpec>[];
    for (final root in parsedNodes) {
      if (root.type == Yaml2JsonSchemasParser.endpointType) continue;
      final prev =
          existingByTech[root.name.toLowerCase()] ??
          existingByName[root.name.toLowerCase()];
      final prevAttrsByName = <String, BusinessAttribute>{
        if (prev != null)
          for (final a in prev.attributes) a.name: a,
      };
      final prevRelsByName = <String, BusinessRelation>{
        if (prev != null)
          for (final r in prev.relations) r.name: r,
      };
      final attrs = <BusinessAttribute>[];
      final rels = <BusinessRelation>[];
      for (final child in root.children) {
        if (child.type == Yaml2JsonSchemasParser.whenType) continue;
        final prevRel = prevRelsByName[child.name];
        if (prevRel != null && knownTypeNames.contains(child.type)) {
          final isList = child.properties['array'] == true;
          final targetPrev =
              existingByTech[child.type.toLowerCase()] ??
              existingByName[child.type.toLowerCase()];
          rels.add(
            prevRel.copyWith(
              targetObjectId: targetPrev?.id ??
                  'obj_${_sanitizeId(child.type).toLowerCase()}',
              cardinality: isList
                  ? BusinessRelationCardinality.oneToMany
                  : BusinessRelationCardinality.oneToOne,
              required: child.properties['required'] == true,
            ),
          );
          continue;
        }
        attrs.add(
          _nodeToAttribute(
            child,
            prev: prevAttrsByName[child.name],
            knownTypeNames: knownTypeNames,
            existingObjects: existing,
          ),
        );
      }

      final obj = BusinessObjectSpec(
        id: prev?.id ?? 'obj_${_sanitizeId(root.name).toLowerCase()}',
        name: prev?.name ?? root.name,
        technicalName: root.name,
        description: prev?.description ?? '',
        aggregateRoot: prev?.aggregateRoot ?? true,
        attributes: attrs,
        relations: rels,
        lifecycleStates: prev?.lifecycleStates ?? const [],
        lifecycleTransitions: prev?.lifecycleTransitions ?? const [],
      );
      obj.validate();
      result.add(obj);
    }
    return result;
  }

  static Map<String, Object?> _enrichRootNode(
    JsonNode root,
    BusinessObjectSpec? obj,
  ) {
    final base = root.toJson();
    final attrByName = <String, BusinessAttribute>{
      if (obj != null)
        for (final a in obj.attributes) a.name: a,
    };
    final relByName = <String, BusinessRelation>{
      if (obj != null)
        for (final r in obj.relations) r.name: r,
    };

    base['objectId'] = obj?.id ?? '';
    base['isRootObject'] = true;
    base['displayName'] = obj != null ? '${obj.name} (${obj.technicalName})' : root.name;
    base['totalAttributes'] = obj?.totalAttributeCount ?? root.children.length;
    base['maxAttributes'] = BusinessObjectSpec.maxAttributesPerObject;
    base['displayType'] = obj != null
        ? '${obj.totalAttributeCount}/${BusinessObjectSpec.maxAttributesPerObject} attr.'
        : 'Objet';
    base['attributePath'] = const <String>[];
    base['children'] = [
      for (var i = 0; i < root.children.length; i++)
        _enrichChildNode(
          root.children[i],
          objectId: obj?.id ?? '',
          attr: attrByName[root.children[i].name],
          rel: relByName[root.children[i].name],
          pathIds: const <String>[],
        ),
    ];
    base['typeIcon'] = 'container';
    return base;
  }

  static Map<String, Object?> _enrichChildNode(
    JsonNode node, {
    required String objectId,
    required BusinessAttribute? attr,
    required BusinessRelation? rel,
    required List<String> pathIds,
  }) {
    final map = node.toJson();
    final nextPath = attr != null ? [...pathIds, attr.id] : pathIds;
    final childByName = <String, BusinessAttribute>{
      if (attr != null)
        for (final c in attr.children) c.name: c,
    };

    final isArray =
        (attr?.isArray ?? false) || (node.properties['array'] == true);
    final isRequired =
        (attr?.required ?? false) || (node.properties['required'] == true);
    final isNullable =
        (attr?.nullable ?? false) || (node.properties['nullable'] == true);

    final typeLabel = StringBuffer();
    if (rel != null) {
      typeLabel.write('Relation (${rel.cardinality.symbol}) → ${node.type}');
    } else if (attr?.type == BusinessAttributeType.object ||
        node.type == Yaml2JsonSchemasParser.objectType) {
      typeLabel.write(isArray ? 'Sous-objets[]' : 'Sous-objet');
    } else {
      typeLabel.write(node.type);
      if (isArray) typeLabel.write('[]');
    }
    if (isRequired) typeLabel.write('!');
    if (isNullable) typeLabel.write('?');
    if (isArray && attr?.estimatedMaxRows != null) {
      typeLabel.write(' · max ${attr!.estimatedMaxRows} lignes');
    }
    if (attr != null && attr.enumValues.isNotEmpty) {
      typeLabel.write(' (${attr.enumValues.join(', ')})');
    }
    if (attr != null && attr.schemaConstraints.isNotEmpty) {
      final summary = attr.schemaConstraints.formatSummary();
      if (summary.isNotEmpty) {
        typeLabel.write(' [$summary]');
      }
    }

    map['objectId'] = objectId;
    map['attributeId'] = attr?.id ?? '';
    map['relationId'] = rel?.id ?? '';
    map['attrType'] = attr?.type.name ?? '';
    map['hasConstraints'] = attr?.schemaConstraints.isNotEmpty ?? false;
    map['isRootObject'] = false;
    map['isArray'] = isArray;
    map['isRequired'] = isRequired;
    map['isNullable'] = isNullable;
    map['estimatedMaxRows'] = attr?.estimatedMaxRows;
    map['attributePath'] = nextPath;
    map['displayName'] = node.name;
    map['displayType'] = typeLabel.toString();

    if (node.children.isNotEmpty) {
      map['typeIcon'] = 'container';
      map['children'] = [
        for (final child in node.children)
          _enrichChildNode(
            child,
            objectId: objectId,
            attr: childByName[child.name],
            rel: null,
            pathIds: nextPath,
          ),
      ];
    } else {
      map['typeIcon'] = attr?.type == BusinessAttributeType.object
          ? 'container'
          : 'value';
    }
    return map;
  }

  static BusinessAttribute _nodeToAttribute(
    JsonNode node, {
    required BusinessAttribute? prev,
    required Set<String> knownTypeNames,
    required List<BusinessObjectSpec> existingObjects,
  }) {
    final isArray = node.properties['array'] == true;
    final isRequired = node.properties['required'] == true;
    final isNullable = node.properties['nullable'] == true;
    final rawDefault = node.properties['default']?.toString();
    final rawEnum = node.properties['enum'];
    final enumValues = rawEnum is List
        ? [for (final v in rawEnum) '$v']
        : const <String>[];

    final prevChildren = <String, BusinessAttribute>{
      if (prev != null)
        for (final c in prev.children) c.name: c,
    };

    if (node.type == Yaml2JsonSchemasParser.objectType) {
      final children = <BusinessAttribute>[
        for (final child in node.children)
          if (child.type != Yaml2JsonSchemasParser.whenType)
            _nodeToAttribute(
              child,
              prev: prevChildren[child.name],
              knownTypeNames: knownTypeNames,
              existingObjects: existingObjects,
            ),
      ];
      return BusinessAttribute(
        id: prev?.id ?? 'attr_${shortid.generate()}',
        name: node.name,
        type: BusinessAttributeType.object,
        required: isRequired,
        nullable: isNullable,
        unique: prev?.unique ?? false,
        isArray: isArray,
        estimatedMaxRows: prev?.estimatedMaxRows,
        defaultValue: rawDefault ?? prev?.defaultValue,
        description: prev?.description ?? '',
        constraints: prev?.constraints ?? '',
        schemaConstraints: prev?.schemaConstraints,
        children: children,
      );
    }

    var refObjectId = '';
    late final BusinessAttributeType type;
    if (enumValues.isNotEmpty || node.type == Yaml2JsonSchemasParser.enumType) {
      type = BusinessAttributeType.enumeration;
    } else if (knownTypeNames.contains(node.type)) {
      type = BusinessAttributeType.reference;
      final matched = existingObjects
          .where((o) => o.technicalName.toLowerCase() == node.type.toLowerCase())
          .firstOrNull;
      refObjectId = matched?.id ?? node.type;
    } else {
      type = BusinessAttributeType.fromJson(node.type);
    }

    return BusinessAttribute(
      id: prev?.id ?? 'attr_${shortid.generate()}',
      name: node.name,
      type: type,
      required: isRequired,
      nullable: isNullable,
      unique: prev?.unique ?? false,
      isArray: isArray,
      estimatedMaxRows: prev?.estimatedMaxRows,
      defaultValue: rawDefault ?? prev?.defaultValue,
      enumValues: enumValues.isNotEmpty ? enumValues : (prev?.enumValues ?? const []),
      referenceObjectId:
          refObjectId.isNotEmpty ? refObjectId : (prev?.referenceObjectId ?? ''),
      description: prev?.description ?? '',
      constraints: prev?.constraints ?? '',
      schemaConstraints: prev?.schemaConstraints,
    );
  }

  static String _sanitizeId(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'objet' : cleaned;
  }
}
