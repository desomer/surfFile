/// Générateur des sections Markdown d'évolution inter-itérations (`vN → vN+1`),
/// de comparatif ciblé avec le jalon précédent ([DomainIterationSnapshot]) et
/// de consignes de migration non-régressive par couche et rôle hexagonal
/// ([PromptEvolutionDecision], [PromptEvolutionSections]).
library;

import 'package:flutter/foundation.dart';

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_spec.dart';
import '../../../models/domain_iteration_snapshot.dart';
import '../../../models/domain_layer_spec.dart';
import '../../../models/usecase_orchestration_spec.dart';
import '../../../models/value_object_spec.dart';
import '../../design_evolution_analyzer.dart';
import 'model_prompt_context.dart';
import 'prompt_generator_models.dart';

/// Décision résolue d'inclusion ou d'omission du bloc d'évolution inter-itérations
/// dans un prompt généré par `BuildHexaPromptGenerator`.
@immutable
class PromptEvolutionDecision {
  /// Crée une décision d'évolution explicite.
  const PromptEvolutionDecision({
    required this.isEvolutionDelta,
    this.baseline,
    this.baselineLabel,
    this.baselineVersion,
    this.currentVersion = '',
    this.changeBump = SemVerBump.none,
    this.artifactReport,
    this.evolutionReport,
  });

  /// Décision neutre sans bloc d'évolution (`fullFromScratch` ou absence de jalon).
  const PromptEvolutionDecision.none()
    : isEvolutionDelta = false,
      baseline = null,
      baselineLabel = null,
      baselineVersion = null,
      currentVersion = '',
      changeBump = SemVerBump.none,
      artifactReport = null,
      evolutionReport = null;

  /// Indique si le prompt doit intégrer la section d'évolution et les métadonnées YAML associées.
  final bool isEvolutionDelta;

  /// Jalon d'itération de référence utilisé pour la comparaison.
  final DomainIterationSnapshot? baseline;

  /// Libellé lisible du jalon d'itération (ex. `Itération 1 — MVP`).
  final String? baselineLabel;

  /// Version sémantique précédente de l'artefact dans le jalon (`null` si nouveau ou autonome).
  final String? baselineVersion;

  /// Version sémantique cible courante de l'artefact.
  final String currentVersion;

  /// Niveau d'incrément SemVer effectif associé au delta.
  final SemVerBump changeBump;

  /// Rapport individuel d'évolution de l'artefact ciblé, s'il existe.
  final ArtifactEvolutionReport? artifactReport;

  /// Rapport d'évolution complet du domaine fonctionnel.
  final DomainEvolutionReport? evolutionReport;
}

/// Assemble les décisions et sections Markdown `Évolution Inter-Itérations & Consignes de Migration`.
abstract final class PromptEvolutionSections {
  /// Résout la décision d'évolution pour un artefact de conception ([item]).
  static PromptEvolutionDecision resolveArtifactDecision({
    required BuildPromptGenerationMode mode,
    required BuildDesignItem item,
    required String currentVersion,
    DomainEvolutionReport? evolutionReport,
  }) {
    final baseline = evolutionReport?.baseline;
    if (mode == BuildPromptGenerationMode.fullFromScratch || baseline == null) {
      return const PromptEvolutionDecision.none();
    }

    final artifactKind = switch (item.kind) {
      BuildDesignItemKind.valueObject => DesignArtifactKind.valueObject,
      BuildDesignItemKind.model => DesignArtifactKind.model,
      BuildDesignItemKind.useCase => DesignArtifactKind.useCase,
      BuildDesignItemKind.saga => DesignArtifactKind.saga,
    };
    final report =
        evolutionReport?.reportFor(artifactKind, item.id) ?? item.evolution;

    switch (mode) {
      case BuildPromptGenerationMode.fullFromScratch:
        return const PromptEvolutionDecision.none();
      case BuildPromptGenerationMode.autoByBaseline:
        final existedInBaseline = report?.baselineVersion != null;
        final isModifiedOrImpacted =
            report != null &&
            (report.state == ArtifactEvolutionState.modified ||
                report.state == ArtifactEvolutionState.impacted);
        if (!existedInBaseline || !isModifiedOrImpacted) {
          return const PromptEvolutionDecision.none();
        }
        return PromptEvolutionDecision(
          isEvolutionDelta: true,
          baseline: baseline,
          baselineLabel: baseline.label,
          baselineVersion: report.baselineVersion,
          currentVersion: currentVersion,
          changeBump: report.effectiveBump,
          artifactReport: report,
          evolutionReport: evolutionReport,
        );
      case BuildPromptGenerationMode.evolutionDelta:
        final prevVer = report?.baselineVersion;
        final effectiveBump = prevVer != null
            ? (report?.effectiveBump ?? SemVerBump.none)
            : SemVerBump.minor;
        return PromptEvolutionDecision(
          isEvolutionDelta: true,
          baseline: baseline,
          baselineLabel: baseline.label,
          baselineVersion: prevVer,
          currentVersion: currentVersion,
          changeBump: effectiveBump,
          artifactReport: report,
          evolutionReport: evolutionReport,
        );
    }
  }

