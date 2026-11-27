/// Construction des prompts par tour et du catalogue Spec compact pour les agents UX ([UxPromptBuilder]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/company_glossary.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_stage_chat.dart';
import '../models/ux/ux_forge_stage.dart';
import '../models/ux/ux_screen_spec.dart';
import 'spec_app_tools.dart';
import 'spec_prompt_builder.dart';
import 'spec_stage_agent.dart';
import 'ux_stage_agent.dart';

/// Assemble les prompts contextuels, le catalogue Spec compact et les directives UX par étape.
abstract final class UxPromptBuilder {
  /// Construit la directive de questionnement UX adaptée au niveau choisi et au tour courant.
  static String uxQuestioningDirective({
    required VibeQuestioningLevel level,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
  }) {
    if (forceFollowUpQuestions) {
      return 'NIVEAU DE QUESTIONNEMENT : + de questions demandé (2 à 4 questions UX complémentaires OBLIGATOIRES) — '
          'Pose impérativement 2 à 4 nouvelles questions ergonomiques et fonctionnelles ciblées via "askUser" '
          '(avec des valeurs "default" pertinentes) pour approfondir cette étape UX, et laisse "uxPatch": null et "specPatch": null sur ce tour.';
    }
    if (afterAskUserReply) {
      return 'NIVEAU DE QUESTIONNEMENT : Réponses utilisateur reçues — '
          'INTERDICTION d’émettre "askUser" sur ce tour ("askUser": null obligatoire). '
          'Intègre les réponses dans un "uxPatch" complet et structuré pour cette étape UX (et un "specPatch" additif uniquement si un objet, attribut ou règle RG manque).';
    }
    return switch (level) {
      VibeQuestioningLevel.none =>
        'NIVEAU DE QUESTIONNEMENT : 0/4 (Aucun) — '
            'INTERDICTION d’émettre "askUser" ("askUser": null obligatoire). '
            'Produis directement un "uxPatch" complet avec des choix ergonomiques et métiers solides.',
      VibeQuestioningLevel.light =>
        'NIVEAU DE QUESTIONNEMENT : 1/4 (Léger, 1 à 2 questions) — '
            'Pose 1 à 2 questions UX clés via "askUser" (avec "default") pour lever les ambiguïtés majeures avant de produire "uxPatch".',
      VibeQuestioningLevel.balanced =>
        'NIVEAU DE QUESTIONNEMENT : 2/4 (Équilibré, 2 à 4 questions) — '
            'Pose 2 à 4 questions UX structurées via "askUser" (avec "default") adaptées à cette étape avant de finaliser "uxPatch".',
      VibeQuestioningLevel.thorough =>
        'NIVEAU DE QUESTIONNEMENT : 3/4 (Approfondi, 4 à 6 questions) — '
            'Pose 4 à 6 questions UX ciblées via "askUser" (avec "default") couvrant les parcours, arbitrages spatiaux, cas limites et micro-interactions de cette étape.',
      VibeQuestioningLevel.exhaustive =>
        'NIVEAU DE QUESTIONNEMENT : 4/4 (Exhaustif, 6 à 10 questions) — '
            'Pose 6 à 10 questions UX complètes via "askUser" (avec "default") pour couvrir l’ensemble des détails d’ergonomie, d’états et de traçabilité de cette étape.',
    };
  }

