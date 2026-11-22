/// Modèles immuables de planification par lots ([VibeExecutionPlan], [VibePlanLot])
/// pour le mode « Plan » (et sa combinaison avec « Reproduire à l'identique ») du chat Vibe IA.
///
/// Représente le découpage d'une demande ou d'un écran complexe en lots séquentiels
/// validés par l'utilisateur avant exécution automatique, ainsi que le suivi de statut
/// individuel de chaque lot et la gestion de pause/reprise sur erreur.
library;

import 'package:flutter/foundation.dart';

/// Formate une durée exprimée en millisecondes de façon lisible (`142 ms`, `3.4 s`, `1m 12s`).
String formatVibeDuration(int durationMs) {
  final safeMs = durationMs < 0 ? 0 : durationMs;
  if (safeMs < 1000) return '$safeMs ms';
  if (safeMs < 60000) {
    return '${(safeMs / 1000).toStringAsFixed(1)} s';
  }
  final totalSeconds = safeMs ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

/// Trace chronométrée d'une étape d'orchestration, d'appel IA, d'outil ou de reprise.
@immutable
class VibeTimedTrace {
  /// Construit une trace timée immuable.
  const VibeTimedTrace({
    required this.label,
    required this.durationMs,
    this.phase = 'step',
    this.elapsedFromStartMs,
    this.detail,
    this.isError = false,
  });

  /// Libellé synthétique de l'étape mesurée.
  final String label;

  /// Durée propre de cette étape en millisecondes.
  final int durationMs;

  /// Catégorie technique (`context`, `llm`, `tool`, `salvage`, `apply`, `verify`, `retry`, `step`).
  final String phase;

  /// Décalage cumulé en millisecondes depuis le début du tour ou du lot.
  final int? elapsedFromStartMs;

  /// Précision optionnelle (ex. TTFT, nombre de composants, erreur).
  final String? detail;

  /// Indique si cette étape s'est terminée en erreur ou en rejet.
  final bool isError;

  /// Formate cette trace sur une ligne compacte horodatée.
  String formatLine() {
    final offsetPrefix = elapsedFromStartMs == null
        ? ''
        : '+${formatVibeDuration(elapsedFromStartMs!)} · ';
    final detailSuffix = detail != null && detail!.trim().isNotEmpty
        ? ' (${detail!.trim()})'
        : '';
    return '$offsetPrefix$label · ${formatVibeDuration(durationMs)}$detailSuffix';
  }

  /// Sérialise cette trace en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'phase': phase,
    'label': label,
    'durationMs': durationMs,
    if (elapsedFromStartMs != null) 'elapsedFromStartMs': elapsedFromStartMs,
    if (detail != null && detail!.isNotEmpty) 'detail': detail,
    if (isError) 'isError': true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeTimedTrace &&
          other.label == label &&
          other.durationMs == durationMs &&
          other.phase == phase &&
          other.elapsedFromStartMs == elapsedFromStartMs &&
          other.detail == detail &&
          other.isError == isError;

  @override
  int get hashCode => Object.hash(
    label,
    durationMs,
    phase,
    elapsedFromStartMs,
    detail,
    isError,
  );
}

/// État d'exécution d'un lot individuel au sein d'un [VibeExecutionPlan].
enum VibeLotStatus {
  /// En attente d'exécution.
  pending('En attente'),

  /// En cours de génération et d'application.
  running('En cours'),

  /// Généré, validé et appliqué avec succès.
  done('Terminé'),

  /// En échec après les tentatives de récupération delta.
  failed('Échec'),

  /// Ignoré manuellement par l'utilisateur après un échec.
  skipped('Ignoré'),

  /// Désactivé par l'utilisateur avant le lancement du plan.
  disabled('Désactivé');

  /// Construit un statut de lot.
  const VibeLotStatus(this.label);

  /// Libellé lisible en français affiché dans la carte du plan.
  final String label;
}

/// État global d'un [VibeExecutionPlan].
enum VibePlanStatus {
  /// Plan généré par l'IA, en attente du clic utilisateur « Exécuter les lots ».
  awaitingConfirmation('En attente de lancement'),

  /// Exécution automatique des lots en cours.
  running('Exécution en cours'),

  /// Exécution mise en pause suite à l'échec d'un lot.
  pausedOnError('En pause (erreur)'),

  /// Tous les lots ont été traités, ignorés ou désactivés.
  completed('Plan terminé'),

  /// Plan annulé avant lancement ou arrêté manuellement par l'utilisateur.
  stopped('Plan arrêté');

  /// Construit un statut global de plan.
  const VibePlanStatus(this.label);

  /// Libellé court affiché sur l'en-tête de la carte.
  final String label;
}

/// Étape (lot) individuelle d'un [VibeExecutionPlan].
@immutable
class VibePlanLot {
  /// Construit un lot immuable de planification Vibe IA.
  const VibePlanLot({
    required this.id,
    required this.title,
    this.description = '',
    this.status = VibeLotStatus.pending,
    this.errorMessage,
    this.durationMs,
    this.attempts = 0,
    this.hasPartialCheckpoint = false,
    this.partialCheckpointSummary,
    this.traces = const <VibeTimedTrace>[],
  });

  /// Identifiant technique unique du lot (ex. `"lot-1"`).
  final String id;

  /// Titre concis du lot affiché à l'utilisateur.
  final String title;

  /// Description détaillée du périmètre visuel et structurel à générer dans ce lot.
  final String description;

  /// État d'avancement du lot.
  final VibeLotStatus status;

  /// Cause détaillée de l'échec lorsque [status] vaut [VibeLotStatus.failed].
  final String? errorMessage;

  /// Durée totale d'exécution de ce lot en millisecondes, lorsqu'elle est mesurée.
  final int? durationMs;

  /// Nombre de tentatives IA consommées lors de la dernière exécution du lot.
  final int attempts;

  /// Indique qu'un checkpoint partiel valide est conservé pour un retry partiel (delta).
  final bool hasPartialCheckpoint;

  /// Résumé lisible du checkpoint partiel conservé (ex. `6 comp., 2 styles`).
  final String? partialCheckpointSummary;

  /// Journal chronométré des étapes exécutées sur ce lot.
  final List<VibeTimedTrace> traces;

  /// Analyse un objet JSON brut en [VibePlanLot], ou retourne `null` si invalide.
  static VibePlanLot? tryFromJson(Object? raw, {int fallbackIndex = 1}) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return VibePlanLot(
        id: 'lot-$fallbackIndex',
        title: trimmed,
        description: trimmed,
      );
    }
    if (raw is! Map) return null;
    final rawTitle = raw['title'] ?? raw['name'] ?? raw['label'];
    final rawDescription = raw['description'] ?? raw['details'] ?? raw['scope'];
    final title = rawTitle is String ? rawTitle.trim() : '';
    final description = rawDescription is String ? rawDescription.trim() : '';
    if (title.isEmpty && description.isEmpty) return null;
    final rawId = raw['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId.trim()
        : 'lot-$fallbackIndex';
    return VibePlanLot(
      id: id,
      title: title.isNotEmpty ? title : 'Lot $fallbackIndex',
      description: description.isNotEmpty ? description : title,
    );
  }

  /// Sérialise ce lot en JSON pour la journalisation ou la reprise de contexte.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    'status': status.name,
    if (durationMs != null) 'durationMs': durationMs,
    if (attempts > 0) 'attempts': attempts,
    if (hasPartialCheckpoint) 'hasPartialCheckpoint': true,
    if (partialCheckpointSummary != null &&
        partialCheckpointSummary!.isNotEmpty)
      'partialCheckpointSummary': partialCheckpointSummary,
    if (traces.isNotEmpty)
      'traces': [for (final trace in traces) trace.toJson()],
  };

  /// Retourne une copie modifiée de ce lot.
  VibePlanLot copyWith({
    String? id,
    String? title,
    String? description,
    VibeLotStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    int? durationMs,
    bool clearDuration = false,
    int? attempts,
    bool? hasPartialCheckpoint,
    String? partialCheckpointSummary,
    bool clearPartialCheckpoint = false,
    List<VibeTimedTrace>? traces,
  }) => VibePlanLot(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
    durationMs: clearDuration ? null : (durationMs ?? this.durationMs),
    attempts: attempts ?? this.attempts,
    hasPartialCheckpoint: clearPartialCheckpoint
        ? false
        : (hasPartialCheckpoint ?? this.hasPartialCheckpoint),
    partialCheckpointSummary: clearPartialCheckpoint
        ? null
        : (partialCheckpointSummary ?? this.partialCheckpointSummary),
    traces: List<VibeTimedTrace>.unmodifiable(traces ?? this.traces),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibePlanLot &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.status == status &&
          other.errorMessage == errorMessage &&
          other.durationMs == durationMs &&
          other.attempts == attempts &&
          other.hasPartialCheckpoint == hasPartialCheckpoint &&
          other.partialCheckpointSummary == partialCheckpointSummary &&
          listEquals(other.traces, traces);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    status,
    errorMessage,
    durationMs,
    attempts,
    hasPartialCheckpoint,
    partialCheckpointSummary,
    Object.hashAll(traces),
  );
}

