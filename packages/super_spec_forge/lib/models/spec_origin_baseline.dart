/// Empreinte d'origine Spec ([SpecOriginBaseline], [SpecFeatureContribution])
/// rattachée à une entrée de contrat Design lors de la promotion d'un objet
/// métier depuis un projet Spec.
library;

import 'package:flutter/foundation.dart';

import 'business_object_spec.dart';
import 'business_rule_spec.dart';

/// Trace immuable de la contribution d'une Feature Portfolio ([SpecFeatureSpec])
/// à la définition d'un objet métier promu dans l'espace Design.
@immutable
class SpecFeatureContribution {
  /// Crée une contribution de feature immuable.
  SpecFeatureContribution({
    required this.featureId,
    this.featureCode = '',
    this.featureName = '',
    required DateTime promotedAt,
  }) : promotedAt = promotedAt.toUtc();

  /// Identifiant stable de la Feature Portfolio source.
  final String featureId;

  /// Code court métier de la Feature source (ex. `FEAT-01`).
  final String featureCode;

  /// Nom fonctionnel de la Feature source.
  final String featureName;

  /// Horodatage UTC de la promotion depuis cette Feature.
  final DateTime promotedAt;

  /// Libellé court d'affichage privilégiant le code métier, puis le nom, puis l'identifiant.
  String get displayLabel => featureCode.trim().isNotEmpty
      ? featureCode.trim()
      : (featureName.trim().isNotEmpty ? featureName.trim() : featureId);

  /// Vérifie les invariants de la contribution de feature.
  void validate() {
    if (featureId.trim().isEmpty) {
      throw const FormatException(
        'SpecFeatureContribution.featureId ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée de cette contribution de feature.
  SpecFeatureContribution copyWith({
    String? featureId,
    String? featureCode,
    String? featureName,
    DateTime? promotedAt,
  }) => SpecFeatureContribution(
    featureId: featureId ?? this.featureId,
    featureCode: featureCode ?? this.featureCode,
    featureName: featureName ?? this.featureName,
    promotedAt: promotedAt ?? this.promotedAt,
  );

  /// Sérialise la contribution de feature en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'featureId': featureId,
    if (featureCode.isNotEmpty) 'featureCode': featureCode,
    if (featureName.isNotEmpty) 'featureName': featureName,
    'promotedAt': promotedAt.toUtc().toIso8601String(),
  };

  /// Désérialise et valide une contribution de feature depuis JSON.
  factory SpecFeatureContribution.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'SpecFeatureContribution doit être un objet JSON.',
      );
    }
    final rawPromotedAt = raw['promotedAt'];
    final parsedPromotedAt = rawPromotedAt is String
        ? DateTime.tryParse(rawPromotedAt)
        : null;
    if (parsedPromotedAt == null) {
      throw const FormatException(
        'SpecFeatureContribution.promotedAt invalide.',
      );
    }
    final contribution = SpecFeatureContribution(
      featureId: (raw['featureId'] as String?)?.trim() ?? '',
      featureCode: (raw['featureCode'] as String?)?.trim() ?? '',
      featureName: (raw['featureName'] as String?)?.trim() ?? '',
      promotedAt: parsedPromotedAt,
    );
    contribution.validate();
    return contribution;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecFeatureContribution &&
          other.featureId == featureId &&
          other.featureCode == featureCode &&
          other.featureName == featureName &&
          other.promotedAt == promotedAt;

  @override
  int get hashCode => Object.hash(
    featureId,
    featureCode,
    featureName,
    promotedAt,
  );
}

