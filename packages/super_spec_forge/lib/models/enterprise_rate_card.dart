/// Modèles immuables de la grille tarifaire d'entreprise ([EnterpriseRateCard]), des profils TJM ([CostProfileRate]), des calibres T-shirt ([TShirtEffortPreset]), des ratios transverses ([TransverseRatioSettings]) et des gains de productivité IA ([AiProductivitySettings]).
library;

import 'package:flutter/foundation.dart';

/// Devise monétaire utilisée pour les chiffrages TJM, Build (CAPEX), Run (OPEX) et TCO.
enum CostCurrency {
  /// Euro (€).
  eur('EUR', '€', 'Euro (€)'),

  /// Dollar américain ($).
  usd('USD', '\$', 'Dollar US (\$)'),

  /// Franc suisse (CHF).
  chf('CHF', 'CHF', 'Franc suisse (CHF)'),

  /// Dollar canadien (CA$).
  cad('CAD', 'CA\$', 'Dollar canadien (CA\$)'),

  /// Livre sterling (£).
  gbp('GBP', '£', 'Livre sterling (£)');

  /// Construit une devise de chiffrage.
  const CostCurrency(this.code, this.symbol, this.label);

  /// Code ISO 4217 sur 3 lettres (`EUR`, `USD`, `CHF`, `CAD`, `GBP`).
  final String code;

  /// Symbole monétaire court affiché avec les montants.
  final String symbol;

  /// Libellé complet lisible dans les sélecteurs.
  final String label;

  /// Résout une devise depuis JSON ou un alias courant, avec repli sur [eur].
  static CostCurrency fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final currency in CostCurrency.values) {
        if (currency.name.toLowerCase() == norm ||
            currency.code.toLowerCase() == norm ||
            currency.symbol.toLowerCase() == norm ||
            currency.label.toLowerCase() == norm) {
          return currency;
        }
      }
      switch (norm) {
        case 'euro':
        case 'euros':
          return CostCurrency.eur;
        case 'dollar':
        case 'dollars':
        case 'us_dollar':
        case 'us-dollar':
        case 'us\$':
          return CostCurrency.usd;
        case 'franc':
        case 'franc_suisse':
        case 'swiss_franc':
          return CostCurrency.chf;
        case 'cad\$':
        case 'canadian_dollar':
        case 'dollar_canadien':
          return CostCurrency.cad;
        case 'pound':
        case 'pounds':
        case 'sterling':
        case 'livre':
          return CostCurrency.gbp;
      }
    }
    return CostCurrency.eur;
  }
}

/// Mode contractuel de réalisation déterminant les TJM applicables.
enum CostDeliveryMode {
  /// Réalisation 100 % par les équipes internes.
  inHouse('Équipe interne'),

  /// Assistance technique / régie par prestataires ou ESN.
  timeAndMaterials('Régie / ESN'),

  /// Engagement forfaitaire clé en main par un intégrateur externe.
  fixedPrice('Forfait clé en main'),

  /// Équipe mixte combinant ressources internes et renforts ESN.
  hybrid('Hybride Interne + ESN');

  /// Construit un mode de delivery.
  const CostDeliveryMode(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un mode de delivery depuis JSON ou un alias courant, avec repli sur [hybrid].
  static CostDeliveryMode fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final mode in CostDeliveryMode.values) {
        if (mode.name.toLowerCase() == norm ||
            mode.label.toLowerCase() == norm) {
          return mode;
        }
      }
      switch (norm) {
        case 'in_house':
        case 'in-house':
        case 'internal':
        case 'interne':
          return CostDeliveryMode.inHouse;
        case 'time_and_materials':
        case 'time-and-materials':
        case 'tm':
        case 't&m':
        case 'regie':
        case 'régie':
        case 'esn':
        case 'external':
        case 'externe':
          return CostDeliveryMode.timeAndMaterials;
        case 'fixed_price':
        case 'fixed-price':
        case 'forfait':
        case 'turnkey':
          return CostDeliveryMode.fixedPrice;
        case 'hybride':
        case 'mixed':
        case 'mixte':
          return CostDeliveryMode.hybrid;
      }
    }
    return CostDeliveryMode.hybrid;
  }
}

/// Discipline d'ingénierie rattachée à un profil de coût ou à un lot WBS.
enum CostDiscipline {
  /// Logique métier, services applicatifs et règles du domaine.
  backend('Backend & Métier', 'Backend'),

  /// Interfaces utilisateur, parcours, composants et ergonomie.
  frontendUx('Frontend & UX/UI', 'Frontend/UX'),

  /// Schémas de données, persistance, migrations et analytique.
  dataModel('Data & Modélisation', 'Data'),

  /// Connecteurs externes, APIs REST/événements et contrats d'échange.
  integration('Intégrations & APIs', 'Intégrations'),

  /// Stratégie de test, scénarios BDD/Gherkin, TDD et automatisation QA.
  qaTesting('QA, BDD & Tests', 'QA/BDD'),

  /// Architecture technique, CI/CD, infrastructure Cloud et sécurité.
  devSecOps('Architecture & DevSecOps', 'DevSecOps'),