  /// Construit le prompt automatique d'amorce lorsqu'on entre dans une étape UX sans historique.
  static String buildStageKickoffPrompt(
    SpecForgeProject project,
    UxForgeStage stage, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) => switch (stage) {
    UxForgeStage.userJourneys =>
      'Nous démarrons l’étape UX 1 (Parcours utilisateurs & Flows) du projet « ${project.name} ». '
          'En t’appuyant sur les personas, les exigences fonctionnelles (EXF) et les cas d’usage du cahier des charges, '
          'propose ou pose les questions nécessaires pour modéliser les parcours bout-en-bout (JRN-001…), leurs étapes, embranchements et critères de succès.',
    UxForgeStage.iaNavigation =>
      'Nous passons à l’étape UX 2 (Architecture & Navigation) du projet « ${project.name} ». '
          'En t’appuyant sur les modules, les parcours utilisateurs JRN-xxx et les règles d’habilitation RG-xxx, '
          'pose tes questions ou structure le shell applicatif, l’arborescence des routes (standard, modales, documents A4) et la graine de thème visuel Material 3.',
    UxForgeStage.screenBlueprints =>
      'Nous passons à l’étape UX 3 (Écrans, Zones & Interactions) du projet « ${project.name} ». '
          'En t’appuyant sur les parcours JRN-xxx, les routes définies, les objets métiers et les règles de gestion RG-xxx, '
          'conçois ou clarifie les schémas directeurs d’écrans (SCR-001…), leurs patterns spatiaux, leurs zones, leurs liaisons d’attributs atomiques, la hiérarchie d’actions et les états UX.\n\n'
          '${SpecPromptBuilder.businessObjectPreferencesDirective(project, modelPreferencesOverride: modelPreferencesOverride)}',
    UxForgeStage.uxReviewExport =>
      'Nous passons à l’étape UX 4 (Audit UX & Export SuperDesigner) du projet « ${project.name} ». '
          'Exécute un audit complet de cohérence et de traçabilité Métier↔UX (personas, EXF, cas d’usage, routes, objets/attributs et règles RG-xxx), '
          'remonte les écarts éventuels et prépare le handoff vers SuperDesigner (DESIGN.md et squelettes d’écrans) ainsi que la suite BDD/TDD.',
  };

