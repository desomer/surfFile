/// Modèles immuables des jeux d'essais et données de référence QA ([QaFixtureSpec], [QaFixtureKind]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Catégorie fonctionnelle d'un jeu d'essai QA.
enum QaFixtureKind {
  /// Cas nominal représentatif du flux standard valide.
  nominal('Nominal (Happy Path)'),

  /// Valeur exacte aux bornes des contraintes JSON Schema ou règles numériques.
  boundary('Valeur aux bornes (Boundary)'),

  /// Jeu de données volontairement non conforme pour tester le rejet métier/schéma.
  invalid('Invalide / Cas d’erreur'),

  /// Contexte d'acteur, rôle ou profil d'habilitation spécifique.
  permission('Profil / Habilitation'),

  /// Instance positionnée dans un état précis du cycle de vie métier.
  lifecycle('État de cycle de vie');

  /// Construit une catégorie de fixture QA.
  const QaFixtureKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout une catégorie de fixture depuis JSON ou un alias courant, avec repli sur [nominal].
  static QaFixtureKind fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final kind in QaFixtureKind.values) {
        if (kind.name.toLowerCase() == norm ||
            kind.label.toLowerCase() == norm) {
          return kind;
        }
      }
      switch (norm) {
        case 'happy_path':
        case 'happy-path':
        case 'happypath':
        case 'valid':
        case 'valide':
        case 'standard':
          return QaFixtureKind.nominal;
        case 'bound':
        case 'bounds':
        case 'edge':
        case 'edge_case':
        case 'edge-case':
        case 'limite':
        case 'limites':
        case 'borne':
        case 'bornes':
          return QaFixtureKind.boundary;
        case 'error':
        case 'erreur':
        case 'negative':
        case 'invalide':
        case 'rejected':
        case 'rejet':
          return QaFixtureKind.invalid;
        case 'auth':
        case 'rbac':
        case 'role':
        case 'habilitation':
        case 'droits':
        case 'security':
        case 'persona':
          return QaFixtureKind.permission;
        case 'state':
        case 'status':
        case 'statut':
        case 'transition':
        case 'workflow':
        case 'cycle_de_vie':
        case 'cycle-de-vie':
          return QaFixtureKind.lifecycle;
      }
    }
    return QaFixtureKind.nominal;
  }
}

/// Jeu d'essai concret réutilisable par les scénarios Gherkin et les cas unitaires TDD (étape QA 1).
@immutable
class QaFixtureSpec {
  /// Construit un jeu d'essai QA immuable dont [payload] est normalisé et figé en profondeur.
  QaFixtureSpec({
    required this.id,
    this.code = 'FIX',
    required this.name,
    this.kind = QaFixtureKind.nominal,
    this.businessObjectId = '',
    this.personaId = '',
    List<String> businessRuleIds = const <String>[],
    this.description = '',
    Map<String, Object?> payload = const <String, Object?>{},
    this.expectedValid = true,
    this.expectedErrorHint = '',
  }) : businessRuleIds = List<String>.unmodifiable(businessRuleIds),
       payload = _freezeJsonMap(payload);

  /// Identifiant technique unique de la fixture (ex. `fix_cmd_nominale`).
  final String id;

  /// Code métier lisible de la fixture (ex. `FIX-001`).
  final String code;

  /// Intitulé explicite du jeu d'essai.
  final String name;

  /// Catégorie de test couverte par cette fixture.
  final QaFixtureKind kind;

  /// Identifiant ou nom technique du `BusinessObjectSpec` principal représenté.
  final String businessObjectId;

  /// Identifiant optionnel du persona associé au contexte d'exécution.
  final String personaId;

  /// Identifiants ou codes des règles de gestion (`RG-xxx`) exercées par ce jeu d'essai.
  final List<String> businessRuleIds;

  /// Intention de test et particularités métier de la fixture.
  final String description;

  /// Enregistrement ou contexte JSON concret, normalisé et non modifiable en profondeur.
  final Map<String, Object?> payload;

  /// Indique si ce jeu de données est censé passer la validation (`true`) ou être rejeté (`false`).
  final bool expectedValid;

  /// Code ou message d'erreur attendu lorsque [expectedValid] vaut `false`.
  final String expectedErrorHint;

