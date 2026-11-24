/// Modèles immuables des postes de coûts récurrents d'exploitation Run / OPEX ([CostRunItemSpec], [CostRunCategory], [CostEnvironmentScope], [CostBillingCycle]).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Catégorie financière d'un poste récurrent d'exploitation (OPEX / Run).
enum CostRunCategory {
  /// Serveurs, conteneurs, serverless, réseau et CDN.
  cloudInfra('Infrastructure Cloud & Compute'),

  /// Bases de données managées, cache, stockage objet et flux.
  databaseStorage('Bases de données & Stockage'),

  /// APIs facturées à l'usage (paiement, SMS, e-mail, cartographie, KYC…).
  thirdPartyApi('APIs & Services tiers'),

  /// Consommation d'inférence LLM, embeddings et services IA.
  aiTokensLlm('IA Générative & Tokens LLM'),

  /// Abonnements logiciels SaaS, monitoring, CI/CD et outillage équipe.
  saasLicenses('Licences SaaS & Outils'),

  /// Maintien en condition opérationnelle (MCO), TMA corrective/évolutive et astreinte.
  supportTma('MCO / TMA & Support'),

  /// Sauvegardes, PRA/PCA, audits de sécurité, WAF et conformité.
  securityCompliance('Sécurité, Sauvegardes & Conformité');

  /// Construit une catégorie de coût Run.
  const CostRunCategory(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout une catégorie Run depuis JSON ou un alias courant, avec repli sur [cloudInfra].
  static CostRunCategory fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final category in CostRunCategory.values) {
        if (category.name.toLowerCase() == norm ||
            category.label.toLowerCase() == norm) {
          return category;
        }
      }
      switch (norm) {
        case 'cloud':
        case 'cloud_infra':
        case 'cloud-infra':
        case 'infra':
        case 'compute':
        case 'hosting':
          return CostRunCategory.cloudInfra;
        case 'database':
        case 'database_storage':
        case 'database-storage':
        case 'db':
        case 'storage':
        case 'bdd':
          return CostRunCategory.databaseStorage;
        case 'api':
        case 'apis':
        case 'third_party_api':
        case 'third-party-api':
        case 'third_party':
          return CostRunCategory.thirdPartyApi;
        case 'ai':
        case 'llm':
        case 'tokens':
        case 'ai_tokens_llm':
        case 'ai-tokens-llm':
          return CostRunCategory.aiTokensLlm;
        case 'saas':
        case 'licenses':
        case 'licences':
        case 'saas_licenses':
        case 'saas-licenses':
          return CostRunCategory.saasLicenses;
        case 'support':
        case 'tma':
        case 'mco':
        case 'support_tma':
        case 'support-tma':
        case 'maintenance':
          return CostRunCategory.supportTma;
        case 'security':
        case 'compliance':
        case 'backup':
        case 'security_compliance':
        case 'security-compliance':
          return CostRunCategory.securityCompliance;
      }
    }
    return CostRunCategory.cloudInfra;
  }
}

/// Périmètre d'environnement couvert par un poste OPEX.
enum CostEnvironmentScope {
  /// Environnement de développement et d'intégration continue.
  dev('Développement'),

  /// Environnement de recette, UAT ou pré-production.
  staging('Recette / Pré-prod'),

  /// Environnement de production cible.
  prod('Production'),

  /// Ressource transverse ou mutualisée multi-environnements.
  global('Global / Multi-env');

  /// Construit une portée d'environnement.
  const CostEnvironmentScope(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un environnement depuis JSON ou un alias courant, avec repli sur [prod].
  static CostEnvironmentScope fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final env in CostEnvironmentScope.values) {
        if (env.name.toLowerCase() == norm || env.label.toLowerCase() == norm) {
          return env;
        }
      }
      switch (norm) {
        case 'development':
        case 'developpement':
          return CostEnvironmentScope.dev;
        case 'uat':
        case 'preprod':
        case 'pre-prod':
        case 'recette':
        case 'qa':
          return CostEnvironmentScope.staging;
        case 'production':
        case 'prd':
          return CostEnvironmentScope.prod;
        case 'all':
        case 'shared':
        case 'multi':
        case 'transverse':
          return CostEnvironmentScope.global;
      }
    }
    return CostEnvironmentScope.prod;
  }
}