  /// Construit un résumé JSON compact du modèle de spécification métier, conçu
  /// pour tenir dans un budget de tokens maîtrisé tout en invitant l'agent UX
  /// à appeler `inspect_business_object` pour les sous-attributs imbriqués.
  static Map<String, Object?> buildCompactSpecCatalogJson(
    SpecForgeProject project,
  ) => <String, Object?>{
    'projectName': project.name,
    'initialIdea': project.initialIdea,
    'lexicon': <String, Object?>{
      'terms': [
        for (final t in project.lexicon.terms)
          <String, Object?>{
            'id': t.id,
            'term': t.term,
            if (t.definition.isNotEmpty) 'definition': t.definition,
            if (t.synonyms.isNotEmpty) 'synonyms': t.synonyms,
            if (t.domain.isNotEmpty) 'domain': t.domain,
          },
      ],
      if (project.lexicon.ambiguousTerms.isNotEmpty)
        'ambiguousTerms': project.lexicon.ambiguousTerms,
      if (project.lexicon.conventions.isNotEmpty)
        'conventions': project.lexicon.conventions,
    },
    'vision': <String, Object?>{
      if (project.vision.ideaSummary.isNotEmpty)
        'ideaSummary': project.vision.ideaSummary,
      if (project.vision.valueProposition.isNotEmpty)
        'valueProposition': project.vision.valueProposition,
      if (project.vision.objectives.isNotEmpty)
        'objectives': project.vision.objectives,
      'personas': [
        for (final p in project.vision.personas)
          <String, Object?>{
            'id': p.id,
            'name': p.name,
            if (p.role.isNotEmpty) 'role': p.role,
            if (p.goals.isNotEmpty) 'goals': p.goals,
            if (p.painPoints.isNotEmpty) 'painPoints': p.painPoints,
          },
      ],
      if (project.vision.constraints.isNotEmpty)
        'constraints': project.vision.constraints,
    },
    'cahierDesCharges': <String, Object?>{
      'modules': [
        for (final m in project.cahierDesCharges.modules)
          <String, Object?>{
            'id': m.id,
            'name': m.name,
            if (m.description.isNotEmpty) 'description': m.description,
          },
      ],
      'functionalRequirements': [
        for (final r in project.cahierDesCharges.functionalRequirements)
          <String, Object?>{
            'id': r.id,
            'code': r.code,
            'title': r.title,
            'priority': r.priority.name,
            if (r.moduleId.isNotEmpty) 'moduleId': r.moduleId,
            if (r.actorIds.isNotEmpty) 'actorIds': r.actorIds,
            if (r.acceptanceCriteria.isNotEmpty)
              'acceptanceCriteria': r.acceptanceCriteria,
          },
      ],
      'useCases': [
        for (final u in project.cahierDesCharges.useCases)
          <String, Object?>{
            'id': u.id,
            'title': u.title,
            if (u.actorId.isNotEmpty) 'actorId': u.actorId,
            if (u.mainFlow.isNotEmpty) 'mainFlow': u.mainFlow,
            if (u.alternativeFlows.isNotEmpty)
              'alternativeFlows': u.alternativeFlows,
          },
      ],
      'nonFunctionalRequirements': [
        for (final n in project.cahierDesCharges.nonFunctionalRequirements)
          <String, Object?>{
            'id': n.id,
            'code': n.code,
            'category': n.category.name,
            'title': n.title,
            if (n.targetMetric.isNotEmpty) 'targetMetric': n.targetMetric,
          },
      ],
    },
    'businessObjectsHint':
        'Résumé racine uniquement : appelle `inspect_business_object(objectIdOrName: "...")` '
            'pour consulter les sous-attributs imbriqués (`children`), les exemples et `schemaConstraints` complets.',
    'businessObjects': [
      for (final o in project.businessObjects)
        <String, Object?>{
          'id': o.id,
          'name': o.name,
          'technicalName': o.technicalName,
          'aggregateRoot': o.aggregateRoot,
          'totalAttributeCount': o.totalAttributeCount,
          if (o.lifecycleStates.isNotEmpty)
            'lifecycleStates': [
              for (final s in o.lifecycleStates)
                <String, Object?>{
                  'name': s.name,
                  if (s.label.isNotEmpty) 'label': s.label,
                  if (s.isInitial) 'isInitial': true,
                  if (s.isTerminal) 'isTerminal': true,
                },
            ],
          if (o.relations.isNotEmpty)
            'relations': [
              for (final r in o.relations)
                <String, Object?>{
                  'id': r.id,
                  'name': r.name,
                  'targetObjectId': r.targetObjectId,
                  'cardinality': r.cardinality.name,
                  if (r.required) 'required': true,
                },
            ],
          'attributes': [
            for (final a in o.attributes)
              <String, Object?>{
                'name': a.name,
                'type': a.type.name,
                if (a.required) 'required': true,
                if (a.isArray) 'isArray': true,
                if (a.referenceObjectId.isNotEmpty)
                  'referenceObjectId': a.referenceObjectId,
                if (a.enumValues.isNotEmpty) 'enumValues': a.enumValues,
                if (a.children.isNotEmpty) 'childCount': a.children.length,
              },
          ],
        },
    ],
    'businessRulesHint':
        'Résumé compact : appelle `get_business_rules` pour inspecter conditions, déclencheurs, effets et messages d’erreur.',
    'businessRules': [
      for (final r in project.businessRules)
        <String, Object?>{
          'id': r.id,
          'code': r.code,
          'title': r.title,
          'category': r.category.name,
          'targetObjectIds': r.targetObjectIds,
          if (r.targetAttributes.isNotEmpty)
            'targetAttributes': r.targetAttributes,
        },
    ],
  };

