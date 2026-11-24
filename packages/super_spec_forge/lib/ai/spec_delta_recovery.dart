/// Récupération incrémentale et prompts de reprise delta en cas d'exception IA ([SpecDeltaRecovery]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import '../models/spec_forge_project.dart';
import 'cost_patch_applier.dart';
import 'spec_patch_applier.dart';

/// Résultat immuable d'une tentative de récupération partielle après échec IA.
@immutable
class SpecSalvageOutcome {
  /// Construit un résultat de récupération partielle.
  const SpecSalvageOutcome({
    required this.hasCheckpoint,
    required this.checkpointProject,
    required this.appliedSummary,
    required this.rejectedEntries,
    required this.wasTruncated,
  });

  /// Aucun progrès exploitable conservé.
  factory SpecSalvageOutcome.none(
    SpecForgeProject fallbackProject, {
    List<SpecPatchRejectedEntry> rejectedEntries = const [],
    bool wasTruncated = false,
  }) => SpecSalvageOutcome(
    hasCheckpoint: false,
    checkpointProject: fallbackProject,
    appliedSummary: '',
    rejectedEntries: rejectedEntries,
    wasTruncated: wasTruncated,
  );

  /// Vrai si au moins un fragment valide a été retenu dans [checkpointProject].
  final bool hasCheckpoint;

  /// Projet partiel sain servant de base au prochain essai.
  final SpecForgeProject checkpointProject;

  /// Résumé lisible des éléments conservés.
  final String appliedSummary;

  /// Entrées rejetées lors de la validation par élément.
  final List<SpecPatchRejectedEntry> rejectedEntries;

  /// Indique si la réponse brute était tronquée ou JSON-invalide.
  final bool wasTruncated;
}

/// Utilitaires de récupération partielle et de relance delta après erreur IA.
abstract final class SpecDeltaRecovery {
  /// Extrait le maximum d'éléments valides depuis [rawResponse] ou [decodedPatch]
  /// et retourne un [SpecSalvageOutcome] exploitable pour une relance delta.
  static SpecSalvageOutcome salvageFailedAttempt({
    required SpecForgeProject workingProject,
    required String rawResponse,
    Map<String, Object?>? decodedPatch,
  }) {
    final wasTruncated = decodedPatch == null;
    final candidatePatch =
        decodedPatch ?? _trySalvagePatchFromTruncatedJson(rawResponse);

    if (candidatePatch == null || candidatePatch.isEmpty) {
      return SpecSalvageOutcome.none(
        workingProject,
        wasTruncated: wasTruncated,
      );
    }

    final partial = SpecPatchApplier.applyPartial(workingProject, candidatePatch);
    final hasCheckpoint = partial.project != workingProject;
    return SpecSalvageOutcome(
      hasCheckpoint: hasCheckpoint,
      checkpointProject: partial.project,
      appliedSummary: partial.summary,
      rejectedEntries: partial.rejectedEntries,
      wasTruncated: wasTruncated,
    );
  }

  /// Récupère le maximum d'éléments valides d'un `"costPatch"` (et d'un éventuel
  /// `"specPatch"` additif) depuis une réponse FinOps échouée ou tronquée.
  static SpecSalvageOutcome salvageCostFailedAttempt({
    required SpecForgeProject workingProject,
    required String rawResponse,
    Map<String, Object?>? decodedCostPatch,
    Map<String, Object?>? decodedSpecPatch,
  }) => CostPatchApplier.salvageFailedAttempt(
    workingProject: workingProject,
    rawResponse: rawResponse,
    decodedCostPatch: decodedCostPatch,
    decodedSpecPatch: decodedSpecPatch,
  );

