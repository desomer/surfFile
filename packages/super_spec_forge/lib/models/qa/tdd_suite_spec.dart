/// Modèles immuables des suites de tests unitaires et contrats TDD ([TddTestSuiteSpec], [TddTestCaseSpec], [TddTargetLayer], [TddExpectedOutcomeKind]).
library;

import 'package:flutter/foundation.dart';

/// Couche architecturale ou nature du contrat vérifié par une suite TDD.
enum TddTargetLayer {
  /// Formules de calcul, agrégations et arrondis métiers.
  calculationFormula('Calcul & Formule'),

  /// Validation des invariants et règles de gestion du domaine.
  domainValidation('Validation métier'),

  /// Automate d'états, gardes et transitions de cycle de vie.
  stateMachine('Cycle de vie & Transitions'),

  /// Politiques d'accès, rôles et habilitations par persona.
  permissionPolicy('Habilitations & Droits'),

  /// Conformité aux contraintes de contrat JSON Schema.
  schemaContract('Contrat JSON Schema'),

  /// Réactivité d'interface, états d'écran et interactions UX.
  uiBehavior('Comportement IHM / UX');

  /// Construit une couche cible TDD.
  const TddTargetLayer(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout une couche TDD depuis JSON ou un alias courant, avec repli sur [domainValidation].
  static TddTargetLayer fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final layer in TddTargetLayer.values) {
        if (layer.name.toLowerCase() == norm ||
            layer.label.toLowerCase() == norm) {
          return layer;
        }
      }
      switch (norm) {
        case 'calculation':
        case 'formula':
        case 'calculation_formula':
        case 'calculation-formula':
        case 'calcul':
        case 'formule':
          return TddTargetLayer.calculationFormula;
        case 'validation':
        case 'domain':
        case 'domain_validation':
        case 'domain-validation':
        case 'metier':
        case 'business_rule':
        case 'business-rule':
          return TddTargetLayer.domainValidation;
        case 'state_machine':
        case 'state-machine':
        case 'lifecycle':
        case 'transition':
        case 'transitions':
        case 'workflow':
        case 'statut':
          return TddTargetLayer.stateMachine;
        case 'permission':
        case 'permissions':
        case 'permission_policy':
        case 'permission-policy':
        case 'rbac':
        case 'auth':
        case 'security':
        case 'droits':
        case 'habilitation':
          return TddTargetLayer.permissionPolicy;
        case 'schema':
        case 'json_schema':
        case 'json-schema':
        case 'schema_contract':
        case 'schema-contract':
        case 'contract':
        case 'contrat':
          return TddTargetLayer.schemaContract;
        case 'ui':
        case 'ux':
        case 'ui_behavior':
        case 'ui-behavior':
        case 'widget':
        case 'ihm':
        case 'screen':
          return TddTargetLayer.uiBehavior;
      }
    }
    return TddTargetLayer.domainValidation;
  }
}

/// Nature de l'assertion attendue à l'issue de la phase `Act` d'un cas TDD.
enum TddExpectedOutcomeKind {
  /// Produit une valeur calculée ou retournée déterministe.
  returnsValue('Retourne une valeur'),

  /// Modifie l'état interne ou produit une nouvelle version de l'entité.
  mutatesState('Change l’état / entité'),

  /// Lève une erreur ou rejette l'opération avec un motif explicite.
  rejectsWithError('Rejette avec erreur'),

  /// Autorise l'exécution de l'action pour le contexte/acteur donné.
  allowsAction('Autorise l’action'),

  /// Interdit l'exécution de l'action pour défaut de droit ou de garde.
  deniesAction('Refuse l’action');