  /// Résout la décision d'évolution pour un prompt autonome de niveau domaine
  /// (`outbound`, `inbound`, `checkIntegration`).
  static PromptEvolutionDecision resolveDomainAdapterDecision({
    required BuildPromptGenerationMode mode,
    DomainEvolutionReport? evolutionReport,
  }) {
    final baseline = evolutionReport?.baseline;
    if (mode == BuildPromptGenerationMode.fullFromScratch ||
        baseline == null ||
        evolutionReport == null) {
      return const PromptEvolutionDecision.none();
    }

    var maxBump = SemVerBump.none;
    for (final report in evolutionReport.allCurrentReports) {
      maxBump = maxBump.max(report.effectiveBump);
    }
    if (evolutionReport.removedArtifacts.isNotEmpty) {
      maxBump = maxBump.max(SemVerBump.major);
    }

    if (mode == BuildPromptGenerationMode.autoByBaseline) {
      final hasDelta =
          evolutionReport.totalActionableCount > 0 ||
          evolutionReport.removedCount > 0;
      if (!hasDelta) {
        return const PromptEvolutionDecision.none();
      }
      return PromptEvolutionDecision(
        isEvolutionDelta: true,
        baseline: baseline,
        baselineLabel: baseline.label,
        currentVersion: '1.0.0',
        changeBump: maxBump.hasChange ? maxBump : SemVerBump.minor,
        evolutionReport: evolutionReport,
      );
    }

    return PromptEvolutionDecision(
      isEvolutionDelta: true,
      baseline: baseline,
      baselineLabel: baseline.label,
      currentVersion: '1.0.0',
      changeBump: maxBump,
      evolutionReport: evolutionReport,
    );
  }

  /// Écrit la section d'évolution inter-itérations d'un [ValueObjectSpec].
  static void writeValueObjectEvolutionSection(
    StringBuffer buf, {
    required PromptEvolutionDecision decision,
    required ValueObjectSpec currentVo,
    required BuildHexaPromptRole role,
  }) {
    final baseline = decision.baseline;
    if (!decision.isEvolutionDelta || baseline == null) return;

    final baseArtifact = _findBaselineVo(baseline, currentVo);
    _writeArtifactHeaderAndQualification(
      buf,
      decision: decision,
      currentVersion: currentVo.version,
    );
    _writeChangesAndImpacts(
      buf,
      report: decision.artifactReport,
      evolutionReport: decision.evolutionReport,
      referencedVoIds: currentVo.referencedValueObjectIds,
    );
    if (baseArtifact != null) {
      _writeValueObjectBaselineComparison(buf, baseArtifact.spec, currentVo);
    }
    _writeMigrationGuidelines(
      buf,
      baselineLabel: baseline.label,
      section: BuildTechStackSection.domain,
      role: role,
      isAddedArtifact: baseArtifact == null,
      removedArtifacts: decision.evolutionReport?.removedArtifacts ?? const [],
    );
    buf.writeln();
  }

  /// Écrit la section d'évolution inter-itérations d'un modèle/contrat ([ModelPromptContext]).
  static void writeModelEvolutionSection(
    StringBuffer buf, {
    required PromptEvolutionDecision decision,
    required ModelPromptContext ctx,
    required BuildTechStackSection section,
    required BuildHexaPromptRole role,
  }) {
    final baseline = decision.baseline;
    if (!decision.isEvolutionDelta || baseline == null) return;

    final baseModel = baseline.models[ctx.item.id];
    _writeArtifactHeaderAndQualification(
      buf,
      decision: decision,
      currentVersion: ctx.detail.version,
    );
    _writeChangesAndImpacts(
      buf,
      report: decision.artifactReport,
      evolutionReport: decision.evolutionReport,
      referencedVoIds: {
        for (final r in ctx.referencedValueObjects) r.spec.id,
      },
    );
    if (baseModel != null) {
      _writeModelBaselineComparison(
        buf,
        previous: baseModel,
        ctx: ctx,
        includePersistenceDetails: section == BuildTechStackSection.persistence,
      );
    }
    _writeMigrationGuidelines(
      buf,
      baselineLabel: baseline.label,
      section: section,
      role: role,
      isAddedArtifact: baseModel == null,
      removedArtifacts: decision.evolutionReport?.removedArtifacts ?? const [],
    );
    buf.writeln();
  }

