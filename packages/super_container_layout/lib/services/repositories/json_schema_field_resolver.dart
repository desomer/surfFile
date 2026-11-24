/// Résolution d'un sous-schéma JSON Schema à partir d'un [JsonAttributePath]
/// pour en extraire automatiquement les contraintes et masques ([SchemaFieldProfile]).
library;

import '../../models/json_text_binding.dart';
import '../../models/text_field_constraints.dart';

/// Inspecte un JSON Schema (Draft 7 / Draft 2020-12) le long d'un chemin de
/// liaison [JsonAttributePath] afin d'en extraire un [SchemaFieldProfile].
abstract final class JsonSchemaFieldResolver {
  /// Clés de contraintes JSON Schema toujours pilotées (et grisées dans le
  /// wizard) lorsque l'héritage du schéma est actif et qu'un nœud correspond.
  static const Set<String> schemaConstraintKeys = {
    'valueType',
    'required',
    'minLength',
    'maxLength',
    'validationPattern',
    'format',
    'minimum',
    'maximum',
    'exclusiveMinimum',
    'exclusiveMaximum',
    'multipleOf',
    'enumValues',
    'constValue',
  };

  /// Résout le sous-schéma déballé (`$ref`, `allOf`, `anyOf`/`oneOf`) associé
  /// à [attributePath] dans [rootSchema], ou retourne `null` si introuvable.
  static Map<String, Object?>? resolveSchemaNode(
    Map<String, Object?>? rootSchema,
    String attributePath,
  ) {
    final resolved = _resolveNodeWithRequired(rootSchema, attributePath);
    return resolved?.node;
  }

  /// Construit une valeur/ligne par défaut pour les éléments du tableau situé à
  /// [arrayPath] à partir de [rootSchema], ou retourne `null` si aucun schéma
  /// d'élément n'est résolu.
  static Object? buildDefaultArrayItem(
    Map<String, Object?>? rootSchema,
    String arrayPath,
  ) {
    final arrayNode = resolveSchemaNode(rootSchema, arrayPath);
    if (arrayNode == null || rootSchema == null) return null;

    Object? rawItemSchema = arrayNode['items'];
    if (rawItemSchema == null &&
        arrayNode['prefixItems'] is List &&
        (arrayNode['prefixItems'] as List).isNotEmpty) {
      rawItemSchema = (arrayNode['prefixItems'] as List).first;
    } else if (rawItemSchema is List && rawItemSchema.isNotEmpty) {
      rawItemSchema = rawItemSchema.first;
    }
    final itemNode = _unwrapNode(rawItemSchema, rootSchema, <String>{});
    if (itemNode == null) return null;
    return _buildDefaultValue(itemNode, rootSchema, <Object>{});
  }

  /// Résout le [SchemaFieldProfile] associé à [attributePath] dans [rootSchema],
  /// ou retourne `null` si le chemin est introuvable, calculé (`@nom`) ou invalide.
  static SchemaFieldProfile? resolve(
    Map<String, Object?>? rootSchema,
    String attributePath,
  ) {
    final resolved = _resolveNodeWithRequired(rootSchema, attributePath);
    if (resolved == null) return null;
    return _extractProfile(resolved.node, isRequired: resolved.isRequired);
  }

