/// Synthétiseur autonome de schémas JSON Schema Draft 2020-12 à partir des
/// structures JSON brutes d'un catalogue `super_spec_forge` (`domains/catalog.json`),
/// sans dépendance au package `super_spec_forge`.
library;

import '../../models/json_value_utils.dart';

/// Synthétise les JSON Schemas Draft 2020-12 des Value Objects, modèles/contrats
/// et paramètres `Input` / `Output` des Use Cases lors d'un import direct.
abstract final class CatalogJsonSchemaSynthesizer {
  /// URI canonique du standard JSON Schema Draft 2020-12.
  static const String draft202012Uri =
      'https://json-schema.org/draft/2020-12/schema';

  static const Set<String> _arrayOnlyKeywords = <String>{
    'minItems',
    'maxItems',
    'uniqueItems',
    'contains',
    'minContains',
    'maxContains',
    'prefixItems',
  };

  static const Set<String> _knownConstraintKeywords = <String>{
    'minimum',
    'maximum',
    'exclusiveMinimum',
    'exclusiveMaximum',
    'multipleOf',
    'minLength',
    'maxLength',
    'pattern',
    'format',
    'contentMediaType',
    'contentEncoding',
    'minItems',
    'maxItems',
    'uniqueItems',
    'contains',
    'minContains',
    'maxContains',
    'prefixItems',
    'minProperties',
    'maxProperties',
    'additionalProperties',
    'patternProperties',
    'propertyNames',
    'dependentRequired',
    'dependentSchemas',
    'const',
    'examples',
    'readOnly',
    'writeOnly',
    'deprecated',
    'title',
    r'$comment',
    'oneOf',
    'anyOf',
    'allOf',
    'not',
    'if',
    'then',
    'else',
  };

  static const Set<String> _extraDraftKeywords = <String>{
    'unevaluatedProperties',
    'unevaluatedItems',
    'propertyDependencies',
    'contentSchema',
    'dependencies',
    'additionalItems',
  };

  /// Construit le JSON Schema Draft 2020-12 racine d'un Value Object résolu.
  static Map<String, Object?> buildValueObjectSchema({
    required Map<String, Object?> voSpec,
    required String technicalName,
    required String scope,
    required List<CatalogResolvedVoEntry> availableValueObjects,
    List<CatalogResolvedVoEntry> fallbackValueObjects =
        const <CatalogResolvedVoEntry>[],
    bool strictObjects = true,
  }) {
    final body = buildValueObjectBodySchema(
      voSpec: voSpec,
      technicalName: technicalName,
      scope: scope,
      availableValueObjects: availableValueObjects,
      fallbackValueObjects: fallbackValueObjects,
      strictObjects: strictObjects,
    );
    return freezeJsonMap(<String, Object?>{
      r'$schema': draft202012Uri,
      'title': technicalName,
      ...body,
    });
  }

