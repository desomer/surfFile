/// Préférences complètes de modélisation des objets métiers, conventions de nommage,
/// stratégie de clés/audit, rigueur JSON Schema et profil régional ([BusinessObjectModelPreferences]).
library;

import 'package:flutter/foundation.dart';

import 'business_object_spec.dart';
import 'technical_modeling_rule.dart';

/// Convention de casse des noms d'attributs et relations générés par l'IA.
enum AttributeNamingCase {
  /// camelCase (ex. `adresseLivraison`, `deliveryAddress`).
  camelCase(
    label: 'camelCase',
    shortLabel: 'camel',
    exampleFr: 'adresseLivraison',
    exampleEn: 'deliveryAddress',
  ),

  /// snake_case (ex. `adresse_livraison`, `delivery_address`).
  snakeCase(
    label: 'snake_case',
    shortLabel: 'snake',
    exampleFr: 'adresse_livraison',
    exampleEn: 'delivery_address',
  ),

  /// PascalCase (ex. `AdresseLivraison`, `DeliveryAddress`).
  pascalCase(
    label: 'PascalCase',
    shortLabel: 'Pascal',
    exampleFr: 'AdresseLivraison',
    exampleEn: 'DeliveryAddress',
  ),

  /// kebab-case (ex. `adresse-livraison`, `delivery-address`).
  kebabCase(
    label: 'kebab-case',
    shortLabel: 'kebab',
    exampleFr: 'adresse-livraison',
    exampleEn: 'delivery-address',
  ),

  /// SCREAMING_SNAKE_CASE (ex. `ADRESSE_LIVRAISON`, `DELIVERY_ADDRESS`).
  screamingSnakeCase(
    label: 'SCREAMING_SNAKE_CASE',
    shortLabel: 'UPPER',
    exampleFr: 'ADRESSE_LIVRAISON',
    exampleEn: 'DELIVERY_ADDRESS',
  );

  const AttributeNamingCase({
    required this.label,
    required this.shortLabel,
    required this.exampleFr,
    required this.exampleEn,
  });

  /// Nom lisible de la convention.
  final String label;

  /// Étiquette courte pour les badges/boutons.
  final String shortLabel;

  /// Exemple en français.
  final String exampleFr;

  /// Exemple en anglais.
  final String exampleEn;

  /// Retourne un exemple représentatif pour [languageCode].
  String exampleForLanguage(String languageCode) {
    final lower = languageCode.trim().toLowerCase();
    return (lower == 'en' || lower == 'english' || lower == 'anglais')
        ? exampleEn
        : exampleFr;
  }

  /// Convertit un identifiant existant vers cette convention (ASCII valide `^[A-Za-z_][A-Za-z0-9_-]*$`).
  String formatIdentifier(String raw) {
    final normalized = BusinessAttribute.normalizeDslIdentifier(raw);
    final spaced = normalized
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (m) => '${m[1]} ${m[2]}',
        );
    final words = spaced
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();
    if (words.isEmpty) return 'champ';

    String cap(String w) =>
        w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}';

    final formatted = switch (this) {
      AttributeNamingCase.camelCase =>
        '${words.first}${words.skip(1).map(cap).join()}',
      AttributeNamingCase.snakeCase => words.join('_'),
      AttributeNamingCase.pascalCase => words.map(cap).join(),
      AttributeNamingCase.kebabCase => words.join('-'),
      AttributeNamingCase.screamingSnakeCase =>
        words.map((w) => w.toUpperCase()).join('_'),
    };
    return BusinessAttribute.isValidDslIdentifier(formatted)
        ? formatted
        : BusinessAttribute.normalizeDslIdentifier(formatted);
  }

  /// Désérialise depuis JSON (retombe sur [camelCase]).
  static AttributeNamingCase fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final value in AttributeNamingCase.values) {
        if (value.name.toLowerCase() == needle ||
            value.label.toLowerCase() == needle) {
          return value;
        }
      }
    }
    return AttributeNamingCase.camelCase;
  }
}

/// Convention de casse des valeurs d'énumération (`enumValues`) et états (`lifecycleStates[*].name`).
enum EnumValueNamingCase {
  /// Laisser libre selon le contexte métier (ex. `pending_approval`, `brouillon`).
  preserve(
    label: 'Libre / tel quel',
    exampleFr: 'en_attente',
    exampleEn: 'pending_approval',
  ),

  /// snake_case minuscule sans accent (ex. `pending_approval`, `en_attente`).
  snakeCase(
    label: 'snake_case',
    exampleFr: 'en_attente',
    exampleEn: 'pending_approval',
  ),

  /// SCREAMING_SNAKE_CASE (ex. `PENDING_APPROVAL`, `EN_ATTENTE`).
  screamingSnakeCase(
    label: 'SCREAMING_SNAKE_CASE',
    exampleFr: 'EN_ATTENTE',
    exampleEn: 'PENDING_APPROVAL',
  ),

  /// camelCase (ex. `pendingApproval`, `enAttente`).
  camelCase(
    label: 'camelCase',
    exampleFr: 'enAttente',
    exampleEn: 'pendingApproval',
  ),

  /// kebab-case (ex. `pending-approval`, `en-attente`).
  kebabCase(
    label: 'kebab-case',
    exampleFr: 'en-attente',
    exampleEn: 'pending-approval',
  );

  const EnumValueNamingCase({
    required this.label,
    required this.exampleFr,
    required this.exampleEn,
  });

  /// Libellé lisible.
  final String label;

  /// Exemple en français.
  final String exampleFr;

  /// Exemple en anglais.
  final String exampleEn;

  /// Exemple représentatif par défaut (en anglais).
  String get example => exampleEn;

  /// Exemple représentatif pour [languageCode].
  String exampleForLanguage(String languageCode) {
    final lower = languageCode.trim().toLowerCase();
    return (lower == 'en' || lower == 'english' || lower == 'anglais')
        ? exampleEn
        : exampleFr;
  }

