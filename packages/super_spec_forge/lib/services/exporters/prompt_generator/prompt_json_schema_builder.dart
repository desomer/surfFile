/// Constructeur de JSON Schemas Draft 2020-12 pour les modèles métiers et
/// les paramètres `Input` / `Output` des Use Cases injectés dans les prompts IA
/// ([PromptJsonSchemaBuilder]).
library;

import 'dart:convert';

import '../../../models/business_object_model_preferences.dart';
import '../../../models/business_object_spec.dart';
import '../../../models/spec_forge_project.dart';
import '../../../models/usecase_orchestration_spec.dart';
import '../../../models/value_object_spec.dart';
import '../spec_super_designer_exporter.dart';
import 'model_prompt_context.dart';

/// Assemble les schémas JSON Schema Draft 2020-12 des modèles et des Use Cases.
abstract final class PromptJsonSchemaBuilder {
  /// URI standard JSON Schema Draft 2020-12.
  static const String draft202012Uri =
      'https://json-schema.org/draft/2020-12/schema';

  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  static const Set<String> _arrayOnlyKeywords = <String>{
    'minItems',
    'maxItems',
    'uniqueItems',
    'contains',
    'minContains',
    'maxContains',
    'prefixItems',
  };

  /// Construit le JSON Schema Draft 2020-12 complet d'un modèle métier à partir
  /// de [ctx], en résolvant les relations et les attributs `reference` vers
  /// les autres entrées du domaine.
  static Map<String, Object?> buildModelSchema(ModelPromptContext ctx) {
    final project = ctx.resolutionProject;
    final strictObjects =
        project.businessObjectModelPreferences.schemaStrictness ==
        JsonSchemaStrictness.strict;
    final voSpecs = [
      for (final item in ctx.availableValueObjects) item.spec,
    ];
    final voScopes = <String, ValueObjectScope>{
      for (final item in ctx.availableValueObjects) item.spec.id: item.scope,
    };
    final entitySchema = _buildObjectSchema(
      project: project,
      obj: ctx.objectSpec,
      refTargets: ctx.refTargets,
      visited: <String>{ctx.objectSpec.id},
      strictObjects: strictObjects,
      valueObjects: voSpecs,
      valueObjectScopes: voScopes,
    );

    return <String, Object?>{
      r'$schema': draft202012Uri,
      'title': ctx.objectSpec.technicalName,
      ...entitySchema,
    };
  }

  /// Construit le JSON Schema Draft 2020-12 complet d'un [ValueObjectSpec]
  /// (`scalar` ou `composite`), en résolvant les Value Objects enfants éventuels.
  static Map<String, Object?> buildValueObjectSchema({
    required ValueObjectSpec valueObject,
    required ValueObjectScope scope,
    List<ResolvedValueObject> availableValueObjects =
        const <ResolvedValueObject>[],
    BusinessObjectModelPreferences? modelPreferences,
  }) {
    final strictObjects =
        (modelPreferences?.schemaStrictness ?? JsonSchemaStrictness.strict) ==
        JsonSchemaStrictness.strict;
    final voSpecs = <ValueObjectSpec>[
      for (final item in availableValueObjects) item.spec,
    ];
    final voScopes = <String, ValueObjectScope>{
      for (final item in availableValueObjects) item.spec.id: item.scope,
    };
    final baseSchema = SpecSuperDesignerExporter.valueObjectToJsonSchema(
      valueObject,
      valueObjects: voSpecs,
      valueObjectScopes: voScopes,
      scope: scope,
      strictObjects: strictObjects,
    );
    return <String, Object?>{
      r'$schema': draft202012Uri,
      'title': valueObject.technicalName,
      ...baseSchema,
    };
  }