  /// Vérifie les invariants structurels de la fixture.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('QaFixtureSpec.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('QaFixtureSpec.name ne peut pas être vide.');
    }
  }

  /// Retourne une copie modifiée.
  QaFixtureSpec copyWith({
    String? id,
    String? code,
    String? name,
    QaFixtureKind? kind,
    String? businessObjectId,
    String? personaId,
    List<String>? businessRuleIds,
    String? description,
    Map<String, Object?>? payload,
    bool? expectedValid,
    String? expectedErrorHint,
  }) => QaFixtureSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    businessObjectId: businessObjectId ?? this.businessObjectId,
    personaId: personaId ?? this.personaId,
    businessRuleIds: businessRuleIds ?? this.businessRuleIds,
    description: description ?? this.description,
    payload: payload ?? this.payload,
    expectedValid: expectedValid ?? this.expectedValid,
    expectedErrorHint: expectedErrorHint ?? this.expectedErrorHint,
  );

  /// Sérialise la fixture en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'kind': kind.name,
    'businessObjectId': businessObjectId,
    'personaId': personaId,
    'businessRuleIds': businessRuleIds,
    'description': description,
    'payload': payload,
    'expectedValid': expectedValid,
    'expectedErrorHint': expectedErrorHint,
  };

  /// Désérialise une fixture QA depuis JSON avec valeurs de repli tolérantes.
  factory QaFixtureSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('QaFixtureSpec doit être un objet JSON.');
    }
    final rawName =
        (raw['name'] as String?)?.trim() ??
        (raw['title'] as String?)?.trim() ??
        (raw['label'] as String?)?.trim() ??
        '';
    final name = rawName.isEmpty ? 'Fixture sans nom' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawObjectId =
        (raw['businessObjectId'] as String?)?.trim() ??
        (raw['targetObjectId'] as String?)?.trim() ??
        '';
    final fixture = QaFixtureSpec(
      id: rawId.isEmpty ? 'fix_${name.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'FIX' : rawCode,
      name: name,
      kind: QaFixtureKind.fromJson(raw['kind']),
      businessObjectId: rawObjectId,
      personaId: (raw['personaId'] as String?)?.trim() ?? '',
      businessRuleIds: _stringList(raw['businessRuleIds']),
      description: (raw['description'] as String?)?.trim() ?? '',
      payload: _parsePayloadMap(
        raw['payload'] ?? raw['data'] ?? raw['record'],
      ),
      expectedValid: raw['expectedValid'] is bool
          ? raw['expectedValid'] as bool
          : true,
      expectedErrorHint: (raw['expectedErrorHint'] as String?)?.trim() ?? '',
    );
    fixture.validate();
    return fixture;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QaFixtureSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.kind == kind &&
          other.businessObjectId == businessObjectId &&
          other.personaId == personaId &&
          listEquals(other.businessRuleIds, businessRuleIds) &&
          other.description == description &&
          _jsonValueEquals(other.payload, payload) &&
          other.expectedValid == expectedValid &&
          other.expectedErrorHint == expectedErrorHint;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    kind,
    businessObjectId,
    personaId,
    Object.hashAll(businessRuleIds),
    description,
    _jsonValueHash(payload),
    expectedValid,
    expectedErrorHint,
  );
}

Map<String, Object?> _parsePayloadMap(Object? raw) {
  if (raw is Map) {
    return _freezeJsonMap(raw);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _freezeJsonMap(decoded);
      }
    } on FormatException {
      // Chaîne brute non JSON : repli sur une map vide.
    }
  }
  return const <String, Object?>{};
}

Map<String, Object?> _freezeJsonMap(Map<Object?, Object?> raw) {
  if (raw.isEmpty) return const <String, Object?>{};
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in raw.entries)
      entry.key.toString(): _normalizeJsonValue(entry.value),
  });
}

Object? _normalizeJsonValue(Object? value) {
  if (value == null || value is bool || value is String) return value;
  if (value is int) return value;
  if (value is double) return value.isFinite ? value : null;
  if (value is num) return value.isFinite ? value : null;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Enum) return value.name;
  if (value is Map) return _freezeJsonMap(value);
  if (value is Iterable) {
    return List<Object?>.unmodifiable([
      for (final item in value) _normalizeJsonValue(item),
    ]);
  }
  return value.toString();
}

bool _jsonValueEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final key = entry.key;
      if (!b.containsKey(key)) return false;
      if (!_jsonValueEquals(entry.value, b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonValueEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _jsonValueHash(Object? value) {
  if (value == null) return 0;
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, _jsonValueHash(e.value))),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_jsonValueHash));
  }
  return value.hashCode;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