/// Photographie immuable de l'origine Spec d'un objet métier promu vers Design,
/// permettant aux analyseurs de dérive de détecter les écarts ultérieurs entre
/// la spécification fonctionnelle et le modèle Design.
@immutable
class SpecOriginBaseline {
  /// Crée une empreinte d'origine Spec immuable.
  SpecOriginBaseline({
    required this.projectId,
    this.projectName = '',
    this.featureId = '',
    this.featureCode = '',
    required this.specObjectId,
    required DateTime promotedAt,
    required this.baseSpecObject,
    Map<String, String> ruleFingerprints = const <String, String>{},
    List<SpecFeatureContribution> contributingFeatures =
        const <SpecFeatureContribution>[],
  }) : promotedAt = promotedAt.toUtc(),
       ruleFingerprints = Map<String, String>.unmodifiable(ruleFingerprints),
       contributingFeatures = List<SpecFeatureContribution>.unmodifiable(
         _normalizeContributingFeatures(
           contributingFeatures: contributingFeatures,
           featureId: featureId,
           featureCode: featureCode,
           promotedAt: promotedAt,
         ),
       );

  /// Identifiant du projet Spec source ([SpecForgeProject.id]).
  final String projectId;

  /// Nom affiché du projet Spec source au moment de la promotion.
  final String projectName;

  /// Identifiant de la dernière Feature Portfolio source promue (vide si projet hors découpage).
  final String featureId;

  /// Code métier de la dernière Feature Portfolio source promue (vide si projet hors découpage).
  final String featureCode;

  /// Identifiant de l'objet métier source ([BusinessObjectSpec.id]) dans la Spec.
  final String specObjectId;

  /// Horodatage UTC de la dernière promotion vers Design.
  final DateTime promotedAt;

  /// Photographie complète du [BusinessObjectSpec] source au moment de la promotion.
  final BusinessObjectSpec baseSpecObject;

  /// Empreintes canoniques des règles de gestion Spec (`code -> empreinte`) liées
  /// à l'objet au moment de la promotion.
  final Map<String, String> ruleFingerprints;

  /// Historique ordonné et dédoublonné des Features ayant contribué à cet objet Design.
  final List<SpecFeatureContribution> contributingFeatures;

  /// Résumé compact des codes/libellés des features contributrices (ex. `FEAT-01, FEAT-02`).
  String get featuresSummaryLabel {
    if (contributingFeatures.isNotEmpty) {
      final labels = <String>[
        for (final c in contributingFeatures)
          if (c.displayLabel.trim().isNotEmpty) c.displayLabel.trim(),
      ];
      if (labels.isNotEmpty) {
        return labels.join(', ');
      }
    }
    return featureCode.trim();
  }

  /// Fusionne une nouvelle [contribution] de feature dans cette empreinte d'origine
  /// en dédoublonnant [contributingFeatures] par `featureId`, en actualisant la
  /// dernière feature promue et en cumulant les empreintes de règles métier.
  SpecOriginBaseline mergeContribution(
    SpecFeatureContribution contribution, {
    required BusinessObjectSpec nextBaseSpecObject,
    required Map<String, String> nextRuleFingerprints,
    String? projectName,
  }) {
    contribution.validate();
    final normalized = SpecFeatureContribution(
      featureId: contribution.featureId.trim(),
      featureCode: contribution.featureCode.trim(),
      featureName: contribution.featureName.trim(),
      promotedAt: contribution.promotedAt,
    );
    final seenIds = <String>{};
    var updatedExisting = false;
    final mergedContributions = <SpecFeatureContribution>[];
    for (final existing in contributingFeatures) {
      if (existing.featureId == normalized.featureId) {
        if (!updatedExisting) {
          mergedContributions.add(normalized);
          seenIds.add(normalized.featureId);
          updatedExisting = true;
        }
      } else if (seenIds.add(existing.featureId)) {
        mergedContributions.add(existing);
      }
    }
    if (!updatedExisting) {
      mergedContributions.add(normalized);
    }
    return SpecOriginBaseline(
      projectId: projectId,
      projectName: projectName ?? this.projectName,
      featureId: normalized.featureId,
      featureCode: normalized.featureCode,
      specObjectId: specObjectId,
      promotedAt: normalized.promotedAt,
      baseSpecObject: nextBaseSpecObject,
      ruleFingerprints: <String, String>{
        ...ruleFingerprints,
        ...nextRuleFingerprints,
      },
      contributingFeatures: mergedContributions,
    );
  }