  /// Reformate une valeur d'énumération selon la convention choisie.
  String formatValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || this == EnumValueNamingCase.preserve) {
      return trimmed;
    }
    final attrCase = switch (this) {
      EnumValueNamingCase.snakeCase => AttributeNamingCase.snakeCase,
      EnumValueNamingCase.screamingSnakeCase =>
        AttributeNamingCase.screamingSnakeCase,
      EnumValueNamingCase.camelCase => AttributeNamingCase.camelCase,
      EnumValueNamingCase.kebabCase => AttributeNamingCase.kebabCase,
      EnumValueNamingCase.preserve => AttributeNamingCase.snakeCase,
    };
    return attrCase.formatIdentifier(trimmed);
  }

  /// Désérialise depuis JSON.
  static EnumValueNamingCase fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in EnumValueNamingCase.values) {
        if (v.name.toLowerCase() == needle || v.label.toLowerCase() == needle) {
          return v;
        }
      }
    }
    return EnumValueNamingCase.snakeCase;
  }
}

/// Stratégie d'identifiant technique primaire sur les agrégats/entités.
enum PrimaryIdStrategy {
  /// Identifiant UUID v4 (`id: uuid!`).
  uuid(
    label: 'UUID v4',
    shortLabel: 'UUID',
    promptGuidance: 'Ajouter un champ primaire `id` de type `uuid` (`required: true`, `unique: true`, `readOnly: true`).',
  ),

  /// Identifiant ULID triable chronologiquement (`id: string!`, 26 caractères).
  ulid(
    label: 'ULID (26 car.)',
    shortLabel: 'ULID',
    promptGuidance: 'Ajouter un champ primaire `id` de type `string` au format ULID (26 caractères Base32, `required: true`, `unique: true`, `readOnly: true`).',
  ),

  /// Entier auto-incrémenté (`id: integer!`, `minimum: 1`).
  autoIncrementInt(
    label: 'Entier auto-incrémenté',
    shortLabel: 'Int ID',
    promptGuidance: 'Ajouter un champ primaire `id` de type `integer` (`minimum: 1`, `required: true`, `unique: true`, `readOnly: true`).',
  ),

  /// Clé métier explicite uniquement (ex. `numero`, `code`, `immatriculation`).
  businessKeyOnly(
    label: 'Clé métier naturelle uniquement',
    shortLabel: 'Clé métier',
    promptGuidance: 'Ne pas ajouter d’`id` technique artificiel ; utiliser une clé métier naturelle explicite (ex. `code`, `numero`, `reference`) avec `unique: true`.',
  ),

  /// Aucune contrainte imposée sur les identifiants.
  none(
    label: 'Libre (selon le contexte)',
    shortLabel: 'Libre',
    promptGuidance: 'Choisir la clé primaire la plus adaptée au domaine.',
  );

  const PrimaryIdStrategy({
    required this.label,
    required this.shortLabel,
    required this.promptGuidance,
  });

  /// Libellé affiché dans l'UI.
  final String label;

  /// Libellé court pour badge.
  final String shortLabel;

  /// Consigne transmise à l'IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static PrimaryIdStrategy fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in PrimaryIdStrategy.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return PrimaryIdStrategy.uuid;
  }
}

/// Convention de nommage des clés étrangères et références.
enum ForeignKeyNamingStyle {
  /// Suffixe ID (`clientId` / `client_id`).
  suffixId(
    label: 'Suffixe Id (ex. clientId / client_id)',
    promptGuidance: 'Nommer les références par ID avec le suffixe Id adapté à la casse (ex. `clientId` ou `client_id`).',
  ),

  /// Préfixe ID (`idClient` / `id_client`).
  prefixId(
    label: 'Préfixe id (ex. idClient / id_client)',
    promptGuidance: 'Nommer les références par ID avec le préfixe id adapté à la casse (ex. `idClient` ou `id_client`).',
  ),

  /// Nom sémantique sans suffixe/préfixe Id (`client`).
  semanticOnly(
    label: 'Nom sémantique pur (ex. client)',
    promptGuidance: 'Nommer les références par le nom métier direct sans suffixe `Id` (ex. `client`, `vehicule`).',
  );

  const ForeignKeyNamingStyle({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static ForeignKeyNamingStyle fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in ForeignKeyNamingStyle.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return ForeignKeyNamingStyle.suffixId;
  }
}

/// Préréglage des champs d'audit automatiques sur les agrégats racines.
enum AuditFieldsPreset {
  /// Aucun champ d'audit imposé.
  none(
    label: 'Aucun champ d’audit imposé',
    promptGuidance: 'Ne pas ajouter de champs d’audit technique sauf besoin métier explicite.',
  ),

  /// Horodatages création / modification.
  timestamps(
    label: 'Horodatages (createdAt, updatedAt)',
    promptGuidance: 'Inclure sur chaque agrégat racine les champs `createdAt` et `updatedAt` (type `datetime`, `readOnly: true`, formatés selon la casse choisie).',
  ),

  /// Audit complet (horodatages + auteurs + version optimiste).
  fullAudit(
    label: 'Audit complet (+ createdBy, updatedBy, version)',
    promptGuidance: 'Inclure sur chaque agrégat racine `createdAt`, `updatedAt`, `createdBy`, `updatedBy` (`readOnly: true`) et `version` (`integer`, `minimum: 1`).',
  ),

  /// Horodatages + suppression logique (soft-delete).
  softDelete(
    label: 'Horodatages + Soft-delete (deletedAt)',
    promptGuidance: 'Inclure sur chaque agrégat racine `createdAt`, `updatedAt` (`readOnly: true`) et `deletedAt` (`datetime`, `nullable: true`) pour la suppression logique.',
  );

  const AuditFieldsPreset({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static AuditFieldsPreset fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in AuditFieldsPreset.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return AuditFieldsPreset.none;
  }
}

/// Niveau de rigueur JSON Schema généré par l'IA et appliqué à l'export.
enum JsonSchemaStrictness {
  /// Minimal : types, `required` essentiels et `examples`.
  minimal(
    label: 'Minimal',
    shortLabel: 'Min',
    promptGuidance: 'Renseigner uniquement les types de base, `required` essentiels et `schemaConstraints.examples`, sans multiplier les contraintes regex ou `additionalProperties`.',
  ),

  /// Standard : longueurs, bornes numériques, formats et exemples.
  standard(
    label: 'Standard',
    shortLabel: 'Std',
    promptGuidance: 'Renseigner les contraintes JSON Schema courantes (`minLength`/`maxLength`, `minimum`/`maximum`, `format`, `minItems`/`maxItems`, `examples`).',
  ),