  /// Écrit la section d'évolution inter-itérations d'un [ApplicationUseCaseSpec].
  static void writeUseCaseEvolutionSection(
    StringBuffer buf, {
    required PromptEvolutionDecision decision,
    required ApplicationUseCaseSpec currentUseCase,
    required BuildHexaPromptRole role,
  }) {
    final baseline = decision.baseline;
    if (!decision.isEvolutionDelta || baseline == null) return;

    final baseUc = baseline.useCases[currentUseCase.id];
    _writeArtifactHeaderAndQualification(
      buf,
      decision: decision,
      currentVersion: currentUseCase.version,
    );
    _writeChangesAndImpacts(
      buf,
      report: decision.artifactReport,
      evolutionReport: decision.evolutionReport,
    );
    if (baseUc != null) {
      _writeUseCaseBaselineComparison(buf, baseUc, currentUseCase);
    }
    _writeMigrationGuidelines(
      buf,
      baselineLabel: baseline.label,
      section: BuildTechStackSection.useCaseSaga,
      role: role,
      isAddedArtifact: baseUc == null,
      removedArtifacts: decision.evolutionReport?.removedArtifacts ?? const [],
    );
    buf.writeln();
  }

  /// Écrit la section d'évolution inter-itérations d'une [OrchestrationSagaSpec].
  static void writeSagaEvolutionSection(
    StringBuffer buf, {
    required PromptEvolutionDecision decision,
    required OrchestrationSagaSpec currentSaga,
    required BuildHexaPromptRole role,
  }) {
    final baseline = decision.baseline;
    if (!decision.isEvolutionDelta || baseline == null) return;

    final baseSaga = baseline.sagas[currentSaga.id];
    _writeArtifactHeaderAndQualification(
      buf,
      decision: decision,
      currentVersion: currentSaga.version,
    );
    _writeChangesAndImpacts(
      buf,
      report: decision.artifactReport,
      evolutionReport: decision.evolutionReport,
    );
    if (baseSaga != null) {
      _writeSagaBaselineComparison(buf, baseSaga, currentSaga);
    }
    _writeMigrationGuidelines(
      buf,
      baselineLabel: baseline.label,
      section: BuildTechStackSection.useCaseSaga,
      role: role,
      isAddedArtifact: baseSaga == null,
      removedArtifacts: decision.evolutionReport?.removedArtifacts ?? const [],
    );
    buf.writeln();
  }

  /// Écrit la section d'évolution inter-itérations d'un prompt autonome de
  /// niveau domaine (`outbound`, `inbound`, `checkIntegration`).
  static void writeDomainAdapterEvolutionSection(
    StringBuffer buf, {
    required PromptEvolutionDecision decision,
    required BuildTechStackSection section,
    required BuildHexaPromptRole role,
  }) {
    final baseline = decision.baseline;
    final report = decision.evolutionReport;
    if (!decision.isEvolutionDelta || baseline == null || report == null) {
      return;
    }

    buf
      ..writeln(
        '## Évolution Inter-Itérations (${baseline.label} → État courant) & Consignes de Migration',
      )
      ..writeln(
        '### Qualification de l’évolution du domaine',
      )
      ..writeln(
        '- **Jalon de référence** : `${baseline.label}` (Itération #${baseline.iterationNumber})',
      )
      ..writeln(
        '- **Impact SemVer consolidé** : **${decision.changeBump.label}**',
      )
      ..writeln(
        '- **Synthèse du périmètre évolué** : '
        '${report.addedCount} nouveau(x), '
        '${report.modifiedCount} modifié(s), '
        '${report.impactedCount} impacté(s), '
        '${report.removedCount} supprimé(s).',
      );

    final actionable = report.allCurrentReports
        .where((r) => r.state.isActionable)
        .toList(growable: false);
    if (actionable.isNotEmpty) {
      buf.writeln('\n### Artefacts créés, modifiés ou impactés à répercuter');
      for (final item in actionable) {
        final versionTransition = item.baselineVersion != null
            ? 'v${item.baselineVersion} → v${item.currentVersion}'
            : 'v${item.currentVersion} (nouveau)';
        buf.writeln(
          '- **[${item.kind.shortLabel} · ${item.state.label} · ${item.effectiveBump.shortLabel}]** '
          '`${item.name}` ($versionTransition)',
        );
        for (final change in item.directChanges.take(4)) {
          buf.writeln('  - `[${change.category}]` ${change.summary}');
        }
        for (final cause in item.impactedBy.take(3)) {
          buf.writeln('  - Impact amont : $cause');
        }
      }
    }

    if (report.removedArtifacts.isNotEmpty) {
      buf.writeln(
        '\n### Artefacts supprimés depuis `${baseline.label}` à décommissionner (`removedArtifacts`)',
      );
      for (final removed in report.removedArtifacts) {
        buf.writeln(
          '- **[${removed.kind.shortLabel} supprimé]** `${removed.name}` '
          '(ancienne version `v${removed.baselineVersion ?? removed.currentVersion}`) : '
          'retirer ou déprécier proprement ses routes, DTOs, mappers, adaptateurs, bindings DI et tests associés.',
        );
      }
    }

    buf.writeln();
    _writeMigrationGuidelines(
      buf,
      baselineLabel: baseline.label,
      section: section,
      role: role,
      isAddedArtifact: false,
      removedArtifacts: report.removedArtifacts,
    );
    buf.writeln();
  }

