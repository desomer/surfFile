/// Application incrémentale et déterministe des patches JSON IA ([SpecPatchApplier]) sur [SpecForgeProject].
library;

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_lexicon.dart';
import '../models/spec_vision.dart';

/// Entrée individuelle d'un patch IA rejetée lors d'une validation partielle.
@immutable
class SpecPatchRejectedEntry {
  /// Construit une entrée rejetée.
  const SpecPatchRejectedEntry({
    required this.section,
    required this.key,
    required this.reason,
  });

  /// Section du patch (`vision`, `cahierDesCharges`, `businessObjects`, `businessRules`, `coherenceIssues`).
  final String section;

  /// Identifiant, code ou nom de l'élément fautif.
  final String key;

  /// Cause lisible de l'exception rencontrée.
  final String reason;

  @override
  String toString() => '$section[$key] : $reason';
}

/// Résultat immuable d'application d'un patch `"specPatch"`.
@immutable
class SpecPatchResult {
  /// Construit un résultat d'application de patch.
  const SpecPatchResult({required this.project, required this.summary});

  /// Projet mis à jour.
  final SpecForgeProject project;

  /// Résumé lisible en français des sections modifiées.
  final String summary;
}

/// Résultat d'une application tolérante par item conservant les éléments valides.
@immutable
class SpecPartialPatchResult {
  /// Construit un résultat d'application partielle.
  SpecPartialPatchResult({
    required this.project,
    required this.summary,
    List<SpecPatchRejectedEntry> rejectedEntries = const [],
  }) : rejectedEntries = List<SpecPatchRejectedEntry>.unmodifiable(
         rejectedEntries,
       );

  /// Projet mis à jour avec uniquement les éléments valides.
  final SpecForgeProject project;

  /// Résumé des éléments valides retenus.
  final String summary;

  /// Éléments rejetés avec la raison exacte de chaque échec.
  final List<SpecPatchRejectedEntry> rejectedEntries;

  /// Vrai si au moins un changement valide a été conservé.
  bool get hasAppliedChanges => summary.isNotEmpty;
}

/// Fusionne incrémentalement un objet `specPatch` dans un [SpecForgeProject].
abstract final class SpecPatchApplier {
  /// Applique [patch] sur [project] sans muter les instances existantes.
  static SpecPatchResult apply(
    SpecForgeProject project,
    Map<String, Object?> patch,
  ) {
    var next = project;
    final summaries = <String>[];

    final rawName = patch['projectName'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      next = next.copyWith(name: rawName.trim());
      summaries.add('nom du projet');
    }

    if (patch['lexicon'] is Map || patch['removeLexiconTermIds'] is List) {
      final updatedLexicon = _applyLexiconPatch(
        next.lexicon,
        patch['lexicon'],
        removeTermIds: _stringSet(patch['removeLexiconTermIds']),
      );
      if (updatedLexicon != next.lexicon) {
        next = next.copyWith(lexicon: updatedLexicon);
        summaries.add('lexique métier (${updatedLexicon.terms.length} terme(s))');
      }
    }

    if (patch['vision'] is Map || patch['removePersonaIds'] is List) {
      final updatedVision = _applyVisionPatch(
        next.vision,
        patch['vision'],
        removePersonaIds: _stringSet(patch['removePersonaIds']),
      );
      if (updatedVision != next.vision) {
        next = next.copyWith(vision: updatedVision);
        summaries.add('cadrage & acteurs');
      }
    }

    if (patch['cahierDesCharges'] is Map ||
        patch['removeModuleIds'] is List ||
        patch['removeRequirementIds'] is List ||
        patch['removeUseCaseIds'] is List ||
        patch['removeNfrIds'] is List) {
      final updatedCdc = _applyCdcPatch(
        next.cahierDesCharges,
        patch['cahierDesCharges'],
        removeModuleIds: _stringSet(patch['removeModuleIds']),
        removeReqIds: _stringSet(patch['removeRequirementIds']),
        removeUseCaseIds: _stringSet(patch['removeUseCaseIds']),
        removeNfrIds: _stringSet(patch['removeNfrIds']),
      );
      if (updatedCdc != next.cahierDesCharges) {
        next = next.copyWith(cahierDesCharges: updatedCdc);
        summaries.add('cahier des charges');
      }
    }

    if (patch['businessObjects'] is List ||
        patch['removeBusinessObjectIds'] is List) {
      final removeIds = _stringSet(patch['removeBusinessObjectIds']);
      final incoming = patch['businessObjects'] is List
          ? [
              for (final item in patch['businessObjects'] as List)
                BusinessObjectSpec.fromJson(item),
            ]
          : const <BusinessObjectSpec>[];
      final merged = _mergeById<BusinessObjectSpec>(
        existing: next.businessObjects,
        incoming: incoming,
        removeIds: removeIds,
        idOf: (o) => o.id,
      );
      next = next.copyWith(businessObjects: merged);
      summaries.add('${merged.length} objet(s) métier(s)');
    }

    if (patch['businessRules'] is List ||
        patch['removeBusinessRuleIds'] is List) {
      final removeIds = _stringSet(patch['removeBusinessRuleIds']);
      final incoming = patch['businessRules'] is List
          ? [
              for (final item in patch['businessRules'] as List)
                BusinessRuleSpec.fromJson(item),
            ]
          : const <BusinessRuleSpec>[];
      final merged = _mergeById<BusinessRuleSpec>(
        existing: next.businessRules,
        incoming: incoming,
        removeIds: removeIds,
        idOf: (r) => r.id,
      );
      next = next.copyWith(businessRules: merged);
      summaries.add('${merged.length} règle(s) de gestion');
    }

    if (patch['coherenceIssues'] is List) {
      final aiIssues = [
        for (final item in patch['coherenceIssues'] as List)
          SpecCoherenceIssue.fromJson(item).copyWith(source: 'ai'),
      ];
      final localIssues = next.coherenceIssues
          .where((i) => i.source == 'local')
          .toList();
      next = next.copyWith(coherenceIssues: [...localIssues, ...aiIssues]);
      summaries.add('${aiIssues.length} point(s) d’audit IA');
    }

    next.validate();
    return SpecPatchResult(
      project: next,
      summary: summaries.isEmpty
          ? 'Aucune modification structurelle'
          : summaries.join(', '),
    );
  }

