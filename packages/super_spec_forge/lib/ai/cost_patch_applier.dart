/// Application déterministe et incrémentale des patches FinOps (`"costPatch"`) et
/// enrichissement strictement additif du modèle métier (`"specPatch"`) ([CostPatchApplier]).
library;

import 'package:flutter/foundation.dart';

import '../models/cost/cost_coherence_issue.dart';
import '../models/cost/cost_forge_spec.dart';
import '../models/cost/cost_risk_item_spec.dart';
import '../models/cost/cost_run_item_spec.dart';
import '../models/cost/cost_wbs_item_spec.dart';
import '../models/enterprise_rate_card.dart';
import '../models/spec_forge_project.dart';
import 'spec_delta_recovery.dart';
import 'spec_patch_applier.dart';
import 'ux_patch_applier.dart';

/// Résultat immuable d'application conjointe de `"costPatch"` et `"specPatch"`.
@immutable
class CostPatchResult {
  /// Construit un résultat d'application de patch FinOps / Coûts.
  const CostPatchResult({required this.project, required this.summary});

  /// Projet mis à jour.
  final SpecForgeProject project;

  /// Résumé lisible en français des sections modifiées.
  final String summary;
}

/// Résultat immuable d'une application tolérante par élément conservant les entrées Coûts/Spec valides.
@immutable
class CostPartialPatchResult {
  /// Construit un résultat d'application partielle FinOps / Coûts.
  CostPartialPatchResult({
    required this.project,
    required this.summary,
    List<SpecPatchRejectedEntry> rejectedEntries = const [],
  }) : rejectedEntries = List<SpecPatchRejectedEntry>.unmodifiable(
         rejectedEntries,
       );

  /// Projet mis à jour avec uniquement les éléments valides.
  final SpecForgeProject project;

  /// Résumé lisible des éléments valides appliqués.
  final String summary;

  /// Entrées individuelles rejetées accompagnées de leur motif de rejet.
  final List<SpecPatchRejectedEntry> rejectedEntries;

  /// Vrai si au moins un changement valide a été conservé.
  bool get hasAppliedChanges => summary.isNotEmpty;
}

/// Fusionne incrémentalement `"costPatch"` sur [CostForgeSpec] et applique
/// `"specPatch"` selon le contrat strictement additif (`additive_safe`) via [UxPatchApplier.applyAdditiveSpecPatch].
abstract final class CostPatchApplier {
  /// Applique [costPatch] et [specPatch] (mode additif sûr) sur [project] sans muter l'existant.
  static CostPatchResult apply(
    SpecForgeProject project, {
    Map<String, Object?>? costPatch,
    Map<String, Object?>? specPatch,
  }) {
    var next = project;
    final summaries = <String>[];

    if (costPatch != null && costPatch.isNotEmpty) {
      final updatedCost = _applyCostPatch(next.costSpec, costPatch, summaries);
      if (updatedCost != next.costSpec) {
        next = next.copyWith(costSpec: updatedCost);
      }
    }

    if (specPatch != null && specPatch.isNotEmpty) {
      next = UxPatchApplier.applyAdditiveSpecPatch(next, specPatch, summaries);
    }

    next.validate();
    return CostPatchResult(
      project: next,
      summary: summaries.isEmpty
          ? 'Aucune modification structurelle'
          : summaries.join(', '),
    );
  }