  /// Cadrage produit, pilotage Agile, spécifications et coordination.
  projectManagement('Pilotage & Produit', 'Pilotage');

  /// Construit une discipline de chiffrage.
  const CostDiscipline(this.label, this.shortLabel);

  /// Libellé complet affiché dans les formulaires et rapports.
  final String label;

  /// Étiquette courte pour les badges et colonnes compactes.
  final String shortLabel;

  /// Résout une discipline depuis JSON ou un alias courant, avec repli sur [backend].
  static CostDiscipline fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final discipline in CostDiscipline.values) {
        if (discipline.name.toLowerCase() == norm ||
            discipline.label.toLowerCase() == norm ||
            discipline.shortLabel.toLowerCase() == norm) {
          return discipline;
        }
      }
      switch (norm) {
        case 'back':
        case 'domain':
        case 'metier':
        case 'métier':
          return CostDiscipline.backend;
        case 'front':
        case 'frontend':
        case 'frontend_ux':
        case 'frontend-ux':
        case 'ux':
        case 'ui':
          return CostDiscipline.frontendUx;
        case 'data':
        case 'data_model':
        case 'data-model':
        case 'database':
        case 'db':
        case 'schema':
          return CostDiscipline.dataModel;
        case 'api':
        case 'apis':
        case 'integrations':
        case 'intégration':
        case 'intégrations':
          return CostDiscipline.integration;
        case 'qa':
        case 'qa_testing':
        case 'qa-testing':
        case 'bdd':
        case 'tdd':
        case 'test':
        case 'tests':
        case 'testing':
          return CostDiscipline.qaTesting;
        case 'devops':
        case 'dev_sec_ops':
        case 'dev-sec-ops':
        case 'ops':
        case 'infra':
        case 'cloud':
        case 'arch':
        case 'architecture':
        case 'security':
          return CostDiscipline.devSecOps;
        case 'pm':
        case 'po':
        case 'product':
        case 'project_management':
        case 'project-management':
        case 'management':
        case 'pilotage':
        case 'gestion':
          return CostDiscipline.projectManagement;
      }
    }
    return CostDiscipline.backend;
  }
}

/// Taille T-shirt d'estimation rapide ou saisie libre directe/PERT.
enum CostTShirtSize {
  /// Très simple (XS).
  xs('XS', 'Très simple (XS)'),

  /// Simple (S).
  s('S', 'Simple (S)'),

  /// Moyen (M).
  m('M', 'Moyen (M)'),

  /// Complexe (L).
  l('L', 'Complexe (L)'),

  /// Très complexe (XL).
  xl('XL', 'Très complexe (XL)'),

  /// Charge saisie librement en jours/homme directs ou PERT 3 points.
  custom('Sur mesure', 'Saisie libre (j/h / PERT)');

  /// Construit un calibre T-shirt.
  const CostTShirtSize(this.code, this.label);

  /// Code court (`XS`, `S`, `M`, `L`, `XL`, `Sur mesure`).
  final String code;

  /// Libellé descriptif complet.
  final String label;

  /// Résout une taille T-shirt depuis JSON ou un alias courant, avec repli sur [m].
  static CostTShirtSize fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final size in CostTShirtSize.values) {
        if (size.name.toLowerCase() == norm ||
            size.code.toLowerCase() == norm ||
            size.label.toLowerCase() == norm) {
          return size;
        }
      }
      switch (norm) {
        case 'extra_small':
        case 'extra-small':
        case 'xsmall':
          return CostTShirtSize.xs;
        case 'small':
          return CostTShirtSize.s;
        case 'medium':
          return CostTShirtSize.m;
        case 'large':
          return CostTShirtSize.l;
        case 'extra_large':
        case 'extra-large':
        case 'xlarge':
          return CostTShirtSize.xl;
        case 'free':
        case 'direct':
        case 'manual':
        case 'pert':
        case 'sur_mesure':
        case 'sur-mesure':
          return CostTShirtSize.custom;
      }
    }
    return CostTShirtSize.m;
  }
}

/// Calibrage PERT 3 points (Optimiste / Nominal / Pessimiste) associé à une taille T-shirt standard.
@immutable
class TShirtEffortPreset {
  /// Construit un barème d'effort T-shirt immuable.
  const TShirtEffortPreset({
    required this.size,
    required this.optimisticDays,
    required this.mostLikelyDays,
    required this.pessimisticDays,
  });

  /// Barème standard par défaut pour les tailles `XS` à `XL`.
  static const List<TShirtEffortPreset> defaults = <TShirtEffortPreset>[
    TShirtEffortPreset(
      size: CostTShirtSize.xs,
      optimisticDays: 0.5,
      mostLikelyDays: 1.0,
      pessimisticDays: 2.0,
    ),
    TShirtEffortPreset(
      size: CostTShirtSize.s,
      optimisticDays: 1.0,
      mostLikelyDays: 2.0,
      pessimisticDays: 4.0,
    ),
    TShirtEffortPreset(
      size: CostTShirtSize.m,
      optimisticDays: 3.0,
      mostLikelyDays: 5.0,
      pessimisticDays: 8.0,
    ),
    TShirtEffortPreset(
      size: CostTShirtSize.l,
      optimisticDays: 6.0,
      mostLikelyDays: 10.0,
      pessimisticDays: 16.0,
    ),
    TShirtEffortPreset(
      size: CostTShirtSize.xl,
      optimisticDays: 12.0,
      mostLikelyDays: 20.0,
      pessimisticDays: 32.0,
    ),
  ];

