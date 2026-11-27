/// Construction des prompts par tour, du résumé UX compact et des directives QA BDD/TDD ([QaPromptBuilder]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/company_glossary.dart';
import '../models/qa/gherkin_feature_spec.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_stage_chat.dart';
import '../models/ux/ux_forge_stage.dart';
import 'qa_stage_agent.dart';
import 'spec_app_tools.dart';
import 'spec_prompt_builder.dart';
import 'spec_stage_agent.dart';
import 'ux_prompt_builder.dart';

/// Assemble les prompts contextuels, les catalogues Spec/UX compacts et les directives QA par étape.
abstract final class QaPromptBuilder {
  /// Construit la directive de questionnement QA adaptée au niveau choisi et au tour courant.
  static String qaQuestioningDirective({
    required VibeQuestioningLevel level,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
  }) {
    if (forceFollowUpQuestions) {
      return 'NIVEAU DE QUESTIONNEMENT : + de questions demandé (2 à 4 questions QA complémentaires OBLIGATOIRES) — '
          'Pose impérativement 2 à 4 nouvelles questions de stratégie de test, cas aux limites ou contrats BDD/TDD ciblées via "askUser" '
          '(avec des valeurs "default" pertinentes) pour approfondir cette étape QA, et laisse "qaPatch": null et "specPatch": null sur ce tour.';
    }
    if (afterAskUserReply) {
      return 'NIVEAU DE QUESTIONNEMENT : Réponses utilisateur reçues — '
          'INTERDICTION d’émettre "askUser" sur ce tour ("askUser": null obligatoire). '
          'Intègre les réponses dans un "qaPatch" complet et structuré pour cette étape QA (et un "specPatch" additif uniquement si un objet, attribut, état ou règle RG manque).';
    }
    return switch (level) {
      VibeQuestioningLevel.none =>
        'NIVEAU DE QUESTIONNEMENT : 0/4 (Aucun) — '
            'INTERDICTION d’émettre "askUser" ("askUser": null obligatoire). '
            'Produis directement un "qaPatch" complet, déterministe et traçable avec des choix de couverture solides.',
      VibeQuestioningLevel.light =>
        'NIVEAU DE QUESTIONNEMENT : 1/4 (Léger, 1 à 2 questions) — '
            'Pose 1 à 2 questions QA clés via "askUser" (avec "default") pour lever les ambiguïtés majeures avant de produire "qaPatch".',
      VibeQuestioningLevel.balanced =>
        'NIVEAU DE QUESTIONNEMENT : 2/4 (Équilibré, 2 à 4 questions) — '
            'Pose 2 à 4 questions QA structurées via "askUser" (avec "default") adaptées à cette étape avant de finaliser "qaPatch".',
      VibeQuestioningLevel.thorough =>
        'NIVEAU DE QUESTIONNEMENT : 3/4 (Approfondi, 4 à 6 questions) — '
            'Pose 4 à 6 questions QA ciblées via "askUser" (avec "default") couvrant les bornes, cas d’erreur, habilitations et contrats de cette étape.',
      VibeQuestioningLevel.exhaustive =>
        'NIVEAU DE QUESTIONNEMENT : 4/4 (Exhaustif, 6 à 10 questions) — '
            'Pose 6 à 10 questions QA complètes via "askUser" (avec "default") pour couvrir l’ensemble des cas limites, scénarios BDD et assertions TDD de cette étape.',
    };
  }

  /// Construit la directive décrivant la langue active des mots-clés Gherkin (`fr` / `en`).
  static String gherkinLanguageDirective(GherkinKeywordLanguage language) =>
      'LANGUE GHERKIN ACTIVE : `${language.name}` (${language.gherkinHeader} — '
      '${language.featureKeyword} / ${language.backgroundKeyword} / '
      '${language.scenarioKeyword} / ${language.scenarioOutlineKeyword} / '
      '${language.examplesKeyword} / ${language.givenKeyword} / '
      '${language.whenKeyword} / ${language.thenKeyword} / '
      '${language.andKeyword} / ${language.butKeyword}). '
      'Dans le JSON de "qaPatch", conserve toujours `keyword` parmi `given`, `when`, `then`, `and`, `but` '
      'et rédige `text`, `title` et `narrative` sans jamais répéter le mot-clé Gherkin au début de `text`.';