  /// Construit le corps JSON Schema d'un Value Object (sans `$schema` ni `title`),
  /// réutilisable en ligne dans les attributs de modèles et composites.
  static Map<String, Object?> buildValueObjectBodySchema({
    required Map<String, Object?> voSpec,
    required String technicalName,
    required String scope,
    required List<CatalogResolvedVoEntry> availableValueObjects,
    List<CatalogResolvedVoEntry> fallbackValueObjects =
        const <CatalogResolvedVoEntry>[],
    bool strictObjects = true,
    Set<String>? visitedVoIds,
  }) {
    final voId = ((voSpec['id'] as String?)?.trim() ?? '').isNotEmpty
        ? (voSpec['id'] as String).trim()
        : technicalName;
    final isComposite = _isCompositeVo(voSpec);
    final visited = <String>{...?visitedVoIds};
    if (!visited.add(voId)) {
      return <String, Object?>{
        'type': isComposite ? 'object' : 'string',
        'x-value-object': technicalName,
        if (scope.isNotEmpty) 'x-value-object-scope': scope,
      };
    }

    final description = (voSpec['description'] as String?)?.trim() ?? '';

    if (!isComposite) {
      final primitiveKind = _normalizeAttributeKind(
        voSpec['primitiveType'] ?? 'string',
      );
      final enumValues = parseCleanStringList(voSpec['enumValues']);
      final schema = _basePrimitiveSchema(
        primitiveKind,
        enumValues: enumValues,
      );
      if (description.isNotEmpty) {
        schema['description'] = description;
      }
      final constraints = _extractConstraintsMap(voSpec['schemaConstraints']);
      for (final entry in constraints.entries) {
        if (!_arrayOnlyKeywords.contains(entry.key)) {
          schema[entry.key] = entry.value;
        }
      }
      schema['x-value-object'] = technicalName;
      if (scope.isNotEmpty) {
        schema['x-value-object-scope'] = scope;
      }
      final normalizationRules = parseCleanStringList(
        voSpec['normalizationRules'],
      );
      if (normalizationRules.isNotEmpty) {
        schema['x-normalization'] = normalizationRules;
      }
      if (!schema.containsKey('examples')) {
        final validExamples = _extractValidVoExamples(
          voSpec['examples'],
          primitiveKind,
        );
        if (validExamples.isNotEmpty) {
          schema['examples'] = validExamples;
        }
      }
      return schema;
    }

    final rawFields = voSpec['fields'];
    final properties = <String, Object?>{};
    final required = <String>[];
    if (rawFields is List) {
      for (final rawField in rawFields) {
        if (rawField is! Map) continue;
        final fieldMap = freezeJsonMap(rawField);
        final fieldName = (fieldMap['name'] as String?)?.trim() ?? '';
        if (fieldName.isEmpty) continue;
        properties[fieldName] = _buildAttributeSchema(
          attrMap: fieldMap,
          strictObjects: strictObjects,
          availableValueObjects: availableValueObjects,
          fallbackValueObjects: fallbackValueObjects,
          allContracts: const <CatalogRawContractItem>[],
          visitedContractIds: const <String>{},
          visitedVoIds: visited,
        );
        if (fieldMap['required'] == true) {
          required.add(fieldName);
        }
      }
    }

    final crossFieldRules = parseCleanStringList(voSpec['crossFieldRules']);
    return <String, Object?>{
      'type': 'object',
      if (description.isNotEmpty) 'description': description,
      if (strictObjects) 'additionalProperties': false,
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
      'x-value-object': technicalName,
      if (scope.isNotEmpty) 'x-value-object-scope': scope,
      if (crossFieldRules.isNotEmpty) 'x-cross-field-rules': crossFieldRules,
    };
  }

  /// Construit le JSON Schema Draft 2020-12 complet d'une entrée de modèle/contrat.
  static Map<String, Object?> buildContractObjectSchema({
    required CatalogRawContractItem contract,
    required List<CatalogRawContractItem> allContracts,
    required List<CatalogResolvedVoEntry> availableValueObjects,
    List<CatalogResolvedVoEntry> fallbackValueObjects =
        const <CatalogResolvedVoEntry>[],
    bool strictObjects = true,
  }) {
    final body = _buildContractBodySchema(
      contract: contract,
      allContracts: allContracts,
      availableValueObjects: availableValueObjects,
      fallbackValueObjects: fallbackValueObjects,
      visitedContractIds: <String>{contract.entryId, contract.objectId},
      strictObjects: strictObjects,
    );
    return freezeJsonMap(<String, Object?>{
      r'$schema': draft202012Uri,
      'title': contract.technicalName,
      ...body,
    });
  }

  /// Construit un JSON Schema Draft 2020-12 strict (`additionalProperties: false`)
  /// pour les paramètres `Input` ou `Output` d'un Use Case.
  static Map<String, Object?> buildUseCaseFieldsSchema({
    required String title,
    required Object? rawFields,
    String description = '',
  }) {
    final properties = <String, Object?>{};
    final required = <String>[];

    if (rawFields is List) {
      for (final rawField in rawFields) {
        final parsed = _parseUseCaseField(rawField);
        if (parsed == null) continue;
        properties[parsed.name] = _useCaseFieldToSchema(parsed);
        if (parsed.effectiveRequired) {
          required.add(parsed.name);
        }
      }
    }

    return freezeJsonMap(<String, Object?>{
      r'$schema': draft202012Uri,
      'title': title,
      if (description.trim().isNotEmpty) 'description': description.trim(),
      'type': 'object',
      'additionalProperties': false,
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
    });
  }

