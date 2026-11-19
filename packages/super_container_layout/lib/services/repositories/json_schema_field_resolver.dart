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

  /// Résout le [SchemaFieldProfile] associé à [attributePath] dans [rootSchema],
  /// ou retourne `null` si le chemin est introuvable, calculé (`@nom`) ou invalide.
  static SchemaFieldProfile? resolve(
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
    return _extractProfile(current, isRequired: isRequired);
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

    // Déduction automatique pour les formats temporels si aucune extension
    // explicite x-mask / x-dateFormat n'est précisée.
    if (mask == null && dateFormat == null) {
      switch (format) {
        case TextFieldFormat.date:
          dateFormat = 'dd/MM/yyyy';
          mask = '##/##/####';
          maskIncludeLiterals ??= false;
          locked.addAll({'dateFormat', 'mask', 'maskIncludeLiterals'});
        case TextFieldFormat.dateTime:
          dateFormat = 'dd/MM/yyyy HH:mm';
          mask = '##/##/#### ##:##';
          maskIncludeLiterals ??= false;
          locked.addAll({'dateFormat', 'mask', 'maskIncludeLiterals'});
        case TextFieldFormat.time:
          mask = '##:##:##';
          maskIncludeLiterals ??= true;
          locked.addAll({'mask', 'maskIncludeLiterals'});
        default:
          break;
      }
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
}
