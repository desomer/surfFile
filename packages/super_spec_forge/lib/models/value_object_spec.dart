/// Modèles immuables du catalogue des Value Objects en Architecture Hexagonale
/// ([ValueObjectSpec], [ValueObjectKind], [ValueObjectScope], [ValueObjectExample],
/// [ValueObjectPresets]).
library;

import 'package:flutter/foundation.dart';

import 'business_object_spec.dart';
import 'json_schema_constraints.dart';

/// Forme structurelle d'un Value Object hexagonal.
enum ValueObjectKind {
  /// Value Object atomique encapsulant une unique valeur primitive validée.
  scalar('Scalaire', 'Valeur primitive encapsulée et auto-validée'),

  /// Value Object composite regroupant plusieurs champs immuables cohérents.
  composite('Composite', 'Structure immuable multi-champs avec règles inter-champs');

  /// Construit une forme de Value Object.
  const ValueObjectKind(this.label, this.description);

  /// Libellé court affiché dans les filtres et badges.
  final String label;

  /// Explication courte affichée dans l'éditeur.
  final String description;

  /// Désérialise une forme de Value Object.
  static ValueObjectKind fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      if (norm == 'composite' ||
          norm == 'struct' ||
          norm == 'object' ||
          norm == 'multi' ||
          norm == 'multi_fields') {
        return ValueObjectKind.composite;
      }
      if (norm == 'scalar' ||
          norm == 'atomic' ||
          norm == 'primitive' ||
          norm == 'scalaire') {
        return ValueObjectKind.scalar;
      }
    }
    return ValueObjectKind.scalar;
  }
}

/// Portée d'appartenance d'un Value Object dans le workspace.
enum ValueObjectScope {
  /// Shared Kernel transverse partagé entre tous les domaines du workspace.
  shared('Shared Kernel', 'Partagé sur tout le workspace'),

  /// Value Object propre à un domaine fonctionnel (Bounded Context).
  domain('Domaine', 'Spécifique au domaine fonctionnel');

  /// Construit une portée de Value Object.
  const ValueObjectScope(this.label, this.description);

  /// Libellé affiché dans les badges et sélecteurs.
  final String label;

  /// Description concise de la portée.
  final String description;

  /// Désérialise une portée.
  static ValueObjectScope fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      if (norm == 'shared' ||
          norm == 'shared_kernel' ||
          norm == 'sharedkernel' ||
          norm == 'workspace') {
        return ValueObjectScope.shared;
      }
    }
    return ValueObjectScope.domain;
  }
}

/// Exemple valide ou contre-exemple invalide d'un [ValueObjectSpec],
/// utilisé pour la documentation métier et les matrices de tests TDD.
@immutable
class ValueObjectExample {
  /// Crée un exemple ou contre-exemple immuable.
  const ValueObjectExample({
    required this.id,
    required this.value,
    this.isValid = true,
    this.reason = '',
  });

  /// Identifiant stable de l'exemple.
  final String id;

  /// Valeur illustrée (scalaire lisible ou JSON compact pour un composite).
  final String value;

  /// `true` pour un cas nominal/limite valide, `false` pour un contre-exemple rejeté.
  final bool isValid;

  /// Explication métier ou règle violée (attendue pour les cas invalides).
  final String reason;

