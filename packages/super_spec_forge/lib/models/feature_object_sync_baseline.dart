/// Modèles immuables d'empreinte de synchronisation d'un objet métier au sein
/// d'une Feature ([FeatureObjectSyncBaseline], [ObjectSyncSourceKind]), servant
/// de base commune (`baseSpec`) aux fusions 3-voies inter-features et depuis Design.
library;

import 'package:flutter/foundation.dart';

import 'business_object_spec.dart';

/// Nature de la source amont depuis laquelle un objet métier a été synchronisé
/// dans une [SpecFeatureSpec].
enum ObjectSyncSourceKind {
  /// Synchronisation depuis une autre Feature du portefeuille projet.
  feature('Autre Feature'),

  /// Synchronisation depuis un domaine fonctionnel de l'espace Design.
  designDomain('Domaine Design');

  /// Construit une catégorie de source de synchronisation.
  const ObjectSyncSourceKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un [ObjectSyncSourceKind] depuis une valeur JSON, ou `null` si non reconnue.
  static ObjectSyncSourceKind? tryFromJson(Object? raw) {
    if (raw is ObjectSyncSourceKind) return raw;
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in ObjectSyncSourceKind.values) {
        if (value.name.toLowerCase() == norm ||
            value.label.toLowerCase() == norm) {
          return value;
        }
      }
      if (norm == 'design_domain' ||
          norm == 'design-domain' ||
          norm == 'design') {
        return ObjectSyncSourceKind.designDomain;
      }
    }
    return null;
  }

  /// Désérialise un [ObjectSyncSourceKind] depuis une valeur JSON (repli sur [feature]).
  static ObjectSyncSourceKind fromJson(Object? raw) =>
      tryFromJson(raw) ?? ObjectSyncSourceKind.feature;
}

/// Photographie immuable de l'état de référence d'un [BusinessObjectSpec] lors
/// de son import ou de sa re-synchronisation dans une Feature cible.
///
/// Utilisée comme ancêtre commun (`baseSpec`) par le moteur de fusion 3-voies
/// afin d'isoler les ajouts locaux de la Feature cible des évolutions de la
/// source amont (autre Feature ou domaine Design).
@immutable
class FeatureObjectSyncBaseline {
  /// Crée une empreinte immuable de synchronisation d'objet métier.
  FeatureObjectSyncBaseline({
    required this.objectId,
    required this.sourceKind,
    this.sourceFeatureId = '',
    this.sourceFeatureCode = '',
    this.sourceFeatureName = '',
    this.sourceDomainId = '',
    this.sourceDomainName = '',
    this.sourceEntryId = '',
    required DateTime syncedAt,
    required this.baseObject,
  }) : syncedAt = syncedAt.toUtc();

  /// Identifiant du [BusinessObjectSpec] correspondant dans la Feature cible.
  final String objectId;

  /// Type de source amont ([ObjectSyncSourceKind.feature] ou [ObjectSyncSourceKind.designDomain]).
  final ObjectSyncSourceKind sourceKind;

  /// Identifiant de la Feature source lorsque [sourceKind] vaut [ObjectSyncSourceKind.feature].
  final String sourceFeatureId;

  /// Code court de la Feature source (ex. `FEAT-01`).
  final String sourceFeatureCode;

  /// Nom fonctionnel de la Feature source.
  final String sourceFeatureName;

  /// Identifiant du domaine fonctionnel source lorsque [sourceKind] vaut [ObjectSyncSourceKind.designDomain].
  final String sourceDomainId;

  /// Nom affiché du domaine fonctionnel source.
  final String sourceDomainName;

  /// Identifiant de l'objet ou de l'entrée source dans la Feature ou le contrat Design amont.
  final String sourceEntryId;

  /// Horodatage UTC de la dernière synchronisation.
  final DateTime syncedAt;

  /// Photographie complète du [BusinessObjectSpec] de référence au moment de la synchronisation.
  final BusinessObjectSpec baseObject;

  /// Libellé synthétique en français identifiant la provenance amont pour l'interface.
  String get sourceDisplayLabel {
    switch (sourceKind) {
      case ObjectSyncSourceKind.feature:
        final code = sourceFeatureCode.trim();
        final name = sourceFeatureName.trim();
        if (code.isNotEmpty && name.isNotEmpty) {
          return '$code · $name';
        }
        if (code.isNotEmpty) return code;
        if (name.isNotEmpty) return name;
        return 'Feature';
      case ObjectSyncSourceKind.designDomain:
        final domain = sourceDomainName.trim();
        return domain.isNotEmpty ? 'Design · $domain' : 'Domaine Design';
    }
  }

  /// Vérifie les invariants structurels de l'empreinte de synchronisation.
  void validate() {
    if (objectId.trim().isEmpty) {
      throw const FormatException(
        'FeatureObjectSyncBaseline.objectId ne peut pas être vide.',
      );
    }
    switch (sourceKind) {
      case ObjectSyncSourceKind.feature:
        if (sourceFeatureId.trim().isEmpty) {
          throw const FormatException(
            'FeatureObjectSyncBaseline.sourceFeatureId est requis lorsque sourceKind vaut feature.',
          );
        }
      case ObjectSyncSourceKind.designDomain:
        if (sourceDomainId.trim().isEmpty) {
          throw const FormatException(
            'FeatureObjectSyncBaseline.sourceDomainId est requis lorsque sourceKind vaut designDomain.',
          );
        }
    }
    baseObject.validate();
  }