  /// Assemble le prompt complet envoyé à l'agent UX de [stage] pour le tour courant.
  static String buildTurnPrompt({
    required SpecForgeProject project,
    required UxForgeStage stage,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    int maxHistoryEntries = 10,
    CompanyGlossary? companyGlossary,
    BusinessObjectModelPreferences? modelPreferencesOverride,
    String? focusedJourneyId,
    String? focusedRouteId,
    String? focusedScreenId,
    UxLayoutZoneName? focusedZone,
    Set<String>? toolNames,
  }) {
    final agent = UxStageAgent.forStage(stage);
    final stageState = project.uxSpec.stageStateFor(stage);
    final specCatalogJson = const JsonEncoder.withIndent('  ')
        .convert(buildCompactSpecCatalogJson(project));
    final uxContextJson = const JsonEncoder.withIndent('  ')
        .convert(project.uxSpec.toCompactContextJson(stage));

    final previousSummaries = <String>[
      for (final specStage in project.enabledSpecStages)
        if (project.stageStateFor(specStage).stageSummary.trim().isNotEmpty)
          '- Spec ${project.stepNumberFor(specStage)} (${specStage.title}) : '
              '${project.stageStateFor(specStage).stageSummary.trim()}',
      for (final uxStage in UxForgeStage.values)
        if (uxStage.index < stage.index &&
            project.uxSpec.stageStateFor(uxStage).stageSummary.trim().isNotEmpty)
          '- UX ${uxStage.stepNumber} (${uxStage.title}) : '
              '${project.uxSpec.stageStateFor(uxStage).stageSummary.trim()}',
    ];

    final history = _buildHistory(
      stageState.messages,
      maxEntries: maxHistoryEntries,
    );

    final shouldInjectModelingRules =
        stage == UxForgeStage.screenBlueprints ||
        stage == UxForgeStage.uxReviewExport ||
        project.businessObjects.isNotEmpty ||
        _mentionsBusinessModeling(project, userInput, focusedScreenId);

    final buffer = StringBuffer()
      ..writeln(
        'ÉTAPE UX ACTIVE : ${stage.stepNumber}/${UxForgeStage.values.length} — ${stage.title} (Agent : ${agent.stage.agentTitle})',
      )
      ..writeln()
      ..writeln(
        uxQuestioningDirective(
          level: questioningLevel,
          afterAskUserReply: afterAskUserReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
        ),
      );

    if (shouldInjectModelingRules) {
      buffer
        ..writeln()
        ..writeln(
          SpecPromptBuilder.businessObjectPreferencesDirective(
            project,
            modelPreferencesOverride: modelPreferencesOverride,
          ),
        )
        ..writeln()
        ..writeln(
          'RÈGLES DE MODÉLISATION DES ATTRIBUTS (POUR TOUT "specPatch" ADDITIF) :\n'
          '${SpecStageAgent.attributeModelingRules}',
        );
    }

    buffer
      ..writeln()
      ..writeln(
        SpecForgeToolRegistry.toolsGuide(
          toolNames: toolNames ?? SpecForgeToolRegistry.uxStageToolNames,
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
        ..writeln('SYNTHÈSE DES ÉTAPES PRÉCÉDENTES (SPEC & UX) :')
        ..writeln(previousSummaries.join('\n'));
    }

    buffer
      ..writeln()
      ..writeln('CATALOGUE COMPACT DES SPÉCIFICATIONS MÉTIERS (JSON) :')
      ..writeln(specCatalogJson)
      ..writeln()
      ..writeln('ÉTAT COURANT DU VOLET UX (JSON) :')
      ..writeln(uxContextJson);

    final focusBlock = buildUxFocusScopeBlock(
      project: project,
      focusedJourneyId: focusedJourneyId,
      focusedRouteId: focusedRouteId,
      focusedScreenId: focusedScreenId,
      focusedZone: focusedZone,
    );
    if (focusBlock.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(focusBlock);
    }

    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT DE CETTE ÉTAPE UX :')
        ..writeln(history);
    }

    buffer
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR POUR CE TOUR :')
      ..writeln(userInput.trim());

    return buffer.toString();
  }