  /// Vérifie les invariants de l'exemple.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ValueObjectExample.id requis.');
    }
    if (value.trim().isEmpty && isValid) {
      throw const FormatException(
        'Un exemple valide de Value Object ne peut pas être vide.',
      );
    }
  }

  /// Copie modifiée.
  ValueObjectExample copyWith({
    String? id,
    String? value,
    bool? isValid,
    String? reason,
  }) => ValueObjectExample(
    id: id ?? this.id,
    value: value ?? this.value,
    isValid: isValid ?? this.isValid,
    reason: reason ?? this.reason,
  );

  /// Sérialise l'exemple en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'value': value,
    'isValid': isValid,
    if (reason.trim().isNotEmpty) 'reason': reason.trim(),
  };

  /// Désérialise un exemple depuis JSON (objet ou chaîne simple).
  factory ValueObjectExample.fromJson(
    Object? raw, {
    int fallbackIndex = 0,
    bool defaultValid = true,
  }) {
    if (raw is String) {
      final cleaned = raw.trim();
      final item = ValueObjectExample(
        id: 'voex_${defaultValid ? 'ok' : 'ko'}_$fallbackIndex',
        value: cleaned,
        isValid: defaultValid,
      );
      item.validate();
      return item;
    }
    if (raw is! Map) {
      throw const FormatException('ValueObjectExample invalide.');
    }
    final rawValue = raw['value'] == null ? '' : '${raw['value']}';
    final isValid = raw['isValid'] is bool
        ? raw['isValid'] as bool
        : (raw['valid'] is bool ? raw['valid'] as bool : defaultValid);
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = ValueObjectExample(
      id: rawId.isEmpty
          ? 'voex_${isValid ? 'ok' : 'ko'}_${fallbackIndex}_${rawValue.hashCode.abs()}'
          : rawId,
      value: rawValue,
      isValid: isValid,
      reason: (raw['reason'] as String? ?? raw['expectedError'] as String? ?? '')
          .trim(),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueObjectExample &&
          other.id == id &&
          other.value == value &&
          other.isValid == isValid &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(id, value, isValid, reason);
}

/// Spécification immuable d'un Value Object DDD / Architecture Hexagonale.
@immutable
class ValueObjectSpec {
  /// Crée une spécification de Value Object immuable.
  ValueObjectSpec({
    required this.id,
    required this.technicalName,
    required this.name,
    this.description = '',
    this.category = 'Métier',
    this.version = '1.0.0',
    this.kind = ValueObjectKind.scalar,
    this.primitiveType = BusinessAttributeType.string,
    List<String> enumValues = const <String>[],
    JsonSchemaConstraints? schemaConstraints,
    List<String> normalizationRules = const <String>[],
    this.constraints = '',
    List<BusinessAttribute> fields = const <BusinessAttribute>[],
    List<String> crossFieldRules = const <String>[],
    List<ValueObjectExample> examples = const <ValueObjectExample>[],
  }) : enumValues = List<String>.unmodifiable(enumValues),
       schemaConstraints = schemaConstraints ?? JsonSchemaConstraints.empty,
       normalizationRules = List<String>.unmodifiable(normalizationRules),
       fields = List<BusinessAttribute>.unmodifiable(fields),
       crossFieldRules = List<String>.unmodifiable(crossFieldRules),
       examples = List<ValueObjectExample>.unmodifiable(examples);

  /// Motif de version sémantique `x.y.z`.
  static final RegExp versionPattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  );

  /// Types primitifs autorisés pour un Value Object scalaire.
  static const List<BusinessAttributeType> allowedScalarTypes =
      <BusinessAttributeType>[
        BusinessAttributeType.string,
        BusinessAttributeType.integer,
        BusinessAttributeType.number,
        BusinessAttributeType.boolean,
        BusinessAttributeType.date,
        BusinessAttributeType.datetime,
        BusinessAttributeType.uuid,
        BusinessAttributeType.email,
        BusinessAttributeType.url,
        BusinessAttributeType.enumeration,
      ];

  /// Catégories standards proposées dans l'interface.
  static const List<String> standardCategories = <String>[
    'Identité',
    'Contact',
    'Finance',
    'Temps',
    'Localisation',
    'Mesure',
    'Métier',
  ];

  /// Identifiant technique stable.
  final String id;

  /// Nom technique PascalCase ASCII utilisé dans le DSL YAML Light et le code généré
  /// (ex. `EmailAddress`, `Money`, `Iban`, `DateRange`).
  final String technicalName;

  /// Libellé métier lisible en français (ex. `Adresse email`, `Montant monétaire`).
  final String name;

  /// Rôle métier et sémantique d'égalité structurelle / immuabilité.
  final String description;

  /// Catégorie fonctionnelle de classement.
  final String category;

  /// Version sémantique (`x.y.z`).
  final String version;

  /// Forme du Value Object (`scalar` ou `composite`).
  final ValueObjectKind kind;

  /// Type primitif encapsulé lorsque [kind] vaut [ValueObjectKind.scalar].
  final BusinessAttributeType primitiveType;

  /// Valeurs d'énumération lorsque [primitiveType] vaut [BusinessAttributeType.enumeration].
  final List<String> enumValues;

  /// Contraintes JSON Schema Draft 2020-12 appliquées au scalaire encapsulé.
  final JsonSchemaConstraints schemaConstraints;

  /// Règles de normalisation appliquées avant validation (ex. `trim`, `lowercase`, `removeSpaces`).
  final List<String> normalizationRules;

  /// Résumé libre complémentaire des contraintes / invariants.
  final String constraints;

  /// Champs immuables lorsque [kind] vaut [ValueObjectKind.composite].
  final List<BusinessAttribute> fields;

  /// Règles métier transverses entre champs d'un composite (ex. `startDate <= endDate`).
  final List<String> crossFieldRules;

  /// Exemples valides et contre-exemples invalides (documentation + matrice TDD).
  final List<ValueObjectExample> examples;

  /// Indique si le Value Object est atomique (scalaire).
  bool get isScalar => kind == ValueObjectKind.scalar;

  /// Indique si le Value Object est composite (multi-champs).
  bool get isComposite => kind == ValueObjectKind.composite;

  /// Exemples valides.
  List<ValueObjectExample> get validExamples =>
      examples.where((e) => e.isValid).toList(growable: false);

  /// Contre-exemples invalides.
  List<ValueObjectExample> get invalidExamples =>
      examples.where((e) => !e.isValid).toList(growable: false);

  /// Identifiants des Value Objects directement référencés par les champs de ce composite.
  Set<String> get referencedValueObjectIds {
    if (!isComposite) return const <String>{};
    final out = <String>{};
    void collect(List<BusinessAttribute> attrs) {
      for (final a in attrs) {
        if (a.type == BusinessAttributeType.valueObject &&
            a.valueObjectId.trim().isNotEmpty) {
          out.add(a.valueObjectId.trim());
        }
        if (a.children.isNotEmpty) collect(a.children);
      }
    }

    collect(fields);
    return out;
  }

  /// Vérifie les invariants du Value Object.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ValueObjectSpec.id ne peut pas être vide.');
    }
    if (technicalName.trim().isEmpty ||
        !BusinessAttribute.isValidDslIdentifier(technicalName)) {
      throw FormatException(
        'Nom technique de Value Object invalide : « $technicalName » '
        '(attendu : identifiant ASCII sans accent ni espace, ex. EmailAddress).',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException('Le libellé du Value Object est requis.');
    }
    if (!versionPattern.hasMatch(version)) {
      throw FormatException(
        'La version du Value Object « $technicalName » doit être au format x.y.z.',
      );
    }
    if (isScalar) {
      if (!allowedScalarTypes.contains(primitiveType)) {
        throw FormatException(
          'Type primitif « ${primitiveType.dslKeyword} » non autorisé pour le '
          'Value Object scalaire « $technicalName ».',
        );
      }
      schemaConstraints.validate();
    } else {
      if (fields.isEmpty) {
        throw FormatException(
          'Le Value Object composite « $technicalName » doit contenir au moins un champ.',
        );
      }
      final seenFieldNames = <String>{};
      for (final field in fields) {
        field.validate();
        if (!seenFieldNames.add(field.name)) {
          throw FormatException(
            'Champ dupliqué « ${field.name} » dans le Value Object « $technicalName ».',
          );
        }
      }
    }
    final seenExampleIds = <String>{};
    for (final ex in examples) {
      ex.validate();
      if (!seenExampleIds.add(ex.id)) {
        throw FormatException(
          'Identifiant d’exemple dupliqué « ${ex.id} » dans « $technicalName ».',
        );
      }
    }
  }

  /// Vérifie l'absence de cycles de composition dans un ensemble de Value Objects.
  static void validateNoCycles(Iterable<ValueObjectSpec> all) {
    final byId = <String, ValueObjectSpec>{
      for (final vo in all) vo.id: vo,
    };
    final byTech = <String, ValueObjectSpec>{
      for (final vo in all) vo.technicalName.toLowerCase(): vo,
    };
    final visiting = <String>{};
    final visited = <String>{};

    void dfs(ValueObjectSpec current) {
      if (visited.contains(current.id)) return;
      if (!visiting.add(current.id)) {
        throw FormatException(
          'Référence circulaire détectée sur le Value Object composite « ${current.technicalName} ».',
        );
      }
      for (final ref in current.referencedValueObjectIds) {
        final target = byId[ref] ?? byTech[ref.toLowerCase()];
        if (target != null) {
          dfs(target);
        }
      }
      visiting.remove(current.id);
      visited.add(current.id);
    }

    for (final vo in all) {
      dfs(vo);
    }
  }

  /// Résumé compact affiché dans les listes et cartes d'aperçu.
  String formatStructureSummary() {
    if (isScalar) {
      final parts = <String>[primitiveType.dslKeyword];
      final scSummary = schemaConstraints.formatSummary();
      if (scSummary.isNotEmpty) parts.add(scSummary);
      if (normalizationRules.isNotEmpty) {
        parts.add('norm: ${normalizationRules.join(', ')}');
      }
      return parts.join(' · ');
    }
    final preview = fields
        .take(4)
        .map((f) => '${f.name}: ${f.type.dslKeyword}${f.required ? '!' : ''}')
        .join(', ');
    final suffix = fields.length > 4 ? ', +${fields.length - 4}' : '';
    return '{ $preview$suffix }';
  }

  /// Copie modifiée.
  ValueObjectSpec copyWith({
    String? id,
    String? technicalName,
    String? name,
    String? description,
    String? category,
    String? version,
    ValueObjectKind? kind,
    BusinessAttributeType? primitiveType,
    List<String>? enumValues,
    JsonSchemaConstraints? schemaConstraints,
    List<String>? normalizationRules,
    String? constraints,
    List<BusinessAttribute>? fields,
    List<String>? crossFieldRules,
    List<ValueObjectExample>? examples,
  }) => ValueObjectSpec(
    id: id ?? this.id,
    technicalName: technicalName ?? this.technicalName,
    name: name ?? this.name,
    description: description ?? this.description,
    category: category ?? this.category,
    version: version ?? this.version,
    kind: kind ?? this.kind,
    primitiveType: primitiveType ?? this.primitiveType,
    enumValues: enumValues ?? this.enumValues,
    schemaConstraints: schemaConstraints ?? this.schemaConstraints,
    normalizationRules: normalizationRules ?? this.normalizationRules,
    constraints: constraints ?? this.constraints,
    fields: fields ?? this.fields,
    crossFieldRules: crossFieldRules ?? this.crossFieldRules,
    examples: examples ?? this.examples,
  );

  /// Sérialise le Value Object en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'technicalName': technicalName,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    if (category.isNotEmpty) 'category': category,
    'version': version,
    'kind': kind.name,
    if (isScalar) 'primitiveType': primitiveType.name,
    if (isScalar && enumValues.isNotEmpty) 'enumValues': enumValues,
    if (isScalar && schemaConstraints.isNotEmpty)
      'schemaConstraints': schemaConstraints.toJson(),
    if (isScalar && normalizationRules.isNotEmpty)
      'normalizationRules': normalizationRules,
    if (constraints.isNotEmpty) 'constraints': constraints,
    if (isComposite) 'fields': [for (final f in fields) f.toJson()],
    if (isComposite && crossFieldRules.isNotEmpty)
      'crossFieldRules': crossFieldRules,
    if (examples.isNotEmpty)
      'examples': [for (final e in examples) e.toJson()],
  };

  /// Désérialise un Value Object depuis JSON.
  factory ValueObjectSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ValueObjectSpec doit être un objet JSON.');
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final rawTech = (raw['technicalName'] as String?)?.trim() ?? '';
    final effectiveTech = rawTech.isNotEmpty
        ? BusinessAttribute.isValidDslIdentifier(rawTech)
              ? rawTech
              : BusinessAttribute.toPascalCaseDslIdentifier(rawTech)
        : BusinessAttribute.toPascalCaseDslIdentifier(
            rawName.isEmpty ? 'ValueObject' : rawName,
          );
    final effectiveName = rawName.isEmpty ? effectiveTech : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawFields = raw['fields'];
    final parsedFields = rawFields is List
        ? [for (final f in rawFields) BusinessAttribute.fromJson(f)]
        : const <BusinessAttribute>[];
    final kind = raw['kind'] != null
        ? ValueObjectKind.fromJson(raw['kind'])
        : (parsedFields.isNotEmpty
              ? ValueObjectKind.composite
              : ValueObjectKind.scalar);

    final rawPrimitive = BusinessAttributeType.fromJson(
      raw['primitiveType'] ?? raw['baseType'] ?? 'string',
    );
    final effectivePrimitive = allowedScalarTypes.contains(rawPrimitive)
        ? rawPrimitive
        : BusinessAttributeType.string;

    final rawVersion = (raw['version'] as String?)?.trim() ?? '';
    final effectiveVersion = versionPattern.hasMatch(rawVersion)
        ? rawVersion
        : '1.0.0';

    final parsedExamples = <ValueObjectExample>[];
    if (raw['examples'] case final List list) {
      for (var i = 0; i < list.length; i++) {
        parsedExamples.add(
          ValueObjectExample.fromJson(list[i], fallbackIndex: i),
        );
      }
    }
    if (raw['validExamples'] case final List list) {
      for (var i = 0; i < list.length; i++) {
        parsedExamples.add(
          ValueObjectExample.fromJson(
            list[i],
            fallbackIndex: parsedExamples.length + i,
            defaultValid: true,
          ),
        );
      }
    }
    if (raw['invalidExamples'] case final List list) {
      for (var i = 0; i < list.length; i++) {
        parsedExamples.add(
          ValueObjectExample.fromJson(
            list[i],
            fallbackIndex: parsedExamples.length + i,
            defaultValid: false,
          ),
        );
      }
    }

    final item = ValueObjectSpec(
      id: rawId.isEmpty ? 'vo_${effectiveTech.toLowerCase()}' : rawId,
      technicalName: effectiveTech,
      name: effectiveName,
      description: (raw['description'] as String?)?.trim() ?? '',
      category: ((raw['category'] as String?)?.trim().isNotEmpty ?? false)
          ? (raw['category'] as String).trim()
          : 'Métier',
      version: effectiveVersion,
      kind: kind,
      primitiveType: effectivePrimitive,
      enumValues: _cleanStringList(raw['enumValues']),
      schemaConstraints: raw['schemaConstraints'] != null
          ? JsonSchemaConstraints.fromJson(raw['schemaConstraints'])
          : JsonSchemaConstraints.empty,
      normalizationRules: _cleanStringList(
        raw['normalizationRules'] ?? raw['normalization'],
      ),
      constraints: (raw['constraints'] as String?)?.trim() ?? '',
      fields: parsedFields,
      crossFieldRules: _cleanStringList(raw['crossFieldRules']),
      examples: parsedExamples,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueObjectSpec &&
          other.id == id &&
          other.technicalName == technicalName &&
          other.name == name &&
          other.description == description &&
          other.category == category &&
          other.version == version &&
          other.kind == kind &&
          other.primitiveType == primitiveType &&
          listEquals(other.enumValues, enumValues) &&
          other.schemaConstraints == schemaConstraints &&
          listEquals(other.normalizationRules, normalizationRules) &&
          other.constraints == constraints &&
          listEquals(other.fields, fields) &&
          listEquals(other.crossFieldRules, crossFieldRules) &&
          listEquals(other.examples, examples);

  @override
  int get hashCode => Object.hash(
    id,
    technicalName,
    name,
    description,
    category,
    version,
    kind,
    primitiveType,
    Object.hashAll(enumValues),
    schemaConstraints,
    Object.hashAll(normalizationRules),
    constraints,
    Object.hashAll(fields),
    Object.hashAll(crossFieldRules),
    Object.hashAll(examples),
  );
}

