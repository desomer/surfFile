/// Modèle immuable des règles techniques du dictionnaire de modélisation des objets métiers ([TechnicalModelingRule], [TechnicalRuleCategory]).
library;

import 'package:flutter/foundation.dart';

/// Catégorie fonctionnelle d'une règle technique de modélisation.
enum TechnicalRuleCategory {
  /// Identifiants, références, codes, numéros séquentiels et clés (`Id`, `Ref`, `Code`, `Number`, `Key`).
  identifiers('Identifiants & Références'),

  /// Dates calendaires et horodatages (`*At`, `*Date`, UTC).
  datesAndTime('Dates & Horodatages'),

  /// Attributs booléens (`is*`, `has*`, `can*`).
  booleans('Booléens'),

  /// Quantités, montants monétaires et unités de mesure (`*Cents`, `*Ms`, `*Kg`).
  quantitiesAndUnits('Quantités & Unités'),

  /// Audit, suppression logique et concurrence optimiste (`createdAt`, `deletedAt`, `version`).
  lifecycleAndAudit('Audit & Cycle de vie'),

  /// Contraintes structurelles JSON Schema (longueurs par défaut, regex, nullabilité).
  schemaConstraints('Contraintes JSON Schema'),

  /// Règle personnalisée définie par l'équipe.
  custom('Règle personnalisée');

  /// Construit une catégorie de règle technique.
  const TechnicalRuleCategory(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise depuis JSON (repli sur [custom]).
  static TechnicalRuleCategory fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final c in TechnicalRuleCategory.values) {
        if (c.name.toLowerCase() == needle || c.label.toLowerCase() == needle) {
          return c;
        }
      }
    }
    return TechnicalRuleCategory.custom;
  }
}

/// Règle technique unitaire du dictionnaire de modélisation des objets métiers.
///
/// Précise quand utiliser un suffixe/préfixe ou une structure donnée
/// (ex. `*Id` vs `*Ref` vs `*Code` vs `*Number`), quel type/format JSON Schema
/// appliquer, ainsi que les exemples et contre-exemples associés.
@immutable
class TechnicalModelingRule {
  /// Construit une règle technique immuable.
  const TechnicalModelingRule({
    required this.id,
    required this.name,
    required this.suffixOrPattern,
    required this.category,
    required this.whenToUse,
    this.whenNotToUse = '',
    this.recommendedType = '',
    this.goodExamples = const <String>[],
    this.badExamples = const <String>[],
    this.enabled = true,
    this.isBuiltIn = false,
  });

  /// Identifiant unique stable de la règle.
  final String id;

  /// Titre concis de la règle (ex. `Suffixe *Id (Identifiant technique)`).
  final String name;

  /// Motif, préfixe ou suffixe ciblé (ex. `*Id`, `*Ref`, `*Number`, `is*`).
  final String suffixOrPattern;

  /// Catégorie de classement.
  final TechnicalRuleCategory category;

  /// Règle prescriptive : quand utiliser ce motif ou cette structure.
  final String whenToUse;

  /// Contre-indication : quand ne PAS l'utiliser et quoi préférer.
  final String whenNotToUse;

  /// Type / format / contrainte JSON Schema recommandé (ex. `string (format: uuid)`).
  final String recommendedType;

  /// Exemples conformes recommandés.
  final List<String> goodExamples;

  /// Contre-exemples à éviter.
  final List<String> badExamples;

  /// Indique si la règle est active dans les directives IA et contrôles.
  final bool enabled;

  /// Indique si la règle provient du catalogue standard intégré.
  final bool isBuiltIn;