  /// Construit un JSON Schema Draft 2020-12 strict (`additionalProperties: false`)
  /// à partir d'une liste de champs [UseCaseFieldSpec] (`Input` ou `Output`).
  static Map<String, Object?> buildUseCaseFieldsSchema({
    required String title,
    required List<UseCaseFieldSpec> fields,
    String description = '',
  }) {
    final properties = <String, Object?>{};
    final required = <String>[];

    for (final field in fields) {
      properties[field.name] = _useCaseFieldToSchema(field);
      if (field.effectiveRequired) {
        required.add(field.name);
      }
    }

    return <String, Object?>{
      r'$schema': draft202012Uri,
      'title': title,
      if (description.trim().isNotEmpty) 'description': description.trim(),
      'type': 'object',
      'additionalProperties': false,
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
    };
  }

  /// Sérialise [schema] en JSON indenté prêt à être inclus dans un bloc Markdown.
  static String toPrettyJson(Map<String, Object?> schema) =>
      _prettyJson.convert(schema);

  /// Écrit un bloc de code Markdown ```` ```json ... ``` ```` pour [schema].
  static void writeJsonSchemaBlock(
    StringBuffer buf,
    Map<String, Object?> schema,
  ) {
    buf
      ..writeln('```json')
      ..writeln(toPrettyJson(schema))
      ..writeln('```');
  }

  static Map<String, Object?> _buildObjectSchema({
    required SpecForgeProject project,
    required BusinessObjectSpec obj,
    required Map<String, String> refTargets,
    required Set<String> visited,
    required bool strictObjects,
    List<ValueObjectSpec> valueObjects = const <ValueObjectSpec>[],
    Map<String, ValueObjectScope> valueObjectScopes =
        const <String, ValueObjectScope>{},
  }) {
    final baseSchema = SpecSuperDesignerExporter.objectToJsonSchema(
      project,
      obj,
      valueObjects: valueObjects,
      valueObjectScopes: valueObjectScopes,
    );
    final rawProps = baseSchema['properties'];
    final baseProps = rawProps is Map
        ? Map<String, Object?>.from(rawProps.cast<String, Object?>())
        : <String, Object?>{};

    for (final attr in obj.attributes) {
      baseProps[attr.name] = _attributeWithResolvedRefs(
        project: project,
        attr: attr,
        refTargets: refTargets,
        visited: visited,
        strictObjects: strictObjects,
        valueObjects: valueObjects,
        valueObjectScopes: valueObjectScopes,
      );
    }

    return <String, Object?>{...baseSchema, 'properties': baseProps};
  }

  static Map<String, Object?> _attributeWithResolvedRefs({
    required SpecForgeProject project,
    required BusinessAttribute attr,
    required Map<String, String> refTargets,
    required Set<String> visited,
    required bool strictObjects,
    List<ValueObjectSpec> valueObjects = const <ValueObjectSpec>[],
    Map<String, ValueObjectScope> valueObjectScopes =
        const <String, ValueObjectScope>{},
  }) {
    if (attr.type == BusinessAttributeType.object && attr.children.isNotEmpty) {
      final childProps = <String, Object?>{};
      final childRequired = <String>[];
      for (final child in attr.children) {
        childProps[child.name] = _attributeWithResolvedRefs(
          project: project,
          attr: child,
          refTargets: refTargets,
          visited: visited,
          strictObjects: strictObjects,
          valueObjects: valueObjects,
          valueObjectScopes: valueObjectScopes,
        );
        if (child.required) childRequired.add(child.name);
      }
      final objectSchema = <String, Object?>{
        'type': 'object',
        if (attr.description.isNotEmpty) 'description': attr.description,
        if (strictObjects) 'additionalProperties': false,
        if (childRequired.isNotEmpty) 'required': childRequired,
        'properties': childProps,
      };
      return _finalizeArrayAndConstraints(
        attr: attr,
        itemSchema: objectSchema,
      );
    }

    if (attr.type == BusinessAttributeType.reference &&
        attr.referenceObjectId.isNotEmpty) {
      final target = _findTargetObject(
        project,
        attr.referenceObjectId,
        refTargets,
      );
      final targetLabel =
          target?.technicalName ??
          refTargets[attr.referenceObjectId] ??
          attr.referenceObjectId;

      if (target != null &&
          !visited.contains(target.id) &&
          (target.attributes.isNotEmpty || target.relations.isNotEmpty)) {
        final resolvedSchema = _buildObjectSchema(
          project: project,
          obj: target,
          refTargets: refTargets,
          visited: <String>{...visited, target.id},
          strictObjects: strictObjects,
          valueObjects: valueObjects,
          valueObjectScopes: valueObjectScopes,
        );
        final schema = <String, Object?>{
          ...resolvedSchema,
          if (attr.description.isNotEmpty) 'description': attr.description,
          'x-reference': targetLabel,
        };
        return _finalizeArrayAndConstraints(
          attr: attr,
          itemSchema: schema,
        );
      }

      final fallbackSchema = <String, Object?>{
        'type': 'string',
        if (attr.description.isNotEmpty) 'description': attr.description,
        'x-reference': targetLabel,
      };
      return _finalizeArrayAndConstraints(
        attr: attr,
        itemSchema: fallbackSchema,
      );
    }

    return SpecSuperDesignerExporter.attributeToJsonSchema(
      attr,
      strictObjects: strictObjects,
      valueObjects: valueObjects,
      valueObjectScopes: valueObjectScopes,
    );
  }