/// Plan de génération découpé en lots séquentiels pour le chat Vibe IA.
@immutable
class VibeExecutionPlan {
  /// Construit un plan immuable composé de [lots].
  VibeExecutionPlan({
    required this.title,
    required List<VibePlanLot> lots,
    this.status = VibePlanStatus.awaitingConfirmation,
    this.reproduceExact = false,
    this.planningDurationMs,
    this.executionDurationMs,
    List<VibeTimedTrace> planningTraces = const <VibeTimedTrace>[],
  }) : lots = List<VibePlanLot>.unmodifiable(lots),
       planningTraces = List<VibeTimedTrace>.unmodifiable(planningTraces);

  /// Titre global du plan affiché en tête de carte.
  final String title;

  /// Liste ordonnée et immuable des lots à exécuter séquentiellement.
  final List<VibePlanLot> lots;

  /// État courant d'exécution du plan.
  final VibePlanStatus status;

  /// Indique si ce plan a été généré en mode « À l’identique » (pixel-perfect).
  final bool reproduceExact;

  /// Durée de la Phase 1 (analyse et découpage du plan) en millisecondes.
  final int? planningDurationMs;

  /// Durée totale d'exécution de la Phase 2 (boucle des lots) en millisecondes.
  final int? executionDurationMs;