  /// Construit le prompt de relance delta incluant le contexte actualisé,
  /// les causes précédentes et les entrées à corriger ou compléter.
  static String buildDeltaRetryPrompt({
    required String refreshedTurnPrompt,
    required List<String> priorCauses,
    required SpecSalvageOutcome salvage,
    String? rawFailedResponse,
  }) {
    final buf = StringBuffer(refreshedTurnPrompt)
      ..writeln()
      ..writeln()
      ..writeln('---')
      ..writeln('REPRISE AUTOMATIQUE APRÈS ERREUR DE VALIDATION / GÉNÉRATION :');

    for (final cause in priorCauses) {
      buf.writeln('- $cause');
    }

    if (salvage.hasCheckpoint) {
      buf.writeln(
        '- Checkpoint partiel DÉJÀ APPLIQUÉ et conservé (${salvage.appliedSummary}) : '
        'ne régénère pas les éléments déjà présents dans l’état courant.',
      );
    }

    if (salvage.wasTruncated) {
      buf.writeln(
        '- La réponse précédente était tronquée ou mal formée en JSON : '
        'renvoie un objet JSON complet, compact et strictement valide.',
      );
    }

    if (salvage.rejectedEntries.isNotEmpty) {
      buf.writeln('- Éléments rejetés à corriger impérativement :');
      for (final entry in salvage.rejectedEntries) {
        buf.writeln('  * ${entry.section}[${entry.key}] -> ${entry.reason}');
      }
    }

    if (!salvage.hasCheckpoint &&
        rawFailedResponse != null &&
        rawFailedResponse.trim().isNotEmpty) {
      final excerpt = rawFailedResponse.trim();
      final clipped = excerpt.length > 800
          ? '${excerpt.substring(0, 800)}…'
          : excerpt;
      buf
        ..writeln('- Extrait de la réponse rejetée :')
        ..writeln(clipped);
    }

    buf.writeln(
      'Corrige uniquement les points en erreur ou manquants et renvoie un JSON valide conforme au schéma.',
    );
    return buf.toString();
  }

  /// Tente d'extraire et équilibrer un champ objet JSON racine (`"specPatch"`,
  /// `"uxPatch"`, `"qaPatch"`, `"costPatch"`) même si le flux global a été tronqué.
  static Map<String, Object?>? trySalvageObjectField(
    String raw,
    String fieldName,
  ) {
    final match = RegExp('"${RegExp.escape(fieldName)}"\\s*:\\s*\\{')
        .firstMatch(raw);
    if (match == null) return null;
    final startBrace = match.end - 1;
    final slice = raw.substring(startBrace);

    // Essaie d'abord de fermer les accolades/crochets ouverts pour décoder le préfixe sain.
    final balanced = _closeOpenJsonContainers(slice);
    if (balanced == null) return null;
    try {
      final decoded = jsonDecode(balanced);
      if (decoded is Map) {
        return <String, Object?>{
          for (final entry in decoded.entries)
            if (entry.key is String) entry.key as String: entry.value,
        };
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Tente d'extraire les objets complets fermés d'un `"specPatch"` même si le flux
  /// JSON global a été coupé avant la fin.
  static Map<String, Object?>? _trySalvagePatchFromTruncatedJson(String raw) =>
      trySalvageObjectField(raw, 'specPatch');

  static String? _closeOpenJsonContainers(String input) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    var lastSafeIndex = 0;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
          if (stack.length <= 2) {
            lastSafeIndex = i + 1;
          }
        }
        continue;
      }

      if (ch == '"') {
        inString = true;
      } else if (ch == '{' || ch == '[') {
        stack.add(ch == '{' ? '}' : ']');
      } else if (ch == '}' || ch == ']') {
        if (stack.isNotEmpty && stack.last == ch) {
          stack.removeLast();
          lastSafeIndex = i + 1;
          if (stack.isEmpty) {
            return input.substring(0, i + 1);
          }
        }
      } else if (ch == ',') {
        lastSafeIndex = i;
      }
    }

    if (lastSafeIndex <= 1) return null;
    var prefix = input.substring(0, lastSafeIndex).trimRight();
    while (prefix.endsWith(',')) {
      prefix = prefix.substring(0, prefix.length - 1).trimRight();
    }
    // Recalcule la pile sur le préfixe sain retenu.
    final closing = <String>[];
    var str = false;
    var esc = false;
    for (var i = 0; i < prefix.length; i++) {
      final ch = prefix[i];
      if (str) {
        if (esc) {
          esc = false;
        } else if (ch == '\\') {
          esc = true;
        } else if (ch == '"') {
          str = false;
        }
        continue;
      }
      if (ch == '"') {
        str = true;
      } else if (ch == '{') {
        closing.add('}');
      } else if (ch == '[') {
        closing.add(']');
      } else if ((ch == '}' || ch == ']') && closing.isNotEmpty) {
        closing.removeLast();
      }
    }
    if (str) return null;
    return '$prefix${closing.reversed.join()}';
  }
}