  /// Taille T-shirt calibrée (ne doit pas être [CostTShirtSize.custom]).
  final CostTShirtSize size;

  /// Charge optimiste `O` en jours/homme (`>= 0`).
  final double optimisticDays;

  /// Charge la plus probable `M` en jours/homme (`>= optimisticDays`).
  final double mostLikelyDays;

  /// Charge pessimiste `P` en jours/homme (`>= mostLikelyDays`).
  final double pessimisticDays;

  /// Charge espérée PERT `(O + 4M + P) / 6` en jours/homme.
  double get expectedDays =>
      (optimisticDays + 4.0 * mostLikelyDays + pessimisticDays) / 6.0;

  /// Vérifie les invariants du calibre T-shirt (`size != custom` et `0 <= O <= M <= P`).
  void validate() {
    if (size == CostTShirtSize.custom) {
      throw const FormatException(
        'TShirtEffortPreset.size ne peut pas être CostTShirtSize.custom.',
      );
    }
    if (!optimisticDays.isFinite ||
        !mostLikelyDays.isFinite ||
        !pessimisticDays.isFinite ||
        optimisticDays < 0.0 ||
        mostLikelyDays < optimisticDays ||
        pessimisticDays < mostLikelyDays) {
      throw FormatException(
        'Bornes PERT invalides pour ${size.code} : '
        'O=$optimisticDays, M=$mostLikelyDays, P=$pessimisticDays.',
      );
    }
  }

  /// Retourne une copie modifiée.
  TShirtEffortPreset copyWith({
    CostTShirtSize? size,
    double? optimisticDays,
    double? mostLikelyDays,
    double? pessimisticDays,
  }) => TShirtEffortPreset(
    size: size ?? this.size,
    optimisticDays: optimisticDays ?? this.optimisticDays,
    mostLikelyDays: mostLikelyDays ?? this.mostLikelyDays,
    pessimisticDays: pessimisticDays ?? this.pessimisticDays,
  );

  /// Sérialise le calibre T-shirt en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'size': size.name,
    'optimisticDays': optimisticDays,
    'mostLikelyDays': mostLikelyDays,
    'pessimisticDays': pessimisticDays,
  };

  /// Désérialise un calibre T-shirt depuis JSON en normalisant `0 <= O <= M <= P`.
  factory TShirtEffortPreset.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'TShirtEffortPreset doit être un objet JSON.',
      );
    }
    final parsedSize = CostTShirtSize.fromJson(raw['size']);
    final effectiveSize = parsedSize == CostTShirtSize.custom
        ? CostTShirtSize.m
        : parsedSize;
    final fallback = defaults.firstWhere(
      (p) => p.size == effectiveSize,
      orElse: () => defaults[2],
    );
    final values = <double>[
      _nonNegativeDouble(raw['optimisticDays'], fallback.optimisticDays),
      _nonNegativeDouble(raw['mostLikelyDays'], fallback.mostLikelyDays),
      _nonNegativeDouble(raw['pessimisticDays'], fallback.pessimisticDays),
    ]..sort();
    final preset = TShirtEffortPreset(
      size: effectiveSize,
      optimisticDays: values[0],
      mostLikelyDays: values[1],
      pessimisticDays: values[2],
    );
    preset.validate();
    return preset;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TShirtEffortPreset &&
          other.size == size &&
          other.optimisticDays == optimisticDays &&
          other.mostLikelyDays == mostLikelyDays &&
          other.pessimisticDays == pessimisticDays;

  @override
  int get hashCode =>
      Object.hash(size, optimisticDays, mostLikelyDays, pessimisticDays);
}

/// Profil métier/technique et taux journaliers moyens (TJM interne et externe).
@immutable
class CostProfileRate {
  /// Construit un profil tarifaire immuable.
  const CostProfileRate({
    required this.id,
    this.code = 'PRF',
    required this.name,
    this.seniority = 'Confirmé',
    this.discipline = CostDiscipline.backend,
    required this.internalDailyRate,
    required this.externalDailyRate,
  });