  static SnapshotValueObjectArtifact? _findBaselineVo(
    DomainIterationSnapshot baseline,
    ValueObjectSpec currentVo,
  ) {
    final byId = baseline.valueObjects[currentVo.id];
    if (byId != null) return byId;
    final lowerTech = currentVo.technicalName.toLowerCase();
    for (final candidate in baseline.valueObjects.values) {
      if (candidate.spec.technicalName.toLowerCase() == lowerTech) {
        return candidate;
      }
    }
    return null;
  }

  static void _writeArtifactHeaderAndQualification(
    StringBuffer buf, {
    required PromptEvolutionDecision decision,
    required String currentVersion,
  }) {
    final baseline = decision.baseline!;
    final prevVer = decision.baselineVersion;
    final report = decision.artifactReport;
    final state = report?.state ??
        (prevVer == null
            ? ArtifactEvolutionState.added
            : ArtifactEvolutionState.unchanged);

    if (prevVer != null) {
      buf.writeln(
        '## Évolution Inter-Itérations (${baseline.label} : v$prevVer → v$currentVersion) & Consignes de Migration',
      );
    } else {
      buf.writeln(
        '## Évolution Inter-Itérations (${baseline.label} : nouvel artefact → v$currentVersion) & Consignes de Migration',
      );
    }

    final String qualificationLabel;
    if (state == ArtifactEvolutionState.impacted &&
        (report?.directChanges.isEmpty ?? true)) {
      qualificationLabel =
          'Impact transitif (${decision.changeBump.label})';
    } else if (state == ArtifactEvolutionState.added && prevVer == null) {
      qualificationLabel =
          'Nouvel artefact post-jalon (${SemVerBump.minor.label})';
    } else if (state == ArtifactEvolutionState.unchanged) {
      qualificationLabel = 'Conforme au jalon (aucune divergence structurelle)';
    } else {
      qualificationLabel = decision.changeBump.label;
    }

    buf
      ..writeln('### Qualification de l’évolution')
      ..writeln(
        '- **Jalon de référence** : `${baseline.label}` (Itération #${baseline.iterationNumber})',
      )
      ..writeln('- **Statut d’évolution** : `${state.label}`')
      ..writeln('- **Qualification d’impact** : **$qualificationLabel**');
    if (prevVer != null) {
      final recSuffix = (report != null && report.needsVersionBump)
          ? ' *(incrément SemVer recommandé : `v${report.recommendedVersion}`)*'
          : '';
      buf.writeln(
        '- **Transition de version** : `v$prevVer` → `v$currentVersion`$recSuffix',
      );
    } else {
      buf.writeln(
        '- **Introduction** : élément créé après la capture du jalon `${baseline.label}` (version initiale `v$currentVersion`), à intégrer sans régression dans le codebase existant.',
      );
    }
  }

  static void _writeChangesAndImpacts(
    StringBuffer buf, {
    required ArtifactEvolutionReport? report,
    required DomainEvolutionReport? evolutionReport,
    Set<String> referencedVoIds = const <String>{},
  }) {
    if (report == null) return;

    if (report.directChanges.isNotEmpty) {
      final grouped = <String, List<ArtifactChangeEntry>>{};
      for (final entry in report.directChanges) {
        grouped.putIfAbsent(entry.category, () => <ArtifactChangeEntry>[]).add(
          entry,
        );
      }
      buf.writeln('\n### Changelog structuré (`directChanges`)');
      for (final group in grouped.entries) {
        buf.writeln('- **${group.key}** :');
        for (final entry in group.value) {
          buf.writeln('  - `[${entry.impact.label}]` ${entry.summary}');
        }
      }
    } else if (report.state == ArtifactEvolutionState.unchanged) {
      buf.writeln(
        '\n### Changelog structuré\n- Aucune modification directe détectée depuis le jalon de référence : vérifie la stricte conformité de l’implémentation existante.',
      );
    }

    if (report.impactedBy.isNotEmpty) {
      buf.writeln('\n### Dépendances amont modifiées (`impactedBy`)');
      for (final cause in report.impactedBy) {
        buf.writeln('- $cause');
      }
      if (evolutionReport != null) {
        final seenUpstreamVoIds = <String>{};
        for (final voReport in evolutionReport.valueObjects.values) {
          if (!voReport.state.isActionable &&
              voReport.state != ArtifactEvolutionState.removed) {
            continue;
          }
          final matchesRef = referencedVoIds.contains(voReport.id) ||
              report.impactedBy.any(
                (cause) => cause.toLowerCase().contains(
                  voReport.name.toLowerCase(),
                ),
              );
          if (matchesRef && seenUpstreamVoIds.add(voReport.id)) {
            if (voReport.directChanges.isNotEmpty) {
              final prev = voReport.baselineVersion ?? '?';
              buf.writeln(
                '  - Détail Value Object `${voReport.name}` (`v$prev` → `v${voReport.currentVersion}`) : '
                '${voReport.directChanges.map((c) => c.summary).join(' ; ')}',
              );
            }
          }
        }
      }
    }
  }

