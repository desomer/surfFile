/// Passerelle d'export vers `super_designer` et `super_container_layout` ([SpecSuperDesignerExporter]).
///
/// Génère :
/// 1. Un schéma YAML « JSON Schemas Light » compatible avec `Yaml2JsonSchemasParser` de `super_designer` ;
/// 2. Des paires (JSON Schema Draft 2020-12 + document de seed) conformes à `REPOSITORY_JSON_AI_GUIDE.md` ;
/// 3. Une exportation complète vers un dossier d'application sandboxée via [SandboxedApplicationStore].
library;

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart'
    show
        Axis,
        CrossAxisAlignment,
        EdgeInsets,
        FontWeight,
        MainAxisAlignment,
        TextAlign,
        ThemeMode;
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/business_object_model_preferences.dart';
import '../../models/business_object_spec.dart';
import '../../models/json_schema_constraints.dart';
import '../../models/spec_forge_project.dart';
import '../../models/ux/ux_navigation_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import 'ux_design_md_exporter.dart';
import 'ux_markdown_exporter.dart';
import 'ux_super_designer_prompt_exporter.dart';

/// Bundle généré pour intégration directe dans `super_designer` / `super_container_layout`.
class SuperDesignerExportBundle {
  /// Construit un bundle d'export.
  const SuperDesignerExportBundle({
    required this.yamlLightSchema,
    required this.repositoriesJsonSchemas,
    required this.repositoriesSeedData,
    this.designMarkdown,
    this.superDesignerChatPrompt,
    this.initialAppearance,
  });

  /// Source YAML « JSON Schemas Light » pour `super_designer`.
  final String yamlLightSchema;

  /// Carte `<repoAlias> -> JSON Schema Draft 2020-12`.
  final Map<String, Map<String, Object?>> repositoriesJsonSchemas;

  /// Carte `<repoAlias> -> document JSON initial` (racine Objet `{...}`).
  final Map<String, Map<String, Object?>> repositoriesSeedData;

  /// Contenu `DESIGN.md` généré depuis l'identité visuelle UX du projet.
  final String? designMarkdown;

  /// Prompt Markdown prêt à coller dans le Vibe Chat de `SuperDesigner`.
  final String? superDesignerChatPrompt;

  /// Apparence initiale multi-pages générée depuis le volet UX du projet.
  final Appearance? initialAppearance;
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
          final targetType =
              target?.technicalName ?? _toPascal(rel.targetObjectId);
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
        collectionKey: <String, Object?>{'type': 'array', 'items': itemSchema},
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

  /// Génère le JSON Schema Draft 2020-12 et les données de démarrage pour tous les objets métiers du projet.
  static SuperDesignerExportBundle toBundle(
    SpecForgeProject project, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) {
    final schemas = <String, Map<String, Object?>>{};
    final seeds = <String, Map<String, Object?>>{};

    for (final obj in project.businessObjects) {
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
      designMarkdown: toDesignMarkdown(project),
      superDesignerChatPrompt: toSuperDesignerChatPrompt(project),
      initialAppearance: buildInitialAppearance(project),
    );
  }

  /// Génère le document `DESIGN.md` complet (frontmatter YAML + charte Markdown) depuis [project].
  static String toDesignMarkdown(SpecForgeProject project) =>
      UxDesignMdExporter.export(project);

  /// Génère le prompt Markdown prêt à l'emploi pour le Vibe Chat de `SuperDesigner`.
  static String toSuperDesignerChatPrompt(SpecForgeProject project) =>
      UxSuperDesignerPromptExporter.export(project);