  /// Strict : validation forte (`additionalProperties: false`, `pattern`, `readOnly`/`writeOnly`, `$comment`, `uniqueItems`).
  strict(
    label: 'Strict (additionalProperties: false)',
    shortLabel: 'Strict',
    promptGuidance:
        r'Appliquer un JSON Schema strict : `additionalProperties: false` sur les objets/sous-objets, `pattern`, bornes précises, `readOnly`/`writeOnly`, `uniqueItems`, `title`, `$comment` et `examples`.',
  );

  const JsonSchemaStrictness({
    required this.label,
    required this.shortLabel,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Libellé court pour badge.
  final String shortLabel;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static JsonSchemaStrictness fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in JsonSchemaStrictness.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return JsonSchemaStrictness.standard;
  }
}

/// Politique de gestion de la nullabilité sur les attributs optionnels.
enum NullabilityStyle {
  /// Préférer l'omission du champ optionnel plutôt que `null`.
  omitOptional(
    label: 'Omettre les champs optionnels (nullable: false)',
    promptGuidance: 'Pour les attributs non obligatoires, privilégier l’omission de la propriété (`nullable: false`) sauf valeur nulle explicitement porteuse de sens.',
  ),

  /// Autoriser explicitement `null` sur les champs optionnels.
  explicitNullable(
    label: 'Autoriser null explicitement (nullable: true)',
    promptGuidance: 'Marquer les attributs optionnels avec `nullable: true` (type `["...", "null"]` en JSON Schema) pour les champs pouvant être vidés.',
  );

  const NullabilityStyle({required this.label, required this.promptGuidance});

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static NullabilityStyle fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in NullabilityStyle.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return NullabilityStyle.omitOptional;
  }
}

/// Style de modélisation des relations `1:1` et `1:N`.
enum RelationModelingStyle {
  /// Équilibré : sous-objets/tableaux ≤ 200 lignes imbriqués, références au-delà.
  balanced(
    label: 'Équilibré (imbriquer ≤ 200 lignes, référencer au-delà)',
    promptGuidance: 'Style équilibré : imbriquer les objets valeur et tableaux bornés (<= 200 lignes), et modéliser les autres agrégats par référence/relation.',
  ),

  /// Normalisé : privilégier des entités séparées reliées par identifiant.
  normalizedRefs(
    label: 'Normalisé (références par ID privilégiées)',
    promptGuidance: 'Privilégier une modélisation normalisée en agrégats séparés reliés par clés de référence (`type: "reference"` ou relations) plutôt que par imbrication profonde.',
  ),

  /// Imbrication prioritaire dans la limite stricte 200 attributs / 200 lignes.
  embeddedFirst(
    label: 'Imbrication prioritaire (dans la limite 200/200)',
    promptGuidance: 'Privilégier les sous-objets (`type: "object"`) et tableaux imbriqués tant que la limite stricte de 200 attributs et 200 lignes est respectée.',
  );

  const RelationModelingStyle({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static RelationModelingStyle fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in RelationModelingStyle.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return RelationModelingStyle.balanced;
  }
}

/// Profil régional par défaut pour les formats et exemples générés.
enum ModelLocaleProfile {
  /// France / EUR (+33, 75001, EUR).
  frEur(
    label: 'France (FR / EUR)',
    currencyCode: 'EUR',
    sampleEmail: 'contact@exemple.fr',
    sampleUrl: 'https://exemple.fr',
    samplePhone: '+33 6 12 34 56 78',
    samplePostalCode: '75001',
    promptGuidance: 'Profil régional FR/EUR : exemples français (code postal 5 chiffres `75001`, téléphone `+33`, devise `EUR`, SIRET/SIREN si pertinent).',
  ),

  /// Union Européenne / EUR (IBAN, TVA, EUR).
  euEur(
    label: 'Europe (EU / EUR)',
    currencyCode: 'EUR',
    sampleEmail: 'contact@company.eu',
    sampleUrl: 'https://company.eu',
    samplePhone: '+33 1 42 68 55 00',
    samplePostalCode: '1000',
    promptGuidance: 'Profil régional EU/EUR : formats européens (IBAN, TVA intracommunautaire, devise `EUR`, téléphone E.164).',
  ),

  /// États-Unis / USD (+1, 10001, USD).
  usUsd(
    label: 'États-Unis (US / USD)',
    currencyCode: 'USD',
    sampleEmail: 'contact@example.com',
    sampleUrl: 'https://example.com',
    samplePhone: '+1-202-555-0142',
    samplePostalCode: '10001',
    promptGuidance: 'Profil régional US/USD : exemples nord-américains (ZIP `10001`, téléphone `+1`, devise `USD`).',
  ),

  /// Suisse / CHF (+41, 1201, CHF).
  chChf(
    label: 'Suisse (CH / CHF)',
    currencyCode: 'CHF',
    sampleEmail: 'contact@exemple.ch',
    sampleUrl: 'https://exemple.ch',
    samplePhone: '+41 22 555 01 99',
    samplePostalCode: '1201',
    promptGuidance: 'Profil régional CH/CHF : exemples suisses (NPA 4 chiffres `1201`, téléphone `+41`, devise `CHF`).',
  ),

  /// Profil personnalisé libre.
  custom(
    label: 'Personnalisé…',
    currencyCode: 'EUR',
    sampleEmail: 'contact@exemple.org',
    sampleUrl: 'https://exemple.org',
    samplePhone: '+33 6 00 00 00 00',
    samplePostalCode: '75001',
    promptGuidance: 'Profil régional personnalisé.',
  );

  const ModelLocaleProfile({
    required this.label,
    required this.currencyCode,
    required this.sampleEmail,
    required this.sampleUrl,
    required this.samplePhone,
    required this.samplePostalCode,
    required this.promptGuidance,
  });

  /// Libellé affiché.
  final String label;

  /// Code devise ISO 4217 associé.
  final String currencyCode;

  /// Email d'exemple par défaut pour les seeds.
  final String sampleEmail;

  /// URL d'exemple par défaut pour les seeds.
  final String sampleUrl;

  /// Téléphone d'exemple.
  final String samplePhone;

  /// Code postal d'exemple.
  final String samplePostalCode;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static ModelLocaleProfile fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in ModelLocaleProfile.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return ModelLocaleProfile.frEur;
  }
}

/// Représentation des montants monétaires dans le modèle de données.
enum CurrencyRepresentation {
  /// Nombre décimal à 2 décimales (`type: "number"`, `multipleOf: 0.01`, `minimum: 0`).
  decimal(
    label: 'Décimal (number, multipleOf: 0.01)',
    promptGuidance: 'Représenter les montants monétaires en `number` (`multipleOf: 0.01`, `minimum: 0`).',
  ),

