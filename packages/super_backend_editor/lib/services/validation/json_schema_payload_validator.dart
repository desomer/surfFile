/// Validateur déterministe et hors-ligne de charges utiles JSON selon le
/// standard JSON Schema Draft 2020-12 et les spécifications de Value Objects
/// ([ImportedValueObjectSpec]).
library;

import 'package:flutter/foundation.dart';
import 'package:super_backend/super_backend.dart';

import '../../models/domain_design_spec.dart';
import '../../models/json_value_utils.dart';

final RegExp _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

final RegExp _emailRegex = RegExp(
  r"^[^\s@]+@[^\s@.]+\.(?:[^\s@.]+\.)*[^\s@.]{2,}$",
);

final RegExp _isoDateRegex = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

final RegExp _isoDateTimeRegex = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:[Zz]|[+-]\d{2}:\d{2})$',
);

/// Violation unitaire relevée lors de la validation d'une charge utile JSON.
@immutable
class PayloadValidationViolation {
  /// Crée une violation immuable sur [path] pour la règle [rule].
  const PayloadValidationViolation({
    required this.path,
    required this.rule,
    required this.message,
  });

  /// Chemin JSON de la valeur en erreur (ex. `'$.email'` ou `'$.lines[0].qty'`).
  final String path;

  /// Code de la règle JSON Schema en échec (ex. `'required'`, `'type'`, `'minimum'`).
  final String rule;

  /// Message explicatif lisible en français.
  final String message;

  /// Retourne une copie modifiée de la violation.
  PayloadValidationViolation copyWith({
    String? path,
    String? rule,
    String? message,
  }) => PayloadValidationViolation(
    path: path ?? this.path,
    rule: rule ?? this.rule,
    message: message ?? this.message,
  );

  /// Sérialise la violation en objet JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'rule': rule,
    'message': message,
  };

  /// Désérialise une violation depuis JSON.
  factory PayloadValidationViolation.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('PayloadValidationViolation invalide.');
    }
    return PayloadValidationViolation(
      path: (raw['path'] as String?)?.trim() ?? r'$',
      rule: (raw['rule'] as String?)?.trim() ?? 'invalid',
      message: (raw['message'] as String?)?.trim() ?? 'Valeur invalide.',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PayloadValidationViolation &&
          other.path == path &&
          other.rule == rule &&
          other.message == message;

  @override
  int get hashCode => Object.hash(path, rule, message);

  @override
  String toString() => '[$rule] $path — $message';
}

/// Résultat complet et immuable d'une validation JSON Schema.
@immutable
class PayloadValidationResult {
  /// Crée un résultat de validation à partir de la liste [violations].
  PayloadValidationResult({
    List<PayloadValidationViolation> violations =
        const <PayloadValidationViolation>[],
  }) : violations = List<PayloadValidationViolation>.unmodifiable(violations);

  const PayloadValidationResult._valid()
    : violations = const <PayloadValidationViolation>[];

  /// Instance constante représentant un résultat sans violation.
  static const PayloadValidationResult valid = PayloadValidationResult._valid();

  /// Liste immuable des violations relevées (vide lorsque [isValid] vaut `true`).
  final List<PayloadValidationViolation> violations;

  /// Indique si la charge utile respecte intégralement le schéma.
  bool get isValid => violations.isEmpty;

  /// Construit la charge d'erreur normalisée prête pour une réponse HTTP/API.
  Map<String, Object?> toErrorPayload() => <String, Object?>{
    'code': 'validation_failed',
    'message': isValid
        ? 'Aucune erreur de validation.'
        : (violations.length == 1
              ? violations.first.message
              : 'La validation du payload a échoué (${violations.length} violations).'),
    'violations': <Map<String, Object?>>[
      for (final violation in violations) violation.toJson(),
    ],
  };

