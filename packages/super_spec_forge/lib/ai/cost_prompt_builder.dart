/// Construction des prompts par tour, des synthèses compactes Métier/UX/QA/Coûts,
/// de la référence [EnterpriseRateCard] et des directives FinOps ([CostPromptBuilder]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/company_glossary.dart';
import '../models/cost/cost_forge_stage.dart';
import '../models/enterprise_rate_card.dart';
import '../models/event_storming_spec.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_stage_chat.dart';
import '../models/ux/ux_forge_stage.dart';
import 'cost_stage_agent.dart';
import 'qa_prompt_builder.dart';
import 'spec_app_tools.dart';
import 'spec_delta_recovery.dart';
import 'spec_prompt_builder.dart';
import 'spec_stage_agent.dart';
import 'ux_prompt_builder.dart';

/// Assemble les instructions système, les contextes compacts Spec/UX/QA/Coûts,
/// la grille tarifaire d'entreprise et les prompts de relance delta pour les 4 étapes FinOps.
abstract final class CostPromptBuilder {
  /// Retourne l'instruction système principale associée à [stage].
  static String buildSystemInstruction(CostForgeStage stage) =>
      CostStageAgent.forStage(stage).systemInstruction;

  /// Retourne le guide statique combinant le schéma `"costPatch"` de [stage] et le guide des outils FinOps.
  static String buildStaticGuide(
    CostForgeStage stage, {
    Set<String>? toolNames,
  }) =>
      '${CostStageAgent.forStage(stage).patchSchemaGuide}\n\n---\n\n'
      '${SpecForgeToolRegistry.toolsGuide(toolNames: toolNames ?? SpecForgeToolRegistry.costStageToolNames)}';

  /// Construit la directive de questionnement FinOps adaptée au niveau choisi et au tour courant.
  static String costQuestioningDirective({
    required VibeQuestioningLevel level,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
  }) {
    if (forceFollowUpQuestions) {
      return 'NIVEAU DE QUESTIONNEMENT : + de questions demandé (2 à 4 questions FinOps complémentaires OBLIGATOIRES) — '
          'Pose impérativement 2 à 4 nouvelles questions de cadrage budgétaire, sourcing, dimensionnement Cloud/Run ou risques ciblées via "askUser" '
          '(avec des valeurs "default" pertinentes) pour approfondir cette étape Coûts, et laisse "costPatch": null et "specPatch": null sur ce tour.';
    }
    if (afterAskUserReply) {
      return 'NIVEAU DE QUESTIONNEMENT : Réponses utilisateur reçues — '
          'INTERDICTION d’émettre "askUser" sur ce tour ("askUser": null obligatoire). '
          'Intègre les réponses dans un "costPatch" complet, chiffré et cohérent pour cette étape FinOps (et un "specPatch" additif uniquement si un objet, attribut, état ou règle RG manque).';
    }
    return switch (level) {
      VibeQuestioningLevel.none =>
        'NIVEAU DE QUESTIONNEMENT : 0/4 (Aucun) — '
            'INTERDICTION d’émettre "askUser" ("askUser": null obligatoire). '
            'Produis directement un "costPatch" complet, réaliste et traçable avec des hypothèses FinOps solides.',
      VibeQuestioningLevel.light =>
        'NIVEAU DE QUESTIONNEMENT : 1/4 (Léger, 1 à 2 questions) — '
            'Pose 1 à 2 questions FinOps clés via "askUser" (avec "default") pour lever les incertitudes majeures avant de produire "costPatch".',
      VibeQuestioningLevel.balanced =>
        'NIVEAU DE QUESTIONNEMENT : 2/4 (Équilibré, 2 à 4 questions) — '
            'Pose 2 à 4 questions FinOps structurées via "askUser" (avec "default") adaptées à cette étape avant de finaliser "costPatch".',
      VibeQuestioningLevel.thorough =>
        'NIVEAU DE QUESTIONNEMENT : 3/4 (Approfondi, 4 à 6 questions) — '
            'Pose 4 à 6 questions FinOps ciblées via "askUser" (avec "default") couvrant le sourcing, les volumétries, les SLA, les licences et les aléas de cette étape.',
      VibeQuestioningLevel.exhaustive =>
        'NIVEAU DE QUESTIONNEMENT : 4/4 (Exhaustif, 6 à 10 questions) — '
            'Pose 6 à 10 questions FinOps complètes via "askUser" (avec "default") pour cadrer finement tous les postes de coûts, ratios, hypothèses Cloud et risques de cette étape.',
    };
  }