/// Résolution d'un [ValueObjectSpec] enrichi de sa portée effective ([ValueObjectScope]).
@immutable
class ResolvedValueObject {
  /// Crée une référence résolue avec sa portée.
  const ResolvedValueObject({
    required this.spec,
    required this.scope,
    this.domainId,
  });

  /// Spécification du Value Object.
  final ValueObjectSpec spec;

  /// Portée effective (`shared` ou `domain`).
  final ValueObjectScope scope;

  /// Identifiant du domaine propriétaire lorsque [scope] vaut [ValueObjectScope.domain].
  final String? domainId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedValueObject &&
          other.spec == spec &&
          other.scope == scope &&
          other.domainId == domainId;

  @override
  int get hashCode => Object.hash(spec, scope, domainId);
}

/// Bibliothèque de Value Objects standards prêts à être importés dans le Shared Kernel ou un domaine.
abstract final class ValueObjectPresets {
  /// Catalogue des Value Objects DDD courants.
  static List<ValueObjectSpec> get standardPresets => <ValueObjectSpec>[
    ValueObjectSpec(
      id: 'vo_preset_email_address',
      technicalName: 'EmailAddress',
      name: 'Adresse email',
      description:
          'Adresse courriel normalisée et conforme RFC 5322, immuable et comparée sans sensibilité à la casse.',
      category: 'Contact',
      kind: ValueObjectKind.scalar,
      primitiveType: BusinessAttributeType.email,
      schemaConstraints: JsonSchemaConstraints(
        minLength: 5,
        maxLength: 254,
        format: 'email',
      ),
      normalizationRules: const <String>['trim', 'lowercase'],
      constraints: 'Longueur max 254 caractères, format email valide.',
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_email_1',
          value: 'alice.martin@entreprise.fr',
          isValid: true,
          reason: 'Adresse nominale normalisée',
        ),
        ValueObjectExample(
          id: 'ex_email_2',
          value: 'alice.martin@',
          isValid: false,
          reason: 'Nom de domaine manquant',
        ),
        ValueObjectExample(
          id: 'ex_email_3',
          value: 'not-an-email',
          isValid: false,
          reason: 'Séparateur @ absent',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_currency_code',
      technicalName: 'CurrencyCode',
      name: 'Code devise ISO 4217',
      description:
          'Code devise alphabétique sur 3 lettres majuscules conforme à la norme ISO 4217.',
      category: 'Finance',
      kind: ValueObjectKind.scalar,
      primitiveType: BusinessAttributeType.string,
      schemaConstraints: JsonSchemaConstraints(
        minLength: 3,
        maxLength: 3,
        pattern: r'^[A-Z]{3}$',
      ),
      normalizationRules: const <String>['trim', 'uppercase'],
      constraints: '3 lettres majuscules ISO 4217 (ex. EUR, USD, GBP).',
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_cur_1',
          value: 'EUR',
          isValid: true,
          reason: 'Devise euro ISO 4217',
        ),
        ValueObjectExample(
          id: 'ex_cur_2',
          value: '€',
          isValid: false,
          reason: 'Symbole au lieu du code ISO 3 lettres',
        ),
        ValueObjectExample(
          id: 'ex_cur_3',
          value: 'EURO',
          isValid: false,
          reason: 'Longueur différente de 3 caractères',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_money',
      technicalName: 'Money',
      name: 'Montant monétaire',
      description:
          'Montant financier immuable couplant une valeur en unités mineures (centimes) et un code devise ISO 4217.',
      category: 'Finance',
      kind: ValueObjectKind.composite,
      fields: <BusinessAttribute>[
        BusinessAttribute(
          id: 'vo_money_amount',
          name: 'amountMinorUnits',
          type: BusinessAttributeType.integer,
          required: true,
          description: 'Montant exprimé en unités mineures (centimes).',
          schemaConstraints: JsonSchemaConstraints(minimum: 0),
        ),
        BusinessAttribute(
          id: 'vo_money_currency',
          name: 'currency',
          type: BusinessAttributeType.string,
          required: true,
          description: 'Code devise ISO 4217 sur 3 lettres majuscules.',
          schemaConstraints: JsonSchemaConstraints(
            minLength: 3,
            maxLength: 3,
            pattern: r'^[A-Z]{3}$',
          ),
        ),
      ],
      crossFieldRules: const <String>[
        'amountMinorUnits doit être un entier >= 0 (pas de virgule flottante)',
        'Les opérations arithmétiques (addition, soustraction, comparaison) exigent la même devise',
      ],
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_money_1',
          value: '{"amountMinorUnits": 12500, "currency": "EUR"}',
          isValid: true,
          reason: '125,00 EUR exprimé en centimes',
        ),
        ValueObjectExample(
          id: 'ex_money_2',
          value: '{"amountMinorUnits": -100, "currency": "EUR"}',
          isValid: false,
          reason: 'Montant négatif interdit',
        ),
        ValueObjectExample(
          id: 'ex_money_3',
          value: '{"amountMinorUnits": 500, "currency": "EU"}',
          isValid: false,
          reason: 'Code devise invalide (non ISO 4217)',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_iban',
      technicalName: 'Iban',
      name: 'IBAN',
      description:
          'Numéro de compte bancaire international normalisé sans espaces avec validation de clé modulo 97.',
      category: 'Finance',
      kind: ValueObjectKind.scalar,
      primitiveType: BusinessAttributeType.string,
      schemaConstraints: JsonSchemaConstraints(
        minLength: 15,
        maxLength: 34,
        pattern: r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$',
      ),
      normalizationRules: const <String>['trim', 'uppercase', 'removeSpaces'],
      constraints: 'Format ISO 13616 + contrôle de clé RIB/IBAN modulo 97.',
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_iban_1',
          value: 'FR7630006000011234567890189',
          isValid: true,
          reason: 'IBAN français valide',
        ),
        ValueObjectExample(
          id: 'ex_iban_2',
          value: 'FR001234',
          isValid: false,
          reason: 'Trop court et clé de contrôle invalide',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_phone_number',
      technicalName: 'PhoneNumber',
      name: 'Numéro de téléphone E.164',
      description:
          'Numéro de téléphone international normalisé au format E.164 (+indicatif suivi de 7 à 15 chiffres).',
      category: 'Contact',
      kind: ValueObjectKind.scalar,
      primitiveType: BusinessAttributeType.string,
      schemaConstraints: JsonSchemaConstraints(
        minLength: 8,
        maxLength: 16,
        pattern: r'^\+[1-9]\d{6,14}$',
      ),
      normalizationRules: const <String>['trim', 'removeSpaces', 'removeDashes'],
      constraints: 'Format international E.164 obligatoire.',
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_phone_1',
          value: '+33612345678',
          isValid: true,
          reason: 'Numéro mobile français E.164',
        ),
        ValueObjectExample(
          id: 'ex_phone_2',
          value: '06 12 34 56 78',
          isValid: false,
          reason: 'Préfixe international + manquant',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_percentage',
      technicalName: 'Percentage',
      name: 'Pourcentage (0–100)',
      description:
          'Taux ou proportion bornée entre 0 et 100 inclus (ex. remise, TVA, avancement).',
      category: 'Mesure',
      kind: ValueObjectKind.scalar,
      primitiveType: BusinessAttributeType.number,
      schemaConstraints: JsonSchemaConstraints(minimum: 0, maximum: 100),
      constraints: 'Valeur numérique comprise entre 0 et 100 inclus.',
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_pct_1',
          value: '20',
          isValid: true,
          reason: 'Taux nominal de 20 %',
        ),
        ValueObjectExample(
          id: 'ex_pct_2',
          value: '105.5',
          isValid: false,
          reason: 'Dépasse la borne supérieure 100',
        ),
        ValueObjectExample(
          id: 'ex_pct_3',
          value: '-5',
          isValid: false,
          reason: 'Valeur négative interdite',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_date_range',
      technicalName: 'DateRange',
      name: 'Période calendaire',
      description:
          'Intervalle immuable de dates [startDate, endDate] garantissant la cohérence chronologique.',
      category: 'Temps',
      kind: ValueObjectKind.composite,
      fields: <BusinessAttribute>[
        BusinessAttribute(
          id: 'vo_dr_start',
          name: 'startDate',
          type: BusinessAttributeType.date,
          required: true,
          description: 'Date de début incluse (ISO 8601).',
        ),
        BusinessAttribute(
          id: 'vo_dr_end',
          name: 'endDate',
          type: BusinessAttributeType.date,
          required: true,
          description: 'Date de fin incluse (ISO 8601).',
        ),
      ],
      crossFieldRules: const <String>[
        'startDate <= endDate (la date de fin ne peut pas précéder la date de début)',
      ],
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_dr_1',
          value: '{"startDate": "2026-01-01", "endDate": "2026-12-31"}',
          isValid: true,
          reason: 'Période annuelle cohérente',
        ),
        ValueObjectExample(
          id: 'ex_dr_2',
          value: '{"startDate": "2026-06-15", "endDate": "2026-06-01"}',
          isValid: false,
          reason: 'endDate antérieure à startDate',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_postal_address',
      technicalName: 'PostalAddress',
      name: 'Adresse postale',
      description:
          'Adresse postale structurée et immuable avec code pays ISO 3166-1 alpha-2.',
      category: 'Localisation',
      kind: ValueObjectKind.composite,
      fields: <BusinessAttribute>[
        BusinessAttribute(
          id: 'vo_addr_street',
          name: 'street',
          type: BusinessAttributeType.string,
          required: true,
          description: 'Numéro et libellé de voie.',
          schemaConstraints: JsonSchemaConstraints(
            minLength: 2,
            maxLength: 200,
          ),
        ),
        BusinessAttribute(
          id: 'vo_addr_postal',
          name: 'postalCode',
          type: BusinessAttributeType.string,
          required: true,
          description: 'Code postal.',
          schemaConstraints: JsonSchemaConstraints(
            minLength: 2,
            maxLength: 20,
          ),
        ),
        BusinessAttribute(
          id: 'vo_addr_city',
          name: 'city',
          type: BusinessAttributeType.string,
          required: true,
          description: 'Ville ou commune.',
          schemaConstraints: JsonSchemaConstraints(
            minLength: 1,
            maxLength: 120,
          ),
        ),
        BusinessAttribute(
          id: 'vo_addr_country',
          name: 'countryCode',
          type: BusinessAttributeType.string,
          required: true,
          description: 'Code pays ISO 3166-1 alpha-2.',
          schemaConstraints: JsonSchemaConstraints(
            minLength: 2,
            maxLength: 2,
            pattern: r'^[A-Z]{2}$',
          ),
        ),
      ],
      crossFieldRules: const <String>[
        'street, postalCode et city ne doivent pas être composés uniquement d’espaces',
      ],
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_addr_1',
          value:
              '{"street": "10 Rue de la Paix", "postalCode": "75002", "city": "Paris", "countryCode": "FR"}',
          isValid: true,
          reason: 'Adresse française complète',
        ),
        ValueObjectExample(
          id: 'ex_addr_2',
          value:
              '{"street": "10 Rue de la Paix", "postalCode": "75002", "city": "Paris", "countryCode": "FRANCE"}',
          isValid: false,
          reason: 'countryCode non conforme ISO alpha-2',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_positive_quantity',
      technicalName: 'PositiveQuantity',
      name: 'Quantité strictement positive',
      description:
          'Quantité entière strictement supérieure à zéro (articles, unités, licences).',
      category: 'Mesure',
      kind: ValueObjectKind.scalar,
      primitiveType: BusinessAttributeType.integer,
      schemaConstraints: JsonSchemaConstraints(minimum: 1),
      constraints: 'Entier >= 1.',
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_qty_1',
          value: '3',
          isValid: true,
          reason: 'Quantité positive valide',
        ),
        ValueObjectExample(
          id: 'ex_qty_2',
          value: '0',
          isValid: false,
          reason: 'Zéro interdit pour une quantité strictement positive',
        ),
      ],
    ),
    ValueObjectSpec(
      id: 'vo_preset_slug',
      technicalName: 'Slug',
      name: 'Identifiant URL (Slug)',
      description:
          'Segment URL canonique en kebab-case minuscule sans accent ni caractère spécial.',
      category: 'Identité',
      kind: ValueObjectKind.scalar,
      primitiveType: BusinessAttributeType.string,
      schemaConstraints: JsonSchemaConstraints(
        minLength: 2,
        maxLength: 64,
        pattern: r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
      ),
      normalizationRules: const <String>['trim', 'lowercase'],
      constraints: 'kebab-case ASCII de 2 à 64 caractères.',
      examples: const <ValueObjectExample>[
        ValueObjectExample(
          id: 'ex_slug_1',
          value: 'commande-client-2026',
          isValid: true,
          reason: 'Slug canonique valide',
        ),
        ValueObjectExample(
          id: 'ex_slug_2',
          value: 'Commande Client!',
          isValid: false,
          reason: 'Majuscules, espace et ponctuation interdits',
        ),
      ],
    ),
  ];
}

List<String> _cleanStringList(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? const <String>[] : <String>[trimmed];
  }
  if (raw is! List) return const <String>[];
  return <String>[
    for (final item in raw)
      if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}