  /// Construit le bloc « FOCUS COURANT DANS L'ATELIER UX » (chaîne vide si aucune sélection active).
  static String buildUxFocusScopeBlock({
    required SpecForgeProject project,
    String? focusedJourneyId,
    String? focusedRouteId,
    String? focusedScreenId,
    UxLayoutZoneName? focusedZone,
  }) {
    final ux = project.uxSpec;
    final journey = (focusedJourneyId != null && focusedJourneyId.trim().isNotEmpty)
        ? ux.findJourney(focusedJourneyId)
        : null;
    final route = (focusedRouteId != null && focusedRouteId.trim().isNotEmpty)
        ? ux.navigation.findRoute(focusedRouteId)
        : null;
    final screen = (focusedScreenId != null && focusedScreenId.trim().isNotEmpty)
        ? ux.findScreen(focusedScreenId)
        : null;

    if (journey == null &&
        route == null &&
        screen == null &&
        focusedZone == null) {
      return '';
    }

    final buf = StringBuffer()
      ..writeln('FOCUS COURANT DANS L’ATELIER UX (SCOPE DE SÉLECTION) :');
    if (journey != null) {
      buf.writeln(
        '- Parcours sélectionné : ${journey.code} — ${journey.name} (id: ${journey.id}, canal: ${journey.channel.name}, ${journey.steps.length} étape(s))',
      );
    }
    if (route != null) {
      buf.writeln(
        '- Route sélectionnée : ${route.path} — ${route.title} (id: ${route.id}, pageType: ${route.pageType.name})',
      );
    }
    if (screen != null) {
      buf.writeln(
        '- Écran sélectionné : ${screen.code} — ${screen.name} (id: ${screen.id}, routeId: ${screen.routeId}, pattern: ${screen.pattern.name}, objet principal: ${screen.primaryObjectId.isEmpty ? "(aucun)" : screen.primaryObjectId})',
      );
      if (focusedZone != null) {
        final zoneSpec = screen.zoneFor(focusedZone);
        if (zoneSpec != null) {
          final zoneJson = const JsonEncoder.withIndent('  ')
              .convert(zoneSpec.toJson());
          buf
            ..writeln(
              '- Zone ciblée sur l’écran : ${focusedZone.name} (${focusedZone.label})',
            )
            ..writeln('- Détail JSON de la zone sélectionnée :')
            ..writeln(zoneJson);
        } else {
          buf.writeln(
            '- Zone ciblée sur l’écran : ${focusedZone.name} (${focusedZone.label}, non encore configurée sur cet écran)',
          );
        }
      }
    } else if (focusedZone != null) {
      buf.writeln(
        '- Zone ciblée : ${focusedZone.name} (${focusedZone.label})',
      );
    }
    buf.writeln(
      '- Consigne scope ciblé : si l’utilisateur fait référence à « ce parcours », « cette route », « cet écran » ou « cette zone », applique la mise à jour en priorité sur l’élément sélectionné en conservant son `id`.',
    );
    return buf.toString().trimRight();
  }

  static bool _mentionsBusinessModeling(
    SpecForgeProject project,
    String userInput,
    String? focusedScreenId,
  ) {
    if (focusedScreenId != null && focusedScreenId.trim().isNotEmpty) {
      final scr = project.uxSpec.findScreen(focusedScreenId);
      if (scr != null && scr.primaryObjectId.isNotEmpty) return true;
    }
    final lower = userInput.toLowerCase();
    const keywords = <String>[
      'objet',
      'attribut',
      'champ',
      'specpatch',
      'rg-',
      'règle',
      'regle',
      'enum',
      'statut',
      'relation',
    ];
    if (keywords.any(lower.contains)) return true;
    for (final obj in project.businessObjects) {
      if (lower.contains(obj.name.toLowerCase()) ||
          lower.contains(obj.technicalName.toLowerCase())) {
        return true;
      }
    }
    return false;
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
