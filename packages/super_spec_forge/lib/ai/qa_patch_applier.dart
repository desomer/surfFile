/// Application déterministe et incrémentale des patches QA (`"qaPatch"`) et
/// enrichissement strictement additif du modèle métier (`"specPatch"`) ([QaPatchApplier]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/qa/gherkin_feature_spec.dart';
import '../models/qa/qa_coherence_issue.dart';
import '../models/qa/qa_fixture_spec.dart';
import '../models/qa/qa_forge_spec.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/qa/tdd_suite_spec.dart';
import '../models/spec_forge_project.dart';
import 'spec_delta_recovery.dart';
import 'spec_patch_applier.dart';
import 'ux_patch_applier.dart';

/// Résultat immuable d'application conjointe de `"qaPatch"` et `"specPatch"`.
@immutable
class QaPatchResult {
  /// Construit un résultat d'application de patch QA.
  const QaPatchResult({required this.project, required this.summary});

  /// Projet mis à jour.
  final SpecForgeProject project;

  /// Résumé lisible en français des sections modifiées.
  final String summary;
}

/// Résultat immuable d'une application tolérante par élément conservant les entrées QA/Spec valides.
@immutable
class QaPartialPatchResult {
  /// Construit un résultat d'application partielle QA.
  QaPartialPatchResult({
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

/// Fusionne incrémentalement `"qaPatch"` sur [QaForgeSpec] et applique
/// `"specPatch"` selon le contrat strictement additif (`additive_safe`) via [UxPatchApplier.applyAdditiveSpecPatch].
abstract final class QaPatchApplier {
  /// Applique [qaPatch] et [specPatch] (mode additif sûr) sur [project] sans muter l'existant.
  static QaPatchResult apply(
    SpecForgeProject project, {
    Map<String, Object?>? qaPatch,
    Map<String, Object?>? specPatch,
  }) {
    var next = project;
    final summaries = <String>[];

    if (qaPatch != null && qaPatch.isNotEmpty) {
      final updatedQa = _applyQaPatch(next.qaSpec, qaPatch, summaries);
      if (updatedQa != next.qaSpec) {
        next = next.copyWith(qaSpec: updatedQa);
      }
    }

    if (specPatch != null && specPatch.isNotEmpty) {
      next = UxPatchApplier.applyAdditiveSpecPatch(next, specPatch, summaries);
    }

    next.validate();
    return QaPatchResult(
      project: next,
      summary: summaries.isEmpty
          ? 'Aucune modification structurelle'
          : summaries.join(', '),
    );
  }

  /// Applique [qaPatch] et [specPatch] élément par élément afin d'isoler toute
  /// entrée invalide dans [QaPartialPatchResult.rejectedEntries] tout en
  /// préservant un checkpoint sain.
  static QaPartialPatchResult applyPartial(
    SpecForgeProject project, {
    Map<String, Object?>? qaPatch,
    Map<String, Object?>? specPatch,
  }) {
    var current = project;
    final appliedSummaries = <String>[];
    final rejected = <SpecPatchRejectedEntry>[];

    if (qaPatch != null && qaPatch.isNotEmpty) {
      if (qaPatch['gherkinLanguage'] != null) {
        try {
          final before = current;
          final res = apply(
            current,
            qaPatch: <String, Object?>{
              'gherkinLanguage': qaPatch['gherkinLanguage'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add(
              'langue Gherkin (${current.qaSpec.gherkinLanguage.name})',
            );
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'qaPatch.gherkinLanguage',
              key: 'gherkinLanguage',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (qaPatch['removeFixtureIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            qaPatch: <String, Object?>{
              'removeFixtureIds': qaPatch['removeFixtureIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression fixture(s)');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'qaPatch.removeFixtureIds',
              key: 'removeFixtureIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (qaPatch['fixtures'] is List) {
        final rawFixtures = qaPatch['fixtures'] as List;
        var count = 0;
        for (var i = 0; i < rawFixtures.length; i++) {
          final item = rawFixtures[i];
          try {
            final res = apply(
              current,
              qaPatch: <String, Object?>{
                'fixtures': <Object?>[item],
              },
            );
            current = res.project;
            count++;
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'qaPatch.fixtures',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) appliedSummaries.add('$count fixture(s) QA');
      }

      if (qaPatch['removeFeatureIds'] is List ||
          qaPatch['removeScenarioIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            qaPatch: <String, Object?>{
              if (qaPatch['removeFeatureIds'] is List)
                'removeFeatureIds': qaPatch['removeFeatureIds'],
              if (qaPatch['removeScenarioIds'] is List)
                'removeScenarioIds': qaPatch['removeScenarioIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression feature(s)/scénario(s)');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'qaPatch.removeFeatureIds',
              key: 'removeFeatureIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (qaPatch['features'] is List) {
        final rawFeatures = qaPatch['features'] as List;
        var count = 0;
        for (var i = 0; i < rawFeatures.length; i++) {
          final item = rawFeatures[i];
          try {
            final res = apply(
              current,
              qaPatch: <String, Object?>{
                'features': <Object?>[item],
              },
            );
            current = res.project;
            count++;
          } catch (e) {
            if (item is Map && item['scenarios'] is List) {
              final salvaged = _salvageFeatureByScenario(
                current,
                item,
                rejected,
              );
              if (salvaged != current) {
                current = salvaged;
                count++;
                continue;
              }
            }
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'qaPatch.features',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) appliedSummaries.add('$count feature(s) Gherkin');
      }

      if (qaPatch['removeTddSuiteIds'] is List ||
          qaPatch['removeTddCaseIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            qaPatch: <String, Object?>{
              if (qaPatch['removeTddSuiteIds'] is List)
                'removeTddSuiteIds': qaPatch['removeTddSuiteIds'],
              if (qaPatch['removeTddCaseIds'] is List)
                'removeTddCaseIds': qaPatch['removeTddCaseIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression suite(s)/cas TDD');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'qaPatch.removeTddSuiteIds',
              key: 'removeTddSuiteIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (qaPatch['tddSuites'] is List) {
        final rawSuites = qaPatch['tddSuites'] as List;
        var count = 0;
        for (var i = 0; i < rawSuites.length; i++) {
          final item = rawSuites[i];
          try {
            final res = apply(
              current,
              qaPatch: <String, Object?>{
                'tddSuites': <Object?>[item],
              },
            );
            current = res.project;
            count++;
          } catch (e) {
            if (item is Map && item['cases'] is List) {
              final salvaged = _salvageSuiteByCase(current, item, rejected);
              if (salvaged != current) {
                current = salvaged;
                count++;
                continue;
              }
            }
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'qaPatch.tddSuites',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) appliedSummaries.add('$count suite(s) TDD');
      }

      if (qaPatch['coherenceIssues'] is List) {
        final rawIssues = qaPatch['coherenceIssues'] as List;
        final validIssues = <Object?>[];
        for (var i = 0; i < rawIssues.length; i++) {
          final item = rawIssues[i];
          try {
            QaCoherenceIssue.fromJson(item);
            validIssues.add(item);
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'qaPatch.coherenceIssues',
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
              qaPatch: <String, Object?>{'coherenceIssues': validIssues},
            );
            current = res.project;
            appliedSummaries.add('${validIssues.length} diagnostic(s) QA IA');
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'qaPatch.coherenceIssues',
                key: 'audit',
                reason: _reasonOf(e),
              ),
            );
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

    return QaPartialPatchResult(
      project: current,
      summary: appliedSummaries.join(', '),
      rejectedEntries: rejected,
    );
  }

  /// Récupère un checkpoint partiel sain depuis une réponse QA échouée ou tronquée,
  /// compatible avec [SpecDeltaRecovery.buildDeltaRetryPrompt].
  static SpecSalvageOutcome salvageFailedAttempt({
    required SpecForgeProject workingProject,
    required String rawResponse,
    Map<String, Object?>? decodedQaPatch,
    Map<String, Object?>? decodedSpecPatch,
  }) {
    final wasTruncated = decodedQaPatch == null && decodedSpecPatch == null;
    final candidateQa =
        decodedQaPatch ?? _trySalvageObjectField(rawResponse, 'qaPatch');
    final candidateSpec =
        decodedSpecPatch ?? _trySalvageObjectField(rawResponse, 'specPatch');

    if ((candidateQa == null || candidateQa.isEmpty) &&
        (candidateSpec == null || candidateSpec.isEmpty)) {
      return SpecSalvageOutcome.none(
        workingProject,
        wasTruncated: wasTruncated,
      );
    }

    final partial = applyPartial(
      workingProject,
      qaPatch: candidateQa,
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

  static QaForgeSpec _applyQaPatch(
    QaForgeSpec current,
    Map<String, Object?> qaPatch,
    List<String> summaries,
  ) {
    var nextQa = current;

    if (qaPatch['gherkinLanguage'] != null) {
      final rawLang = qaPatch['gherkinLanguage'];
      if (rawLang is! String) {
        throw const FormatException(
          'qaPatch.gherkinLanguage doit être une chaîne ("fr" ou "en").',
        );
      }
      final nextLang = GherkinKeywordLanguage.fromJson(rawLang);
      if (nextLang != nextQa.gherkinLanguage) {
        nextQa = nextQa.copyWith(gherkinLanguage: nextLang);
        summaries.add('langue Gherkin (${nextLang.name})');
      }
    }

    if (qaPatch['fixtures'] is List || qaPatch['removeFixtureIds'] is List) {
      final removeSet = _lowerStringSet(qaPatch['removeFixtureIds']);
      final mergedFixtures = <QaFixtureSpec>[
        for (final f in nextQa.fixtures)
          if (!_matchesRemove(f.id, f.code, 'FIX', removeSet)) f,
      ];

      if (qaPatch['fixtures'] is List) {
        for (final rawItem in qaPatch['fixtures'] as List) {
          final incoming = QaFixtureSpec.fromJson(rawItem);
          if (_matchesRemove(incoming.id, incoming.code, 'FIX', removeSet)) {
            continue;
          }
          final map = rawItem is Map ? rawItem : const <Object?, Object?>{};
          final hasExplicitId =
              (map['id'] as String?)?.trim().isNotEmpty == true;
          var idx = mergedFixtures.indexWhere(
            (e) => e.id.toLowerCase() == incoming.id.toLowerCase(),
          );
          if (idx < 0 && _hasSpecificCode(incoming.code, 'FIX')) {
            idx = mergedFixtures.indexWhere(
              (e) => e.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }

          if (idx >= 0) {
            final prev = mergedFixtures[idx];
            final mergedFixture = QaFixtureSpec(
              id: hasExplicitId ? incoming.id : prev.id,
              code: map.containsKey('code') ? incoming.code : prev.code,
              name:
                  (map['name'] is String ||
                      map['title'] is String ||
                      map['label'] is String)
                  ? incoming.name
                  : prev.name,
              kind: map.containsKey('kind') ? incoming.kind : prev.kind,
              businessObjectId:
                  (map.containsKey('businessObjectId') ||
                      map.containsKey('targetObjectId'))
                  ? incoming.businessObjectId
                  : prev.businessObjectId,
              personaId: map.containsKey('personaId')
                  ? incoming.personaId
                  : prev.personaId,
              businessRuleIds: map.containsKey('businessRuleIds')
                  ? incoming.businessRuleIds
                  : prev.businessRuleIds,
              description: map.containsKey('description')
                  ? incoming.description
                  : prev.description,
              payload:
                  (map.containsKey('payload') ||
                      map.containsKey('data') ||
                      map.containsKey('record'))
                  ? incoming.payload
                  : prev.payload,
              expectedValid: map.containsKey('expectedValid')
                  ? incoming.expectedValid
                  : prev.expectedValid,
              expectedErrorHint: map.containsKey('expectedErrorHint')
                  ? incoming.expectedErrorHint
                  : prev.expectedErrorHint,
            );
            mergedFixture.validate();
            mergedFixtures[idx] = mergedFixture;
          } else {
            var candidate = incoming;
            final usedIds = <String>{
              for (final f in mergedFixtures) f.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            candidate.validate();
            mergedFixtures.add(candidate);
          }
        }
      }

      if (!listEquals(mergedFixtures, nextQa.fixtures)) {
        nextQa = nextQa.copyWith(fixtures: mergedFixtures);
        summaries.add('${mergedFixtures.length} fixture(s) QA');
      }
    }

    if (qaPatch['features'] is List ||
        qaPatch['removeFeatureIds'] is List ||
        qaPatch['removeScenarioIds'] is List) {
      final removeFeatures = _lowerStringSet(qaPatch['removeFeatureIds']);
      final globalRemoveScenarios = _lowerStringSet(
        qaPatch['removeScenarioIds'],
      );
      final mergedFeatures = <GherkinFeatureSpec>[
        for (final feat in nextQa.features)
          if (!_matchesRemove(feat.id, feat.code, 'FEAT', removeFeatures))
            globalRemoveScenarios.isEmpty
                ? feat
                : feat.copyWith(
                    scenarios: [
                      for (final sc in feat.scenarios)
                        if (!_matchesRemove(
                          sc.id,
                          sc.code,
                          'SCN',
                          globalRemoveScenarios,
                        ))
                          sc,
                    ],
                  ),
      ];

      if (qaPatch['features'] is List) {
        for (final rawItem in qaPatch['features'] as List) {
          final incoming = GherkinFeatureSpec.fromJson(rawItem);
          if (_matchesRemove(
            incoming.id,
            incoming.code,
            'FEAT',
            removeFeatures,
          )) {
            continue;
          }
          final map = rawItem is Map ? rawItem : const <Object?, Object?>{};
          final hasExplicitId =
              (map['id'] as String?)?.trim().isNotEmpty == true;
          final localRemoveScenarios = <String>{
            ...globalRemoveScenarios,
            ..._lowerStringSet(map['removeScenarioIds']),
          };

          var idx = mergedFeatures.indexWhere(
            (f) => f.id.toLowerCase() == incoming.id.toLowerCase(),
          );
          if (idx < 0 && _hasSpecificCode(incoming.code, 'FEAT')) {
            idx = mergedFeatures.indexWhere(
              (f) => f.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }

          if (idx >= 0) {
            final prev = mergedFeatures[idx];
            final mergedScenarios = _mergeScenarios(
              prev.scenarios,
              map['scenarios'],
              localRemoveScenarios,
            );
            final mergedFeature = GherkinFeatureSpec(
              id: hasExplicitId ? incoming.id : prev.id,
              code: map.containsKey('code') ? incoming.code : prev.code,
              title:
                  ((map['title'] is String &&
                          (map['title'] as String).trim().isNotEmpty) ||
                      (map['name'] is String &&
                          (map['name'] as String).trim().isNotEmpty))
                  ? incoming.title
                  : prev.title,
              moduleId: map.containsKey('moduleId')
                  ? incoming.moduleId
                  : prev.moduleId,
              personaId: map.containsKey('personaId')
                  ? incoming.personaId
                  : prev.personaId,
              narrative: map.containsKey('narrative')
                  ? incoming.narrative
                  : prev.narrative,
              tags: map.containsKey('tags') ? incoming.tags : prev.tags,
              backgroundSteps: map.containsKey('backgroundSteps')
                  ? incoming.backgroundSteps
                  : prev.backgroundSteps,
              scenarios: mergedScenarios,
            );
            mergedFeature.validate();
            mergedFeatures[idx] = mergedFeature;
          } else {
            var candidate = localRemoveScenarios.isEmpty
                ? incoming
                : incoming.copyWith(
                    scenarios: [
                      for (final sc in incoming.scenarios)
                        if (!_matchesRemove(
                          sc.id,
                          sc.code,
                          'SCN',
                          localRemoveScenarios,
                        ))
                          sc,
                    ],
                  );
            final usedIds = <String>{
              for (final f in mergedFeatures) f.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            candidate.validate();
            mergedFeatures.add(candidate);
          }
        }
      }

      if (!listEquals(mergedFeatures, nextQa.features)) {
        nextQa = nextQa.copyWith(features: mergedFeatures);
        final totalSc = mergedFeatures.fold<int>(
          0,
          (sum, f) => sum + f.scenarios.length,
        );
        summaries.add(
          '${mergedFeatures.length} feature(s) Gherkin ($totalSc scénario(s))',
        );
      }
    }

    if (qaPatch['tddSuites'] is List ||
        qaPatch['removeTddSuiteIds'] is List ||
        qaPatch['removeTddCaseIds'] is List) {
      final removeSuites = _lowerStringSet(qaPatch['removeTddSuiteIds']);
      final globalRemoveCases = _lowerStringSet(qaPatch['removeTddCaseIds']);
      final mergedSuites = <TddTestSuiteSpec>[
        for (final s in nextQa.tddSuites)
          if (!_matchesRemove(s.id, s.code, 'TDD', removeSuites))
            globalRemoveCases.isEmpty
                ? s
                : s.copyWith(
                    cases: [
                      for (final c in s.cases)
                        if (!_matchesRemove(
                          c.id,
                          c.code,
                          'TC',
                          globalRemoveCases,
                        ))
                          c,
                    ],
                  ),
      ];

      if (qaPatch['tddSuites'] is List) {
        for (final rawItem in qaPatch['tddSuites'] as List) {
          final incoming = TddTestSuiteSpec.fromJson(rawItem);
          if (_matchesRemove(incoming.id, incoming.code, 'TDD', removeSuites)) {
            continue;
          }
          final map = rawItem is Map ? rawItem : const <Object?, Object?>{};
          final hasExplicitId =
              (map['id'] as String?)?.trim().isNotEmpty == true;
          final localRemoveCases = <String>{
            ...globalRemoveCases,
            ..._lowerStringSet(map['removeCaseIds']),
            ..._lowerStringSet(map['removeTddCaseIds']),
          };

          var idx = mergedSuites.indexWhere(
            (s) => s.id.toLowerCase() == incoming.id.toLowerCase(),
          );
          if (idx < 0 && _hasSpecificCode(incoming.code, 'TDD')) {
            idx = mergedSuites.indexWhere(
              (s) => s.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }

          if (idx >= 0) {
            final prev = mergedSuites[idx];
            final mergedCases = _mergeTddCases(
              prev.cases,
              map['cases'],
              localRemoveCases,
            );
            final mergedSuite = TddTestSuiteSpec(
              id: hasExplicitId ? incoming.id : prev.id,
              code: map.containsKey('code') ? incoming.code : prev.code,
              name:
                  ((map['name'] is String &&
                          (map['name'] as String).trim().isNotEmpty) ||
                      (map['title'] is String &&
                          (map['title'] as String).trim().isNotEmpty))
                  ? incoming.name
                  : prev.name,
              layer: map.containsKey('layer') ? incoming.layer : prev.layer,
              targetObjectId:
                  (map.containsKey('targetObjectId') ||
                      map.containsKey('businessObjectId'))
                  ? incoming.targetObjectId
                  : prev.targetObjectId,
              moduleId: map.containsKey('moduleId')
                  ? incoming.moduleId
                  : prev.moduleId,
              description: map.containsKey('description')
                  ? incoming.description
                  : prev.description,
              cases: mergedCases,
            );
            mergedSuite.validate();
            mergedSuites[idx] = mergedSuite;
          } else {
            var candidate = localRemoveCases.isEmpty
                ? incoming
                : incoming.copyWith(
                    cases: [
                      for (final c in incoming.cases)
                        if (!_matchesRemove(
                          c.id,
                          c.code,
                          'TC',
                          localRemoveCases,
                        ))
                          c,
                    ],
                  );
            final usedIds = <String>{
              for (final s in mergedSuites) s.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            candidate.validate();
            mergedSuites.add(candidate);
          }
        }
      }

      if (!listEquals(mergedSuites, nextQa.tddSuites)) {
        nextQa = nextQa.copyWith(tddSuites: mergedSuites);
        final totalCases = mergedSuites.fold<int>(
          0,
          (sum, s) => sum + s.cases.length,
        );
        summaries.add('${mergedSuites.length} suite(s) TDD ($totalCases cas)');
      }
    }

    if (qaPatch['coherenceIssues'] is List) {
      final localIssues = nextQa.coherenceIssues
          .where((i) => i.source == 'local')
          .toList();
      final seenIds = <String>{for (final i in localIssues) i.id};
      final aiIssues = <QaCoherenceIssue>[];
      for (final item in qaPatch['coherenceIssues'] as List) {
        var issue = QaCoherenceIssue.fromJson(item).copyWith(source: 'ai');
        if (!seenIds.add(issue.id)) {
          var suffix = 2;
          while (!seenIds.add('${issue.id}_$suffix')) {
            suffix++;
          }
          issue = issue.copyWith(id: '${issue.id}_$suffix');
        }
        aiIssues.add(issue);
      }
      final combined = <QaCoherenceIssue>[...localIssues, ...aiIssues];
      if (!listEquals(combined, nextQa.coherenceIssues)) {
        nextQa = nextQa.copyWith(coherenceIssues: combined);
      }
      summaries.add('${aiIssues.length} diagnostic(s) QA IA');
    }

    return nextQa;
  }

  static List<GherkinScenarioSpec> _mergeScenarios(
    List<GherkinScenarioSpec> existing,
    Object? rawIncomingList,
    Set<String> removeScenarioSet,
  ) {
    final merged = <GherkinScenarioSpec>[
      for (final sc in existing)
        if (!_matchesRemove(sc.id, sc.code, 'SCN', removeScenarioSet)) sc,
    ];
    if (rawIncomingList is! List || rawIncomingList.isEmpty) {
      return merged;
    }

    for (final rawSc in rawIncomingList) {
      final incoming = GherkinScenarioSpec.fromJson(rawSc);
      if (_matchesRemove(incoming.id, incoming.code, 'SCN', removeScenarioSet)) {
        continue;
      }
      final map = rawSc is Map ? rawSc : const <Object?, Object?>{};
      final hasExplicitId = (map['id'] as String?)?.trim().isNotEmpty == true;

      var idx = merged.indexWhere(
        (s) => s.id.toLowerCase() == incoming.id.toLowerCase(),
      );
      if (idx < 0 && _hasSpecificCode(incoming.code, 'SCN')) {
        idx = merged.indexWhere(
          (s) => s.code.toLowerCase() == incoming.code.toLowerCase(),
        );
      }

      if (idx >= 0) {
        final prev = merged[idx];
        final nextExamples = map.containsKey('examples')
            ? incoming.examples
            : prev.examples;
        final nextIsOutline = map['isOutline'] is bool
            ? incoming.isOutline
            : (nextExamples.isNotEmpty || prev.isOutline);
        final updated = GherkinScenarioSpec(
          id: hasExplicitId ? incoming.id : prev.id,
          code: map.containsKey('code') ? incoming.code : prev.code,
          title:
              ((map['title'] is String &&
                      (map['title'] as String).trim().isNotEmpty) ||
                  (map['name'] is String &&
                      (map['name'] as String).trim().isNotEmpty))
              ? incoming.title
              : prev.title,
          isOutline: nextIsOutline,
          tags: map.containsKey('tags') ? incoming.tags : prev.tags,
          steps: map.containsKey('steps') ? incoming.steps : prev.steps,
          examples: nextExamples,
          requirementIds: map.containsKey('requirementIds')
              ? incoming.requirementIds
              : prev.requirementIds,
          useCaseIds: map.containsKey('useCaseIds')
              ? incoming.useCaseIds
              : prev.useCaseIds,
          businessRuleIds: map.containsKey('businessRuleIds')
              ? incoming.businessRuleIds
              : prev.businessRuleIds,
          journeyIds: map.containsKey('journeyIds')
              ? incoming.journeyIds
              : prev.journeyIds,
          screenIds: map.containsKey('screenIds')
              ? incoming.screenIds
              : prev.screenIds,
          fixtureIds: map.containsKey('fixtureIds')
              ? incoming.fixtureIds
              : prev.fixtureIds,
        );
        updated.validate();
        merged[idx] = updated;
      } else {
        var candidate = incoming;
        final usedIds = <String>{for (final s in merged) s.id.toLowerCase()};
        if (usedIds.contains(candidate.id.toLowerCase())) {
          var suffix = 2;
          while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
            suffix++;
          }
          candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
        }
        candidate.validate();
        merged.add(candidate);
      }
    }
    return merged;
  }

  static List<TddTestCaseSpec> _mergeTddCases(
    List<TddTestCaseSpec> existing,
    Object? rawIncomingList,
    Set<String> removeCaseSet,
  ) {
    final merged = <TddTestCaseSpec>[
      for (final c in existing)
        if (!_matchesRemove(c.id, c.code, 'TC', removeCaseSet)) c,
    ];
    if (rawIncomingList is! List || rawIncomingList.isEmpty) {
      return merged;
    }

    for (var i = 0; i < rawIncomingList.length; i++) {
      final rawCase = rawIncomingList[i];
      final map = rawCase is Map ? rawCase : const <Object?, Object?>{};
      final hasExplicitOrder = map['order'] != null;
      final incoming = rawCase is Map && !hasExplicitOrder
          ? TddTestCaseSpec.fromJson(<Object?, Object?>{
              ...rawCase,
              'order': merged.length + 1,
            })
          : TddTestCaseSpec.fromJson(rawCase);

      if (_matchesRemove(incoming.id, incoming.code, 'TC', removeCaseSet)) {
        continue;
      }
      final hasExplicitId = (map['id'] as String?)?.trim().isNotEmpty == true;

      var idx = merged.indexWhere(
        (c) => c.id.toLowerCase() == incoming.id.toLowerCase(),
      );
      if (idx < 0 && _hasSpecificCode(incoming.code, 'TC')) {
        idx = merged.indexWhere(
          (c) => c.code.toLowerCase() == incoming.code.toLowerCase(),
        );
      }

      if (idx >= 0) {
        final prev = merged[idx];
        final updated = TddTestCaseSpec(
          id: hasExplicitId ? incoming.id : prev.id,
          code: map.containsKey('code') ? incoming.code : prev.code,
          order: hasExplicitOrder ? incoming.order : prev.order,
          title:
              ((map['title'] is String &&
                      (map['title'] as String).trim().isNotEmpty) ||
                  (map['name'] is String &&
                      (map['name'] as String).trim().isNotEmpty))
              ? incoming.title
              : prev.title,
          fixtureId: map.containsKey('fixtureId')
              ? incoming.fixtureId
              : prev.fixtureId,
          arrange: map.containsKey('arrange') ? incoming.arrange : prev.arrange,
          act: map.containsKey('act') ? incoming.act : prev.act,
          outcomeKind: map.containsKey('outcomeKind')
              ? incoming.outcomeKind
              : prev.outcomeKind,
          assertExpected: map.containsKey('assertExpected')
              ? incoming.assertExpected
              : prev.assertExpected,
          expectedErrorMessage: map.containsKey('expectedErrorMessage')
              ? incoming.expectedErrorMessage
              : prev.expectedErrorMessage,
          businessRuleIds: map.containsKey('businessRuleIds')
              ? incoming.businessRuleIds
              : prev.businessRuleIds,
          requirementIds: map.containsKey('requirementIds')
              ? incoming.requirementIds
              : prev.requirementIds,
          screenIds: map.containsKey('screenIds')
              ? incoming.screenIds
              : prev.screenIds,
        );
        updated.validate();
        merged[idx] = updated;
      } else {
        var candidate = incoming;
        final usedIds = <String>{for (final c in merged) c.id.toLowerCase()};
        if (usedIds.contains(candidate.id.toLowerCase())) {
          var suffix = 2;
          while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
            suffix++;
          }
          candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
        }
        candidate.validate();
        merged.add(candidate);
      }
    }
    return merged;
  }

  static SpecForgeProject _salvageFeatureByScenario(
    SpecForgeProject project,
    Map<Object?, Object?> rawFeature,
    List<SpecPatchRejectedEntry> rejected,
  ) {
    final featureHeader = <String, Object?>{
      for (final entry in rawFeature.entries)
        if (entry.key is String && entry.key != 'scenarios')
          entry.key as String: entry.value,
    };
    var current = project;
    try {
      current = apply(
        current,
        qaPatch: <String, Object?>{
          'features': <Object?>[featureHeader],
        },
      ).project;
    } catch (_) {
      return project;
    }

    final targetFeature = current.qaSpec.features.last;
    final rawScenarios = rawFeature['scenarios'] as List;
    for (var j = 0; j < rawScenarios.length; j++) {
      final scItem = rawScenarios[j];
      try {
        current = apply(
          current,
          qaPatch: <String, Object?>{
            'features': <Object?>[
              <String, Object?>{
                'id': targetFeature.id,
                'scenarios': <Object?>[scItem],
              },
            ],
          },
        ).project;
      } catch (e) {
        rejected.add(
          SpecPatchRejectedEntry(
            section: 'qaPatch.features.scenarios',
            key: _labelForItem(scItem, fallback: '${targetFeature.code}#$j'),
            reason: _reasonOf(e),
          ),
        );
      }
    }
    return current;
  }

  static SpecForgeProject _salvageSuiteByCase(
    SpecForgeProject project,
    Map<Object?, Object?> rawSuite,
    List<SpecPatchRejectedEntry> rejected,
  ) {
    final suiteHeader = <String, Object?>{
      for (final entry in rawSuite.entries)
        if (entry.key is String && entry.key != 'cases')
          entry.key as String: entry.value,
    };
    var current = project;
    try {
      current = apply(
        current,
        qaPatch: <String, Object?>{
          'tddSuites': <Object?>[suiteHeader],
        },
      ).project;
    } catch (_) {
      return project;
    }

    final targetSuite = current.qaSpec.tddSuites.last;
    final rawCases = rawSuite['cases'] as List;
    for (var j = 0; j < rawCases.length; j++) {
      final caseItem = rawCases[j];
      try {
        current = apply(
          current,
          qaPatch: <String, Object?>{
            'tddSuites': <Object?>[
              <String, Object?>{
                'id': targetSuite.id,
                'cases': <Object?>[caseItem],
              },
            ],
          },
        ).project;
      } catch (e) {
        rejected.add(
          SpecPatchRejectedEntry(
            section: 'qaPatch.tddSuites.cases',
            key: _labelForItem(caseItem, fallback: '${targetSuite.code}#$j'),
            reason: _reasonOf(e),
          ),
        );
      }
    }
    return current;
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

  static Map<String, Object?>? _trySalvageObjectField(
    String raw,
    String fieldName,
  ) {
    final match = RegExp('"$fieldName"\\s*:\\s*\\{').firstMatch(raw);
    if (match == null) return null;
    final startBrace = match.end - 1;
    final slice = raw.substring(startBrace);
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
