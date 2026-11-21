/// Modèle immuable complet des contraintes JSON Schema Draft 7 / 2020-12
/// portées par un attribut d'objet métier ([JsonSchemaConstraints]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Ensemble complet et immuable des mots-clés de validation et métadonnées
/// JSON Schema (Draft 7 / Draft 2020-12) applicables à un [BusinessAttribute].
@immutable
class JsonSchemaConstraints {
  /// Construit un jeu de contraintes JSON Schema immuable.
  JsonSchemaConstraints({
    // Numériques
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
    // Chaînes
    this.minLength,
    this.maxLength,
    this.pattern,
    this.format,
    this.contentMediaType,
    this.contentEncoding,
    // Tableaux
    this.minItems,
    this.maxItems,
    this.uniqueItems,
    Map<String, Object?>? contains,
    this.minContains,
    this.maxContains,
    List<Map<String, Object?>>? prefixItems,
    // Sous-objets
    this.minProperties,
    this.maxProperties,
    Object? additionalProperties,
    Map<String, Object?>? patternProperties,
    Map<String, Object?>? propertyNames,
    Map<String, List<String>>? dependentRequired,
    Map<String, Object?>? dependentSchemas,
    // Générique & métadonnées
    this.hasConst = false,
    this.constValue,
    List<Object?>? examples,
    this.readOnly,
    this.writeOnly,
    this.deprecated,
    this.title,
    this.comment,
    // Composition & conditionnels
    List<Map<String, Object?>>? oneOf,
    List<Map<String, Object?>>? anyOf,
    List<Map<String, Object?>>? allOf,
    Map<String, Object?>? not,
    Map<String, Object?>? ifSchema,
    Map<String, Object?>? thenSchema,
    Map<String, Object?>? elseSchema,
    // Extensions (x-mask, x-dateFormat, etc.)
    Map<String, Object?>? extraKeywords,
  }) : contains = _freezeSchemaMap(contains),
       prefixItems = _freezeSchemaList(prefixItems),
       additionalProperties = _freezeAdditionalProperties(additionalProperties),
       patternProperties = _freezeSchemaMap(patternProperties),
       propertyNames = _freezeSchemaMap(propertyNames),
       dependentRequired = _freezeDependentRequired(dependentRequired),
       dependentSchemas = _freezeSchemaMap(dependentSchemas),
       examples = examples == null
           ? const <Object?>[]
           : List<Object?>.unmodifiable(examples.map(_deepFreezeValue)),
       oneOf = _freezeSchemaList(oneOf),
       anyOf = _freezeSchemaList(anyOf),
       allOf = _freezeSchemaList(allOf),
       not = _freezeSchemaMap(not),
       ifSchema = _freezeSchemaMap(ifSchema),
       thenSchema = _freezeSchemaMap(thenSchema),
       elseSchema = _freezeSchemaMap(elseSchema),
       extraKeywords = _freezeSchemaMap(extraKeywords) ?? const {};

  /// Jeu de contraintes vide.
  static final JsonSchemaConstraints empty = JsonSchemaConstraints();

  /// Formats JSON Schema standard couramment proposés dans l'atelier.
  static const List<String> standardFormats = <String>[
    'date',
    'date-time',
    'time',
    'duration',
    'email',
    'idn-email',
    'hostname',
    'ipv4',
    'ipv6',
    'uri',
    'uri-reference',
    'iri',
    'uuid',
    'regex',
    'json-pointer',
  ];