  static Map<String, Object?> _buildContractBodySchema({
    required CatalogRawContractItem contract,
    required List<CatalogRawContractItem> allContracts,
    required List<CatalogResolvedVoEntry> availableValueObjects,
    required List<CatalogResolvedVoEntry> fallbackValueObjects,
    required Set<String> visitedContractIds,
    required bool strictObjects,
  }) {
    final objSpec = contract.objectSpec;
    final properties = <String, Object?>{};
    final required = <String>[];

    final rawAttributes = objSpec['attributes'];
    if (rawAttributes is List) {
      for (final rawAttr in rawAttributes) {
        if (rawAttr is! Map) continue;
        final attrMap = freezeJsonMap(rawAttr);
        final attrName = (attrMap['name'] as String?)?.trim() ?? '';
        if (attrName.isEmpty) continue;
        properties[attrName] = _buildAttributeSchema(
          attrMap: attrMap,
          strictObjects: strictObjects,
          availableValueObjects: availableValueObjects,
          fallbackValueObjects: fallbackValueObjects,
          allContracts: allContracts,
          visitedContractIds: visitedContractIds,
        );
        if (attrMap['required'] == true) {
          required.add(attrName);
        }
      }
    }

    final rawRelations = objSpec['relations'];
    if (rawRelations is List) {
      for (final rawRel in rawRelations) {
        if (rawRel is! Map) continue;
        final relMap = freezeJsonMap(rawRel);
        final relName = (relMap['name'] as String?)?.trim() ?? '';
        if (relName.isEmpty) continue;
        final targetObjId = (relMap['targetObjectId'] as String?)?.trim() ?? '';
        final target = _findTargetContract(allContracts, targetObjId);
        final isList = _isCollectionCardinality(relMap['cardinality']);

        final Map<String, Object?> itemOrRefSchema;
        if (target != null &&
            !visitedContractIds.contains(target.entryId) &&
            !visitedContractIds.contains(target.objectId)) {
          itemOrRefSchema = _buildContractBodySchema(
            contract: target,
            allContracts: allContracts,
            availableValueObjects: availableValueObjects,
            fallbackValueObjects: fallbackValueObjects,
            visitedContractIds: <String>{
              ...visitedContractIds,
              target.entryId,
              target.objectId,
            },
            strictObjects: strictObjects,
          );
        } else {
          itemOrRefSchema = <String, Object?>{'type': 'string'};
        }

        properties[relName] = isList
            ? <String, Object?>{'type': 'array', 'items': itemOrRefSchema}
            : itemOrRefSchema;
        if (relMap['required'] == true && !required.contains(relName)) {
          required.add(relName);
        }
      }
    }

    final description = (objSpec['description'] as String?) ?? '';
    return <String, Object?>{
      'type': 'object',
      if (description.isNotEmpty) 'description': description,
      if (strictObjects) 'additionalProperties': false,
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
    };
  }