  static void _writeValueObjectBaselineComparison(
    StringBuffer buf,
    ValueObjectSpec previous,
    ValueObjectSpec current,
  ) {
    final notes = <String>[];
    if (previous.technicalName != current.technicalName) {
      notes.add(
        'Renommage technique : `${previous.technicalName}` → `${current.technicalName}`.',
      );
    }
    if (previous.kind != current.kind) {
      notes.add(
        'Changement de forme : `${previous.kind.label}` → `${current.kind.label}`.',
      );
    } else if (current.isScalar) {
      if (previous.primitiveType != current.primitiveType) {
        notes.add(
          'Type primitif modifié : `${previous.primitiveType.dslKeyword}` → `${current.primitiveType.dslKeyword}`.',
        );
      }
      final removedEnums = previous.enumValues
          .where((v) => !current.enumValues.contains(v))
          .toList();
      final addedEnums = current.enumValues
          .where((v) => !previous.enumValues.contains(v))
          .toList();
      if (removedEnums.isNotEmpty) {
        notes.add(
          'Valeurs enum retirées du jalon : `${removedEnums.join('`, `')}`.',
        );
      }
      if (addedEnums.isNotEmpty) {
        notes.add(
          'Nouvelles valeurs enum ajoutées : `${addedEnums.join('`, `')}`.',
        );
      }
      if (!listEquals(previous.normalizationRules, current.normalizationRules)) {
        notes.add(
          'Pipeline de normalisation : `[${previous.normalizationRules.join(', ')}]` → `[${current.normalizationRules.join(', ')}]`.',
        );
      }
      final prevSc = previous.schemaConstraints.formatSummary();
      final currSc = current.schemaConstraints.formatSummary();
      if (prevSc != currSc) {
        notes.add(
          'Contraintes JSON Schema : `${prevSc.isEmpty ? 'aucune' : prevSc}` → `${currSc.isEmpty ? 'aucune' : currSc}`.',
        );
      }
    } else {
      _collectAttributeDiffNotes(
        notes,
        previous.fields,
        current.fields,
        noun: 'Champ composite',
      );
      final removedRules = previous.crossFieldRules
          .where((r) => !current.crossFieldRules.contains(r))
          .toList();
      if (removedRules.isNotEmpty) {
        notes.add(
          'Règle(s) inter-champs retirée(s) ou remplacée(s) : ${removedRules.join(' ; ')}.',
        );
      }
    }

    if (notes.isNotEmpty) {
      buf.writeln('\n### Comparatif ciblé avec le jalon précédent');
      for (final n in notes) {
        buf.writeln('- $n');
      }
    }
  }

  static void _writeModelBaselineComparison(
    StringBuffer buf, {
    required SnapshotModelArtifact previous,
    required ModelPromptContext ctx,
    required bool includePersistenceDetails,
  }) {
    final notes = <String>[];
    final currentObj = ctx.objectSpec;
    if (previous.name != ctx.item.name ||
        previous.objectSpec.technicalName != currentObj.technicalName) {
      notes.add(
        'Identifiant modèle : `${previous.objectSpec.technicalName}` → `${currentObj.technicalName}`.',
      );
    }
    if (previous.dslType != ctx.dslType) {
      notes.add('Type DSL : `${previous.dslType}` → `${ctx.dslType}`.');
    }

    _collectAttributeDiffNotes(
      notes,
      previous.objectSpec.attributes,
      currentObj.attributes,
      noun: 'Attribut',
    );

    final prevRelsByName = <String, BusinessRelation>{
      for (final r in previous.objectSpec.relations) r.name: r,
    };
    final currRelsByName = <String, BusinessRelation>{
      for (final r in currentObj.relations) r.name: r,
    };
    for (final prevRel in previous.objectSpec.relations) {
      final currRel = currRelsByName[prevRel.name];
      if (currRel == null) {
        notes.add(
          'Relation supprimée depuis le jalon : `${prevRel.name}` (${prevRel.cardinality.name}).',
        );
      } else if (prevRel.cardinality != currRel.cardinality ||
          prevRel.required != currRel.required) {
        notes.add(
          'Relation modifiée `${prevRel.name}` : `${prevRel.cardinality.name}${prevRel.required ? '!' : ''}` → `${currRel.cardinality.name}${currRel.required ? '!' : ''}`.',
        );
      }
    }
    for (final currRel in currentObj.relations) {
      if (!prevRelsByName.containsKey(currRel.name)) {
        notes.add(
          'Nouvelle relation ajoutée : `${currRel.name}` (${currRel.cardinality.name}${currRel.required ? ', requise' : ''}).',
        );
      }
    }

    _collectDomainLayerDiffNotes(
      notes,
      previous.domainLayerSpec,
      ctx.layerSpec,
      includePersistenceDetails: includePersistenceDetails,
    );

    if (notes.isNotEmpty) {
      buf.writeln('\n### Comparatif ciblé avec le jalon précédent');
      for (final n in notes) {
        buf.writeln('- $n');
      }
    }
  }