  static BusinessObjectSpec? _findTargetObject(
    SpecForgeProject project,
    String refId,
    Map<String, String> refTargets,
  ) {
    final direct = project.findBusinessObject(refId);
    if (direct != null) return direct;
    final techName = refTargets[refId] ?? refId;
    final lower = techName.trim().toLowerCase();
    for (final obj in project.businessObjects) {
      if (obj.technicalName.trim().toLowerCase() == lower ||
          obj.name.trim().toLowerCase() == lower) {
        return obj;
      }
    }
    return null;
  }

  static Map<String, Object?> _finalizeArrayAndConstraints({
    required BusinessAttribute attr,
    required Map<String, Object?> itemSchema,
  }) {
    final schema = Map<String, Object?>.from(itemSchema);
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

  static Map<String, Object?> _useCaseFieldToSchema(UseCaseFieldSpec field) {
    final Map<String, Object?> itemSchema;
    if (field.children.isNotEmpty) {
      final childProps = <String, Object?>{};
      final childRequired = <String>[];
      for (final child in field.children) {
        childProps[child.name] = _useCaseFieldToSchema(child);
        if (child.effectiveRequired) {
          childRequired.add(child.name);
        }
      }
      itemSchema = <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        if (childRequired.isNotEmpty) 'required': childRequired,
        'properties': childProps,
      };
    } else {
      itemSchema = _scalarUseCaseTypeSchema(field);
    }

    if (field.enumValues.isNotEmpty) {
      itemSchema['enum'] = field.enumValues;
    }
    if (field.description.trim().isNotEmpty) {
      itemSchema['description'] = field.description.trim();
    }
    _applyUseCaseConstraints(itemSchema, field.constraints);

    if (field.nullable && itemSchema['type'] is String) {
      itemSchema['type'] = <String>[itemSchema['type'] as String, 'null'];
    }

    if (field.effectiveIsArray) {
      return <String, Object?>{'type': 'array', 'items': itemSchema};
    }
    return itemSchema;
  }