  /// Traces chronométrées de la Phase 1 (planification).
  final List<VibeTimedTrace> planningTraces;

  /// Somme des durées mesurées (planification + exécution des lots).
  int get totalMeasuredDurationMs {
    final exec =
        executionDurationMs ??
        lots.fold<int>(0, (sum, lot) => sum + (lot.durationMs ?? 0));
    return (planningDurationMs ?? 0) + exec;
  }

  /// Nombre de lots terminés avec succès.
  int get doneCount =>
      lots.where((lot) => lot.status == VibeLotStatus.done).length;

  /// Nombre de lots traités, plus les lots désactivés après le lancement.
  int get finishedCount => lots
      .where(
        (lot) =>
            lot.status == VibeLotStatus.done ||
            lot.status == VibeLotStatus.skipped ||
            (status != VibePlanStatus.awaitingConfirmation &&
                lot.status == VibeLotStatus.disabled),
      )
      .length;

  /// Nombre de lots qui restent activés et peuvent être exécutés ou repris.
  int get actionableCount => lots
      .where(
        (lot) =>
            lot.status == VibeLotStatus.pending ||
            lot.status == VibeLotStatus.failed,
      )
      .length;

  /// Indice du premier lot à traiter (`pending` ou `failed`), ou `-1` si tout est traité.
  int get nextActionableIndex => lots.indexWhere(
    (lot) =>
        lot.status == VibeLotStatus.pending ||
        lot.status == VibeLotStatus.failed,
  );