  static void _collectAttributeDiffNotes(
    List<String> notes,
    List<BusinessAttribute> previousAttrs,
    List<BusinessAttribute> currentAttrs, {
    required String noun,
  }) {
    final prevById = <String, BusinessAttribute>{
      for (final a in previousAttrs) a.id: a,
    };
    final prevByName = <String, BusinessAttribute>{
      for (final a in previousAttrs) a.name: a,
    };
    final matchedPrevIds = <String>{};

    String describeType(BusinessAttribute a) {
      final base = a.type == BusinessAttributeType.valueObject
          ? 'VO:${a.valueObjectId}'
          : (a.type == BusinessAttributeType.reference
                ? 'ref:${a.referenceObjectId}'
                : a.type.dslKeyword);
      final arr = a.isArray ? '[]' : '';
      final req = a.required ? '!' : (a.nullable ? '?' : '');
      return '$base$arr$req';
    }

    for (final curr in currentAttrs) {
      final prev = prevById[curr.id] ?? prevByName[curr.name];
      if (prev == null) {
        notes.add(
          '$noun ajouté : `${curr.name}` (`${describeType(curr)}`${curr.required ? ', obligatoire' : ', optionnel'}).',
        );
        continue;
      }
      matchedPrevIds.add(prev.id);
      if (prev.name != curr.name) {
        notes.add('$noun renommé : `${prev.name}` → `${curr.name}`.');
      }
      final prevSig = describeType(prev);
      final currSig = describeType(curr);
      if (prevSig != currSig) {
        notes.add('$noun retypé/modifié `${curr.name}` : `$prevSig` → `$currSig`.');
      }
    }

    for (final prev in previousAttrs) {
      if (!matchedPrevIds.contains(prev.id) &&
          !currentAttrs.any((c) => c.name == prev.name)) {
        notes.add(
          '$noun supprimé depuis le jalon : `${prev.name}` (`${describeType(prev)}`).',
        );
      }
    }
  }

  static void _collectDomainLayerDiffNotes(
    List<String> notes,
    HexagonalDomainLayerSpec previous,
    HexagonalDomainLayerSpec current, {
    required bool includePersistenceDetails,
  }) {
    final prevStateSigs = {
      for (final s in previous.stateChanges) s.effectiveMethodSignature,
    };
    final currStateSigs = {
      for (final s in current.stateChanges) s.effectiveMethodSignature,
    };
    for (final removed in prevStateSigs.difference(currStateSigs)) {
      notes.add('Mutation Domain retirée ou renommée : `$removed`.');
    }
    for (final added in currStateSigs.difference(prevStateSigs)) {
      notes.add('Mutation Domain ajoutée ou mise à jour : `$added`.');
    }

    final prevFactorySigs = {
      for (final f in previous.factories) f.effectiveMethodSignature,
    };
    final currFactorySigs = {
      for (final f in current.factories) f.effectiveMethodSignature,
    };
    for (final removed in prevFactorySigs.difference(currFactorySigs)) {
      notes.add('Fabrique Domain retirée ou renommée : `$removed`.');
    }
    for (final added in currFactorySigs.difference(prevFactorySigs)) {
      notes.add('Fabrique Domain ajoutée ou mise à jour : `$added`.');
    }

    if (includePersistenceDetails) {
      final prevPol = previous.persistencePolicy;
      final currPol = current.persistencePolicy;
      if (prevPol.repositoryPortName != currPol.repositoryPortName &&
          prevPol.repositoryPortName.trim().isNotEmpty) {
        notes.add(
          'Port Repository renommé : `${prevPol.repositoryPortName}` → `${currPol.repositoryPortName}`.',
        );
      }
      if (prevPol.concurrencyStrategy != currPol.concurrencyStrategy) {
        notes.add(
          'Stratégie de concurrence modifiée : `${prevPol.concurrencyStrategy.label}` → `${currPol.concurrencyStrategy.label}`.',
        );
      }
      if (prevPol.deletionStrategy != currPol.deletionStrategy) {
        notes.add(
          'Politique de suppression modifiée : `${prevPol.deletionStrategy.label}` → `${currPol.deletionStrategy.label}`.',
        );
      }
    }
  }