  /// Construit un type de résultat attendu TDD.
  const TddExpectedOutcomeKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un type de résultat attendu depuis JSON ou un alias courant, avec repli sur [returnsValue].
  static TddExpectedOutcomeKind fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final kind in TddExpectedOutcomeKind.values) {
        if (kind.name.toLowerCase() == norm ||
            kind.label.toLowerCase() == norm) {
          return kind;
        }
      }
      switch (norm) {
        case 'returns':
        case 'return':
        case 'returns_value':
        case 'returns-value':
        case 'value':
        case 'valeur':
          return TddExpectedOutcomeKind.returnsValue;
        case 'mutates':
        case 'mutate':
        case 'mutates_state':
        case 'mutates-state':
        case 'state_change':
        case 'updates':
        case 'mutation':
          return TddExpectedOutcomeKind.mutatesState;
        case 'rejects':
        case 'reject':
        case 'rejects_with_error':
        case 'rejects-with-error':
        case 'throws':
        case 'error':
        case 'exception':
        case 'invalid':
          return TddExpectedOutcomeKind.rejectsWithError;
        case 'allows':
        case 'allow':
        case 'allows_action':
        case 'allows-action':
        case 'permitted':
        case 'authorized':
          return TddExpectedOutcomeKind.allowsAction;
        case 'denies':
        case 'deny':
        case 'denies_action':
        case 'denies-action':
        case 'forbidden':
        case 'unauthorized':
          return TddExpectedOutcomeKind.deniesAction;
      }
    }
    return TddExpectedOutcomeKind.returnsValue;
  }
}

/// Cas de test atomique structuré en `Arrange / Act / Assert` dans l'ordre Red → Green → Refactor.
@immutable
class TddTestCaseSpec {
  /// Construit un cas de test TDD immuable.
  TddTestCaseSpec({
    required this.id,
    this.code = 'TC',
    this.order = 1,
    required this.title,
    this.fixtureId = '',
    this.arrange = '',
    this.act = '',
    this.outcomeKind = TddExpectedOutcomeKind.returnsValue,
    this.assertExpected = '',
    this.expectedErrorMessage = '',
    List<String> businessRuleIds = const <String>[],
    List<String> requirementIds = const <String>[],
    List<String> screenIds = const <String>[],
  }) : businessRuleIds = List<String>.unmodifiable(businessRuleIds),
       requirementIds = List<String>.unmodifiable(requirementIds),
       screenIds = List<String>.unmodifiable(screenIds);

  /// Identifiant unique du cas de test dans sa suite (ex. `tc_cmd_encours_depasse`).
  final String id;

  /// Code lisible du cas de test (ex. `TC-001`).
  final String code;

  /// Ordre d'implémentation progressive Red → Green → Refactor (`>= 1`).
  final int order;

  /// Intitulé précis du comportement unitaire vérifié.
  final String title;

  /// Identifiant ou code optionnel de la fixture (`FIX-xxx`) utilisée en entrée.
  final String fixtureId;

  /// Préparation du contexte et des données (`Arrange`).
  final String arrange;

  /// Invocation de la fonction, commande ou action testée (`Act`).
  final String act;

  /// Catégorie d'assertion attendue.
  final TddExpectedOutcomeKind outcomeKind;

  /// État, valeur ou postcondition exacte vérifiée (`Assert`).
  final String assertExpected;

  /// Message ou code d'erreur précis attendu en cas de rejet.
  final String expectedErrorMessage;

  /// Identifiants ou codes des règles de gestion (`RG-xxx`) couvertes.
  final List<String> businessRuleIds;

  /// Identifiants ou codes des exigences (`EXF-xxx` / `ENF-xxx`) couvertes.
  final List<String> requirementIds;

  /// Identifiants ou codes des écrans UX (`SCR-xxx`) concernés.
  final List<String> screenIds;