  /// Grille standard de 7 profils couvrant l'ingénierie logicielle et le pilotage.
  static const List<CostProfileRate> defaults = <CostProfileRate>[
    CostProfileRate(
      id: 'prof_arch',
      code: 'PRF-ARCH',
      name: 'Architecte & Tech Lead',
      seniority: 'Lead',
      discipline: CostDiscipline.devSecOps,
      internalDailyRate: 650.0,
      externalDailyRate: 950.0,
    ),
    CostProfileRate(
      id: 'prof_back',
      code: 'PRF-BACK',
      name: 'Développeur Backend & Métier',
      seniority: 'Senior',
      discipline: CostDiscipline.backend,
      internalDailyRate: 520.0,
      externalDailyRate: 750.0,
    ),
    CostProfileRate(
      id: 'prof_front',
      code: 'PRF-FRONT',
      name: 'Développeur Frontend & UX',
      seniority: 'Confirmé',
      discipline: CostDiscipline.frontendUx,
      internalDailyRate: 500.0,
      externalDailyRate: 720.0,
    ),
    CostProfileRate(
      id: 'prof_data',
      code: 'PRF-DATA',
      name: 'Ingénieur Data & Intégration',
      seniority: 'Senior',
      discipline: CostDiscipline.dataModel,
      internalDailyRate: 540.0,
      externalDailyRate: 780.0,
    ),
    CostProfileRate(
      id: 'prof_qa',
      code: 'PRF-QA',
      name: 'Ingénieur QA / BDD & Automatisation',
      seniority: 'Confirmé',
      discipline: CostDiscipline.qaTesting,
      internalDailyRate: 460.0,
      externalDailyRate: 650.0,
    ),
    CostProfileRate(
      id: 'prof_ops',
      code: 'PRF-OPS',
      name: 'Ingénieur Cloud & DevSecOps',
      seniority: 'Senior',
      discipline: CostDiscipline.devSecOps,
      internalDailyRate: 580.0,
      externalDailyRate: 850.0,
    ),
    CostProfileRate(
      id: 'prof_pm',
      code: 'PRF-PM',
      name: 'Product Owner / Chef de projet',
      seniority: 'Senior',
      discipline: CostDiscipline.projectManagement,
      internalDailyRate: 550.0,
      externalDailyRate: 800.0,
    ),
  ];

  /// Identifiant technique unique du profil (ex. `prof_back`).
  final String id;

  /// Code lisible du profil (ex. `PRF-BACK`).
  final String code;

  /// Intitulé du rôle ou métier.
  final String name;

  /// Niveau de séniorité (`Junior`, `Confirmé`, `Senior`, `Lead`…).
  final String seniority;

  /// Discipline principale rattachée au profil.
  final CostDiscipline discipline;

  /// Coût journalier chargé d'une ressource interne (`>= 0`).
  final double internalDailyRate;

  /// Taux journalier facturé par un prestataire / ESN (`>= 0`).
  final double externalDailyRate;

  /// Calcule le TJM effectif selon le [mode] de réalisation retenu.
  double effectiveDailyRate(CostDeliveryMode mode) => switch (mode) {
    CostDeliveryMode.inHouse => internalDailyRate,
    CostDeliveryMode.timeAndMaterials ||
    CostDeliveryMode.fixedPrice => externalDailyRate,
    CostDeliveryMode.hybrid => (internalDailyRate + externalDailyRate) / 2.0,
  };

  /// Vérifie les invariants du profil tarifaire.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('CostProfileRate.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'CostProfileRate.name ne peut pas être vide.',
      );
    }
    if (!internalDailyRate.isFinite || internalDailyRate < 0.0) {
      throw const FormatException(
        'CostProfileRate.internalDailyRate doit être positif ou nul.',
      );
    }
    if (!externalDailyRate.isFinite || externalDailyRate < 0.0) {
      throw const FormatException(
        'CostProfileRate.externalDailyRate doit être positif ou nul.',
      );
    }
  }

  /// Retourne une copie modifiée.
  CostProfileRate copyWith({
    String? id,
    String? code,
    String? name,
    String? seniority,
    CostDiscipline? discipline,
    double? internalDailyRate,
    double? externalDailyRate,
  }) => CostProfileRate(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    seniority: seniority ?? this.seniority,
    discipline: discipline ?? this.discipline,
    internalDailyRate: internalDailyRate ?? this.internalDailyRate,
    externalDailyRate: externalDailyRate ?? this.externalDailyRate,
  );

  /// Sérialise le profil tarifaire en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'seniority': seniority,
    'discipline': discipline.name,
    'internalDailyRate': internalDailyRate,
    'externalDailyRate': externalDailyRate,
  };

  /// Désérialise un profil tarifaire depuis JSON avec valeurs de repli tolérantes.
  factory CostProfileRate.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('CostProfileRate doit être un objet JSON.');
    }
    final rawName =
        (raw['name'] as String?)?.trim() ??
        (raw['title'] as String?)?.trim() ??
        (raw['role'] as String?)?.trim() ??
        '';
    final name = rawName.isEmpty ? 'Profil sans nom' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawSeniority = (raw['seniority'] as String?)?.trim() ?? '';
    final discipline = CostDiscipline.fromJson(raw['discipline']);
    final internalRate = _nonNegativeDouble(
      raw['internalDailyRate'] ?? raw['internalRate'] ?? raw['dailyRate'],
      500.0,
    );
    final externalRate = _nonNegativeDouble(
      raw['externalDailyRate'] ?? raw['externalRate'] ?? raw['dailyRate'],
      internalRate,
    );
    final profile = CostProfileRate(
      id: rawId.isEmpty ? 'prof_${name.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'PRF' : rawCode,
      name: name,
      seniority: rawSeniority.isEmpty ? 'Confirmé' : rawSeniority,
      discipline: discipline,
      internalDailyRate: internalRate,
      externalDailyRate: externalRate,
    );
    profile.validate();
    return profile;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostProfileRate &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.seniority == seniority &&
          other.discipline == discipline &&
          other.internalDailyRate == internalDailyRate &&
          other.externalDailyRate == externalDailyRate;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    seniority,
    discipline,
    internalDailyRate,
    externalDailyRate,
  );
}