  static List<SpecFeatureContribution> _normalizeContributingFeatures({
    required List<SpecFeatureContribution> contributingFeatures,
    required String featureId,
    required String featureCode,
    required DateTime promotedAt,
  }) {
    if (contributingFeatures.isNotEmpty) {
      return contributingFeatures;
    }
    final trimmedFeatureId = featureId.trim();
    if (trimmedFeatureId.isEmpty) {
      return const <SpecFeatureContribution>[];
    }
    return <SpecFeatureContribution>[
      SpecFeatureContribution(
        featureId: trimmedFeatureId,
        featureCode: featureCode.trim(),
        featureName: '',
        promotedAt: promotedAt,
      ),
    ];
  }

  /// Calcule une empreinte canonique déterministe d'une [BusinessRuleSpec] afin
  /// de détecter toute modification ultérieure d'une règle `RG-xxx` côté Spec.
  static String computeRuleFingerprint(BusinessRuleSpec rule) {
    final objects = <String>[
      for (final id in rule.targetObjectIds)
        if (id.trim().isNotEmpty) id.trim(),
    ]..sort();
    final attributes = <String>[
      for (final attr in rule.targetAttributes)
        if (attr.trim().isNotEmpty) attr.trim(),
    ]..sort();
    final examples = <String>[
      for (final ex in rule.examples)
        if (ex.trim().isNotEmpty) ex.trim(),
    ];
    return <String>[
      rule.code.trim(),
      rule.category.name,
      rule.priority.name,
      rule.active ? 'active' : 'inactive',
      rule.title.trim(),
      rule.description.trim(),
      'when:${rule.trigger.trim()}',
      'if:${rule.condition.trim()}',
      'then:${rule.effect.trim()}',
      'err:${rule.errorMessage.trim()}',
      'objs:${objects.join(',')}',
      'attrs:${attributes.join(',')}',
      if (examples.isNotEmpty) 'ex:${examples.join(',')}',
    ].join(' | ');
  }

  /// Vérifie les invariants de l'empreinte d'origine Spec.
  void validate() {
    if (projectId.trim().isEmpty) {
      throw const FormatException(
        'SpecOriginBaseline.projectId ne peut pas être vide.',
      );
    }
    if (specObjectId.trim().isEmpty) {
      throw const FormatException(
        'SpecOriginBaseline.specObjectId ne peut pas être vide.',
      );
    }
    baseSpecObject.validate();
    for (final contribution in contributingFeatures) {
      contribution.validate();
    }
  }

  /// Retourne une copie modifiée de cette empreinte d'origine Spec.
  SpecOriginBaseline copyWith({
    String? projectId,
    String? projectName,
    String? featureId,
    String? featureCode,
    String? specObjectId,
    DateTime? promotedAt,
    BusinessObjectSpec? baseSpecObject,
    Map<String, String>? ruleFingerprints,
    List<SpecFeatureContribution>? contributingFeatures,
  }) {
    final hasSingleAutoDerivedContribution =
        this.contributingFeatures.length == 1 &&
        this.contributingFeatures.single.featureId == this.featureId.trim() &&
        this.contributingFeatures.single.featureName.isEmpty;
    final nextContributions =
        contributingFeatures ??
        ((hasSingleAutoDerivedContribution &&
                (featureId != null ||
                    featureCode != null ||
                    promotedAt != null))
            ? const <SpecFeatureContribution>[]
            : this.contributingFeatures);
    return SpecOriginBaseline(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      featureId: featureId ?? this.featureId,
      featureCode: featureCode ?? this.featureCode,
      specObjectId: specObjectId ?? this.specObjectId,
      promotedAt: promotedAt ?? this.promotedAt,
      baseSpecObject: baseSpecObject ?? this.baseSpecObject,
      ruleFingerprints: ruleFingerprints ?? this.ruleFingerprints,
      contributingFeatures: nextContributions,
    );
  }