  /// Construit une [Appearance] initiale multi-pages et thématisée à partir du volet UX de [project].
  ///
  /// Lorsque `routes` et `screens` sont tous deux vides, retourne un [DefaultAppearance]
  /// propre appliquant la couleur d'accentuation et le mode de thème de `visualTheme`.
  static Appearance buildInitialAppearance(SpecForgeProject project) {
    final nav = project.uxSpec.navigation;
    final seed = nav.visualTheme;
    final accent = JsonColor.parseLiteral(
      UxVisualThemeSeed.normalizeAccentHex(seed.accentHex),
      'accentHex',
    );
    final mode = switch (seed.themeMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final baseAppearance = DefaultAppearance(
      mode: mode,
      accent: accent,
      styles: const <String, ContainerStyle>{
        'background': ContainerStyle(
          color: ThemeColor(ThemeColorRole.surfaceContainerLowest),
          padding: 0,
        ),
      },
    );

    if (nav.routes.isEmpty && project.uxSpec.screens.isEmpty) {
      return baseAppearance;
    }

    try {
      final built = _UxAppearanceBlueprintBuilder(
        project: project,
        baseAppearance: baseAppearance,
      ).build();
      AppearanceTransfer.validateComponentRegions(built);
      final layoutStyleViolations =
          AppearanceTransfer.findIneffectiveLayoutStyleViolations(built);
      if (layoutStyleViolations.isNotEmpty) {
        throw FormatException(layoutStyleViolations.values.first);
      }
      // Vérifie l'encodage/décodage sans perte via AppearanceCodec.
      const codec = AppearanceCodec();
      codec.decode(codec.encode(built));
      return built;
    } on Object {
      return baseAppearance;
    }
  }

  /// Exporte le projet sous forme d'une application sandboxée prête à être ouverte dans `super_designer` / `super_container_layout`.
  static Future<SandboxedApplicationManifest> exportToSandboxedApplication(
    SpecForgeProject project,
    Directory targetDirectory, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
    SandboxedApplicationStore? applicationStore,
  }) async {
    final store = applicationStore ?? SandboxedApplicationStore();
    final inspection = await store.inspectDirectory(targetDirectory);
    final manifest = inspection.exists
        ? await store.openApplication(targetDirectory, initializeNonEmpty: true)
        : await store.createApplication(targetDirectory, name: project.name);

    final bundle = toBundle(
      project,
      modelPreferencesOverride: modelPreferencesOverride,
    );
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

      final promptFile = File(
        '${targetDirectory.path}${Platform.pathSeparator}prompt_super_designer.md',
      );
      await promptFile.writeAsString(
        bundle.superDesignerChatPrompt ?? toSuperDesignerChatPrompt(project),
        flush: true,
      );

      if (project.uxSpec.hasContent) {
        final designMarkdown =
            bundle.designMarkdown ?? toDesignMarkdown(project);
        final designPreset = DesignMdParser.parseExternal(designMarkdown);
        final customDesignStore = CustomDesignSystemStore.forRepositoryStore(
          repoStore,
        );
        await customDesignStore.save(designPreset);

        final designFile = File(
          '${targetDirectory.path}${Platform.pathSeparator}DESIGN.md',
        );
        await designFile.writeAsString(designMarkdown, flush: true);

        final uxMarkdownFile = File(
          '${targetDirectory.path}${Platform.pathSeparator}spec_forge_ux.md',
        );
        await uxMarkdownFile.writeAsString(
          UxMarkdownExporter.export(project),
          flush: true,
        );

        final initialAppearance =
            bundle.initialAppearance ?? buildInitialAppearance(project);
        final appearanceStore = SandboxedApplicationStore.appearanceStoreFor(
          targetDirectory,
        );
        await appearanceStore.save(initialAppearance);
      }
    } finally {
      repoStore.dispose();
    }
    return manifest;
  }

  /// Exporte sur disque l'ensemble des livrables UX & SuperDesigner (sans fichier HTML) :
  /// - `specification_ux.md`, `specification_ux.json` et `DESIGN.md` ;
  /// - `prompt_super_designer.md` (prompt prêt à coller dans le Chat de `SuperDesigner`) ;
  /// - `schema_light.yaml`, `repositories_bundle.json`, `json_schemas/<alias>.schema.json` et `repositories/<alias>.json` ;
  /// - et optionnellement le dossier `super_designer_app/` prêt à ouvrir dans `SuperDesigner`.
  static Future<void> exportUxAndSuperDesignerDirectory(
    SpecForgeProject project,
    Directory targetDirectory, {
    bool includeSandboxedApp = true,
    BusinessObjectModelPreferences? modelPreferencesOverride,
    SandboxedApplicationStore? applicationStore,
  }) async {
    await targetDirectory.create(recursive: true);
    final sep = Platform.pathSeparator;
    const prettyEncoder = JsonEncoder.withIndent('  ');

    // Supprime un éventuel ancien export HTML obsolète s'il était présent dans ce dossier.
    final legacyHtmlFile = File('${targetDirectory.path}${sep}specification_ux.html');
    if (await legacyHtmlFile.exists()) {
      await legacyHtmlFile.delete();
    }

    final bundle = toBundle(
      project,
      modelPreferencesOverride: modelPreferencesOverride,
    );
    final uxMarkdown = UxMarkdownExporter.export(project);
    final designMd = bundle.designMarkdown ?? toDesignMarkdown(project);
    final chatPrompt =
        bundle.superDesignerChatPrompt ?? toSuperDesignerChatPrompt(project);
    final uxJson = prettyEncoder.convert(project.uxSpec.toJson());
    final bundleJson = prettyEncoder.convert(<String, Object?>{
      'repositoriesJsonSchemas': bundle.repositoriesJsonSchemas,
      'repositoriesSeedData': bundle.repositoriesSeedData,
    });

    await File('${targetDirectory.path}${sep}specification_ux.md')
        .writeAsString(uxMarkdown, flush: true);
    await File('${targetDirectory.path}${sep}specification_ux.json')
        .writeAsString(uxJson, flush: true);
    await File('${targetDirectory.path}${sep}DESIGN.md')
        .writeAsString(designMd, flush: true);
    await File('${targetDirectory.path}${sep}prompt_super_designer.md')
        .writeAsString(chatPrompt, flush: true);
    await File('${targetDirectory.path}${sep}schema_light.yaml')
        .writeAsString(bundle.yamlLightSchema, flush: true);
    await File('${targetDirectory.path}${sep}repositories_bundle.json')
        .writeAsString(bundleJson, flush: true);

    final schemasDir = Directory('${targetDirectory.path}${sep}json_schemas');
    await schemasDir.create(recursive: true);
    for (final entry in bundle.repositoriesJsonSchemas.entries) {
      await File('${schemasDir.path}$sep${entry.key}.schema.json')
          .writeAsString('${prettyEncoder.convert(entry.value)}\n', flush: true);
    }

    final reposDir = Directory('${targetDirectory.path}${sep}repositories');
    await reposDir.create(recursive: true);
    for (final entry in bundle.repositoriesSeedData.entries) {
      await File('${reposDir.path}$sep${entry.key}.json')
          .writeAsString('${prettyEncoder.convert(entry.value)}\n', flush: true);
    }

    if (includeSandboxedApp) {
      await exportToSandboxedApplication(
        project,
        Directory('${targetDirectory.path}${sep}super_designer_app'),
        modelPreferencesOverride: modelPreferencesOverride,
        applicationStore: applicationStore,
      );
    }
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
      BusinessAttributeType.date =>
        '2026-01-${(15 + (index % 14)).toString().padLeft(2, '0')}',
      BusinessAttributeType.datetime =>
        '2026-01-${(15 + (index % 14)).toString().padLeft(2, '0')}T10:30:00Z',
      BusinessAttributeType.uuid =>
        '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
      BusinessAttributeType.email => sampleEmail,
      BusinessAttributeType.url =>
        index == 0
            ? localeProfile.sampleUrl
            : '${localeProfile.sampleUrl}/$index',
      BusinessAttributeType.enumeration =>
        attr.enumValues.isNotEmpty
            ? attr.enumValues[index % attr.enumValues.length]
            : 'valeur_${index + 1}',
      BusinessAttributeType.reference =>
        'ref_${(index + 1).toString().padLeft(3, '0')}',
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
    var base = index == 0
        ? 'Exemple ${attr.name}'
        : 'Exemple ${attr.name} ${index + 1}';
    if (minLen > base.length) {
      base = base.padRight(minLen, 'x');
    }
    if (maxLen != null && base.length > maxLen) {
      final suffix = index == 0 ? '' : '${index + 1}';
      if (suffix.isNotEmpty && maxLen > suffix.length) {
        base = '${base.substring(0, maxLen - suffix.length)}$suffix';
      } else {
        base = base.substring(0, maxLen);
      }
    }
    return base;
  }

  static int _sampleInt(JsonSchemaConstraints sc, {int index = 0}) {
    final low =
        sc.minimum?.ceil() ??
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
    final low =
        sc.minimum?.toDouble() ??
        (sc.exclusiveMinimum != null
            ? sc.exclusiveMinimum!.toDouble() + 1.0
            : 10.0);
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

class _ResolvedPageEntry {
  const _ResolvedPageEntry({
    required this.route,
    required this.screen,
    required this.pageConfig,
    required this.prefix,
  });

  final UxRouteNode route;
  final UxScreenSpec screen;
  final EditorPageConfig pageConfig;
  final String prefix;
}

class _ResolvedRepoTarget {
  const _ResolvedRepoTarget({
    required this.object,
    required this.repoAlias,
    required this.collectionPath,
    required this.itemPrefix,
  });

  final BusinessObjectSpec object;
  final String repoAlias;
  final String? collectionPath;
  final String itemPrefix;
}

class _SlotLeafField {
  const _SlotLeafField({
    required this.relativePath,
    required this.label,
    required this.attribute,
  });

  final String relativePath;
  final String label;
  final BusinessAttribute attribute;
}

class _UxAppearanceBlueprintBuilder {
  _UxAppearanceBlueprintBuilder({
    required this.project,
    required this.baseAppearance,
  }) : nav = project.uxSpec.navigation,
       seed = project.uxSpec.navigation.visualTheme {
    final roots = project.businessObjects
        .where((o) => o.aggregateRoot)
        .toList();
    exportedObjects = roots.isNotEmpty ? roots : project.businessObjects;
    surfaceSystem = switch (seed.surfaceSystem) {
      'liquidGlass' => DesignSystem.liquidGlass,
      'neumorphism' => DesignSystem.neumorphism,
      _ => DesignSystem.material,
    };
    cardRadius = seed.cardRadius.isFinite
        ? seed.cardRadius.clamp(0.0, 32.0)
        : 14.0;
    itemRadius = (cardRadius - 4.0).clamp(6.0, 12.0);
    fontFamily = seed.fontFamily.trim().isEmpty
        ? 'Inter'
        : seed.fontFamily.trim();
    switch (seed.density) {
      case UxDensityProfile.compact:
        zoneSpacing = 12.0;
        zonePadding = 12.0;
        cardPadding = 16.0;
        innerSpacing = 8.0;
        listItemExtent = 52.0;
        tableRowHeight = 36.0;
      case UxDensityProfile.comfortable:
        zoneSpacing = 16.0;
        zonePadding = 16.0;
        cardPadding = 20.0;
        innerSpacing = 12.0;
        listItemExtent = 56.0;
        tableRowHeight = 40.0;
      case UxDensityProfile.spacious:
        zoneSpacing = 20.0;
        zonePadding = 20.0;
        cardPadding = 24.0;
        innerSpacing = 12.0;
        listItemExtent = 60.0;
        tableRowHeight = 40.0;
    }
  }

  final SpecForgeProject project;
  final DefaultAppearance baseAppearance;
  final UxNavigationSpec nav;
  final UxVisualThemeSeed seed;

  late final List<BusinessObjectSpec> exportedObjects;
  late final DesignSystem surfaceSystem;
  late final double cardRadius;
  late final double itemRadius;
  late final String fontFamily;
  late final double zoneSpacing;
  late final double zonePadding;
  late final double cardPadding;
  late final double innerSpacing;
  late final double listItemExtent;
  late final double tableRowHeight;

  final Map<String, ContainerStyle> _styles = <String, ContainerStyle>{
    'background': const ContainerStyle(
      color: ThemeColor(ThemeColorRole.surfaceContainerLowest),
      padding: 0,
    ),
  };
  final Map<String, ComponentConfig> _components = <String, ComponentConfig>{};
  final Map<String, List<ComponentBehavior>> _behaviors =
      <String, List<ComponentBehavior>>{};
  final Map<String, ComponentUsage> _usages = <String, ComponentUsage>{};
  final Set<String> _usedIds = <String>{'root', 'mainLayout', 'background'};
  final Set<String> _usedTranslationKeys = <String>{};
  final Map<String, EditorPageConfig> _routeLookup =
      <String, EditorPageConfig>{};

  int _seq = 0;

  DefaultAppearance build() {
    final entries = _resolvePages();
    if (entries.isEmpty) {
      return baseAppearance;
    }

    final homeEntry = _resolveHomeEntry(entries);
    final catalog = EditorPageCatalog(
      pages: [for (final e in entries) e.pageConfig],
      homePageId: homeEntry.pageConfig.id,
    );

    final primaryNavPages = [
      for (final e in entries)
        if (e.route.showInPrimaryNav && !e.pageConfig.pageType.isModal)
          e.pageConfig,
    ];

    // Configure également la page racine '/' (root + mainLayout) sur l'écran d'accueil.
    _buildRootHomeScaffold(
      homeScreen: homeEntry.screen,
      title: homeEntry.pageConfig.name,
      primaryNavPages: primaryNavPages,
    );

    // Génère le graphe complet de chaque page déclarée dans EditorPageCatalog.
    for (final entry in entries) {
      _buildCatalogPage(entry: entry, primaryNavPages: primaryNavPages);
    }

    return baseAppearance.copyWith(
      styles: _styles,
      components: _components,
      behaviors: _behaviors,
      usages: _usages,
      pageCatalog: catalog,
    );
  }

  List<_ResolvedPageEntry> _resolvePages() {
    final ux = project.uxSpec;
    final matchedScreenIds = <String>{};
    final pairs = <({UxRouteNode route, UxScreenSpec screen})>[];
    final seenRouteIds = <String>{};

    for (final route in nav.routes) {
      seenRouteIds.add(route.id.toLowerCase());
      UxScreenSpec? matched;
      for (final screen in ux.screens) {
        if (matchedScreenIds.contains(screen.id)) continue;
        if (_screenMatchesRoute(screen, route)) {
          matched = screen;
          matchedScreenIds.add(screen.id);
          break;
        }
      }
      pairs.add((
        route: route,
        screen: matched ?? _synthesizeScreenForRoute(route),
      ));
    }

    for (var i = 0; i < ux.screens.length; i++) {
      final screen = ux.screens[i];
      if (matchedScreenIds.contains(screen.id)) continue;
      var candidateRouteId = screen.routeId.trim().isNotEmpty
          ? screen.routeId.trim()
          : 'route_${_slugToken(screen.id, fallback: '${i + 1}')}';
      if (!seenRouteIds.add(candidateRouteId.toLowerCase())) {
        var suffix = 2;
        while (!seenRouteIds.add('${candidateRouteId}_$suffix'.toLowerCase())) {
          suffix++;
        }
        candidateRouteId = '${candidateRouteId}_$suffix';
      }
      final synthesizedRoute = UxRouteNode(
        id: candidateRouteId,
        path: '/${_slugSegment(screen.name, fallback: 'ecran-${i + 1}')}',
        title: screen.name,
        pageType: screen.pattern == UxScreenPattern.documentA4
            ? EditorPageType.a4Document
            : EditorPageType.standard,
        allowedPersonaIds: screen.personaIds,
      );
      pairs.add((route: synthesizedRoute, screen: screen));
    }

    final result = <_ResolvedPageEntry>[];
    final seenCatalogPaths = <String>{};
    final seenDynamicPrefixes = <String>{};

    for (var i = 0; i < pairs.length; i++) {
      final pair = pairs[i];
      final pageId = _allocatePageId(pair.route.id, index: i);
      final (:path, :defaultParams) = _allocateCatalogPath(
        rawPath: pair.route.path,
        fallbackSlug: _slugSegment(pair.route.title, fallback: 'accueil'),
        seenPaths: seenCatalogPaths,
        seenDynamicPrefixes: seenDynamicPrefixes,
      );

      final pageType =
          pair.screen.pattern == UxScreenPattern.documentA4 &&
              pair.route.pageType == EditorPageType.standard
          ? EditorPageType.a4Document
          : pair.route.pageType;

      final double? modalWidth = switch (pageType) {
        EditorPageType.dialog => 640,
        EditorPageType.sideSheet => 440,
        _ => null,
      };
      final double? modalHeight = switch (pageType) {
        EditorPageType.dialog => 520,
        EditorPageType.bottomSheet => 420,
        _ => null,
      };

      final pageConfig = EditorPageConfig(
        id: pageId,
        name: pair.route.title.trim().isNotEmpty
            ? pair.route.title.trim()
            : pair.screen.name,
        path: path,
        pageType: pageType,
        modalWidth: modalWidth,
        modalHeight: modalHeight,
        defaultParameters: defaultParams,
      );

      _routeLookup[pair.route.id.toLowerCase()] = pageConfig;
      _routeLookup[pair.route.path.toLowerCase()] = pageConfig;
      _routeLookup[pageId.toLowerCase()] = pageConfig;
      _routeLookup[path.toLowerCase()] = pageConfig;
      if (pair.screen.routeId.trim().isNotEmpty) {
        _routeLookup.putIfAbsent(
          pair.screen.routeId.trim().toLowerCase(),
          () => pageConfig,
        );
      }

      result.add(
        _ResolvedPageEntry(
          route: pair.route,
          screen: pair.screen,
          pageConfig: pageConfig,
          prefix: 'p${i + 1}',
        ),
      );
    }
    return result;
  }

  _ResolvedPageEntry _resolveHomeEntry(List<_ResolvedPageEntry> entries) {
    final explicitHome = nav.homeRouteId.trim().toLowerCase();
    if (explicitHome.isNotEmpty) {
      final normalizedHome = UxRouteNode.normalizePath(nav.homeRouteId)
          .toLowerCase();
      for (final entry in entries) {
        if (entry.route.id.toLowerCase() == explicitHome ||
            entry.route.path.toLowerCase() == explicitHome ||
            entry.route.path.toLowerCase() == normalizedHome ||
            entry.pageConfig.id.toLowerCase() == explicitHome) {
          return entry;
        }
      }
    }
    for (final entry in entries) {
      if (entry.route.path == '/' && !entry.pageConfig.pageType.isModal) {
        return entry;
      }
    }
    for (final entry in entries) {
      if (!entry.pageConfig.pageType.isModal) return entry;
    }
    return entries.first;
  }

  UxScreenSpec _synthesizeScreenForRoute(UxRouteNode route) {
    final defaultObj = exportedObjects.isNotEmpty
        ? exportedObjects.first
        : null;
    final pattern = switch (route.pageType) {
      EditorPageType.a4Document => UxScreenPattern.documentA4,
      EditorPageType.dialog ||
      EditorPageType.bottomSheet ||
      EditorPageType.sideSheet => UxScreenPattern.form,
      EditorPageType.standard =>
        defaultObj != null
            ? UxScreenPattern.masterDetail
            : UxScreenPattern.custom,
    };
    return UxScreenSpec(
      id: 'scr_auto_${_slugToken(route.id, fallback: 'view')}',
      code: 'SCR',
      name: route.title,
      routeId: route.id,
      pattern: pattern,
      primaryObjectId: defaultObj?.id ?? '',
      zones: UxScreenSpec.defaultZonesForPattern(pattern),
      states: UxScreenStatesSpec(
        emptyStateTitle: defaultObj != null
            ? 'Aucun élément ${defaultObj.name.toLowerCase()}'
            : 'Aucune donnée disponible',
      ),
    );
  }

  void _buildRootHomeScaffold({
    required UxScreenSpec homeScreen,
    required String title,
    required List<EditorPageConfig> primaryNavPages,
  }) {
    _buildScreenLayout(
      layoutId: 'mainLayout',
      prefix: 'root',
      screen: homeScreen,
      registerLayoutUsage: false,
    );

    String? appBarId;
    if (nav.hasAppBar) {
      appBarId = _buildApplicationBar(
        prefix: 'root',
        title: title,
        currentPageId: null,
        primaryNavPages: primaryNavPages,
      );
    }

    _components['root'] = ScaffoldPageConfig.fromNative(
      NativeComponentConfig(
        regions: <String, bool>{
          if (appBarId != null) 'appBar': true,
          'body': true,
        },
        placements: <String, List<String>>{
          if (appBarId != null) 'appBar': <String>[appBarId],
          'body': const <String>['scaffold:body'],
        },
        slotTypes: <String, String>{
          ?appBarId: 'registry:ApplicationBar',
          'scaffold:body': 'scaffold:body',
        },
        slotLabels: <String, String>{
          ?appBarId: 'Barre de titre',
          'scaffold:body': 'Espace principal',
        },
      ),
    );
  }

  void _buildCatalogPage({
    required _ResolvedPageEntry entry,
    required List<EditorPageConfig> primaryNavPages,
  }) {
    final page = entry.pageConfig;
    final prefix = entry.prefix;

    if (page.pageType == EditorPageType.a4Document) {
      final sheetLayoutId = _nextId(prefix, 'sheet_layout');
      _buildScreenLayout(
        layoutId: sheetLayoutId,
        prefix: prefix,
        screen: entry.screen,
        registerLayoutUsage: true,
      );
      _components[page.id] = A4PageConfig(
        orientation: A4Orientation.portrait,
        sheets: <A4SheetConfig>[
          A4SheetConfig(
            id: _nextId(prefix, 'sheet'),
            label: _nonEmpty(entry.screen.name, 'Feuille 1'),
            rootSlotId: sheetLayoutId,
            rootSlotType: 'registry:Layout',
          ),
        ],
        showPageNumbers: true,
        defaultFileName: '${DesignMdParser.slugify(page.name)}.pdf',
      );
      return;
    }

    final bodyLayoutId = _nextId(prefix, 'layout');
    _buildScreenLayout(
      layoutId: bodyLayoutId,
      prefix: prefix,
      screen: entry.screen,
      registerLayoutUsage: true,
    );

    String? appBarId;
    if (nav.hasAppBar && !page.pageType.isModal) {
      appBarId = _buildApplicationBar(
        prefix: prefix,
        title: page.name,
        currentPageId: page.id,
        primaryNavPages: primaryNavPages,
      );
    }

    _components[page.id] = ScaffoldPageConfig.fromNative(
      NativeComponentConfig(
        regions: <String, bool>{
          if (appBarId != null) 'appBar': true,
          'body': true,
        },
        placements: <String, List<String>>{
          if (appBarId != null) 'appBar': <String>[appBarId],
          'body': <String>[bodyLayoutId],
        },
        slotTypes: <String, String>{
          ?appBarId: 'registry:ApplicationBar',
          bodyLayoutId: 'registry:Layout',
        },
        slotLabels: <String, String>{
          ?appBarId: 'Barre supérieure',
          bodyLayoutId: _nonEmpty(entry.screen.name, page.name),
        },
      ),
    );
  }

  String _buildApplicationBar({
    required String prefix,
    required String title,
    required String? currentPageId,
    required List<EditorPageConfig> primaryNavPages,
  }) {
    final appBarId = _nextId(prefix, 'appbar');
    final titleId = _nextId(prefix, 'appbar_title');
    _components[titleId] = SuperValueConfig(
      initialText: _nonEmpty(title, project.name),
      fontFamily: fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: const ThemeColor(ThemeColorRole.onSurface),
    );
    _usages[titleId] = ComponentUsage.explanation(
      _nextTranslationKey('${title}_appBarTitle'),
    );

    final navActionIds = <String>[];
    final slotTypes = <String, String>{titleId: 'registry:Value'};
    final slotLabels = <String, String>{titleId: 'Titre de page'};

    if (primaryNavPages.length > 1) {
      for (final target in primaryNavPages.take(5)) {
        if (target.id == currentPageId) continue;
        final btnId = _nextId(prefix, 'nav');
        _components[btnId] = SuperActionConfig(
          kind: SuperActionKind.text,
          variant: SuperActionVariant.text,
          label: target.name,
          fontFamily: fontFamily,
          fontSize: 13,
          color: const ThemeColor(ThemeColorRole.onSurfaceVariant),
        );
        _usages[btnId] = const ComponentUsage(kind: ComponentUsageKind.action);
        _behaviors[btnId] = <ComponentBehavior>[
          ComponentBehavior(
            id: _nextId(prefix, 'beh_nav'),
            event: BehaviorEvent.onTap,
            action: GoToPageAction(
              pagePath: target.path,
              pageId: target.id,
              pageName: target.name,
            ),
          ),
        ];
        navActionIds.add(btnId);
        slotTypes[btnId] = 'registry:Action';
        slotLabels[btnId] = 'Aller vers ${target.name}';
      }
    }

    _components[appBarId] = NativeComponentConfig(
      regions: <String, bool>{
        'title': true,
        if (navActionIds.isNotEmpty) 'actions': true,
      },
      placements: <String, List<String>>{
        'title': <String>[titleId],
        if (navActionIds.isNotEmpty) 'actions': navActionIds,
      },
      slotTypes: slotTypes,
      slotLabels: slotLabels,
    );
    _usages[appBarId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    return appBarId;
  }

  void _buildScreenLayout({
    required String layoutId,
    required String prefix,
    required UxScreenSpec screen,
    required bool registerLayoutUsage,
  }) {
    final rawEnabled = screen.zones.where((z) => z.enabled).toList();
    final sourceZones = rawEnabled.isNotEmpty
        ? rawEnabled
        : UxScreenSpec.defaultZonesForPattern(screen.pattern);

    final zonesByKind = <UxLayoutZoneName, UxScreenZoneSpec>{
      for (final z in sourceZones) z.zone: z,
    };

    if (!zonesByKind.containsKey(UxLayoutZoneName.center) ||
        zonesByKind[UxLayoutZoneName.center]!.slots.isEmpty) {
      zonesByKind[UxLayoutZoneName.center] = UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_auto_center',
            title: _nonEmpty(screen.name, 'Contenu principal'),
            kind: UxWidgetKind.detailCard,
            businessObjectId: screen.primaryObjectId,
          ),
        ],
      );
    }

    final hasExplicitToolbar = zonesByKind.values.any(
      (z) => z.slots.any((s) => s.kind == UxWidgetKind.toolbar),
    );
    if (screen.actions.isNotEmpty && !hasExplicitToolbar) {
      final syntheticToolbar = UxZoneWidgetSlot(
        id: 'slot_auto_actions',
        title: 'Actions',
        kind: UxWidgetKind.toolbar,
      );
      final existingSouth = zonesByKind[UxLayoutZoneName.south];
      if (existingSouth != null) {
        zonesByKind[UxLayoutZoneName.south] = existingSouth.copyWith(
          slots: <UxZoneWidgetSlot>[...existingSouth.slots, syntheticToolbar],
        );
      } else {
        zonesByKind[UxLayoutZoneName.south] = UxScreenZoneSpec(
          zone: UxLayoutZoneName.south,
          sizePx: 64,
          axis: 'row',
          slots: <UxZoneWidgetSlot>[syntheticToolbar],
        );
      }
    }

    final primaryObj = _resolveScreenPrimaryObject(screen);
    final stateTracker = _ScreenBuildState();

    final placements = <SuperLayoutZone, List<String>>{};
    final slotTypes = <String, String>{};
    final slotLabels = <String, String>{};
    final slotConstraints = <String, SlotSizeConstraints>{};
    final zoneAxes = <SuperLayoutZone, Axis>{};
    final zoneFlows = <SuperLayoutZone, ZoneFlowConfig>{};

    for (final entry in zonesByKind.entries) {
      final uxZone = entry.value;
      final targetZone = _toSuperZone(uxZone.zone);
      final isHorizontal = uxZone.axis == 'row';
      if (isHorizontal) {
        zoneAxes[targetZone] = Axis.horizontal;
      }

      final zoneSlotIds = <String>[];
      final effectiveSlots = uxZone.slots.isNotEmpty
          ? uxZone.slots
          : <UxZoneWidgetSlot>[
              UxZoneWidgetSlot(
                id: 'slot_${uxZone.zone.name}',
                title: uxZone.zone.label,
                kind: uxZone.zone == UxLayoutZoneName.west
                    ? UxWidgetKind.masterList
                    : UxWidgetKind.detailCard,
                businessObjectId: screen.primaryObjectId,
              ),
            ];

      for (final slot in effectiveSlots) {
        final built = _buildWidgetForSlot(
          prefix: prefix,
          screen: screen,
          zoneSpec: uxZone,
          slot: slot,
          fallbackObject: primaryObj,
          screenState: stateTracker,
        );
        zoneSlotIds.add(built.id);
        slotTypes[built.id] = built.placementType;
        slotLabels[built.id] = _nonEmpty(slot.title, slot.kind.label);
        if (built.constraints != null) {
          slotConstraints[built.id] = built.constraints!;
        }
      }

      placements[targetZone] = zoneSlotIds;
      final isActionFooter =
          uxZone.zone == UxLayoutZoneName.south &&
          effectiveSlots.length == 1 &&
          effectiveSlots.single.kind == UxWidgetKind.toolbar;

      zoneFlows[targetZone] = ZoneFlowConfig(
        expandSlots: !isActionFooter,
        mainAxisAlignment: isActionFooter
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: isActionFooter
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        spacing: zoneSpacing,
        padding: zonePadding,
      );
    }

    final hasNorth = placements.containsKey(SuperLayoutZone.north);
    final hasSouth = placements.containsKey(SuperLayoutZone.south);
    final hasWest = placements.containsKey(SuperLayoutZone.west);
    final hasEast = placements.containsKey(SuperLayoutZone.east);

    final northZone = zonesByKind[UxLayoutZoneName.north];
    final southZone = zonesByKind[UxLayoutZoneName.south];
    final westZone = zonesByKind[UxLayoutZoneName.west];
    final eastZone = zonesByKind[UxLayoutZoneName.east];

    // Règle d'or : jamais west ni east dans autoSides ; tailles fixes explicites.
    final autoSides = <SuperLayoutZone>{
      if (hasNorth && northZone?.sizePx == null) SuperLayoutZone.north,
      if (hasSouth && southZone?.sizePx == null) SuperLayoutZone.south,
    };

    _components[layoutId] = SuperLayoutConfig(
      north: hasNorth,
      south: hasSouth,
      west: hasWest,
      east: hasEast,
      northSize: (northZone?.sizePx ?? 76.0).clamp(32.0, 400.0),
      southSize: (southZone?.sizePx ?? 64.0).clamp(32.0, 400.0),
      westSize: (westZone?.sizePx ?? 320.0).clamp(220.0, 560.0),
      eastSize: (eastZone?.sizePx ?? 320.0).clamp(220.0, 560.0),
      nw: (hasNorth && hasWest) ? CornerMerge.row : CornerMerge.none,
      ne: (hasNorth && hasEast) ? CornerMerge.row : CornerMerge.none,
      sw: (hasSouth && hasWest) ? CornerMerge.row : CornerMerge.none,
      se: (hasSouth && hasEast) ? CornerMerge.row : CornerMerge.none,
      resizeSides: hasWest || hasEast,
      autoSides: autoSides,
      zoneAxes: zoneAxes,
      zoneFlows: zoneFlows,
      slotSizeConstraints: slotConstraints,
      slotLabels: slotLabels,
      placements: placements,
      slotTypes: slotTypes,
    );
    if (registerLayoutUsage) {
      _usages[layoutId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    }
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildWidgetForSlot({
    required String prefix,
    required UxScreenSpec screen,
    required UxScreenZoneSpec zoneSpec,
    required UxZoneWidgetSlot slot,
    required BusinessObjectSpec? fallbackObject,
    required _ScreenBuildState screenState,
  }) {
    final slotObj = slot.businessObjectId.trim().isNotEmpty
        ? project.findBusinessObject(slot.businessObjectId)
        : fallbackObject;
    final repoTarget = _resolveRepoTarget(slotObj);
    final emptyText = _resolveEmptyText(screen, slotObj);

    return switch (slot.kind) {
      UxWidgetKind.masterList => _buildMasterListCard(
        prefix: prefix,
        slot: slot,
        repoTarget: repoTarget,
        emptyText: emptyText,
      ),
      UxWidgetKind.dataTable => _buildDataTableCard(
        prefix: prefix,
        slot: slot,
        repoTarget: repoTarget,
        emptyText: emptyText,
      ),
      UxWidgetKind.treeView => _buildTreeViewCard(
        prefix: prefix,
        slot: slot,
        repoTarget: repoTarget,
        emptyText: emptyText,
      ),
      UxWidgetKind.formSection => _buildFieldsCard(
        prefix: prefix,
        slot: slot,
        repoTarget: repoTarget,
        inputMode: true,
        readOnly: screen.states.readOnlyRuleIds.isNotEmpty,
      ),
      UxWidgetKind.detailCard || UxWidgetKind.chart => _buildFieldsCard(
        prefix: prefix,
        slot: slot,
        repoTarget: repoTarget,
        inputMode: false,
        readOnly: false,
      ),
      UxWidgetKind.kpiRow => _buildKpiRow(
        prefix: prefix,
        slot: slot,
        repoTarget: repoTarget,
      ),
      UxWidgetKind.toolbar => _buildToolbar(
        prefix: prefix,
        screen: screen,
        slot: slot,
        screenState: screenState,
      ),
      UxWidgetKind.searchFilterBar => _buildSearchFilterCard(
        prefix: prefix,
        slot: slot,
        inVerticalZone: zoneSpec.axis != 'row',
      ),
      UxWidgetKind.statusBanner => _buildStatusBannerCard(
        prefix: prefix,
        slot: slot,
        inVerticalZone: zoneSpec.axis != 'row',
      ),
      UxWidgetKind.tabGroup => _buildTabGroup(
        prefix: prefix,
        slot: slot,
        repoTarget: repoTarget,
      ),
    };
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildMasterListCard({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required _ResolvedRepoTarget? repoTarget,
    required String emptyText,
  }) {
    final listId = _nextId(prefix, 'list');
    final collectionBinding =
        repoTarget != null && repoTarget.collectionPath != null
        ? _tryBinding(repoTarget.repoAlias, repoTarget.collectionPath!)
        : null;

    final fields = repoTarget != null
        ? _selectFieldsForSlot(
            repoTarget.object,
            slot.attributeNames,
            maxCount: 2,
          )
        : const <_SlotLeafField>[];

    final rowValueIds = <String>[];
    final rowSlotTypes = <String, String>{};
    final rowSlotLabels = <String, String>{};

    if (collectionBinding != null && fields.isNotEmpty) {
      for (var i = 0; i < fields.length; i++) {
        final field = fields[i];
        final valId = _nextId(prefix, 'row_val');
        final rowBinding = _tryBinding(
          null,
          '${repoTarget!.collectionPath!}[?].${field.relativePath}',
        );
        _components[valId] = SuperValueConfig(
          initialText: rowBinding == null ? field.label : '',
          fontFamily: fontFamily,
          fontSize: i == 0 ? 14 : 12,
          fontWeight: i == 0 ? FontWeight.w500 : FontWeight.w400,
          color: ThemeColor(
            i == 0 ? ThemeColorRole.onSurface : ThemeColorRole.onSurfaceVariant,
          ),
          binding: rowBinding,
        );
        if (rowBinding == null) {
          _usages[valId] = const ComponentUsage(
            kind: ComponentUsageKind.dynamicData,
          );
        }
        rowValueIds.add(valId);
        rowSlotTypes[valId] = 'registry:Value';
        rowSlotLabels[valId] = field.label;
      }
    } else {
      final sampleId = _nextId(prefix, 'row_sample');
      _components[sampleId] = SuperValueConfig(
        initialText: slot.title,
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: const ThemeColor(ThemeColorRole.onSurface),
      );
      _usages[sampleId] = const ComponentUsage(
        kind: ComponentUsageKind.dynamicData,
      );
      rowValueIds.add(sampleId);
      rowSlotTypes[sampleId] = 'registry:Value';
      rowSlotLabels[sampleId] = 'Élément de liste';
    }

    _components[listId] = SuperListViewConfig(
      binding: collectionBinding,
      itemExtent: listItemExtent,
      spacing: 4,
      allowAdd: collectionBinding != null,
      allowRemove: collectionBinding != null,
      emptyText: emptyText,
      template: SuperLayoutConfig(
        autoSides: const <SuperLayoutZone>{},
        zoneFlows: const <SuperLayoutZone, ZoneFlowConfig>{
          SuperLayoutZone.center: ZoneFlowConfig(
            expandSlots: false,
            spacing: 2,
          ),
        },
        placements: <SuperLayoutZone, List<String>>{
          SuperLayoutZone.center: rowValueIds,
        },
        slotTypes: rowSlotTypes,
        slotLabels: rowSlotLabels,
      ),
    );
    if (collectionBinding == null) {
      _usages[listId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    }

    _styles['$listId:item'] = ContainerStyle(
      designSystem: surfaceSystem,
      color: const ThemeColor(ThemeColorRole.surface),
      radius: itemRadius,
      paddingInsets: const Quad(10, 38, 10, 12),
      hoverEffect: true,
      states: SurfaceStyleStates(
        selected: SelectedSurfaceStyle(
          style: const ContainerStyle(
            color: ThemeColor(ThemeColorRole.secondaryContainer),
            borderWidth: 1,
            borderColor: ThemeColor(ThemeColorRole.primary),
          ),
          properties: const <SurfaceStyleProperty>{
            SurfaceStyleProperty.background,
            SurfaceStyleProperty.border,
          },
        ),
      ),
    );

    final cardId = _wrapInTitledCard(
      prefix: prefix,
      title: slot.title,
      bodySlotId: listId,
      bodyPlacementType: 'registry:ListView',
      bodyLabel: slot.title,
      scrollableBody: false,
      expandBody: true,
    );
    return (id: cardId, placementType: 'registry:Card', constraints: null);
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildDataTableCard({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required _ResolvedRepoTarget? repoTarget,
    required String emptyText,
  }) {
    final tableId = _nextId(prefix, 'table');
    final collectionBinding =
        repoTarget != null && repoTarget.collectionPath != null
        ? _tryBinding(repoTarget.repoAlias, repoTarget.collectionPath!)
        : null;

    final fields = repoTarget != null
        ? _selectFieldsForSlot(
            repoTarget.object,
            slot.attributeNames,
            maxCount: 4,
          )
        : const <_SlotLeafField>[];

    final columns = <SuperTableColumnConfig>[];
    final cellPlacements = <String, List<String>>{};
    final cellSlotTypes = <String, String>{};
    final cellSlotLabels = <String, String>{};

    if (fields.isNotEmpty) {
      var assignedFill = false;
      for (var i = 0; i < fields.length; i++) {
        final field = fields[i];
        final colId = 'col_${i + 1}';
        final isNumeric =
            field.attribute.type == BusinessAttributeType.integer ||
            field.attribute.type == BusinessAttributeType.number;
        final shouldFill =
            !assignedFill && (!isNumeric || i == fields.length - 1);
        if (shouldFill) assignedFill = true;

        columns.add(
          SuperTableColumnConfig(
            id: colId,
            title: field.label,
            width: isNumeric ? 120 : 180,
            fillPercent: shouldFill ? 100 : 0,
          ),
        );

        final cellValId = _nextId(prefix, 'cell');
        final cellBinding = collectionBinding != null
            ? _tryBinding(
                null,
                '${repoTarget!.collectionPath!}[?].${field.relativePath}',
              )
            : null;
        _components[cellValId] = SuperValueConfig(
          initialText: cellBinding == null ? '—' : '',
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: i == 0 ? FontWeight.w500 : FontWeight.w400,
          color: const ThemeColor(ThemeColorRole.onSurface),
          textAlign: isNumeric ? TextAlign.end : TextAlign.start,
          binding: cellBinding,
        );
        if (cellBinding == null) {
          _usages[cellValId] = const ComponentUsage(
            kind: ComponentUsageKind.dynamicData,
          );
        }
        cellPlacements[SuperTableConfig.cellZoneFor(colId)] = <String>[
          cellValId,
        ];
        cellSlotTypes[cellValId] = 'registry:Value';
        cellSlotLabels[cellValId] = field.label;
      }
    } else {
      columns.add(
        SuperTableColumnConfig(
          id: 'col_1',
          title: slot.title,
          width: 200,
          fillPercent: 100,
        ),
      );
      final cellValId = _nextId(prefix, 'cell_default');
      _components[cellValId] = SuperValueConfig(
        initialText: '—',
        fontFamily: fontFamily,
        fontSize: 13,
        color: const ThemeColor(ThemeColorRole.onSurface),
      );
      _usages[cellValId] = const ComponentUsage(
        kind: ComponentUsageKind.dynamicData,
      );
      cellPlacements[SuperTableConfig.cellZoneFor('col_1')] = <String>[
        cellValId,
      ];
      cellSlotTypes[cellValId] = 'registry:Value';
      cellSlotLabels[cellValId] = slot.title;
    }

    _components[tableId] = SuperTableConfig(
      binding: collectionBinding,
      columns: columns,
      headerRowHeight: 38,
      rowHeight: tableRowHeight,
      allowAdd: collectionBinding != null,
      emptyText: emptyText,
      placements: cellPlacements,
      slotTypes: cellSlotTypes,
      slotLabels: cellSlotLabels,
    );
    if (collectionBinding == null) {
      _usages[tableId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    }

    final cardId = _wrapInTitledCard(
      prefix: prefix,
      title: slot.title,
      bodySlotId: tableId,
      bodyPlacementType: 'registry:Table',
      bodyLabel: slot.title,
      scrollableBody: false,
      expandBody: true,
    );
    return (id: cardId, placementType: 'registry:Card', constraints: null);
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildTreeViewCard({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required _ResolvedRepoTarget? repoTarget,
    required String emptyText,
  }) {
    final treeId = _nextId(prefix, 'tree');
    final collectionBinding =
        repoTarget != null && repoTarget.collectionPath != null
        ? _tryBinding(repoTarget.repoAlias, repoTarget.collectionPath!)
        : null;

    final fields = repoTarget != null
        ? _selectFieldsForSlot(
            repoTarget.object,
            slot.attributeNames,
            maxCount: 2,
          )
        : const <_SlotLeafField>[];

    final headerValId = _nextId(prefix, 'tree_hdr');
    final headerBinding = collectionBinding != null && fields.isNotEmpty
        ? _tryBinding(
            null,
            '${repoTarget!.collectionPath!}[?].${fields.first.relativePath}',
          )
        : null;
    _components[headerValId] = SuperValueConfig(
      initialText: headerBinding == null ? slot.title : '',
      fontFamily: fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: const ThemeColor(ThemeColorRole.onSurface),
      binding: headerBinding,
    );
    if (headerBinding == null) {
      _usages[headerValId] = const ComponentUsage(
        kind: ComponentUsageKind.dynamicData,
      );
    }

    final treePlacements = <String, List<String>>{
      SuperTreeViewConfig.headerZone: <String>[headerValId],
    };
    final treeSlotTypes = <String, String>{headerValId: 'registry:Value'};
    final treeSlotLabels = <String, String>{
      headerValId: fields.isNotEmpty ? fields.first.label : slot.title,
    };

    if (fields.length > 1) {
      final dataValId = _nextId(prefix, 'tree_data');
      final dataBinding = collectionBinding != null
          ? _tryBinding(
              null,
              '${repoTarget!.collectionPath!}[?].${fields[1].relativePath}',
            )
          : null;
      _components[dataValId] = SuperValueConfig(
        initialText: dataBinding == null ? '—' : '',
        fontFamily: fontFamily,
        fontSize: 12,
        color: const ThemeColor(ThemeColorRole.onSurfaceVariant),
        binding: dataBinding,
      );
      if (dataBinding == null) {
        _usages[dataValId] = const ComponentUsage(
          kind: ComponentUsageKind.dynamicData,
        );
      }
      treePlacements[SuperTreeViewConfig.dataZone] = <String>[dataValId];
      treeSlotTypes[dataValId] = 'registry:Value';
      treeSlotLabels[dataValId] = fields[1].label;
    }

    _components[treeId] = SuperTreeViewConfig(
      binding: collectionBinding,
      headerSize: 240,
      rowHeight: 34,
      indent: 20,
      emptyText: emptyText,
      placements: treePlacements,
      slotTypes: treeSlotTypes,
      slotLabels: treeSlotLabels,
    );
    if (collectionBinding == null) {
      _usages[treeId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    }

    final cardId = _wrapInTitledCard(
      prefix: prefix,
      title: slot.title,
      bodySlotId: treeId,
      bodyPlacementType: 'registry:TreeView',
      bodyLabel: slot.title,
      scrollableBody: false,
      expandBody: true,
    );
    return (id: cardId, placementType: 'registry:Card', constraints: null);
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildFieldsCard({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required _ResolvedRepoTarget? repoTarget,
    required bool inputMode,
    required bool readOnly,
  }) {
    final innerLayoutId = _nextId(prefix, 'card_layout');
    final titleValId = _nextId(prefix, 'card_title');

    _components[titleValId] = SuperValueConfig(
      initialText: _nonEmpty(slot.title, 'Détails'),
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: const ThemeColor(ThemeColorRole.onSurface),
    );
    _usages[titleValId] = ComponentUsage.explanation(
      _nextTranslationKey('${slot.title}_heading'),
    );

    final childIds = <String>[titleValId];
    final slotTypes = <String, String>{titleValId: 'registry:Value'};
    final slotLabels = <String, String>{titleValId: 'Titre — ${slot.title}'};

    final fields = repoTarget != null
        ? _selectFieldsForSlot(
            repoTarget.object,
            slot.attributeNames,
            maxCount: 6,
          )
        : const <_SlotLeafField>[];

    if (fields.isNotEmpty && repoTarget != null) {
      for (final field in fields) {
        final fieldId = _nextId(prefix, 'field');
        final explicitBinding = _tryBinding(
          repoTarget.repoAlias,
          '${repoTarget.itemPrefix}.${field.relativePath}',
        );
        _components[fieldId] = _buildBoundFieldConfig(
          field: field,
          binding: explicitBinding,
          inputMode: inputMode,
          readOnly: readOnly,
        );
        if (explicitBinding == null) {
          _usages[fieldId] = ComponentUsage(
            kind: inputMode
                ? ComponentUsageKind.userInput
                : ComponentUsageKind.dynamicData,
          );
        }
        childIds.add(fieldId);
        slotTypes[fieldId] = 'registry:Value';
        slotLabels[fieldId] = field.label;
      }
    } else if (slot.attributeNames.isNotEmpty) {
      for (final rawAttr in slot.attributeNames.take(6)) {
        final fieldId = _nextId(prefix, 'field');
        final humanLabel = _humanizeIdentifier(rawAttr);
        _components[fieldId] = SuperValueConfig(
          mode: inputMode ? SuperValueMode.input : SuperValueMode.display,
          label: humanLabel,
          initialText: inputMode ? '' : '—',
          readOnly: readOnly,
          fontFamily: fontFamily,
          fontSize: 14,
          color: const ThemeColor(ThemeColorRole.onSurface),
        );
        _usages[fieldId] = ComponentUsage(
          kind: inputMode
              ? ComponentUsageKind.userInput
              : ComponentUsageKind.dynamicData,
        );
        childIds.add(fieldId);
        slotTypes[fieldId] = 'registry:Value';
        slotLabels[fieldId] = humanLabel;
      }
    } else {
      final summaryId = _nextId(prefix, 'summary');
      _components[summaryId] = SuperValueConfig(
        mode: inputMode ? SuperValueMode.input : SuperValueMode.display,
        label: slot.title,
        initialText: inputMode
            ? ''
            : _nonEmpty(slot.summary, 'Sélectionnez un élément'),
        fontFamily: fontFamily,
        fontSize: 14,
        color: const ThemeColor(ThemeColorRole.onSurfaceVariant),
      );
      _usages[summaryId] = ComponentUsage(
        kind: inputMode
            ? ComponentUsageKind.userInput
            : ComponentUsageKind.dynamicData,
      );
      childIds.add(summaryId);
      slotTypes[summaryId] = 'registry:Value';
      slotLabels[summaryId] = slot.title;
    }

    // Règle d'or : autoSides vide sur tout layout feuille défilant.
    _components[innerLayoutId] = SuperLayoutConfig(
      autoSides: const <SuperLayoutZone>{},
      zoneFlows: <SuperLayoutZone, ZoneFlowConfig>{
        SuperLayoutZone.center: ZoneFlowConfig(
          expandSlots: false,
          scrollable: true,
          spacing: innerSpacing,
        ),
      },
      placements: <SuperLayoutZone, List<String>>{
        SuperLayoutZone.center: childIds,
      },
      slotTypes: slotTypes,
      slotLabels: slotLabels,
    );
    _usages[innerLayoutId] = const ComponentUsage(
      kind: ComponentUsageKind.layout,
    );

    final cardId = _nextId(prefix, 'card');
    _styles[cardId] = _buildCardStyle();
    _components[cardId] = NativeComponentConfig(
      regions: const <String, bool>{'child': true},
      placements: <String, List<String>>{
        'child': <String>[innerLayoutId],
      },
      slotTypes: <String, String>{innerLayoutId: 'registry:Layout'},
      slotLabels: <String, String>{innerLayoutId: slot.title},
    );
    _usages[cardId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    return (id: cardId, placementType: 'registry:Card', constraints: null);
  }

  SuperValueConfig _buildBoundFieldConfig({
    required _SlotLeafField field,
    required JsonTextBinding? binding,
    required bool inputMode,
    required bool readOnly,
  }) {
    final attr = field.attribute;
    if (inputMode && attr.type == BusinessAttributeType.boolean) {
      return SuperValueConfig(
        mode: SuperValueMode.input,
        kind: SuperValueKind.checkbox,
        label: field.label,
        readOnly: readOnly,
        fontFamily: fontFamily,
        fontSize: 14,
        color: const ThemeColor(ThemeColorRole.onSurface),
        binding: binding,
      );
    }

    if (inputMode &&
        attr.type == BusinessAttributeType.enumeration &&
        attr.enumValues.length >= 2 &&
        attr.enumValues.every((v) => v.trim().isNotEmpty && !v.contains(','))) {
      final options = [
        for (final v in attr.enumValues) SuperChoiceOption(value: v, label: v),
      ];
      return SuperValueConfig(
        mode: SuperValueMode.input,
        kind: SuperValueKind.choice,
        label: field.label,
        readOnly: readOnly,
        fontFamily: fontFamily,
        fontSize: 14,
        color: const ThemeColor(ThemeColorRole.onSurface),
        binding: binding,
        choice: SuperChoiceConfig(
          variant: options.length <= 4
              ? ChoiceVariant.segmented
              : ChoiceVariant.dropdown,
          direction: Axis.horizontal,
          options: options,
          allowEmpty: !attr.required,
        ),
      );
    }

    return SuperValueConfig(
      mode: inputMode ? SuperValueMode.input : SuperValueMode.display,
      label: field.label,
      initialText: binding == null && !inputMode ? '—' : '',
      readOnly: readOnly,
      fontFamily: fontFamily,
      fontSize: 14,
      color: const ThemeColor(ThemeColorRole.onSurface),
      binding: binding,
    );
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildKpiRow({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required _ResolvedRepoTarget? repoTarget,
  }) {
    final rowLayoutId = _nextId(prefix, 'kpi_row');
    final fields = repoTarget != null
        ? _selectFieldsForSlot(
            repoTarget.object,
            slot.attributeNames,
            maxCount: 3,
          )
        : const <_SlotLeafField>[];

    final kpiCardIds = <String>[];
    final slotTypes = <String, String>{};
    final slotLabels = <String, String>{};

    final count = fields.isNotEmpty ? fields.length : 3;
    for (var i = 0; i < count; i++) {
      final field = i < fields.length ? fields[i] : null;
      final kpiCardId = _nextId(prefix, 'kpi_card');
      final kpiInnerId = _nextId(prefix, 'kpi_inner');
      final kpiValId = _nextId(prefix, 'kpi_val');
      final metricLabel = field?.label ?? '${slot.title} ${i + 1}';
      final binding = field != null && repoTarget != null
          ? _tryBinding(
              repoTarget.repoAlias,
              '${repoTarget.itemPrefix}.${field.relativePath}',
            )
          : null;

      _components[kpiValId] = SuperValueConfig(
        mode: SuperValueMode.display,
        label: metricLabel,
        initialText: binding == null ? '${(i + 1) * 12}' : '',
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: const ThemeColor(ThemeColorRole.onSurface),
        binding: binding,
      );
      if (binding == null) {
        _usages[kpiValId] = const ComponentUsage(
          kind: ComponentUsageKind.dynamicData,
        );
      }

      _components[kpiInnerId] = SuperLayoutConfig(
        autoSides: const <SuperLayoutZone>{},
        zoneFlows: const <SuperLayoutZone, ZoneFlowConfig>{
          SuperLayoutZone.center: ZoneFlowConfig(expandSlots: false),
        },
        placements: <SuperLayoutZone, List<String>>{
          SuperLayoutZone.center: <String>[kpiValId],
        },
        slotTypes: <String, String>{kpiValId: 'registry:Value'},
        slotLabels: <String, String>{kpiValId: metricLabel},
      );
      _usages[kpiInnerId] = const ComponentUsage(
        kind: ComponentUsageKind.layout,
      );

      _styles[kpiCardId] = _buildCardStyle();
      _components[kpiCardId] = NativeComponentConfig(
        regions: const <String, bool>{'child': true},
        placements: <String, List<String>>{
          'child': <String>[kpiInnerId],
        },
        slotTypes: <String, String>{kpiInnerId: 'registry:Layout'},
        slotLabels: <String, String>{kpiInnerId: metricLabel},
      );
      _usages[kpiCardId] = const ComponentUsage(
        kind: ComponentUsageKind.layout,
      );

      kpiCardIds.add(kpiCardId);
      slotTypes[kpiCardId] = 'registry:Card';
      slotLabels[kpiCardId] = metricLabel;
    }

    _components[rowLayoutId] = SuperLayoutConfig(
      autoSides: const <SuperLayoutZone>{},
      zoneAxes: const <SuperLayoutZone, Axis>{
        SuperLayoutZone.center: Axis.horizontal,
      },
      zoneFlows: <SuperLayoutZone, ZoneFlowConfig>{
        SuperLayoutZone.center: ZoneFlowConfig(
          expandSlots: true,
          spacing: zoneSpacing,
        ),
      },
      placements: <SuperLayoutZone, List<String>>{
        SuperLayoutZone.center: kpiCardIds,
      },
      slotTypes: slotTypes,
      slotLabels: slotLabels,
    );
    _usages[rowLayoutId] = const ComponentUsage(
      kind: ComponentUsageKind.layout,
    );
    return (
      id: rowLayoutId,
      placementType: 'registry:Layout',
      constraints: null,
    );
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildToolbar({
    required String prefix,
    required UxScreenSpec screen,
    required UxZoneWidgetSlot slot,
    required _ScreenBuildState screenState,
  }) {
    final toolbarLayoutId = _nextId(prefix, 'toolbar');
    final btnIds = <String>[];
    final slotTypes = <String, String>{};
    final slotLabels = <String, String>{};
    final slotConstraints = <String, SlotSizeConstraints>{};

    final effectiveActions = screen.actions.isNotEmpty
        ? screen.actions
        : <UxScreenAction>[
            if (screen.states.emptyStateCta.trim().isNotEmpty)
              UxScreenAction(
                id: 'act_cta',
                label: screen.states.emptyStateCta.trim(),
                hierarchy: UxActionHierarchy.primary,
              )
            else
              UxScreenAction(
                id: 'act_refresh',
                label: 'Actualiser',
                hierarchy: UxActionHierarchy.secondary,
              ),
          ];

    for (final uxAction in effectiveActions) {
      final btnId = _nextId(prefix, 'act');
      final isFirstPrimary =
          uxAction.hierarchy == UxActionHierarchy.primary &&
          !screenState.hasEmittedPrimaryAction;
      if (isFirstPrimary) {
        screenState.hasEmittedPrimaryAction = true;
      }

      final SuperActionConfig config;
      switch (uxAction.hierarchy) {
        case UxActionHierarchy.primary when isFirstPrimary:
          config = SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            variant: SuperActionVariant.filled,
            label: uxAction.label,
            icon: _inferActionIcon(uxAction.label, fallback: 'check'),
            fontFamily: fontFamily,
            fontSize: 13,
            color: const ThemeColor(ThemeColorRole.onPrimary),
            iconColor: const ThemeColor(ThemeColorRole.onPrimary),
            radius: itemRadius,
          );
        case UxActionHierarchy.primary || UxActionHierarchy.secondary:
          config = SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            variant: SuperActionVariant.tonal,
            label: uxAction.label,
            icon: _inferActionIcon(uxAction.label, fallback: 'touch_app'),
            fontFamily: fontFamily,
            fontSize: 13,
            color: const ThemeColor(ThemeColorRole.onSecondaryContainer),
            iconColor: const ThemeColor(ThemeColorRole.onSecondaryContainer),
            radius: itemRadius,
          );
        case UxActionHierarchy.destructive:
          config = SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            variant: SuperActionVariant.tonal,
            label: uxAction.label,
            tooltip: uxAction.confirmationMessage,
            icon: 'delete',
            fontFamily: fontFamily,
            fontSize: 13,
            backgroundColor: const ThemeColor(ThemeColorRole.errorContainer),
            color: const ThemeColor(ThemeColorRole.onErrorContainer),
            iconColor: const ThemeColor(ThemeColorRole.onErrorContainer),
            radius: itemRadius,
          );
        case UxActionHierarchy.inline:
          config = SuperActionConfig(
            kind: SuperActionKind.icon,
            variant: SuperActionVariant.icon,
            label: uxAction.label,
            tooltip: uxAction.label,
            icon: _inferActionIcon(uxAction.label, fallback: 'more_horiz'),
            iconColor: const ThemeColor(ThemeColorRole.onSurfaceVariant),
          );
      }

      _components[btnId] = config;
      _usages[btnId] = const ComponentUsage(kind: ComponentUsageKind.action);

      final targetRouteRef = uxAction.targetRouteId.trim();
      if (targetRouteRef.isNotEmpty) {
        final targetPage = _resolveTargetPage(targetRouteRef);
        if (targetPage != null) {
          _behaviors[btnId] = <ComponentBehavior>[
            ComponentBehavior(
              id: _nextId(prefix, 'beh_act'),
              event: BehaviorEvent.onTap,
              action: GoToPageAction(
                pagePath: targetPage.path,
                pageId: targetPage.id,
                pageName: targetPage.name,
              ),
            ),
          ];
        } else if (targetRouteRef == '/') {
          _behaviors[btnId] = <ComponentBehavior>[
            ComponentBehavior(
              id: _nextId(prefix, 'beh_act'),
              event: BehaviorEvent.onTap,
              action: const GoToPageAction(pagePath: '/'),
            ),
          ];
        }
      }

      btnIds.add(btnId);
      slotTypes[btnId] = 'registry:Action';
      slotLabels[btnId] = uxAction.label;
      slotConstraints[btnId] = const SlotSizeConstraints(fitContent: true);
    }

    _components[toolbarLayoutId] = SuperLayoutConfig(
      autoSides: const <SuperLayoutZone>{},
      zoneAxes: const <SuperLayoutZone, Axis>{
        SuperLayoutZone.center: Axis.horizontal,
      },
      zoneFlows: const <SuperLayoutZone, ZoneFlowConfig>{
        SuperLayoutZone.center: ZoneFlowConfig(
          expandSlots: false,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 8,
        ),
      },
      slotSizeConstraints: slotConstraints,
      placements: <SuperLayoutZone, List<String>>{
        SuperLayoutZone.center: btnIds,
      },
      slotTypes: slotTypes,
      slotLabels: slotLabels,
    );
    _usages[toolbarLayoutId] = const ComponentUsage(
      kind: ComponentUsageKind.layout,
    );
    return (
      id: toolbarLayoutId,
      placementType: 'registry:Layout',
      constraints: const SlotSizeConstraints(fitContent: true),
    );
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildSearchFilterCard({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required bool inVerticalZone,
  }) {
    final searchValId = _nextId(prefix, 'search');
    _components[searchValId] = SuperValueConfig(
      mode: SuperValueMode.input,
      label: _nonEmpty(slot.title, 'Rechercher'),
      placeholder: 'Filtrer…',
      fontFamily: fontFamily,
      fontSize: 13,
      color: const ThemeColor(ThemeColorRole.onSurface),
    );
    _usages[searchValId] = const ComponentUsage(
      kind: ComponentUsageKind.userInput,
    );

    final cardId = _nextId(prefix, 'search_card');
    _styles[cardId] = _buildCardStyle(paddingOverride: 12);
    _components[cardId] = NativeComponentConfig(
      regions: const <String, bool>{'child': true},
      placements: <String, List<String>>{
        'child': <String>[searchValId],
      },
      slotTypes: <String, String>{searchValId: 'registry:Value'},
      slotLabels: <String, String>{searchValId: slot.title},
    );
    _usages[cardId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    return (
      id: cardId,
      placementType: 'registry:Card',
      constraints: inVerticalZone
          ? const SlotSizeConstraints(fitContent: true)
          : null,
    );
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildStatusBannerCard({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required bool inVerticalZone,
  }) {
    final indicatorId = _nextId(prefix, 'status');
    _components[indicatorId] = SuperIndicatorConfig(
      icon: 'info',
      label: _nonEmpty(slot.summary, slot.title),
      fontFamily: fontFamily,
      fontSize: 13,
      color: const ThemeColor(ThemeColorRole.onPrimaryContainer),
      iconColor: const ThemeColor(ThemeColorRole.onPrimaryContainer),
      backgroundColor: const ThemeColor(ThemeColorRole.primaryContainer),
      radius: itemRadius,
      horizontalPadding: 12,
      verticalPadding: 6,
    );
    _usages[indicatorId] = const ComponentUsage(
      kind: ComponentUsageKind.feedback,
    );

    return (
      id: indicatorId,
      placementType: 'registry:Indicator',
      constraints: inVerticalZone
          ? const SlotSizeConstraints(fitContent: true)
          : null,
    );
  }

  ({String id, String placementType, SlotSizeConstraints? constraints})
  _buildTabGroup({
    required String prefix,
    required UxZoneWidgetSlot slot,
    required _ResolvedRepoTarget? repoTarget,
  }) {
    final tabCompId = _nextId(prefix, 'tabs');
    final tab1BtnId = _nextId(prefix, 'tab_btn');
    final tab2BtnId = _nextId(prefix, 'tab_btn');

    _components[tab1BtnId] = SuperActionConfig(
      kind: SuperActionKind.text,
      variant: SuperActionVariant.text,
      label: slot.title,
      fontFamily: fontFamily,
    );
    _usages[tab1BtnId] = const ComponentUsage(kind: ComponentUsageKind.action);

    _components[tab2BtnId] = SuperActionConfig(
      kind: SuperActionKind.text,
      variant: SuperActionVariant.text,
      label: 'Informations complémentaires',
      fontFamily: fontFamily,
    );
    _usages[tab2BtnId] = const ComponentUsage(kind: ComponentUsageKind.action);

    final card1 = _buildFieldsCard(
      prefix: prefix,
      slot: slot,
      repoTarget: repoTarget,
      inputMode: false,
      readOnly: false,
    );
    final card2 = _buildFieldsCard(
      prefix: prefix,
      slot: slot.copyWith(title: 'Détails secondaires'),
      repoTarget: repoTarget,
      inputMode: false,
      readOnly: false,
    );

    _components[tabCompId] = SuperTabConfig(
      mode: SuperTabMode.static,
      tabBarStyle: ContainerStyle(
        designSystem: surfaceSystem,
        color: const ThemeColor(ThemeColorRole.surfaceContainer),
        radius: itemRadius,
        padding: 4,
        borderWidth: 1,
        borderColor: const ThemeColor(ThemeColorRole.outlineVariant),
      ),
      placements: <String, List<String>>{
        SuperTabConfig.tabsZone: <String>[tab1BtnId, tab2BtnId],
        SuperTabConfig.contentZoneFor(tab1BtnId): <String>[card1.id],
        SuperTabConfig.contentZoneFor(tab2BtnId): <String>[card2.id],
      },
      slotTypes: <String, String>{
        tab1BtnId: 'registry:Action',
        tab2BtnId: 'registry:Action',
        card1.id: card1.placementType,
        card2.id: card2.placementType,
      },
      slotLabels: <String, String>{
        tab1BtnId: slot.title,
        tab2BtnId: 'Informations complémentaires',
        card1.id: slot.title,
        card2.id: 'Détails secondaires',
      },
    );
    _usages[tabCompId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    return (id: tabCompId, placementType: 'registry:Tab', constraints: null);
  }

  String _wrapInTitledCard({
    required String prefix,
    required String title,
    required String bodySlotId,
    required String bodyPlacementType,
    required String bodyLabel,
    required bool scrollableBody,
    required bool expandBody,
  }) {
    final cardLayoutId = _nextId(prefix, 'card_body');
    final headerId = _nextId(prefix, 'card_hdr');

    _components[headerId] = SuperValueConfig(
      initialText: _nonEmpty(title, bodyLabel),
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: const ThemeColor(ThemeColorRole.onSurface),
    );
    _usages[headerId] = ComponentUsage.explanation(
      _nextTranslationKey('${title}_cardTitle'),
    );

    _components[cardLayoutId] = SuperLayoutConfig(
      north: true,
      autoSides: scrollableBody
          ? const <SuperLayoutZone>{}
          : const <SuperLayoutZone>{SuperLayoutZone.north},
      zoneFlows: <SuperLayoutZone, ZoneFlowConfig>{
        SuperLayoutZone.north: const ZoneFlowConfig(
          expandSlots: false,
          paddingInsets: EdgeInsets.fromLTRB(0, 0, 0, 8),
        ),
        SuperLayoutZone.center: ZoneFlowConfig(
          expandSlots: expandBody,
          scrollable: scrollableBody,
          spacing: innerSpacing,
        ),
      },
      placements: <SuperLayoutZone, List<String>>{
        SuperLayoutZone.north: <String>[headerId],
        SuperLayoutZone.center: <String>[bodySlotId],
      },
      slotTypes: <String, String>{
        headerId: 'registry:Value',
        bodySlotId: bodyPlacementType,
      },
      slotLabels: <String, String>{
        headerId: 'Titre — $title',
        bodySlotId: bodyLabel,
      },
    );
    _usages[cardLayoutId] = const ComponentUsage(
      kind: ComponentUsageKind.layout,
    );

    final cardId = _nextId(prefix, 'card');
    _styles[cardId] = _buildCardStyle();
    _components[cardId] = NativeComponentConfig(
      regions: const <String, bool>{'child': true},
      placements: <String, List<String>>{
        'child': <String>[cardLayoutId],
      },
      slotTypes: <String, String>{cardLayoutId: 'registry:Layout'},
      slotLabels: <String, String>{cardLayoutId: title},
    );
    _usages[cardId] = const ComponentUsage(kind: ComponentUsageKind.layout);
    return cardId;
  }

  ContainerStyle _buildCardStyle({double? paddingOverride}) => ContainerStyle(
    designSystem: surfaceSystem,
    color: const ThemeColor(ThemeColorRole.surface),
    radius: cardRadius,
    padding: paddingOverride ?? cardPadding,
    borderWidth: 1,
    borderColor: const ThemeColor(ThemeColorRole.outlineVariant),
  );

  BusinessObjectSpec? _resolveScreenPrimaryObject(UxScreenSpec screen) {
    if (screen.primaryObjectId.trim().isNotEmpty) {
      final explicit = project.findBusinessObject(screen.primaryObjectId);
      if (explicit != null) return explicit;
    }
    for (final zone in screen.zones) {
      for (final slot in zone.slots) {
        if (slot.businessObjectId.trim().isNotEmpty) {
          final found = project.findBusinessObject(slot.businessObjectId);
          if (found != null) return found;
        }
      }
    }
    return exportedObjects.isNotEmpty ? exportedObjects.first : null;
  }

  _ResolvedRepoTarget? _resolveRepoTarget(BusinessObjectSpec? obj) {
    if (obj == null) return null;
    if (exportedObjects.any((e) => e.id == obj.id)) {
      final alias = SpecSuperDesignerExporter.repoAliasFor(obj);
      final collectionKey = SpecSuperDesignerExporter.collectionKeyFor(alias);
      return _ResolvedRepoTarget(
        object: obj,
        repoAlias: alias,
        collectionPath: collectionKey,
        itemPrefix: '$collectionKey[?]',
      );
    }

    for (final root in exportedObjects) {
      for (final rel in root.relations) {
        final target = project.findBusinessObject(rel.targetObjectId);
        if (target?.id != obj.id) continue;
        final rootAlias = SpecSuperDesignerExporter.repoAliasFor(root);
        final rootCollection = SpecSuperDesignerExporter.collectionKeyFor(
          rootAlias,
        );
        if (rel.cardinality == BusinessRelationCardinality.oneToOne) {
          return _ResolvedRepoTarget(
            object: obj,
            repoAlias: rootAlias,
            collectionPath: null,
            itemPrefix: '$rootCollection[?].${rel.name}',
          );
        }
        final nestedCollection = '$rootCollection[?].${rel.name}';
        return _ResolvedRepoTarget(
          object: obj,
          repoAlias: rootAlias,
          collectionPath: nestedCollection,
          itemPrefix: '$nestedCollection[?]',
        );
      }
    }

    final fallbackAlias = SpecSuperDesignerExporter.repoAliasFor(obj);
    final fallbackCollection = SpecSuperDesignerExporter.collectionKeyFor(
      fallbackAlias,
    );
    return _ResolvedRepoTarget(
      object: obj,
      repoAlias: fallbackAlias,
      collectionPath: fallbackCollection,
      itemPrefix: '$fallbackCollection[?]',
    );
  }

  List<_SlotLeafField> _selectFieldsForSlot(
    BusinessObjectSpec obj,
    List<String> requestedNames, {
    required int maxCount,
  }) {
    final allScalarFields = <_SlotLeafField>[];

    void collect(List<BusinessAttribute> attrs, String prefix) {
      for (final attr in attrs) {
        final relPath = prefix.isEmpty ? attr.name : '$prefix.${attr.name}';
        if (attr.isArray) continue;
        if (attr.type == BusinessAttributeType.object &&
            attr.children.isNotEmpty) {
          collect(attr.children, relPath);
        } else if (attr.type != BusinessAttributeType.object &&
            attr.type != BusinessAttributeType.json) {
          allScalarFields.add(
            _SlotLeafField(
              relativePath: relPath,
              label: _humanizeIdentifier(attr.name),
              attribute: attr,
            ),
          );
        }
      }
    }

    collect(obj.attributes, '');

    if (requestedNames.isNotEmpty) {
      final matched = <_SlotLeafField>[];
      final seen = <String>{};
      for (final raw in requestedNames) {
        final needle = raw
            .trim()
            .replaceAll('[?]', '')
            .replaceAll('[]', '')
            .toLowerCase();
        if (needle.isEmpty) continue;
        for (final candidate in allScalarFields) {
          if (candidate.relativePath.toLowerCase() == needle ||
              candidate.attribute.name.toLowerCase() == needle ||
              candidate.attribute.id.toLowerCase() == needle) {
            if (seen.add(candidate.relativePath)) {
              matched.add(candidate);
            }
            break;
          }
        }
      }
      if (matched.isNotEmpty) {
        return matched.take(maxCount).toList();
      }
    }

    // Priorise les champs lisibles (hors uuid technique pur en première colonne s'il existe d'autres champs).
    final readable = [
      ...allScalarFields.where(
        (f) => f.attribute.type != BusinessAttributeType.uuid,
      ),
      ...allScalarFields.where(
        (f) => f.attribute.type == BusinessAttributeType.uuid,
      ),
    ];
    return readable.take(maxCount).toList();
  }

  EditorPageConfig? _resolveTargetPage(String targetRouteRef) {
    final trimmed = targetRouteRef.trim();
    if (trimmed.isEmpty) return null;
    final direct = _routeLookup[trimmed.toLowerCase()];
    if (direct != null) return direct;
    final normalized = UxRouteNode.normalizePath(trimmed).toLowerCase();
    return _routeLookup[normalized];
  }

  String _resolveEmptyText(UxScreenSpec screen, BusinessObjectSpec? obj) {
    if (screen.states.emptyStateTitle.trim().isNotEmpty) {
      return screen.states.emptyStateTitle.trim();
    }
    if (obj != null) {
      return 'Aucun élément ${obj.name.toLowerCase()}';
    }
    return 'Aucun élément disponible';
  }

  String _allocatePageId(String rawId, {required int index}) {
    var base = _slugToken(rawId, fallback: 'page_${index + 1}');
    if (base == 'root' ||
        base == 'mainLayout' ||
        base == 'background' ||
        base.startsWith('scaffold_') ||
        base.startsWith('__')) {
      base = 'page_$base';
    }
    var candidate = base;
    var suffix = 2;
    while (!_usedIds.add(candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  ({String path, Map<String, String> defaultParams}) _allocateCatalogPath({
    required String rawPath,
    required String fallbackSlug,
    required Set<String> seenPaths,
    required Set<String> seenDynamicPrefixes,
  }) {
    final trimmed = rawPath.trim();
    final segments = <String>[];
    final params = <String, String>{};

    if (trimmed.isNotEmpty && trimmed != '/') {
      for (final rawSeg in trimmed.split('/')) {
        final seg = rawSeg.trim();
        if (seg.isEmpty) continue;
        if (seg.startsWith(':')) {
          final paramMatch = RegExp(r'^:([A-Za-z_][A-Za-z0-9_]*)')
              .firstMatch(seg);
          if (paramMatch != null) {
            final paramName = paramMatch.group(1)!;
            if (!params.containsKey(paramName)) {
              if (segments.isEmpty) {
                segments.add(fallbackSlug);
              }
              segments.add(':$paramName');
              params[paramName] = '1';
            }
            continue;
          }
        }
        segments.add(_slugSegment(seg, fallback: 'section'));
      }
    }

    if (segments.isEmpty) {
      segments.add(fallbackSlug == 'page' ? 'accueil' : fallbackSlug);
    }

    final firstDynamicIdx = segments.indexWhere((s) => s.startsWith(':'));
    if (firstDynamicIdx >= 0) {
      var prefixLiteral = segments.first;
      var suffix = 2;
      while (!seenDynamicPrefixes.add(prefixLiteral.toLowerCase()) ||
          seenPaths.any(
            (existing) =>
                existing == '/$prefixLiteral' ||
                existing.startsWith('/$prefixLiteral/'),
          )) {
        prefixLiteral = '${segments.first}-$suffix';
        suffix++;
      }
      segments[0] = prefixLiteral;
    }

    var candidate = '/${segments.join('/')}';
    var suffix = 2;
    while (!seenPaths.add(candidate.toLowerCase()) ||
        (firstDynamicIdx < 0 &&
            seenDynamicPrefixes.contains(segments.first.toLowerCase()))) {
      if (firstDynamicIdx >= 0) {
        final updatedFirst = '${segments.first}-$suffix';
        seenDynamicPrefixes.add(updatedFirst.toLowerCase());
        candidate = '/${[updatedFirst, ...segments.skip(1)].join('/')}';
      } else {
        final updatedFirst = '${segments.first}-$suffix';
        if (!seenDynamicPrefixes.contains(updatedFirst.toLowerCase())) {
          candidate = '/${[updatedFirst, ...segments.skip(1)].join('/')}';
        } else {
          candidate = '/${segments.join('/')}-$suffix';
        }
      }
      suffix++;
    }
    return (path: candidate, defaultParams: params);
  }

  String _nextId(String prefix, String role) {
    while (true) {
      _seq++;
      final candidate = '${prefix}_${role}_$_seq';
      if (_usedIds.add(candidate)) return candidate;
    }
  }

  String _nextTranslationKey(String rawLabel) {
    var base = ComponentUsage.suggestTranslationKey(rawLabel);
    if (base.isEmpty || !ComponentUsage.translationKeyPattern.hasMatch(base)) {
      base = 'uxSectionTitle';
    }
    var candidate = base;
    var suffix = 2;
    while (!_usedTranslationKeys.add(candidate)) {
      candidate = '$base$suffix';
      suffix++;
    }
    return candidate;
  }

  JsonTextBinding? _tryBinding(String? repositoryId, String path) {
    try {
      final binding = JsonTextBinding(repositoryId: repositoryId, path: path);
      binding.validate();
      return binding;
    } on FormatException {
      return null;
    }
  }

  static SuperLayoutZone _toSuperZone(UxLayoutZoneName zone) => switch (zone) {
    UxLayoutZoneName.north => SuperLayoutZone.north,
    UxLayoutZoneName.west => SuperLayoutZone.west,
    UxLayoutZoneName.center => SuperLayoutZone.center,
    UxLayoutZoneName.east => SuperLayoutZone.east,
    UxLayoutZoneName.south => SuperLayoutZone.south,
  };

  static bool _screenMatchesRoute(UxScreenSpec screen, UxRouteNode route) {
    final raw = screen.routeId.trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (route.id.toLowerCase() == lower) return true;
    final normalized = UxRouteNode.normalizePath(raw).toLowerCase();
    return route.path.toLowerCase() == lower ||
        route.path.toLowerCase() == normalized;
  }

  static String _inferActionIcon(String label, {required String fallback}) {
    final lower = label.toLowerCase();
    final candidate = switch (lower) {
      _
          when lower.contains('ajout') ||
              lower.contains('créer') ||
              lower.contains('creer') ||
              lower.contains('nouveau') ||
              lower.contains('nouvelle') =>
        'add',
      _ when lower.contains('enregistr') || lower.contains('sauvegard') =>
        'save',
      _ when lower.contains('modif') || lower.contains('édit') => 'edit',
      _ when lower.contains('supprim') || lower.contains('retir') => 'delete',
      _ when lower.contains('export') || lower.contains('télécharg') =>
        'download',
      _ when lower.contains('imprim') || lower.contains('pdf') => 'print',
      _ when lower.contains('filtr') => 'filter_list',
      _ when lower.contains('recherch') => 'search',
      _
          when lower.contains('valid') ||
              lower.contains('approuv') ||
              lower.contains('confirm') =>
        'check_circle',
      _ when lower.contains('annul') || lower.contains('ferm') => 'close',
      _ => fallback,
    };
    return MaterialIconCatalog.resolveCanonicalId(candidate) ??
        (MaterialIconCatalog.isKnown(candidate) ? candidate : 'touch_app');
  }

  static String _humanizeIdentifier(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'^_+'), '');
    if (cleaned.isEmpty) return 'Champ';
    final spaced = cleaned
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2].toString().toLowerCase()}',
        )
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    if (spaced.isEmpty) return 'Champ';
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  static String _slugToken(String input, {required String fallback}) {
    final lower = input
        .trim()
        .replaceAll(RegExp(r'[àáâãäåÀÁÂÃÄÅ]'), 'a')
        .replaceAll(RegExp(r'[çÇ]'), 'c')
        .replaceAll(RegExp(r'[èéêëÈÉÊË]'), 'e')
        .replaceAll(RegExp(r'[ìíîïÌÍÎÏ]'), 'i')
        .replaceAll(RegExp(r'[òóôõöÒÓÔÕÖ]'), 'o')
        .replaceAll(RegExp(r'[ùúûüÙÚÛÜ]'), 'u')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return lower.isEmpty ? fallback : lower;
  }

  static String _slugSegment(String input, {required String fallback}) {
    final lower = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return lower.isEmpty ? fallback : lower;
  }

  static String _nonEmpty(String value, String fallback) =>
      value.trim().isNotEmpty ? value.trim() : fallback;
}

class _ScreenBuildState {
  bool hasEmittedPrimaryAction = false;
}