  /// Jeu de règles techniques standard livré par défaut.
  static const List<TechnicalModelingRule> defaultRules = <TechnicalModelingRule>[
    TechnicalModelingRule(
      id: 'rule_suffix_id',
      name: 'Suffixe *Id (Identifiant technique interne)',
      suffixOrPattern: 'id / *Id',
      category: TechnicalRuleCategory.identifiers,
      whenToUse:
          'Clé primaire technique générée par le système (UUID/ULID/auto-incrément) ou clé étrangère vers une entité interne du domaine.',
      whenNotToUse:
          'Ne pas utiliser pour un numéro de facture/commande lu par l’humain (préférer *Number), ni pour une référence partenaire externe (préférer *Ref), ni pour un code nomenclature (préférer *Code).',
      recommendedType: 'string (format: uuid ou ULID) — readOnly: true sur la clé primaire',
      goodExamples: ['id', 'customerId', 'deliveryNoteId'],
      badExamples: ['invoiceId (pour un n° FAC-2026-001)', 'countryId (pour "FR")'],
      enabled: true,
      isBuiltIn: true,
    ),
    TechnicalModelingRule(
      id: 'rule_suffix_ref',
      name: 'Suffixe *Ref (Référence externe / corrélation)',
      suffixOrPattern: '*Ref',
      category: TechnicalRuleCategory.identifiers,
      whenToUse:
          'Identifiant ou référence émis par un système tiers, un partenaire, un fournisseur ou un document client (corrélation inter-systèmes, suivi transporteur, référence client).',
      whenNotToUse:
          'Ne pas utiliser pour une clé étrangère vers une table/entité interne (préférer *Id) ni pour une séquence générée par notre application (préférer *Number).',
      recommendedType: 'string (maxLength: 64..128, trim, pattern alphanumérique si connu)',
      goodExamples: ['externalRef', 'carrierTrackingRef', 'clientPurchaseOrderRef'],
      badExamples: ['customerRef (si référence interne -> customerId)'],
      enabled: true,
      isBuiltIn: true,
    ),
    TechnicalModelingRule(
      id: 'rule_suffix_code',
      name: 'Suffixe *Code (Code court / nomenclature)',
      suffixOrPattern: '*Code',
      category: TechnicalRuleCategory.identifiers,
      whenToUse:
          'Code métier court, stable et normalisé issu d’un référentiel ou d’une norme (devise ISO, pays, TVA, code tarifaire, code article SKU, code motif).',
      whenNotToUse:
          'Ne pas utiliser pour une séquence chronologique de documents (préférer *Number) ni pour un UUID technique (préférer *Id).',
      recommendedType:
          r'string (minLength: 2, maxLength: 32..64, pattern: ^[A-Z0-9_-]+$)',
      goodExamples: ['currencyCode', 'countryCode', 'vatRateCode', 'skuCode'],
      badExamples: ['orderCode (pour CMD-2026-0042 -> orderNumber)'],
      enabled: true,
      isBuiltIn: true,
    ),
    TechnicalModelingRule(
      id: 'rule_suffix_number',
      name: 'Suffixe *Number (Numéro séquentiel métier)',
      suffixOrPattern: '*Number',
      category: TechnicalRuleCategory.identifiers,
      whenToUse:
          'Numéro métier lisible, souvent séquentiel ou soumis à contrainte légale/comptable (numéro de facture, devis, bon de livraison, contrat, dossier).',
      whenNotToUse:
          'Ne pas utiliser comme clé étrangère relationnelle entre entités (utiliser *Id) ni pour une quantité/compteur mathématique (préférer *Count).',
      recommendedType:
          r'string (maxLength: 40, unique: true, pattern structuré ex. ^FAC-[0-9]{4}-[0-9]+$)',
      goodExamples: ['invoiceNumber', 'quoteNumber', 'orderNumber', 'siretNumber'],
      badExamples: ['itemsNumber (pour un compteur -> itemCount)'],
      enabled: true,
      isBuiltIn: true,
    ),
    TechnicalModelingRule(
      id: 'rule_suffix_key',
      name: 'Suffixe *Key (Clé fonctionnelle / idempotence)',
      suffixOrPattern: '*Key',
      category: TechnicalRuleCategory.identifiers,
      whenToUse:
          'Clé d’idempotence API, clé de partition, slug stable de configuration ou clé fonctionnelle composite exposée en URL.',
      whenNotToUse:
          'Ne pas utiliser à la place de `id` sur une entité métier standard.',
      recommendedType:
          r'string (maxLength: 128, pattern URL-safe ^[a-z0-9._:-]+$)',
      goodExamples: ['idempotencyKey', 'tenantKey', 'webhookSignatureKey'],
      badExamples: ['userKey (si clé primaire -> id ou userId)'],
      enabled: true,
      isBuiltIn: true,
    ),
    TechnicalModelingRule(
      id: 'rule_datetime_at',
      name: 'Horodatage *At vs Date calendaire *Date',
      suffixOrPattern: '*At / *Date',
      category: TechnicalRuleCategory.datesAndTime,
      whenToUse:
          'Utiliser *At pour tout instant précis (date + heure UTC ISO 8601, format date-time), et *Date uniquement pour une date calendaire sans heure (échéance, naissance, jour férié, format date YYYY-MM-DD).',
      whenNotToUse:
          'Ne pas typer un champ *At en date simple ni un champ *Date en date-time avec fuseau horaire ambigu.',
      recommendedType: '*At -> string (format: date-time, UTC) · *Date -> string (format: date)',
      goodExamples: ['createdAt', 'validatedAt', 'dueDate', 'birthDate'],
      badExamples: ['createdDate (pour un timestamp)', 'birthAt (pour une date de naissance)'],
      enabled: true,
      isBuiltIn: true,
    ),
    TechnicalModelingRule(
      id: 'rule_boolean_prefix',
      name: 'Préfixes booléens (is* / has* / can*)',
      suffixOrPattern: 'is* / has* / can*',
      category: TechnicalRuleCategory.booleans,
      whenToUse:
          'Toujours formuler les booléens en question affirmative sans négation (isActive, hasAttachment, canApprove) avec valeur par défaut explicite.',
      whenNotToUse:
          'Éviter les noms ambigus sans préfixe (`active`, `deleted`) et les doubles négations (`isNotDisabled`).',
      recommendedType: 'boolean (default explicite recommandé)',
      goodExamples: ['isActive', 'isTaxExempt', 'hasSignedContract', 'canCancel'],
      badExamples: ['disabled', 'isNotValid', 'flag'],
      enabled: true,
      isBuiltIn: true,
    ),
    TechnicalModelingRule(
      id: 'rule_units_suffix',
      name: 'Unités & quantités explicites',
      suffixOrPattern: '*Cents / *Amount / *Ms / *Kg / *Count',
      category: TechnicalRuleCategory.quantitiesAndUnits,
      whenToUse:
          'Préciser l’unité ou la nature dans le nom ou via un sous-objet {value, unit} dès qu’une valeur numérique représente une durée, un poids, une distance, un montant ou un cardinal.',
      whenNotToUse:
          'Éviter les noms nus ambigus comme `duration`, `weight`, `price` sans unité ni convention.',
      recommendedType: 'number/integer (minimum: 0) avec suffixe d’unité explicite',
      goodExamples: ['totalAmountHt', 'unitPriceCents', 'timeoutMs', 'netWeightKg', 'lineCount'],
      badExamples: ['delay', 'weight', 'total'],
      enabled: true,
      isBuiltIn: true,
    ),
  ];