/// Ratios forfaitaires d'activités transverses et provision d'aléas appliqués au Build (`0..200` %).
@immutable
class TransverseRatioSettings {
  /// Construit les ratios transverses immuables.
  const TransverseRatioSettings({
    this.projectManagementPct = 15.0,
    this.architectureDevOpsPct = 10.0,
    this.transverseQaPct = 10.0,
    this.contingencyPct = 15.0,
  });

  /// Ratios transverses standards par défaut.
  static const TransverseRatioSettings defaults = TransverseRatioSettings();

  /// Part de gestion de projet, cérémonies Agile et cadrage produit (`%`, défaut `15.0`).
  final double projectManagementPct;

  /// Part d'architecture transverse, socle CI/CD et DevSecOps (`%`, défaut `10.0`).
  final double architectureDevOpsPct;

  /// Part de recette transverse, intégration bout-en-bout et tests E2E (`%`, défaut `10.0`).
  final double transverseQaPct;

  /// Provision pour aléas et complexité d'intégration (`%`, défaut `15.0`).
  final double contingencyPct;

  /// Vérifie que chaque pourcentage est compris dans l'intervalle `[0, 200]`.
  void validate() {
    _validateRange(
      projectManagementPct,
      0.0,
      200.0,
      'TransverseRatioSettings.projectManagementPct',
    );
    _validateRange(
      architectureDevOpsPct,
      0.0,
      200.0,
      'TransverseRatioSettings.architectureDevOpsPct',
    );
    _validateRange(
      transverseQaPct,
      0.0,
      200.0,
      'TransverseRatioSettings.transverseQaPct',
    );
    _validateRange(
      contingencyPct,
      0.0,
      200.0,
      'TransverseRatioSettings.contingencyPct',
    );
  }

  /// Retourne une copie modifiée.
  TransverseRatioSettings copyWith({
    double? projectManagementPct,
    double? architectureDevOpsPct,
    double? transverseQaPct,
    double? contingencyPct,
  }) => TransverseRatioSettings(
    projectManagementPct: projectManagementPct ?? this.projectManagementPct,
    architectureDevOpsPct: architectureDevOpsPct ?? this.architectureDevOpsPct,
    transverseQaPct: transverseQaPct ?? this.transverseQaPct,
    contingencyPct: contingencyPct ?? this.contingencyPct,
  );

  /// Sérialise les ratios transverses en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'projectManagementPct': projectManagementPct,
    'architectureDevOpsPct': architectureDevOpsPct,
    'transverseQaPct': transverseQaPct,
    'contingencyPct': contingencyPct,
  };

  /// Désérialise les ratios transverses depuis JSON en bornant les valeurs dans `[0, 200]`.
  factory TransverseRatioSettings.fromJson(Object? raw) {
    if (raw == null) return defaults;
    if (raw is! Map) {
      throw const FormatException(
        'TransverseRatioSettings doit être un objet JSON.',
      );
    }
    final settings = TransverseRatioSettings(
      projectManagementPct: _clampedDouble(
        raw['projectManagementPct'],
        defaults.projectManagementPct,
        0.0,
        200.0,
      ),
      architectureDevOpsPct: _clampedDouble(
        raw['architectureDevOpsPct'],
        defaults.architectureDevOpsPct,
        0.0,
        200.0,
      ),
      transverseQaPct: _clampedDouble(
        raw['transverseQaPct'],
        defaults.transverseQaPct,
        0.0,
        200.0,
      ),
      contingencyPct: _clampedDouble(
        raw['contingencyPct'],
        defaults.contingencyPct,
        0.0,
        200.0,
      ),
    );
    settings.validate();
    return settings;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransverseRatioSettings &&
          other.projectManagementPct == projectManagementPct &&
          other.architectureDevOpsPct == architectureDevOpsPct &&
          other.transverseQaPct == transverseQaPct &&
          other.contingencyPct == contingencyPct;

  @override
  int get hashCode => Object.hash(
    projectManagementPct,
    architectureDevOpsPct,
    transverseQaPct,
    contingencyPct,
  );
}

/// Hypothèses de gains de productivité apportés par l'ingénierie assistée par IA (`0..80` %).
@immutable
class AiProductivitySettings {
  /// Construit les paramètres d'accélération IA immuables.
  const AiProductivitySettings({
    this.enabled = true,
    this.backendGainPct = 25.0,
    this.frontendUxGainPct = 25.0,
    this.dataIntegrationGainPct = 20.0,
    this.qaTestingGainPct = 35.0,
    this.devSecOpsGainPct = 15.0,
    this.pmSpecsGainPct = 20.0,
  });

  /// Paramètres d'accélération IA standards par défaut.
  static const AiProductivitySettings defaults = AiProductivitySettings();

  /// Active ou désactive l'application des gains IA sur les lots éligibles.
  final bool enabled;