  /// Lève une [PayloadValidationException] si [isValid] vaut `false`.
  void throwIfInvalid() {
    if (!isValid) {
      throw PayloadValidationException(this);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PayloadValidationResult &&
          listEquals(other.violations, violations);

  @override
  int get hashCode => Object.hashAll(violations);

  @override
  String toString() => isValid
      ? 'PayloadValidationResult(valid)'
      : 'PayloadValidationResult(${violations.length} violations: '
            '${violations.join('; ')})';
}

/// Exception levée lorsqu'une charge utile échoue à la validation JSON Schema.
class PayloadValidationException extends SuperBackendException
    implements Exception {
  /// Crée une exception portant le [result] détaillé de la validation.
  PayloadValidationException(
    this.result, {
    String? message,
    super.statusCode = 422,
  }) : super(
         code: 'validation_failed',
         message:
             message ??
             (result.violations.isEmpty
                 ? 'La validation de la charge utile JSON a échoué.'
                 : result.violations
                       .map((v) => '${v.path}: ${v.message}')
                       .join(' ; ')),
       );

  /// Résultat structuré contenant l'ensemble des violations détectées.
  final PayloadValidationResult result;

  @override
  Map<String, Object?> toJson() => result.toErrorPayload();

  @override
  String toString() => 'PayloadValidationException: $message';
}

/// Validateur déterministe et sans accès réseau conforme au brouillon
/// JSON Schema Draft 2020-12 et aux Value Objects du domaine.
class JsonSchemaPayloadValidator {
  /// Crée un validateur optionnellement enrichi d'un catalogue de Value Objects.
  const JsonSchemaPayloadValidator({
    this._valueObjectsByKey = const <String, ImportedValueObjectSpec>{},
  });

  /// Construit un validateur indexant tous les Value Objects d'une [DomainDesignSpec].
  factory JsonSchemaPayloadValidator.fromDesignSpec(DomainDesignSpec spec) {
    final map = <String, ImportedValueObjectSpec>{};
    for (final vo in spec.valueObjects) {
      map[vo.id] = vo;
      map[vo.technicalName] = vo;
      map[vo.technicalName.toLowerCase()] = vo;
      map[vo.name.toLowerCase()] = vo;
    }
    return JsonSchemaPayloadValidator(
      valueObjectsByKey: Map<String, ImportedValueObjectSpec>.unmodifiable(map),
    );
  }

  /// Champs techniques système ignorés par `additionalProperties: false`
  /// lorsque `allowSystemFields` vaut `true`.
  static const Set<String> defaultSystemFields = <String>{
    'id',
    'version',
    'deletedAt',
    'createdAt',
    'updatedAt',
  };

  final Map<String, ImportedValueObjectSpec> _valueObjectsByKey;

  /// Valide [value] par rapport au schéma Draft 2020-12 [schema].
  ///
  /// - [partialUpdate] : ignore l'absence des champs `required` de premier
  ///   niveau tout en validant intégralement chaque champ fourni (mode `PATCH`).
  /// - [allowSystemFields] : autorise les métadonnées système ([systemFields])
  ///   même lorsque `additionalProperties` vaut `false`.
  PayloadValidationResult validate(
    Object? value,
    Map<String, Object?> schema, {
    bool partialUpdate = false,
    bool allowSystemFields = false,
    Set<String> systemFields = defaultSystemFields,
    String rootPath = r'$',
  }) {
    if (schema.isEmpty) return PayloadValidationResult.valid;
    final violations = <PayloadValidationViolation>[];
    final ctx = _ValidationContext(
      rootSchema: schema,
      rootPath: rootPath,
      partialUpdate: partialUpdate,
      allowSystemFields: allowSystemFields,
      systemFields: systemFields,
      valueObjectsByKey: _valueObjectsByKey,
    );
    _validateNode(
      value: value,
      schemaNode: schema,
      path: rootPath,
      ctx: ctx,
      violations: violations,
      activeRefs: <String>{},
    );
    return violations.isEmpty
        ? PayloadValidationResult.valid
        : PayloadValidationResult(violations: violations);
  }

  /// Valide [value] et lève [PayloadValidationException] en cas de violation.
  void assertValid(
    Object? value,
    Map<String, Object?> schema, {
    bool partialUpdate = false,
    bool allowSystemFields = false,
    Set<String> systemFields = defaultSystemFields,
    String rootPath = r'$',
  }) {
    validate(
      value,
      schema,
      partialUpdate: partialUpdate,
      allowSystemFields: allowSystemFields,
      systemFields: systemFields,
      rootPath: rootPath,
    ).throwIfInvalid();
  }

  /// Valide [value] contre un [ImportedValueObjectSpec] en exploitant son
  /// `jsonSchema` ou, s'il est vide, les contraintes issues de `specJson`.
  PayloadValidationResult validateAgainstValueObject(
    Object? value,
    ImportedValueObjectSpec vo, {
    String rootPath = r'$',
  }) {
    final effectiveSchema = vo.jsonSchema.isNotEmpty
        ? vo.jsonSchema
        : synthesizeValueObjectSchema(
            vo,
            valueObjectsByKey: _valueObjectsByKey,
          );
    return validate(value, effectiveSchema, rootPath: rootPath);
  }

  /// Synthétise un schéma JSON Draft 2020-12 à partir de [vo] lorsque son
  /// `jsonSchema` pré-généré est absent ou vide.
  static Map<String, Object?> synthesizeValueObjectSchema(
    ImportedValueObjectSpec vo, {
    Map<String, ImportedValueObjectSpec> valueObjectsByKey =
        const <String, ImportedValueObjectSpec>{},
  }) {
    if (vo.jsonSchema.isNotEmpty) return vo.jsonSchema;
    return _synthesizeVoSchemaInternal(
      vo,
      valueObjectsByKey: valueObjectsByKey,
      visitedIds: <String>{},
    );
  }

  static Map<String, Object?> _synthesizeVoSchemaInternal(
    ImportedValueObjectSpec vo, {
    required Map<String, ImportedValueObjectSpec> valueObjectsByKey,
    required Set<String> visitedIds,
  }) {
    if (!visitedIds.add(vo.id)) {
      return const <String, Object?>{};
    }
    final spec = vo.specJson;
    final out = <String, Object?>{};

    if (vo.isScalar) {
      final rawType =
          (vo.primitiveType ?? spec['primitiveType'] ?? 'string')
              .toString()
              .trim()
              .toLowerCase();
      _applyPrimitiveTypeAndFormat(out, rawType);

      final rawEnums = spec['enumValues'] ?? spec['enum'];
      if (rawEnums is List && rawEnums.isNotEmpty) {
        out['enum'] = List<Object?>.unmodifiable(rawEnums);
      }

      _mergeConstraintsMap(out, spec);
      if (spec['schemaConstraints'] case final Map sc) {
        _mergeConstraintsMap(out, sc);
      }
    } else {
      out['type'] = 'object';
      final properties = <String, Object?>{};
      final requiredFields = <String>[];
      for (final field in vo.fields) {
        final fieldName = (field['name'] as String?)?.trim() ?? '';
        if (fieldName.isEmpty) continue;
        properties[fieldName] = _attributeMapToSchema(
          field,
          valueObjectsByKey: valueObjectsByKey,
          visitedVoIds: visitedIds,
        );
        if (field['required'] == true) {
          requiredFields.add(fieldName);
        }
      }
      if (properties.isNotEmpty) {
        out['properties'] = properties;
      }
      if (requiredFields.isNotEmpty) {
        out['required'] = requiredFields;
      }
      if (spec.containsKey('additionalProperties')) {
        out['additionalProperties'] = spec['additionalProperties'];
      } else if (properties.isNotEmpty) {
        out['additionalProperties'] = false;
      }
      _mergeConstraintsMap(out, spec);
      if (spec['schemaConstraints'] case final Map sc) {
        _mergeConstraintsMap(out, sc);
      }
    }

    visitedIds.remove(vo.id);
    return Map<String, Object?>.unmodifiable(out);
  }

  static Map<String, Object?> _attributeMapToSchema(
    Map<String, Object?> attr, {
    required Map<String, ImportedValueObjectSpec> valueObjectsByKey,
    required Set<String> visitedVoIds,
  }) {
    final rawType =
        (attr['type'] as String?)?.trim().toLowerCase() ?? 'string';
    final nullable = attr['nullable'] == true;
    final isArray = attr['isArray'] == true;

    Map<String, Object?> itemSchema;
    if ((rawType == 'vo' ||
            rawType == 'valueobject' ||
            rawType == 'value_object' ||
            rawType == 'value-object') &&
        attr['valueObjectId'] is String &&
        (attr['valueObjectId'] as String).trim().isNotEmpty) {
      final voKey = (attr['valueObjectId'] as String).trim();
      final targetVo =
          valueObjectsByKey[voKey] ?? valueObjectsByKey[voKey.toLowerCase()];
      if (targetVo != null) {
        itemSchema = Map<String, Object?>.of(
          targetVo.jsonSchema.isNotEmpty
              ? targetVo.jsonSchema
              : _synthesizeVoSchemaInternal(
                  targetVo,
                  valueObjectsByKey: valueObjectsByKey,
                  visitedIds: visitedVoIds,
                ),
        );
      } else {
        itemSchema = <String, Object?>{'type': 'string'};
      }
    } else if (rawType == 'object' ||
        rawType == 'subobject' ||
        rawType == 'sub_object' ||
        rawType == 'struct') {
      itemSchema = <String, Object?>{'type': 'object'};
      if (attr['children'] case final List children when children.isNotEmpty) {
        final childProps = <String, Object?>{};
        final childReq = <String>[];
        for (final rawChild in children) {
          if (rawChild is! Map) continue;
          final childMap = freezeJsonMap(rawChild);
          final childName = (childMap['name'] as String?)?.trim() ?? '';
          if (childName.isEmpty) continue;
          childProps[childName] = _attributeMapToSchema(
            childMap,
            valueObjectsByKey: valueObjectsByKey,
            visitedVoIds: visitedVoIds,
          );
          if (childMap['required'] == true) {
            childReq.add(childName);
          }
        }
        if (childProps.isNotEmpty) itemSchema['properties'] = childProps;
        if (childReq.isNotEmpty) itemSchema['required'] = childReq;
      }
    } else if (rawType == 'json' || rawType == 'any') {
      itemSchema = <String, Object?>{};
    } else {
      itemSchema = <String, Object?>{};
      _applyPrimitiveTypeAndFormat(itemSchema, rawType);
    }

    final rawEnums = attr['enumValues'] ?? attr['enum'];
    if (rawEnums is List && rawEnums.isNotEmpty) {
      itemSchema['enum'] = List<Object?>.unmodifiable(rawEnums);
    }
    _mergeConstraintsMap(itemSchema, attr);
    if (attr['schemaConstraints'] case final Map sc) {
      _mergeConstraintsMap(itemSchema, sc);
    }

    if (isArray) {
      final arrSchema = <String, Object?>{
        'type': nullable ? <String>['array', 'null'] : 'array',
        'items': itemSchema,
      };
      if (attr['schemaConstraints'] case final Map sc) {
        for (final key in const <String>[
          'minItems',
          'maxItems',
          'uniqueItems',
        ]) {
          if (sc[key] != null) {
            arrSchema[key] = sc[key];
            itemSchema.remove(key);
          }
        }
      }
      return arrSchema;
    }

    if (nullable && itemSchema['type'] != null) {
      final currentType = itemSchema['type'];
      if (currentType is String && currentType != 'null') {
        itemSchema['type'] = <String>[currentType, 'null'];
      } else if (currentType is List && !currentType.contains('null')) {
        itemSchema['type'] = <Object?>[...currentType, 'null'];
      }
    }
    return itemSchema;
  }

  static void _applyPrimitiveTypeAndFormat(
    Map<String, Object?> target,
    String rawType,
  ) {
    switch (rawType) {
      case 'int':
      case 'integer':
        target['type'] = 'integer';
      case 'number':
      case 'float':
      case 'double':
      case 'decimal':
        target['type'] = 'number';
      case 'bool':
      case 'boolean':
        target['type'] = 'boolean';
      case 'date':
        target['type'] = 'string';
        target['format'] = 'date';
      case 'datetime':
      case 'date-time':
      case 'timestamp':
        target['type'] = 'string';
        target['format'] = 'date-time';
      case 'uuid':
        target['type'] = 'string';
        target['format'] = 'uuid';
      case 'email':
        target['type'] = 'string';
        target['format'] = 'email';
      case 'url':
      case 'uri':
        target['type'] = 'string';
        target['format'] = 'uri';
      case 'ref':
      case 'reference':
      case 'enum':
      case 'enumeration':
      case 'string':
      case 'text':
      case 'str':
      default:
        target['type'] = 'string';
    }
  }

  static void _mergeConstraintsMap(
    Map<String, Object?> target,
    Map<dynamic, dynamic> source,
  ) {
    const directKeys = <String>[
      'minimum',
      'maximum',
      'exclusiveMinimum',
      'exclusiveMaximum',
      'multipleOf',
      'minLength',
      'maxLength',
      'pattern',
      'format',
      'minItems',
      'maxItems',
      'uniqueItems',
      'minProperties',
      'maxProperties',
      'additionalProperties',
      'allOf',
      'anyOf',
      'oneOf',
      'not',
    ];
    for (final key in directKeys) {
      final v = source[key];
      if (v != null && (v is! String || v.isNotEmpty)) {
        target[key] = v;
      }
    }
    if (source['hasConst'] == true) {
      target['const'] = source['constValue'];
    } else if (source.containsKey('const')) {
      target['const'] = source['const'];
    }
  }

  void _validateNode({
    required Object? value,
    required Object? schemaNode,
    required String path,
    required _ValidationContext ctx,
    required List<PayloadValidationViolation> violations,
    required Set<String> activeRefs,
  }) {
    if (schemaNode is bool) {
      if (!schemaNode) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'schema',
            message: 'Aucune valeur n’est autorisée à cet emplacement.',
          ),
        );
      }
      return;
    }
    if (schemaNode is! Map) return;