  /// Entier en centimes (`type: "integer"`, `minimum: 0`).
  integerCents(
    label: 'Entier en centimes (integer)',
    promptGuidance: 'Représenter les montants monétaires en `integer` exprimés en centimes (`minimum: 0`).',
  ),

  /// Sous-objet `{ amount, currency }`.
  amountWithCurrencyObject(
    label: 'Sous-objet { amount, currency }',
    promptGuidance: 'Représenter chaque montant monétaire par un sous-objet structuré (`type: "object"`) contenant le montant et le code devise ISO 4217.',
  );

  const CurrencyRepresentation({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static CurrencyRepresentation fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in CurrencyRepresentation.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return CurrencyRepresentation.decimal;
  }
}

/// Politique de suffixation des dates et horodatages.
enum DateTimeSuffixPolicy {
  /// Imposer `*At` pour `date-time` UTC et `*Date` pour `date` calendaire.
  strictAtAndDate(
    label: '*At (horodatage UTC) vs *Date (date calendaire)',
    promptGuidance:
        'Distinguer strictement `*At` (string format `date-time` en UTC ISO 8601) et `*Date` (string format `date` calendaire YYYY-MM-DD sans heure).',
  ),

  /// Laisser le nommage libre.
  flexible(
    label: 'Libre selon le contexte',
    promptGuidance:
        'Choisir le nom de date le plus naturel selon le métier tout en précisant le format `date` ou `date-time` UTC.',
  );

  const DateTimeSuffixPolicy({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static DateTimeSuffixPolicy fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in DateTimeSuffixPolicy.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return DateTimeSuffixPolicy.strictAtAndDate;
  }
}

/// Politique de préfixage des attributs booléens.
enum BooleanPrefixPolicy {
  /// Imposer `is*`, `has*`, `can*` (forme affirmative).
  strictIsHasCan(
    label: 'Strict : is* / has* / can* (sans négation)',
    promptGuidance:
        'Préfixer obligatoirement tous les booléens par `is`, `has` ou `can` (ou leur équivalent dans la langue choisie) à la forme affirmative, avec valeur par défaut explicite.',
  ),

  /// Préférer `is*` sans le bloquer.
  preferIs(
    label: 'Préférer is* lorsque naturel',
    promptGuidance:
        'Privilégier le préfixe `is` sur les booléens d’état (`isActive`, `isEnabled`) à la forme affirmative.',
  ),

  /// Libre.
  free(
    label: 'Libre',
    promptGuidance: 'Nommer les booléens librement à la forme affirmative.',
  );

  const BooleanPrefixPolicy({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static BooleanPrefixPolicy fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in BooleanPrefixPolicy.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return BooleanPrefixPolicy.strictIsHasCan;
  }
}

/// Politique de représentation des unités et quantités physiques/temporelles.
enum UnitSuffixPolicy {
  /// Suffixe d'unité explicite (`*Cents`, `*Ms`, `*Kg`, `*Minutes`, `*Meters`).
  explicitSuffix(
    label: 'Suffixe d’unité explicite (*Ms, *Kg, *Cents…)',
    promptGuidance:
        'Suffixer systématiquement les mesures physiques, durées et grandeurs par leur unité explicite (`*Ms`, `*Seconds`, `*Kg`, `*Cents`, `*Km`, `*Count`) pour éviter toute ambiguïté.',
  ),

  /// Sous-objet `{ value, unit }`.
  valueUnitObject(
    label: 'Sous-objet structuré { value, unit }',
    promptGuidance:
        'Modéliser les grandeurs physiques multi-unités via un sous-objet `{ value, unit }` avec unité normalisée.',
  ),

  /// Libre.
  free(
    label: 'Libre (unité précisée en description)',
    promptGuidance:
        'Préciser systématiquement l’unité de mesure dans la description JSON Schema de l’attribut.',
  );

  const UnitSuffixPolicy({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static UnitSuffixPolicy fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in UnitSuffixPolicy.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return UnitSuffixPolicy.explicitSuffix;
  }
}

/// Stratégie de suppression logique (soft-delete) sur les agrégats racines.
enum SoftDeleteStrategy {
  /// Suppression logique non imposée.
  none(
    label: 'Non imposée (suppression physique ou selon besoin)',
    promptGuidance: 'Ne pas ajouter de marqueur de soft-delete sauf besoin d’archivage explicite.',
  ),

  /// Champ `deletedAt` nullable.
  deletedAtTimestamp(
    label: 'Horodatage deletedAt (nullable)',
    promptGuidance:
        'Ajouter un champ `deletedAt` (`date-time`, `nullable: true`, `readOnly: true`) pour la suppression logique.',
  ),

  /// Indicateur `isDeleted`.
  isDeletedFlag(
    label: 'Booléen isDeleted (default: false)',
    promptGuidance:
        'Ajouter un champ `isDeleted` (`boolean`, `default: false`) pour la suppression logique.',
  ),

  /// Combinaison `isDeleted` + `deletedAt`.
  both(
    label: 'Complet : isDeleted + deletedAt',
    promptGuidance:
        'Ajouter `isDeleted` (`boolean`, `default: false`) et `deletedAt` (`date-time`, `nullable: true`) sur chaque agrégat racine.',
  );

  const SoftDeleteStrategy({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static SoftDeleteStrategy fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in SoftDeleteStrategy.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return SoftDeleteStrategy.none;
  }
}

/// Stratégie de verrouillage optimiste (concurrence d'écriture).
enum OptimisticLockingStrategy {
  /// Aucun champ de version imposé.
  none(
    label: 'Aucun champ de version imposé',
    promptGuidance: 'Ne pas imposer de champ de concurrence optimiste sauf besoin explicite.',
  ),

  /// Entier incrémental `version`.
  integerVersion(
    label: 'Compteur entier version (>= 1)',
    promptGuidance:
        'Ajouter un champ `version` (`integer`, `minimum: 1`, `default: 1`, `readOnly: true`) pour la concurrence optimiste.',
  ),