  /// Applique [costPatch] et [specPatch] élément par élément afin d'isoler toute
  /// entrée invalide dans [CostPartialPatchResult.rejectedEntries] tout en
  /// préservant un checkpoint sain.
  static CostPartialPatchResult applyPartial(
    SpecForgeProject project, {
    Map<String, Object?>? costPatch,
    Map<String, Object?>? specPatch,
  }) {
    var current = project;
    final appliedSummaries = <String>[];
    final rejected = <SpecPatchRejectedEntry>[];

    if (costPatch != null && costPatch.isNotEmpty) {
      for (final scalarKey in const <String>[
        'currency',
        'hoursPerDay',
        'deliveryMode',
        'targetUsersCount',
        'assumptionsNotes',
        'transverseRatios',
        'aiProductivity',
      ]) {
        if (costPatch[scalarKey] == null) continue;
        try {
          final before = current;
          final res = apply(
            current,
            costPatch: <String, Object?>{scalarKey: costPatch[scalarKey]},
          );
          if (res.project != before) {
            current = res.project;
            if (res.summary.isNotEmpty &&
                res.summary != 'Aucune modification structurelle') {
              appliedSummaries.add(res.summary);
            }
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'costPatch.$scalarKey',
              key: scalarKey,
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (costPatch['removeProfileIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            costPatch: <String, Object?>{
              'removeProfileIds': costPatch['removeProfileIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression profil(s) TJM');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'costPatch.removeProfileIds',
              key: 'removeProfileIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (costPatch['profiles'] != null) {
        if (costPatch['profiles'] is! List) {
          rejected.add(
            const SpecPatchRejectedEntry(
              section: 'costPatch.profiles',
              key: 'profiles',
              reason: 'costPatch.profiles doit être une liste JSON.',
            ),
          );
        } else {
          final rawProfiles = costPatch['profiles'] as List;
          var count = 0;
          for (var i = 0; i < rawProfiles.length; i++) {
            final item = rawProfiles[i];
            try {
              final res = apply(
                current,
                costPatch: <String, Object?>{
                  'profiles': <Object?>[item],
                },
              );
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'costPatch.profiles',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count profil(s) TJM');
        }
      }

      if (costPatch['tshirtPresets'] != null) {
        if (costPatch['tshirtPresets'] is! List) {
          rejected.add(
            const SpecPatchRejectedEntry(
              section: 'costPatch.tshirtPresets',
              key: 'tshirtPresets',
              reason: 'costPatch.tshirtPresets doit être une liste JSON.',
            ),
          );
        } else {
          final rawPresets = costPatch['tshirtPresets'] as List;
          var count = 0;
          for (var i = 0; i < rawPresets.length; i++) {
            final item = rawPresets[i];
            try {
              final res = apply(
                current,
                costPatch: <String, Object?>{
                  'tshirtPresets': <Object?>[item],
                },
              );
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'costPatch.tshirtPresets',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count calibre(s) T-shirt');
        }
      }

      if (costPatch['removeWbsItemIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            costPatch: <String, Object?>{
              'removeWbsItemIds': costPatch['removeWbsItemIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression lot(s) WBS');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'costPatch.removeWbsItemIds',
              key: 'removeWbsItemIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (costPatch['wbsItems'] != null) {
        if (costPatch['wbsItems'] is! List) {
          rejected.add(
            const SpecPatchRejectedEntry(
              section: 'costPatch.wbsItems',
              key: 'wbsItems',
              reason: 'costPatch.wbsItems doit être une liste JSON.',
            ),
          );
        } else {
          final rawWbs = costPatch['wbsItems'] as List;
          var count = 0;
          for (var i = 0; i < rawWbs.length; i++) {
            final item = rawWbs[i];
            try {
              final res = apply(
                current,
                costPatch: <String, Object?>{
                  'wbsItems': <Object?>[item],
                },
              );
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'costPatch.wbsItems',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count lot(s) WBS');
        }
      }

      if (costPatch['removeRunItemIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            costPatch: <String, Object?>{
              'removeRunItemIds': costPatch['removeRunItemIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression poste(s) Run');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'costPatch.removeRunItemIds',
              key: 'removeRunItemIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (costPatch['runItems'] != null) {
        if (costPatch['runItems'] is! List) {
          rejected.add(
            const SpecPatchRejectedEntry(
              section: 'costPatch.runItems',
              key: 'runItems',
              reason: 'costPatch.runItems doit être une liste JSON.',
            ),
          );
        } else {
          final rawRuns = costPatch['runItems'] as List;
          var count = 0;
          for (var i = 0; i < rawRuns.length; i++) {
            final item = rawRuns[i];
            try {
              final res = apply(
                current,
                costPatch: <String, Object?>{
                  'runItems': <Object?>[item],
                },
              );
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'costPatch.runItems',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count poste(s) Run OPEX');
        }
      }

      if (costPatch['removeRiskItemIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            costPatch: <String, Object?>{
              'removeRiskItemIds': costPatch['removeRiskItemIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression risque(s)');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'costPatch.removeRiskItemIds',
              key: 'removeRiskItemIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (costPatch['riskItems'] != null) {
        if (costPatch['riskItems'] is! List) {
          rejected.add(
            const SpecPatchRejectedEntry(
              section: 'costPatch.riskItems',
              key: 'riskItems',
              reason: 'costPatch.riskItems doit être une liste JSON.',
            ),
          );
        } else {
          final rawRisks = costPatch['riskItems'] as List;
          var count = 0;
          for (var i = 0; i < rawRisks.length; i++) {
            final item = rawRisks[i];
            try {
              final res = apply(
                current,
                costPatch: <String, Object?>{
                  'riskItems': <Object?>[item],
                },
              );
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'costPatch.riskItems',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count risque(s) EMV');
        }
      }

      if (costPatch['coherenceIssues'] != null) {
        if (costPatch['coherenceIssues'] is! List) {
          rejected.add(
            const SpecPatchRejectedEntry(
              section: 'costPatch.coherenceIssues',
              key: 'coherenceIssues',
              reason: 'costPatch.coherenceIssues doit être une liste JSON.',
            ),
          );
        } else {
          final rawIssues = costPatch['coherenceIssues'] as List;
          final validIssues = <Object?>[];
          for (var i = 0; i < rawIssues.length; i++) {
            final item = rawIssues[i];
            try {
              CostCoherenceIssue.fromJson(item);
              validIssues.add(item);
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'costPatch.coherenceIssues',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (validIssues.isNotEmpty) {
            try {
              final res = apply(
                current,
                costPatch: <String, Object?>{'coherenceIssues': validIssues},
              );
              current = res.project;
              appliedSummaries.add(
                '${validIssues.length} diagnostic(s) Coûts IA',
              );
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'costPatch.coherenceIssues',
                  key: 'audit',
                  reason: _reasonOf(e),
                ),
              );
            }
          }
        }
      }
    }

    if (specPatch != null && specPatch.isNotEmpty) {
      if (specPatch['businessObjects'] is List) {
        final rawObjects = specPatch['businessObjects'] as List;
        var count = 0;
        for (var i = 0; i < rawObjects.length; i++) {
          final item = rawObjects[i];
          try {
            final localSummaries = <String>[];
            current = UxPatchApplier.applyAdditiveSpecPatch(
              current,
              <String, Object?>{
                'businessObjects': <Object?>[item],
              },
              localSummaries,
            );
            if (localSummaries.isNotEmpty) count++;
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'specPatch.businessObjects',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) {
          appliedSummaries.add('$count objet(s) métier(s) enrichi(s)/ajouté(s)');
        }
      }

      if (specPatch['businessRules'] is List) {
        final rawRules = specPatch['businessRules'] as List;
        var count = 0;
        for (var i = 0; i < rawRules.length; i++) {
          final item = rawRules[i];
          try {
            final localSummaries = <String>[];
            current = UxPatchApplier.applyAdditiveSpecPatch(
              current,
              <String, Object?>{
                'businessRules': <Object?>[item],
              },
              localSummaries,
            );
            if (localSummaries.isNotEmpty) count++;
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'specPatch.businessRules',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) {
          appliedSummaries.add('$count règle(s) RG enrichie(s)/ajoutée(s)');
        }
      }
    }

    return CostPartialPatchResult(
      project: current,
      summary: appliedSummaries.join(', '),
      rejectedEntries: rejected,
    );
  }

  /// Récupère un checkpoint partiel sain depuis une réponse FinOps échouée ou tronquée,
  /// compatible avec [SpecDeltaRecovery.buildDeltaRetryPrompt].
  static SpecSalvageOutcome salvageFailedAttempt({
    required SpecForgeProject workingProject,
    required String rawResponse,
    Map<String, Object?>? decodedCostPatch,
    Map<String, Object?>? decodedSpecPatch,
  }) {
    final wasTruncated = decodedCostPatch == null && decodedSpecPatch == null;
    final candidateCost =
        decodedCostPatch ??
        SpecDeltaRecovery.trySalvageObjectField(rawResponse, 'costPatch');
    final candidateSpec =
        decodedSpecPatch ??
        SpecDeltaRecovery.trySalvageObjectField(rawResponse, 'specPatch');

    if ((candidateCost == null || candidateCost.isEmpty) &&
        (candidateSpec == null || candidateSpec.isEmpty)) {
      return SpecSalvageOutcome.none(
        workingProject,
        wasTruncated: wasTruncated,
      );
    }

    final partial = applyPartial(
      workingProject,
      costPatch: candidateCost,
      specPatch: candidateSpec,
    );
    final hasCheckpoint = partial.project != workingProject;
    return SpecSalvageOutcome(
      hasCheckpoint: hasCheckpoint,
      checkpointProject: partial.project,
      appliedSummary: partial.summary,
      rejectedEntries: partial.rejectedEntries,
      wasTruncated: wasTruncated,
    );
  }

  static CostForgeSpec _applyCostPatch(
    CostForgeSpec current,
    Map<String, Object?> costPatch,
    List<String> summaries,
  ) {
    var nextCost = current;

    if (costPatch['currency'] != null) {
      final rawCurrency = costPatch['currency'];
      if (rawCurrency is! String || rawCurrency.trim().isEmpty) {
        throw const FormatException(
          'costPatch.currency doit être une chaîne non vide ("EUR", "USD", "CHF", "CAD", "GBP").',
        );
      }
      final nextCurrency = CostCurrency.fromJson(rawCurrency);
      if (nextCurrency != nextCost.currency) {
        nextCost = nextCost.copyWith(currency: nextCurrency);
        summaries.add('devise (${nextCurrency.code})');
      }
    }

    if (costPatch['hoursPerDay'] != null) {
      final hours = _parseStrictDouble(
        costPatch['hoursPerDay'],
        'costPatch.hoursPerDay',
      );
      if (hours <= 0.0 || hours > 24.0) {
        throw const FormatException(
          'costPatch.hoursPerDay doit être compris dans ]0, 24].',
        );
      }
      if (hours != nextCost.hoursPerDay) {
        nextCost = nextCost.copyWith(hoursPerDay: hours);
        summaries.add('durée journalière (${hours}h/j)');
      }
    }

    if (costPatch['deliveryMode'] != null) {
      final rawMode = costPatch['deliveryMode'];
      if (rawMode is! String || rawMode.trim().isEmpty) {
        throw const FormatException(
          'costPatch.deliveryMode doit être une chaîne non vide.',
        );
      }
      final nextMode = CostDeliveryMode.fromJson(rawMode);
      if (nextMode != nextCost.deliveryMode) {
        nextCost = nextCost.copyWith(deliveryMode: nextMode);
        summaries.add('mode delivery (${nextMode.label})');
      }
    }

    if (costPatch['targetUsersCount'] != null) {
      final targetUsers = _parseStrictInt(
        costPatch['targetUsersCount'],
        'costPatch.targetUsersCount',
      );
      if (targetUsers < 1) {
        throw const FormatException(
          'costPatch.targetUsersCount doit être supérieur ou égal à 1.',
        );
      }
      if (targetUsers != nextCost.targetUsersCount) {
        nextCost = nextCost.copyWith(targetUsersCount: targetUsers);
        summaries.add('cible utilisateurs ($targetUsers)');
      }
    }

    if (costPatch['assumptionsNotes'] != null) {
      final rawNotes = costPatch['assumptionsNotes'];
      if (rawNotes is! String) {
        throw const FormatException(
          'costPatch.assumptionsNotes doit être une chaîne de caractères.',
        );
      }
      final trimmed = rawNotes.trim();
      if (trimmed != nextCost.assumptionsNotes) {
        nextCost = nextCost.copyWith(assumptionsNotes: trimmed);
        summaries.add('hypothèses budgétaires');
      }
    }

    if (costPatch['profiles'] != null || costPatch['removeProfileIds'] != null) {
      if (costPatch['profiles'] != null && costPatch['profiles'] is! List) {
        throw const FormatException(
          'costPatch.profiles doit être une liste JSON.',
        );
      }
      if (costPatch['removeProfileIds'] != null &&
          costPatch['removeProfileIds'] is! List) {
        throw const FormatException(
          'costPatch.removeProfileIds doit être une liste JSON.',
        );
      }
      final removeSet = _lowerStringSet(costPatch['removeProfileIds']);
      final mergedProfiles = <CostProfileRate>[
        for (final p in nextCost.profiles)
          if (!_matchesRemove(p.id, p.code, 'PRF', removeSet)) p,
      ];

      if (costPatch['profiles'] is List) {
        for (final rawItem in costPatch['profiles'] as List) {
          if (rawItem is! Map) {
            throw const FormatException(
              'Chaque élément de costPatch.profiles doit être un objet JSON.',
            );
          }
          _checkNonNegativeField(
            rawItem,
            const <String>['internalDailyRate', 'internalRate', 'dailyRate'],
            'CostProfileRate.internalDailyRate',
          );
          _checkNonNegativeField(
            rawItem,
            const <String>['externalDailyRate', 'externalRate', 'dailyRate'],
            'CostProfileRate.externalDailyRate',
          );
          final incoming = CostProfileRate.fromJson(rawItem);
          final hasExplicitId =
              (rawItem['id'] as String?)?.trim().isNotEmpty == true;
          final hasExplicitCode =
              (rawItem['code'] as String?)?.trim().isNotEmpty == true;
          if (_matchesRemove(
            incoming.id,
            hasExplicitCode ? incoming.code : '',
            'PRF',
            removeSet,
          )) {
            continue;
          }

          var idx = -1;
          if (hasExplicitId) {
            idx = mergedProfiles.indexWhere(
              (e) => e.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }
          if (idx < 0 &&
              hasExplicitCode &&
              _hasSpecificCode(incoming.code, 'PRF')) {
            idx = mergedProfiles.indexWhere(
              (e) => e.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }
          if (idx < 0 && !hasExplicitId && !hasExplicitCode) {
            idx = mergedProfiles.indexWhere(
              (e) => e.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }

          if (idx >= 0) {
            final prev = mergedProfiles[idx];
            final hasName =
                _hasNonEmptyString(rawItem, 'name') ||
                _hasNonEmptyString(rawItem, 'title') ||
                _hasNonEmptyString(rawItem, 'role');
            final hasInternal =
                rawItem.containsKey('internalDailyRate') ||
                rawItem.containsKey('internalRate') ||
                rawItem.containsKey('dailyRate');
            final hasExternal =
                rawItem.containsKey('externalDailyRate') ||
                rawItem.containsKey('externalRate') ||
                rawItem.containsKey('dailyRate');
            final updated = CostProfileRate(
              id: hasExplicitId ? incoming.id : prev.id,
              code: hasExplicitCode ? incoming.code : prev.code,
              name: hasName ? incoming.name : prev.name,
              seniority: _hasNonEmptyString(rawItem, 'seniority')
                  ? incoming.seniority
                  : prev.seniority,
              discipline: rawItem.containsKey('discipline')
                  ? incoming.discipline
                  : prev.discipline,
              internalDailyRate: hasInternal
                  ? incoming.internalDailyRate
                  : prev.internalDailyRate,
              externalDailyRate: hasExternal
                  ? incoming.externalDailyRate
                  : prev.externalDailyRate,
            );
            updated.validate();
            mergedProfiles[idx] = updated;
          } else {
            var candidate = hasExplicitCode
                ? incoming
                : incoming.copyWith(
                    code: _nextSequentialCode(
                      mergedProfiles.map((p) => p.code),
                      'PRF',
                    ),
                  );
            final usedIds = <String>{
              for (final p in mergedProfiles) p.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            candidate.validate();
            mergedProfiles.add(candidate);
          }
        }
      }

      if (!listEquals(mergedProfiles, nextCost.profiles)) {
        nextCost = nextCost.copyWith(profiles: mergedProfiles);
        summaries.add('${mergedProfiles.length} profil(s) TJM');
      }
    }

    if (costPatch['tshirtPresets'] != null) {
      if (costPatch['tshirtPresets'] is! List) {
        throw const FormatException(
          'costPatch.tshirtPresets doit être une liste JSON.',
        );
      }
      final bySize = <CostTShirtSize, TShirtEffortPreset>{
        for (final p in nextCost.tshirtPresets) p.size: p,
      };
      for (final rawItem in costPatch['tshirtPresets'] as List) {
        if (rawItem is! Map) {
          throw const FormatException(
            'Chaque élément de costPatch.tshirtPresets doit être un objet JSON.',
          );
        }
        final rawSizeVal = rawItem['size'] ?? rawItem['tshirtSize'];
        if (rawSizeVal == null) {
          throw const FormatException(
            'TShirtEffortPreset.size est requis.',
          );
        }
        final resolvedSize = CostTShirtSize.fromJson(rawSizeVal);
        if (resolvedSize == CostTShirtSize.custom) {
          throw const FormatException(
            'TShirtEffortPreset.size ne peut pas être custom.',
          );
        }
        _checkNonNegativeField(
          rawItem,
          const <String>['optimisticDays'],
          'TShirtEffortPreset.optimisticDays',
        );
        _checkNonNegativeField(
          rawItem,
          const <String>['mostLikelyDays'],
          'TShirtEffortPreset.mostLikelyDays',
        );
        _checkNonNegativeField(
          rawItem,
          const <String>['pessimisticDays'],
          'TShirtEffortPreset.pessimisticDays',
        );
        final prev = bySize[resolvedSize] ?? nextCost.presetFor(resolvedSize);
        final values = <double>[
          rawItem['optimisticDays'] != null
              ? _parseStrictDouble(
                  rawItem['optimisticDays'],
                  'TShirtEffortPreset.optimisticDays',
                )
              : prev.optimisticDays,
          rawItem['mostLikelyDays'] != null
              ? _parseStrictDouble(
                  rawItem['mostLikelyDays'],
                  'TShirtEffortPreset.mostLikelyDays',
                )
              : prev.mostLikelyDays,
          rawItem['pessimisticDays'] != null
              ? _parseStrictDouble(
                  rawItem['pessimisticDays'],
                  'TShirtEffortPreset.pessimisticDays',
                )
              : prev.pessimisticDays,
        ]..sort();
        final preset = TShirtEffortPreset(
          size: resolvedSize,
          optimisticDays: values[0],
          mostLikelyDays: values[1],
          pessimisticDays: values[2],
        );
        preset.validate();
        bySize[resolvedSize] = preset;
      }

      final mergedPresets = <TShirtEffortPreset>[
        for (final size in CostTShirtSize.values)
          if (size != CostTShirtSize.custom && bySize.containsKey(size))
            bySize[size]!,
      ];
      if (!listEquals(mergedPresets, nextCost.tshirtPresets)) {
        nextCost = nextCost.copyWith(tshirtPresets: mergedPresets);
        summaries.add('calibres T-shirt');
      }
    }

    if (costPatch['transverseRatios'] != null) {
      final rawRatios = costPatch['transverseRatios'];
      if (rawRatios is! Map) {
        throw const FormatException(
          'costPatch.transverseRatios doit être un objet JSON.',
        );
      }
      final prev = nextCost.transverseRatios;
      final updatedRatios = TransverseRatioSettings(
        projectManagementPct: rawRatios['projectManagementPct'] != null
            ? _parseBoundedDouble(
                rawRatios['projectManagementPct'],
                0.0,
                200.0,
                'transverseRatios.projectManagementPct',
              )
            : prev.projectManagementPct,
        architectureDevOpsPct: rawRatios['architectureDevOpsPct'] != null
            ? _parseBoundedDouble(
                rawRatios['architectureDevOpsPct'],
                0.0,
                200.0,
                'transverseRatios.architectureDevOpsPct',
              )
            : prev.architectureDevOpsPct,
        transverseQaPct: rawRatios['transverseQaPct'] != null
            ? _parseBoundedDouble(
                rawRatios['transverseQaPct'],
                0.0,
                200.0,
                'transverseRatios.transverseQaPct',
              )
            : prev.transverseQaPct,
        contingencyPct: rawRatios['contingencyPct'] != null
            ? _parseBoundedDouble(
                rawRatios['contingencyPct'],
                0.0,
                200.0,
                'transverseRatios.contingencyPct',
              )
            : prev.contingencyPct,
      );
      updatedRatios.validate();
      if (updatedRatios != prev) {
        nextCost = nextCost.copyWith(transverseRatios: updatedRatios);
        summaries.add('ratios transverses');
      }
    }

    if (costPatch['aiProductivity'] != null) {
      final rawAi = costPatch['aiProductivity'];
      if (rawAi is! Map) {
        throw const FormatException(
          'costPatch.aiProductivity doit être un objet JSON.',
        );
      }
      final prev = nextCost.aiProductivity;
      final rawEnabled = rawAi['enabled'];
      if (rawEnabled != null && rawEnabled is! bool) {
        throw const FormatException(
          'aiProductivity.enabled doit être un booléen.',
        );
      }
      final updatedAi = AiProductivitySettings(
        enabled: rawEnabled is bool ? rawEnabled : prev.enabled,
        backendGainPct: rawAi['backendGainPct'] != null
            ? _parseBoundedDouble(
                rawAi['backendGainPct'],
                0.0,
                80.0,
                'aiProductivity.backendGainPct',
              )
            : prev.backendGainPct,
        frontendUxGainPct: rawAi['frontendUxGainPct'] != null
            ? _parseBoundedDouble(
                rawAi['frontendUxGainPct'],
                0.0,
                80.0,
                'aiProductivity.frontendUxGainPct',
              )
            : prev.frontendUxGainPct,
        dataIntegrationGainPct: rawAi['dataIntegrationGainPct'] != null
            ? _parseBoundedDouble(
                rawAi['dataIntegrationGainPct'],
                0.0,
                80.0,
                'aiProductivity.dataIntegrationGainPct',
              )
            : prev.dataIntegrationGainPct,
        qaTestingGainPct: rawAi['qaTestingGainPct'] != null
            ? _parseBoundedDouble(
                rawAi['qaTestingGainPct'],
                0.0,
                80.0,
                'aiProductivity.qaTestingGainPct',
              )
            : prev.qaTestingGainPct,
        devSecOpsGainPct: rawAi['devSecOpsGainPct'] != null
            ? _parseBoundedDouble(
                rawAi['devSecOpsGainPct'],
                0.0,
                80.0,
                'aiProductivity.devSecOpsGainPct',
              )
            : prev.devSecOpsGainPct,
        pmSpecsGainPct: rawAi['pmSpecsGainPct'] != null
            ? _parseBoundedDouble(
                rawAi['pmSpecsGainPct'],
                0.0,
                80.0,
                'aiProductivity.pmSpecsGainPct',
              )
            : prev.pmSpecsGainPct,
      );
      updatedAi.validate();
      if (updatedAi != prev) {
        nextCost = nextCost.copyWith(aiProductivity: updatedAi);
        summaries.add('productivité IA');
      }
    }

    if (costPatch['wbsItems'] != null || costPatch['removeWbsItemIds'] != null) {
      if (costPatch['wbsItems'] != null && costPatch['wbsItems'] is! List) {
        throw const FormatException(
          'costPatch.wbsItems doit être une liste JSON.',
        );
      }
      if (costPatch['removeWbsItemIds'] != null &&
          costPatch['removeWbsItemIds'] is! List) {
        throw const FormatException(
          'costPatch.removeWbsItemIds doit être une liste JSON.',
        );
      }
      final removeSet = _lowerStringSet(costPatch['removeWbsItemIds']);
      final mergedWbs = <CostWbsItemSpec>[
        for (final w in nextCost.wbsItems)
          if (!_matchesRemove(w.id, w.code, 'WBS', removeSet)) w,
      ];

      if (costPatch['wbsItems'] is List) {
        for (final rawItem in costPatch['wbsItems'] as List) {
          if (rawItem is! Map) {
            throw const FormatException(
              'Chaque élément de costPatch.wbsItems doit être un objet JSON.',
            );
          }
          _checkNonNegativeField(
            rawItem,
            const <String>[
              'optimisticDays',
              'optimistic',
              'mostLikelyDays',
              'mostLikely',
              'nominalDays',
              'pessimisticDays',
              'pessimistic',
              'days',
              'directDays',
              'manDays',
            ],
            'CostWbsItemSpec.days',
          );
          final incoming = CostWbsItemSpec.fromJson(rawItem);
          final hasExplicitId =
              (rawItem['id'] as String?)?.trim().isNotEmpty == true;
          final hasExplicitCode =
              (rawItem['code'] as String?)?.trim().isNotEmpty == true;
          if (_matchesRemove(
            incoming.id,
            hasExplicitCode ? incoming.code : '',
            'WBS',
            removeSet,
          )) {
            continue;
          }

          var idx = -1;
          if (hasExplicitId) {
            idx = mergedWbs.indexWhere(
              (w) => w.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }
          if (idx < 0 && hasExplicitCode) {
            idx = mergedWbs.indexWhere(
              (w) => w.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }
          if (idx < 0 && !hasExplicitId && !hasExplicitCode) {
            idx = mergedWbs.indexWhere(
              (w) => w.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }

          final hasExplicitSize =
              rawItem.containsKey('tshirtSize') || rawItem.containsKey('size');
          final hasExplicitDirect =
              rawItem.containsKey('days') ||
              rawItem.containsKey('directDays') ||
              rawItem.containsKey('manDays');
          final hasExplicitO =
              rawItem.containsKey('optimisticDays') ||
              rawItem.containsKey('optimistic');
          final hasExplicitM =
              rawItem.containsKey('mostLikelyDays') ||
              rawItem.containsKey('mostLikely') ||
              rawItem.containsKey('nominalDays');
          final hasExplicitP =
              rawItem.containsKey('pessimisticDays') ||
              rawItem.containsKey('pessimistic');
          final hasAnyExplicitEffort =
              hasExplicitDirect || hasExplicitO || hasExplicitM || hasExplicitP;
          final hasExplicitProfile = _hasNonEmptyString(rawItem, 'profileId');

          if (idx >= 0) {
            final prev = mergedWbs[idx];
            final hasTitle =
                _hasNonEmptyString(rawItem, 'title') ||
                _hasNonEmptyString(rawItem, 'name') ||
                _hasNonEmptyString(rawItem, 'label');
            final nextSize = hasExplicitSize
                ? incoming.tshirtSize
                : (hasExplicitDirect && !hasExplicitO && !hasExplicitP
                      ? CostTShirtSize.custom
                      : prev.tshirtSize);

            double nextO = prev.optimisticDays;
            double nextM = prev.mostLikelyDays;
            double nextP = prev.pessimisticDays;
            if (hasAnyExplicitEffort) {
              if (hasExplicitDirect &&
                  !hasExplicitO &&
                  !hasExplicitM &&
                  !hasExplicitP) {
                nextO = incoming.optimisticDays;
                nextM = incoming.mostLikelyDays;
                nextP = incoming.pessimisticDays;
              } else {
                final bounds = <double>[
                  hasExplicitO ? incoming.optimisticDays : prev.optimisticDays,
                  hasExplicitM ? incoming.mostLikelyDays : prev.mostLikelyDays,
                  hasExplicitP
                      ? incoming.pessimisticDays
                      : prev.pessimisticDays,
                ]..sort();
                nextO = bounds[0];
                nextM = bounds[1];
                nextP = bounds[2];
              }
            } else if (hasExplicitSize && nextSize != CostTShirtSize.custom) {
              final preset = nextCost.presetFor(nextSize);
              nextO = preset.optimisticDays;
              nextM = preset.mostLikelyDays;
              nextP = preset.pessimisticDays;
            }

            final updated = CostWbsItemSpec(
              id: hasExplicitId ? incoming.id : prev.id,
              code: hasExplicitCode ? incoming.code : prev.code,
              title: hasTitle ? incoming.title : prev.title,
              description: rawItem.containsKey('description')
                  ? incoming.description
                  : prev.description,
              discipline: rawItem.containsKey('discipline')
                  ? incoming.discipline
                  : prev.discipline,
              priority: rawItem.containsKey('priority')
                  ? incoming.priority
                  : prev.priority,
              profileId: hasExplicitProfile
                  ? incoming.profileId
                  : (rawItem.containsKey('discipline')
                        ? nextCost
                              .resolveProfileForDiscipline(incoming.discipline)
                              .id
                        : prev.profileId),
              tshirtSize: nextSize,
              optimisticDays: nextO,
              mostLikelyDays: nextM,
              pessimisticDays: nextP,
              aiEligible: rawItem['aiEligible'] is bool
                  ? incoming.aiEligible
                  : prev.aiEligible,
              moduleId: rawItem.containsKey('moduleId')
                  ? incoming.moduleId
                  : prev.moduleId,
              requirementIds: rawItem.containsKey('requirementIds')
                  ? incoming.requirementIds
                  : prev.requirementIds,
              businessObjectIds: rawItem.containsKey('businessObjectIds')
                  ? incoming.businessObjectIds
                  : prev.businessObjectIds,
              uxScreenIds: rawItem.containsKey('uxScreenIds')
                  ? incoming.uxScreenIds
                  : prev.uxScreenIds,
              qaFeatureIds: rawItem.containsKey('qaFeatureIds')
                  ? incoming.qaFeatureIds
                  : prev.qaFeatureIds,
              tddSuiteIds: rawItem.containsKey('tddSuiteIds')
                  ? incoming.tddSuiteIds
                  : prev.tddSuiteIds,
              origin: _hasNonEmptyString(rawItem, 'origin')
                  ? incoming.origin
                  : prev.origin,
            );
            updated.validate();
            mergedWbs[idx] = updated;
          } else {
            var candidate = incoming;
            if (!hasAnyExplicitEffort &&
                candidate.tshirtSize != CostTShirtSize.custom) {
              candidate = candidate.withTShirtPreset(
                nextCost.presetFor(candidate.tshirtSize),
              );
            }
            if (!hasExplicitProfile) {
              candidate = candidate.copyWith(
                profileId: nextCost
                    .resolveProfileForDiscipline(candidate.discipline)
                    .id,
              );
            }
            if (!hasExplicitCode) {
              candidate = candidate.copyWith(
                code: _nextSequentialCode(
                  mergedWbs.map((w) => w.code),
                  'WBS',
                ),
              );
            }
            if (!_hasNonEmptyString(rawItem, 'origin')) {
              candidate = candidate.copyWith(origin: 'ai');
            }
            final usedIds = <String>{
              for (final w in mergedWbs) w.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            candidate.validate();
            mergedWbs.add(candidate);
          }
        }
      }

      if (!listEquals(mergedWbs, nextCost.wbsItems)) {
        nextCost = nextCost.copyWith(wbsItems: mergedWbs);
        summaries.add('${mergedWbs.length} lot(s) WBS');
      }
    }

    if (costPatch['runItems'] != null || costPatch['removeRunItemIds'] != null) {
      if (costPatch['runItems'] != null && costPatch['runItems'] is! List) {
        throw const FormatException(
          'costPatch.runItems doit être une liste JSON.',
        );
      }
      if (costPatch['removeRunItemIds'] != null &&
          costPatch['removeRunItemIds'] is! List) {
        throw const FormatException(
          'costPatch.removeRunItemIds doit être une liste JSON.',
        );
      }
      final removeSet = _lowerStringSet(costPatch['removeRunItemIds']);
      final mergedRuns = <CostRunItemSpec>[
        for (final r in nextCost.runItems)
          if (!_matchesRemove(r.id, r.code, 'RUN', removeSet)) r,
      ];

      if (costPatch['runItems'] is List) {
        for (final rawItem in costPatch['runItems'] as List) {
          if (rawItem is! Map) {
            throw const FormatException(
              'Chaque élément de costPatch.runItems doit être un objet JSON.',
            );
          }
          _checkNonNegativeField(
            rawItem,
            const <String>['unitCost', 'cost'],
            'CostRunItemSpec.unitCost',
          );
          _checkNonNegativeField(
            rawItem,
            const <String>['quantity', 'qty'],
            'CostRunItemSpec.quantity',
          );
          _checkBoundedField(
            rawItem,
            const <String>['annualGrowthPct', 'growthPct'],
            -50.0,
            500.0,
            'CostRunItemSpec.annualGrowthPct',
          );
          final incoming = CostRunItemSpec.fromJson(rawItem);
          final hasExplicitId =
              (rawItem['id'] as String?)?.trim().isNotEmpty == true;
          final hasExplicitCode =
              (rawItem['code'] as String?)?.trim().isNotEmpty == true;
          if (_matchesRemove(
            incoming.id,
            hasExplicitCode ? incoming.code : '',
            'RUN',
            removeSet,
          )) {
            continue;
          }

          var idx = -1;
          if (hasExplicitId) {
            idx = mergedRuns.indexWhere(
              (r) => r.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }
          if (idx < 0 && hasExplicitCode) {
            idx = mergedRuns.indexWhere(
              (r) => r.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }
          if (idx < 0 && !hasExplicitId && !hasExplicitCode) {
            idx = mergedRuns.indexWhere(
              (r) => r.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }

          if (idx >= 0) {
            final prev = mergedRuns[idx];
            final hasName =
                _hasNonEmptyString(rawItem, 'name') ||
                _hasNonEmptyString(rawItem, 'title') ||
                _hasNonEmptyString(rawItem, 'label');
            final updated = CostRunItemSpec(
              id: hasExplicitId ? incoming.id : prev.id,
              code: hasExplicitCode ? incoming.code : prev.code,
              name: hasName ? incoming.name : prev.name,
              description: rawItem.containsKey('description')
                  ? incoming.description
                  : prev.description,
              category: rawItem.containsKey('category')
                  ? incoming.category
                  : prev.category,
              environment: rawItem.containsKey('environment')
                  ? incoming.environment
                  : prev.environment,
              billingCycle: rawItem.containsKey('billingCycle')
                  ? incoming.billingCycle
                  : prev.billingCycle,
              unitCost:
                  (rawItem.containsKey('unitCost') ||
                      rawItem.containsKey('cost'))
                  ? incoming.unitCost
                  : prev.unitCost,
              quantity:
                  (rawItem.containsKey('quantity') ||
                      rawItem.containsKey('qty'))
                  ? incoming.quantity
                  : prev.quantity,
              annualGrowthPct:
                  (rawItem.containsKey('annualGrowthPct') ||
                      rawItem.containsKey('growthPct'))
                  ? incoming.annualGrowthPct
                  : prev.annualGrowthPct,
              enabled: rawItem['enabled'] is bool
                  ? incoming.enabled
                  : prev.enabled,
            );
            updated.validate();
            mergedRuns[idx] = updated;
          } else {
            var candidate = hasExplicitCode
                ? incoming
                : incoming.copyWith(
                    code: _nextSequentialCode(
                      mergedRuns.map((r) => r.code),
                      'RUN',
                    ),
                  );
            final usedIds = <String>{
              for (final r in mergedRuns) r.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            candidate.validate();
            mergedRuns.add(candidate);
          }
        }
      }

      if (!listEquals(mergedRuns, nextCost.runItems)) {
        nextCost = nextCost.copyWith(runItems: mergedRuns);
        summaries.add('${mergedRuns.length} poste(s) Run OPEX');
      }
    }

    if (costPatch['riskItems'] != null ||
        costPatch['removeRiskItemIds'] != null) {
      if (costPatch['riskItems'] != null && costPatch['riskItems'] is! List) {
        throw const FormatException(
          'costPatch.riskItems doit être une liste JSON.',
        );
      }
      if (costPatch['removeRiskItemIds'] != null &&
          costPatch['removeRiskItemIds'] is! List) {
        throw const FormatException(
          'costPatch.removeRiskItemIds doit être une liste JSON.',
        );
      }
      final removeSet = _lowerStringSet(costPatch['removeRiskItemIds']);
      final mergedRisks = <CostRiskItemSpec>[
        for (final r in nextCost.riskItems)
          if (!_matchesRemove(r.id, r.code, 'RSK', removeSet)) r,
      ];

      if (costPatch['riskItems'] is List) {
        for (final rawItem in costPatch['riskItems'] as List) {
          if (rawItem is! Map) {
            throw const FormatException(
              'Chaque élément de costPatch.riskItems doit être un objet JSON.',
            );
          }
          _checkBoundedField(
            rawItem,
            const <String>['probabilityPct', 'probability'],
            0.0,
            100.0,
            'CostRiskItemSpec.probabilityPct',
          );
          _checkNonNegativeField(
            rawItem,
            const <String>['impactDays', 'days'],
            'CostRiskItemSpec.impactDays',
          );
          _checkNonNegativeField(
            rawItem,
            const <String>['fixedCostImpact', 'fixedCost', 'costImpact'],
            'CostRiskItemSpec.fixedCostImpact',
          );
          final incoming = CostRiskItemSpec.fromJson(rawItem);
          final hasExplicitId =
              (rawItem['id'] as String?)?.trim().isNotEmpty == true;
          final hasExplicitCode =
              (rawItem['code'] as String?)?.trim().isNotEmpty == true;
          final hasExplicitProfile = _hasNonEmptyString(rawItem, 'profileId');
          if (_matchesRemove(
            incoming.id,
            hasExplicitCode ? incoming.code : '',
            'RSK',
            removeSet,
          )) {
            continue;
          }

          var idx = -1;
          if (hasExplicitId) {
            idx = mergedRisks.indexWhere(
              (r) => r.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }
          if (idx < 0 && hasExplicitCode) {
            idx = mergedRisks.indexWhere(
              (r) => r.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }
          if (idx < 0 && !hasExplicitId && !hasExplicitCode) {
            idx = mergedRisks.indexWhere(
              (r) => r.id.toLowerCase() == incoming.id.toLowerCase(),
            );
          }

          if (idx >= 0) {
            final prev = mergedRisks[idx];
            final hasTitle =
                _hasNonEmptyString(rawItem, 'title') ||
                _hasNonEmptyString(rawItem, 'name') ||
                _hasNonEmptyString(rawItem, 'label');
            final updated = CostRiskItemSpec(
              id: hasExplicitId ? incoming.id : prev.id,
              code: hasExplicitCode ? incoming.code : prev.code,
              title: hasTitle ? incoming.title : prev.title,
              description: rawItem.containsKey('description')
                  ? incoming.description
                  : prev.description,
              probabilityPct:
                  (rawItem.containsKey('probabilityPct') ||
                      rawItem.containsKey('probability'))
                  ? incoming.probabilityPct
                  : prev.probabilityPct,
              impactDays:
                  (rawItem.containsKey('impactDays') ||
                      rawItem.containsKey('days'))
                  ? incoming.impactDays
                  : prev.impactDays,
              fixedCostImpact:
                  (rawItem.containsKey('fixedCostImpact') ||
                      rawItem.containsKey('fixedCost') ||
                      rawItem.containsKey('costImpact'))
                  ? incoming.fixedCostImpact
                  : prev.fixedCostImpact,
              profileId: hasExplicitProfile
                  ? incoming.profileId
                  : prev.profileId,
              mitigation: rawItem.containsKey('mitigation')
                  ? incoming.mitigation
                  : prev.mitigation,
              linkedHotspotId: rawItem.containsKey('linkedHotspotId')
                  ? incoming.linkedHotspotId
                  : prev.linkedHotspotId,
              linkedRequirementIds: rawItem.containsKey('linkedRequirementIds')
                  ? incoming.linkedRequirementIds
                  : prev.linkedRequirementIds,
            );
            updated.validate();
            mergedRisks[idx] = updated;
          } else {
            var candidate = incoming;
            if (!hasExplicitProfile) {
              candidate = candidate.copyWith(
                profileId: nextCost
                    .resolveProfileForDiscipline(CostDiscipline.backend)
                    .id,
              );
            }
            if (!hasExplicitCode) {
              candidate = candidate.copyWith(
                code: _nextSequentialCode(
                  mergedRisks.map((r) => r.code),
                  'RSK',
                ),
              );
            }
            final usedIds = <String>{
              for (final r in mergedRisks) r.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            candidate.validate();
            mergedRisks.add(candidate);
          }
        }
      }

      if (!listEquals(mergedRisks, nextCost.riskItems)) {
        nextCost = nextCost.copyWith(riskItems: mergedRisks);
        summaries.add('${mergedRisks.length} risque(s) EMV');
      }
    }

    if (costPatch['coherenceIssues'] != null) {
      if (costPatch['coherenceIssues'] is! List) {
        throw const FormatException(
          'costPatch.coherenceIssues doit être une liste JSON.',
        );
      }
      final localIssues = nextCost.coherenceIssues
          .where((i) => i.source == 'local')
          .toList();
      final seenIds = <String>{for (final i in localIssues) i.id};
      final aiIssues = <CostCoherenceIssue>[];
      for (final item in costPatch['coherenceIssues'] as List) {
        var issue = CostCoherenceIssue.fromJson(item).copyWith(source: 'ai');
        if (!seenIds.add(issue.id)) {
          var suffix = 2;
          while (!seenIds.add('${issue.id}_$suffix')) {
            suffix++;
          }
          issue = issue.copyWith(id: '${issue.id}_$suffix');
        }
        aiIssues.add(issue);
      }
      final combined = <CostCoherenceIssue>[...localIssues, ...aiIssues];
      if (!listEquals(combined, nextCost.coherenceIssues)) {
        nextCost = nextCost.copyWith(coherenceIssues: combined);
      }
      summaries.add('${aiIssues.length} diagnostic(s) Coûts IA');
    }

    return nextCost;
  }

  static String _nextSequentialCode(
    Iterable<String> existingCodes,
    String prefix,
  ) {
    final pattern = RegExp(
      '^${RegExp.escape(prefix)}-(\\d+)\$',
      caseSensitive: false,
    );
    var maxNum = 0;
    for (final code in existingCodes) {
      final match = pattern.firstMatch(code.trim());
      if (match != null) {
        final value = int.tryParse(match.group(1)!) ?? 0;
        if (value > maxNum) maxNum = value;
      }
    }
    final next = (maxNum + 1).toString().padLeft(3, '0');
    return '$prefix-$next';
  }

  static bool _hasNonEmptyString(Map<Object?, Object?> map, String key) {
    final value = map[key];
    return value is String && value.trim().isNotEmpty;
  }

  static double _parseStrictDouble(Object? raw, String fieldName) {
    if (raw is num) {
      final v = raw.toDouble();
      if (v.isFinite) return v;
    } else if (raw is String) {
      final v = double.tryParse(raw.trim().replaceAll(',', '.'));
      if (v != null && v.isFinite) return v;
    }
    throw FormatException('$fieldName doit être un nombre valide.');
  }

  static int _parseStrictInt(Object? raw, String fieldName) {
    if (raw is int) return raw;
    if (raw is num && raw.isFinite) return raw.round();
    if (raw is String) {
      final v = int.tryParse(raw.trim());
      if (v != null) return v;
    }
    throw FormatException('$fieldName doit être un entier valide.');
  }

  static double _parseBoundedDouble(
    Object? raw,
    double min,
    double max,
    String fieldName,
  ) {
    final v = _parseStrictDouble(raw, fieldName);
    if (v < min || v > max) {
      throw FormatException(
        '$fieldName doit être compris dans [$min, $max] (reçu : $v).',
      );
    }
    return v;
  }

  static void _checkNonNegativeField(
    Map<Object?, Object?> map,
    List<String> keys,
    String fieldName,
  ) {
    for (final key in keys) {
      if (!map.containsKey(key) || map[key] == null) continue;
      final v = _parseStrictDouble(map[key], fieldName);
      if (v < 0.0) {
        throw FormatException(
          '$fieldName doit être supérieur ou égal à 0 (reçu : $v).',
        );
      }
    }
  }

  static void _checkBoundedField(
    Map<Object?, Object?> map,
    List<String> keys,
    double min,
    double max,
    String fieldName,
  ) {
    for (final key in keys) {
      if (!map.containsKey(key) || map[key] == null) continue;
      _parseBoundedDouble(map[key], min, max, fieldName);
    }
  }

  static bool _hasSpecificCode(String code, String genericPrefix) {
    final trimmed = code.trim();
    return trimmed.isNotEmpty &&
        trimmed.toUpperCase() != genericPrefix.toUpperCase();
  }

  static bool _matchesRemove(
    String id,
    String code,
    String genericPrefix,
    Set<String> removeSet,
  ) {
    if (removeSet.isEmpty) return false;
    if (removeSet.contains(id.toLowerCase())) return true;
    if (_hasSpecificCode(code, genericPrefix) &&
        removeSet.contains(code.toLowerCase())) {
      return true;
    }
    return false;
  }

  static Set<String> _lowerStringSet(Object? raw) {
    if (raw is! List) return const <String>{};
    return <String>{
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim().toLowerCase(),
    };
  }

  static String _labelForItem(Object? raw, {required String fallback}) {
    if (raw is Map) {
      for (final key in const <String>[
        'code',
        'id',
        'size',
        'technicalName',
        'name',
        'title',
      ]) {
        final v = raw[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return fallback;
  }

  static String _reasonOf(Object error) {
    if (error is FormatException) return error.message;
    return error.toString();
  }
}
