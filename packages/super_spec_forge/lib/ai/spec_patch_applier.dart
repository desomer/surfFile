/// Application incrémentale et déterministe des patches JSON IA ([SpecPatchApplier]) sur [SpecForgeProject].
library;

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_vision.dart';

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