  /// Chaîne `etag`.
  etagString(
    label: 'Jeton etag (string opaque)',
    promptGuidance:
        'Ajouter un champ `etag` (`string`, `readOnly: true`) pour le contrôle de concurrence optimiste.',
  );

  const OptimisticLockingStrategy({
    required this.label,
    required this.promptGuidance,
  });

  /// Libellé lisible.
  final String label;

  /// Directive IA.
  final String promptGuidance;

  /// Désérialise depuis JSON.
  static OptimisticLockingStrategy fromJson(Object? raw) {
    if (raw is String) {
      final needle = raw.trim().toLowerCase();
      for (final v in OptimisticLockingStrategy.values) {
        if (v.name.toLowerCase() == needle) return v;
      }
    }
    return OptimisticLockingStrategy.none;
  }
}

/// Alias rétrocompatible vers [BusinessObjectModelPreferences].
typedef BusinessObjectLanguageSettings = BusinessObjectModelPreferences;

/// Ensemble unifié des préférences de modélisation, nommage, JSON Schema et dictionnaire
/// de règles techniques transmis au `Domain Modeler` et appliqué aux exporteurs.
@immutable
class BusinessObjectModelPreferences {
  /// Construit un jeu de préférences de modèle et règles techniques immuable.
  const BusinessObjectModelPreferences({
    this.attributeLanguage = 'en',
    this.enumLanguage = 'en',
    this.contentLanguage = 'fr',
    this.attributeCase = AttributeNamingCase.camelCase,
    this.enumCase = EnumValueNamingCase.snakeCase,
    this.singularObjectsPluralCollections = true,
    this.idStrategy = PrimaryIdStrategy.uuid,
    this.foreignKeyStyle = ForeignKeyNamingStyle.suffixId,
    this.auditPreset = AuditFieldsPreset.none,
    this.schemaStrictness = JsonSchemaStrictness.standard,
    this.nullabilityStyle = NullabilityStyle.omitOptional,
    this.relationStyle = RelationModelingStyle.balanced,
    this.localeProfile = ModelLocaleProfile.frEur,
    this.customLocaleLabel = '',
    this.currencyStyle = CurrencyRepresentation.decimal,
    this.customInstructions = '',
    this.enforceIdRefCodeNumberDistinction = true,
    this.dateTimeSuffixPolicy = DateTimeSuffixPolicy.strictAtAndDate,
    this.booleanPrefixPolicy = BooleanPrefixPolicy.strictIsHasCan,
    this.unitSuffixPolicy = UnitSuffixPolicy.explicitSuffix,
    this.softDeleteStrategy = SoftDeleteStrategy.none,
    this.optimisticLockingStrategy = OptimisticLockingStrategy.none,
    this.defaultCodeMaxLength = 64,
    this.defaultLabelMaxLength = 255,
    this.defaultDescriptionMaxLength = 2000,
    this.technicalRules = TechnicalModelingRule.defaultRules,
  });

  /// Préférences par défaut (`en` pour attributs & valeurs d'enum, `fr` pour les textes/exemples).
  static const BusinessObjectModelPreferences defaults =
      BusinessObjectModelPreferences();

  /// Langues prédéfinies proposées dans l'interface.
  static const List<({String code, String label})> commonLanguages = [
    (code: 'fr', label: 'Français'),
    (code: 'en', label: 'English'),
    (code: 'es', label: 'Español'),
    (code: 'de', label: 'Deutsch'),
    (code: 'it', label: 'Italiano'),
    (code: 'pt', label: 'Português'),
  ];

  /// Langue des identifiants techniques générés (`technicalName`, `name`, `relations`, etc.).
  final String attributeLanguage;

  /// Langue des valeurs d'énumération (`enumValues`) et codes d'états (`lifecycleStates[*].name`).
  final String enumLanguage;

  /// Langue des libellés, descriptions et exemples (`title`, `description`, `examples`, `$comment`, etc.).
  final String contentLanguage;

  /// Convention de casse des noms d'attributs et relations.
  final AttributeNamingCase attributeCase;

  /// Convention de casse des `enumValues` et états de cycle de vie.
  final EnumValueNamingCase enumCase;

  /// Impose des noms d'objets au singulier et des collections/tableaux au pluriel.
  final bool singularObjectsPluralCollections;

  /// Stratégie d'identifiant technique primaire.
  final PrimaryIdStrategy idStrategy;

  /// Convention de nommage des clés étrangères.
  final ForeignKeyNamingStyle foreignKeyStyle;

  /// Préréglage des champs d'audit automatiques sur les agrégats racines.
  final AuditFieldsPreset auditPreset;

  /// Niveau de rigueur JSON Schema par défaut.
  final JsonSchemaStrictness schemaStrictness;

  /// Politique de nullabilité des attributs optionnels.
  final NullabilityStyle nullabilityStyle;

  /// Style de modélisation des relations `1:1` / `1:N`.
  final RelationModelingStyle relationStyle;

  /// Profil régional pour les exemples et formats métier.
  final ModelLocaleProfile localeProfile;

  /// Libellé libre lorsque [localeProfile] vaut [ModelLocaleProfile.custom].
  final String customLocaleLabel;

  /// Représentation des montants monétaires.
  final CurrencyRepresentation currencyStyle;

  /// Consignes libres complémentaires transmises à l'IA.
  final String customInstructions;

  /// Impose la distinction stricte entre `*Id`, `*Ref`, `*Code`, `*Number` et `*Key`.
  final bool enforceIdRefCodeNumberDistinction;

  /// Convention de nommage des dates et horodatages (`*At` vs `*Date`).
  final DateTimeSuffixPolicy dateTimeSuffixPolicy;

  /// Convention de préfixage des booléens (`is*`, `has*`, `can*`).
  final BooleanPrefixPolicy booleanPrefixPolicy;

  /// Convention d'unités et quantités explicites.
  final UnitSuffixPolicy unitSuffixPolicy;

  /// Stratégie de suppression logique (soft-delete).
  final SoftDeleteStrategy softDeleteStrategy;

  /// Stratégie de verrouillage optimiste (`version` / `etag`).
  final OptimisticLockingStrategy optimisticLockingStrategy;

  /// Longueur maximale par défaut des codes/références courtes (`maxLength`).
  final int defaultCodeMaxLength;

  /// Longueur maximale par défaut des libellés/titres (`maxLength`).
  final int defaultLabelMaxLength;

  /// Longueur maximale par défaut des descriptions longues (`maxLength`).
  final int defaultDescriptionMaxLength;

