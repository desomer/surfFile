/// Modèles immuables de planification par lots ([VibeExecutionPlan], [VibePlanLot])
/// pour le mode « Reproduire à l'identique » du chat Vibe IA.
///
/// Représente le découpage d'un écran complexe en lots séquentiels validés par
/// l'utilisateur avant exécution automatique, ainsi que le suivi de statut
/// individuel de chaque lot et la gestion de pause/reprise sur erreur.
library;

import 'package:flutter/foundation.dart';

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
  skipped('Ignoré');

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

  /// Tous les lots ont été traités (terminés ou ignorés).
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
  };

  /// Retourne une copie modifiée de ce lot.
  VibePlanLot copyWith({
    String? id,
    String? title,
    String? description,
    VibeLotStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => VibePlanLot(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibePlanLot &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.status == status &&
          other.errorMessage == errorMessage;

  @override
  int get hashCode =>
      Object.hash(id, title, description, status, errorMessage);
}

/// Plan de génération découpé en lots séquentiels pour le chat Vibe IA.
@immutable
class VibeExecutionPlan {
  /// Construit un plan immuable composé de [lots].
  VibeExecutionPlan({
    required this.title,
    required List<VibePlanLot> lots,
    this.status = VibePlanStatus.awaitingConfirmation,
  }) : lots = List<VibePlanLot>.unmodifiable(lots);

  /// Titre global du plan affiché en tête de carte.
  final String title;

  /// Liste ordonnée et immuable des lots à exécuter séquentiellement.
  final List<VibePlanLot> lots;

  /// État courant d'exécution du plan.
  final VibePlanStatus status;

  /// Nombre de lots terminés avec succès.
  int get doneCount =>
      lots.where((lot) => lot.status == VibeLotStatus.done).length;

  /// Nombre de lots traités ([VibeLotStatus.done] ou [VibeLotStatus.skipped]).
  int get finishedCount => lots
      .where(
        (lot) =>
            lot.status == VibeLotStatus.done ||
            lot.status == VibeLotStatus.skipped,
      )
      .length;

  /// Indice du premier lot à traiter (`pending` ou `failed`), ou `-1` si tout est traité.
  int get nextActionableIndex => lots.indexWhere(
    (lot) =>
        lot.status == VibeLotStatus.pending ||
        lot.status == VibeLotStatus.failed,
  );

  /// Analyse l'objet JSON `"plan"` retourné par l'IA, ou retourne `null` s'il est invalide/vide.
  static VibeExecutionPlan? tryFromJson(Object? raw) {
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

    final rawTitle = raw['title'] ?? raw['name'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : 'Plan de reproduction à l’identique';
    return VibeExecutionPlan(title: title, lots: parsedLots);
  }

  /// Sérialise ce plan en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'status': status.name,
    'lots': [for (final lot in lots) lot.toJson()],
  };

  /// Retourne une copie du plan avec de nouveaux champs éventuels.
  VibeExecutionPlan copyWith({
    String? title,
    List<VibePlanLot>? lots,
    VibePlanStatus? status,
  }) => VibeExecutionPlan(
    title: title ?? this.title,
    lots: lots ?? this.lots,
    status: status ?? this.status,
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
      final marker = i == lotIndex ? '>>> À EXÉCUTER MAINTENANT' : lot.status.label;
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
          listEquals(other.lots, lots);

  @override
  int get hashCode => Object.hash(title, status, Object.hashAll(lots));
}