  /// Sérialise l'empreinte d'origine Spec en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': projectId,
    if (projectName.isNotEmpty) 'projectName': projectName,
    if (featureId.isNotEmpty) 'featureId': featureId,
    if (featureCode.isNotEmpty) 'featureCode': featureCode,
    'specObjectId': specObjectId,
    'promotedAt': promotedAt.toUtc().toIso8601String(),
    'baseSpecObject': baseSpecObject.toJson(),
    if (ruleFingerprints.isNotEmpty) 'ruleFingerprints': ruleFingerprints,
    if (contributingFeatures.isNotEmpty)
      'contributingFeatures': [
        for (final c in contributingFeatures) c.toJson(),
      ],
  };

  /// Désérialise et valide une empreinte d'origine Spec depuis JSON.
  factory SpecOriginBaseline.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'SpecOriginBaseline doit être un objet JSON.',
      );
    }
    final rawPromotedAt = raw['promotedAt'];
    final parsedPromotedAt = rawPromotedAt is String
        ? DateTime.tryParse(rawPromotedAt)
        : null;
    if (parsedPromotedAt == null) {
      throw const FormatException(
        'SpecOriginBaseline.promotedAt invalide.',
      );
    }
    if (raw['baseSpecObject'] is! Map) {
      throw const FormatException(
        'SpecOriginBaseline.baseSpecObject invalide.',
      );
    }
    final rawFingerprints = raw['ruleFingerprints'];
    if (rawFingerprints != null && rawFingerprints is! Map) {
      throw const FormatException(
        'SpecOriginBaseline.ruleFingerprints invalide.',
      );
    }
    final parsedFingerprints = <String, String>{};
    if (rawFingerprints is Map) {
      for (final entry in rawFingerprints.entries) {
        final key = '${entry.key}'.trim();
        if (key.isNotEmpty && entry.value != null) {
          parsedFingerprints[key] = '${entry.value}';
        }
      }
    }
    final rawContributions = raw['contributingFeatures'];
    if (rawContributions != null && rawContributions is! List) {
      throw const FormatException(
        'SpecOriginBaseline.contributingFeatures invalide.',
      );
    }
    final parsedContributions = <SpecFeatureContribution>[
      if (rawContributions is List)
        for (final item in rawContributions)
          SpecFeatureContribution.fromJson(item),
    ];
    final baseline = SpecOriginBaseline(
      projectId: (raw['projectId'] as String?)?.trim() ?? '',
      projectName: (raw['projectName'] as String?)?.trim() ?? '',
      featureId: (raw['featureId'] as String?)?.trim() ?? '',
      featureCode: (raw['featureCode'] as String?)?.trim() ?? '',
      specObjectId: (raw['specObjectId'] as String?)?.trim() ?? '',
      promotedAt: parsedPromotedAt,
      baseSpecObject: BusinessObjectSpec.fromJson(raw['baseSpecObject']),
      ruleFingerprints: parsedFingerprints,
      contributingFeatures: parsedContributions,
    );
    baseline.validate();
    return baseline;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecOriginBaseline &&
          other.projectId == projectId &&
          other.projectName == projectName &&
          other.featureId == featureId &&
          other.featureCode == featureCode &&
          other.specObjectId == specObjectId &&
          other.promotedAt == promotedAt &&
          other.baseSpecObject == baseSpecObject &&
          mapEquals(other.ruleFingerprints, ruleFingerprints) &&
          listEquals(other.contributingFeatures, contributingFeatures);

  @override
  int get hashCode => Object.hash(
    projectId,
    projectName,
    featureId,
    featureCode,
    specObjectId,
    promotedAt,
    baseSpecObject,
    Object.hashAllUnordered([
      for (final e in ruleFingerprints.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAll(contributingFeatures),
  );
}
