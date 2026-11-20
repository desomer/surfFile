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

import '../../models/business_object_spec.dart';
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
          buf.writeln('  ${attr.name}: ${_formatDslType(project, attr)}');
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

  /// Génère le JSON Schema Draft 2020-12 et les données de démarrage pour chaque agrégat racine.
  static SuperDesignerExportBundle toBundle(SpecForgeProject project) {
    final schemas = <String, Map<String, Object?>>{};
    final seeds = <String, Map<String, Object?>>{};

    final roots = project.businessObjects.where((o) => o.aggregateRoot).toList();
    final objects = roots.isNotEmpty ? roots : project.businessObjects;

    for (final obj in objects) {
      final repoAlias = _toSnakeCase(obj.technicalName);
      final collectionKey = _pluralizeSnake(repoAlias);
      final itemSchema = _objectToJsonSchema(project, obj, visited: {obj.id});

      schemas[repoAlias] = <String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'title': obj.name,
        'description': obj.description,
        'type': 'object',
        'required': [collectionKey],
        'properties': <String, Object?>{
          collectionKey: <String, Object?>{
            'type': 'array',
            'items': itemSchema,
          },
        },
      };

      seeds[repoAlias] = <String, Object?>{
        collectionKey: [
          _buildSampleRecord(project, obj, visited: {obj.id}),
        ],
      };
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

  static String _formatDslType(
    SpecForgeProject project,
    BusinessAttribute attr,
  ) {
    var base = switch (attr.type) {
      BusinessAttributeType.enumeration when attr.enumValues.isNotEmpty =>
        'enum(${attr.enumValues.join(', ')})',
      BusinessAttributeType.enumeration => 'string(enum)',
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

  static Map<String, Object?> _objectToJsonSchema(
    SpecForgeProject project,
    BusinessObjectSpec obj, {
    required Set<String> visited,
  }) {
    final properties = <String, Object?>{};
    final required = <String>[];

    for (final attr in obj.attributes) {
      properties[attr.name] = _attributeToJsonSchema(attr);
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
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
    };
  }

  static Map<String, Object?> _attributeToJsonSchema(BusinessAttribute attr) {
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
      BusinessAttributeType.json => <String, Object?>{'type': 'object'},
    };
    if (attr.description.isNotEmpty) {
      schema['description'] = attr.description;
    }
    if (attr.isArray) {
      return <String, Object?>{'type': 'array', 'items': schema};
    }
    return schema;
  }

  static Map<String, Object?> _buildSampleRecord(
    SpecForgeProject project,
    BusinessObjectSpec obj, {
    required Set<String> visited,
  }) {
    final record = <String, Object?>{};
    for (final attr in obj.attributes) {
      final sample = _sampleValueForAttribute(attr);
      record[attr.name] = attr.isArray ? [sample] : sample;
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
            )
          : 'ref_1';
      record[rel.name] = isList ? [value] : value;
    }
    return record;
  }

  static Object _sampleValueForAttribute(BusinessAttribute attr) {
    if (attr.defaultValue != null && attr.defaultValue!.trim().isNotEmpty) {
      return attr.defaultValue!.trim();
    }
    return switch (attr.type) {
      BusinessAttributeType.string => 'Exemple ${attr.name}',
      BusinessAttributeType.integer => 1,
      BusinessAttributeType.number => 100.0,
      BusinessAttributeType.boolean => true,
      BusinessAttributeType.date => '2026-01-15',
      BusinessAttributeType.datetime => '2026-01-15T10:30:00Z',
      BusinessAttributeType.uuid => '00000000-0000-4000-8000-000000000001',
      BusinessAttributeType.email => 'contact@exemple.fr',
      BusinessAttributeType.url => 'https://exemple.fr',
      BusinessAttributeType.enumeration =>
        attr.enumValues.isNotEmpty ? attr.enumValues.first : 'valeur',
      BusinessAttributeType.reference => 'ref_001',
      BusinessAttributeType.json => <String, Object?>{},
    };
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