  /// Construit le bloc de référence décrivant la grille tarifaire d'entreprise ([EnterpriseRateCard]) lorsqu'elle est fournie.
  static String enterpriseRateCardBlock(EnterpriseRateCard? enterpriseRateCard) {
    if (enterpriseRateCard == null) return '';
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(enterpriseRateCard.toJson());
    return [
      'GRILLE TARIFAIRE D’ENTREPRISE DE RÉFÉRENCE (ENTERPRISE RATE CARD) :',
      'Respecte en priorité ces TJM internes/externes, cette devise (${enterpriseRateCard.currency.code}), '
          'ces calibres T-shirt et ces standards d’entreprise, sauf dérogation explicite justifiée par le projet ou demandée par l’utilisateur :',
      encoded,
    ].join('\n');
  }

  /// Construit le prompt automatique d'amorce lorsqu'on entre dans une étape Coûts sans historique.
  static String buildStageKickoffPrompt(
    SpecForgeProject project,
    CostForgeStage stage, {
    EnterpriseRateCard? enterpriseRateCard,
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) {
    final hasUx = project.uxSpec.hasContent;
    final hasQa = project.qaSpec.hasContent;
    final hasEnterprise = enterpriseRateCard != null;
    return switch (stage) {
      CostForgeStage.rateCardAssumptions =>
        'Nous démarrons l’étape Coûts 1 (Équipe, TJM & Hypothèses) du projet « ${project.name} ». '
            'En t’appuyant sur la vision, les personas, le cahier des charges, la complexité technique'
            '${hasEnterprise ? ' et la grille tarifaire d’entreprise de référence,' : ','} '
            'propose ou pose les questions nécessaires pour calibrer la devise, le mode de delivery, la volumétrie cible d’utilisateurs, '
            'les profils TJM, les calibres T-shirt PERT, les ratios transverses, les gains de productivité IA et les hypothèses budgétaires.\n\n'
            '${SpecPromptBuilder.businessObjectPreferencesDirective(project, modelPreferencesOverride: modelPreferencesOverride)}',
      CostForgeStage.buildWbs =>
        'Nous passons à l’étape Coûts 2 (Chiffrage Build CAPEX / WBS) du projet « ${project.name} ». '
            'En t’appuyant sur la grille de profils TJM active, les modules, les exigences fonctionnelles et non fonctionnelles, '
            'l’Event Storming, les objets métiers'
            '${hasUx ? ', les écrans UX (SCR-xxx)' : ''}'
            '${hasQa ? ' et les suites BDD/TDD (FEAT-xxx / TDD-xxx)' : ''}, '
            'pose tes questions ou structure les lots WBS traçables (WBS-001…) avec priorités MoSCoW, profils, tailles T-shirt et charges PERT 3 points en jours/homme.',
      CostForgeStage.runOpex =>
        'Nous passons à l’étape Coûts 3 (Coûts Run, Cloud & Licences OPEX) du projet « ${project.name} » '
            '(cible : ${project.costSpec.targetUsersCount} utilisateurs actifs, devise : ${project.costSpec.currency.code}). '
            'En t’appuyant sur les exigences non fonctionnelles (SLA, sécurité, volumétrie), les objets métiers et les intégrations externes/IA, '
            'pose tes questions ou dimensionne les postes récurrents OPEX (RUN-001…) couvrant Cloud, BDD/stockage, APIs tierces, tokens IA, licences SaaS, MCO/TMA et sécurité/conformité.',
      CostForgeStage.tcoReviewExport =>
        'Nous passons à l’étape Coûts 4 (Synthèse TCO, Risques & Export) du projet « ${project.name} ». '
            'Audite la cohérence globale Build + Run + Spécifications, identifie et valorise les risques budgétaires en EMV (RSK-001…) '
            'à partir des hotspots Event Storming et des exigences critiques, remonte les alertes FinOps éventuelles dans `coherenceIssues` '
            'et consolide la synthèse exécutive TCO à 1, 3 et 5 ans.',
    };
  }

  /// Construit un résumé JSON compact de l'Event Storming (contextes bornés, métriques de flux et hotspots)
  /// destiné à l'estimation WBS et à l'identification des risques.
  static Map<String, Object?> buildCompactEventStormingSummaryJson(
    SpecForgeProject project,
  ) {
    final es = project.eventStorming;
    return <String, Object?>{
      'boundedContextCount': es.boundedContexts.length,
      'flowCount': es.flows.length,
      'totalEventCount': es.totalEventCount,
      'totalCommandCount': es.totalCommandCount,
      'totalPolicyCount': es.totalPolicyCount,
      'openHotspotCount': es.openHotspotCount,
      'eventStormingHint':
          'Résumé compact : appelle `get_event_storming` pour inspecter l’intégralité des commandes, événements, agrégats et politiques d’un flux.',
      'boundedContexts': [
        for (final bc in es.boundedContexts)
          <String, Object?>{
            'id': bc.id,
            'code': bc.code,
            'name': bc.name,
            if (bc.description.isNotEmpty) 'description': bc.description,
          },
      ],
      'flows': [
        for (final f in es.flows)
          <String, Object?>{
            'id': f.id,
            'code': f.code,
            'title': f.title,
            'domainEventCount': f.domainEventCount,
            'commandCount': f.commandCount,
            'policyCount': f.policyCount,
            'openHotspotCount': f.openHotspotCount,
            if (f.requirementIds.isNotEmpty) 'requirementIds': f.requirementIds,
            'hotspots': [
              for (final n in f.nodes)
                if (n.kind == EventStormNodeKind.hotspot)
                  <String, Object?>{
                    'id': n.id,
                    if (n.code.isNotEmpty) 'code': n.code,
                    'title': n.title,
                    if (n.description.isNotEmpty) 'description': n.description,
                    'resolved': n.resolved,
                    if (n.answer.isNotEmpty) 'answer': n.answer,
                    if (n.targetObjectId.isNotEmpty)
                      'targetObjectId': n.targetObjectId,
                  },
            ],
          },
      ],
    };
  }

  /// Construit un résumé JSON compact du volet QA BDD/TDD (`FIX-xxx`, `FEAT-xxx`, `TDD-xxx`)
  /// destiné au calibrage des lots de tests et d'automatisation dans le WBS.
  static Map<String, Object?> buildCompactQaSummaryJson(
    SpecForgeProject project,
  ) {
    final qa = project.qaSpec;
    return <String, Object?>{
      'currentQaStage': qa.currentStage.name,
      'gherkinLanguage': qa.gherkinLanguage.name,
      'fixtureCount': qa.fixtures.length,
      'featureCount': qa.features.length,
      'totalScenarioCount': qa.totalScenarioCount,
      'tddSuiteCount': qa.tddSuites.length,
      'totalTddCaseCount': qa.totalTddCaseCount,
      'qaHint':
          'Résumé compact : appelle `inspect_qa_artifact(idOrCode: "...")` pour lire le détail complet d’une feature `FEAT-xxx`, d’une suite `TDD-xxx` ou d’une fixture `FIX-xxx`.',
      'features': [
        for (final f in qa.features)
          <String, Object?>{
            'id': f.id,
            'code': f.code,
            'title': f.title,
            if (f.moduleId.isNotEmpty) 'moduleId': f.moduleId,
            'scenarioCount': f.scenarios.length,
          },
      ],
      'tddSuites': [
        for (final s in qa.tddSuites)
          <String, Object?>{
            'id': s.id,
            'code': s.code,
            'name': s.name,
            'layer': s.layer.name,
            if (s.targetObjectId.isNotEmpty) 'targetObjectId': s.targetObjectId,
            if (s.moduleId.isNotEmpty) 'moduleId': s.moduleId,
            'caseCount': s.cases.length,
          },
      ],
    };
  }

  /// Assemble le prompt complet envoyé à l'agent FinOps de [stage] pour le tour courant.
  static String buildTurnPrompt({
    required SpecForgeProject project,
    required CostForgeStage stage,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    int maxHistoryEntries = 10,
    EnterpriseRateCard? enterpriseRateCard,
    CompanyGlossary? companyGlossary,
    BusinessObjectModelPreferences? modelPreferencesOverride,
    String? focusedCostItemId,
    String? focusedProfileId,
    String? focusedWbsItemId,
    String? focusedRunItemId,
    String? focusedRiskItemId,
    Set<String>? toolNames,
  }) {
    final agent = CostStageAgent.forStage(stage);
    final stageState = project.costSpec.stageStateFor(stage);
    final specCatalogJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(UxPromptBuilder.buildCompactSpecCatalogJson(project));
    final costContextJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(project.costSpec.toCompactContextJson(stage));
    final costSummaryJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(SpecForgeToolRegistry.buildCostSummaryJson(project.costSpec));

    final previousSummaries = <String>[
      for (final specStage in SpecForgeStage.values)
        if (project.stageStateFor(specStage).stageSummary.trim().isNotEmpty)
          '- Spec ${specStage.stepNumber} (${specStage.title}) : '
              '${project.stageStateFor(specStage).stageSummary.trim()}',
      if (project.uxSpec.hasContent)
        for (final uxStage in UxForgeStage.values)
          if (project.uxSpec
              .stageStateFor(uxStage)
              .stageSummary
              .trim()
              .isNotEmpty)
            '- UX ${uxStage.stepNumber} (${uxStage.title}) : '
                '${project.uxSpec.stageStateFor(uxStage).stageSummary.trim()}',
      if (project.qaSpec.hasContent)
        for (final qaStage in QaForgeStage.values)
          if (project.qaSpec
              .stageStateFor(qaStage)
              .stageSummary
              .trim()
              .isNotEmpty)
            '- QA ${qaStage.stepNumber} (${qaStage.title}) : '
                '${project.qaSpec.stageStateFor(qaStage).stageSummary.trim()}',
      for (final costStage in CostForgeStage.values)
        if (costStage.index < stage.index &&
            project.costSpec
                .stageStateFor(costStage)
                .stageSummary
                .trim()
                .isNotEmpty)
          '- Coûts ${costStage.stepNumber} (${costStage.title}) : '
              '${project.costSpec.stageStateFor(costStage).stageSummary.trim()}',
    ];

    final history = _buildHistory(
      stageState.messages,
      maxEntries: maxHistoryEntries,
    );

    final buffer = StringBuffer()
      ..writeln(
        'ÉTAPE COÛTS / FINOPS ACTIVE : ${stage.stepNumber}/${CostForgeStage.values.length} — ${stage.title} (Agent : ${agent.stage.agentTitle})',
      )
      ..writeln()
      ..writeln(
        costQuestioningDirective(
          level: questioningLevel,
          afterAskUserReply: afterAskUserReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
        ),
      )
      ..writeln()
      ..writeln(
        SpecPromptBuilder.businessObjectPreferencesDirective(
          project,
          modelPreferencesOverride: modelPreferencesOverride,
        ),
      )
      ..writeln()
      ..writeln(
        'RÈGLES DE MODÉLISATION DES ATTRIBUTS (POUR TOUT "specPatch" ADDITIF ÉVENTUEL) :\n'
        '${SpecStageAgent.attributeModelingRules}',
      )
      ..writeln()
      ..writeln(
        SpecForgeToolRegistry.toolsGuide(
          toolNames: toolNames ?? SpecForgeToolRegistry.costStageToolNames,
        ),
      );

    final rateCardSection = enterpriseRateCardBlock(enterpriseRateCard);
    if (rateCardSection.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(rateCardSection);
    }

    final glossaryBlock = SpecPromptBuilder.companyGlossaryBlock(
      companyGlossary,
    );
    if (glossaryBlock.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(glossaryBlock);
    }

    if (previousSummaries.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('SYNTHÈSE DES ÉTAPES PRÉCÉDENTES (SPEC, UX, QA & COÛTS) :')
        ..writeln(previousSummaries.join('\n'));
    }

    buffer
      ..writeln()
      ..writeln('CATALOGUE COMPACT DES SPÉCIFICATIONS MÉTIERS (JSON) :')
      ..writeln(specCatalogJson);

    if (project.eventStorming.hasContent) {
      final esJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(buildCompactEventStormingSummaryJson(project));
      buffer
        ..writeln()
        ..writeln(
          'RÉSUMÉ COMPACT EVENT STORMING (CONTEXTES BORNÉS, FLUX & HOTSPOTS) :',
        )
        ..writeln(esJson);
    }

    if (project.uxSpec.hasContent) {
      final uxSummaryJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(QaPromptBuilder.buildCompactUxSummaryJson(project));
      buffer
        ..writeln()
        ..writeln(
          'RÉSUMÉ COMPACT DU VOLET UX (PARCOURS JRN, ROUTES, ÉCRANS SCR & ACTIONS) :',
        )
        ..writeln(uxSummaryJson);
    } else {
      buffer
        ..writeln()
        ..writeln(
          'ÉTAT DU VOLET UX : Non renseigné — estime les lots Frontend/API à partir du cahier des charges et laisse `uxScreenIds` vide.',
        );
    }

    if (project.qaSpec.hasContent) {
      final qaSummaryJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(buildCompactQaSummaryJson(project));
      buffer
        ..writeln()
        ..writeln(
          'RÉSUMÉ COMPACT DU VOLET QA BDD/TDD (FIXTURES FIX, FEATURES FEAT & SUITES TDD) :',
        )
        ..writeln(qaSummaryJson);
    } else {
      buffer
        ..writeln()
        ..writeln(
          'ÉTAT DU VOLET QA : Non renseigné — laisse `qaFeatureIds` et `tddSuiteIds` vides sur les lots WBS.',
        );
    }

    buffer
      ..writeln()
      ..writeln('ÉTAT COURANT DU VOLET COÛTS / FINOPS (JSON) :')
      ..writeln(costContextJson)
      ..writeln()
      ..writeln(
        'INDICATEURS FINANCIERS CALCULÉS SUR L’ÉTAT COURANT (BUILD, RUN, RISQUES EMV & TCO 1/3/5 ANS) :',
      )
      ..writeln(costSummaryJson);

    final focusBlock = buildCostFocusScopeBlock(
      project: project,
      focusedCostItemId: focusedCostItemId,
      focusedProfileId: focusedProfileId,
      focusedWbsItemId: focusedWbsItemId,
      focusedRunItemId: focusedRunItemId,
      focusedRiskItemId: focusedRiskItemId,
    );
    if (focusBlock.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(focusBlock);
    }

    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT DE CETTE ÉTAPE COÛTS :')
        ..writeln(history);
    }

    buffer
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR POUR CE TOUR :')
      ..writeln(userInput.trim());

    return buffer.toString();
  }