/// Périodicité de facturation d'un poste récurrent Run.
enum CostBillingCycle {
  /// Facturation mensuelle (`× 12` sur l'année).
  monthly('Mensuel'),

  /// Facturation annuelle globale (`/ 12` par mois).
  yearly('Annuel');

  /// Construit un cycle de facturation.
  const CostBillingCycle(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout une périodicité de facturation depuis JSON ou un alias courant, avec repli sur [monthly].
  static CostBillingCycle fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final cycle in CostBillingCycle.values) {
        if (cycle.name.toLowerCase() == norm ||
            cycle.label.toLowerCase() == norm) {
          return cycle;
        }
      }
      switch (norm) {
        case 'annual':
        case 'annually':
        case 'year':
        case 'an':
          return CostBillingCycle.yearly;
        case 'month':
        case 'mois':
          return CostBillingCycle.monthly;
      }
    }
    return CostBillingCycle.monthly;
  }
}

/// Poste de coût récurrent d'exploitation (OPEX) pour le Cloud, les licences, les APIs/LLM et la TMA.
@immutable
class CostRunItemSpec {
  /// Construit un poste OPEX immuable.
  const CostRunItemSpec({
    required this.id,
    this.code = 'RUN-001',
    required this.name,
    this.description = '',
    this.category = CostRunCategory.cloudInfra,
    this.environment = CostEnvironmentScope.prod,
    this.billingCycle = CostBillingCycle.monthly,
    this.unitCost = 0.0,
    this.quantity = 1.0,
    this.annualGrowthPct = 0.0,
    this.enabled = true,
  });

  /// Identifiant technique unique du poste OPEX.
  final String id;

  /// Code lisible du poste Run (ex. `RUN-001`).
  final String code;

  /// Intitulé du service, abonnement ou forfait récurrent.
  final String name;

  /// Détail du dimensionnement, métrique d'usage ou fournisseur retenu.
  final String description;

  /// Catégorie financière OPEX.
  final CostRunCategory category;

  /// Environnement couvert par ce poste (`prod` par défaut).
  final CostEnvironmentScope environment;

  /// Périodicité de facturation de [unitCost] (`monthly` par défaut).
  final CostBillingCycle billingCycle;

  /// Coût unitaire hors taxes sur la période [billingCycle] (`>= 0`).
  final double unitCost;

  /// Quantité ou nombre d'unités consommées (`>= 0`, `1.0` par défaut).
  final double quantity;

  /// Croissance annuelle composée de ce poste à partir de l'année 2 (`-50..500` %).
  final double annualGrowthPct;

  /// Indique si ce poste est actif dans la simulation OPEX/TCO.
  final bool enabled;

  /// Coût total sur une période de facturation brute (`0.0` lorsque [enabled] vaut `false`).
  double get rawPeriodCost => enabled ? unitCost * quantity : 0.0;

  /// Coût mensuel lissé en année 1.
  double get monthlyCost => billingCycle == CostBillingCycle.monthly
      ? rawPeriodCost
      : rawPeriodCost / 12.0;

  /// Coût annuel en année 1.
  double get yearlyCost => billingCycle == CostBillingCycle.yearly
      ? rawPeriodCost
      : rawPeriodCost * 12.0;

  /// Calcule le coût annuel projeté pour l'année [yearIndex] (`1` = année 1, croissance composée ensuite).
  double yearlyCostForYear(int yearIndex) => yearIndex <= 1
      ? yearlyCost
      : yearlyCost * math.pow(1.0 + annualGrowthPct / 100.0, yearIndex - 1);