  static void _writeUseCaseBaselineComparison(
    StringBuffer buf,
    ApplicationUseCaseSpec previous,
    ApplicationUseCaseSpec current,
  ) {
    final notes = <String>[];
    if (previous.inboundPort.trim() != current.inboundPort.trim()) {
      notes.add(
        'Port entrant modifié : `${previous.inboundPort}` → `${current.inboundPort}`.',
      );
    }
    if (previous.cqrsType != current.cqrsType) {
      notes.add(
        'Qualification CQRS modifiée : `${previous.cqrsType.label}` → `${current.cqrsType.label}`.',
      );
    }
    if (previous.targetAggregate.trim() != current.targetAggregate.trim()) {
      notes.add(
        'Agrégat cible modifié : `${previous.targetAggregate}` → `${current.targetAggregate}`.',
      );
    }

    void diffUcFields(
      String label,
      List<UseCaseFieldSpec> prevList,
      List<UseCaseFieldSpec> currList,
    ) {
      final prevMap = <String, UseCaseFieldSpec>{
        for (final f in prevList) f.name: f,
      };
      final currMap = <String, UseCaseFieldSpec>{
        for (final f in currList) f.name: f,
      };
      for (final f in prevList) {
        final curr = currMap[f.name];
        if (curr == null) {
          notes.add('Champ $label supprimé : `${f.name}` (`${f.type}`).');
        } else if (f.type != curr.type ||
            f.effectiveRequired != curr.effectiveRequired ||
            f.effectiveIsArray != curr.effectiveIsArray) {
          notes.add(
            'Champ $label modifié `${f.name}` : `${f.type}${f.effectiveIsArray ? '[]' : ''}${f.effectiveRequired ? '!' : '?'}` → `${curr.type}${curr.effectiveIsArray ? '[]' : ''}${curr.effectiveRequired ? '!' : '?'}`.',
          );
        }
      }
      for (final f in currList) {
        if (!prevMap.containsKey(f.name)) {
          notes.add(
            'Champ $label ajouté : `${f.name}` (`${f.type}${f.effectiveRequired ? ', requis' : ', optionnel'}`).',
          );
        }
      }
    }

    diffUcFields('Input', previous.triggerInputs, current.triggerInputs);
    diffUcFields('Output', previous.outputs, current.outputs);

    final removedPorts = previous.outboundPorts
        .where((p) => !current.outboundPorts.contains(p))
        .toList();
    final addedPorts = current.outboundPorts
        .where((p) => !previous.outboundPorts.contains(p))
        .toList();
    if (removedPorts.isNotEmpty) {
      notes.add('Ports sortants retirés : `${removedPorts.join('`, `')}`.');
    }
    if (addedPorts.isNotEmpty) {
      notes.add('Ports sortants ajoutés : `${addedPorts.join('`, `')}`.');
    }

    if (notes.isNotEmpty) {
      buf.writeln('\n### Comparatif ciblé avec le jalon précédent');
      for (final n in notes) {
        buf.writeln('- $n');
      }
    }
  }

  static void _writeSagaBaselineComparison(
    StringBuffer buf,
    OrchestrationSagaSpec previous,
    OrchestrationSagaSpec current,
  ) {
    final notes = <String>[];
    if (previous.coordinationMode != current.coordinationMode) {
      notes.add(
        'Mode de coordination modifié : `${previous.coordinationMode.label}` → `${current.coordinationMode.label}`.',
      );
    }
    if (previous.triggerEventOrCommand.trim() !=
        current.triggerEventOrCommand.trim()) {
      notes.add(
        'Déclencheur initial modifié : `${previous.triggerEventOrCommand}` → `${current.triggerEventOrCommand}`.',
      );
    }
    if (previous.correlationKey.trim() != current.correlationKey.trim()) {
      notes.add(
        'Clé de corrélation modifiée : `${previous.correlationKey}` → `${current.correlationKey}`.',
      );
    }

    final prevSteps = <String, SagaCompensationRow>{
      for (final s in previous.compensationMatrix) s.step: s,
    };
    final currSteps = <String, SagaCompensationRow>{
      for (final s in current.compensationMatrix) s.step: s,
    };
    for (final prevStep in previous.compensationMatrix) {
      final currStep = currSteps[prevStep.step];
      if (currStep == null) {
        notes.add('Étape de Saga supprimée : **${prevStep.step}**.');
      } else if (prevStep.compensationAction != currStep.compensationAction ||
          prevStep.nominalAction != currStep.nominalAction) {
        notes.add(
          'Étape de Saga modifiée **${currStep.step}** : action `${prevStep.nominalAction}` / compensation `${prevStep.compensationAction}` → `${currStep.nominalAction}` / `${currStep.compensationAction}`.',
        );
      }
    }
    for (final currStep in current.compensationMatrix) {
      if (!prevSteps.containsKey(currStep.step)) {
        notes.add(
          'Nouvelle étape de Saga ajoutée : **${currStep.step}** (compensation : `${currStep.compensationAction.isEmpty ? 'aucune' : currStep.compensationAction}`).',
        );
      }
    }

    if (notes.isNotEmpty) {
      buf.writeln('\n### Comparatif ciblé avec le jalon précédent');
      for (final n in notes) {
        buf.writeln('- $n');
      }
    }
  }