    final schema = schemaNode;

    // 1. Résolution locale `$ref` (Draft 2020-12 autorise `$ref` avec mots-clés frères).
    final rawRef = schema[r'$ref'];
    if (rawRef is String && rawRef.trim().isNotEmpty) {
      final ref = rawRef.trim();
      final cycleKey = '$path::$ref';
      if (activeRefs.add(cycleKey)) {
        final resolved = _resolveRef(ref, ctx);
        if (resolved == null) {
          violations.add(
            PayloadValidationViolation(
              path: path,
              rule: 'ref',
              message: 'Référence de schéma JSON introuvable : « $ref ».',
            ),
          );
        } else {
          _validateNode(
            value: value,
            schemaNode: resolved,
            path: path,
            ctx: ctx,
            violations: violations,
            activeRefs: activeRefs,
          );
        }
        activeRefs.remove(cycleKey);
      }
    }

    // 2. Composition logique : allOf, anyOf, oneOf, not, if/then/else.
    if (schema['allOf'] case final List allOfList) {
      for (final sub in allOfList) {
        _validateNode(
          value: value,
          schemaNode: sub,
          path: path,
          ctx: ctx,
          violations: violations,
          activeRefs: activeRefs,
        );
      }
    }

    if (schema['anyOf'] case final List anyOfList when anyOfList.isNotEmpty) {
      var matched = false;
      for (final sub in anyOfList) {
        final probe = <PayloadValidationViolation>[];
        _validateNode(
          value: value,
          schemaNode: sub,
          path: path,
          ctx: ctx,
          violations: probe,
          activeRefs: Set<String>.of(activeRefs),
        );
        if (probe.isEmpty) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'anyOf',
            message:
                'La valeur ne correspond à aucune des variantes autorisées (anyOf).',
          ),
        );
      }
    }

    if (schema['oneOf'] case final List oneOfList when oneOfList.isNotEmpty) {
      var matchCount = 0;
      for (final sub in oneOfList) {
        final probe = <PayloadValidationViolation>[];
        _validateNode(
          value: value,
          schemaNode: sub,
          path: path,
          ctx: ctx,
          violations: probe,
          activeRefs: Set<String>.of(activeRefs),
        );
        if (probe.isEmpty) {
          matchCount++;
        }
      }
      if (matchCount != 1) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'oneOf',
            message: matchCount == 0
                ? 'La valeur ne correspond à aucun schéma exclusif (oneOf).'
                : 'La valeur correspond à plusieurs schémas exclusifs ($matchCount correspondances oneOf au lieu de 1).',
          ),
        );
      }
    }

    if (schema.containsKey('not')) {
      final probe = <PayloadValidationViolation>[];
      _validateNode(
        value: value,
        schemaNode: schema['not'],
        path: path,
        ctx: ctx,
        violations: probe,
        activeRefs: Set<String>.of(activeRefs),
      );
      if (probe.isEmpty) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'not',
            message: 'La valeur correspond à un motif explicitement interdit (not).',
          ),
        );
      }
    }

    if (schema.containsKey('if')) {
      final ifProbe = <PayloadValidationViolation>[];
      _validateNode(
        value: value,
        schemaNode: schema['if'],
        path: path,
        ctx: ctx,
        violations: ifProbe,
        activeRefs: Set<String>.of(activeRefs),
      );
      if (ifProbe.isEmpty) {
        if (schema.containsKey('then')) {
          _validateNode(
            value: value,
            schemaNode: schema['then'],
            path: path,
            ctx: ctx,
            violations: violations,
            activeRefs: activeRefs,
          );
        }
      } else if (schema.containsKey('else')) {
        _validateNode(
          value: value,
          schemaNode: schema['else'],
          path: path,
          ctx: ctx,
          violations: violations,
          activeRefs: activeRefs,
        );
      }
    }

    // 3. Vérification de `const` et `enum`.
    if (schema.containsKey('const')) {
      final expectedConst = schema['const'];
      if (!deepJsonEquals(value, expectedConst)) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'const',
            message: 'La valeur doit être strictement égale à « $expectedConst ».',
          ),
        );
      }
    }

    if (schema['enum'] case final List enumValues) {
      final matched = enumValues.any((item) => deepJsonEquals(value, item));
      if (!matched) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'enum',
            message:
                'Valeur non autorisée. Valeurs permises : ${enumValues.join(', ')}.',
          ),
        );
      }
    }

    // 4. Vérification du `type`.
    final rawType = schema['type'];
    if (rawType != null && !_matchesSchemaType(value, rawType)) {
      final expectedDesc = rawType is List ? rawType.join(' | ') : '$rawType';
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'type',
          message:
              'Type JSON invalide : attendu « $expectedDesc », reçu « ${_describeRuntimeJsonType(value)} ».',
        ),
      );
      return;
    }

    // 5. Règles spécifiques au type de la valeur courante.
    if (value is String) {
      _validateString(value, schema, path, violations);
    } else if (value is num && value is! bool) {
      _validateNumber(value, schema, path, violations);
    } else if (value is List) {
      _validateArray(value, schema, path, ctx, violations, activeRefs);
    } else if (value is Map) {
      _validateObject(value, schema, path, ctx, violations, activeRefs);
    }
  }

  Object? _resolveRef(String ref, _ValidationContext ctx) {
    if (ref == '#') return ctx.rootSchema;
    if (ref.startsWith('#/')) {
      final segments = ref.substring(2).split('/');
      Object? cursor = ctx.rootSchema;
      for (final rawSeg in segments) {
        final seg = Uri.decodeComponent(
          rawSeg,
        ).replaceAll('~1', '/').replaceAll('~0', '~');
        if (cursor is Map && cursor.containsKey(seg)) {
          cursor = cursor[seg];
        } else if (cursor == ctx.rootSchema &&
            (seg == r'$defs' || seg == 'definitions')) {
          final alt = seg == r'$defs' ? 'definitions' : r'$defs';
          if (ctx.rootSchema[alt] is Map) {
            cursor = ctx.rootSchema[alt];
          } else {
            cursor = null;
            break;
          }
        } else {
          cursor = null;
          break;
        }
      }
      if (cursor != null) return cursor;

      final lastSegment = Uri.decodeComponent(segments.last);
      final vo =
          ctx.valueObjectsByKey[lastSegment] ??
          ctx.valueObjectsByKey[lastSegment.toLowerCase()];
      if (vo != null) {
        return synthesizeValueObjectSchema(
          vo,
          valueObjectsByKey: ctx.valueObjectsByKey,
        );
      }
    } else {
      final vo =
          ctx.valueObjectsByKey[ref] ?? ctx.valueObjectsByKey[ref.toLowerCase()];
      if (vo != null) {
        return synthesizeValueObjectSchema(
          vo,
          valueObjectsByKey: ctx.valueObjectsByKey,
        );
      }
    }
    return null;
  }

  static bool _matchesSchemaType(Object? value, Object rawType) {
    if (rawType is String) {
      return _matchesSingleType(value, rawType);
    }
    if (rawType is List) {
      return rawType.any(
        (t) => t is String && _matchesSingleType(value, t),
      );
    }
    return true;
  }

  static bool _matchesSingleType(Object? value, String expected) {
    switch (expected) {
      case 'null':
        return value == null;
      case 'boolean':
        return value is bool;
      case 'string':
        return value is String;
      case 'integer':
        if (value is bool) return false;
        if (value is int) return true;
        if (value is double) {
          return value.isFinite && value == value.truncateToDouble();
        }
        return false;
      case 'number':
        if (value is bool) return false;
        return value is num && value.isFinite;
      case 'array':
        return value is List;
      case 'object':
        return value is Map;
      default:
        return true;
    }
  }

  static String _describeRuntimeJsonType(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return 'boolean';
    if (value is int) return 'integer';
    if (value is num) return 'number';
    if (value is String) return 'string';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    return value.runtimeType.toString();
  }

  static void _validateString(
    String value,
    Map<dynamic, dynamic> schema,
    String path,
    List<PayloadValidationViolation> violations,
  ) {
    final runeLength = value.runes.length;
    final minLen = _asInt(schema['minLength']);
    if (minLen != null && runeLength < minLen) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'minLength',
          message:
              'La chaîne doit contenir au moins $minLen caractère(s) (reçu : $runeLength).',
        ),
      );
    }

    final maxLen = _asInt(schema['maxLength']);
    if (maxLen != null && runeLength > maxLen) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'maxLength',
          message:
              'La chaîne ne doit pas dépasser $maxLen caractère(s) (reçu : $runeLength).',
        ),
      );
    }

    final pattern = schema['pattern'];
    if (pattern is String && pattern.isNotEmpty) {
      try {
        if (!RegExp(pattern).hasMatch(value)) {
          violations.add(
            PayloadValidationViolation(
              path: path,
              rule: 'pattern',
              message:
                  'La chaîne ne respecte pas l’expression régulière attendue « $pattern ».',
            ),
          );
        }
      } on FormatException {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'pattern',
            message: 'Expression régulière de schéma invalide : « $pattern ».',
          ),
        );
      }
    }

    final format = (schema['format'] as String?)?.trim().toLowerCase();
    if (format != null && format.isNotEmpty) {
      if (!_isValidFormat(value, format)) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'format',
            message:
                'La valeur « $value » ne respecte pas le format attendu « $format ».',
          ),
        );
      }
    }
  }

  static bool _isValidFormat(String value, String format) {
    switch (format) {
      case 'email':
      case 'idn-email':
        return _emailRegex.hasMatch(value) && !value.contains('..');
      case 'uuid':
        return _uuidRegex.hasMatch(value);
      case 'date':
        final match = _isoDateRegex.firstMatch(value);
        if (match == null) return false;
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        return _isValidCalendarDate(year, month, day);
      case 'date-time':
        final match = _isoDateTimeRegex.firstMatch(value);
        if (match == null) return false;
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);
        final second = int.parse(match.group(6)!);
        if (!_isValidCalendarDate(year, month, day)) return false;
        if (hour > 23 || minute > 59 || second > 59) return false;
        return DateTime.tryParse(value) != null;
      case 'uri':
      case 'url':
        if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return false;
        final uri = Uri.tryParse(value);
        return uri != null &&
            uri.hasScheme &&
            uri.scheme.isNotEmpty &&
            (uri.hasAuthority || uri.path.isNotEmpty);
      default:
        return true;
    }
  }

  static bool _isValidCalendarDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1) return false;
    const monthDays = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var maxDay = monthDays[month - 1];
    final isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    if (month == 2 && isLeap) maxDay = 29;
    return day <= maxDay;
  }

  static void _validateNumber(
    num value,
    Map<dynamic, dynamic> schema,
    String path,
    List<PayloadValidationViolation> violations,
  ) {
    final min = _asNum(schema['minimum']);
    final exMinRaw = schema['exclusiveMinimum'];
    if (min != null) {
      if (exMinRaw == true) {
        if (value <= min) {
          violations.add(
            PayloadValidationViolation(
              path: path,
              rule: 'exclusiveMinimum',
              message: 'La valeur doit être strictement supérieure à $min.',
            ),
          );
        }
      } else if (value < min) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'minimum',
            message: 'La valeur doit être supérieure ou égale à $min (reçu : $value).',
          ),
        );
      }
    }

    final exMin = _asNum(exMinRaw);
    if (exMin != null && value <= exMin) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'exclusiveMinimum',
          message:
              'La valeur doit être strictement supérieure à $exMin (reçu : $value).',
        ),
      );
    }

    final max = _asNum(schema['maximum']);
    final exMaxRaw = schema['exclusiveMaximum'];
    if (max != null) {
      if (exMaxRaw == true) {
        if (value >= max) {
          violations.add(
            PayloadValidationViolation(
              path: path,
              rule: 'exclusiveMaximum',
              message: 'La valeur doit être strictement inférieure à $max.',
            ),
          );
        }
      } else if (value > max) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'maximum',
            message: 'La valeur doit être inférieure ou égale à $max (reçu : $value).',
          ),
        );
      }
    }

    final exMax = _asNum(exMaxRaw);
    if (exMax != null && value >= exMax) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'exclusiveMaximum',
          message:
              'La valeur doit être strictement inférieure à $exMax (reçu : $value).',
        ),
      );
    }

    final multipleOf = _asNum(schema['multipleOf']);
    if (multipleOf != null && multipleOf > 0) {
      final bool isMultiple;
      if (value is int && multipleOf is int) {
        isMultiple = value % multipleOf == 0;
      } else {
        final quotient = value / multipleOf;
        isMultiple = (quotient - quotient.roundToDouble()).abs() <= 1e-9;
      }
      if (!isMultiple) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'multipleOf',
            message: 'La valeur ($value) doit être un multiple de $multipleOf.',
          ),
        );
      }
    }
  }

  void _validateArray(
    List<dynamic> value,
    Map<dynamic, dynamic> schema,
    String path,
    _ValidationContext ctx,
    List<PayloadValidationViolation> violations,
    Set<String> activeRefs,
  ) {
    final minItems = _asInt(schema['minItems']);
    if (minItems != null && value.length < minItems) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'minItems',
          message:
              'Le tableau doit contenir au moins $minItems élément(s) (reçu : ${value.length}).',
        ),
      );
    }

    final maxItems = _asInt(schema['maxItems']);
    if (maxItems != null && value.length > maxItems) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'maxItems',
          message:
              'Le tableau ne doit pas dépasser $maxItems élément(s) (reçu : ${value.length}).',
        ),
      );
    }

    if (schema['uniqueItems'] == true && value.length > 1) {
      var hasDuplicate = false;
      for (var i = 0; i < value.length && !hasDuplicate; i++) {
        for (var j = i + 1; j < value.length; j++) {
          if (deepJsonEquals(value[i], value[j])) {
            hasDuplicate = true;
            break;
          }
        }
      }
      if (hasDuplicate) {
        violations.add(
          PayloadValidationViolation(
            path: path,
            rule: 'uniqueItems',
            message: 'Tous les éléments du tableau doivent être uniques.',
          ),
        );
      }
    }

    var startItemsIndex = 0;
    if (schema['prefixItems'] case final List prefixList) {
      final limit = prefixList.length < value.length
          ? prefixList.length
          : value.length;
      for (var i = 0; i < limit; i++) {
        _validateNode(
          value: value[i],
          schemaNode: prefixList[i],
          path: '$path[$i]',
          ctx: ctx,
          violations: violations,
          activeRefs: activeRefs,
        );
      }
      startItemsIndex = prefixList.length;
    }

    if (schema.containsKey('items')) {
      final itemsSchema = schema['items'];
      for (var i = startItemsIndex; i < value.length; i++) {
        _validateNode(
          value: value[i],
          schemaNode: itemsSchema,
          path: '$path[$i]',
          ctx: ctx,
          violations: violations,
          activeRefs: activeRefs,
        );
      }
    }
  }

  void _validateObject(
    Map<dynamic, dynamic> rawMap,
    Map<dynamic, dynamic> schema,
    String path,
    _ValidationContext ctx,
    List<PayloadValidationViolation> violations,
    Set<String> activeRefs,
  ) {
    final map = <String, Object?>{
      for (final e in rawMap.entries) '${e.key}': e.value,
    };
    final isRoot = path == ctx.rootPath;

    final minProps = _asInt(schema['minProperties']);
    if (minProps != null && map.length < minProps) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'minProperties',
          message:
              'L’objet doit contenir au moins $minProps propriété(s) (reçu : ${map.length}).',
        ),
      );
    }

    final maxProps = _asInt(schema['maxProperties']);
    if (maxProps != null && map.length > maxProps) {
      violations.add(
        PayloadValidationViolation(
          path: path,
          rule: 'maxProperties',
          message:
              'L’objet ne doit pas dépasser $maxProps propriété(s) (reçu : ${map.length}).',
        ),
      );
    }

    final requiredSet = <String>{};
    if (schema['required'] case final List reqList) {
      for (final item in reqList) {
        if (item is String && item.isNotEmpty) {
          requiredSet.add(item);
        }
      }
    }

    if (!(ctx.partialUpdate && isRoot)) {
      for (final reqKey in requiredSet) {
        if (!map.containsKey(reqKey)) {
          violations.add(
            PayloadValidationViolation(
              path: '$path.$reqKey',
              rule: 'required',
              message: 'Le champ obligatoire « $reqKey » est manquant.',
            ),
          );
        }
      }
    }

    final properties = schema['properties'] is Map
        ? schema['properties'] as Map
        : const <dynamic, dynamic>{};
    final patternProps = schema['patternProperties'] is Map
        ? schema['patternProperties'] as Map
        : const <dynamic, dynamic>{};

    final matchedPatternKeys = <String>{};
    if (patternProps.isNotEmpty) {
      for (final patternEntry in patternProps.entries) {
        final regexStr = '${patternEntry.key}';
        RegExp? regex;
        try {
          regex = RegExp(regexStr);
        } on FormatException {
          regex = null;
        }
        if (regex == null) continue;
        for (final key in map.keys) {
          if (regex.hasMatch(key)) {
            matchedPatternKeys.add(key);
            _validateNode(
              value: map[key],
              schemaNode: patternEntry.value,
              path: '$path.$key',
              ctx: ctx,
              violations: violations,
              activeRefs: activeRefs,
            );
          }
        }
      }
    }

    for (final entry in map.entries) {
      final key = entry.key;
      final propVal = entry.value;
      final isAllowedSystemKey =
          ctx.allowSystemFields && ctx.systemFields.contains(key);

      if (properties.containsKey(key)) {
        if (isAllowedSystemKey &&
            propVal == null &&
            !requiredSet.contains(key)) {
          continue;
        }
        _validateNode(
          value: propVal,
          schemaNode: properties[key],
          path: '$path.$key',
          ctx: ctx,
          violations: violations,
          activeRefs: activeRefs,
        );
      } else if (!matchedPatternKeys.contains(key)) {
        if (isAllowedSystemKey) {
          continue;
        }
        final addProps = schema['additionalProperties'];
        if (addProps == false) {
          violations.add(
            PayloadValidationViolation(
              path: '$path.$key',
              rule: 'additionalProperties',
              message: 'La propriété non déclarée « $key » n’est pas autorisée.',
            ),
          );
        } else if (addProps is Map) {
          _validateNode(
            value: propVal,
            schemaNode: addProps,
            path: '$path.$key',
            ctx: ctx,
            violations: violations,
            activeRefs: activeRefs,
          );
        }
      }
    }
  }

  static int? _asInt(Object? raw) => switch (raw) {
    int i => i,
    double d when d.isFinite && d == d.truncateToDouble() => d.toInt(),
    _ => null,
  };

  static num? _asNum(Object? raw) => switch (raw) {
    int i => i,
    double d when d.isFinite => d,
    _ => null,
  };
}

class _ValidationContext {
  const _ValidationContext({
    required this.rootSchema,
    required this.rootPath,
    required this.partialUpdate,
    required this.allowSystemFields,
    required this.systemFields,
    required this.valueObjectsByKey,
  });

  final Map<String, Object?> rootSchema;
  final String rootPath;
  final bool partialUpdate;
  final bool allowSystemFields;
  final Set<String> systemFields;
  final Map<String, ImportedValueObjectSpec> valueObjectsByKey;
}
