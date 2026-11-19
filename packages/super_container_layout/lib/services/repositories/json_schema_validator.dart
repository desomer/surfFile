/// Validateur JSON Schema standard (Draft 7 / Draft 2020-12) en Dart pur
/// pour la validation stricte des documents de repositories
/// ([JsonSchemaValidator]).
library;

import 'dart:convert';

import '../../models/repository_json_schema.dart';
import '../../models/text_field_constraints.dart';

/// Validateur et inspecteur JSON Schema (Draft 7 / Draft 2020-12) sans
/// dépendance externe.
abstract final class JsonSchemaValidator {
  static const Set<String> _validTypes = <String>{
    'object',
    'array',
    'string',
    'integer',
    'number',
    'boolean',
    'null',
  };

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _emailPattern = RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  );
  static final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final RegExp _timePattern = RegExp(
    r'^(\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})?$',
    caseSensitive: false,
  );
  static final RegExp _dateTimePattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})$',
  );
  static final RegExp _ipv4Pattern = RegExp(
    r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$',
  );
  static final RegExp _hostnamePattern = RegExp(
    r'^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
  );

  /// Vérifie qu'un objet JSON représente une définition JSON Schema valide.
  ///
  /// Retourne le schéma normalisé et immuable (clés `String`), ou lève une
  /// [FormatException] si un mot-clé structurel, une expression régulière ou
  /// une référence `$ref` locale est invalide.
  static Map<String, Object?> validateSchemaDefinition(Object? rawSchema) {
    if (rawSchema is! Map) {
      throw const FormatException(
        'Le JSON Schema racine doit être un objet JSON {...}.',
      );
    }
    final normalized = RepositoryJsonSchemaDocument.deepCloneSchemaMap(
      rawSchema,
    );
    _validateSubschemaNode(
      normalized,
      rootSchema: normalized,
      schemaPath: '#',
      allowBool: false,
    );
    return normalized;
  }

  /// Décode [rawText] en JSON et valide qu'il s'agit d'un JSON Schema valide.
  static Map<String, Object?> parseSchemaText(String rawText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawText);
    } on FormatException {
      throw const FormatException('JSON Schema invalide : syntaxe JSON incorrecte.');
    }
    return validateSchemaDefinition(decoded);
  }

  /// Valide [document] contre [schema] et retourne un [JsonSchemaValidationResult].
  ///
  /// Si [schema] est structurellement invalide, lève une [FormatException].
  static JsonSchemaValidationResult validate(
    Object? document,
    Map<String, Object?> schema,
  ) {
    final rootSchema = validateSchemaDefinition(schema);
    final issues = <JsonSchemaValidationIssue>[];
    _validateInstance(
      value: document,
      schemaNode: rootSchema,
      rootSchema: rootSchema,
      instancePath: '',
      schemaPath: '#',
      issues: issues,
      activeRefs: <String>{},
    );
    return issues.isEmpty
        ? JsonSchemaValidationResult.valid
        : JsonSchemaValidationResult(issues: issues);
  }

  /// Valide [document] contre [schema] et lève une
  /// [JsonSchemaValidationException] si le document n'est pas conforme.
  static void assertValid({
    required String repositoryId,
    required Object? document,
    required Map<String, Object?> schema,
  }) {
    final result = validate(document, schema);
    if (!result.isValid) {
      throw JsonSchemaValidationException(
        repositoryId: repositoryId,
        issues: result.issues,
      );
    }
  }

  /// Infère un JSON Schema initial à partir d'un document JSON existant.
  static Map<String, Object?> inferSchema(
    Object? document, {
    String? title,
    bool markPresentKeysRequired = false,
  }) {
    final inferred = _inferNode(
      document,
      markPresentKeysRequired: markPresentKeysRequired,
    );
    return <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      ...inferred,
    };
  }

  static Map<String, Object?> _inferNode(
    Object? value, {
    required bool markPresentKeysRequired,
  }) {
    if (value == null) {
      return <String, Object?>{'type': 'null'};
    }
    if (value is bool) {
      return <String, Object?>{'type': 'boolean'};
    }
    if (value is int) {
      return <String, Object?>{'type': 'integer'};
    }
    if (value is num) {
      return <String, Object?>{'type': 'number'};
    }
    if (value is String) {
      if (_uuidPattern.hasMatch(value)) {
        return <String, Object?>{'type': 'string', 'format': 'uuid'};
      }
      if (_dateTimePattern.hasMatch(value)) {
        return <String, Object?>{'type': 'string', 'format': 'date-time'};
      }
      if (_datePattern.hasMatch(value)) {
        return <String, Object?>{'type': 'string', 'format': 'date'};
      }
      if (_emailPattern.hasMatch(value)) {
        return <String, Object?>{'type': 'string', 'format': 'email'};
      }
      return <String, Object?>{'type': 'string'};
    }
    if (value is List) {
      if (value.isEmpty) {
        return <String, Object?>{'type': 'array'};
      }
      var mergedItem = _inferNode(
        value.first,
        markPresentKeysRequired: markPresentKeysRequired,
      );
      for (var i = 1; i < value.length; i++) {
        mergedItem = _mergeInferredSchemas(
          mergedItem,
          _inferNode(
            value[i],
            markPresentKeysRequired: markPresentKeysRequired,
          ),
        );
      }
      return <String, Object?>{'type': 'array', 'items': mergedItem};
    }
    if (value is Map) {
      final props = <String, Object?>{};
      final requiredKeys = <String>[];
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (key.startsWith('@')) continue;
        props[key] = _inferNode(
          entry.value,
          markPresentKeysRequired: markPresentKeysRequired,
        );
        if (markPresentKeysRequired) {
          requiredKeys.add(key);
        }
      }
      return <String, Object?>{
        'type': 'object',
        'properties': props,
        if (requiredKeys.isNotEmpty) 'required': requiredKeys,
        'additionalProperties': true,
      };
    }
    return <String, Object?>{};
  }

  static Map<String, Object?> _mergeInferredSchemas(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    if (a['type'] == 'object' && b['type'] == 'object') {
      final propsA = a['properties'] as Map<String, Object?>? ?? const {};
      final propsB = b['properties'] as Map<String, Object?>? ?? const {};
      final mergedProps = <String, Object?>{};
      final allKeys = <String>{...propsA.keys, ...propsB.keys};
      for (final key in allKeys) {
        final inA = propsA[key] as Map<String, Object?>?;
        final inB = propsB[key] as Map<String, Object?>?;
        if (inA != null && inB != null) {
          mergedProps[key] = _mergeInferredSchemas(inA, inB);
        } else {
          mergedProps[key] = inA ?? inB ?? const <String, Object?>{};
        }
      }
      final reqA = (a['required'] as List?)?.cast<String>().toSet();
      final reqB = (b['required'] as List?)?.cast<String>().toSet();
      final mergedReq = (reqA != null && reqB != null)
          ? reqA.intersection(reqB).toList()
          : const <String>[];
      return <String, Object?>{
        'type': 'object',
        'properties': mergedProps,
        if (mergedReq.isNotEmpty) 'required': mergedReq,
        'additionalProperties': true,
      };
    }
    if (a['type'] == b['type']) {
      if (a['format'] == b['format']) return a;
      return <String, Object?>{if (a['type'] != null) 'type': a['type']};
    }
    if ((a['type'] == 'integer' && b['type'] == 'number') ||
        (a['type'] == 'number' && b['type'] == 'integer')) {
      return <String, Object?>{'type': 'number'};
    }
    final types = <String>{
      if (a['type'] is String) a['type'] as String,
      if (a['type'] is List) ...(a['type'] as List).cast<String>(),
      if (b['type'] is String) b['type'] as String,
      if (b['type'] is List) ...(b['type'] as List).cast<String>(),
    };
    if (types.length > 1) {
      return <String, Object?>{'type': types.toList()};
    }
    return const <String, Object?>{};
  }

  static void _validateSubschemaNode(
    Object? node, {
    required Map<String, Object?> rootSchema,
    required String schemaPath,
    bool allowBool = true,
  }) {
    if (node is bool) {
      if (!allowBool) {
        throw FormatException(
          'Un sous-schéma booléen n’est pas autorisé à « $schemaPath ».',
        );
      }
      return;
    }
    if (node is! Map) {
      throw FormatException(
        'Sous-schéma invalide à « $schemaPath » : objet JSON ou booléen attendu.',
      );
    }

    if (node.containsKey('type')) {
      final rawType = node['type'];
      if (rawType is String) {
        if (!_validTypes.contains(rawType)) {
          throw FormatException(
            'Type JSON Schema inconnu « $rawType » à « $schemaPath/type ».',
          );
        }
      } else if (rawType is List) {
        if (rawType.isEmpty) {
          throw FormatException(
            'La liste de types à « $schemaPath/type » ne peut pas être vide.',
          );
        }
        final seen = <String>{};
        for (final t in rawType) {
          if (t is! String || !_validTypes.contains(t)) {
            throw FormatException(
              'Type JSON Schema invalide « $t » à « $schemaPath/type ».',
            );
          }
          if (!seen.add(t)) {
            throw FormatException(
              'Type dupliqué « $t » à « $schemaPath/type ».',
            );
          }
        }
      } else {
        throw FormatException(
          'Mot-clé "type" invalide à « $schemaPath/type ».',
        );
      }
    }

    if (node.containsKey('enum')) {
      final rawEnum = node['enum'];
      if (rawEnum is! List || rawEnum.isEmpty) {
        throw FormatException(
          'Mot-clé "enum" invalide à « $schemaPath/enum » : tableau non vide attendu.',
        );
      }
    }

    if (node.containsKey('required')) {
      final req = node['required'];
      if (req is! List || req.any((e) => e is! String)) {
        throw FormatException(
          'Mot-clé "required" invalide à « $schemaPath/required » : liste de chaînes attendue.',
        );
      }
      final seen = <String>{};
      for (final item in req.cast<String>()) {
        if (!seen.add(item)) {
          throw FormatException(
            'Clé requise dupliquée « $item » à « $schemaPath/required ».',
          );
        }
      }
    }

    for (final key in const [
      'minProperties',
      'maxProperties',
      'minItems',
      'maxItems',
      'minLength',
      'maxLength',
    ]) {
      if (node.containsKey(key)) {
        final v = node[key];
        if (v is! int || v < 0) {
          throw FormatException(
            'Mot-clé "$key" invalide à « $schemaPath/$key » : entier >= 0 attendu.',
          );
        }
      }
    }

    for (final key in const ['minimum', 'maximum']) {
      if (node.containsKey(key)) {
        final v = node[key];
        if (v is! num || !v.isFinite) {
          throw FormatException(
            'Mot-clé "$key" invalide à « $schemaPath/$key » : nombre fini attendu.',
          );
        }
      }
    }

    for (final key in const ['exclusiveMinimum', 'exclusiveMaximum']) {
      if (node.containsKey(key)) {
        final v = node[key];
        if (v is! bool && (v is! num || !v.isFinite)) {
          throw FormatException(
            'Mot-clé "$key" invalide à « $schemaPath/$key » : nombre ou booléen attendu.',
          );
        }
      }
    }

    if (node.containsKey('multipleOf')) {
      final v = node['multipleOf'];
      if (v is! num || !v.isFinite || v <= 0) {
        throw FormatException(
          'Mot-clé "multipleOf" invalide à « $schemaPath/multipleOf » : nombre > 0 attendu.',
        );
      }
    }

    if (node.containsKey('uniqueItems') && node['uniqueItems'] is! bool) {
      throw FormatException(
        'Mot-clé "uniqueItems" invalide à « $schemaPath/uniqueItems » : booléen attendu.',
      );
    }

    if (node.containsKey('pattern')) {
      final pattern = node['pattern'];
      if (pattern is! String) {
        throw FormatException(
          'Mot-clé "pattern" invalide à « $schemaPath/pattern » : chaîne attendue.',
        );
      }
      try {
        RegExp(pattern);
      } on FormatException catch (e) {
        throw FormatException(
          'Expression régulière invalide à « $schemaPath/pattern » : ${e.message}',
        );
      }
    }

    if (node.containsKey('format') && node['format'] is! String) {
      throw FormatException(
        'Mot-clé "format" invalide à « $schemaPath/format » : chaîne attendue.',
      );
    }

    if (node.containsKey('x-mask')) {
      final rawMask = node['x-mask'];
      if (rawMask is! String) {
        throw FormatException(
          'Mot-clé "x-mask" invalide à « $schemaPath/x-mask » : chaîne attendue.',
        );
      }
      try {
        PatternMask.validatePattern(rawMask);
      } on FormatException catch (e) {
        throw FormatException(
          'Masque "x-mask" invalide à « $schemaPath/x-mask » : ${e.message}',
        );
      }
    }

    if (node.containsKey('x-dateFormat')) {
      final rawDateFormat = node['x-dateFormat'];
      if (rawDateFormat is! String) {
        throw FormatException(
          'Mot-clé "x-dateFormat" invalide à « $schemaPath/x-dateFormat » : chaîne attendue.',
        );
      }
      try {
        DateFieldFormat.validatePattern(rawDateFormat);
      } on FormatException catch (e) {
        throw FormatException(
          'Format "x-dateFormat" invalide à « $schemaPath/x-dateFormat » : ${e.message}',
        );
      }
    }

    for (final mapKey in const [
      'properties',
      'patternProperties',
      r'$defs',
      'definitions',
    ]) {
      if (node.containsKey(mapKey)) {
        final map = node[mapKey];
        if (map is! Map) {
          throw FormatException(
            'Mot-clé "$mapKey" invalide à « $schemaPath/$mapKey » : objet attendu.',
          );
        }
        for (final entry in map.entries) {
          final k = entry.key.toString();
          if (mapKey == 'patternProperties') {
            try {
              RegExp(k);
            } on FormatException catch (e) {
              throw FormatException(
                'Regex invalide "$k" à « $schemaPath/patternProperties » : ${e.message}',
              );
            }
          }
          _validateSubschemaNode(
            entry.value,
            rootSchema: rootSchema,
            schemaPath: '$schemaPath/$mapKey/${_escapePointer(k)}',
          );
        }
      }
    }

    for (final subKey in const [
      'additionalProperties',
      'additionalItems',
      'contains',
      'not',
      'if',
      'then',
      'else',
      'propertyNames',
    ]) {
      if (node.containsKey(subKey)) {
        _validateSubschemaNode(
          node[subKey],
          rootSchema: rootSchema,
          schemaPath: '$schemaPath/$subKey',
        );
      }
    }

    if (node.containsKey('items')) {
      final items = node['items'];
      if (items is List) {
        for (var i = 0; i < items.length; i++) {
          _validateSubschemaNode(
            items[i],
            rootSchema: rootSchema,
            schemaPath: '$schemaPath/items/$i',
          );
        }
      } else {
        _validateSubschemaNode(
          items,
          rootSchema: rootSchema,
          schemaPath: '$schemaPath/items',
        );
      }
    }

    for (final listKey in const ['prefixItems', 'allOf', 'anyOf', 'oneOf']) {
      if (node.containsKey(listKey)) {
        final list = node[listKey];
        if (list is! List || list.isEmpty) {
          throw FormatException(
            'Mot-clé "$listKey" invalide à « $schemaPath/$listKey » : tableau non vide attendu.',
          );
        }
        for (var i = 0; i < list.length; i++) {
          _validateSubschemaNode(
            list[i],
            rootSchema: rootSchema,
            schemaPath: '$schemaPath/$listKey/$i',
          );
        }
      }
    }

    if (node.containsKey('dependentRequired')) {
      final depReq = node['dependentRequired'];
      if (depReq is! Map) {
        throw FormatException(
          'Mot-clé "dependentRequired" invalide à « $schemaPath/dependentRequired ».',
        );
      }
      for (final entry in depReq.entries) {
        if (entry.value is! List ||
            (entry.value as List).any((e) => e is! String)) {
          throw FormatException(
            'Entrée invalide pour "${entry.key}" à « $schemaPath/dependentRequired ».',
          );
        }
      }
    }

    if (node.containsKey('dependencies')) {
      final deps = node['dependencies'];
      if (deps is! Map) {
        throw FormatException(
          'Mot-clé "dependencies" invalide à « $schemaPath/dependencies ».',
        );
      }
      for (final entry in deps.entries) {
        final v = entry.value;
        if (v is List) {
          if (v.any((e) => e is! String)) {
            throw FormatException(
              'Dépendance invalide pour "${entry.key}" à « $schemaPath/dependencies ».',
            );
          }
        } else {
          _validateSubschemaNode(
            v,
            rootSchema: rootSchema,
            schemaPath: '$schemaPath/dependencies/${_escapePointer(entry.key.toString())}',
          );
        }
      }
    }

    if (node.containsKey(r'$ref')) {
      final ref = node[r'$ref'];
      if (ref is! String || ref.isEmpty) {
        throw FormatException(
          'Référence "\$ref" invalide à « $schemaPath/\$ref ».',
        );
      }
      if (!ref.startsWith('#')) {
        throw FormatException(
          'Seules les références locales "#..." sont supportées ("$ref" à « $schemaPath/\$ref »).',
        );
      }
      if (_resolveLocalRef(rootSchema, ref) == _unresolvedRef) {
        throw FormatException(
          'Référence locale "\$ref" introuvable : "$ref" à « $schemaPath/\$ref ».',
        );
      }
    }
  }

  static const Object _unresolvedRef = Object();

  static Object? _resolveLocalRef(
    Map<String, Object?> rootSchema,
    String ref,
  ) {
    if (ref == '#') return rootSchema;
    if (!ref.startsWith('#/')) return _unresolvedRef;
    final segments = ref.substring(2).split('/').map(_unescapePointer);
    Object? current = rootSchema;
    for (final segment in segments) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else if (current is List) {
        final idx = int.tryParse(segment);
        if (idx == null || idx < 0 || idx >= current.length) {
          return _unresolvedRef;
        }
        current = current[idx];
      } else {
        return _unresolvedRef;
      }
    }
    if (current is! Map && current is! bool) return _unresolvedRef;
    return current;
  }

  static String _escapePointer(String token) =>
      token.replaceAll('~', '~0').replaceAll('/', '~1');

  static String _unescapePointer(String token) =>
      token.replaceAll('~1', '/').replaceAll('~0', '~');

  static void _validateInstance({
    required Object? value,
    required Object? schemaNode,
    required Map<String, Object?> rootSchema,
    required String instancePath,
    required String schemaPath,
    required List<JsonSchemaValidationIssue> issues,
    required Set<String> activeRefs,
  }) {
    if (schemaNode is bool) {
      if (!schemaNode) {
        issues.add(
          JsonSchemaValidationIssue(
            instancePath: instancePath,
            schemaPath: schemaPath,
            keyword: 'false',
            message: 'Valeur interdite par le schéma.',
          ),
        );
      }
      return;
    }
    if (schemaNode is! Map) return;

    // Résolution de $ref (en Draft 2020-12, $ref peut coexister avec d'autres mots-clés).
    if (schemaNode.containsKey(r'$ref')) {
      final ref = schemaNode[r'$ref'] as String;
      final guardKey = '$instancePath@@$ref';
      if (activeRefs.add(guardKey)) {
        try {
          final target = _resolveLocalRef(rootSchema, ref);
          if (target != _unresolvedRef) {
            _validateInstance(
              value: value,
              schemaNode: target,
              rootSchema: rootSchema,
              instancePath: instancePath,
              schemaPath: ref,
              issues: issues,
              activeRefs: activeRefs,
            );
          }
        } finally {
          activeRefs.remove(guardKey);
        }
      }
    }

    // Type
    if (schemaNode.containsKey('type')) {
      final rawType = schemaNode['type'];
      final allowedTypes = rawType is String
          ? <String>[rawType]
          : (rawType as List).cast<String>();
      if (!allowedTypes.any((t) => _matchesType(value, t))) {
        issues.add(
          JsonSchemaValidationIssue(
            instancePath: instancePath,
            schemaPath: '$schemaPath/type',
            keyword: 'type',
            message:
                'Type attendu : ${allowedTypes.join(' | ')}, reçu : ${_describeType(value)}.',
          ),
        );
      }
    }

    // const
    if (schemaNode.containsKey('const')) {
      final expected = schemaNode['const'];
      if (!_deepEquals(value, expected)) {
        issues.add(
          JsonSchemaValidationIssue(
            instancePath: instancePath,
            schemaPath: '$schemaPath/const',
            keyword: 'const',
            message: 'Valeur attendue : ${jsonEncode(expected)}.',
          ),
        );
      }
    }

    // enum
    if (schemaNode.containsKey('enum')) {
      final allowed = schemaNode['enum'] as List;
      if (!allowed.any((candidate) => _deepEquals(value, candidate))) {
        issues.add(
          JsonSchemaValidationIssue(
            instancePath: instancePath,
            schemaPath: '$schemaPath/enum',
            keyword: 'enum',
            message:
                'Valeur non autorisée (${jsonEncode(value)}) ; valeurs acceptées : ${allowed.map(jsonEncode).join(', ')}.',
          ),
        );
      }
    }

    // Contraintes sur les chaînes
    if (value is String) {
      final runeCount = value.runes.length;
      if (schemaNode.containsKey('minLength')) {
        final minLength = schemaNode['minLength'] as int;
        if (runeCount < minLength) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/minLength',
              keyword: 'minLength',
              message:
                  'Longueur minimale requise : $minLength caractère(s) (actuel : $runeCount).',
            ),
          );
        }
      }
      if (schemaNode.containsKey('maxLength')) {
        final maxLength = schemaNode['maxLength'] as int;
        if (runeCount > maxLength) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/maxLength',
              keyword: 'maxLength',
              message:
                  'Longueur maximale autorisée : $maxLength caractère(s) (actuel : $runeCount).',
            ),
          );
        }
      }
      if (schemaNode.containsKey('pattern')) {
        final pattern = schemaNode['pattern'] as String;
        if (!RegExp(pattern).hasMatch(value)) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/pattern',
              keyword: 'pattern',
              message: 'Ne correspond pas au motif « $pattern ».',
            ),
          );
        }
      }
      if (schemaNode.containsKey('format')) {
        final format = schemaNode['format'] as String;
        final formatError = _validateFormat(value, format);
        if (formatError != null) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/format',
              keyword: 'format',
              message: formatError,
            ),
          );
        }
      }
    }

    // Contraintes numériques
    if (value is num) {
      if (schemaNode.containsKey('minimum')) {
        final min = schemaNode['minimum'] as num;
        final exclusive = schemaNode['exclusiveMinimum'] == true;
        if (exclusive ? value <= min : value < min) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/minimum',
              keyword: exclusive ? 'exclusiveMinimum' : 'minimum',
              message: exclusive
                  ? 'Doit être strictement supérieur à $min.'
                  : 'Doit être supérieur ou égal à $min.',
            ),
          );
        }
      }
      if (schemaNode['exclusiveMinimum'] is num) {
        final exMin = schemaNode['exclusiveMinimum'] as num;
        if (value <= exMin) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/exclusiveMinimum',
              keyword: 'exclusiveMinimum',
              message: 'Doit être strictement supérieur à $exMin.',
            ),
          );
        }
      }
      if (schemaNode.containsKey('maximum')) {
        final max = schemaNode['maximum'] as num;
        final exclusive = schemaNode['exclusiveMaximum'] == true;
        if (exclusive ? value >= max : value > max) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/maximum',
              keyword: exclusive ? 'exclusiveMaximum' : 'maximum',
              message: exclusive
                  ? 'Doit être strictement inférieur à $max.'
                  : 'Doit être inférieur ou égal à $max.',
            ),
          );
        }
      }
      if (schemaNode['exclusiveMaximum'] is num) {
        final exMax = schemaNode['exclusiveMaximum'] as num;
        if (value >= exMax) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/exclusiveMaximum',
              keyword: 'exclusiveMaximum',
              message: 'Doit être strictement inférieur à $exMax.',
            ),
          );
        }
      }
      if (schemaNode.containsKey('multipleOf')) {
        final divisor = schemaNode['multipleOf'] as num;
        if (!_isMultipleOf(value, divisor)) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/multipleOf',
              keyword: 'multipleOf',
              message: 'Doit être un multiple de $divisor.',
            ),
          );
        }
      }
    }

    // Contraintes sur les tableaux
    if (value is List) {
      if (schemaNode.containsKey('minItems')) {
        final minItems = schemaNode['minItems'] as int;
        if (value.length < minItems) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/minItems',
              keyword: 'minItems',
              message:
                  'Nombre minimal d’éléments : $minItems (actuel : ${value.length}).',
            ),
          );
        }
      }
      if (schemaNode.containsKey('maxItems')) {
        final maxItems = schemaNode['maxItems'] as int;
        if (value.length > maxItems) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/maxItems',
              keyword: 'maxItems',
              message:
                  'Nombre maximal d’éléments : $maxItems (actuel : ${value.length}).',
            ),
          );
        }
      }
      if (schemaNode['uniqueItems'] == true) {
        var duplicateFound = false;
        for (var i = 0; i < value.length && !duplicateFound; i++) {
          for (var j = i + 1; j < value.length; j++) {
            if (_deepEquals(value[i], value[j])) {
              duplicateFound = true;
              issues.add(
                JsonSchemaValidationIssue(
                  instancePath: '$instancePath[$j]',
                  schemaPath: '$schemaPath/uniqueItems',
                  keyword: 'uniqueItems',
                  message:
                      'Les éléments du tableau doivent être uniques (doublon avec l’indice $i).',
                ),
              );
              break;
            }
          }
        }
      }

      var tupleCount = 0;
      if (schemaNode.containsKey('prefixItems')) {
        final prefixItems = schemaNode['prefixItems'] as List;
        tupleCount = prefixItems.length;
        for (var i = 0; i < prefixItems.length && i < value.length; i++) {
          _validateInstance(
            value: value[i],
            schemaNode: prefixItems[i],
            rootSchema: rootSchema,
            instancePath: '$instancePath[$i]',
            schemaPath: '$schemaPath/prefixItems/$i',
            issues: issues,
            activeRefs: activeRefs,
          );
        }
      }

      if (schemaNode.containsKey('items')) {
        final items = schemaNode['items'];
        if (items is List) {
          tupleCount = items.length;
          for (var i = 0; i < items.length && i < value.length; i++) {
            _validateInstance(
              value: value[i],
              schemaNode: items[i],
              rootSchema: rootSchema,
              instancePath: '$instancePath[$i]',
              schemaPath: '$schemaPath/items/$i',
              issues: issues,
              activeRefs: activeRefs,
            );
          }
          if (schemaNode.containsKey('additionalItems')) {
            final extraSchema = schemaNode['additionalItems'];
            for (var i = items.length; i < value.length; i++) {
              _validateInstance(
                value: value[i],
                schemaNode: extraSchema,
                rootSchema: rootSchema,
                instancePath: '$instancePath[$i]',
                schemaPath: '$schemaPath/additionalItems',
                issues: issues,
                activeRefs: activeRefs,
              );
            }
          }
        } else {
          for (var i = tupleCount; i < value.length; i++) {
            _validateInstance(
              value: value[i],
              schemaNode: items,
              rootSchema: rootSchema,
              instancePath: '$instancePath[$i]',
              schemaPath: '$schemaPath/items',
              issues: issues,
              activeRefs: activeRefs,
            );
          }
        }
      }

      if (schemaNode.containsKey('contains')) {
        final containsSchema = schemaNode['contains'];
        var matched = false;
        for (var i = 0; i < value.length; i++) {
          final probe = <JsonSchemaValidationIssue>[];
          _validateInstance(
            value: value[i],
            schemaNode: containsSchema,
            rootSchema: rootSchema,
            instancePath: '$instancePath[$i]',
            schemaPath: '$schemaPath/contains',
            issues: probe,
            activeRefs: activeRefs,
          );
          if (probe.isEmpty) {
            matched = true;
            break;
          }
        }
        if (!matched) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/contains',
              keyword: 'contains',
              message:
                  'Aucun élément du tableau ne satisfait la contrainte "contains".',
            ),
          );
        }
      }
    }

    // Contraintes sur les objets
    if (value is Map) {
      if (schemaNode.containsKey('minProperties')) {
        final minProps = schemaNode['minProperties'] as int;
        if (value.length < minProps) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/minProperties',
              keyword: 'minProperties',
              message:
                  'Nombre minimal de propriétés : $minProps (actuel : ${value.length}).',
            ),
          );
        }
      }
      if (schemaNode.containsKey('maxProperties')) {
        final maxProps = schemaNode['maxProperties'] as int;
        if (value.length > maxProps) {
          issues.add(
            JsonSchemaValidationIssue(
              instancePath: instancePath,
              schemaPath: '$schemaPath/maxProperties',
              keyword: 'maxProperties',
              message:
                  'Nombre maximal de propriétés : $maxProps (actuel : ${value.length}).',
            ),
          );
        }
      }
      if (schemaNode.containsKey('required')) {
        for (final reqKey in (schemaNode['required'] as List).cast<String>()) {
          if (!value.containsKey(reqKey)) {
            final childPath = instancePath.isEmpty
                ? reqKey
                : '$instancePath.$reqKey';
            issues.add(
              JsonSchemaValidationIssue(
                instancePath: childPath,
                schemaPath: '$schemaPath/required',
                keyword: 'required',
                message: 'Propriété obligatoire « $reqKey » manquante.',
              ),
            );
          }
        }
      }

      if (schemaNode.containsKey('dependentRequired')) {
        final depReq = schemaNode['dependentRequired'] as Map;
        for (final entry in depReq.entries) {
          final trigger = entry.key.toString();
          if (value.containsKey(trigger)) {
            for (final reqKey in (entry.value as List).cast<String>()) {
              if (!value.containsKey(reqKey)) {
                final childPath = instancePath.isEmpty
                    ? reqKey
                    : '$instancePath.$reqKey';
                issues.add(
                  JsonSchemaValidationIssue(
                    instancePath: childPath,
                    schemaPath: '$schemaPath/dependentRequired',
                    keyword: 'dependentRequired',
                    message:
                        'Propriété « $reqKey » requise lorsque « $trigger » est présente.',
                  ),
                );
              }
            }
          }
        }
      }

      if (schemaNode.containsKey('dependencies')) {
        final deps = schemaNode['dependencies'] as Map;
        for (final entry in deps.entries) {
          final trigger = entry.key.toString();
          if (!value.containsKey(trigger)) continue;
          final dep = entry.value;
          if (dep is List) {
            for (final reqKey in dep.cast<String>()) {
              if (!value.containsKey(reqKey)) {
                final childPath = instancePath.isEmpty
                    ? reqKey
                    : '$instancePath.$reqKey';
                issues.add(
                  JsonSchemaValidationIssue(
                    instancePath: childPath,
                    schemaPath: '$schemaPath/dependencies',
                    keyword: 'dependencies',
                    message:
                        'Propriété « $reqKey » requise lorsque « $trigger » est présente.',
                  ),
                );
              }
            }
          } else {
            _validateInstance(
              value: value,
              schemaNode: dep,
              rootSchema: rootSchema,
              instancePath: instancePath,
              schemaPath: '$schemaPath/dependencies/${_escapePointer(trigger)}',
              issues: issues,
              activeRefs: activeRefs,
            );
          }
        }
      }

      final props = schemaNode['properties'] as Map? ?? const {};
      final patternProps = schemaNode['patternProperties'] as Map? ?? const {};
      final compiledPatterns = <({String raw, RegExp regex, Object? schema})>[
        for (final entry in patternProps.entries)
          (
            raw: entry.key.toString(),
            regex: RegExp(entry.key.toString()),
            schema: entry.value,
          ),
      ];
      final hasAdditional = schemaNode.containsKey('additionalProperties');
      final additionalSchema = schemaNode['additionalProperties'];
      final hasPropertyNames = schemaNode.containsKey('propertyNames');
      final propertyNamesSchema = schemaNode['propertyNames'];

      for (final entry in value.entries) {
        final key = entry.key.toString();
        final childPath = instancePath.isEmpty ? key : '$instancePath.$key';

        if (hasPropertyNames) {
          _validateInstance(
            value: key,
            schemaNode: propertyNamesSchema,
            rootSchema: rootSchema,
            instancePath: childPath,
            schemaPath: '$schemaPath/propertyNames',
            issues: issues,
            activeRefs: activeRefs,
          );
        }

        var matchedKnownProperty = false;
        if (props.containsKey(key)) {
          matchedKnownProperty = true;
          _validateInstance(
            value: entry.value,
            schemaNode: props[key],
            rootSchema: rootSchema,
            instancePath: childPath,
            schemaPath: '$schemaPath/properties/${_escapePointer(key)}',
            issues: issues,
            activeRefs: activeRefs,
          );
        }

        for (final pat in compiledPatterns) {
          if (pat.regex.hasMatch(key)) {
            matchedKnownProperty = true;
            _validateInstance(
              value: entry.value,
              schemaNode: pat.schema,
              rootSchema: rootSchema,
              instancePath: childPath,
              schemaPath:
                  '$schemaPath/patternProperties/${_escapePointer(pat.raw)}',
              issues: issues,
              activeRefs: activeRefs,
            );
          }
        }

        if (!matchedKnownProperty && hasAdditional) {
          if (additionalSchema == false) {
            issues.add(
              JsonSchemaValidationIssue(
                instancePath: childPath,
                schemaPath: '$schemaPath/additionalProperties',
                keyword: 'additionalProperties',
                message: 'Propriété supplémentaire « $key » non autorisée.',
              ),
            );
          } else if (additionalSchema != true) {
            _validateInstance(
              value: entry.value,
              schemaNode: additionalSchema,
              rootSchema: rootSchema,
              instancePath: childPath,
              schemaPath: '$schemaPath/additionalProperties',
              issues: issues,
              activeRefs: activeRefs,
            );
          }
        }
      }
    }

    // Compositions logiques
    if (schemaNode.containsKey('allOf')) {
      final branches = schemaNode['allOf'] as List;
      for (var i = 0; i < branches.length; i++) {
        _validateInstance(
          value: value,
          schemaNode: branches[i],
          rootSchema: rootSchema,
          instancePath: instancePath,
          schemaPath: '$schemaPath/allOf/$i',
          issues: issues,
          activeRefs: activeRefs,
        );
      }
    }

    if (schemaNode.containsKey('anyOf')) {
      final branches = schemaNode['anyOf'] as List;
      var matched = false;
      for (var i = 0; i < branches.length; i++) {
        final probe = <JsonSchemaValidationIssue>[];
        _validateInstance(
          value: value,
          schemaNode: branches[i],
          rootSchema: rootSchema,
          instancePath: instancePath,
          schemaPath: '$schemaPath/anyOf/$i',
          issues: probe,
          activeRefs: activeRefs,
        );
        if (probe.isEmpty) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        issues.add(
          JsonSchemaValidationIssue(
            instancePath: instancePath,
            schemaPath: '$schemaPath/anyOf',
            keyword: 'anyOf',
            message:
                'La valeur ne correspond à aucune des branches de "anyOf".',
          ),
        );
      }
    }

    if (schemaNode.containsKey('oneOf')) {
      final branches = schemaNode['oneOf'] as List;
      var matches = 0;
      for (var i = 0; i < branches.length; i++) {
        final probe = <JsonSchemaValidationIssue>[];
        _validateInstance(
          value: value,
          schemaNode: branches[i],
          rootSchema: rootSchema,
          instancePath: instancePath,
          schemaPath: '$schemaPath/oneOf/$i',
          issues: probe,
          activeRefs: activeRefs,
        );
        if (probe.isEmpty) matches++;
      }
      if (matches != 1) {
        issues.add(
          JsonSchemaValidationIssue(
            instancePath: instancePath,
            schemaPath: '$schemaPath/oneOf',
            keyword: 'oneOf',
            message: matches == 0
                ? 'La valeur ne correspond à aucune branche de "oneOf".'
                : 'La valeur correspond à $matches branches de "oneOf" (exactement 1 attendue).',
          ),
        );
      }
    }

    if (schemaNode.containsKey('not')) {
      final probe = <JsonSchemaValidationIssue>[];
      _validateInstance(
        value: value,
        schemaNode: schemaNode['not'],
        rootSchema: rootSchema,
        instancePath: instancePath,
        schemaPath: '$schemaPath/not',
        issues: probe,
        activeRefs: activeRefs,
      );
      if (probe.isEmpty) {
        issues.add(
          JsonSchemaValidationIssue(
            instancePath: instancePath,
            schemaPath: '$schemaPath/not',
            keyword: 'not',
            message: 'La valeur ne doit pas satisfaire le schéma "not".',
          ),
        );
      }
    }

    if (schemaNode.containsKey('if')) {
      final probe = <JsonSchemaValidationIssue>[];
      _validateInstance(
        value: value,
        schemaNode: schemaNode['if'],
        rootSchema: rootSchema,
        instancePath: instancePath,
        schemaPath: '$schemaPath/if',
        issues: probe,
        activeRefs: activeRefs,
      );
      if (probe.isEmpty) {
        if (schemaNode.containsKey('then')) {
          _validateInstance(
            value: value,
            schemaNode: schemaNode['then'],
            rootSchema: rootSchema,
            instancePath: instancePath,
            schemaPath: '$schemaPath/then',
            issues: issues,
            activeRefs: activeRefs,
          );
        }
      } else if (schemaNode.containsKey('else')) {
        _validateInstance(
          value: value,
          schemaNode: schemaNode['else'],
          rootSchema: rootSchema,
          instancePath: instancePath,
          schemaPath: '$schemaPath/else',
          issues: issues,
          activeRefs: activeRefs,
        );
      }
    }
  }

  static bool _matchesType(Object? value, String type) => switch (type) {
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'integer' => value is int || (value is num && value.isFinite && value % 1 == 0),
    'number' => value is num && value.isFinite,
    'boolean' => value is bool,
    'null' => value == null,
    _ => false,
  };

  static String _describeType(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return 'boolean';
    if (value is int) return 'integer';
    if (value is num) return 'number';
    if (value is String) return 'string';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    return value.runtimeType.toString();
  }

  static bool _isMultipleOf(num value, num divisor) {
    if (value is int && divisor is int) {
      return value % divisor == 0;
    }
    final ratio = value / divisor;
    if (!ratio.isFinite) return false;
    final rounded = ratio.roundToDouble();
    final diff = (ratio - rounded).abs();
    final tolerance = 1e-9 * (rounded.abs() < 1 ? 1.0 : rounded.abs());
    return diff <= tolerance;
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is num && b is num) return a == b;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key) ||
            !_deepEquals(entry.value, b[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static String? _validateFormat(String value, String format) {
    switch (format) {
      case 'email':
        return _emailPattern.hasMatch(value)
            ? null
            : 'Adresse e-mail invalide.';
      case 'uuid':
        return _uuidPattern.hasMatch(value)
            ? null
            : 'Identifiant UUID invalide.';
      case 'uri':
      case 'url':
        final uri = Uri.tryParse(value);
        if (uri == null || !uri.hasScheme || uri.scheme.isEmpty) {
          return 'URI invalide (schéma manquant ou mal formé).';
        }
        return null;
      case 'date':
        final match = _datePattern.firstMatch(value);
        if (match == null || !_isValidCalendarDate(match)) {
          return 'Date ISO 8601 invalide (attendu : YYYY-MM-DD).';
        }
        return null;
      case 'time':
        final match = _timePattern.firstMatch(value);
        if (match == null || !_isValidClockTime(match, 1)) {
          return 'Heure ISO 8601 invalide (attendu : HH:MM:SS).';
        }
        return null;
      case 'date-time':
        final match = _dateTimePattern.firstMatch(value);
        if (match == null ||
            !_isValidCalendarDate(match) ||
            !_isValidClockTime(match, 4)) {
          return 'Date-heure ISO 8601 invalide (ex. 2026-11-19T12:00:00Z).';
        }
        return null;
      case 'ipv4':
        return _ipv4Pattern.hasMatch(value) ? null : 'Adresse IPv4 invalide.';
      case 'ipv6':
        try {
          Uri.parseIPv6Address(value);
          return null;
        } on FormatException {
          return 'Adresse IPv6 invalide.';
        }
      case 'hostname':
        return _hostnamePattern.hasMatch(value)
            ? null
            : 'Nom d’hôte invalide.';
      default:
        return null;
    }
  }

  static bool _isValidCalendarDate(RegExpMatch match) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static bool _isValidClockTime(RegExpMatch match, int startGroup) {
    final hour = int.parse(match.group(startGroup)!);
    final minute = int.parse(match.group(startGroup + 1)!);
    final second = int.parse(match.group(startGroup + 2)!);
    return hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59 &&
        second >= 0 &&
        second <= 60;
  }
}