  /// Catalogue des règles techniques détaillées du dictionnaire de modélisation.
  final List<TechnicalModelingRule> technicalRules;

  /// Vrai si toutes les préférences sont aux valeurs par défaut.
  bool get isDefault => this == defaults;

  /// Retourne un libellé lisible pour un code ou nom de langue.
  static String describeLanguage(String codeOrName) {
    final needle = codeOrName.trim().toLowerCase();
    for (final entry in commonLanguages) {
      if (entry.code == needle || entry.label.toLowerCase() == needle) {
        return '${entry.label} (${entry.code})';
      }
    }
    return codeOrName.trim().isEmpty ? 'Français (fr)' : codeOrName.trim();
  }

  /// Retourne un code court pour l'affichage compact (ex. `FR`, `EN`).
  static String shortCode(String codeOrName) {
    final trimmed = codeOrName.trim();
    if (trimmed.isEmpty) return 'FR';
    final lower = trimmed.toLowerCase();
    for (final entry in commonLanguages) {
      if (entry.code == lower || entry.label.toLowerCase() == lower) {
        return entry.code.toUpperCase();
      }
    }
    return trimmed.length <= 4
        ? trimmed.toUpperCase()
        : trimmed.substring(0, 4).toUpperCase();
  }

  /// Résumé compact pour le bouton de l'en-tête (`FR · camel / FR · Std`).
  String formatCompactButtonSummary() =>
      '${shortCode(attributeLanguage)} · ${attributeCase.shortLabel} / ${shortCode(contentLanguage)} · ${schemaStrictness.shortLabel}';

  /// Construit le bloc de directives complet injecté dans les prompts IA.
  String toPromptDirective() {
    final attrLang = describeLanguage(attributeLanguage);
    final enumLang = describeLanguage(enumLanguage);
    final contentLang = describeLanguage(contentLanguage);
    final caseExample = attributeCase.exampleForLanguage(attributeLanguage);
    final enumExample = enumCase.exampleForLanguage(enumLanguage);
    final localeDesc =
        localeProfile == ModelLocaleProfile.custom &&
            customLocaleLabel.trim().isNotEmpty
        ? 'Profil régional personnalisé : ${customLocaleLabel.trim()}'
        : localeProfile.promptGuidance;

    final buf = StringBuffer()
      ..writeln('PRÉFÉRENCES DU MODÈLE D’OBJETS MÉTIERS (IMPÉRATIF) :')
      ..writeln(
        '- Langue des attributs et identifiants techniques (`technicalName`, `attributes[*].name`, `children[*].name`, `relations[*].name`) : $attrLang — toujours en ASCII strict (`^[A-Za-z_][A-Za-z0-9_-]*\$`, SANS ACCENT ni espace).',
      )
      ..writeln(
        '- Casse des noms d’attributs et relations : ${attributeCase.label} (ex. `$caseExample`).',
      )
      ..writeln(
        '- Langue et casse des valeurs `enumValues` et codes d’états `lifecycleStates[*].name` : $enumLang en ${enumCase.label} (ex. `$enumExample`).',
      )
      ..writeln(
        '- Langue des libellés, descriptions et exemples (`BusinessObjectSpec.name`, `description`, `constraints`, `schemaConstraints.title`, `schemaConstraints.examples`, `schemaConstraints.\$comment`, `defaultValue`, `LifecycleState.label`) : $contentLang.',
      )
      ..writeln(
        '- Exemples JSON Schema (`schemaConstraints.examples`) : renseigner systématiquement 1 à 3 valeurs d’exemple réalistes et typées sur chaque attribut (racine et sous-attributs), conformes au format, aux bornes, au profil régional et à `enumValues`.',
      )
      ..writeln(
        singularObjectsPluralCollections
            ? '- Convention singulier/pluriel : nommer les entités au singulier (`Commande`/`Order`) et les tableaux/relations 1:N au pluriel (`lignes`/`lines`).'
            : '- Convention singulier/pluriel : libre selon le contexte métier.',
      )
      ..writeln('- Stratégie d’identifiant primaire : ${idStrategy.promptGuidance}')
      ..writeln('- Clés étrangères / références : ${foreignKeyStyle.promptGuidance}')
      ..writeln(
        enforceIdRefCodeNumberDistinction
            ? '- Arbitrage Id / Ref / Code / Number / Key (IMPÉRATIF) : réserver `*Id` aux clés techniques opaques/relations internes, `*Ref` aux références externes inter-systèmes, `*Code` aux nomenclatures courtes normalisées, `*Number` aux numéros séquentiels métier/légaux et `*Key` aux clés d’idempotence/URL.'
            : '- Arbitrage Id / Ref / Code / Number : souple selon le contexte métier.',
      )
      ..writeln('- Dates & horodatages : ${dateTimeSuffixPolicy.promptGuidance}')
      ..writeln('- Booléens : ${booleanPrefixPolicy.promptGuidance}')
      ..writeln('- Quantités & unités : ${unitSuffixPolicy.promptGuidance}')
      ..writeln('- Champs d’audit : ${auditPreset.promptGuidance}')
      ..writeln('- Suppression logique (soft-delete) : ${softDeleteStrategy.promptGuidance}')
      ..writeln('- Concurrence optimiste : ${optimisticLockingStrategy.promptGuidance}')
      ..writeln('- Rigueur JSON Schema : ${schemaStrictness.promptGuidance}')
      ..writeln(
        '- Bornes JSON Schema par défaut : codes/références <= $defaultCodeMaxLength car., libellés/noms <= $defaultLabelMaxLength car., descriptions <= $defaultDescriptionMaxLength car. (respecter <= 200 attributs/objet et <= 200 lignes/tableau imbriqué).',
      )
      ..writeln('- Nullabilité : ${nullabilityStyle.promptGuidance}')
      ..writeln('- Style des relations : ${relationStyle.promptGuidance}')
      ..writeln('- $localeDesc')
      ..writeln('- Monétaire : ${currencyStyle.promptGuidance}');

    final activeRules = technicalRules.where((r) => r.enabled).toList();
    if (activeRules.isNotEmpty) {
      buf.writeln('DICTIONNAIRE DE RÈGLES TECHNIQUES ACTIVES (${activeRules.length}) :');
      for (final rule in activeRules) {
        buf.writeln('  • ${rule.toPromptLine()}');
      }
    }

    if (customInstructions.trim().isNotEmpty) {
      buf.writeln('- Consignes complémentaires d’équipe : ${customInstructions.trim()}');
    }
    return buf.toString().trimRight();
  }

