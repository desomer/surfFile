/// Application déterministe et incrémentale des patches UX (`"uxPatch"`) et
/// enrichissement strictement additif du modèle métier (`"specPatch"`) ([UxPatchApplier]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/json_schema_constraints.dart';
import '../models/spec_forge_project.dart';
import '../models/ux/ux_coherence_issue.dart';
import '../models/ux/ux_forge_spec.dart';
import '../models/ux/ux_journey_spec.dart';
import '../models/ux/ux_navigation_spec.dart';
import '../models/ux/ux_screen_spec.dart';
import 'spec_delta_recovery.dart';
import 'spec_patch_applier.dart';

/// Résultat immuable d'application conjointe de `"uxPatch"` et `"specPatch"`.
@immutable
class UxPatchResult {
  /// Construit un résultat d'application de patch UX.
  const UxPatchResult({required this.project, required this.summary});

  /// Projet mis à jour.
  final SpecForgeProject project;

  /// Résumé lisible en français des sections modifiées.
  final String summary;
}

/// Résultat immuable d'une application tolérante par élément conservant les entrées UX/Spec valides.
@immutable
class UxPartialPatchResult {
  /// Construit un résultat d'application partielle UX.
  UxPartialPatchResult({
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

/// Fusionne incrémentalement `"uxPatch"` sur [UxForgeSpec] et applique
/// `"specPatch"` selon le contrat strictement additif (`additive_safe`).
abstract final class UxPatchApplier {
  /// Clés destructrices explicitement ignorées lorsqu'un `"specPatch"` provient d'un agent UX.
  static const Set<String> ignoredDestructiveSpecKeys = <String>{
    'removeBusinessObjectIds',
    'removeBusinessRuleIds',
    'removeLexiconTermIds',
    'removePersonaIds',
    'removeModuleIds',
    'removeRequirementIds',
    'removeUseCaseIds',
    'removeNfrIds',
    'removeAttributes',
  };

  /// Applique [uxPatch] et [specPatch] (mode additif sûr) sur [project] sans muter l'existant.
  static UxPatchResult apply(
    SpecForgeProject project, {
    Map<String, Object?>? uxPatch,
    Map<String, Object?>? specPatch,
  }) {
    var next = project;
    final summaries = <String>[];

    if (uxPatch != null && uxPatch.isNotEmpty) {
      final updatedUx = _applyUxPatch(next.uxSpec, uxPatch, summaries);
      if (updatedUx != next.uxSpec) {
        next = next.copyWith(uxSpec: updatedUx);
      }
    }

    if (specPatch != null && specPatch.isNotEmpty) {
      next = applyAdditiveSpecPatch(next, specPatch, summaries);
    }

    next.validate();
    return UxPatchResult(
      project: next,
      summary: summaries.isEmpty
          ? 'Aucune modification structurelle'
          : summaries.join(', '),
    );
  }

  /// Applique [uxPatch] et [specPatch] élément par élément afin d'isoler toute
  /// entrée invalide dans [UxPartialPatchResult.rejectedEntries] tout en
  /// préservant un checkpoint sain.
  static UxPartialPatchResult applyPartial(
    SpecForgeProject project, {
    Map<String, Object?>? uxPatch,
    Map<String, Object?>? specPatch,
  }) {
    var current = project;
    final appliedSummaries = <String>[];
    final rejected = <SpecPatchRejectedEntry>[];

    if (uxPatch != null && uxPatch.isNotEmpty) {
      if (uxPatch['removeJourneyIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            uxPatch: <String, Object?>{
              'removeJourneyIds': uxPatch['removeJourneyIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression parcours');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'uxPatch.removeJourneyIds',
              key: 'removeJourneyIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (uxPatch['journeys'] is List) {
        final rawJourneys = uxPatch['journeys'] as List;
        var count = 0;
        for (var i = 0; i < rawJourneys.length; i++) {
          final item = rawJourneys[i];
          try {
            final res = apply(
              current,
              uxPatch: <String, Object?>{
                'journeys': <Object?>[item],
              },
            );
            current = res.project;
            count++;
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'uxPatch.journeys',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) appliedSummaries.add('$count parcours UX');
      }

      if (uxPatch['navigation'] is Map ||
          uxPatch['removeRouteIds'] is List ||
          uxPatch['visualTheme'] is Map) {
        final rawNav = uxPatch['navigation'];
        final navMap = rawNav is Map ? rawNav : const <Object?, Object?>{};
        final scalarNav = <String, Object?>{
          for (final entry in navMap.entries)
            if (entry.key is String &&
                entry.key != 'routes' &&
                entry.key != 'visualTheme')
              entry.key as String: entry.value,
        };
        final rawTheme = navMap['visualTheme'] ?? uxPatch['visualTheme'];

        if (scalarNav.isNotEmpty || uxPatch['removeRouteIds'] is List) {
          try {
            final res = apply(
              current,
              uxPatch: <String, Object?>{
                if (scalarNav.isNotEmpty) 'navigation': scalarNav,
                if (uxPatch['removeRouteIds'] is List)
                  'removeRouteIds': uxPatch['removeRouteIds'],
              },
            );
            current = res.project;
            appliedSummaries.add('shell navigation');
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'uxPatch.navigation',
                key: 'shell',
                reason: _reasonOf(e),
              ),
            );
          }
        }

        if (rawTheme is Map) {
          try {
            final res = apply(
              current,
              uxPatch: <String, Object?>{
                'navigation': <String, Object?>{'visualTheme': rawTheme},
              },
            );
            current = res.project;
            appliedSummaries.add('thème visuel');
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'uxPatch.navigation.visualTheme',
                key: 'visualTheme',
                reason: _reasonOf(e),
              ),
            );
          }
        }

        final rawRoutes = navMap['routes'];
        if (rawRoutes is List) {
          var count = 0;
          for (var i = 0; i < rawRoutes.length; i++) {
            final item = rawRoutes[i];
            try {
              final res = apply(
                current,
                uxPatch: <String, Object?>{
                  'navigation': <String, Object?>{
                    'routes': <Object?>[item],
                  },
                },
              );
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'uxPatch.navigation.routes',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count route(s)');
        }
      }

      if (uxPatch['removeScreenIds'] is List) {
        try {
          final before = current;
          final res = apply(
            current,
            uxPatch: <String, Object?>{
              'removeScreenIds': uxPatch['removeScreenIds'],
            },
          );
          if (res.project != before) {
            current = res.project;
            appliedSummaries.add('suppression écran(s)');
          }
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'uxPatch.removeScreenIds',
              key: 'removeScreenIds',
              reason: _reasonOf(e),
            ),
          );
        }
      }

      if (uxPatch['screens'] is List) {
        final rawScreens = uxPatch['screens'] as List;
        var count = 0;
        for (var i = 0; i < rawScreens.length; i++) {
          final item = rawScreens[i];
          try {
            final res = apply(
              current,
              uxPatch: <String, Object?>{
                'screens': <Object?>[item],
              },
            );
            current = res.project;
            count++;
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'uxPatch.screens',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) appliedSummaries.add('$count écran(s) UX');
      }

      if (uxPatch['coherenceIssues'] is List) {
        final rawIssues = uxPatch['coherenceIssues'] as List;
        final validIssues = <Object?>[];
        for (var i = 0; i < rawIssues.length; i++) {
          final item = rawIssues[i];
          try {
            UxCoherenceIssue.fromJson(item);
            validIssues.add(item);
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'uxPatch.coherenceIssues',
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
              uxPatch: <String, Object?>{'coherenceIssues': validIssues},
            );
            current = res.project;
            appliedSummaries.add('${validIssues.length} diagnostic(s) UX IA');
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'uxPatch.coherenceIssues',
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
            current = applyAdditiveSpecPatch(
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
            current = applyAdditiveSpecPatch(
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

    return UxPartialPatchResult(
      project: current,
      summary: appliedSummaries.join(', '),
      rejectedEntries: rejected,
    );
  }

  /// Récupère un checkpoint partiel sain depuis une réponse UX échouée ou tronquée,
  /// compatible avec [SpecDeltaRecovery.buildDeltaRetryPrompt].
  static SpecSalvageOutcome salvageFailedAttempt({
    required SpecForgeProject workingProject,
    required String rawResponse,
    Map<String, Object?>? decodedUxPatch,
    Map<String, Object?>? decodedSpecPatch,
  }) {
    final wasTruncated = decodedUxPatch == null && decodedSpecPatch == null;
    final candidateUx =
        decodedUxPatch ?? _trySalvageObjectField(rawResponse, 'uxPatch');
    final candidateSpec =
        decodedSpecPatch ?? _trySalvageObjectField(rawResponse, 'specPatch');

    if ((candidateUx == null || candidateUx.isEmpty) &&
        (candidateSpec == null || candidateSpec.isEmpty)) {
      return SpecSalvageOutcome.none(
        workingProject,
        wasTruncated: wasTruncated,
      );
    }

    final partial = applyPartial(
      workingProject,
      uxPatch: candidateUx,
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

  /// Applique un `"specPatch"` selon le contrat strictement additif (`additive_safe`) :
  /// ignore toute clé destructrice, n'accepte que `businessObjects` et `businessRules`,
  /// et ne supprime jamais d'objet, d'attribut, de sous-attribut, de relation, d'état ou de règle existant.
  static SpecForgeProject applyAdditiveSpecPatch(
    SpecForgeProject project,
    Map<String, Object?> specPatch,
    List<String> summaries,
  ) {
    var next = project;

    if (specPatch['businessObjects'] is List) {
      final rawList = specPatch['businessObjects'] as List;
      final mergedObjects = List<BusinessObjectSpec>.from(next.businessObjects);
      var addedCount = 0;
      var enrichedCount = 0;

      for (final rawObj in rawList) {
        final incoming = BusinessObjectSpec.fromJson(rawObj);
        final matchIndex = mergedObjects.indexWhere(
          (existing) =>
              existing.id.toLowerCase() == incoming.id.toLowerCase() ||
              existing.technicalName.toLowerCase() ==
                  incoming.technicalName.toLowerCase(),
        );

        if (matchIndex >= 0) {
          final existing = mergedObjects[matchIndex];
          final merged = _mergeBusinessObjectAdditively(existing, incoming);
          merged.validate();
          if (merged != existing) {
            mergedObjects[matchIndex] = merged;
            enrichedCount++;
          }
        } else {
          var candidate = incoming;
          final usedIds = <String>{
            for (final o in mergedObjects) o.id.toLowerCase(),
          };
          if (usedIds.contains(candidate.id.toLowerCase())) {
            var suffix = 2;
            while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
              suffix++;
            }
            candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
          }
          candidate.validate();
          mergedObjects.add(candidate);
          addedCount++;
        }
      }

      if (addedCount > 0 || enrichedCount > 0) {
        next = next.copyWith(businessObjects: mergedObjects);
        final parts = <String>[
          if (addedCount > 0) '+$addedCount objet(s) métier(s)',
          if (enrichedCount > 0) '$enrichedCount objet(s) métier(s) enrichi(s)',
        ];
        summaries.add(parts.join(', '));
      }
    }

    if (specPatch['businessRules'] is List) {
      final rawList = specPatch['businessRules'] as List;
      final mergedRules = List<BusinessRuleSpec>.from(next.businessRules);
      var addedCount = 0;
      var enrichedCount = 0;

      for (final rawRule in rawList) {
        final incoming = BusinessRuleSpec.fromJson(rawRule);
        final ruleMap = rawRule is Map ? rawRule : const <Object?, Object?>{};
        final hasSpecificCode =
            incoming.code.trim().isNotEmpty &&
            incoming.code.trim().toUpperCase() != 'RG';

        final matchIndex = mergedRules.indexWhere(
          (existing) =>
              existing.id.toLowerCase() == incoming.id.toLowerCase() ||
              (hasSpecificCode &&
                  existing.code.toLowerCase() == incoming.code.toLowerCase()),
        );

        if (matchIndex >= 0) {
          final existing = mergedRules[matchIndex];
          final merged = _mergeBusinessRuleAdditively(
            existing,
            incoming,
            ruleMap,
          );
          merged.validate();
          if (merged != existing) {
            mergedRules[matchIndex] = merged;
            enrichedCount++;
          }
        } else {
          var candidate = incoming;
          final usedIds = <String>{
            for (final r in mergedRules) r.id.toLowerCase(),
          };
          if (usedIds.contains(candidate.id.toLowerCase())) {
            var suffix = 2;
            while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
              suffix++;
            }
            candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
          }
          candidate.validate();
          mergedRules.add(candidate);
          addedCount++;
        }
      }

      if (addedCount > 0 || enrichedCount > 0) {
        next = next.copyWith(businessRules: mergedRules);
        final parts = <String>[
          if (addedCount > 0) '+$addedCount règle(s) RG',
          if (enrichedCount > 0) '$enrichedCount règle(s) RG enrichie(s)',
        ];
        summaries.add(parts.join(', '));
      }
    }

    next.validate();
    return next;
  }

  static UxForgeSpec _applyUxPatch(
    UxForgeSpec current,
    Map<String, Object?> uxPatch,
    List<String> summaries,
  ) {
    var nextUx = current;

    if (uxPatch['journeys'] is List || uxPatch['removeJourneyIds'] is List) {
      final removeSet = _lowerStringSet(uxPatch['removeJourneyIds']);
      final mergedJourneys = <UxJourneySpec>[
        for (final j in nextUx.journeys)
          if (!removeSet.contains(j.id.toLowerCase()) &&
              !(j.code.isNotEmpty &&
                  j.code.toUpperCase() != 'JRN' &&
                  removeSet.contains(j.code.toLowerCase())))
            j,
      ];

      if (uxPatch['journeys'] is List) {
        for (final rawItem in uxPatch['journeys'] as List) {
          var incoming = UxJourneySpec.fromJson(rawItem);
          if (removeSet.contains(incoming.id.toLowerCase()) ||
              (incoming.code.isNotEmpty &&
                  incoming.code.toUpperCase() != 'JRN' &&
                  removeSet.contains(incoming.code.toLowerCase()))) {
            continue;
          }
          final hasExplicitId =
              rawItem is Map &&
              (rawItem['id'] as String?)?.trim().isNotEmpty == true;
          var idx = mergedJourneys.indexWhere(
            (e) => e.id.toLowerCase() == incoming.id.toLowerCase(),
          );
          if (idx < 0 &&
              incoming.code.isNotEmpty &&
              incoming.code.toUpperCase() != 'JRN') {
            idx = mergedJourneys.indexWhere(
              (e) => e.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }
          if (idx >= 0) {
            final prev = mergedJourneys[idx];
            if (!hasExplicitId) {
              incoming = incoming.copyWith(id: prev.id);
            }
            mergedJourneys[idx] = incoming;
          } else {
            var candidate = incoming;
            final usedIds = <String>{
              for (final j in mergedJourneys) j.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            mergedJourneys.add(candidate);
          }
        }
      }

      if (!listEquals(mergedJourneys, nextUx.journeys)) {
        nextUx = nextUx.copyWith(journeys: mergedJourneys);
        summaries.add('${mergedJourneys.length} parcours UX');
      }
    }

    if (uxPatch['navigation'] is Map ||
        uxPatch['removeRouteIds'] is List ||
        uxPatch['visualTheme'] is Map) {
      final navMap = uxPatch['navigation'] is Map
          ? uxPatch['navigation'] as Map
          : const <Object?, Object?>{};
      final removeRoutes = <String>{
        ..._lowerStringSet(uxPatch['removeRouteIds']),
        ..._lowerStringSet(navMap['removeRouteIds']),
      };
      final normalizedRemovePaths = <String>{
        for (final r in removeRoutes)
          if (r.startsWith('/')) UxRouteNode.normalizePath(r).toLowerCase(),
      };

      final currentNav = nextUx.navigation;
      final mergedRoutes = <UxRouteNode>[
        for (final r in currentNav.routes)
          if (!removeRoutes.contains(r.id.toLowerCase()) &&
              !normalizedRemovePaths.contains(r.path.toLowerCase()))
            r,
      ];

      if (navMap['routes'] is List) {
        for (final rawRoute in navMap['routes'] as List) {
          var incoming = UxRouteNode.fromJson(rawRoute);
          if (removeRoutes.contains(incoming.id.toLowerCase()) ||
              normalizedRemovePaths.contains(incoming.path.toLowerCase())) {
            continue;
          }
          final hasExplicitId =
              rawRoute is Map &&
              (rawRoute['id'] as String?)?.trim().isNotEmpty == true;
          var idx = mergedRoutes.indexWhere(
            (r) => r.id.toLowerCase() == incoming.id.toLowerCase(),
          );
          if (idx < 0) {
            if (!incoming.pageType.isModal) {
              idx = mergedRoutes.indexWhere(
                (r) =>
                    !r.pageType.isModal &&
                    r.path.toLowerCase() == incoming.path.toLowerCase(),
              );
            } else if (!hasExplicitId) {
              idx = mergedRoutes.indexWhere(
                (r) =>
                    r.pageType == incoming.pageType &&
                    r.path.toLowerCase() == incoming.path.toLowerCase(),
              );
            }
          }

          if (idx >= 0) {
            final prev = mergedRoutes[idx];
            if (!hasExplicitId) {
              incoming = incoming.copyWith(id: prev.id);
            }
            mergedRoutes[idx] = incoming;
            if (!incoming.pageType.isModal) {
              mergedRoutes.removeWhere(
                (r) =>
                    !identical(r, incoming) &&
                    !r.pageType.isModal &&
                    r.path.toLowerCase() == incoming.path.toLowerCase(),
              );
            }
          } else {
            var candidate = incoming;
            final usedIds = <String>{
              for (final r in mergedRoutes) r.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            mergedRoutes.add(candidate);
          }
        }
      }

      final rawTheme = navMap['visualTheme'] ?? uxPatch['visualTheme'];
      final mergedTheme = rawTheme is Map
          ? _mergeVisualThemeIncrementally(currentNav.visualTheme, rawTheme)
          : currentNav.visualTheme;

      var nextHomeRouteId = currentNav.homeRouteId;
      if (navMap['homeRouteId'] is String) {
        nextHomeRouteId = (navMap['homeRouteId'] as String).trim();
      } else if (removeRoutes.contains(nextHomeRouteId.toLowerCase())) {
        nextHomeRouteId = '';
      }

      final updatedNav = UxNavigationSpec(
        shellPattern: navMap['shellPattern'] != null
            ? UxShellPattern.fromJson(navMap['shellPattern'])
            : currentNav.shellPattern,
        hasAppBar: navMap['hasAppBar'] is bool
            ? navMap['hasAppBar'] as bool
            : currentNav.hasAppBar,
        hasBreadcrumbs: navMap['hasBreadcrumbs'] is bool
            ? navMap['hasBreadcrumbs'] as bool
            : currentNav.hasBreadcrumbs,
        hasGlobalSearch: navMap['hasGlobalSearch'] is bool
            ? navMap['hasGlobalSearch'] as bool
            : currentNav.hasGlobalSearch,
        homeRouteId: nextHomeRouteId,
        routes: mergedRoutes,
        visualTheme: mergedTheme,
      );
      updatedNav.validate();

      if (updatedNav != currentNav) {
        nextUx = nextUx.copyWith(navigation: updatedNav);
        summaries.add(
          'navigation & thème (${updatedNav.routes.length} route(s))',
        );
      }
    }

    if (uxPatch['screens'] is List || uxPatch['removeScreenIds'] is List) {
      final removeSet = _lowerStringSet(uxPatch['removeScreenIds']);
      final mergedScreens = <UxScreenSpec>[
        for (final s in nextUx.screens)
          if (!removeSet.contains(s.id.toLowerCase()) &&
              !(s.code.isNotEmpty &&
                  s.code.toUpperCase() != 'SCR' &&
                  removeSet.contains(s.code.toLowerCase())))
            s,
      ];

      if (uxPatch['screens'] is List) {
        for (final rawItem in uxPatch['screens'] as List) {
          final incoming = UxScreenSpec.fromJson(rawItem);
          if (removeSet.contains(incoming.id.toLowerCase()) ||
              (incoming.code.isNotEmpty &&
                  incoming.code.toUpperCase() != 'SCR' &&
                  removeSet.contains(incoming.code.toLowerCase()))) {
            continue;
          }
          final map = rawItem is Map ? rawItem : const <Object?, Object?>{};
          final hasExplicitId =
              (map['id'] as String?)?.trim().isNotEmpty == true;
          var idx = mergedScreens.indexWhere(
            (s) => s.id.toLowerCase() == incoming.id.toLowerCase(),
          );
          if (idx < 0 &&
              incoming.code.isNotEmpty &&
              incoming.code.toUpperCase() != 'SCR') {
            idx = mergedScreens.indexWhere(
              (s) => s.code.toLowerCase() == incoming.code.toLowerCase(),
            );
          }

          if (idx >= 0) {
            final prev = mergedScreens[idx];
            final mergedScreen = UxScreenSpec(
              id: hasExplicitId ? incoming.id : prev.id,
              code: map.containsKey('code') ? incoming.code : prev.code,
              name: (map['name'] is String || map['title'] is String)
                  ? incoming.name
                  : prev.name,
              routeId: map.containsKey('routeId')
                  ? incoming.routeId
                  : prev.routeId,
              pattern: map.containsKey('pattern')
                  ? incoming.pattern
                  : prev.pattern,
              purpose: map.containsKey('purpose')
                  ? incoming.purpose
                  : prev.purpose,
              personaIds: map.containsKey('personaIds')
                  ? incoming.personaIds
                  : prev.personaIds,
              useCaseIds: map.containsKey('useCaseIds')
                  ? incoming.useCaseIds
                  : prev.useCaseIds,
              requirementIds: map.containsKey('requirementIds')
                  ? incoming.requirementIds
                  : prev.requirementIds,
              primaryObjectId: map.containsKey('primaryObjectId')
                  ? incoming.primaryObjectId
                  : prev.primaryObjectId,
              zones: map.containsKey('zones') ? incoming.zones : prev.zones,
              actions: map.containsKey('actions')
                  ? incoming.actions
                  : prev.actions,
              states: map.containsKey('states')
                  ? _mergeScreenStates(prev.states, map['states'])
                  : prev.states,
            );
            mergedScreen.validate();
            mergedScreens[idx] = mergedScreen;
          } else {
            var candidate = incoming;
            final usedIds = <String>{
              for (final s in mergedScreens) s.id.toLowerCase(),
            };
            if (usedIds.contains(candidate.id.toLowerCase())) {
              var suffix = 2;
              while (usedIds.contains('${incoming.id}_$suffix'.toLowerCase())) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${incoming.id}_$suffix');
            }
            mergedScreens.add(candidate);
          }
        }
      }

      if (!listEquals(mergedScreens, nextUx.screens)) {
        nextUx = nextUx.copyWith(screens: mergedScreens);
        summaries.add('${mergedScreens.length} écran(s) UX');
      }
    }

    if (uxPatch['coherenceIssues'] is List) {
      final localIssues = nextUx.coherenceIssues
          .where((i) => i.source == 'local')
          .toList();
      final seenIds = <String>{for (final i in localIssues) i.id};
      final aiIssues = <UxCoherenceIssue>[];
      for (final item in uxPatch['coherenceIssues'] as List) {
        var issue = UxCoherenceIssue.fromJson(item).copyWith(source: 'ai');
        if (!seenIds.add(issue.id)) {
          var suffix = 2;
          while (!seenIds.add('${issue.id}_$suffix')) {
            suffix++;
          }
          issue = issue.copyWith(id: '${issue.id}_$suffix');
        }
        aiIssues.add(issue);
      }
      final combined = <UxCoherenceIssue>[...localIssues, ...aiIssues];
      if (!listEquals(combined, nextUx.coherenceIssues)) {
        nextUx = nextUx.copyWith(coherenceIssues: combined);
      }
      summaries.add('${aiIssues.length} diagnostic(s) UX IA');
    }

    return nextUx;
  }

  static UxVisualThemeSeed _mergeVisualThemeIncrementally(
    UxVisualThemeSeed base,
    Map<Object?, Object?> raw,
  ) {
    final rawAccent = raw['accentHex'];
    final accentHex = rawAccent is String && rawAccent.trim().isNotEmpty
        ? UxVisualThemeSeed.normalizeAccentHex(
            rawAccent,
            fallback: base.accentHex,
          )
        : base.accentHex;

    final rawMode = raw['themeMode'];
    final themeMode = rawMode is String && rawMode.trim().isNotEmpty
        ? UxVisualThemeSeed.normalizeThemeMode(rawMode)
        : base.themeMode;

    final rawSurface = raw['surfaceSystem'];
    final surfaceSystem = rawSurface is String && rawSurface.trim().isNotEmpty
        ? UxVisualThemeSeed.normalizeSurfaceSystem(rawSurface)
        : base.surfaceSystem;

    final rawFont = raw['fontFamily'];
    final fontFamily = rawFont is String && rawFont.trim().isNotEmpty
        ? rawFont.trim()
        : base.fontFamily;

    final density = raw.containsKey('density') && raw['density'] != null
        ? UxDensityProfile.fromJson(raw['density'])
        : base.density;

    final rawRadius = raw['cardRadius'];
    final cardRadius = switch (rawRadius) {
      final num v when v.isFinite => v.toDouble().clamp(0.0, 32.0),
      final String s => switch (double.tryParse(s.trim())) {
        final double v when v.isFinite => v.clamp(0.0, 32.0),
        _ => base.cardRadius,
      },
      _ => base.cardRadius,
    };

    final uxVoiceGuidelines = raw['uxVoiceGuidelines'] is String
        ? (raw['uxVoiceGuidelines'] as String).trim()
        : base.uxVoiceGuidelines;

    final merged = UxVisualThemeSeed(
      accentHex: accentHex,
      themeMode: themeMode,
      surfaceSystem: surfaceSystem,
      fontFamily: fontFamily,
      density: density,
      cardRadius: cardRadius,
      uxVoiceGuidelines: uxVoiceGuidelines,
    );
    merged.validate();
    return merged;
  }

  static UxScreenStatesSpec _mergeScreenStates(
    UxScreenStatesSpec base,
    Object? raw,
  ) {
    if (raw is! Map) return base;
    final parsed = UxScreenStatesSpec.fromJson(raw);
    return UxScreenStatesSpec(
      emptyStateTitle: raw.containsKey('emptyStateTitle')
          ? parsed.emptyStateTitle
          : base.emptyStateTitle,
      emptyStateCta: raw.containsKey('emptyStateCta')
          ? parsed.emptyStateCta
          : base.emptyStateCta,
      loadingPattern: raw.containsKey('loadingPattern')
          ? parsed.loadingPattern
          : base.loadingPattern,
      errorHandling: raw.containsKey('errorHandling')
          ? parsed.errorHandling
          : base.errorHandling,
      readOnlyRuleIds: raw.containsKey('readOnlyRuleIds')
          ? parsed.readOnlyRuleIds
          : base.readOnlyRuleIds,
    );
  }

  static BusinessObjectSpec _mergeBusinessObjectAdditively(
    BusinessObjectSpec existing,
    BusinessObjectSpec incoming,
  ) {
    final usedAttrIds = <String>{};
    _collectAttributeIds(existing.attributes, usedAttrIds);

    final mergedAttributes = _mergeAttributeListAdditively(
      existing.attributes,
      incoming.attributes,
      usedAttrIds,
    );

    final mergedRelations = List<BusinessRelation>.from(existing.relations);
    final usedRelIds = <String>{
      for (final r in mergedRelations) r.id.toLowerCase(),
    };
    for (final incRel in incoming.relations) {
      final idx = mergedRelations.indexWhere(
        (r) =>
            r.id.toLowerCase() == incRel.id.toLowerCase() ||
            r.name.toLowerCase() == incRel.name.toLowerCase(),
      );
      if (idx >= 0) {
        final prev = mergedRelations[idx];
        mergedRelations[idx] = prev.copyWith(
          description: incRel.description.isNotEmpty
              ? incRel.description
              : prev.description,
          inverseName: incRel.inverseName.isNotEmpty
              ? incRel.inverseName
              : prev.inverseName,
        );
      } else {
        var candidate = incRel;
        if (usedRelIds.contains(candidate.id.toLowerCase())) {
          var suffix = 2;
          while (usedRelIds.contains('${incRel.id}_$suffix'.toLowerCase())) {
            suffix++;
          }
          candidate = candidate.copyWith(id: '${incRel.id}_$suffix');
        }
        usedRelIds.add(candidate.id.toLowerCase());
        mergedRelations.add(candidate);
      }
    }

    final mergedStates = List<LifecycleState>.from(existing.lifecycleStates);
    for (final incState in incoming.lifecycleStates) {
      final idx = mergedStates.indexWhere(
        (s) => s.name.toLowerCase() == incState.name.toLowerCase(),
      );
      if (idx >= 0) {
        final prev = mergedStates[idx];
        mergedStates[idx] = prev.copyWith(
          label: incState.label.isNotEmpty ? incState.label : prev.label,
          description: incState.description.isNotEmpty
              ? incState.description
              : prev.description,
        );
      } else {
        mergedStates.add(incState);
      }
    }

    final mergedTransitions = List<LifecycleTransition>.from(
      existing.lifecycleTransitions,
    );
    final usedTrIds = <String>{
      for (final t in mergedTransitions) t.id.toLowerCase(),
    };
    for (final incTr in incoming.lifecycleTransitions) {
      final idx = mergedTransitions.indexWhere(
        (t) =>
            t.id.toLowerCase() == incTr.id.toLowerCase() ||
            (t.fromState.toLowerCase() == incTr.fromState.toLowerCase() &&
                t.toState.toLowerCase() == incTr.toState.toLowerCase() &&
                t.trigger.toLowerCase() == incTr.trigger.toLowerCase()),
      );
      if (idx >= 0) {
        final prev = mergedTransitions[idx];
        mergedTransitions[idx] = prev.copyWith(
          trigger: incTr.trigger.isNotEmpty ? incTr.trigger : prev.trigger,
          guardSummary: incTr.guardSummary.isNotEmpty
              ? incTr.guardSummary
              : prev.guardSummary,
        );
      } else {
        var candidate = incTr;
        if (usedTrIds.contains(candidate.id.toLowerCase())) {
          var suffix = 2;
          while (usedTrIds.contains('${incTr.id}_$suffix'.toLowerCase())) {
            suffix++;
          }
          candidate = candidate.copyWith(id: '${incTr.id}_$suffix');
        }
        usedTrIds.add(candidate.id.toLowerCase());
        mergedTransitions.add(candidate);
      }
    }

    return existing.copyWith(
      description: existing.description.isEmpty && incoming.description.isNotEmpty
          ? incoming.description
          : existing.description,
      attributes: mergedAttributes,
      relations: mergedRelations,
      lifecycleStates: mergedStates,
      lifecycleTransitions: mergedTransitions,
    );
  }

  static List<BusinessAttribute> _mergeAttributeListAdditively(
    List<BusinessAttribute> existingList,
    List<BusinessAttribute> incomingList,
    Set<String> usedAttrIds,
  ) {
    final merged = List<BusinessAttribute>.from(existingList);

    for (final incAttr in incomingList) {
      final idx = merged.indexWhere(
        (e) =>
            e.id.toLowerCase() == incAttr.id.toLowerCase() ||
            e.name.toLowerCase() == incAttr.name.toLowerCase(),
      );

      if (idx >= 0) {
        final prev = merged[idx];
        final mergedChildren = _mergeAttributeListAdditively(
          prev.children,
          incAttr.children,
          usedAttrIds,
        );
        final mergedEnumValues = <String>[
          ...prev.enumValues,
          for (final v in incAttr.enumValues)
            if (!prev.enumValues.contains(v)) v,
        ];
        final mergedSchemaConstraints = _mergeSchemaConstraintsAdditively(
          prev.schemaConstraints,
          incAttr.schemaConstraints,
        );
        final effectiveType =
            prev.type == BusinessAttributeType.json && mergedChildren.isNotEmpty
            ? BusinessAttributeType.object
            : prev.type;

        merged[idx] = prev.copyWith(
          type: effectiveType,
          estimatedMaxRows: prev.estimatedMaxRows ?? incAttr.estimatedMaxRows,
          defaultValue: prev.defaultValue ?? incAttr.defaultValue,
          referenceObjectId: prev.referenceObjectId.isNotEmpty
              ? prev.referenceObjectId
              : incAttr.referenceObjectId,
          description: incAttr.description.isNotEmpty
              ? incAttr.description
              : prev.description,
          constraints: incAttr.constraints.isNotEmpty
              ? incAttr.constraints
              : prev.constraints,
          enumValues: mergedEnumValues,
          schemaConstraints: mergedSchemaConstraints,
          children: mergedChildren,
        );
      } else {
        final sanitizedNew = _ensureUniqueAttributeIds(incAttr, usedAttrIds);
        sanitizedNew.validate();
        merged.add(sanitizedNew);
      }
    }

    return merged;
  }

  static JsonSchemaConstraints _mergeSchemaConstraintsAdditively(
    JsonSchemaConstraints existing,
    JsonSchemaConstraints incoming,
  ) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;

    final baseMap = existing.toSchemaMap();
    final incMap = incoming.toSchemaMap();
    final combined = <String, Object?>{...baseMap};

    for (final entry in incMap.entries) {
      if (entry.key == 'examples' &&
          baseMap['examples'] is List &&
          entry.value is List) {
        final existingExamples = List<Object?>.from(
          baseMap['examples'] as List,
        );
        final seenJson = <String>{
          for (final ex in existingExamples) jsonEncode(ex),
        };
        for (final candidate in entry.value as List) {
          if (seenJson.add(jsonEncode(candidate))) {
            existingExamples.add(candidate);
          }
        }
        combined['examples'] = existingExamples;
      } else {
        combined[entry.key] = entry.value;
      }
    }

    try {
      return JsonSchemaConstraints.fromJson(combined);
    } on FormatException {
      return existing;
    }
  }

  static void _collectAttributeIds(
    List<BusinessAttribute> attrs,
    Set<String> sink,
  ) {
    for (final attr in attrs) {
      sink.add(attr.id.toLowerCase());
      _collectAttributeIds(attr.children, sink);
    }
  }

  static BusinessAttribute _ensureUniqueAttributeIds(
    BusinessAttribute attr,
    Set<String> usedAttrIds,
  ) {
    var candidateId = attr.id;
    if (usedAttrIds.contains(candidateId.toLowerCase())) {
      var suffix = 2;
      while (usedAttrIds.contains('${attr.id}_$suffix'.toLowerCase())) {
        suffix++;
      }
      candidateId = '${attr.id}_$suffix';
    }
    usedAttrIds.add(candidateId.toLowerCase());
    final nextChildren = <BusinessAttribute>[
      for (final child in attr.children)
        _ensureUniqueAttributeIds(child, usedAttrIds),
    ];
    return attr.copyWith(id: candidateId, children: nextChildren);
  }

  static BusinessRuleSpec _mergeBusinessRuleAdditively(
    BusinessRuleSpec existing,
    BusinessRuleSpec incoming,
    Map<Object?, Object?> rawMap,
  ) {
    final mergedTargetObjects = <String>[
      ...existing.targetObjectIds,
      for (final id in incoming.targetObjectIds)
        if (!existing.targetObjectIds.contains(id)) id,
    ];
    final mergedTargetAttributes = <String>[
      ...existing.targetAttributes,
      for (final a in incoming.targetAttributes)
        if (!existing.targetAttributes.contains(a)) a,
    ];
    final mergedExamples = <String>[
      ...existing.examples,
      for (final ex in incoming.examples)
        if (!existing.examples.contains(ex)) ex,
    ];

    final hasExplicitTitle =
        rawMap['title'] is String && (rawMap['title'] as String).trim().isNotEmpty;
    final hasExplicitCategory =
        rawMap['category'] is String &&
        (rawMap['category'] as String).trim().isNotEmpty;
    final hasExplicitPriority =
        rawMap['priority'] is String &&
        (rawMap['priority'] as String).trim().isNotEmpty;
    final hasSpecificIncomingCode =
        incoming.code.trim().isNotEmpty &&
        incoming.code.trim().toUpperCase() != 'RG';

    return existing.copyWith(
      code: (existing.code.isEmpty || existing.code.toUpperCase() == 'RG') &&
              hasSpecificIncomingCode
          ? incoming.code
          : existing.code,
      title: hasExplicitTitle ? incoming.title : existing.title,
      category: hasExplicitCategory ? incoming.category : existing.category,
      priority: hasExplicitPriority ? incoming.priority : existing.priority,
      description: incoming.description.isNotEmpty
          ? incoming.description
          : existing.description,
      targetObjectIds: mergedTargetObjects,
      targetAttributes: mergedTargetAttributes,
      trigger: incoming.trigger.isNotEmpty ? incoming.trigger : existing.trigger,
      condition: incoming.condition.isNotEmpty
          ? incoming.condition
          : existing.condition,
      effect: incoming.effect.isNotEmpty ? incoming.effect : existing.effect,
      errorMessage: incoming.errorMessage.isNotEmpty
          ? incoming.errorMessage
          : existing.errorMessage,
      examples: mergedExamples,
      active: rawMap['active'] is bool
          ? rawMap['active'] as bool
          : existing.active,
    );
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
        'path',
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
    if (error is ArgumentError) return error.message?.toString() ?? '$error';
    if (error is StateError) return error.message;
    return error.toString();
  }
}
