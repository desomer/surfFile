/// Modèles immuables des parcours utilisateurs et étapes de flux ([UxJourneySpec], [UxJourneyStep], [UxTargetChannel]).
library;

import 'package:flutter/foundation.dart';

/// Canal d'interaction cible d'un parcours utilisateur.
enum UxTargetChannel {
  /// Application de bureau (Windows / macOS / Linux).
  desktop('Desktop'),

  /// Application ou portail Web adaptatif.
  webResponsive('Web responsive'),

  /// Interface tactile tablette.
  tablet('Tablette'),

  /// Interface smartphone mobile.
  mobile('Mobile');

  /// Construit un canal cible UX.
  const UxTargetChannel(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un canal cible depuis JSON ou un alias courant, avec repli sur [desktop].
  static UxTargetChannel fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final channel in UxTargetChannel.values) {
        if (channel.name.toLowerCase() == norm ||
            channel.label.toLowerCase() == norm) {
          return channel;
        }
      }
      switch (norm) {
        case 'desktop_app':
        case 'pc':
        case 'windows':
        case 'bureau':
          return UxTargetChannel.desktop;
        case 'web':
        case 'web_responsive':
        case 'web-responsive':
        case 'responsive':
          return UxTargetChannel.webResponsive;
        case 'ipad':
          return UxTargetChannel.tablet;
        case 'phone':
        case 'smartphone':
        case 'ios':
        case 'android':
          return UxTargetChannel.mobile;
      }
    }
    return UxTargetChannel.desktop;
  }
}

/// Étape séquentielle ou conditionnelle d'un parcours utilisateur ([UxJourneySpec]).
@immutable
class UxJourneyStep {
  /// Construit une étape de parcours immuable.
  const UxJourneyStep({
    required this.id,
    this.order = 1,
    required this.title,
    this.actorAction = '',
    this.systemResponse = '',
    this.targetRouteId = '',
    this.branchCondition = '',
    this.painPointResolved = '',
  });

  /// Identifiant unique de l'étape au sein du parcours.
  final String id;

  /// Ordre séquentiel d'exécution (`>= 1`).
  final int order;

  /// Intitulé synthétique de l'étape.
  final String title;

  /// Action accomplie par l'utilisateur ou le persona.
  final String actorAction;

  /// Réponse visuelle ou métier fournie par le système.
  final String systemResponse;

  /// Identifiant de la route ou vue cible associée (optionnel).
  final String targetRouteId;

  /// Condition d'embranchement ou cas alternatif éventuel.
  final String branchCondition;

  /// Point de friction du persona résolu à cette étape.
  final String painPointResolved;

  /// Vérifie les invariants de l'étape de parcours.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('UxJourneyStep.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException('UxJourneyStep.title ne peut pas être vide.');
    }
    if (order < 1) {
      throw FormatException(
        'UxJourneyStep.order doit être supérieur ou égal à 1 : $order',
      );
    }
  }

  /// Retourne une copie modifiée.
  UxJourneyStep copyWith({
    String? id,
    int? order,
    String? title,
    String? actorAction,
    String? systemResponse,
    String? targetRouteId,
    String? branchCondition,
    String? painPointResolved,
  }) => UxJourneyStep(
    id: id ?? this.id,
    order: order ?? this.order,
    title: title ?? this.title,
    actorAction: actorAction ?? this.actorAction,
    systemResponse: systemResponse ?? this.systemResponse,
    targetRouteId: targetRouteId ?? this.targetRouteId,
    branchCondition: branchCondition ?? this.branchCondition,
    painPointResolved: painPointResolved ?? this.painPointResolved,
  );

  /// Sérialise l'étape en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'order': order,
    'title': title,
    'actorAction': actorAction,
    'systemResponse': systemResponse,
    'targetRouteId': targetRouteId,
    'branchCondition': branchCondition,
    'painPointResolved': painPointResolved,
  };

  /// Désérialise une étape de parcours depuis JSON avec valeurs de repli tolérantes.
  factory UxJourneyStep.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UxJourneyStep doit être un objet JSON.');
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
    final title = rawTitle.isEmpty ? 'Étape $order' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final step = UxJourneyStep(
      id: rawId.isEmpty ? 'step_${order}_${title.hashCode.abs()}' : rawId,
      order: order,
      title: title,
      actorAction: (raw['actorAction'] as String?)?.trim() ?? '',
      systemResponse: (raw['systemResponse'] as String?)?.trim() ?? '',
      targetRouteId: (raw['targetRouteId'] as String?)?.trim() ?? '',
      branchCondition: (raw['branchCondition'] as String?)?.trim() ?? '',
      painPointResolved: (raw['painPointResolved'] as String?)?.trim() ?? '',
    );
    step.validate();
    return step;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxJourneyStep &&
          other.id == id &&
          other.order == order &&
          other.title == title &&
          other.actorAction == actorAction &&
          other.systemResponse == systemResponse &&
          other.targetRouteId == targetRouteId &&
          other.branchCondition == branchCondition &&
          other.painPointResolved == painPointResolved;

  @override
  int get hashCode => Object.hash(
    id,
    order,
    title,
    actorAction,
    systemResponse,
    targetRouteId,
    branchCondition,
    painPointResolved,
  );
}