  /// Valide la cohérence des préférences et règles techniques.
  void validate() {
    if (attributeLanguage.trim().isEmpty) {
      throw const FormatException(
        'La langue des attributs générés ne peut pas être vide.',
      );
    }
    if (enumLanguage.trim().isEmpty) {
      throw const FormatException(
        'La langue des valeurs d’enum ne peut pas être vide.',
      );
    }
    if (contentLanguage.trim().isEmpty) {
      throw const FormatException(
        'La langue des exemples, titres et descriptions ne peut pas être vide.',
      );
    }
    if (defaultCodeMaxLength < 4 ||
        defaultLabelMaxLength < 8 ||
        defaultDescriptionMaxLength < 16) {
      throw const FormatException(
        'Les longueurs maximales par défaut doivent être positives (code >= 4, libellé >= 8, description >= 16).',
      );
    }
    final seenIds = <String>{};
    for (final rule in technicalRules) {
      rule.validate();
      if (!seenIds.add(rule.id)) {
        throw FormatException('Règle technique dupliquée : ${rule.id}');
      }
    }
  }

  /// Copie modifiée.
  BusinessObjectModelPreferences copyWith({
    String? attributeLanguage,
    String? enumLanguage,
    String? contentLanguage,
    AttributeNamingCase? attributeCase,
    EnumValueNamingCase? enumCase,
    bool? singularObjectsPluralCollections,
    PrimaryIdStrategy? idStrategy,
    ForeignKeyNamingStyle? foreignKeyStyle,
    AuditFieldsPreset? auditPreset,
    JsonSchemaStrictness? schemaStrictness,
    NullabilityStyle? nullabilityStyle,
    RelationModelingStyle? relationStyle,
    ModelLocaleProfile? localeProfile,
    String? customLocaleLabel,
    CurrencyRepresentation? currencyStyle,
    String? customInstructions,
    bool? enforceIdRefCodeNumberDistinction,
    DateTimeSuffixPolicy? dateTimeSuffixPolicy,
    BooleanPrefixPolicy? booleanPrefixPolicy,
    UnitSuffixPolicy? unitSuffixPolicy,
    SoftDeleteStrategy? softDeleteStrategy,
    OptimisticLockingStrategy? optimisticLockingStrategy,
    int? defaultCodeMaxLength,
    int? defaultLabelMaxLength,
    int? defaultDescriptionMaxLength,
    List<TechnicalModelingRule>? technicalRules,
  }) => BusinessObjectModelPreferences(
    attributeLanguage: (attributeLanguage ?? this.attributeLanguage).trim(),
    enumLanguage: (enumLanguage ?? this.enumLanguage).trim(),
    contentLanguage: (contentLanguage ?? this.contentLanguage).trim(),
    attributeCase: attributeCase ?? this.attributeCase,
    enumCase: enumCase ?? this.enumCase,
    singularObjectsPluralCollections:
        singularObjectsPluralCollections ??
        this.singularObjectsPluralCollections,
    idStrategy: idStrategy ?? this.idStrategy,
    foreignKeyStyle: foreignKeyStyle ?? this.foreignKeyStyle,
    auditPreset: auditPreset ?? this.auditPreset,
    schemaStrictness: schemaStrictness ?? this.schemaStrictness,
    nullabilityStyle: nullabilityStyle ?? this.nullabilityStyle,
    relationStyle: relationStyle ?? this.relationStyle,
    localeProfile: localeProfile ?? this.localeProfile,
    customLocaleLabel: (customLocaleLabel ?? this.customLocaleLabel).trim(),
    currencyStyle: currencyStyle ?? this.currencyStyle,
    customInstructions: (customInstructions ?? this.customInstructions).trim(),
    enforceIdRefCodeNumberDistinction:
        enforceIdRefCodeNumberDistinction ??
        this.enforceIdRefCodeNumberDistinction,
    dateTimeSuffixPolicy: dateTimeSuffixPolicy ?? this.dateTimeSuffixPolicy,
    booleanPrefixPolicy: booleanPrefixPolicy ?? this.booleanPrefixPolicy,
    unitSuffixPolicy: unitSuffixPolicy ?? this.unitSuffixPolicy,
    softDeleteStrategy: softDeleteStrategy ?? this.softDeleteStrategy,
    optimisticLockingStrategy:
        optimisticLockingStrategy ?? this.optimisticLockingStrategy,
    defaultCodeMaxLength: defaultCodeMaxLength ?? this.defaultCodeMaxLength,
    defaultLabelMaxLength: defaultLabelMaxLength ?? this.defaultLabelMaxLength,
    defaultDescriptionMaxLength:
        defaultDescriptionMaxLength ?? this.defaultDescriptionMaxLength,
    technicalRules: List<TechnicalModelingRule>.unmodifiable(
      technicalRules ?? this.technicalRules,
    ),
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'attributeLanguage': attributeLanguage,
    'enumLanguage': enumLanguage,
    'contentLanguage': contentLanguage,
    'attributeCase': attributeCase.name,
    'enumCase': enumCase.name,
    'singularObjectsPluralCollections': singularObjectsPluralCollections,
    'idStrategy': idStrategy.name,
    'foreignKeyStyle': foreignKeyStyle.name,
    'auditPreset': auditPreset.name,
    'schemaStrictness': schemaStrictness.name,
    'nullabilityStyle': nullabilityStyle.name,
    'relationStyle': relationStyle.name,
    'localeProfile': localeProfile.name,
    if (customLocaleLabel.isNotEmpty) 'customLocaleLabel': customLocaleLabel,
    'currencyStyle': currencyStyle.name,
    if (customInstructions.isNotEmpty) 'customInstructions': customInstructions,
    'enforceIdRefCodeNumberDistinction': enforceIdRefCodeNumberDistinction,
    'dateTimeSuffixPolicy': dateTimeSuffixPolicy.name,
    'booleanPrefixPolicy': booleanPrefixPolicy.name,
    'unitSuffixPolicy': unitSuffixPolicy.name,
    'softDeleteStrategy': softDeleteStrategy.name,
    'optimisticLockingStrategy': optimisticLockingStrategy.name,
    'defaultCodeMaxLength': defaultCodeMaxLength,
    'defaultLabelMaxLength': defaultLabelMaxLength,
    'defaultDescriptionMaxLength': defaultDescriptionMaxLength,
    'technicalRules': [for (final r in technicalRules) r.toJson()],
  };