  /// Analyse l'objet JSON `"plan"` retourné par l'IA, ou retourne `null` s'il est invalide/vide.
  static VibeExecutionPlan? tryFromJson(
    Object? raw, {
    bool reproduceExact = false,
  }) {
    if (raw is! Map) return null;
    final rawLots = raw['lots'] ?? raw['steps'];
    if (rawLots is! List || rawLots.isEmpty) return null;

    final parsedLots = <VibePlanLot>[];
    final seenIds = <String>{};
    for (var i = 0; i < rawLots.length; i++) {
      final parsed = VibePlanLot.tryFromJson(rawLots[i], fallbackIndex: i + 1);
      if (parsed == null) continue;
      var uniqueId = parsed.id;
      var suffix = 2;
      while (!seenIds.add(uniqueId)) {
        uniqueId = '${parsed.id}_$suffix';
        suffix++;
      }
      parsedLots.add(
        uniqueId == parsed.id ? parsed : parsed.copyWith(id: uniqueId),
      );
    }
    if (parsedLots.isEmpty) return null;

    final rawExact = raw['reproduceExact'];
    final effectiveExact = rawExact is bool ? rawExact : reproduceExact;
    final rawTitle = raw['title'] ?? raw['name'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : effectiveExact
        ? 'Plan de reproduction à l’identique'
        : 'Plan d’exécution par lots';
    return VibeExecutionPlan(
      title: title,
      lots: parsedLots,
      reproduceExact: effectiveExact,
    );
  }

  /// Sérialise ce plan en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'status': status.name,
    if (reproduceExact) 'reproduceExact': true,
    if (planningDurationMs != null) 'planningDurationMs': planningDurationMs,
    if (executionDurationMs != null) 'executionDurationMs': executionDurationMs,
    if (planningTraces.isNotEmpty)
      'planningTraces': [for (final t in planningTraces) t.toJson()],
    'lots': [for (final lot in lots) lot.toJson()],
  };

  /// Retourne une copie du plan avec de nouveaux champs éventuels.
  VibeExecutionPlan copyWith({
    String? title,
    List<VibePlanLot>? lots,
    VibePlanStatus? status,
    bool? reproduceExact,
    int? planningDurationMs,
    int? executionDurationMs,
    bool clearExecutionDuration = false,
    List<VibeTimedTrace>? planningTraces,
  }) => VibeExecutionPlan(
    title: title ?? this.title,
    lots: lots ?? this.lots,
    status: status ?? this.status,
    reproduceExact: reproduceExact ?? this.reproduceExact,
    planningDurationMs: planningDurationMs ?? this.planningDurationMs,
    executionDurationMs: clearExecutionDuration
        ? null
        : (executionDurationMs ?? this.executionDurationMs),
    planningTraces: planningTraces ?? this.planningTraces,
  );

  /// Retourne une copie du plan après mise à jour du lot situé à [index].
  VibeExecutionPlan withLotAt(
    int index,
    VibePlanLot Function(VibePlanLot lot) transform,
  ) {
    if (index < 0 || index >= lots.length) return this;
    final updated = List<VibePlanLot>.of(lots);
    updated[index] = transform(updated[index]);
    return copyWith(lots: updated);
  }

  /// Formate la progression du plan et le périmètre du lot [lotIndex] pour le prompt d'exécution.
  String formatLotContextPrompt(int lotIndex) {
    final target = lots[lotIndex];
    final buffer = StringBuffer()
      ..writeln('PLAN EN COURS : "$title" (lot ${lotIndex + 1}/${lots.length})')
      ..writeln('ÉTAT DES LOTS :');
    for (var i = 0; i < lots.length; i++) {
      final lot = lots[i];
      final marker = i == lotIndex
          ? '>>> À EXÉCUTER MAINTENANT'
          : lot.status.label;
      buffer.writeln(
        '${i + 1}. [${lot.id}] ${lot.title} — $marker'
        '${lot.description.isNotEmpty && i == lotIndex ? '\n   Détails : ${lot.description}' : ''}',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'LOT CIBLE OBLIGATOIRE (${lotIndex + 1}/${lots.length}) : '
        '"${target.title}" [${target.id}]',
      );
    if (target.description.isNotEmpty) {
      buffer.writeln('Périmètre exact du lot : ${target.description}');
    }
    return buffer.toString().trimRight();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeExecutionPlan &&
          other.title == title &&
          other.status == status &&
          other.reproduceExact == reproduceExact &&
          other.planningDurationMs == planningDurationMs &&
          other.executionDurationMs == executionDurationMs &&
          listEquals(other.planningTraces, planningTraces) &&
          listEquals(other.lots, lots);

  @override
  int get hashCode => Object.hash(
    title,
    status,
    reproduceExact,
    planningDurationMs,
    executionDurationMs,
    Object.hashAll(planningTraces),
    Object.hashAll(lots),
  );
}