  /// Gain de productivité IA sur le développement Backend & Métier (`%`, défaut `25.0`).
  final double backendGainPct;

  /// Gain de productivité IA sur le Frontend & UX/UI (`%`, défaut `25.0`).
  final double frontendUxGainPct;

  /// Gain de productivité IA sur la Data, la modélisation et les intégrations (`%`, défaut `20.0`).
  final double dataIntegrationGainPct;

  /// Gain de productivité IA sur les tests QA, BDD et TDD (`%`, défaut `35.0`).
  final double qaTestingGainPct;

  /// Gain de productivité IA sur l'architecture et le DevSecOps (`%`, défaut `15.0`).
  final double devSecOpsGainPct;

  /// Gain de productivité IA sur le cadrage produit et la rédaction de specs (`%`, défaut `20.0`).
  final double pmSpecsGainPct;

  /// Retourne le gain IA (`0..80` %) applicable à [discipline], ou `0.0` si [enabled] vaut `false`.
  double gainPctFor(CostDiscipline discipline) {
    if (!enabled) return 0.0;
    return switch (discipline) {
      CostDiscipline.backend => backendGainPct,
      CostDiscipline.frontendUx => frontendUxGainPct,
      CostDiscipline.dataModel ||
      CostDiscipline.integration => dataIntegrationGainPct,
      CostDiscipline.qaTesting => qaTestingGainPct,
      CostDiscipline.devSecOps => devSecOpsGainPct,
      CostDiscipline.projectManagement => pmSpecsGainPct,
    };
  }

  /// Vérifie que chaque gain de productivité est compris dans `[0, 80]`.
  void validate() {
    _validateRange(
      backendGainPct,
      0.0,
      80.0,
      'AiProductivitySettings.backendGainPct',
    );
    _validateRange(
      frontendUxGainPct,
      0.0,
      80.0,
      'AiProductivitySettings.frontendUxGainPct',
    );
    _validateRange(
      dataIntegrationGainPct,
      0.0,
      80.0,
      'AiProductivitySettings.dataIntegrationGainPct',
    );
    _validateRange(
      qaTestingGainPct,
      0.0,
      80.0,
      'AiProductivitySettings.qaTestingGainPct',
    );
    _validateRange(
      devSecOpsGainPct,
      0.0,
      80.0,
      'AiProductivitySettings.devSecOpsGainPct',
    );
    _validateRange(
      pmSpecsGainPct,
      0.0,
      80.0,
      'AiProductivitySettings.pmSpecsGainPct',
    );
  }

  /// Retourne une copie modifiée.
  AiProductivitySettings copyWith({
    bool? enabled,
    double? backendGainPct,
    double? frontendUxGainPct,
    double? dataIntegrationGainPct,
    double? qaTestingGainPct,
    double? devSecOpsGainPct,
    double? pmSpecsGainPct,
  }) => AiProductivitySettings(
    enabled: enabled ?? this.enabled,
    backendGainPct: backendGainPct ?? this.backendGainPct,
    frontendUxGainPct: frontendUxGainPct ?? this.frontendUxGainPct,
    dataIntegrationGainPct:
        dataIntegrationGainPct ?? this.dataIntegrationGainPct,
    qaTestingGainPct: qaTestingGainPct ?? this.qaTestingGainPct,
    devSecOpsGainPct: devSecOpsGainPct ?? this.devSecOpsGainPct,
    pmSpecsGainPct: pmSpecsGainPct ?? this.pmSpecsGainPct,
  );

  /// Sérialise les paramètres d'accélération IA en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'backendGainPct': backendGainPct,
    'frontendUxGainPct': frontendUxGainPct,
    'dataIntegrationGainPct': dataIntegrationGainPct,
    'qaTestingGainPct': qaTestingGainPct,
    'devSecOpsGainPct': devSecOpsGainPct,
    'pmSpecsGainPct': pmSpecsGainPct,
  };

  /// Désérialise les paramètres d'accélération IA depuis JSON en bornant chaque gain dans `[0, 80]`.
  factory AiProductivitySettings.fromJson(Object? raw) {
    if (raw == null) return defaults;
    if (raw is! Map) {
      throw const FormatException(
        'AiProductivitySettings doit être un objet JSON.',
      );
    }
    final settings = AiProductivitySettings(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      backendGainPct: _clampedDouble(
        raw['backendGainPct'],
        defaults.backendGainPct,
        0.0,
        80.0,
      ),
      frontendUxGainPct: _clampedDouble(
        raw['frontendUxGainPct'],
        defaults.frontendUxGainPct,
        0.0,
        80.0,
      ),
      dataIntegrationGainPct: _clampedDouble(
        raw['dataIntegrationGainPct'],
        defaults.dataIntegrationGainPct,
        0.0,
        80.0,
      ),
      qaTestingGainPct: _clampedDouble(
        raw['qaTestingGainPct'],
        defaults.qaTestingGainPct,
        0.0,
        80.0,
      ),
      devSecOpsGainPct: _clampedDouble(
        raw['devSecOpsGainPct'],
        defaults.devSecOpsGainPct,
        0.0,
        80.0,
      ),
      pmSpecsGainPct: _clampedDouble(
        raw['pmSpecsGainPct'],
        defaults.pmSpecsGainPct,
        0.0,
        80.0,
      ),
    );
    settings.validate();
    return settings;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiProductivitySettings &&
          other.enabled == enabled &&
          other.backendGainPct == backendGainPct &&
          other.frontendUxGainPct == frontendUxGainPct &&
          other.dataIntegrationGainPct == dataIntegrationGainPct &&
          other.qaTestingGainPct == qaTestingGainPct &&
          other.devSecOpsGainPct == devSecOpsGainPct &&
          other.pmSpecsGainPct == pmSpecsGainPct;

  @override
  int get hashCode => Object.hash(
    enabled,
    backendGainPct,
    frontendUxGainPct,
    dataIntegrationGainPct,
    qaTestingGainPct,
    devSecOpsGainPct,
    pmSpecsGainPct,
  );
}