  /// Vérifie les invariants du cas de test TDD.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('TddTestCaseSpec.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'TddTestCaseSpec.title ne peut pas être vide.',
      );
    }
    if (order < 1) {
      throw FormatException(
        'TddTestCaseSpec.order doit être supérieur ou égal à 1 : $order',
      );
    }
  }

  /// Retourne une copie modifiée.
  TddTestCaseSpec copyWith({
    String? id,
    String? code,
    int? order,
    String? title,
    String? fixtureId,
    String? arrange,
    String? act,
    TddExpectedOutcomeKind? outcomeKind,
    String? assertExpected,
    String? expectedErrorMessage,
    List<String>? businessRuleIds,
    List<String>? requirementIds,
    List<String>? screenIds,
  }) => TddTestCaseSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    order: order ?? this.order,
    title: title ?? this.title,
    fixtureId: fixtureId ?? this.fixtureId,
    arrange: arrange ?? this.arrange,
    act: act ?? this.act,
    outcomeKind: outcomeKind ?? this.outcomeKind,
    assertExpected: assertExpected ?? this.assertExpected,
    expectedErrorMessage: expectedErrorMessage ?? this.expectedErrorMessage,
    businessRuleIds: businessRuleIds ?? this.businessRuleIds,
    requirementIds: requirementIds ?? this.requirementIds,
    screenIds: screenIds ?? this.screenIds,
  );

  /// Sérialise le cas de test TDD en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'order': order,
    'title': title,
    'fixtureId': fixtureId,
    'arrange': arrange,
    'act': act,
    'outcomeKind': outcomeKind.name,
    'assertExpected': assertExpected,
    'expectedErrorMessage': expectedErrorMessage,
    'businessRuleIds': businessRuleIds,
    'requirementIds': requirementIds,
    'screenIds': screenIds,
  };

  /// Désérialise un cas de test TDD depuis JSON avec valeurs de repli tolérantes.
  factory TddTestCaseSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'TddTestCaseSpec doit être un objet JSON.',
      );
    }
    final rawOrder = raw['order'];
    final parsedOrder = switch (rawOrder) {
      final int v => v,
      final num v => v.toInt(),
      final String s => int.tryParse(s.trim()) ?? 1,
      _ => 1,
    };
    final order = parsedOrder < 1 ? 1 : parsedOrder;
    final rawTitle =
        (raw['title'] as String?)?.trim() ??
        (raw['name'] as String?)?.trim() ??
        '';
    final title = rawTitle.isEmpty ? 'Cas TDD $order' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final testCase = TddTestCaseSpec(
      id: rawId.isEmpty ? 'tc_${order}_${title.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'TC' : rawCode,
      order: order,
      title: title,
      fixtureId: (raw['fixtureId'] as String?)?.trim() ?? '',
      arrange: (raw['arrange'] as String?)?.trim() ?? '',
      act: (raw['act'] as String?)?.trim() ?? '',
      outcomeKind: TddExpectedOutcomeKind.fromJson(raw['outcomeKind']),
      assertExpected: (raw['assertExpected'] as String?)?.trim() ?? '',
      expectedErrorMessage:
          (raw['expectedErrorMessage'] as String?)?.trim() ?? '',
      businessRuleIds: _stringList(raw['businessRuleIds']),
      requirementIds: _stringList(raw['requirementIds']),
      screenIds: _stringList(raw['screenIds']),
    );
    testCase.validate();
    return testCase;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TddTestCaseSpec &&
          other.id == id &&
          other.code == code &&
          other.order == order &&
          other.title == title &&
          other.fixtureId == fixtureId &&
          other.arrange == arrange &&
          other.act == act &&
          other.outcomeKind == outcomeKind &&
          other.assertExpected == assertExpected &&
          other.expectedErrorMessage == expectedErrorMessage &&
          listEquals(other.businessRuleIds, businessRuleIds) &&
          listEquals(other.requirementIds, requirementIds) &&
          listEquals(other.screenIds, screenIds);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    order,
    title,
    fixtureId,
    arrange,
    act,
    outcomeKind,
    assertExpected,
    expectedErrorMessage,
    Object.hashAll(businessRuleIds),
    Object.hashAll(requirementIds),
    Object.hashAll(screenIds),
  );
}

/// Suite logique de cas de tests TDD ciblant un objet métier, module ou couche technique (étape QA 3).
@immutable
class TddTestSuiteSpec {
  /// Construit une suite de tests TDD immuable.
  TddTestSuiteSpec({
    required this.id,
    this.code = 'TDD',
    required this.name,
    this.layer = TddTargetLayer.domainValidation,
    this.targetObjectId = '',
    this.moduleId = '',
    this.description = '',
    List<TddTestCaseSpec> cases = const <TddTestCaseSpec>[],
  }) : cases = List<TddTestCaseSpec>.unmodifiable(cases);