  static ({Map<String, Object?> node, bool isRequired})?
  _resolveNodeWithRequired(
    Map<String, Object?>? rootSchema,
    String attributePath,
  ) {
    if (rootSchema == null || attributePath.trim().isEmpty) return null;
    if (JsonTextBinding.isCalculatedPath(attributePath)) return null;
    final JsonAttributePath parsed;
    try {
      parsed = JsonAttributePath(attributePath);
    } on FormatException {
      return null;
    }

    var current = _unwrapNode(rootSchema, rootSchema, <String>{});
    if (current == null) return null;

    var isRequired = false;
    for (final step in parsed.steps) {
      current = _unwrapNode(current, rootSchema, <String>{});
      if (current == null) return null;

      if (step.key != null) {
        final key = step.key!;
        final req = current['required'];
        isRequired = req is List && req.contains(key);

        Object? next;
        final props = current['properties'];
        if (props is Map && props.containsKey(key)) {
          next = props[key];
        } else {
          final patternProps = current['patternProperties'];
          if (patternProps is Map) {
            for (final entry in patternProps.entries) {
              try {
                if (RegExp(entry.key.toString()).hasMatch(key)) {
                  next = entry.value;
                  break;
                }
              } on FormatException {
                // Ignore un motif patternProperties invalide.
              }
            }
          }
          if (next == null && current['additionalProperties'] is Map) {
            next = current['additionalProperties'];
          }
        }
        current = _unwrapNode(next, rootSchema, <String>{});
      } else {
        isRequired = false;
        Object? next;
        final idx = step.index;
        if (idx != null) {
          final prefixItems = current['prefixItems'];
          final items = current['items'];
          if (prefixItems is List && idx >= 0 && idx < prefixItems.length) {
            next = prefixItems[idx];
          } else if (items is List && idx >= 0 && idx < items.length) {
            next = items[idx];
          } else if (items is Map) {
            next = items;
          } else if (items is List && current['additionalItems'] is Map) {
            next = current['additionalItems'];
          }
        } else {
          // Joker [?]
          final items = current['items'];
          if (items is Map) {
            next = items;
          } else if (current['prefixItems'] is List &&
              (current['prefixItems'] as List).isNotEmpty) {
            next = (current['prefixItems'] as List).first;
          } else if (items is List && items.isNotEmpty) {
            next = items.first;
          }
        }
        current = _unwrapNode(next, rootSchema, <String>{});
      }
      if (current == null) return null;
    }

    if (current == null) return null;
    return (node: current, isRequired: isRequired);
  }

  static Object? _buildDefaultValue(
    Map<String, Object?> node,
    Map<String, Object?> rootSchema,
    Set<Object> activeNodes,
  ) {
    if (node.containsKey('default')) {
      return _cloneJsonValue(node['default']);
    }
    if (node.containsKey('const')) {
      return _cloneJsonValue(node['const']);
    }

    final rawType = _primaryJsonType(node);
    if (rawType == 'object' || (rawType == null && node['properties'] is Map)) {
      if (!activeNodes.add(node)) {
        return <String, dynamic>{};
      }
      try {
        final result = <String, dynamic>{};
        final requiredKeys = <String>{
          if (node['required'] case final List<Object?> req)
            for (final item in req)
              if (item is String) item,
        };
        final props = node['properties'];
        if (props is Map) {
          for (final entry in props.entries) {
            final key = entry.key.toString();
            final propNode = _unwrapNode(entry.value, rootSchema, <String>{});
            if (propNode == null) continue;
            if (!requiredKeys.contains(key) &&
                _shouldOmitOptionalProperty(propNode)) {
              continue;
            }
            result[key] = _buildDefaultValue(propNode, rootSchema, activeNodes);
          }
        }
        return result;
      } finally {
        activeNodes.remove(node);
      }
    }

    if (rawType == 'array') {
      final minItems = node['minItems'];
      final count = minItems is int && minItems > 0 ? minItems : 0;
      if (count > 0 && node['items'] != null && activeNodes.add(node)) {
        try {
          final itemNode = _unwrapNode(node['items'], rootSchema, <String>{});
          if (itemNode != null) {
            return <Object?>[
              for (var i = 0; i < count; i++)
                _buildDefaultValue(itemNode, rootSchema, activeNodes),
            ];
          }
        } finally {
          activeNodes.remove(node);
        }
      }
      return <Object?>[];
    }

    if (node['enum'] is List && (node['enum'] as List).isNotEmpty) {
      return _cloneJsonValue((node['enum'] as List).first);
    }

    if (_allowsNullType(node) && _hasConstrainedStringRule(node)) {
      return null;
    }

    return switch (rawType) {
      'string' => _defaultStringFor(node),
      'boolean' => false,
      'integer' => _defaultIntegerFor(node),
      'number' => _defaultNumberFor(node),
      'null' => null,
      _ => null,
    };
  }

  static bool _allowsNullType(Map<String, Object?> node) {
    final raw = node['type'];
    return raw == 'null' || (raw is List && raw.contains('null'));
  }

