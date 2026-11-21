/// Passerelle d'export vers `super_designer` et `super_container_layout` ([SpecSuperDesignerExporter]).
///
/// Génère :
/// 1. Un schéma YAML « JSON Schemas Light » compatible avec `Yaml2JsonSchemasParser` de `super_designer` ;
/// 2. Des paires (JSON Schema Draft 2020-12 + document de seed) conformes à `REPOSITORY_JSON_AI_GUIDE.md` ;
/// 3. Une exportation complète vers un dossier d'application sandboxée via [SandboxedApplicationStore].
library;

import 'dart:convert';
import 'dart:io';

import 'package:super_container_layout/super_container_layout.dart';

import '../../models/business_object_model_preferences.dart';
import '../../models/business_object_spec.dart';
import '../../models/json_schema_constraints.dart';
import '../../models/spec_forge_project.dart';

/// Bundle généré pour intégration directe dans `super_designer` / `super_container_layout`.
class SuperDesignerExportBundle {
  /// Construit un bundle d'export.
  const SuperDesignerExportBundle({
    required this.yamlLightSchema,
    required this.repositoriesJsonSchemas,
    required this.repositoriesSeedData,
  });

  /// Source YAML « JSON Schemas Light » pour `super_designer`.
  final String yamlLightSchema;

  /// Carte `<repoAlias> -> JSON Schema Draft 2020-12`.
  final Map<String, Map<String, Object?>> repositoriesJsonSchemas;

  /// Carte `<repoAlias> -> document JSON initial` (racine Objet `{...}`).
  final Map<String, Map<String, Object?>> repositoriesSeedData;
}

/// Convertit les objets métiers et règles de [SpecForgeProject] vers `super_designer` et `super_container_layout`.
abstract final class SpecSuperDesignerExporter {
  /// Génère le YAML « JSON Schemas Light » compatible avec `Yaml2JsonSchemasParser`.
  static String toYamlLightSchema(SpecForgeProject project) {
    if (project.businessObjects.isEmpty) {
      return '# Aucun objet métier défini dans ${project.name}\n';
    }
    final buf = StringBuffer()
      ..writeln('# Schéma généré par SuperSpecForge — ${project.name}')
      ..writeln();

    for (final obj in project.businessObjects) {
      buf.writeln('${obj.technicalName}:');
      if (obj.attributes.isEmpty && obj.relations.isEmpty) {
        buf.writeln('  id: uuid!');
      } else {
        for (final attr in obj.attributes) {
          _writeDslAttribute(buf, project, attr, indent: '  ');
        }
        for (final rel in obj.relations) {
          final target = project.findBusinessObject(rel.targetObjectId);
          final targetType = target?.technicalName ?? _toPascal(rel.targetObjectId);
          final isList =
              rel.cardinality == BusinessRelationCardinality.oneToMany ||
              rel.cardinality == BusinessRelationCardinality.manyToMany;
          final suffix = rel.required ? '!' : '';
          final key = isList ? '${rel.name}[]' : rel.name;
          buf.writeln('  $key: $targetType$suffix');
        }
      }
      buf.writeln();
    }
    return '${buf.toString().trimRight()}\n';
  }

  /// Calcule l'alias snake_case du repository associé à [obj].
  static String repoAliasFor(BusinessObjectSpec obj) =>
      _toSnakeCase(obj.technicalName);

  /// Calcule la clé de collection plurielle associée à un [repoAlias].
  static String collectionKeyFor(String repoAlias) =>
      _pluralizeSnake(repoAlias);

  /// Construit le couple `(alias, schema, seed)` pour un objet métier [obj].
  static ({
    String alias,
    Map<String, Object?> schema,
    Map<String, Object?> seed,
  })
  buildRepositoryPreview(
    SpecForgeProject project,
    BusinessObjectSpec obj, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) {
    final prefs =
        modelPreferencesOverride ?? project.businessObjectModelPreferences;
    final strictObjects = prefs.schemaStrictness == JsonSchemaStrictness.strict;
    final locale = prefs.localeProfile;
    final repoAlias = repoAliasFor(obj);
    final collectionKey = collectionKeyFor(repoAlias);
    final itemSchema = _objectToJsonSchema(
      project,
      obj,
      visited: {obj.id},
      strictObjects: strictObjects,
    );

    final schema = <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': obj.name,
      'description': obj.description,
      'type': 'object',
      if (strictObjects) 'additionalProperties': false,
      'required': [collectionKey],
      'properties': <String, Object?>{
        collectionKey: <String, Object?>{
          'type': 'array',
          'items': itemSchema,
        },
      },
    };