/// Parcours utilisateur bout-en-bout rattaché à un persona, des cas d'usage et des exigences.
@immutable
class UxJourneySpec {
  /// Construit un parcours utilisateur immuable.
  UxJourneySpec({
    required this.id,
    this.code = 'JRN',
    required this.name,
    this.personaId = '',
    List<String> useCaseIds = const <String>[],
    List<String> requirementIds = const <String>[],
    this.channel = UxTargetChannel.desktop,
    this.trigger = '',
    this.goal = '',
    List<UxJourneyStep> steps = const <UxJourneyStep>[],
    List<String> successCriteria = const <String>[],
  }) : useCaseIds = List<String>.unmodifiable(useCaseIds),
       requirementIds = List<String>.unmodifiable(requirementIds),
       steps = List<UxJourneyStep>.unmodifiable(steps),
       successCriteria = List<String>.unmodifiable(successCriteria);

  /// Identifiant technique unique du parcours (ex. `jrn_commande_express`).
  final String id;

  /// Code métier lisible du parcours (ex. `JRN-001`).
  final String code;

  /// Intitulé du parcours utilisateur.
  final String name;

  /// Identifiant du persona principal concerné.
  final String personaId;

  /// Identifiants des cas d'usage (`UseCaseSpec`) couverts.
  final List<String> useCaseIds;

  /// Identifiants ou codes des exigences fonctionnelles (`EXF-xxx`) couvertes.
  final List<String> requirementIds;

  /// Canal d'exécution cible du parcours.
  final UxTargetChannel channel;

  /// Événement ou contexte déclencheur initial du parcours.
  final String trigger;

  /// Objectif utilisateur visé en fin de parcours.
  final String goal;

  /// Séquence ordonnée des étapes du parcours.
  final List<UxJourneyStep> steps;

  /// Critères mesurables ou observables de réussite UX.
  final List<String> successCriteria;

  /// Vérifie les invariants du parcours et l'unicité des identifiants d'étapes.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('UxJourneySpec.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('UxJourneySpec.name ne peut pas être vide.');
    }
    final stepIds = <String>{};
    for (final step in steps) {
      step.validate();
      if (!stepIds.add(step.id)) {
        throw FormatException(
          'Étape de parcours dupliquée « ${step.id} » dans « $name ».',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  UxJourneySpec copyWith({
    String? id,
    String? code,
    String? name,
    String? personaId,
    List<String>? useCaseIds,
    List<String>? requirementIds,
    UxTargetChannel? channel,
    String? trigger,
    String? goal,
    List<UxJourneyStep>? steps,
    List<String>? successCriteria,
  }) => UxJourneySpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    personaId: personaId ?? this.personaId,
    useCaseIds: useCaseIds ?? this.useCaseIds,
    requirementIds: requirementIds ?? this.requirementIds,
    channel: channel ?? this.channel,
    trigger: trigger ?? this.trigger,
    goal: goal ?? this.goal,
    steps: steps ?? this.steps,
    successCriteria: successCriteria ?? this.successCriteria,
  );

  /// Sérialise le parcours en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'personaId': personaId,
    'useCaseIds': useCaseIds,
    'requirementIds': requirementIds,
    'channel': channel.name,
    'trigger': trigger,
    'goal': goal,
    'steps': [for (final s in steps) s.toJson()],
    'successCriteria': successCriteria,
  };

  /// Désérialise un parcours utilisateur depuis JSON avec valeurs de repli tolérantes.
  factory UxJourneySpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UxJourneySpec doit être un objet JSON.');
    }
    final rawName =
        (raw['name'] as String?)?.trim() ??
        (raw['title'] as String?)?.trim() ??
        '';
    final name = rawName.isEmpty ? 'Parcours sans nom' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';

    final parsedSteps = <UxJourneyStep>[];
    final seenStepIds = <String>{};
    if (raw['steps'] is List) {
      final rawList = raw['steps'] as List;
      for (var i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        var step = item is Map && item['order'] == null
            ? UxJourneyStep.fromJson(<Object?, Object?>{
                ...item,
                'order': i + 1,
              })
            : UxJourneyStep.fromJson(item);
        if (!seenStepIds.add(step.id)) {
          var suffix = 2;
          while (!seenStepIds.add('${step.id}_$suffix')) {
            suffix++;
          }
          step = step.copyWith(id: '${step.id}_$suffix');
        }
        parsedSteps.add(step);
      }
    }

    final journey = UxJourneySpec(
      id: rawId.isEmpty ? 'jrn_${name.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'JRN' : rawCode,
      name: name,
      personaId: (raw['personaId'] as String?)?.trim() ?? '',
      useCaseIds: _stringList(raw['useCaseIds']),
      requirementIds: _stringList(raw['requirementIds']),
      channel: UxTargetChannel.fromJson(raw['channel']),
      trigger: (raw['trigger'] as String?)?.trim() ?? '',
      goal: (raw['goal'] as String?)?.trim() ?? '',
      steps: parsedSteps,
      successCriteria: _stringList(raw['successCriteria']),
    );
    journey.validate();
    return journey;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxJourneySpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.personaId == personaId &&
          listEquals(other.useCaseIds, useCaseIds) &&
          listEquals(other.requirementIds, requirementIds) &&
          other.channel == channel &&
          other.trigger == trigger &&
          other.goal == goal &&
          listEquals(other.steps, steps) &&
          listEquals(other.successCriteria, successCriteria);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    personaId,
    Object.hashAll(useCaseIds),
    Object.hashAll(requirementIds),
    channel,
    trigger,
    goal,
    Object.hashAll(steps),
    Object.hashAll(successCriteria),
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
