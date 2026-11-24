/// Modèle immuable d'un risque financier projet et de sa provision probabilisée EMV ([CostRiskItemSpec]).
library;

import 'package:flutter/foundation.dart';

/// Risque identifié sur le chiffrage et valorisé en espérance mathématique (EMV : probabilité × impact).
@immutable
class CostRiskItemSpec {
  /// Construit un risque budgétaire immuable.
  CostRiskItemSpec({
    required this.id,
    this.code = 'RSK-001',
    required this.title,
    this.description = '',
    this.probabilityPct = 30.0,
    this.impactDays = 0.0,
    this.fixedCostImpact = 0.0,
    this.profileId = 'prof_back',
    this.mitigation = '',
    this.linkedHotspotId = '',
    List<String> linkedRequirementIds = const <String>[],
  }) : linkedRequirementIds = List<String>.unmodifiable(linkedRequirementIds);

  /// Identifiant technique unique du risque.
  final String id;

  /// Code lisible du risque (ex. `RSK-001`).
  final String code;

  /// Intitulé concis du risque technique, fonctionnel ou fournisseur.
  final String title;

  /// Description détaillée de la cause et des conséquences sur le projet.
  final String description;

  /// Probabilité d'occurrence estimée (`0..100` %, `30.0` par défaut).
  final double probabilityPct;

  /// Surcoût en jours/homme en cas de survenance (`>= 0`).
  final double impactDays;

  /// Surcoût financier forfaitaire direct (pénalité, licence, matériel…) en cas de survenance (`>= 0`).
  final double fixedCostImpact;

  /// Identifiant du profil tarifaire utilisé pour valoriser [impactDays].
  final String profileId;

  /// Plan de prévention, contournement ou réduction du risque.
  final String mitigation;

  /// Identifiant optionnel d'un Hotspot Event Storming lié.
  final String linkedHotspotId;

  /// Identifiants ou codes des exigences (`EF-xxx` / `ENF-xxx`) exposées au risque.
  final List<String> linkedRequirementIds;

  /// Espérance mathématique de charge pondérée (`impactDays * probabilityPct / 100`).
  double get expectedDays => impactDays * (probabilityPct / 100.0);

  /// Espérance mathématique du surcoût forfaitaire (`fixedCostImpact * probabilityPct / 100`).
  double get expectedFixedCost => fixedCostImpact * (probabilityPct / 100.0);

  /// Vérifie les invariants du risque budgétaire.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('CostRiskItemSpec.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'CostRiskItemSpec.title ne peut pas être vide.',
      );
    }
    if (!probabilityPct.isFinite ||
        probabilityPct < 0.0 ||
        probabilityPct > 100.0) {
      throw const FormatException(
        'CostRiskItemSpec.probabilityPct doit être compris dans [0, 100].',
      );
    }
    if (!impactDays.isFinite || impactDays < 0.0) {
      throw const FormatException(
        'CostRiskItemSpec.impactDays doit être supérieur ou égal à 0.',
      );
    }
    if (!fixedCostImpact.isFinite || fixedCostImpact < 0.0) {
      throw const FormatException(
        'CostRiskItemSpec.fixedCostImpact doit être supérieur ou égal à 0.',
      );
    }
  }

  /// Retourne une copie modifiée.
  CostRiskItemSpec copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    double? probabilityPct,
    double? impactDays,
    double? fixedCostImpact,
    String? profileId,
    String? mitigation,
    String? linkedHotspotId,
    List<String>? linkedRequirementIds,
  }) => CostRiskItemSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    description: description ?? this.description,
    probabilityPct: probabilityPct ?? this.probabilityPct,
    impactDays: impactDays ?? this.impactDays,
    fixedCostImpact: fixedCostImpact ?? this.fixedCostImpact,
    profileId: profileId ?? this.profileId,
    mitigation: mitigation ?? this.mitigation,
    linkedHotspotId: linkedHotspotId ?? this.linkedHotspotId,
    linkedRequirementIds: linkedRequirementIds ?? this.linkedRequirementIds,
  );

  /// Sérialise le risque budgétaire en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    'description': description,
    'probabilityPct': probabilityPct,
    'impactDays': impactDays,
    'fixedCostImpact': fixedCostImpact,
    'profileId': profileId,
    'mitigation': mitigation,
    'linkedHotspotId': linkedHotspotId,
    'linkedRequirementIds': linkedRequirementIds,
  };

  /// Désérialise un risque budgétaire depuis JSON avec bornage tolérant.
  factory CostRiskItemSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('CostRiskItemSpec doit être un objet JSON.');
    }
    final rawTitle =
        (raw['title'] as String?)?.trim() ??
        (raw['name'] as String?)?.trim() ??
        (raw['label'] as String?)?.trim() ??
        '';
    final title = rawTitle.isEmpty ? 'Risque sans titre' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawProfileId = (raw['profileId'] as String?)?.trim() ?? '';
    final item = CostRiskItemSpec(
      id: rawId.isEmpty ? 'rsk_${title.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'RSK-001' : rawCode,
      title: title,
      description: (raw['description'] as String?)?.trim() ?? '',
      probabilityPct: _clampedDouble(
        raw['probabilityPct'] ?? raw['probability'],
        30.0,
        0.0,
        100.0,
      ),
      impactDays: _nonNegativeDouble(raw['impactDays'] ?? raw['days'], 0.0),
      fixedCostImpact: _nonNegativeDouble(
        raw['fixedCostImpact'] ?? raw['fixedCost'] ?? raw['costImpact'],
        0.0,
      ),
      profileId: rawProfileId.isEmpty ? 'prof_back' : rawProfileId,
      mitigation: (raw['mitigation'] as String?)?.trim() ?? '',
      linkedHotspotId: (raw['linkedHotspotId'] as String?)?.trim() ?? '',
      linkedRequirementIds: _stringList(raw['linkedRequirementIds']),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostRiskItemSpec &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.description == description &&
          other.probabilityPct == probabilityPct &&
          other.impactDays == impactDays &&
          other.fixedCostImpact == fixedCostImpact &&
          other.profileId == profileId &&
          other.mitigation == mitigation &&
          other.linkedHotspotId == linkedHotspotId &&
          listEquals(other.linkedRequirementIds, linkedRequirementIds);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    description,
    probabilityPct,
    impactDays,
    fixedCostImpact,
    profileId,
    mitigation,
    linkedHotspotId,
    Object.hashAll(linkedRequirementIds),
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

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