  /// Vérifie les invariants de la règle.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'TechnicalModelingRule.id ne peut pas être vide.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'TechnicalModelingRule.name ne peut pas être vide.',
      );
    }
    if (suffixOrPattern.trim().isEmpty) {
      throw const FormatException(
        'TechnicalModelingRule.suffixOrPattern ne peut pas être vide.',
      );
    }
    if (whenToUse.trim().isEmpty) {
      throw const FormatException(
        'TechnicalModelingRule.whenToUse ne peut pas être vide.',
      );
    }
  }

  /// Indique si cette règle correspond au filtre de recherche [query].
  bool matchesQuery(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        suffixOrPattern.toLowerCase().contains(needle) ||
        whenToUse.toLowerCase().contains(needle) ||
        whenNotToUse.toLowerCase().contains(needle) ||
        recommendedType.toLowerCase().contains(needle) ||
        goodExamples.any((e) => e.toLowerCase().contains(needle)) ||
        badExamples.any((e) => e.toLowerCase().contains(needle));
  }

  /// Construit une ligne de directive concise pour le prompt IA.
  String toPromptLine() {
    final buf = StringBuffer()
      ..write('[$suffixOrPattern] $name : $whenToUse');
    if (whenNotToUse.trim().isNotEmpty) {
      buf.write(' | À éviter : ${whenNotToUse.trim()}');
    }
    if (recommendedType.trim().isNotEmpty) {
      buf.write(' | Format : ${recommendedType.trim()}');
    }
    if (goodExamples.isNotEmpty) {
      buf.write(' | Ex : ${goodExamples.join(', ')}');
    }
    return buf.toString();
  }

  /// Copie modifiée.
  TechnicalModelingRule copyWith({
    String? id,
    String? name,
    String? suffixOrPattern,
    TechnicalRuleCategory? category,
    String? whenToUse,
    String? whenNotToUse,
    String? recommendedType,
    List<String>? goodExamples,
    List<String>? badExamples,
    bool? enabled,
    bool? isBuiltIn,
  }) => TechnicalModelingRule(
    id: id ?? this.id,
    name: name ?? this.name,
    suffixOrPattern: suffixOrPattern ?? this.suffixOrPattern,
    category: category ?? this.category,
    whenToUse: whenToUse ?? this.whenToUse,
    whenNotToUse: whenNotToUse ?? this.whenNotToUse,
    recommendedType: recommendedType ?? this.recommendedType,
    goodExamples: goodExamples ?? this.goodExamples,
    badExamples: badExamples ?? this.badExamples,
    enabled: enabled ?? this.enabled,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'suffixOrPattern': suffixOrPattern,
    'category': category.name,
    'whenToUse': whenToUse,
    if (whenNotToUse.isNotEmpty) 'whenNotToUse': whenNotToUse,
    if (recommendedType.isNotEmpty) 'recommendedType': recommendedType,
    if (goodExamples.isNotEmpty) 'goodExamples': goodExamples,
    if (badExamples.isNotEmpty) 'badExamples': badExamples,
    'enabled': enabled,
    'isBuiltIn': isBuiltIn,
  };

  /// Désérialise depuis JSON.
  factory TechnicalModelingRule.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'TechnicalModelingRule doit être un objet JSON.',
      );
    }
    final name = (raw['name'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final pattern = (raw['suffixOrPattern'] as String?)?.trim() ?? '';
    final whenToUse = (raw['whenToUse'] as String?)?.trim() ?? '';
    final item = TechnicalModelingRule(
      id: id.isEmpty ? 'rule_${name.hashCode.abs()}' : id,
      name: name.isEmpty ? 'Règle sans nom' : name,
      suffixOrPattern: pattern.isEmpty ? '*' : pattern,
      category: TechnicalRuleCategory.fromJson(raw['category']),
      whenToUse: whenToUse.isEmpty ? 'À préciser' : whenToUse,
      whenNotToUse: (raw['whenNotToUse'] as String?)?.trim() ?? '',
      recommendedType: (raw['recommendedType'] as String?)?.trim() ?? '',
      goodExamples: _stringList(raw['goodExamples']),
      badExamples: _stringList(raw['badExamples']),
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      isBuiltIn: raw['isBuiltIn'] == true,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TechnicalModelingRule &&
          other.id == id &&
          other.name == name &&
          other.suffixOrPattern == suffixOrPattern &&
          other.category == category &&
          other.whenToUse == whenToUse &&
          other.whenNotToUse == whenNotToUse &&
          other.recommendedType == recommendedType &&
          listEquals(other.goodExamples, goodExamples) &&
          listEquals(other.badExamples, badExamples) &&
          other.enabled == enabled &&
          other.isBuiltIn == isBuiltIn;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    suffixOrPattern,
    category,
    whenToUse,
    whenNotToUse,
    recommendedType,
    Object.hashAll(goodExamples),
    Object.hashAll(badExamples),
    enabled,
    isBuiltIn,
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return List<String>.unmodifiable([
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ]);
}