  /// Retourne une copie modifiée de cette empreinte de synchronisation.
  FeatureObjectSyncBaseline copyWith({
    String? objectId,
    ObjectSyncSourceKind? sourceKind,
    String? sourceFeatureId,
    String? sourceFeatureCode,
    String? sourceFeatureName,
    String? sourceDomainId,
    String? sourceDomainName,
    String? sourceEntryId,
    DateTime? syncedAt,
    BusinessObjectSpec? baseObject,
  }) => FeatureObjectSyncBaseline(
    objectId: objectId ?? this.objectId,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceFeatureId: sourceFeatureId ?? this.sourceFeatureId,
    sourceFeatureCode: sourceFeatureCode ?? this.sourceFeatureCode,
    sourceFeatureName: sourceFeatureName ?? this.sourceFeatureName,
    sourceDomainId: sourceDomainId ?? this.sourceDomainId,
    sourceDomainName: sourceDomainName ?? this.sourceDomainName,
    sourceEntryId: sourceEntryId ?? this.sourceEntryId,
    syncedAt: syncedAt ?? this.syncedAt,
    baseObject: baseObject ?? this.baseObject,
  );

  /// Sérialise l'empreinte de synchronisation en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'objectId': objectId,
    'sourceKind': sourceKind.name,
    if (sourceFeatureId.isNotEmpty) 'sourceFeatureId': sourceFeatureId,
    if (sourceFeatureCode.isNotEmpty) 'sourceFeatureCode': sourceFeatureCode,
    if (sourceFeatureName.isNotEmpty) 'sourceFeatureName': sourceFeatureName,
    if (sourceDomainId.isNotEmpty) 'sourceDomainId': sourceDomainId,
    if (sourceDomainName.isNotEmpty) 'sourceDomainName': sourceDomainName,
    if (sourceEntryId.isNotEmpty) 'sourceEntryId': sourceEntryId,
    'syncedAt': syncedAt.toUtc().toIso8601String(),
    'baseObject': baseObject.toJson(),
  };

  /// Désérialise et valide une empreinte de synchronisation depuis JSON.
  factory FeatureObjectSyncBaseline.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'FeatureObjectSyncBaseline doit être un objet JSON.',
      );
    }
    final rawSourceKind = raw['sourceKind'];
    final ObjectSyncSourceKind parsedKind;
    if (rawSourceKind != null) {
      final resolved = ObjectSyncSourceKind.tryFromJson(rawSourceKind);
      if (resolved == null) {
        throw const FormatException(
          'FeatureObjectSyncBaseline.sourceKind invalide.',
        );
      }
      parsedKind = resolved;
    } else {
      final hasDomain =
          (raw['sourceDomainId'] as String?)?.trim().isNotEmpty ?? false;
      parsedKind = hasDomain
          ? ObjectSyncSourceKind.designDomain
          : ObjectSyncSourceKind.feature;
    }

    final rawSyncedAt = raw['syncedAt'];
    final parsedSyncedAt = rawSyncedAt is String
        ? DateTime.tryParse(rawSyncedAt)
        : null;
    if (parsedSyncedAt == null) {
      throw const FormatException(
        'FeatureObjectSyncBaseline.syncedAt invalide.',
      );
    }
    if (raw['baseObject'] is! Map) {
      throw const FormatException(
        'FeatureObjectSyncBaseline.baseObject invalide.',
      );
    }

    final baseline = FeatureObjectSyncBaseline(
      objectId: (raw['objectId'] as String?)?.trim() ?? '',
      sourceKind: parsedKind,
      sourceFeatureId: (raw['sourceFeatureId'] as String?)?.trim() ?? '',
      sourceFeatureCode: (raw['sourceFeatureCode'] as String?)?.trim() ?? '',
      sourceFeatureName: (raw['sourceFeatureName'] as String?)?.trim() ?? '',
      sourceDomainId: (raw['sourceDomainId'] as String?)?.trim() ?? '',
      sourceDomainName: (raw['sourceDomainName'] as String?)?.trim() ?? '',
      sourceEntryId: (raw['sourceEntryId'] as String?)?.trim() ?? '',
      syncedAt: parsedSyncedAt,
      baseObject: BusinessObjectSpec.fromJson(raw['baseObject']),
    );
    baseline.validate();
    return baseline;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureObjectSyncBaseline &&
          other.objectId == objectId &&
          other.sourceKind == sourceKind &&
          other.sourceFeatureId == sourceFeatureId &&
          other.sourceFeatureCode == sourceFeatureCode &&
          other.sourceFeatureName == sourceFeatureName &&
          other.sourceDomainId == sourceDomainId &&
          other.sourceDomainName == sourceDomainName &&
          other.sourceEntryId == sourceEntryId &&
          other.syncedAt == syncedAt &&
          other.baseObject == baseObject;

  @override
  int get hashCode => Object.hash(
    objectId,
    sourceKind,
    sourceFeatureId,
    sourceFeatureCode,
    sourceFeatureName,
    sourceDomainId,
    sourceDomainName,
    sourceEntryId,
    syncedAt,
    baseObject,
  );
}