  static bool _hasConstrainedStringRule(Map<String, Object?> node) {
    if (_primaryJsonType(node) != 'string') return false;
    final minLen = node['minLength'];
    if (minLen is int && minLen > 0) return true;
    final pattern = node['pattern'];
    if (pattern is String && pattern.isNotEmpty) return true;
    final format = node['format'];
    if (format is String && format.trim().isNotEmpty) return true;
    return false;
  }

  static bool _shouldOmitOptionalProperty(Map<String, Object?> node) {
    if (node.containsKey('default') || node.containsKey('const')) return false;
    if (node['enum'] is List && (node['enum'] as List).isNotEmpty) return false;
    if (_allowsNullType(node)) return false;
    if (_primaryJsonType(node) != 'string') return false;

    final pattern = node['pattern'];
    if (pattern is String && pattern.isNotEmpty) return true;

    final format = (node['format'] as String?)?.trim().toLowerCase();
    if (format != null &&
        format.isNotEmpty &&
        format != 'date' &&
        format != 'date-time' &&
        format != 'time' &&
        format != 'uuid') {
      return true;
    }

    final minLen = node['minLength'];
    if (minLen is int && minLen > 0) return true;
    return false;
  }

  static String _defaultStringFor(Map<String, Object?> node) {
    final format = (node['format'] as String?)?.trim().toLowerCase();
    if (format != null && format.isNotEmpty) {
      final nowUtc = DateTime.now().toUtc();
      String two(int v) => v.toString().padLeft(2, '0');
      final isoDate =
          '${nowUtc.year.toString().padLeft(4, '0')}-${two(nowUtc.month)}-${two(nowUtc.day)}';
      switch (format) {
        case 'date':
          return isoDate;
        case 'date-time':
          return '${isoDate}T${two(nowUtc.hour)}:${two(nowUtc.minute)}:${two(nowUtc.second)}Z';
        case 'time':
          return '00:00:00';
        case 'uuid':
          return '00000000-0000-0000-0000-000000000000';
        case 'email':
          return 'nouveau@exemple.com';
        case 'uri':
        case 'url':
          return 'https://exemple.com';
        case 'ipv4':
          return '127.0.0.1';
        case 'ipv6':
          return '::1';
        case 'hostname':
          return 'exemple.com';
      }
    }
    final minLen = node['minLength'];
    if (minLen is int && minLen > 0) {
      final maxLen = node['maxLength'];
      final targetLen = maxLen is int && maxLen > 0 && maxLen < minLen
          ? maxLen
          : minLen;
      return '-' * targetLen;
    }
    return '';
  }

  static String? _primaryJsonType(Map<String, Object?> node) {
    final raw = node['type'];
    if (raw is String) return raw;
    if (raw is List) {
      for (final candidate in raw) {
        if (candidate is String && candidate != 'null') return candidate;
      }
      if (raw.contains('null')) return 'null';
    }
    return null;
  }

  static int _defaultIntegerFor(Map<String, Object?> node) {
    final min = node['minimum'];
    final exMin = node['exclusiveMinimum'];
    final max = node['maximum'];
    final exMax = node['exclusiveMaximum'];
    int? lower;
    if (min is num && min.isFinite) {
      lower = min.ceil();
    }
    if (exMin is num && exMin.isFinite) {
      final exLower = exMin.floor() + 1;
      lower = lower == null || exLower > lower ? exLower : lower;
    }
    int? upper;
    if (max is num && max.isFinite) {
      upper = max.floor();
    }
    if (exMax is num && exMax.isFinite) {
      final exUpper = exMax.ceil() - 1;
      upper = upper == null || exUpper < upper ? exUpper : upper;
    }

    var candidate = 0;
    if (lower != null && candidate < lower) {
      candidate = lower;
    }
    if (upper != null && candidate > upper) {
      candidate = upper;
    }

    final multipleOf = node['multipleOf'];
    if (multipleOf is num && multipleOf.isFinite && multipleOf > 0) {
      final step = multipleOf.round();
      if (step > 0 && (multipleOf - step).abs() < 1e-9 && candidate % step != 0) {
        final up = ((candidate / step).ceil()) * step;
        final down = ((candidate / step).floor()) * step;
        if (upper == null || up <= upper) {
          candidate = up;
        } else if (lower == null || down >= lower) {
          candidate = down;
        }
      }
    }
    return candidate;
  }