  static Map<String, Object?> _buildAttributeSchema({
    required Map<String, Object?> attrMap,
    required bool strictObjects,
    required List<CatalogResolvedVoEntry> availableValueObjects,
    required List<CatalogResolvedVoEntry> fallbackValueObjects,
    required List<CatalogRawContractItem> allContracts,
    required Set<String> visitedContractIds,
    Set<String>? visitedVoIds,
  }) {
    final rawChildren = attrMap['children'];
    final hasChildren = rawChildren is List && rawChildren.isNotEmpty;
    final resolvedKind = _normalizeAttributeKind(attrMap['type']);
    final effectiveKind = (hasChildren && resolvedKind == 'json')
        ? 'object'
        : resolvedKind;
    final description = (attrMap['description'] as String?)?.trim() ?? '';

    if (effectiveKind == 'object' && hasChildren) {
      final childProps = <String, Object?>{};
      final childRequired = <String>[];
      for (final rawChild in rawChildren) {
        if (rawChild is! Map) continue;
        final childMap = freezeJsonMap(rawChild);
        final childName = (childMap['name'] as String?)?.trim() ?? '';
        if (childName.isEmpty) continue;
        childProps[childName] = _buildAttributeSchema(
          attrMap: childMap,
          strictObjects: strictObjects,
          availableValueObjects: availableValueObjects,
          fallbackValueObjects: fallbackValueObjects,
          allContracts: allContracts,
          visitedContractIds: visitedContractIds,
          visitedVoIds: visitedVoIds,
        );
        if (childMap['required'] == true) {
          childRequired.add(childName);
        }
      }
      final objectSchema = <String, Object?>{
        'type': 'object',
        if (description.isNotEmpty) 'description': description,
        if (strictObjects) 'additionalProperties': false,
        if (childRequired.isNotEmpty) 'required': childRequired,
        'properties': childProps,
      };
      return _finalizeArrayAndConstraints(
        attrMap: attrMap,
        itemSchema: objectSchema,
      );
    }

    if (effectiveKind == 'reference') {
      final refId = (attrMap['referenceObjectId'] as String?)?.trim() ?? '';
      if (refId.isNotEmpty) {
        final target = _findTargetContract(allContracts, refId);
        final targetLabel = target?.technicalName ?? refId;
        if (target != null &&
            !visitedContractIds.contains(target.entryId) &&
            !visitedContractIds.contains(target.objectId) &&
            target.hasAttributesOrRelations) {
          final resolvedTarget = _buildContractBodySchema(
            contract: target,
            allContracts: allContracts,
            availableValueObjects: availableValueObjects,
            fallbackValueObjects: fallbackValueObjects,
            visitedContractIds: <String>{
              ...visitedContractIds,
              target.entryId,
              target.objectId,
            },
            strictObjects: strictObjects,
          );
          final refSchema = <String, Object?>{
            ...resolvedTarget,
            if (description.isNotEmpty) 'description': description,
            'x-reference': targetLabel,
          };
          return _finalizeArrayAndConstraints(
            attrMap: attrMap,
            itemSchema: refSchema,
          );
        }
        final fallbackRef = <String, Object?>{
          'type': 'string',
          if (description.isNotEmpty) 'description': description,
          'x-reference': targetLabel,
        };
        return _finalizeArrayAndConstraints(
          attrMap: attrMap,
          itemSchema: fallbackRef,
        );
      }
      final bareRef = <String, Object?>{
        'type': 'string',
        if (description.isNotEmpty) 'description': description,
      };
      return _finalizeArrayAndConstraints(
        attrMap: attrMap,
        itemSchema: bareRef,
      );
    }

    final Map<String, Object?> itemSchema;
    if (effectiveKind == 'valueObject') {
      final voNeedle = (attrMap['valueObjectId'] as String?)?.trim() ?? '';
      final resolvedVo = _resolveValueObject(
        voNeedle,
        availableValueObjects,
        fallbackValueObjects,
      );
      if (resolvedVo != null) {
        itemSchema = Map<String, Object?>.from(
          buildValueObjectBodySchema(
            voSpec: resolvedVo.spec,
            technicalName: resolvedVo.technicalName,
            scope: resolvedVo.scope,
            availableValueObjects: availableValueObjects,
            fallbackValueObjects: fallbackValueObjects,
            strictObjects: strictObjects,
            visitedVoIds: visitedVoIds,
          ),
        );
      } else {
        itemSchema = <String, Object?>{
          'type': 'string',
          if (voNeedle.isNotEmpty) 'x-value-object': voNeedle,
        };
      }
    } else if (effectiveKind == 'object') {
      itemSchema = <String, Object?>{
        'type': 'object',
        if (strictObjects) 'additionalProperties': false,
      };
    } else if (effectiveKind == 'json') {
      itemSchema = <String, Object?>{'type': 'object'};
    } else {
      final enumValues = parseCleanStringList(attrMap['enumValues']);
      itemSchema = _basePrimitiveSchema(effectiveKind, enumValues: enumValues);
    }

    if (description.isNotEmpty) {
      itemSchema['description'] = description;
    }
    return _finalizeArrayAndConstraints(
      attrMap: attrMap,
      itemSchema: itemSchema,
    );
  }