  /// Vérifie les invariants structurels et financiers du poste Run.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('CostRunItemSpec.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'CostRunItemSpec.name ne peut pas être vide.',
      );
    }
    if (!unitCost.isFinite || unitCost < 0.0) {
      throw const FormatException(
        'CostRunItemSpec.unitCost doit être supérieur ou égal à 0.',
      );
    }
    if (!quantity.isFinite || quantity < 0.0) {
      throw const FormatException(
        'CostRunItemSpec.quantity doit être supérieur ou égal à 0.',
      );
    }
    if (!annualGrowthPct.isFinite ||
        annualGrowthPct < -50.0 ||
        annualGrowthPct > 500.0) {
      throw const FormatException(
        'CostRunItemSpec.annualGrowthPct doit être compris dans [-50, 500].',
      );
    }
  }

  /// Retourne une copie modifiée.
  CostRunItemSpec copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    CostRunCategory? category,
    CostEnvironmentScope? environment,
    CostBillingCycle? billingCycle,
    double? unitCost,
    double? quantity,
    double? annualGrowthPct,
    bool? enabled,
  }) => CostRunItemSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
    category: category ?? this.category,
    environment: environment ?? this.environment,
    billingCycle: billingCycle ?? this.billingCycle,
    unitCost: unitCost ?? this.unitCost,
    quantity: quantity ?? this.quantity,
    annualGrowthPct: annualGrowthPct ?? this.annualGrowthPct,
    enabled: enabled ?? this.enabled,
  );

  /// Sérialise le poste Run en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'category': category.name,
    'environment': environment.name,
    'billingCycle': billingCycle.name,
    'unitCost': unitCost,
    'quantity': quantity,
    'annualGrowthPct': annualGrowthPct,
    'enabled': enabled,
  };

  /// Désérialise un poste Run depuis JSON avec bornage tolérant.
  factory CostRunItemSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('CostRunItemSpec doit être un objet JSON.');
    }
    final rawName =
        (raw['name'] as String?)?.trim() ??
        (raw['title'] as String?)?.trim() ??
        (raw['label'] as String?)?.trim() ??
        '';
    final name = rawName.isEmpty ? 'Poste Run sans nom' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final item = CostRunItemSpec(
      id: rawId.isEmpty ? 'run_${name.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'RUN-001' : rawCode,
      name: name,
      description: (raw['description'] as String?)?.trim() ?? '',
      category: CostRunCategory.fromJson(raw['category']),
      environment: CostEnvironmentScope.fromJson(raw['environment']),
      billingCycle: CostBillingCycle.fromJson(raw['billingCycle']),
      unitCost: _nonNegativeDouble(raw['unitCost'] ?? raw['cost'], 0.0),
      quantity: _nonNegativeDouble(raw['quantity'] ?? raw['qty'], 1.0),
      annualGrowthPct: _clampedDouble(
        raw['annualGrowthPct'] ?? raw['growthPct'],
        0.0,
        -50.0,
        500.0,
      ),
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostRunItemSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.description == description &&
          other.category == category &&
          other.environment == environment &&
          other.billingCycle == billingCycle &&
          other.unitCost == unitCost &&
          other.quantity == quantity &&
          other.annualGrowthPct == annualGrowthPct &&
          other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    description,
    category,
    environment,
    billingCycle,
    unitCost,
    quantity,
    annualGrowthPct,
    enabled,
  );
}

double? _tryParseDouble(Object? raw) {
  if (raw is num) {
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
  if (raw is String) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

double _nonNegativeDouble(Object? raw, double fallback) {
  final parsed = _tryParseDouble(raw);
  if (parsed == null) return fallback;
  return parsed < 0.0 ? 0.0 : parsed;
}

double _clampedDouble(Object? raw, double fallback, double min, double max) {
  final parsed = _tryParseDouble(raw);
  if (parsed == null) return fallback;
  if (parsed < min) return min;
  if (parsed > max) return max;
  return parsed;
}