  /// Identifiant technique unique de la suite (ex. `tdd_validation_commande`).
  final String id;

  /// Code lisible de la suite TDD (ex. `TDD-001`).
  final String code;

  /// Intitulé de la suite de tests.
  final String name;

  /// Couche ou nature du contrat vérifié par cette suite.
  final TddTargetLayer layer;

  /// Identifiant ou nom technique de l'objet métier ciblé (optionnel).
  final String targetObjectId;

  /// Identifiant du module fonctionnel rattaché (optionnel).
  final String moduleId;

  /// Périmètre et stratégie Red → Green → Refactor de la suite.
  final String description;

  /// Séquence ordonnée des cas de tests atomiques `Arrange / Act / Assert`.
  final List<TddTestCaseSpec> cases;

  /// Vérifie les invariants de la suite et l'unicité des identifiants de cas.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('TddTestSuiteSpec.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'TddTestSuiteSpec.name ne peut pas être vide.',
      );
    }
    final caseIds = <String>{};
    for (final testCase in cases) {
      testCase.validate();
      if (!caseIds.add(testCase.id)) {
        throw FormatException(
          'Cas TDD dupliqué « ${testCase.id} » dans la suite « $name ».',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  TddTestSuiteSpec copyWith({
    String? id,
    String? code,
    String? name,
    TddTargetLayer? layer,
    String? targetObjectId,
    String? moduleId,
    String? description,
    List<TddTestCaseSpec>? cases,
  }) => TddTestSuiteSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    layer: layer ?? this.layer,
    targetObjectId: targetObjectId ?? this.targetObjectId,
    moduleId: moduleId ?? this.moduleId,
    description: description ?? this.description,
    cases: cases ?? this.cases,
  );

  /// Sérialise la suite TDD en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'layer': layer.name,
    'targetObjectId': targetObjectId,
    'moduleId': moduleId,
    'description': description,
    'cases': [for (final c in cases) c.toJson()],
  };

  /// Désérialise une suite TDD depuis JSON avec valeurs de repli tolérantes.
  factory TddTestSuiteSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'TddTestSuiteSpec doit être un objet JSON.',
      );
    }
    final rawName =
        (raw['name'] as String?)?.trim() ??
        (raw['title'] as String?)?.trim() ??
        '';
    final name = rawName.isEmpty ? 'Suite TDD sans nom' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';

    final parsedCases = <TddTestCaseSpec>[];
    final seenCaseIds = <String>{};
    if (raw['cases'] is List) {
      final rawList = raw['cases'] as List;
      for (var i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        var testCase = item is Map && item['order'] == null
            ? TddTestCaseSpec.fromJson(<Object?, Object?>{
                ...item,
                'order': i + 1,
              })
            : TddTestCaseSpec.fromJson(item);
        if (!seenCaseIds.add(testCase.id)) {
          var suffix = 2;
          while (!seenCaseIds.add('${testCase.id}_$suffix')) {
            suffix++;
          }
          testCase = testCase.copyWith(id: '${testCase.id}_$suffix');
        }
        parsedCases.add(testCase);
      }
    }

    final suite = TddTestSuiteSpec(
      id: rawId.isEmpty ? 'tdd_${name.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'TDD' : rawCode,
      name: name,
      layer: TddTargetLayer.fromJson(raw['layer']),
      targetObjectId:
          (raw['targetObjectId'] as String?)?.trim() ??
          (raw['businessObjectId'] as String?)?.trim() ??
          '',
      moduleId: (raw['moduleId'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      cases: parsedCases,
    );
    suite.validate();
    return suite;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TddTestSuiteSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.layer == layer &&
          other.targetObjectId == targetObjectId &&
          other.moduleId == moduleId &&
          other.description == description &&
          listEquals(other.cases, cases);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    layer,
    targetObjectId,
    moduleId,
    description,
    Object.hashAll(cases),
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