/// Référentiel tarifaire transverse d'entreprise partagé entre les projets du workspace.
@immutable
class EnterpriseRateCard {
  /// Construit une grille tarifaire d'entreprise immuable.
  EnterpriseRateCard({
    this.currency = CostCurrency.eur,
    this.hoursPerDay = 7.5,
    this.defaultDeliveryMode = CostDeliveryMode.hybrid,
    List<CostProfileRate> profiles = CostProfileRate.defaults,
    List<TShirtEffortPreset> tshirtPresets = TShirtEffortPreset.defaults,
    this.transverseRatios = TransverseRatioSettings.defaults,
    this.aiProductivity = AiProductivitySettings.defaults,
    this.notes = '',
  }) : profiles = List<CostProfileRate>.unmodifiable(profiles),
       tshirtPresets = List<TShirtEffortPreset>.unmodifiable(tshirtPresets);

  /// Grille tarifaire d'entreprise standard par défaut.
  static final EnterpriseRateCard defaults = EnterpriseRateCard();

  /// Devise de référence de l'entreprise.
  final CostCurrency currency;

  /// Nombre d'heures ouvrées par jour/homme (`7.5` par défaut).
  final double hoursPerDay;

  /// Mode contractuel de delivery appliqué par défaut aux nouveaux chiffrages.
  final CostDeliveryMode defaultDeliveryMode;

  /// Catalogue des profils métiers/techniques et de leurs TJM.
  final List<CostProfileRate> profiles;

  /// Calibrages PERT par taille T-shirt (`XS` à `XL`).
  final List<TShirtEffortPreset> tshirtPresets;

  /// Ratios d'activités transverses et provision d'aléas standards.
  final TransverseRatioSettings transverseRatios;

  /// Paramètres d'accélération IA par discipline.
  final AiProductivitySettings aiProductivity;

  /// Notes méthodologiques ou conventions financières internes.
  final String notes;

  /// Vrai si cette grille est strictement identique aux valeurs [defaults].
  bool get isDefault => this == defaults;