  /// Construit le prompt automatique d'amorce lorsqu'on entre dans une étape QA sans historique.
  static String buildStageKickoffPrompt(
    SpecForgeProject project,
    QaForgeStage stage, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) {
    final hasUx = project.uxSpec.hasContent;
    final lang = project.qaSpec.gherkinLanguage;
    return switch (stage) {
      QaForgeStage.testFixtures =>
        'Nous démarrons l’étape QA 1 (Jeux de données & Cas aux limites) du projet « ${project.name} ». '
            'En t’appuyant sur les objets métiers, leurs contraintes JSON Schema (minimum, maximum, minLength, maxLength, multipleOf, pattern, x-mask), '
            'leurs cycles de vie, les personas et les règles de gestion RG-xxx, '
            'propose ou pose les questions nécessaires pour concevoir les fixtures déterministes (FIX-001…) couvrant les cas nominaux, bornes, invalides, habilitations et cycles de vie.\n\n'
            '${SpecPromptBuilder.businessObjectPreferencesDirective(project, modelPreferencesOverride: modelPreferencesOverride)}',
      QaForgeStage.gherkinFeatures =>
        'Nous passons à l’étape QA 2 (Features Gherkin BDD `.feature`, langue active : `${lang.name}`) du projet « ${project.name} ». '
            'En t’appuyant sur le lexique canonique, les exigences fonctionnelles EXF-xxx, les cas d’usage, les règles RG-xxx, les fixtures FIX-xxx'
            '${hasUx ? ' ainsi que les parcours JRN-xxx et écrans SCR-xxx du volet UX,' : ' (le volet UX étant vide, concentre-toi sur des scénarios domaine/API purs),'
            } '
            'pose tes questions ou structure les fonctionnalités Gherkin (FEAT-001…), contextes partagés, scénarios (SCN-001…) et plans de scénarios avec tables d’exemples.',
      QaForgeStage.tddSuites =>
        'Nous passons à l’étape QA 3 (Suites TDD Unitaires & Contrats) du projet « ${project.name} ». '
            'En t’appuyant sur les objets métiers, formules, automates d’états, règles RG-xxx (et leurs messages d’erreur) ainsi que les fixtures FIX-xxx, '
            'conçois ou clarifie les suites TDD (TDD-001…) et cas atomiques Arrange / Act / Assert (TC-001…) ordonnés en progression stricte Red → Green → Refactor.',
      QaForgeStage.qaReviewExport =>
        'Nous passons à l’étape QA 4 (Couverture 360° & Export BDD/TDD) du projet « ${project.name} ». '
            'Exécute un audit complet de couverture et de cohérence entre les spécifications métiers'
            '${hasUx ? ', le volet UX (JRN-xxx / SCR-xxx)' : ''}'
            ' et le volet QA (FIX-xxx, FEAT-xxx/SCN-xxx, TDD-xxx/TC-xxx), '
            'remonte les trous de couverture éventuels dans `coherenceIssues` et prépare les livrables finaux (`.feature`, fixtures JSON et prompt TDD).',
    };
  }

  /// Construit un résumé JSON compact du volet UX (parcours `JRN-xxx`, routes,
  /// écrans `SCR-xxx` et actions) destiné aux agents QA lorsque `project.uxSpec.hasContent` vaut `true`.
  static Map<String, Object?> buildCompactUxSummaryJson(
    SpecForgeProject project,
  ) {
    final ux = project.uxSpec;
    return <String, Object?>{
      'currentUxStage': ux.currentStage.name,
      'shellPattern': ux.navigation.shellPattern.name,
      if (ux.navigation.homeRouteId.isNotEmpty)
        'homeRouteId': ux.navigation.homeRouteId,
      'uxHint':
          'Résumé compact : appelle `inspect_ux_screen(idOrCode: "...")` pour lire le détail des zones et slots d’un écran `SCR-xxx` ou les étapes complètes d’un parcours `JRN-xxx`.',
      'journeys': [
        for (final j in ux.journeys)
          <String, Object?>{
            'id': j.id,
            'code': j.code,
            'name': j.name,
            if (j.personaId.isNotEmpty) 'personaId': j.personaId,
            'channel': j.channel.name,
            if (j.useCaseIds.isNotEmpty) 'useCaseIds': j.useCaseIds,
            if (j.requirementIds.isNotEmpty) 'requirementIds': j.requirementIds,
            if (j.steps.isNotEmpty)
              'steps': [
                for (final st in j.steps)
                  <String, Object?>{
                    'id': st.id,
                    'order': st.order,
                    'title': st.title,
                    if (st.targetRouteId.isNotEmpty)
                      'targetRouteId': st.targetRouteId,
                    if (st.branchCondition.isNotEmpty)
                      'branchCondition': st.branchCondition,
                  },
              ],
            if (j.successCriteria.isNotEmpty)
              'successCriteria': j.successCriteria,
          },
      ],
      'routes': [
        for (final r in ux.navigation.routes)
          <String, Object?>{
            'id': r.id,
            'path': r.path,
            'title': r.title,
            'pageType': r.pageType.name,
            if (r.moduleId.isNotEmpty) 'moduleId': r.moduleId,
            if (r.allowedPersonaIds.isNotEmpty)
              'allowedPersonaIds': r.allowedPersonaIds,
            if (r.permissionRuleIds.isNotEmpty)
              'permissionRuleIds': r.permissionRuleIds,
          },
      ],
      'screens': [
        for (final s in ux.screens)
          <String, Object?>{
            'id': s.id,
            'code': s.code,
            'name': s.name,
            if (s.routeId.isNotEmpty) 'routeId': s.routeId,
            'pattern': s.pattern.name,
            if (s.primaryObjectId.isNotEmpty)
              'primaryObjectId': s.primaryObjectId,
            if (s.personaIds.isNotEmpty) 'personaIds': s.personaIds,
            if (s.useCaseIds.isNotEmpty) 'useCaseIds': s.useCaseIds,
            if (s.requirementIds.isNotEmpty) 'requirementIds': s.requirementIds,
            if (s.actions.isNotEmpty)
              'actions': [
                for (final a in s.actions)
                  <String, Object?>{
                    'id': a.id,
                    'label': a.label,
                    'hierarchy': a.hierarchy.name,
                    if (a.businessRuleIds.isNotEmpty)
                      'businessRuleIds': a.businessRuleIds,
                    if (a.targetRouteId.isNotEmpty)
                      'targetRouteId': a.targetRouteId,
                    if (a.confirmationMessage.isNotEmpty)
                      'confirmationMessage': a.confirmationMessage,
                  },
              ],
            if (s.states.readOnlyRuleIds.isNotEmpty)
              'readOnlyRuleIds': s.states.readOnlyRuleIds,
          },
      ],
    };
  }

  /// Assemble le prompt complet envoyé à l'agent QA de [stage] pour le tour courant.
  static String buildTurnPrompt({
    required SpecForgeProject project,
    required QaForgeStage stage,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    int maxHistoryEntries = 10,
    CompanyGlossary? companyGlossary,
    BusinessObjectModelPreferences? modelPreferencesOverride,
    String? focusedFixtureId,
    String? focusedFeatureId,
    String? focusedScenarioId,
    String? focusedTddSuiteId,
    Set<String>? toolNames,
  }) {
    final agent = QaStageAgent.forStage(stage);
    final stageState = project.qaSpec.stageStateFor(stage);
    final specCatalogJson = const JsonEncoder.withIndent('  ')
        .convert(UxPromptBuilder.buildCompactSpecCatalogJson(project));
    final qaContextJson = const JsonEncoder.withIndent('  ')
        .convert(project.qaSpec.toCompactContextJson(stage));

    final previousSummaries = <String>[
      for (final specStage in project.enabledSpecStages)
        if (project.stageStateFor(specStage).stageSummary.trim().isNotEmpty)
          '- Spec ${project.stepNumberFor(specStage)} (${specStage.title}) : '
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
      for (final qaStage in QaForgeStage.values)
        if (qaStage.index < stage.index &&
            project.qaSpec
                .stageStateFor(qaStage)
                .stageSummary
                .trim()
                .isNotEmpty)
          '- QA ${qaStage.stepNumber} (${qaStage.title}) : '
              '${project.qaSpec.stageStateFor(qaStage).stageSummary.trim()}',
    ];

    final history = _buildHistory(
      stageState.messages,
      maxEntries: maxHistoryEntries,
    );

    final buffer = StringBuffer()
      ..writeln(
        'ÉTAPE QA ACTIVE : ${stage.stepNumber}/${QaForgeStage.values.length} — ${stage.title} (Agent : ${agent.stage.agentTitle})',
      )
      ..writeln()
      ..writeln(
        qaQuestioningDirective(
          level: questioningLevel,
          afterAskUserReply: afterAskUserReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
        ),
      )
      ..writeln()
      ..writeln(gherkinLanguageDirective(project.qaSpec.gherkinLanguage))
      ..writeln()
      ..writeln(
        SpecPromptBuilder.businessObjectPreferencesDirective(
          project,
          modelPreferencesOverride: modelPreferencesOverride,
        ),
      )
      ..writeln()
      ..writeln(
        'RÈGLES DE MODÉLISATION DES ATTRIBUTS (POUR LES FIXTURES ET TOUT "specPatch" ADDITIF) :\n'
        '${SpecStageAgent.attributeModelingRules}',
      )
      ..writeln()
      ..writeln(
        SpecForgeToolRegistry.toolsGuide(
          toolNames: toolNames ?? SpecForgeToolRegistry.qaStageToolNames,
        ),
      );

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
        ..writeln('SYNTHÈSE DES ÉTAPES PRÉCÉDENTES (SPEC, UX & QA) :')
        ..writeln(previousSummaries.join('\n'));
    }

    buffer
      ..writeln()
      ..writeln('CATALOGUE COMPACT DES SPÉCIFICATIONS MÉTIERS (JSON) :')
      ..writeln(specCatalogJson);

    if (project.exampleMappings.isNotEmpty &&
        (stage == QaForgeStage.testFixtures ||
            stage == QaForgeStage.gherkinFeatures)) {
      final emJson = const JsonEncoder.withIndent('  ').convert([
        for (final s in project.exampleMappings) s.toJson(),
      ]);
      buffer
        ..writeln()
        ..writeln(
          'TABLEAUX D’EXAMPLE MAPPING (EXEMPLES VERTS CONCRETS & RÈGLES BLEUES À RÉUTILISER) :',
        )
        ..writeln(emJson);
    }

    if (project.uxSpec.hasContent) {
      final uxSummaryJson = const JsonEncoder.withIndent('  ')
          .convert(buildCompactUxSummaryJson(project));
      buffer
        ..writeln()
        ..writeln('RÉSUMÉ COMPACT DU VOLET UX (PARCOURS JRN, ROUTES, ÉCRANS SCR & ACTIONS) :')
        ..writeln(uxSummaryJson);
    } else {
      buffer
        ..writeln()
        ..writeln(
          'ÉTAT DU VOLET UX : Non renseigné — génère des jeux d’essais, scénarios Gherkin et suites TDD centrés sur le domaine métier, les contrats JSON Schema et les règles RG-xxx (laisse `journeyIds` et `screenIds` vides).',
        );
    }

    buffer
      ..writeln()
      ..writeln('ÉTAT COURANT DU VOLET QA BDD/TDD (JSON) :')
      ..writeln(qaContextJson);

    final focusBlock = buildQaFocusScopeBlock(
      project: project,
      focusedFixtureId: focusedFixtureId,
      focusedFeatureId: focusedFeatureId,
      focusedScenarioId: focusedScenarioId,
      focusedTddSuiteId: focusedTddSuiteId,
    );
    if (focusBlock.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(focusBlock);
    }

    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT DE CETTE ÉTAPE QA :')
        ..writeln(history);
    }

    buffer
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR POUR CE TOUR :')
      ..writeln(userInput.trim());

    return buffer.toString();
  }

  /// Construit le bloc « FOCUS COURANT DANS L'ATELIER QA » (chaîne vide si aucune sélection active).
  static String buildQaFocusScopeBlock({
    required SpecForgeProject project,
    String? focusedFixtureId,
    String? focusedFeatureId,
    String? focusedScenarioId,
    String? focusedTddSuiteId,
  }) {
    final qa = project.qaSpec;
    final fixture =
        (focusedFixtureId != null && focusedFixtureId.trim().isNotEmpty)
        ? qa.findFixture(focusedFixtureId)
        : null;
    var feature =
        (focusedFeatureId != null && focusedFeatureId.trim().isNotEmpty)
        ? qa.findFeature(focusedFeatureId)
        : null;

    GherkinScenarioSpec? scenario;
    if (focusedScenarioId != null && focusedScenarioId.trim().isNotEmpty) {
      final needle = focusedScenarioId.trim().toLowerCase();
      if (feature != null) {
        scenario = _findScenarioInList(feature.scenarios, needle);
      }
      if (scenario == null) {
        for (final candidate in qa.features) {
          final hit = _findScenarioInList(candidate.scenarios, needle);
          if (hit != null) {
            scenario = hit;
            feature ??= candidate;
            break;
          }
        }
      }
    }

    final tddSuite =
        (focusedTddSuiteId != null && focusedTddSuiteId.trim().isNotEmpty)
        ? qa.findTddSuite(focusedTddSuiteId)
        : null;

    if (fixture == null &&
        feature == null &&
        scenario == null &&
        tddSuite == null) {
      return '';
    }

    final buf = StringBuffer()
      ..writeln('FOCUS COURANT DANS L’ATELIER QA (SCOPE DE SÉLECTION) :');
    if (fixture != null) {
      buf.writeln(
        '- Fixture sélectionnée : ${fixture.code} — ${fixture.name} (id: ${fixture.id}, kind: ${fixture.kind.name}, objet: ${fixture.businessObjectId.isEmpty ? "(aucun)" : fixture.businessObjectId}, expectedValid: ${fixture.expectedValid})',
      );
    }
    if (feature != null) {
      buf.writeln(
        '- Feature Gherkin sélectionnée : ${feature.code} — ${feature.title} (id: ${feature.id}, ${feature.scenarios.length} scénario(s))',
      );
    }
    if (scenario != null) {
      final scenarioJson = const JsonEncoder.withIndent('  ')
          .convert(scenario.toJson());
      buf
        ..writeln(
          '- Scénario Gherkin ciblé : ${scenario.code} — ${scenario.title} (id: ${scenario.id}, isOutline: ${scenario.isOutline})',
        )
        ..writeln('- Détail JSON du scénario sélectionné :')
        ..writeln(scenarioJson);
    }
    if (tddSuite != null) {
      buf.writeln(
        '- Suite TDD sélectionnée : ${tddSuite.code} — ${tddSuite.name} (id: ${tddSuite.id}, layer: ${tddSuite.layer.name}, ${tddSuite.cases.length} cas)',
      );
    }
    buf.writeln(
      '- Consigne scope ciblé : si l’utilisateur fait référence à « cette fixture », « cette feature », « ce scénario » ou « cette suite TDD », applique la mise à jour en priorité sur l’élément sélectionné en conservant son `id`.',
    );
    return buf.toString().trimRight();
  }

  static GherkinScenarioSpec? _findScenarioInList(
    List<GherkinScenarioSpec> scenarios,
    String lowerNeedle,
  ) {
    for (final sc in scenarios) {
      if (sc.id.toLowerCase() == lowerNeedle ||
          (sc.code.isNotEmpty && sc.code.toLowerCase() == lowerNeedle)) {
        return sc;
      }
    }
    for (final sc in scenarios) {
      if (sc.title.toLowerCase() == lowerNeedle) {
        return sc;
      }
    }
    return null;
  }

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