    final seed = <String, Object?>{
      collectionKey: [
        _buildSampleRecord(
          project,
          obj,
          visited: {obj.id},
          localeProfile: locale,
        ),
      ],
    };

    return (alias: repoAlias, schema: schema, seed: seed);
  }

  /// Génère le JSON Schema Draft 2020-12 et les données de démarrage pour chaque agrégat racine.
  static SuperDesignerExportBundle toBundle(
    SpecForgeProject project, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) {
    final schemas = <String, Map<String, Object?>>{};
    final seeds = <String, Map<String, Object?>>{};

    final roots = project.businessObjects.where((o) => o.aggregateRoot).toList();
    final objects = roots.isNotEmpty ? roots : project.businessObjects;

    for (final obj in objects) {
      final preview = buildRepositoryPreview(
        project,
        obj,
        modelPreferencesOverride: modelPreferencesOverride,
      );
      schemas[preview.alias] = preview.schema;
      seeds[preview.alias] = preview.seed;
    }

    return SuperDesignerExportBundle(
      yamlLightSchema: toYamlLightSchema(project),
      repositoriesJsonSchemas: Map<String, Map<String, Object?>>.unmodifiable(
        schemas,
      ),
      repositoriesSeedData: Map<String, Map<String, Object?>>.unmodifiable(
        seeds,
      ),
    );
  }

  /// Exporte le projet sous forme d'une application sandboxée prête à être ouverte dans `super_designer` / `super_container_layout`.
  static Future<SandboxedApplicationManifest> exportToSandboxedApplication(
    SpecForgeProject project,
    Directory targetDirectory, {
    SandboxedApplicationStore? applicationStore,
  }) async {
    final store = applicationStore ?? SandboxedApplicationStore();
    final inspection = await store.inspectDirectory(targetDirectory);
    final manifest = inspection.exists
        ? await store.openApplication(targetDirectory, initializeNonEmpty: true)
        : await store.createApplication(targetDirectory, name: project.name);

    final bundle = toBundle(project);
    final repoStore = SandboxedApplicationStore.repositoryStoreFor(
      targetDirectory,
    );
    try {
      for (final entry in bundle.repositoriesSeedData.entries) {
        final alias = entry.key;
        final seed = entry.value;
        final rawSchema = bundle.repositoriesJsonSchemas[alias];

        final repo = RepositoryImpl(
          id: alias,
          json: seed,
          jsonSchema: rawSchema,
        );
        await repoStore.registerPersistentRepository(repo);
      }

      // Dépose aussi le schéma YAML « JSON Schemas Light » dans le dossier de l'application.
      final yamlFile = File(
        '${targetDirectory.path}${Platform.pathSeparator}spec_forge_schema.yaml',
      );
      await yamlFile.writeAsString(bundle.yamlLightSchema, flush: true);

      final specSummaryFile = File(
        '${targetDirectory.path}${Platform.pathSeparator}spec_forge_project.json',
      );
      await specSummaryFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(project.toJson()),
        flush: true,
      );
    } finally {
      repoStore.dispose();
    }
    return manifest;
  }

  static void _writeDslAttribute(
    StringBuffer buf,
    SpecForgeProject project,
    BusinessAttribute attr, {
    required String indent,
  }) {
    if (attr.type == BusinessAttributeType.object && attr.children.isNotEmpty) {
      final arraySuffix = attr.isArray ? '[]' : '';
      final reqSuffix = attr.required ? '!' : (attr.nullable ? '?' : '');
      buf.writeln('$indent${attr.name}$arraySuffix$reqSuffix:');
      for (final child in attr.children) {
        _writeDslAttribute(buf, project, child, indent: '$indent  ');
      }
      return;
    }
    buf.writeln('$indent${attr.name}: ${_formatDslType(project, attr)}');
  }

  static String _formatDslType(
    SpecForgeProject project,
    BusinessAttribute attr,
  ) {
    var base = switch (attr.type) {
      BusinessAttributeType.enumeration when attr.enumValues.isNotEmpty =>
        'enum(${attr.enumValues.join(', ')})',
      BusinessAttributeType.enumeration => 'string(enum)',
      BusinessAttributeType.object => 'json',
      BusinessAttributeType.reference =>
        project.findBusinessObject(attr.referenceObjectId)?.technicalName ??
            (attr.referenceObjectId.isNotEmpty
                ? _toPascal(attr.referenceObjectId)
                : 'string'),
      _ => attr.type.dslKeyword,
    };

    if (attr.isArray) {
      base = '$base[]';
    }
    if (attr.required) {
      base = '$base!';
    } else if (attr.nullable) {
      base = '$base?';
    }
    if (attr.defaultValue != null && attr.defaultValue!.trim().isNotEmpty) {
      base = '$base = ${attr.defaultValue!.trim()}';
    }
    return base;
  }

  /// Construit le sous-schéma JSON Schema Draft 2020-12 complet d'un [BusinessObjectSpec].
  static Map<String, Object?> objectToJsonSchema(
    SpecForgeProject project,
    BusinessObjectSpec obj,
  ) => _objectToJsonSchema(
    project,
    obj,
    visited: {obj.id},
    strictObjects:
        project.businessObjectModelPreferences.schemaStrictness ==
        JsonSchemaStrictness.strict,
  );

  static Map<String, Object?> _objectToJsonSchema(
    SpecForgeProject project,
    BusinessObjectSpec obj, {
    required Set<String> visited,
    required bool strictObjects,
  }) {
    final properties = <String, Object?>{};
    final required = <String>[];

    for (final attr in obj.attributes) {
      properties[attr.name] = attributeToJsonSchema(
        attr,
        strictObjects: strictObjects,
      );
      if (attr.required) required.add(attr.name);
    }

    for (final rel in obj.relations) {
      final target = project.findBusinessObject(rel.targetObjectId);
      final isList =
          rel.cardinality == BusinessRelationCardinality.oneToMany ||
          rel.cardinality == BusinessRelationCardinality.manyToMany;
      final Map<String, Object?> itemOrRefSchema;
      if (target != null && !visited.contains(target.id)) {
        itemOrRefSchema = _objectToJsonSchema(
          project,
          target,
          visited: {...visited, target.id},
          strictObjects: strictObjects,
        );
      } else {
        itemOrRefSchema = <String, Object?>{'type': 'string'};
      }
      properties[rel.name] = isList
          ? <String, Object?>{'type': 'array', 'items': itemOrRefSchema}
          : itemOrRefSchema;
      if (rel.required) required.add(rel.name);
    }

    return <String, Object?>{
      'type': 'object',
      if (obj.description.isNotEmpty) 'description': obj.description,
      if (strictObjects) 'additionalProperties': false,
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
    };
  }

  static const Set<String> _arrayOnlyKeywords = <String>{
    'minItems',
    'maxItems',
    'uniqueItems',
    'contains',
    'minContains',
    'maxContains',
    'prefixItems',
  };

  /// Construit le sous-schéma JSON Schema Draft 2020-12 complet d'un [BusinessAttribute].
  static Map<String, Object?> attributeToJsonSchema(
    BusinessAttribute attr, {
    bool strictObjects = false,
  }) {
    final schema = switch (attr.type) {
      BusinessAttributeType.string => <String, Object?>{'type': 'string'},
      BusinessAttributeType.integer => <String, Object?>{'type': 'integer'},
      BusinessAttributeType.number => <String, Object?>{'type': 'number'},
      BusinessAttributeType.boolean => <String, Object?>{'type': 'boolean'},
      BusinessAttributeType.date => <String, Object?>{
        'type': 'string',
        'format': 'date',
      },
      BusinessAttributeType.datetime => <String, Object?>{
        'type': 'string',
        'format': 'date-time',
      },
      BusinessAttributeType.uuid => <String, Object?>{
        'type': 'string',
        'format': 'uuid',
      },
      BusinessAttributeType.email => <String, Object?>{
        'type': 'string',
        'format': 'email',
      },
      BusinessAttributeType.url => <String, Object?>{
        'type': 'string',
        'format': 'uri',
      },
      BusinessAttributeType.enumeration => <String, Object?>{
        'type': 'string',
        if (attr.enumValues.isNotEmpty) 'enum': attr.enumValues,
      },
      BusinessAttributeType.reference => <String, Object?>{'type': 'string'},
      BusinessAttributeType.object when attr.children.isNotEmpty =>
        <String, Object?>{
          'type': 'object',
          if (strictObjects) 'additionalProperties': false,
          if (attr.children.any((c) => c.required))
            'required': [
              for (final c in attr.children)
                if (c.required) c.name,
            ],
          'properties': <String, Object?>{
            for (final c in attr.children)
              c.name: attributeToJsonSchema(c, strictObjects: strictObjects),
          },
        },
      BusinessAttributeType.object => <String, Object?>{
        'type': 'object',
        if (strictObjects) 'additionalProperties': false,
      },
      BusinessAttributeType.json => <String, Object?>{'type': 'object'},
    };
    if (attr.description.isNotEmpty) {
      schema['description'] = attr.description;
    }

    final constraintMap = attr.schemaConstraints.toSchemaMap();
    final arrayConstraints = <String, Object?>{};
    for (final entry in constraintMap.entries) {
      if (attr.isArray && _arrayOnlyKeywords.contains(entry.key)) {
        arrayConstraints[entry.key] = entry.value;
      } else if (!_arrayOnlyKeywords.contains(entry.key)) {
        schema[entry.key] = entry.value;
      }
    }

    if (attr.nullable && schema['type'] is String) {
      schema['type'] = <String>[schema['type'] as String, 'null'];
    }

    if (attr.isArray) {
      final effectiveMaxItems =
          arrayConstraints['maxItems'] ?? attr.estimatedMaxRows;
      return <String, Object?>{
        'type': 'array',
        ...arrayConstraints,
        'maxItems': ?effectiveMaxItems,
        'items': schema,
      };
    }
    return schema;
  }

  static Map<String, Object?> _buildSampleRecord(
    SpecForgeProject project,
    BusinessObjectSpec obj, {
    required Set<String> visited,
    ModelLocaleProfile localeProfile = ModelLocaleProfile.frEur,
  }) {
    final record = <String, Object?>{};
    for (final attr in obj.attributes) {
      if (attr.isArray) {
        final minItems = attr.schemaConstraints.minItems ?? 1;
        final count = minItems < 1 ? 1 : (minItems > 5 ? 5 : minItems);
        record[attr.name] = [
          for (var i = 0; i < count; i++)
            _sampleValueForAttribute(
              attr,
              index: i,
              localeProfile: localeProfile,
            ),
        ];
      } else {
        record[attr.name] = _sampleValueForAttribute(
          attr,
          localeProfile: localeProfile,
        );
      }
    }
    for (final rel in obj.relations) {
      final target = project.findBusinessObject(rel.targetObjectId);
      final isList =
          rel.cardinality == BusinessRelationCardinality.oneToMany ||
          rel.cardinality == BusinessRelationCardinality.manyToMany;
      final value = (target != null && !visited.contains(target.id))
          ? _buildSampleRecord(
              project,
              target,
              visited: {...visited, target.id},
              localeProfile: localeProfile,
            )
          : 'ref_1';
      record[rel.name] = isList ? [value] : value;
    }
    return record;
  }

  static Object? _sampleValueForAttribute(
    BusinessAttribute attr, {
    int index = 0,
    ModelLocaleProfile localeProfile = ModelLocaleProfile.frEur,
  }) {
    final sc = attr.schemaConstraints;
    if (sc.hasConst) {
      return sc.constValue;
    }
    if (sc.examples.isNotEmpty && index < sc.examples.length) {
      return sc.examples[index];
    }
    if (attr.type == BusinessAttributeType.object && attr.children.isNotEmpty) {
      return <String, Object?>{
        for (final child in attr.children)
          child.name: child.isArray
              ? [
                  _sampleValueForAttribute(
                    child,
                    index: index,
                    localeProfile: localeProfile,
                  ),
                ]
              : _sampleValueForAttribute(
                  child,
                  index: index,
                  localeProfile: localeProfile,
                ),
      };
    }
    if (index == 0 &&
        attr.defaultValue != null &&
        attr.defaultValue!.trim().isNotEmpty) {
      return attr.defaultValue!.trim();
    }
    final emailParts = localeProfile.sampleEmail.split('@');
    final sampleEmail = index == 0
        ? localeProfile.sampleEmail
        : '${emailParts.first}$index@${emailParts.last}';
    return switch (attr.type) {
      BusinessAttributeType.string => _sampleString(attr, index: index),
      BusinessAttributeType.integer => _sampleInt(sc, index: index),
      BusinessAttributeType.number => _sampleDouble(sc, index: index),
      BusinessAttributeType.boolean => index.isEven,
      BusinessAttributeType.date => '2026-01-${(15 + (index % 14)).toString().padLeft(2, '0')}',
      BusinessAttributeType.datetime => '2026-01-${(15 + (index % 14)).toString().padLeft(2, '0')}T10:30:00Z',
      BusinessAttributeType.uuid =>
        '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
      BusinessAttributeType.email => sampleEmail,
      BusinessAttributeType.url =>
        index == 0 ? localeProfile.sampleUrl : '${localeProfile.sampleUrl}/$index',
      BusinessAttributeType.enumeration => attr.enumValues.isNotEmpty
          ? attr.enumValues[index % attr.enumValues.length]
          : 'valeur_${index + 1}',
      BusinessAttributeType.reference => 'ref_${(index + 1).toString().padLeft(3, '0')}',
      BusinessAttributeType.object => <String, Object?>{
        if (index > 0) 'index': index,
      },
      BusinessAttributeType.json => <String, Object?>{
        if (index > 0) 'index': index,
      },
    };
  }

  static String _sampleString(BusinessAttribute attr, {int index = 0}) {
    final minLen = attr.schemaConstraints.minLength ?? 0;
    final maxLen = attr.schemaConstraints.maxLength;
    var base = index == 0 ? 'Exemple ${attr.name}' : 'Exemple ${attr.name} ${index + 1}';
    if (minLen > base.length) {
      base = base.padRight(minLen, 'x');
    }
    if (maxLen != null && base.length > maxLen) {
      final suffix = index == 0 ? '' : '${index + 1}';
      if (suffix.isNotEmpty && maxLen > suffix.length) {
        base =
            '${base.substring(0, maxLen - suffix.length)}$suffix';
      } else {
        base = base.substring(0, maxLen);
      }
    }
    return base;
  }

  static int _sampleInt(JsonSchemaConstraints sc, {int index = 0}) {
    final low = sc.minimum?.ceil() ??
        (sc.exclusiveMinimum != null ? sc.exclusiveMinimum!.floor() + 1 : 1);
    final mult = sc.multipleOf?.round();
    if (mult != null && mult > 0) {
      final rem = low % mult;
      final aligned = rem == 0 ? low : low + (mult - rem);
      final candidate = aligned + (index * mult);
      if (sc.maximum != null && candidate > sc.maximum!) {
        return aligned;
      }
      return candidate;
    }
    final candidate = low + index;
    if (sc.maximum != null && candidate > sc.maximum!) {
      return low;
    }
    return candidate;
  }

  static double _sampleDouble(JsonSchemaConstraints sc, {int index = 0}) {
    final low = sc.minimum?.toDouble() ??
        (sc.exclusiveMinimum != null ? sc.exclusiveMinimum!.toDouble() + 1.0 : 10.0);
    final step = sc.multipleOf?.toDouble() ?? 1.0;
    final candidate = low + (index * step);
    if (sc.maximum != null && candidate > sc.maximum!) {
      return low;
    }
    return candidate;
  }

  static String _toSnakeCase(String input) {
    final withUnderscores = input
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toLowerCase();
    final base = withUnderscores.isEmpty ? 'entite' : withUnderscores;
    return base.length > 32 ? base.substring(0, 32) : base;
  }

  static String _pluralizeSnake(String snake) =>
      snake.endsWith('s') ? snake : '${snake}s';

  static String _toPascal(String input) {
    final words = input
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty);
    if (words.isEmpty) return 'ObjetMetier';
    return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join();
  }
}