  /// Tente d'appliquer chaque section et chaque élément individuellement afin
  /// de conserver un checkpoint sain en cas d'erreur ponctuelle.
  static SpecPartialPatchResult applyPartial(
    SpecForgeProject project,
    Map<String, Object?> patch,
  ) {
    var current = project;
    final appliedSummaries = <String>[];
    final rejected = <SpecPatchRejectedEntry>[];

    final rawName = patch['projectName'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      final candidate = current.copyWith(name: rawName.trim());
      try {
        candidate.validate();
        current = candidate;
        appliedSummaries.add('nom du projet');
      } catch (e) {
        rejected.add(
          SpecPatchRejectedEntry(
            section: 'projectName',
            key: rawName.trim(),
            reason: _reasonOf(e),
          ),
        );
      }
    }

    if (patch['lexicon'] is Map || patch['removeLexiconTermIds'] is List) {
      final rawLexicon = patch['lexicon'];
      if (rawLexicon is Map) {
        final scalarPatch = <String, Object?>{
          for (final entry in rawLexicon.entries)
            if (entry.key is String && entry.key != 'terms')
              entry.key as String: entry.value,
        };
        if (scalarPatch.isNotEmpty || patch['removeLexiconTermIds'] is List) {
          try {
            final res = apply(current, {
              if (scalarPatch.isNotEmpty) 'lexicon': scalarPatch,
              if (patch['removeLexiconTermIds'] is List)
                'removeLexiconTermIds': patch['removeLexiconTermIds'],
            });
            current = res.project;
            appliedSummaries.add('lexique');
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'lexicon',
                key: 'conventions',
                reason: _reasonOf(e),
              ),
            );
          }
        }
        final rawTerms = rawLexicon['terms'];
        if (rawTerms is List) {
          var count = 0;
          for (var i = 0; i < rawTerms.length; i++) {
            final item = rawTerms[i];
            try {
              final res = apply(current, {
                'lexicon': {
                  'terms': [item],
                },
              });
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'lexicon.terms',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count terme(s)');
        }
      }
    }

    if (patch['vision'] is Map || patch['removePersonaIds'] is List) {
      final rawVision = patch['vision'];
      if (rawVision is Map) {
        final scalarPatch = <String, Object?>{
          for (final entry in rawVision.entries)
            if (entry.key is String && entry.key != 'personas')
              entry.key as String: entry.value,
        };
        if (scalarPatch.isNotEmpty || patch['removePersonaIds'] is List) {
          try {
            final res = apply(current, {
              if (scalarPatch.isNotEmpty) 'vision': scalarPatch,
              if (patch['removePersonaIds'] is List)
                'removePersonaIds': patch['removePersonaIds'],
            });
            current = res.project;
            appliedSummaries.add('cadrage');
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'vision',
                key: 'synthèse',
                reason: _reasonOf(e),
              ),
            );
          }
        }
        final rawPersonas = rawVision['personas'];
        if (rawPersonas is List) {
          var count = 0;
          for (var i = 0; i < rawPersonas.length; i++) {
            final item = rawPersonas[i];
            try {
              final res = apply(current, {
                'vision': {
                  'personas': [item],
                },
              });
              current = res.project;
              count++;
            } catch (e) {
              rejected.add(
                SpecPatchRejectedEntry(
                  section: 'vision.personas',
                  key: _labelForItem(item, fallback: '#$i'),
                  reason: _reasonOf(e),
                ),
              );
            }
          }
          if (count > 0) appliedSummaries.add('$count persona(s)');
        }
      }
    }

    if (patch['cahierDesCharges'] is Map ||
        patch['removeModuleIds'] is List ||
        patch['removeRequirementIds'] is List ||
        patch['removeUseCaseIds'] is List ||
        patch['removeNfrIds'] is List) {
      final rawCdc = patch['cahierDesCharges'];
      final cdcMap = rawCdc is Map ? rawCdc : const <Object?, Object?>{};

      void applyListSection(String key, String label) {
        final rawList = cdcMap[key];
        if (rawList is! List) return;
        var count = 0;
        for (var i = 0; i < rawList.length; i++) {
          final item = rawList[i];
          try {
            final res = apply(current, {
              'cahierDesCharges': {
                key: [item],
              },
            });
            current = res.project;
            count++;
          } catch (e) {
            rejected.add(
              SpecPatchRejectedEntry(
                section: 'cahierDesCharges.$key',
                key: _labelForItem(item, fallback: '#$i'),
                reason: _reasonOf(e),
              ),
            );
          }
        }
        if (count > 0) appliedSummaries.add('$count $label');
      }

      applyListSection('modules', 'module(s)');
      applyListSection('functionalRequirements', 'exigence(s)');
      applyListSection('useCases', 'cas d’usage');
      applyListSection('nonFunctionalRequirements', 'ENF');
    }

    if (patch['businessObjects'] is List) {
      final list = patch['businessObjects'] as List;
      var count = 0;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        try {
          final res = apply(current, {
            'businessObjects': [item],
          });
          current = res.project;
          count++;
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'businessObjects',
              key: _labelForItem(item, fallback: '#$i'),
              reason: _reasonOf(e),
            ),
          );
        }
      }
      if (count > 0) appliedSummaries.add('$count objet(s) métier(s)');
    }

    if (patch['businessRules'] is List) {
      final list = patch['businessRules'] as List;
      var count = 0;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        try {
          final res = apply(current, {
            'businessRules': [item],
          });
          current = res.project;
          count++;
        } catch (e) {
          rejected.add(
            SpecPatchRejectedEntry(
              section: 'businessRules',
              key: _labelForItem(item, fallback: '#$i'),
              reason: _reasonOf(e),
            ),
          );
        }
      }
      if (count > 0) appliedSummaries.add('$count règle(s)');
    }

    if (patch['coherenceIssues'] is List) {
      try {
        final res = apply(current, {'coherenceIssues': patch['coherenceIssues']});
        current = res.project;
        appliedSummaries.add('points d’audit');
      } catch (e) {
        rejected.add(
          SpecPatchRejectedEntry(
            section: 'coherenceIssues',
            key: 'audit',
            reason: _reasonOf(e),
          ),
        );
      }
    }

    return SpecPartialPatchResult(
      project: current,
      summary: appliedSummaries.join(', '),
      rejectedEntries: rejected,
    );
  }

  static String _labelForItem(Object? raw, {required String fallback}) {
    if (raw is Map) {
      for (final key in const ['code', 'id', 'technicalName', 'name', 'title']) {
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

  static SpecLexicon _applyLexiconPatch(
    SpecLexicon current,
    Object? rawLexicon, {
    required Set<String> removeTermIds,
  }) {
    final map = rawLexicon is Map ? rawLexicon : const <Object?, Object?>{};
    final incomingTerms = map['terms'] is List
        ? [
            for (final item in map['terms'] as List) LexiconTerm.fromJson(item),
          ]
        : const <LexiconTerm>[];
    final terms = _mergeById<LexiconTerm>(
      existing: current.terms,
      incoming: incomingTerms,
      removeIds: removeTermIds,
      idOf: (t) => t.id,
    );
    return current.copyWith(
      terms: terms,
      ambiguousTerms: map.containsKey('ambiguousTerms')
          ? _stringList(map['ambiguousTerms'])
          : null,
      conventions: map.containsKey('conventions')
          ? _stringList(map['conventions'])
          : null,
    );
  }

  static SpecVision _applyVisionPatch(
    SpecVision current,
    Object? rawVision, {
    required Set<String> removePersonaIds,
  }) {
    final map = rawVision is Map ? rawVision : const <Object?, Object?>{};
    final incomingPersonas = map['personas'] is List
        ? [
            for (final item in map['personas'] as List)
              SpecPersona.fromJson(item),
          ]
        : const <SpecPersona>[];
    final personas = _mergeById<SpecPersona>(
      existing: current.personas,
      incoming: incomingPersonas,
      removeIds: removePersonaIds,
      idOf: (p) => p.id,
    );

    return current.copyWith(
      ideaSummary: _nonEmptyStringOrNull(map['ideaSummary']),
      problemStatement: _nonEmptyStringOrNull(map['problemStatement']),
      valueProposition: _nonEmptyStringOrNull(map['valueProposition']),
      objectives: map.containsKey('objectives')
          ? _stringList(map['objectives'])
          : null,
      personas: personas,
      constraints: map.containsKey('constraints')
          ? _stringList(map['constraints'])
          : null,
      outOfScope: map.containsKey('outOfScope')
          ? _stringList(map['outOfScope'])
          : null,
    );
  }

  static SpecCahierDesCharges _applyCdcPatch(
    SpecCahierDesCharges current,
    Object? rawCdc, {
    required Set<String> removeModuleIds,
    required Set<String> removeReqIds,
    required Set<String> removeUseCaseIds,
    required Set<String> removeNfrIds,
  }) {
    final map = rawCdc is Map ? rawCdc : const <Object?, Object?>{};

    final modules = _mergeById<SpecModule>(
      existing: current.modules,
      incoming: map['modules'] is List
          ? [for (final item in map['modules'] as List) SpecModule.fromJson(item)]
          : const <SpecModule>[],
      removeIds: removeModuleIds,
      idOf: (m) => m.id,
    );

    final reqs = _mergeById<FunctionalRequirement>(
      existing: current.functionalRequirements,
      incoming: map['functionalRequirements'] is List
          ? [
              for (final item in map['functionalRequirements'] as List)
                FunctionalRequirement.fromJson(item),
            ]
          : const <FunctionalRequirement>[],
      removeIds: removeReqIds,
      idOf: (r) => r.id,
    );

    final useCases = _mergeById<UseCaseSpec>(
      existing: current.useCases,
      incoming: map['useCases'] is List
          ? [
              for (final item in map['useCases'] as List)
                UseCaseSpec.fromJson(item),
            ]
          : const <UseCaseSpec>[],
      removeIds: removeUseCaseIds,
      idOf: (u) => u.id,
    );

    final nfrs = _mergeById<NonFunctionalRequirement>(
      existing: current.nonFunctionalRequirements,
      incoming: map['nonFunctionalRequirements'] is List
          ? [
              for (final item in map['nonFunctionalRequirements'] as List)
                NonFunctionalRequirement.fromJson(item),
            ]
          : const <NonFunctionalRequirement>[],
      removeIds: removeNfrIds,
      idOf: (n) => n.id,
    );

    return current.copyWith(
      modules: modules,
      functionalRequirements: reqs,
      useCases: useCases,
      nonFunctionalRequirements: nfrs,
    );
  }

  static List<T> _mergeById<T>({
    required List<T> existing,
    required List<T> incoming,
    required Set<String> removeIds,
    required String Function(T item) idOf,
  }) {
    final result = <T>[
      for (final item in existing)
        if (!removeIds.contains(idOf(item))) item,
    ];
    for (final item in incoming) {
      final id = idOf(item);
      if (removeIds.contains(id)) continue;
      final index = result.indexWhere((e) => idOf(e) == id);
      if (index >= 0) {
        result[index] = item;
      } else {
        result.add(item);
      }
    }
    return result;
  }

  static Set<String> _stringSet(Object? raw) {
    if (raw is! List) return const <String>{};
    return {
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    };
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return [
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }

  static String? _nonEmptyStringOrNull(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