  static Map<String, Object?> _finalizeArrayAndConstraints({
    required Map<String, Object?> attrMap,
    required Map<String, Object?> itemSchema,
  }) {
    final schema = Map<String, Object?>.from(itemSchema);
    final isArray = attrMap['isArray'] == true;
    final nullable = attrMap['nullable'] == true;
    final rawConstraintsSource = attrMap.containsKey('schemaConstraints')
        ? attrMap['schemaConstraints']
        : attrMap;
    final constraints = _extractConstraintsMap(rawConstraintsSource);

    final arrayConstraints = <String, Object?>{};
    for (final entry in constraints.entries) {
      if (isArray && _arrayOnlyKeywords.contains(entry.key)) {
        arrayConstraints[entry.key] = entry.value;
      } else if (!_arrayOnlyKeywords.contains(entry.key)) {
        schema[entry.key] = entry.value;
      }
    }

    if (nullable && schema['type'] is String) {
      schema['type'] = <String>[schema['type'] as String, 'null'];
    }

    if (isArray) {
      final estimatedMax = _asInt(attrMap['estimatedMaxRows']);
      final effectiveMaxItems = arrayConstraints['maxItems'] ?? estimatedMax;
      return <String, Object?>{
        'type': 'array',
        ...arrayConstraints,
        'maxItems': ?effectiveMaxItems,
        'items': schema,
      };
    }
    return schema;
  }

  static Map<String, Object?> _basePrimitiveSchema(
    String normalizedKind, {
    List<String> enumValues = const <String>[],
  }) => switch (normalizedKind) {
    'integer' => <String, Object?>{'type': 'integer'},
    'number' => <String, Object?>{'type': 'number'},
    'boolean' => <String, Object?>{'type': 'boolean'},
    'date' => <String, Object?>{'type': 'string', 'format': 'date'},
    'datetime' => <String, Object?>{'type': 'string', 'format': 'date-time'},
    'uuid' => <String, Object?>{'type': 'string', 'format': 'uuid'},
    'email' => <String, Object?>{'type': 'string', 'format': 'email'},
    'url' => <String, Object?>{'type': 'string', 'format': 'uri'},
    'enumeration' => <String, Object?>{
      'type': 'string',
      if (enumValues.isNotEmpty) 'enum': enumValues,
    },
    _ => <String, Object?>{'type': 'string'},
  };

  static String _normalizeAttributeKind(Object? raw) {
    if (raw is! String) return 'string';
    switch (raw.trim().toLowerCase()) {
      case 'int':
      case 'integer':
        return 'integer';
      case 'number':
      case 'float':
      case 'double':
      case 'decimal':
        return 'number';
      case 'bool':
      case 'boolean':
        return 'boolean';
      case 'date':
        return 'date';
      case 'datetime':
      case 'date-time':
      case 'timestamp':
        return 'datetime';
      case 'uuid':
        return 'uuid';
      case 'email':
        return 'email';
      case 'url':
      case 'uri':
        return 'url';
      case 'enum':
      case 'enumeration':
        return 'enumeration';
      case 'ref':
      case 'reference':
        return 'reference';
      case 'vo':
      case 'valueobject':
      case 'value_object':
      case 'value-object':
        return 'valueObject';
      case 'object':
      case 'subobject':
      case 'sub_object':
      case 'sous-objet':
      case 'struct':
        return 'object';
      case 'json':
      case 'any':
        return 'json';
      default:
        return 'string';
    }
  }

  static bool _isCompositeVo(Map<String, Object?> voSpec) {
    final rawKind = (voSpec['kind'] as String?)?.trim().toLowerCase();
    if (rawKind != null && rawKind.isNotEmpty) {
      return rawKind == 'composite' ||
          rawKind == 'struct' ||
          rawKind == 'object' ||
          rawKind == 'multi' ||
          rawKind == 'multi_fields';
    }
    final fields = voSpec['fields'];
    return fields is List && fields.isNotEmpty;
  }

  static bool _isCollectionCardinality(Object? raw) {
    if (raw is! String) return true;
    final norm = raw.trim().toLowerCase();
    if (norm == 'onetoone' || norm == '1:1') return false;
    return true;
  }

  static CatalogRawContractItem? _findTargetContract(
    List<CatalogRawContractItem> allContracts,
    String refId,
  ) {
    final needle = refId.trim();
    if (needle.isEmpty || allContracts.isEmpty) return null;
    for (final item in allContracts) {
      if (item.entryId == needle || item.objectId == needle) return item;
    }
    final lower = needle.toLowerCase();
    for (final item in allContracts) {
      if (item.technicalName.toLowerCase() == lower ||
          item.name.toLowerCase() == lower) {
        return item;
      }
    }
    return null;
  }