  /// Désérialise depuis JSON (rétrocompatible avec l'ancien `businessObjectLanguageSettings`).
  factory BusinessObjectModelPreferences.fromJson(Object? raw) {
    if (raw is! Map) return BusinessObjectModelPreferences.defaults;
    final attr = (raw['attributeLanguage'] as String?)?.trim() ?? '';
    final enumLang = (raw['enumLanguage'] as String?)?.trim() ?? '';
    final content = (raw['contentLanguage'] as String?)?.trim() ?? '';
    final rawRules = raw['technicalRules'];
    final parsedRules = rawRules is List
        ? List<TechnicalModelingRule>.unmodifiable([
            for (final item in rawRules) TechnicalModelingRule.fromJson(item),
          ])
        : TechnicalModelingRule.defaultRules;
    return BusinessObjectModelPreferences(
      attributeLanguage: attr.isEmpty ? 'en' : attr,
      enumLanguage: enumLang.isEmpty ? 'en' : enumLang,
      contentLanguage: content.isEmpty ? 'fr' : content,
      attributeCase: AttributeNamingCase.fromJson(raw['attributeCase']),
      enumCase: EnumValueNamingCase.fromJson(raw['enumCase']),
      singularObjectsPluralCollections:
          raw['singularObjectsPluralCollections'] is bool
          ? raw['singularObjectsPluralCollections'] as bool
          : true,
      idStrategy: PrimaryIdStrategy.fromJson(raw['idStrategy']),
      foreignKeyStyle: ForeignKeyNamingStyle.fromJson(raw['foreignKeyStyle']),
      auditPreset: AuditFieldsPreset.fromJson(raw['auditPreset']),
      schemaStrictness: JsonSchemaStrictness.fromJson(raw['schemaStrictness']),
      nullabilityStyle: NullabilityStyle.fromJson(raw['nullabilityStyle']),
      relationStyle: RelationModelingStyle.fromJson(raw['relationStyle']),
      localeProfile: ModelLocaleProfile.fromJson(raw['localeProfile']),
      customLocaleLabel: (raw['customLocaleLabel'] as String?)?.trim() ?? '',
      currencyStyle: CurrencyRepresentation.fromJson(raw['currencyStyle']),
      customInstructions: (raw['customInstructions'] as String?)?.trim() ?? '',
      enforceIdRefCodeNumberDistinction:
          raw['enforceIdRefCodeNumberDistinction'] is bool
          ? raw['enforceIdRefCodeNumberDistinction'] as bool
          : true,
      dateTimeSuffixPolicy: DateTimeSuffixPolicy.fromJson(
        raw['dateTimeSuffixPolicy'],
      ),
      booleanPrefixPolicy: BooleanPrefixPolicy.fromJson(
        raw['booleanPrefixPolicy'],
      ),
      unitSuffixPolicy: UnitSuffixPolicy.fromJson(raw['unitSuffixPolicy']),
      softDeleteStrategy: SoftDeleteStrategy.fromJson(
        raw['softDeleteStrategy'],
      ),
      optimisticLockingStrategy: OptimisticLockingStrategy.fromJson(
        raw['optimisticLockingStrategy'],
      ),
      defaultCodeMaxLength:
          (raw['defaultCodeMaxLength'] as num?)?.toInt().clamp(4, 512) ?? 64,
      defaultLabelMaxLength:
          (raw['defaultLabelMaxLength'] as num?)?.toInt().clamp(8, 2048) ?? 255,
      defaultDescriptionMaxLength:
          (raw['defaultDescriptionMaxLength'] as num?)
              ?.toInt()
              .clamp(16, 20000) ??
          2000,
      technicalRules: parsedRules,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessObjectModelPreferences &&
          other.attributeLanguage == attributeLanguage &&
          other.enumLanguage == enumLanguage &&
          other.contentLanguage == contentLanguage &&
          other.attributeCase == attributeCase &&
          other.enumCase == enumCase &&
          other.singularObjectsPluralCollections ==
              singularObjectsPluralCollections &&
          other.idStrategy == idStrategy &&
          other.foreignKeyStyle == foreignKeyStyle &&
          other.auditPreset == auditPreset &&
          other.schemaStrictness == schemaStrictness &&
          other.nullabilityStyle == nullabilityStyle &&
          other.relationStyle == relationStyle &&
          other.localeProfile == localeProfile &&
          other.customLocaleLabel == customLocaleLabel &&
          other.currencyStyle == currencyStyle &&
          other.customInstructions == customInstructions &&
          other.enforceIdRefCodeNumberDistinction ==
              enforceIdRefCodeNumberDistinction &&
          other.dateTimeSuffixPolicy == dateTimeSuffixPolicy &&
          other.booleanPrefixPolicy == booleanPrefixPolicy &&
          other.unitSuffixPolicy == unitSuffixPolicy &&
          other.softDeleteStrategy == softDeleteStrategy &&
          other.optimisticLockingStrategy == optimisticLockingStrategy &&
          other.defaultCodeMaxLength == defaultCodeMaxLength &&
          other.defaultLabelMaxLength == defaultLabelMaxLength &&
          other.defaultDescriptionMaxLength == defaultDescriptionMaxLength &&
          listEquals(other.technicalRules, technicalRules);

  @override
  int get hashCode => Object.hashAll([
    attributeLanguage,
    enumLanguage,
    contentLanguage,
    attributeCase,
    enumCase,
    singularObjectsPluralCollections,
    idStrategy,
    foreignKeyStyle,
    auditPreset,
    schemaStrictness,
    nullabilityStyle,
    relationStyle,
    localeProfile,
    customLocaleLabel,
    currencyStyle,
    customInstructions,
    enforceIdRefCodeNumberDistinction,
    dateTimeSuffixPolicy,
    booleanPrefixPolicy,
    unitSuffixPolicy,
    softDeleteStrategy,
    optimisticLockingStrategy,
    defaultCodeMaxLength,
    defaultLabelMaxLength,
    defaultDescriptionMaxLength,
    Object.hashAll(technicalRules),
  ]);
}