  /// Mots-clés gérés explicitement par les champs typés de cette classe.
  static const Set<String> knownKeywords = <String>{
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

  // --- Numériques ---
  final num? minimum;
  final num? maximum;
  final num? exclusiveMinimum;
  final num? exclusiveMaximum;
  final num? multipleOf;

  // --- Chaînes ---
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final String? format;
  final String? contentMediaType;
  final String? contentEncoding;

  // --- Tableaux ---
  final int? minItems;
  final int? maxItems;
  final bool? uniqueItems;
  final Map<String, Object?>? contains;
  final int? minContains;
  final int? maxContains;
  final List<Map<String, Object?>> prefixItems;

  // --- Sous-objets ---
  final int? minProperties;
  final int? maxProperties;
  final Object? additionalProperties; // bool | Map<String, Object?> | null
  final Map<String, Object?>? patternProperties;
  final Map<String, Object?>? propertyNames;
  final Map<String, List<String>>? dependentRequired;
  final Map<String, Object?>? dependentSchemas;

  // --- Générique & métadonnées ---
  final bool hasConst;
  final Object? constValue;
  final List<Object?> examples;
  final bool? readOnly;
  final bool? writeOnly;
  final bool? deprecated;
  final String? title;
  final String? comment;

  // --- Composition & conditionnels ---
  final List<Map<String, Object?>> oneOf;
  final List<Map<String, Object?>> anyOf;
  final List<Map<String, Object?>> allOf;
  final Map<String, Object?>? not;
  final Map<String, Object?>? ifSchema;
  final Map<String, Object?>? thenSchema;
  final Map<String, Object?>? elseSchema;

  // --- Extensions & mots-clés additionnels ---
  final Map<String, Object?> extraKeywords;

  /// Libellés lisibles associés aux choix d'une énumération (`x-enumNames`).
  List<String> get enumNames {
    final raw = extraKeywords['x-enumNames'];
    if (raw is! List) return const <String>[];
    return List<String>.unmodifiable([for (final item in raw) '$item']);
  }

  /// Descriptifs associés aux choix d'une énumération (`x-enumDescriptions`).
  List<String> get enumDescriptions {
    final raw = extraKeywords['x-enumDescriptions'];
    if (raw is! List) return const <String>[];
    return List<String>.unmodifiable([for (final item in raw) '$item']);
  }

  /// Masque de saisie/affichage `PatternMask` (`x-mask`), ou `null`.
  String? get xMask {
    final raw = extraKeywords['x-mask'];
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Indique si l'attribut est indexable/recherchable (`x-searchable`), ou `null`.
  bool? get xSearchable {
    final raw = extraKeywords['x-searchable'];
    return raw is bool ? raw : null;
  }

  /// Indique si l'attribut doit être indexé en base de données (`x-database-index`), ou `null`.
  bool? get xDatabaseIndex {
    final raw = extraKeywords['x-database-index'];
    return raw is bool ? raw : null;
  }

  /// Vrai lorsqu'aucune contrainte ni métadonnée n'est renseignée.
  bool get isEmpty =>
      minimum == null &&
      maximum == null &&
      exclusiveMinimum == null &&
      exclusiveMaximum == null &&
      multipleOf == null &&
      minLength == null &&
      maxLength == null &&
      (pattern == null || pattern!.isEmpty) &&
      (format == null || format!.isEmpty) &&
      (contentMediaType == null || contentMediaType!.isEmpty) &&
      (contentEncoding == null || contentEncoding!.isEmpty) &&
      minItems == null &&
      maxItems == null &&
      uniqueItems == null &&
      contains == null &&
      minContains == null &&
      maxContains == null &&
      prefixItems.isEmpty &&
      minProperties == null &&
      maxProperties == null &&
      additionalProperties == null &&
      patternProperties == null &&
      propertyNames == null &&
      dependentRequired == null &&
      dependentSchemas == null &&
      !hasConst &&
      examples.isEmpty &&
      readOnly == null &&
      writeOnly == null &&
      deprecated == null &&
      (title == null || title!.isEmpty) &&
      (comment == null || comment!.isEmpty) &&
      oneOf.isEmpty &&
      anyOf.isEmpty &&
      allOf.isEmpty &&
      not == null &&
      ifSchema == null &&
      thenSchema == null &&
      elseSchema == null &&
      extraKeywords.isEmpty;

  /// Vrai si au moins une contrainte est définie.
  bool get isNotEmpty => !isEmpty;

  /// Valide la cohérence intrinsèque et la conformité JSON Schema via [JsonSchemaValidator].
  void validate() {
    if (minimum != null && (!minimum!.isFinite)) {
      throw const FormatException('minimum doit être un nombre fini.');
    }
    if (maximum != null && (!maximum!.isFinite)) {
      throw const FormatException('maximum doit être un nombre fini.');
    }
    if (minimum != null && maximum != null && minimum! > maximum!) {
      throw FormatException(
        'minimum ($minimum) ne peut pas dépasser maximum ($maximum).',
      );
    }
    if (exclusiveMinimum != null && (!exclusiveMinimum!.isFinite)) {
      throw const FormatException('exclusiveMinimum doit être un nombre fini.');
    }
    if (exclusiveMaximum != null && (!exclusiveMaximum!.isFinite)) {
      throw const FormatException('exclusiveMaximum doit être un nombre fini.');
    }
    if (exclusiveMinimum != null &&
        exclusiveMaximum != null &&
        exclusiveMinimum! >= exclusiveMaximum!) {
      throw FormatException(
        'exclusiveMinimum ($exclusiveMinimum) doit être strictement inférieur à exclusiveMaximum ($exclusiveMaximum).',
      );
    }
    if (multipleOf != null && (!multipleOf!.isFinite || multipleOf! <= 0)) {
      throw FormatException(
        'multipleOf ($multipleOf) doit être strictement supérieur à 0.',
      );
    }
    if (minLength != null && minLength! < 0) {
      throw FormatException('minLength ($minLength) doit être >= 0.');
    }
    if (maxLength != null && maxLength! < 0) {
      throw FormatException('maxLength ($maxLength) doit être >= 0.');
    }
    if (minLength != null && maxLength != null && minLength! > maxLength!) {
      throw FormatException(
        'minLength ($minLength) ne peut pas dépasser maxLength ($maxLength).',
      );
    }
    if (pattern != null && pattern!.isNotEmpty) {
      try {
        RegExp(pattern!);
      } on FormatException catch (e) {
        throw FormatException('Expression régulière "pattern" invalide : ${e.message}');
      }
    }
    if (minItems != null && minItems! < 0) {
      throw FormatException('minItems ($minItems) doit être >= 0.');
    }
    if (maxItems != null && maxItems! < 0) {
      throw FormatException('maxItems ($maxItems) doit être >= 0.');
    }
    if (minItems != null && maxItems != null && minItems! > maxItems!) {
      throw FormatException(
        'minItems ($minItems) ne peut pas dépasser maxItems ($maxItems).',
      );
    }
    if (minContains != null && minContains! < 0) {
      throw FormatException('minContains ($minContains) doit être >= 0.');
    }
    if (maxContains != null && maxContains! < 0) {
      throw FormatException('maxContains ($maxContains) doit être >= 0.');
    }
    if (minContains != null &&
        maxContains != null &&
        minContains! > maxContains!) {
      throw FormatException(
        'minContains ($minContains) ne peut pas dépasser maxContains ($maxContains).',
      );
    }
    if (minProperties != null && minProperties! < 0) {
      throw FormatException('minProperties ($minProperties) doit être >= 0.');
    }
    if (maxProperties != null && maxProperties! < 0) {
      throw FormatException('maxProperties ($maxProperties) doit être >= 0.');
    }
    if (minProperties != null &&
        maxProperties != null &&
        minProperties! > maxProperties!) {
      throw FormatException(
        'minProperties ($minProperties) ne peut pas dépasser maxProperties ($maxProperties).',
      );
    }

    if (extraKeywords.containsKey('x-searchable') &&
        extraKeywords['x-searchable'] is! bool) {
      throw const FormatException(
        'Mot-clé "x-searchable" invalide : booléen (true/false) attendu.',
      );
    }
    if (extraKeywords.containsKey('x-database-index') &&
        extraKeywords['x-database-index'] is! bool) {
      throw const FormatException(
        'Mot-clé "x-database-index" invalide : booléen (true/false) attendu.',
      );
    }

    final map = toSchemaMap();
    if (map.isNotEmpty) {
      JsonSchemaValidator.validateSchemaDefinition(map);
    }
  }

  /// Exporte l'ensemble des mots-clés actifs sous forme de fragment JSON Schema Draft 2020-12.
  Map<String, Object?> toSchemaMap() {
    final map = <String, Object?>{
      if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
      if (comment != null && comment!.trim().isNotEmpty)
        r'$comment': comment!.trim(),
      'minimum': ?minimum,
      'maximum': ?maximum,
      'exclusiveMinimum': ?exclusiveMinimum,
      'exclusiveMaximum': ?exclusiveMaximum,
      'multipleOf': ?multipleOf,
      'minLength': ?minLength,
      'maxLength': ?maxLength,
      if (pattern != null && pattern!.isNotEmpty) 'pattern': pattern,
      if (format != null && format!.trim().isNotEmpty) 'format': format!.trim(),
      if (contentMediaType != null && contentMediaType!.trim().isNotEmpty)
        'contentMediaType': contentMediaType!.trim(),
      if (contentEncoding != null && contentEncoding!.trim().isNotEmpty)
        'contentEncoding': contentEncoding!.trim(),
      'minItems': ?minItems,
      'maxItems': ?maxItems,
      'uniqueItems': ?uniqueItems,
      'contains': ?contains,
      'minContains': ?minContains,
      'maxContains': ?maxContains,
      if (prefixItems.isNotEmpty) 'prefixItems': prefixItems,
      'minProperties': ?minProperties,
      'maxProperties': ?maxProperties,
      'additionalProperties': ?additionalProperties,
      if (patternProperties != null && patternProperties!.isNotEmpty)
        'patternProperties': patternProperties,
      if (propertyNames != null && propertyNames!.isNotEmpty)
        'propertyNames': propertyNames,
      if (dependentRequired != null && dependentRequired!.isNotEmpty)
        'dependentRequired': dependentRequired,
      if (dependentSchemas != null && dependentSchemas!.isNotEmpty)
        'dependentSchemas': dependentSchemas,
      if (hasConst) 'const': constValue,
      if (examples.isNotEmpty) 'examples': examples,
      'readOnly': ?readOnly,
      'writeOnly': ?writeOnly,
      'deprecated': ?deprecated,
      if (oneOf.isNotEmpty) 'oneOf': oneOf,
      if (anyOf.isNotEmpty) 'anyOf': anyOf,
      if (allOf.isNotEmpty) 'allOf': allOf,
      'not': ?not,
      if (ifSchema != null) 'if': ifSchema,
      if (thenSchema != null) 'then': thenSchema,
      if (elseSchema != null) 'else': elseSchema,
    };
    for (final entry in extraKeywords.entries) {
      map.putIfAbsent(entry.key, () => entry.value);
    }
    return map;
  }

  /// Sérialise en JSON (identique à [toSchemaMap]).
  Map<String, Object?> toJson() => toSchemaMap();

  /// Désérialise un [JsonSchemaConstraints] depuis un objet JSON tolérant.
  factory JsonSchemaConstraints.fromJson(Object? raw) {
    if (raw == null) return JsonSchemaConstraints.empty;
    if (raw is! Map) {
      throw const FormatException(
        'JsonSchemaConstraints doit être un objet JSON.',
      );
    }
    final map = <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };

    var minimum = _asNum(map['minimum']);
    var maximum = _asNum(map['maximum']);
    num? exclusiveMinimum = _asNum(map['exclusiveMinimum']);
    num? exclusiveMaximum = _asNum(map['exclusiveMaximum']);
    // Compatibilité Draft-07 où exclusiveMinimum/Maximum peut être un booléen.
    if (map['exclusiveMinimum'] == true && minimum != null) {
      exclusiveMinimum = minimum;
      minimum = null;
    }
    if (map['exclusiveMaximum'] == true && maximum != null) {
      exclusiveMaximum = maximum;
      maximum = null;
    }

    final extra = <String, Object?>{};
    for (final entry in map.entries) {
      if (!knownKeywords.contains(entry.key) &&
          entry.key.startsWith('x-') ||
          const {
            'unevaluatedProperties',
            'unevaluatedItems',
            'propertyDependencies',
            'contentSchema',
            'dependencies',
            'additionalItems',
          }.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }

    final constraints = JsonSchemaConstraints(
      minimum: minimum,
      maximum: maximum,
      exclusiveMinimum: exclusiveMinimum,
      exclusiveMaximum: exclusiveMaximum,
      multipleOf: _asNum(map['multipleOf']),
      minLength: _asInt(map['minLength']),
      maxLength: _asInt(map['maxLength']),
      pattern: _asString(map['pattern']),
      format: _asString(map['format']),
      contentMediaType: _asString(map['contentMediaType']),
      contentEncoding: _asString(map['contentEncoding']),
      minItems: _asInt(map['minItems']),
      maxItems: _asInt(map['maxItems']),
      uniqueItems: _asBool(map['uniqueItems']),
      contains: _asSchemaMap(map['contains']),
      minContains: _asInt(map['minContains']),
      maxContains: _asInt(map['maxContains']),
      prefixItems: _asSchemaList(map['prefixItems']),
      minProperties: _asInt(map['minProperties']),
      maxProperties: _asInt(map['maxProperties']),
      additionalProperties: _parseAdditionalProperties(
        map['additionalProperties'],
      ),
      patternProperties: _asSchemaMap(map['patternProperties']),
      propertyNames: _asSchemaMap(map['propertyNames']),
      dependentRequired: _asDependentRequired(map['dependentRequired']),
      dependentSchemas: _asSchemaMap(map['dependentSchemas']),
      hasConst: map.containsKey('const'),
      constValue: map['const'],
      examples: map['examples'] is List ? map['examples'] as List<Object?> : null,
      readOnly: _asBool(map['readOnly']),
      writeOnly: _asBool(map['writeOnly']),
      deprecated: _asBool(map['deprecated']),
      title: _asString(map['title']),
      comment: _asString(map[r'$comment']),
      oneOf: _asSchemaList(map['oneOf']),
      anyOf: _asSchemaList(map['anyOf']),
      allOf: _asSchemaList(map['allOf']),
      not: _asSchemaMap(map['not']),
      ifSchema: _asSchemaMap(map['if']),
      thenSchema: _asSchemaMap(map['then']),
      elseSchema: _asSchemaMap(map['else']),
      extraKeywords: extra.isEmpty ? null : extra,
    );
    constraints.validate();
    return constraints;
  }

  /// Retourne la liste de puces lisibles décrivant les contraintes actives.
  List<String> describeBadges() {
    final badges = <String>[];
    if (minimum != null) badges.add('min: $minimum');
    if (exclusiveMinimum != null) badges.add('> $exclusiveMinimum');
    if (maximum != null) badges.add('max: $maximum');
    if (exclusiveMaximum != null) badges.add('< $exclusiveMaximum');
    if (multipleOf != null) badges.add('multiple de $multipleOf');
    if (minLength != null) badges.add('minLen: $minLength');
    if (maxLength != null) badges.add('maxLen: $maxLength');
    if (format != null && format!.isNotEmpty) badges.add('format: $format');
    if (pattern != null && pattern!.isNotEmpty) badges.add('regex: $pattern');
    if (contentMediaType != null && contentMediaType!.isNotEmpty) {
      badges.add('media: $contentMediaType');
    }
    if (contentEncoding != null && contentEncoding!.isNotEmpty) {
      badges.add('enc: $contentEncoding');
    }
    if (minItems != null) badges.add('minItems: $minItems');
    if (maxItems != null) badges.add('maxItems: $maxItems');
    if (uniqueItems == true) badges.add('uniqueItems');
    if (contains != null) badges.add('contains');
    if (minContains != null) badges.add('minContains: $minContains');
    if (maxContains != null) badges.add('maxContains: $maxContains');
    if (prefixItems.isNotEmpty) badges.add('prefixItems(${prefixItems.length})');
    if (minProperties != null) badges.add('minProps: $minProperties');
    if (maxProperties != null) badges.add('maxProps: $maxProperties');
    if (additionalProperties != null) {
      badges.add(
        additionalProperties == false
            ? 'additionalProps: false'
            : 'additionalProps',
      );
    }
    if (patternProperties != null && patternProperties!.isNotEmpty) {
      badges.add('patternProps(${patternProperties!.length})');
    }
    if (propertyNames != null) badges.add('propertyNames');
    if (dependentRequired != null && dependentRequired!.isNotEmpty) {
      badges.add('dependentRequired');
    }
    if (dependentSchemas != null && dependentSchemas!.isNotEmpty) {
      badges.add('dependentSchemas');
    }
    if (hasConst) badges.add('const: $constValue');
    if (readOnly == true) badges.add('readOnly');
    if (writeOnly == true) badges.add('writeOnly');
    if (deprecated == true) badges.add('deprecated');
    if (oneOf.isNotEmpty) badges.add('oneOf(${oneOf.length})');
    if (anyOf.isNotEmpty) badges.add('anyOf(${anyOf.length})');
    if (allOf.isNotEmpty) badges.add('allOf(${allOf.length})');
    if (not != null) badges.add('not');
    if (ifSchema != null) badges.add('if/then/else');
    for (final key in extraKeywords.keys) {
      if (key == 'x-enumNames' || key == 'x-enumDescriptions') {
        final raw = extraKeywords[key];
        if (raw is List) {
          badges.add('$key(${raw.length})');
          continue;
        }
      }
      badges.add('$key: ${extraKeywords[key]}');
    }
    return badges;
  }

  /// Retourne une description compacte en une ligne des contraintes actives.
  String formatSummary() => describeBadges().join(' · ');

  /// Copie modifiée.
  JsonSchemaConstraints copyWith({
    num? minimum,
    bool clearMinimum = false,
    num? maximum,
    bool clearMaximum = false,
    num? exclusiveMinimum,
    bool clearExclusiveMinimum = false,
    num? exclusiveMaximum,
    bool clearExclusiveMaximum = false,
    num? multipleOf,
    bool clearMultipleOf = false,
    int? minLength,
    bool clearMinLength = false,
    int? maxLength,
    bool clearMaxLength = false,
    String? pattern,
    bool clearPattern = false,
    String? format,
    bool clearFormat = false,
    String? contentMediaType,
    bool clearContentMediaType = false,
    String? contentEncoding,
    bool clearContentEncoding = false,
    int? minItems,
    bool clearMinItems = false,
    int? maxItems,
    bool clearMaxItems = false,
    bool? uniqueItems,
    bool clearUniqueItems = false,
    Map<String, Object?>? contains,
    bool clearContains = false,
    int? minContains,
    bool clearMinContains = false,
    int? maxContains,
    bool clearMaxContains = false,
    List<Map<String, Object?>>? prefixItems,
    int? minProperties,
    bool clearMinProperties = false,
    int? maxProperties,
    bool clearMaxProperties = false,
    Object? additionalProperties,
    bool clearAdditionalProperties = false,
    Map<String, Object?>? patternProperties,
    bool clearPatternProperties = false,
    Map<String, Object?>? propertyNames,
    bool clearPropertyNames = false,
    Map<String, List<String>>? dependentRequired,
    bool clearDependentRequired = false,
    Map<String, Object?>? dependentSchemas,
    bool clearDependentSchemas = false,
    bool? hasConst,
    Object? constValue,
    bool clearConst = false,
    List<Object?>? examples,
    bool? readOnly,
    bool clearReadOnly = false,
    bool? writeOnly,
    bool clearWriteOnly = false,
    bool? deprecated,
    bool clearDeprecated = false,
    String? title,
    bool clearTitle = false,
    String? comment,
    bool clearComment = false,
    List<Map<String, Object?>>? oneOf,
    List<Map<String, Object?>>? anyOf,
    List<Map<String, Object?>>? allOf,
    Map<String, Object?>? not,
    bool clearNot = false,
    Map<String, Object?>? ifSchema,
    bool clearIfSchema = false,
    Map<String, Object?>? thenSchema,
    bool clearThenSchema = false,
    Map<String, Object?>? elseSchema,
    bool clearElseSchema = false,
    Map<String, Object?>? extraKeywords,
  }) => JsonSchemaConstraints(
    minimum: clearMinimum ? null : (minimum ?? this.minimum),
    maximum: clearMaximum ? null : (maximum ?? this.maximum),
    exclusiveMinimum: clearExclusiveMinimum
        ? null
        : (exclusiveMinimum ?? this.exclusiveMinimum),
    exclusiveMaximum: clearExclusiveMaximum
        ? null
        : (exclusiveMaximum ?? this.exclusiveMaximum),
    multipleOf: clearMultipleOf ? null : (multipleOf ?? this.multipleOf),
    minLength: clearMinLength ? null : (minLength ?? this.minLength),
    maxLength: clearMaxLength ? null : (maxLength ?? this.maxLength),
    pattern: clearPattern ? null : (pattern ?? this.pattern),
    format: clearFormat ? null : (format ?? this.format),
    contentMediaType: clearContentMediaType
        ? null
        : (contentMediaType ?? this.contentMediaType),
    contentEncoding: clearContentEncoding
        ? null
        : (contentEncoding ?? this.contentEncoding),
    minItems: clearMinItems ? null : (minItems ?? this.minItems),
    maxItems: clearMaxItems ? null : (maxItems ?? this.maxItems),
    uniqueItems: clearUniqueItems ? null : (uniqueItems ?? this.uniqueItems),
    contains: clearContains ? null : (contains ?? this.contains),
    minContains: clearMinContains ? null : (minContains ?? this.minContains),
    maxContains: clearMaxContains ? null : (maxContains ?? this.maxContains),
    prefixItems: prefixItems ?? this.prefixItems,
    minProperties: clearMinProperties
        ? null
        : (minProperties ?? this.minProperties),
    maxProperties: clearMaxProperties
        ? null
        : (maxProperties ?? this.maxProperties),
    additionalProperties: clearAdditionalProperties
        ? null
        : (additionalProperties ?? this.additionalProperties),
    patternProperties: clearPatternProperties
        ? null
        : (patternProperties ?? this.patternProperties),
    propertyNames: clearPropertyNames
        ? null
        : (propertyNames ?? this.propertyNames),
    dependentRequired: clearDependentRequired
        ? null
        : (dependentRequired ?? this.dependentRequired),
    dependentSchemas: clearDependentSchemas
        ? null
        : (dependentSchemas ?? this.dependentSchemas),
    hasConst: clearConst ? false : (hasConst ?? this.hasConst),
    constValue: clearConst ? null : (constValue ?? this.constValue),
    examples: examples ?? this.examples,
    readOnly: clearReadOnly ? null : (readOnly ?? this.readOnly),
    writeOnly: clearWriteOnly ? null : (writeOnly ?? this.writeOnly),
    deprecated: clearDeprecated ? null : (deprecated ?? this.deprecated),
    title: clearTitle ? null : (title ?? this.title),
    comment: clearComment ? null : (comment ?? this.comment),
    oneOf: oneOf ?? this.oneOf,
    anyOf: anyOf ?? this.anyOf,
    allOf: allOf ?? this.allOf,
    not: clearNot ? null : (not ?? this.not),
    ifSchema: clearIfSchema ? null : (ifSchema ?? this.ifSchema),
    thenSchema: clearThenSchema ? null : (thenSchema ?? this.thenSchema),
    elseSchema: clearElseSchema ? null : (elseSchema ?? this.elseSchema),
    extraKeywords: extraKeywords ?? this.extraKeywords,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! JsonSchemaConstraints) return false;
    return jsonEncode(toSchemaMap()) == jsonEncode(other.toSchemaMap());
  }

  @override
  int get hashCode => jsonEncode(toSchemaMap()).hashCode;

  static num? _asNum(Object? raw) {
    if (raw is num && raw.isFinite) return raw;
    if (raw is String) return num.tryParse(raw.trim());
    return null;
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num && raw.isFinite && raw == raw.toInt()) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static bool? _asBool(Object? raw) => raw is bool ? raw : null;

  static String? _asString(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, Object?>? _asSchemaMap(Object? raw) {
    if (raw is! Map) return null;
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static List<Map<String, Object?>>? _asSchemaList(Object? raw) {
    if (raw is! List) return null;
    final out = <Map<String, Object?>>[];
    for (final item in raw) {
      final m = _asSchemaMap(item);
      if (m != null) out.add(m);
    }
    return out;
  }

  static Object? _parseAdditionalProperties(Object? raw) {
    if (raw is bool) return raw;
    return _asSchemaMap(raw);
  }

  static Map<String, List<String>>? _asDependentRequired(Object? raw) {
    if (raw is! Map) return null;
    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! List) continue;
      result[entry.key as String] = [
        for (final item in entry.value as List)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    }
    return result;
  }

  static Object? _deepFreezeValue(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final e in value.entries) e.key.toString(): _deepFreezeValue(e.value),
      });
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_deepFreezeValue));
    }
    return value;
  }

  static Map<String, Object?>? _freezeSchemaMap(Map<String, Object?>? raw) {
    if (raw == null) return null;
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final e in raw.entries) e.key: _deepFreezeValue(e.value),
    });
  }

  static List<Map<String, Object?>> _freezeSchemaList(
    List<Map<String, Object?>>? raw,
  ) {
    if (raw == null) return const <Map<String, Object?>>[];
    return List<Map<String, Object?>>.unmodifiable([
      for (final item in raw) _freezeSchemaMap(item)!,
    ]);
  }

  static Object? _freezeAdditionalProperties(Object? raw) {
    if (raw is bool) return raw;
    if (raw is Map<String, Object?>) return _freezeSchemaMap(raw);
    if (raw is Map) {
      return _freezeSchemaMap(<String, Object?>{
        for (final e in raw.entries) e.key.toString(): e.value,
      });
    }
    return null;
  }

  static Map<String, List<String>>? _freezeDependentRequired(
    Map<String, List<String>>? raw,
  ) {
    if (raw == null) return null;
    return Map<String, List<String>>.unmodifiable(<String, List<String>>{
      for (final e in raw.entries)
        e.key: List<String>.unmodifiable(e.value),
    });
  }
}