  static void _writeMigrationGuidelines(
    StringBuffer buf, {
    required String baselineLabel,
    required BuildTechStackSection section,
    required BuildHexaPromptRole role,
    required bool isAddedArtifact,
    required List<ArtifactEvolutionReport> removedArtifacts,
  }) {
    buf.writeln('\n### Consignes de refactoring non-régressif & Migration');

    if (role == BuildHexaPromptRole.unitTest) {
      buf
        ..writeln(
          '- **Non-régression des tests existants** : conserve tous les tests unitaires existants qui restent valides vis-à-vis du jalon `$baselineLabel` ; ne supprime jamais un test nominal ou limite non impacté.',
        )
        ..writeln(
          '- **Adaptation chirurgicale** : mets à jour uniquement les fixtures, constructeurs et assertions directement touchés par un changement volontaire de contrat, de signature ou d’invariant.',
        )
        ..writeln(
          '- **Couverture prioritaire du delta `vN → vN+1`** : ajoute des cas de test dédiés pour chaque nouvel attribut/champ, chaque contrainte durcie ou assouplie, chaque nouvelle erreur métier et chaque dépendance amont modifiée.',
        );
      if (section == BuildTechStackSection.persistence) {
        buf.writeln(
          '- **Tests de migration du Mapper** : vérifie explicitement la reconstitution des nouveaux champs/Value Objects et la rétrocompatibilité des données existantes (valeurs par défaut / colonnes optionnelles).',
        );
      }
      return;
    }

    if (isAddedArtifact) {
      buf
        ..writeln(
          '- **Intégration incrémentale propre** : cet élément est nouvellement introduit après `$baselineLabel` ; réutilise les types partagés, erreurs de base et Value Objects déjà présents dans le dépôt sans dupliquer le socle existant.',
        )
        ..writeln(
          '- **Zéro régression** : n’altère pas le comportement des modèles, ports et handlers existants non concernés.',
        );
      return;
    }

    switch (section) {
      case BuildTechStackSection.domain:
        buf
          ..writeln(
            '- **Évolution sur place sans régression** : fais évoluer l’implémentation existante dans `domain/` en préservant les invariants, méthodes métier et événements inchangés depuis `$baselineLabel`.',
          )
          ..writeln(
            '- **Mise à jour des fabriques & égalité** : adapte les constructeurs privés, fabriques (`create` / `reconstitute`), signatures de mutations/calculs et erreurs métier typées selon le delta ci-dessus.',
          )
          ..writeln(
            '- **Propagation des Value Objects amont** : répercute toute évolution des Value Objects référencés (nouvelle signature `create()`, normalisation ou champs composites) sans contourner leur validation.',
          );
      case BuildTechStackSection.persistence:
        buf
          ..writeln(
            '- **Adaptation de l’entité & du Mapper** : mets à jour l’entité/schéma ORM et le mapper bidirectionnel (`toPersistence` / `toDomain` via `reconstitute`) pour refléter les attributs et Value Objects ajoutés, renommés ou supprimés.',
          )
          ..writeln(
            '- **Migration de schéma incrémentale obligatoire** : produis ou mets à jour la migration de persistance (`ALTER TABLE`, ajout/suppression de colonnes, modification d’index/contraintes d’unicité) en prévoyant un **backfill ou une valeur par défaut sûre** pour toute nouvelle colonne `NOT NULL`.',
          )
          ..writeln(
            '- **Continuité du Port Repository** : adapte l’interface du port sortant et l’adaptateur concret uniquement sur les méthodes impactées, sans casser les appelants existants.',
          );
      case BuildTechStackSection.useCaseSaga:
        buf
          ..writeln(
            '- **Adaptation des contrats applicatifs** : mets à jour les structures immuables `Input` / `Output` (Commands / Queries), le port entrant et les appels aux agrégats / ports sortants impactés.',
          )
          ..writeln(
            '- **Cohérence transactionnelle & compensations** : pour une Saga ou une commande multi-étapes, aligne l’ordre inverse des compensations (`Rollback`), la clé de corrélation et l’idempotence avec la nouvelle matrice.',
          );
      case BuildTechStackSection.outbound:
      case BuildTechStackSection.inbound:
      case BuildTechStackSection.checkIntegration:
        buf.writeln(
          '- **Alignement des adaptateurs & du câblage DI** : mets à jour les contrôleurs, DTOs de validation aux bordures, consumers, adaptateurs sortants et bindings d’injection de dépendances impactés par les évolutions ci-dessus.',
        );
        if (removedArtifacts.isNotEmpty) {
          buf.writeln(
            '- **Décommissionnement propre (`removedArtifacts`)** : supprime les contrôleurs, DTOs, mappers, tokens d’injection et enregistrements de module devenus obsolètes pour `${removedArtifacts.map((r) => r.name).join('`, `')}` afin de garantir une compilation propre sans code mort.',
          );
        } else {
          buf.writeln(
            '- **Stabilité des contrats non modifiés** : préserve strictement les routes HTTP, schémas d’événements et bindings existants non touchés par l’itération.',
          );
        }
      case BuildTechStackSection.boilerplate:
      case BuildTechStackSection.devTools:
      case BuildTechStackSection.playground:
        buf.writeln(
          '- **Mise à jour incrémentale** : adapte uniquement les fichiers touchés par l’évolution depuis `$baselineLabel` sans réinitialiser la configuration existante.',
        );
    }
  }
}