  /// Construit le bloc « FOCUS COURANT DANS L'ATELIER COÛTS » (chaîne vide si aucune sélection active).
  static String buildCostFocusScopeBlock({
    required SpecForgeProject project,
    String? focusedCostItemId,
    String? focusedProfileId,
    String? focusedWbsItemId,
    String? focusedRunItemId,
    String? focusedRiskItemId,
  }) {
    final cost = project.costSpec;
    var profile =
        (focusedProfileId != null && focusedProfileId.trim().isNotEmpty)
        ? cost.findProfile(focusedProfileId)
        : null;
    var wbs = (focusedWbsItemId != null && focusedWbsItemId.trim().isNotEmpty)
        ? cost.findWbsItem(focusedWbsItemId)
        : null;
    var run = (focusedRunItemId != null && focusedRunItemId.trim().isNotEmpty)
        ? cost.findRunItem(focusedRunItemId)
        : null;
    var risk =
        (focusedRiskItemId != null && focusedRiskItemId.trim().isNotEmpty)
        ? cost.findRiskItem(focusedRiskItemId)
        : null;

    if (focusedCostItemId != null && focusedCostItemId.trim().isNotEmpty) {
      final generic = focusedCostItemId.trim();
      wbs ??= cost.findWbsItem(generic);
      if (wbs == null) run ??= cost.findRunItem(generic);
      if (wbs == null && run == null) risk ??= cost.findRiskItem(generic);
      if (wbs == null && run == null && risk == null) {
        profile ??= cost.findProfile(generic);
      }
    }

    if (profile == null && wbs == null && run == null && risk == null) {
      return '';
    }

    final buf = StringBuffer()
      ..writeln('FOCUS COURANT DANS L’ATELIER COÛTS (SCOPE DE SÉLECTION) :');
    if (profile != null) {
      buf.writeln(
        '- Profil TJM sélectionné : ${profile.code} — ${profile.name} (id: ${profile.id}, discipline: ${profile.discipline.name}, interne: ${profile.internalDailyRate} ${cost.currency.code}/j, externe: ${profile.externalDailyRate} ${cost.currency.code}/j)',
      );
    }
    if (wbs != null) {
      final wbsJson = const JsonEncoder.withIndent('  ').convert(wbs.toJson());
      buf
        ..writeln(
          '- Lot Build WBS sélectionné : ${wbs.code} — ${wbs.title} (id: ${wbs.id}, priorité: ${wbs.priority.name}, taille: ${wbs.tshirtSize.name}, PERT espéré: ${wbs.expectedDays.toStringAsFixed(2)} j/h)',
        )
        ..writeln('- Détail JSON du lot WBS sélectionné :')
        ..writeln(wbsJson);
    }
    if (run != null) {
      final runJson = const JsonEncoder.withIndent('  ').convert(run.toJson());
      buf
        ..writeln(
          '- Poste Run OPEX sélectionné : ${run.code} — ${run.name} (id: ${run.id}, catégorie: ${run.category.name}, env: ${run.environment.name}, mensuel: ${run.monthlyCost.toStringAsFixed(2)} ${cost.currency.code})',
        )
        ..writeln('- Détail JSON du poste Run sélectionné :')
        ..writeln(runJson);
    }
    if (risk != null) {
      final riskJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(risk.toJson());
      buf
        ..writeln(
          '- Risque budgétaire sélectionné : ${risk.code} — ${risk.title} (id: ${risk.id}, probabilité: ${risk.probabilityPct} %, EMV charge: ${risk.expectedDays.toStringAsFixed(2)} j/h)',
        )
        ..writeln('- Détail JSON du risque sélectionné :')
        ..writeln(riskJson);
    }
    buf.writeln(
      '- Consigne scope ciblé : si l’utilisateur fait référence à « ce profil », « ce lot WBS », « ce poste Run » ou « ce risque », applique la mise à jour en priorité sur l’élément sélectionné en conservant son `id`.',
    );
    return buf.toString().trimRight();
  }

  /// Construit le prompt de relance delta après erreur de validation ou troncature JSON sur une étape Coûts.
  static String buildDeltaRetryPrompt({
    required String refreshedTurnPrompt,
    required List<String> priorCauses,
    required SpecSalvageOutcome salvage,
    String? rawFailedResponse,
  }) => SpecDeltaRecovery.buildDeltaRetryPrompt(
    refreshedTurnPrompt: refreshedTurnPrompt,
    priorCauses: priorCauses,
    salvage: salvage,
    rawFailedResponse: rawFailedResponse,
  );

  static String _buildHistory(
    List<SpecChatMessage> messages, {
    required int maxEntries,
  }) {
    if (messages.isEmpty) return '';
    final slice = messages.length <= maxEntries
        ? messages
        : messages.sublist(messages.length - maxEntries);
    return slice.map((m) => m.toConversationEntry()).join('\n');
  }
}