  static Map<String, Object?> _scalarUseCaseTypeSchema(UseCaseFieldSpec field) {
    var raw = field.type.trim();
    if (raw.endsWith('!') || raw.endsWith('?')) {
      raw = raw.substring(0, raw.length - 1).trim();
    }
    if (raw.endsWith('[]')) {
      raw = raw.substring(0, raw.length - 2).trim();
    } else {
      final genericMatch = RegExp(
        r'^(?:list|array)\s*<\s*(.+?)\s*>$',
        caseSensitive: false,
      ).firstMatch(raw);
      if (genericMatch != null) {
        raw = genericMatch.group(1)!.trim();
      }
    }

    final lower = raw.toLowerCase();
    if (lower.contains('uuid')) {
      return <String, Object?>{'type': 'string', 'format': 'uuid'};
    }
    if (lower.contains('datetime') || lower == 'date-time') {
      return <String, Object?>{'type': 'string', 'format': 'date-time'};
    }
    if (lower == 'date') {
      return <String, Object?>{'type': 'string', 'format': 'date'};
    }
    if (lower.contains('email')) {
      return <String, Object?>{'type': 'string', 'format': 'email'};
    }
    if (lower == 'url' || lower == 'uri') {
      return <String, Object?>{'type': 'string', 'format': 'uri'};
    }
    if (lower == 'int' || lower == 'integer') {
      return <String, Object?>{'type': 'integer'};
    }
    if (lower == 'number' ||
        lower == 'decimal' ||
        lower == 'double' ||
        lower == 'float') {
      return <String, Object?>{'type': 'number'};
    }
    if (lower == 'bool' || lower == 'boolean') {
      return <String, Object?>{'type': 'boolean'};
    }
    if (lower == 'object' || lower == 'json' || lower == 'map') {
      return <String, Object?>{'type': 'object'};
    }
    if (lower.startsWith('reference')) {
      final refMatch = RegExp(
        r'^reference\s*<\s*(.+?)\s*>$',
        caseSensitive: false,
      ).firstMatch(raw);
      return <String, Object?>{
        'type': 'string',
        if (refMatch != null) 'x-reference': refMatch.group(1)!.trim(),
      };
    }
    if (lower == 'enum' || lower == 'enumeration' || lower == 'string') {
      return <String, Object?>{'type': 'string'};
    }

    // Type métier ou personnalisé (ex. `OrderItem`, `Money`, etc.)
    final baseToken = raw.split(RegExp(r'[\s(]')).first.trim();
    if (baseToken.isNotEmpty &&
        baseToken != 'string' &&
        RegExp(r'^[A-Z]').hasMatch(baseToken)) {
      return <String, Object?>{'type': 'object', 'x-type': baseToken};
    }
    return <String, Object?>{'type': 'string'};
  }

  static void _applyUseCaseConstraints(
    Map<String, Object?> schema,
    String rawConstraints,
  ) {
    final trimmed = rawConstraints.trim();
    if (trimmed.isEmpty) return;

    final gtMatch = RegExp(r'^>\s*(-?\d+(?:\.\d+)?)$').firstMatch(trimmed);
    if (gtMatch != null) {
      schema['exclusiveMinimum'] = num.parse(gtMatch.group(1)!);
      return;
    }
    final gteMatch = RegExp(r'^>=\s*(-?\d+(?:\.\d+)?)$').firstMatch(trimmed);
    if (gteMatch != null) {
      schema['minimum'] = num.parse(gteMatch.group(1)!);
      return;
    }
    final ltMatch = RegExp(r'^<\s*(-?\d+(?:\.\d+)?)$').firstMatch(trimmed);
    if (ltMatch != null) {
      schema['exclusiveMaximum'] = num.parse(ltMatch.group(1)!);
      return;
    }
    final lteMatch = RegExp(r'^<=\s*(-?\d+(?:\.\d+)?)$').firstMatch(trimmed);
    if (lteMatch != null) {
      schema['maximum'] = num.parse(lteMatch.group(1)!);
      return;
    }

    final upper = trimmed.toUpperCase();
    if (upper == 'UUID') {
      schema['format'] = 'uuid';
      return;
    }
    if (trimmed.toLowerCase() == 'requis' ||
        trimmed.toLowerCase() == 'required' ||
        trimmed.toLowerCase() == 'obligatoire') {
      return;
    }

    schema['x-constraints'] = trimmed;
  }
}