  static double _defaultNumberFor(Map<String, Object?> node) {
    final min = node['minimum'];
    final exMin = node['exclusiveMinimum'];
    final max = node['maximum'];
    final exMax = node['exclusiveMaximum'];
    final multipleOf = node['multipleOf'];
    final step = (multipleOf is num && multipleOf.isFinite && multipleOf > 0)
        ? multipleOf.toDouble()
        : null;

    var candidate = 0.0;
    if (min is num && min.isFinite && candidate < min) {
      candidate = min.toDouble();
    }
    if (exMin is num && exMin.isFinite && candidate <= exMin) {
      final upperBound = max is num && max.isFinite
          ? max.toDouble()
          : (exMax is num && exMax.isFinite ? exMax.toDouble() : null);
      final delta = step ?? 1.0;
      if (upperBound != null && exMin.toDouble() + delta > upperBound) {
        candidate = (exMin.toDouble() + upperBound) / 2.0;
      } else {
        candidate = exMin.toDouble() + delta;
      }
    }
    if (max is num && max.isFinite && candidate > max) {
      candidate = max.toDouble();
    }
    if (exMax is num && exMax.isFinite && candidate >= exMax) {
      final lowerBound = min is num && min.isFinite
          ? min.toDouble()
          : (exMin is num && exMin.isFinite ? exMin.toDouble() : null);
      final delta = step ?? 1.0;
      if (lowerBound != null && exMax.toDouble() - delta < lowerBound) {
        candidate = (lowerBound + exMax.toDouble()) / 2.0;
      } else {
        candidate = exMax.toDouble() - delta;
      }
    }
    if (step != null) {
      final ratio = candidate / step;
      if ((ratio - ratio.round()).abs() > 1e-9) {
        final up = ratio.ceil() * step;
        final down = ratio.floor() * step;
        final fitsUpper =
            (max is! num || !max.isFinite || up <= max) &&
            (exMax is! num || !exMax.isFinite || up < exMax);
        final fitsLower =
            (min is! num || !min.isFinite || down >= min) &&
            (exMin is! num || !exMin.isFinite || down > exMin);
        if (fitsUpper) {
          candidate = up;
        } else if (fitsLower) {
          candidate = down;
        }
      }
    }
    return candidate;
  }