  /// Recherche un profil par identifiant, code `PRF-xxx` ou nom (insensible à la casse).
  CostProfileRate? findProfile(String idOrCodeOrName) {
    final needle = idOrCodeOrName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final profile in profiles) {
      if (profile.id.toLowerCase() == needle ||
          (profile.code.isNotEmpty && profile.code.toLowerCase() == needle)) {
        return profile;
      }
    }
    for (final profile in profiles) {
      if (profile.name.toLowerCase() == needle) return profile;
    }
    return null;
  }

  /// Résout le profil de référence pour [discipline] (premier profil correspondant, sinon premier profil disponible, sinon premier profil par défaut).
  CostProfileRate resolveProfileForDiscipline(CostDiscipline discipline) {
    for (final profile in profiles) {
      if (profile.discipline == discipline) return profile;
    }
    if (profiles.isNotEmpty) return profiles.first;
    return CostProfileRate.defaults.first;
  }

  /// Retourne le calibre PERT correspondant à [size] (repli sur [TShirtEffortPreset.defaults] puis `M`).
  TShirtEffortPreset presetFor(CostTShirtSize size) {
    final target = size == CostTShirtSize.custom ? CostTShirtSize.m : size;
    for (final preset in tshirtPresets) {
      if (preset.size == target) return preset;
    }
    for (final preset in TShirtEffortPreset.defaults) {
      if (preset.size == target) return preset;
    }
    return TShirtEffortPreset.defaults[2];
  }

  /// Calcule le TJM moyen arithmétique de la grille pour [mode] (ou [defaultDeliveryMode] si omis).
  double averageDailyRate([CostDeliveryMode? mode]) {
    final effectiveMode = mode ?? defaultDeliveryMode;
    final source = profiles.isNotEmpty ? profiles : CostProfileRate.defaults;
    final total = source.fold<double>(
      0.0,
      (sum, profile) => sum + profile.effectiveDailyRate(effectiveMode),
    );
    return total / source.length;
  }

  /// Vérifie les invariants structurels de la grille tarifaire d'entreprise.
  void validate() {
    if (!hoursPerDay.isFinite || hoursPerDay <= 0.0 || hoursPerDay > 24.0) {
      throw const FormatException(
        'EnterpriseRateCard.hoursPerDay doit être compris dans ]0, 24].',
      );
    }
    final seenProfileIds = <String>{};
    for (final profile in profiles) {
      profile.validate();
      if (!seenProfileIds.add(profile.id)) {
        throw FormatException('Profil TJM dupliqué : ${profile.id}');
      }
    }
    final seenSizes = <CostTShirtSize>{};
    for (final preset in tshirtPresets) {
      preset.validate();
      if (!seenSizes.add(preset.size)) {
        throw FormatException(
          'Calibre T-shirt dupliqué : ${preset.size.code}',
        );
      }
    }
    transverseRatios.validate();
    aiProductivity.validate();
  }

  /// Retourne une copie modifiée.
  EnterpriseRateCard copyWith({
    CostCurrency? currency,
    double? hoursPerDay,
    CostDeliveryMode? defaultDeliveryMode,
    List<CostProfileRate>? profiles,
    List<TShirtEffortPreset>? tshirtPresets,
    TransverseRatioSettings? transverseRatios,
    AiProductivitySettings? aiProductivity,
    String? notes,
  }) => EnterpriseRateCard(
    currency: currency ?? this.currency,
    hoursPerDay: hoursPerDay ?? this.hoursPerDay,
    defaultDeliveryMode: defaultDeliveryMode ?? this.defaultDeliveryMode,
    profiles: profiles ?? this.profiles,
    tshirtPresets: tshirtPresets ?? this.tshirtPresets,
    transverseRatios: transverseRatios ?? this.transverseRatios,
    aiProductivity: aiProductivity ?? this.aiProductivity,
    notes: notes ?? this.notes,
  );

  /// Sérialise la grille tarifaire d'entreprise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'currency': currency.name,
    'hoursPerDay': hoursPerDay,
    'defaultDeliveryMode': defaultDeliveryMode.name,
    'profiles': [for (final p in profiles) p.toJson()],
    'tshirtPresets': [for (final t in tshirtPresets) t.toJson()],
    'transverseRatios': transverseRatios.toJson(),
    'aiProductivity': aiProductivity.toJson(),
    'notes': notes,
  };

  /// Désérialise une grille tarifaire d'entreprise depuis JSON (retourne [defaults] si `raw == null`).
  factory EnterpriseRateCard.fromJson(Object? raw) {
    if (raw == null) return defaults;
    if (raw is! Map) {
      throw const FormatException(
        'EnterpriseRateCard doit être un objet JSON.',
      );
    }

    List<CostProfileRate> parsedProfiles = CostProfileRate.defaults;
    if (raw['profiles'] is List) {
      final list = <CostProfileRate>[];
      final seenIds = <String>{};
      for (final item in raw['profiles'] as List) {
        var profile = CostProfileRate.fromJson(item);
        if (!seenIds.add(profile.id)) {
          var suffix = 2;
          while (!seenIds.add('${profile.id}_$suffix')) {
            suffix++;
          }
          profile = profile.copyWith(id: '${profile.id}_$suffix');
        }
        list.add(profile);
      }
      parsedProfiles = list;
    }

    List<TShirtEffortPreset> parsedPresets = TShirtEffortPreset.defaults;
    if (raw['tshirtPresets'] is List) {
      final list = <TShirtEffortPreset>[];
      final seenSizes = <CostTShirtSize>{};
      for (final item in raw['tshirtPresets'] as List) {
        final preset = TShirtEffortPreset.fromJson(item);
        if (seenSizes.add(preset.size)) {
          list.add(preset);
        }
      }
      parsedPresets = list;
    }

    final card = EnterpriseRateCard(
      currency: CostCurrency.fromJson(raw['currency']),
      hoursPerDay: _clampedDouble(raw['hoursPerDay'], 7.5, 0.5, 24.0),
      defaultDeliveryMode: CostDeliveryMode.fromJson(
        raw['defaultDeliveryMode'] ?? raw['deliveryMode'],
      ),
      profiles: parsedProfiles,
      tshirtPresets: parsedPresets,
      transverseRatios: TransverseRatioSettings.fromJson(
        raw['transverseRatios'],
      ),
      aiProductivity: AiProductivitySettings.fromJson(raw['aiProductivity']),
      notes: (raw['notes'] as String?) ?? '',
    );
    card.validate();
    return card;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnterpriseRateCard &&
          other.currency == currency &&
          other.hoursPerDay == hoursPerDay &&
          other.defaultDeliveryMode == defaultDeliveryMode &&
          listEquals(other.profiles, profiles) &&
          listEquals(other.tshirtPresets, tshirtPresets) &&
          other.transverseRatios == transverseRatios &&
          other.aiProductivity == aiProductivity &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(
    currency,
    hoursPerDay,
    defaultDeliveryMode,
    Object.hashAll(profiles),
    Object.hashAll(tshirtPresets),
    transverseRatios,
    aiProductivity,
    notes,
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

void _validateRange(double value, double min, double max, String fieldName) {
  if (!value.isFinite || value < min || value > max) {
    throw FormatException(
      '$fieldName doit être compris dans [$min, $max] (reçu : $value).',
    );
  }
}