  static CatalogResolvedVoEntry? _resolveValueObject(
    String idOrName,
    List<CatalogResolvedVoEntry> available,
    List<CatalogResolvedVoEntry> fallback,
  ) {
    final needle = idOrName.trim();
    if (needle.isEmpty) return null;
    for (final vo in available) {
      if (vo.id == needle) return vo;
    }
    final lower = needle.toLowerCase();
    for (final vo in available) {
      if (vo.technicalName.toLowerCase() == lower) return vo;
    }
    for (final vo in fallback) {
      if (vo.id == needle) return vo;
    }
    return null;
  }

  static List<Object> _extractValidVoExamples(
    Object? rawExamples,
    String primitiveKind,
  ) {
    if (rawExamples is! List) return const <Object>[];
    final out = <Object>[];
    for (final raw in rawExamples) {
      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty) {
          out.add(_coerceExampleScalar(trimmed, primitiveKind));
        }
      } else if (raw is Map) {
        final isValid = raw['isValid'] is bool
            ? raw['isValid'] as bool
            : (raw['valid'] is bool ? raw['valid'] as bool : true);
        if (!isValid) continue;
        final val = raw['value']?.toString().trim() ?? '';
        if (val.isNotEmpty) {
          out.add(_coerceExampleScalar(val, primitiveKind));
        }
      }
    }
    return out;
  }

  static Object _coerceExampleScalar(String trimmed, String primitiveKind) =>
      switch (primitiveKind) {
        'integer' => int.tryParse(trimmed) ?? trimmed,
        'number' => num.tryParse(trimmed) ?? trimmed,
        'boolean' =>
          trimmed.toLowerCase() == 'true'
              ? true
              : (trimmed.toLowerCase() == 'false' ? false : trimmed),
        _ => trimmed,
      };

  static Map<String, Object?> _extractConstraintsMap(Object? raw) {
    if (raw is! Map || raw.isEmpty) return const <String, Object?>{};
    final out = <String, Object?>{};

    var minVal = _asNum(raw['minimum']);
    var maxVal = _asNum(raw['maximum']);
    var exclMin = _asNum(raw['exclusiveMinimum']);
    var exclMax = _asNum(raw['exclusiveMaximum']);
    if (raw['exclusiveMinimum'] == true && minVal != null) {
      exclMin = minVal;
      minVal = null;
    }
    if (raw['exclusiveMaximum'] == true && maxVal != null) {
      exclMax = maxVal;
      maxVal = null;
    }

    void putIfNonEmptyStr(String key, Object? v) {
      if (v is String && v.trim().isNotEmpty) {
        out[key] = key == 'pattern' ? v : v.trim();
      }
    }

    putIfNonEmptyStr('title', raw['title']);
    putIfNonEmptyStr(r'$comment', raw[r'$comment']);
    if (minVal != null) out['minimum'] = minVal;
    if (maxVal != null) out['maximum'] = maxVal;
    if (exclMin != null) out['exclusiveMinimum'] = exclMin;
    if (exclMax != null) out['exclusiveMaximum'] = exclMax;
    final mult = _asNum(raw['multipleOf']);
    if (mult != null) out['multipleOf'] = mult;

    for (final intKey in const <String>[
      'minLength',
      'maxLength',
      'minItems',
      'maxItems',
      'minContains',
      'maxContains',
      'minProperties',
      'maxProperties',
    ]) {
      final parsed = _asInt(raw[intKey]);
      if (parsed != null) out[intKey] = parsed;
    }

    putIfNonEmptyStr('pattern', raw['pattern']);
    putIfNonEmptyStr('format', raw['format']);
    putIfNonEmptyStr('contentMediaType', raw['contentMediaType']);
    putIfNonEmptyStr('contentEncoding', raw['contentEncoding']);

    for (final boolKey in const <String>[
      'uniqueItems',
      'readOnly',
      'writeOnly',
      'deprecated',
    ]) {
      if (raw[boolKey] is bool) out[boolKey] = raw[boolKey];
    }

    if (raw['additionalProperties'] is bool ||
        raw['additionalProperties'] is Map) {
      out['additionalProperties'] = freezeJsonValue(
        raw['additionalProperties'],
      );
    }

    for (final mapKey in const <String>[
      'contains',
      'patternProperties',
      'propertyNames',
      'dependentRequired',
      'dependentSchemas',
      'not',
      'if',
      'then',
      'else',
    ]) {
      if (raw[mapKey] is Map && (raw[mapKey] as Map).isNotEmpty) {
        out[mapKey] = freezeJsonMap(raw[mapKey] as Map);
      }
    }

    for (final listKey in const <String>[
      'prefixItems',
      'oneOf',
      'anyOf',
      'allOf',
    ]) {
      if (raw[listKey] is List && (raw[listKey] as List).isNotEmpty) {
        out[listKey] = freezeJsonMapList(raw[listKey]);
      }
    }

    if (raw.containsKey('const')) {
      out['const'] = freezeJsonValue(raw['const']);
    }
    if (raw['examples'] is List && (raw['examples'] as List).isNotEmpty) {
      out['examples'] = freezeJsonValue(raw['examples']);
    }

    for (final entry in raw.entries) {
      final key = '${entry.key}';
      if (!_knownConstraintKeywords.contains(key) &&
          (key.startsWith('x-') || _extraDraftKeywords.contains(key))) {
        out.putIfAbsent(key, () => freezeJsonValue(entry.value));
      }
    }
    return out;
  }

  static num? _asNum(Object? v) => switch (v) {
    int i => i,
    double d when d.isFinite => d,
    num n when n.isFinite => n,
    String s => num.tryParse(s.trim()),
    _ => null,
  };

  static int? _asInt(Object? v) => switch (v) {
    int i => i,
    num n when n.isFinite => n.toInt(),
    String s => int.tryParse(s.trim()),
    _ => null,
  };

  static _ParsedUseCaseField? _parseUseCaseField(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final idx = trimmed.indexOf(':');
      if (idx > 0) {
        final rawName = trimmed.substring(0, idx).trim();
        if (rawName.isEmpty) return null;
        var rawType = trimmed.substring(idx + 1).trim();
        var constraints = '';
        final parenMatch = RegExp(r'^(.+?)\s*\(([^)]+)\)\s*$')
            .firstMatch(rawType);
        if (parenMatch != null) {
          rawType = parenMatch.group(1)!.trim();
          constraints = parenMatch.group(2)!.trim();
        }
        var nullable = false;
        bool? required;
        var isArray = false;
        if (rawType.endsWith('?')) {
          nullable = true;
          rawType = rawType.substring(0, rawType.length - 1).trim();
        }
        if (rawType.endsWith('!')) {
          required = true;
          rawType = rawType.substring(0, rawType.length - 1).trim();
        }
        if (rawType.endsWith('[]')) {
          isArray = true;
          rawType = rawType.substring(0, rawType.length - 2).trim();
        }
        return _ParsedUseCaseField(
          name: rawName,
          type: rawType.isEmpty ? 'string' : rawType,
          constraints: constraints,
          description: '',
          required: required,
          nullable: nullable,
          isArray: isArray,
          enumValues: const <String>[],
          children: const <_ParsedUseCaseField>[],
        );
      }
      return _ParsedUseCaseField(
        name: trimmed,
        type: 'string',
        constraints: '',
        description: '',
        required: null,
        nullable: false,
        isArray: false,
        enumValues: const <String>[],
        children: const <_ParsedUseCaseField>[],
      );
    }
    if (raw is! Map) return null;
    final name = (raw['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    final rawType = (raw['type'] as String?)?.trim() ?? '';
    final children = <_ParsedUseCaseField>[];
    if (raw['children'] case final List rawChildren) {
      for (final item in rawChildren) {
        final parsedChild = _parseUseCaseField(item);
        if (parsedChild != null) children.add(parsedChild);
      }
    }
    return _ParsedUseCaseField(
      name: name,
      type: rawType.isEmpty ? 'string' : rawType,
      constraints: (raw['constraints'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      required: raw['required'] is bool ? raw['required'] as bool : null,
      nullable: raw['nullable'] == true,
      isArray: raw['isArray'] == true,
      enumValues: parseCleanStringList(raw['enumValues'] ?? raw['enum']),
      children: children,
    );
  }

  static Map<String, Object?> _useCaseFieldToSchema(_ParsedUseCaseField field) {
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
      itemSchema = _scalarUseCaseTypeSchema(field.type);
    }

    if (field.enumValues.isNotEmpty) {
      itemSchema['enum'] = field.enumValues;
    }
    if (field.description.isNotEmpty) {
      itemSchema['description'] = field.description;
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

  static Map<String, Object?> _scalarUseCaseTypeSchema(String fieldType) {
    var raw = fieldType.trim();
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

    if (trimmed.toUpperCase() == 'UUID') {
      schema['format'] = 'uuid';
      return;
    }
    final lower = trimmed.toLowerCase();
    if (lower == 'requis' || lower == 'required' || lower == 'obligatoire') {
      return;
    }
    schema['x-constraints'] = trimmed;
  }
}

/// Représentation intermédiaire d'un Value Object résolu pour la synthèse JSON Schema.
class CatalogResolvedVoEntry {
  /// Crée une entrée intermédiaire de Value Object résolu.
  const CatalogResolvedVoEntry({
    required this.id,
    required this.technicalName,
    required this.scope,
    required this.spec,
  });

  /// Identifiant technique du Value Object.
  final String id;

  /// Nom technique PascalCase du Value Object.
  final String technicalName;

  /// Portée résolue (`domain` ou `shared`).
  final String scope;

  /// Spécification JSON brute du Value Object.
  final Map<String, Object?> spec;
}

/// Représentation intermédiaire d'une entrée de contrat pour la résolution croisée.
class CatalogRawContractItem {
  /// Crée une entrée intermédiaire de contrat.
  const CatalogRawContractItem({
    required this.entryId,
    required this.objectId,
    required this.name,
    required this.technicalName,
    required this.groupName,
    required this.dslType,
    required this.title,
    required this.version,
    required this.states,
    required this.objectSpec,
    required this.domainLayer,
  });

  /// Identifiant du nœud dans l'arbre DSL.
  final String entryId;

  /// Identifiant interne de `objectSpec` (égal à [entryId] par défaut).
  final String objectId;

  /// Nom du nœud DSL.
  final String name;

  /// Nom technique PascalCase de l'entrée.
  final String technicalName;

  /// Rubrique DSL parente (`models`, `dto`, `message`, `components`).
  final String groupName;

  /// Type DSL (`model`, `createxdto`, etc.).
  final String dslType;

  /// Libellé métier.
  final String title;

  /// Version sémantique (`x.y.z`).
  final String version;

  /// États d'avancement par étape.
  final Map<String, String> states;

  /// Spécification JSON brute de l'objet métier.
  final Map<String, Object?> objectSpec;

  /// Spécification JSON brute de la couche Domain hexagonale.
  final Map<String, Object?> domainLayer;

  /// Indique si `objectSpec` déclare au moins un attribut ou une relation.
  bool get hasAttributesOrRelations {
    final attrs = objectSpec['attributes'];
    final rels = objectSpec['relations'];
    return (attrs is List && attrs.isNotEmpty) ||
        (rels is List && rels.isNotEmpty);
  }
}

class _ParsedUseCaseField {
  const _ParsedUseCaseField({
    required this.name,
    required this.type,
    required this.constraints,
    required this.description,
    required this.required,
    required this.nullable,
    required this.isArray,
    required this.enumValues,
    required this.children,
  });

  final String name;
  final String type;
  final String constraints;
  final String description;
  final bool? required;
  final bool nullable;
  final bool isArray;
  final List<String> enumValues;
  final List<_ParsedUseCaseField> children;

  bool get effectiveRequired {
    if (required != null) return required!;
    final lower = '${constraints.toLowerCase()} ${type.toLowerCase()}';
    if (lower.contains('optionnel') || lower.contains('optional')) {
      return false;
    }
    return lower.contains('requis') ||
        lower.contains('required') ||
        lower.contains('obligatoire') ||
        type.trim().endsWith('!');
  }

  bool get effectiveIsArray {
    if (isArray) return true;
    final lower = type.trim().toLowerCase();
    return lower.endsWith('[]') ||
        lower.startsWith('list<') ||
        lower.startsWith('array<');
  }
}