  static Object? _cloneJsonValue(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _cloneJsonValue(entry.value),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _cloneJsonValue(item)];
    }
    return value;
  }

  static SchemaFieldProfile _extractProfile(
    Map<String, Object?> node, {
    required bool isRequired,
  }) {
    final locked = <String>{...schemaConstraintKeys};
    final valueType = _parseValueType(node['type']);

    final rawMinLen = node['minLength'];
    final minLength = rawMinLen is int && rawMinLen >= 0 ? rawMinLen : null;

    final rawMaxLen = node['maxLength'];
    final maxLength = rawMaxLen is int && rawMaxLen >= 1 ? rawMaxLen : null;

    var validationPattern = '';
    if (node['pattern'] is String) {
      final candidate = node['pattern'] as String;
      try {
        RegExp(candidate, unicode: true);
        validationPattern = candidate;
      } on FormatException {
        validationPattern = '';
      }
    }

    final format = node['format'] is String
        ? (TextFieldFormat.tryParse(node['format'] as String) ??
              TextFieldFormat.none)
        : TextFieldFormat.none;

    double? toFiniteDouble(Object? raw) =>
        raw is num && raw.isFinite ? raw.toDouble() : null;

    double? minimum = toFiniteDouble(node['minimum']);
    double? maximum = toFiniteDouble(node['maximum']);
    double? exclusiveMinimum = toFiniteDouble(node['exclusiveMinimum']);
    double? exclusiveMaximum = toFiniteDouble(node['exclusiveMaximum']);

    // Compatibilité Draft-07 : exclusiveMinimum/exclusiveMaximum booléen.
    if (node['exclusiveMinimum'] == true && minimum != null) {
      exclusiveMinimum = minimum;
      minimum = null;
    }
    if (node['exclusiveMaximum'] == true && maximum != null) {
      exclusiveMaximum = maximum;
      maximum = null;
    }

    final rawMultipleOf = toFiniteDouble(node['multipleOf']);
    final multipleOf =
        rawMultipleOf != null && rawMultipleOf > 0 ? rawMultipleOf : null;

    final enumValues = <String>[];
    if (node['enum'] is List) {
      for (final item in node['enum'] as List) {
        if (item is String || item is num || item is bool) {
          enumValues.add(item.toString());
        }
      }
    }

    final rawConst = node['const'];
    final constValue =
        (rawConst is String || rawConst is num || rawConst is bool)
        ? rawConst.toString()
        : null;

    String? validationMessage;
    if (node['x-validationMessage'] is String) {
      validationMessage = node['x-validationMessage'] as String;
      locked.add('validationMessage');
    }

    // Masques et formats via extensions x-* ou déduction sur `format`.
    String? mask;
    if (node['x-mask'] is String) {
      final candidate = node['x-mask'] as String;
      try {
        PatternMask.validatePattern(candidate);
        mask = candidate;
        locked.add('mask');
      } on FormatException {
        // Ignore un x-mask invalide.
      }
    }

    bool? maskIncludeLiterals;
    if (node['x-maskIncludeLiterals'] is bool) {
      maskIncludeLiterals = node['x-maskIncludeLiterals'] as bool;
      locked.add('maskIncludeLiterals');
    }

    String? dateFormat;
    if (node['x-dateFormat'] is String) {
      final candidate = node['x-dateFormat'] as String;
      try {
        DateFieldFormat.validatePattern(candidate);
        dateFormat = candidate;
        locked.add('dateFormat');
      } on FormatException {
        // Ignore un x-dateFormat invalide.
      }
    }

    int? decimalDigits;
    if (node['x-decimalDigits'] is int) {
      final candidate = node['x-decimalDigits'] as int;
      if (candidate >= 0 && candidate <= 10) {
        decimalDigits = candidate;
        locked.add('decimalDigits');
      }
    }

    String? decimalSeparator;
    if (node['x-decimalSeparator'] == '.' ||
        node['x-decimalSeparator'] == ',') {
      decimalSeparator = node['x-decimalSeparator'] as String;
      locked.add('decimalSeparator');
    }

    String? thousandsSeparator;
    if (node['x-thousandsSeparator'] is String) {
      final candidate = node['x-thousandsSeparator'] as String;
      if (candidate.length <= 1 && candidate != (decimalSeparator ?? '.')) {
        thousandsSeparator = candidate;
        locked.add('thousandsSeparator');
      }
    }

    // Déduction automatique pour les formats temporels.
    if (format == TextFieldFormat.date && dateFormat == null) {
      if (mask == null || mask == '##/##/####') {
        dateFormat = 'dd/MM/yyyy';
        mask ??= '##/##/####';
        maskIncludeLiterals ??= false;
        locked.addAll({'dateFormat', 'mask', 'maskIncludeLiterals'});
      } else if (mask == '####-##-##') {
        dateFormat = 'yyyy-MM-dd';
        maskIncludeLiterals ??= true;
        locked.addAll({'dateFormat', 'maskIncludeLiterals'});
      }
    } else if (format == TextFieldFormat.dateTime && dateFormat == null) {
      if (mask == null || mask == '##/##/#### ##:##') {
        dateFormat = 'dd/MM/yyyy HH:mm';
        mask ??= '##/##/#### ##:##';
        maskIncludeLiterals ??= false;
        locked.addAll({'dateFormat', 'mask', 'maskIncludeLiterals'});
      }
    } else if (format == TextFieldFormat.time &&
        mask == null &&
        dateFormat == null) {
      mask = '##:##:##';
      maskIncludeLiterals ??= true;
      locked.addAll({'mask', 'maskIncludeLiterals'});
    }

    return SchemaFieldProfile(
      valueType: valueType,
      required: isRequired,
      minLength: minLength,
      maxLength: maxLength,
      validationPattern: validationPattern,
      format: format,
      minimum: minimum,
      maximum: maximum,
      exclusiveMinimum: exclusiveMinimum,
      exclusiveMaximum: exclusiveMaximum,
      multipleOf: multipleOf,
      enumValues: List.unmodifiable(enumValues),
      constValue: constValue,
      validationMessage: validationMessage,
      mask: mask,
      maskIncludeLiterals: maskIncludeLiterals,
      dateFormat: dateFormat,
      decimalDigits: decimalDigits,
      decimalSeparator: decimalSeparator,
      thousandsSeparator: thousandsSeparator,
      lockedKeys: Set.unmodifiable(locked),
    );
  }

  static TextFieldValueType _parseValueType(Object? rawType) {
    String? chosen;
    if (rawType is String) {
      chosen = rawType;
    } else if (rawType is List) {
      final nonNull = [
        for (final t in rawType)
          if (t is String && t != 'null') t,
      ];
      if (nonNull.length == 1) {
        chosen = nonNull.single;
      }
    }
    return switch (chosen) {
      'integer' => TextFieldValueType.integer,
      'number' => TextFieldValueType.number,
      _ => TextFieldValueType.string,
    };
  }

  static Map<String, Object?>? _unwrapNode(
    Object? rawNode,
    Map<String, Object?> rootSchema,
    Set<String> seenRefs,
  ) {
    if (rawNode is! Map) return null;
    var merged = <String, Object?>{
      for (final entry in rawNode.entries) entry.key.toString(): entry.value,
    };

    final ref = merged[r'$ref'];
    if (ref is String && ref.startsWith('#') && seenRefs.add(ref)) {
      final target = _resolveLocalRef(rootSchema, ref);
      final resolved = _unwrapNode(target, rootSchema, seenRefs);
      seenRefs.remove(ref);
      if (resolved != null) {
        merged = _mergeNodes(resolved, Map.of(merged)..remove(r'$ref'));
      }
    }

    if (merged['allOf'] is List) {
      final branches = merged['allOf'] as List;
      var base = Map<String, Object?>.of(merged)..remove('allOf');
      for (final branch in branches) {
        final resolved = _unwrapNode(branch, rootSchema, seenRefs);
        if (resolved != null) {
          base = _mergeNodes(base, resolved);
        }
      }
      merged = base;
    }

    for (final compKey in const ['anyOf', 'oneOf']) {
      if (merged[compKey] is List) {
        final branches = merged[compKey] as List;
        final nonNullBranches = <Map<String, Object?>>[];
        for (final branch in branches) {
          final resolved = _unwrapNode(branch, rootSchema, seenRefs);
          if (resolved != null && resolved['type'] != 'null') {
            nonNullBranches.add(resolved);
          }
        }
        if (nonNullBranches.length == 1) {
          final base = Map<String, Object?>.of(merged)..remove(compKey);
          merged = _mergeNodes(base, nonNullBranches.single);
        }
      }
    }

    return merged;
  }

  static Map<String, Object?> _mergeNodes(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final result = Map<String, Object?>.of(a);
    for (final entry in b.entries) {
      if (entry.key == 'properties' &&
          result['properties'] is Map &&
          entry.value is Map) {
        result['properties'] = <String, Object?>{
          for (final e in (result['properties'] as Map).entries)
            e.key.toString(): e.value,
          for (final e in (entry.value as Map).entries)
            e.key.toString(): e.value,
        };
      } else if (entry.key == 'required' &&
          result['required'] is List &&
          entry.value is List) {
        result['required'] = <String>{
          ...(result['required'] as List).cast<String>(),
          ...(entry.value as List).cast<String>(),
        }.toList();
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static Object? _resolveLocalRef(Map<String, Object?> root, String ref) {
    if (ref == '#') return root;
    if (!ref.startsWith('#/')) return null;
    final segments = ref
        .substring(2)
        .split('/')
        .map((s) => s.replaceAll('~1', '/').replaceAll('~0', '~'));
    Object? current = root;
    for (final segment in segments) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else if (current is List) {
        final idx = int.tryParse(segment);
        if (idx == null || idx < 0 || idx >= current.length) return null;
        current = current[idx];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Audite toutes les définitions de champs d'un JSON Schema pour détecter
  /// d'éventuelles incohérences entre `format`, `pattern`, `x-mask` et `x-dateFormat`.
  static List<({String schemaPath, String kind, String message})>
  auditSchemaExtensions(Map<String, Object?> rootSchema) {
    final issues = <({String schemaPath, String kind, String message})>[];
    final visited = <Object>{};

    void visit(Object? raw, String path) {
      if (raw is! Map || !visited.add(raw)) return;
      final node = <String, Object?>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
      final rawFormat = node['format'];
      final parsedFormat = rawFormat is String
          ? TextFieldFormat.tryParse(rawFormat)
          : null;
      final rawMask = node['x-mask'];
      final rawDateFormat = node['x-dateFormat'];
      final rawPattern = node['pattern'];

      if (rawMask != null) {
        if (rawMask is! String) {
          issues.add((
            schemaPath: '$path/x-mask',
            kind: 'invalid_schema_mask',
            message: 'L’extension "x-mask" doit être une chaîne de caractères.',
          ));
        } else {
          try {
            PatternMask.validatePattern(rawMask);
          } on FormatException catch (e) {
            issues.add((
              schemaPath: '$path/x-mask',
              kind: 'invalid_schema_mask',
              message: e.message,
            ));
          }
        }
      }

      if (rawDateFormat != null) {
        if (rawDateFormat is! String) {
          issues.add((
            schemaPath: '$path/x-dateFormat',
            kind: 'invalid_schema_date_format',
            message:
                'L’extension "x-dateFormat" doit être une chaîne de caractères.',
          ));
        } else {
          try {
            DateFieldFormat.validatePattern(rawDateFormat);
          } on FormatException catch (e) {
            issues.add((
              schemaPath: '$path/x-dateFormat',
              kind: 'invalid_schema_date_format',
              message: e.message,
            ));
          }
        }
      }

      if (parsedFormat == TextFieldFormat.date ||
          parsedFormat == TextFieldFormat.dateTime) {
        final sampleIso = parsedFormat == TextFieldFormat.date
            ? '2026-05-19'
            : '2026-05-19T14:30:00Z';
        if (rawPattern is String) {
          try {
            if (!RegExp(rawPattern, unicode: true).hasMatch(sampleIso)) {
              issues.add((
                schemaPath: '$path/pattern',
                kind: 'schema_date_pattern_conflict',
                message:
                    'Le motif "pattern" ($rawPattern) rejette le format ISO requis par "format": "${parsedFormat!.schemaName}" (ex. "$sampleIso"). Retire "pattern" ou aligne-le sur ISO 8601.',
              ));
            }
          } on FormatException {
            // Déjà signalé par JsonSchemaValidator.
          }
        }
        if (rawMask is String &&
            rawDateFormat == null &&
            ((parsedFormat == TextFieldFormat.date &&
                    rawMask != '##/##/####' &&
                    rawMask != '####-##-##') ||
                (parsedFormat == TextFieldFormat.dateTime &&
                    rawMask != '##/##/#### ##:##'))) {
          issues.add((
            schemaPath: '$path/x-mask',
            kind: 'schema_mask_date_conflict',
            message:
                'Le masque "x-mask" ("$rawMask") avec "format": "${parsedFormat!.schemaName}" exige un "x-dateFormat" explicite compatible.',
          ));
        }
      }

      for (final mapKey in const [
        'properties',
        'patternProperties',
        r'$defs',
        'definitions',
      ]) {
        if (node[mapKey] is Map) {
          for (final entry in (node[mapKey] as Map).entries) {
            visit(entry.value, '$path/$mapKey/${entry.key}');
          }
        }
      }
      if (node['items'] is Map) {
        visit(node['items'], '$path/items');
      } else if (node['items'] is List) {
        final list = node['items'] as List;
        for (var i = 0; i < list.length; i++) {
          visit(list[i], '$path/items/$i');
        }
      }
      for (final listKey in const ['prefixItems', 'allOf', 'anyOf', 'oneOf']) {
        if (node[listKey] is List) {
          final list = node[listKey] as List;
          for (var i = 0; i < list.length; i++) {
            visit(list[i], '$path/$listKey/$i');
          }
        }
      }
      for (final subKey in const [
        'additionalProperties',
        'additionalItems',
        'if',
        'then',
        'else',
      ]) {
        if (node[subKey] is Map) {
          visit(node[subKey], '$path/$subKey');
        }
      }
    }

    visit(rootSchema, '#');
    return issues;
  }
}
