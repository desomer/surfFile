/// Construction des prompts par tour pour les agents IA spécialisés de `super_spec_forge` ([SpecPromptBuilder]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/company_glossary.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_stage_chat.dart';
import 'spec_stage_agent.dart';

/// Assemble les prompts contextuels et consignes de questionnement pour chaque étape.
abstract final class SpecPromptBuilder {
  /// Construit la directive de questionnement adaptée au niveau choisi et au tour courant.
  static String questioningDirective({
    required VibeQuestioningLevel level,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
  }) {
    if (forceFollowUpQuestions) {
      return 'NIVEAU DE QUESTIONNEMENT : + de questions demandé (2 à 4 questions complémentaires OBLIGATOIRES) — '
          'Pose impérativement 2 à 4 nouvelles questions ciblées et non redondantes via "askUser" '
          '(avec des valeurs "default" pertinentes) pour approfondir cette étape, et laisse "specPatch": null sur ce tour.';
    }
    if (afterAskUserReply) {
      return 'NIVEAU DE QUESTIONNEMENT : Réponses utilisateur reçues — '
          'INTERDICTION d’émettre "askUser" sur ce tour ("askUser": null obligatoire). '
          'Intègre les réponses dans un "specPatch" complet et structuré pour cette étape.';
    }
    return switch (level) {
      VibeQuestioningLevel.none =>
        'NIVEAU DE QUESTIONNEMENT : 0/4 (Aucun) — '
            'INTERDICTION d’émettre "askUser" ("askUser": null obligatoire). '
            'Produis directement un "specPatch" complet avec des hypothèses métier solides.',
      VibeQuestioningLevel.light =>
        'NIVEAU DE QUESTIONNEMENT : 1/4 (Léger, 1 à 2 questions) — '
            'Pose 1 à 2 questions clés via "askUser" (avec "default") pour lever les ambiguïtés majeures avant de produire "specPatch".',
      VibeQuestioningLevel.balanced =>
        'NIVEAU DE QUESTIONNEMENT : 2/4 (Équilibré, 2 à 4 questions) — '
            'Pose 2 à 4 questions structurées via "askUser" (avec "default") adaptées à cette étape avant de finaliser "specPatch".',
      VibeQuestioningLevel.thorough =>
        'NIVEAU DE QUESTIONNEMENT : 3/4 (Approfondi, 4 à 6 questions) — '
            'Pose 4 à 6 questions ciblées via "askUser" (avec "default") couvrant les choix métier, cas limites et contraintes de cette étape.',
      VibeQuestioningLevel.exhaustive =>
        'NIVEAU DE QUESTIONNEMENT : 4/4 (Exhaustif, 6 à 10 questions) — '
            'Pose 6 à 10 questions complètes via "askUser" (avec "default") pour couvrir l’ensemble des détails et cas limites de cette étape.',
    };
  }

  /// Construit la directive complète des préférences du modèle pour l'IA.
  static String businessObjectPreferencesDirective(
    SpecForgeProject project, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) => (modelPreferencesOverride ?? project.businessObjectModelPreferences)
      .toPromptDirective();

  /// Alias rétrocompatible vers [businessObjectPreferencesDirective].
  static String businessObjectLanguageDirective(
    SpecForgeProject project, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) => businessObjectPreferencesDirective(
    project,
    modelPreferencesOverride: modelPreferencesOverride,
  );

  /// Construit le prompt automatique d'amorce lorsqu'on entre dans une étape sans historique.
  static String buildStageKickoffPrompt(
    SpecForgeProject project,
    SpecForgeStage stage, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) => switch (stage) {
    SpecForgeStage.lexicon =>
      'Voici l’idée initiale du projet « ${project.name} » : « ${project.initialIdea} ». '
          'Identifie les termes métier clés, acronymes et ambiguïtés terminologiques, et pose tes questions pour établir le lexique métier partagé.',
    SpecForgeStage.vision =>
      'Nous passons à l’étape 2 (Cadrage & Acteurs). En t’appuyant sur l’idée initiale « ${project.initialIdea} » et le lexique métier établi, '
          'pose tes questions de cadrage pour clarifier la vision, les objectifs, les acteurs/personas et les contraintes.',
    SpecForgeStage.specifications =>
      'Nous passons à l’étape 3 (Cahier des charges). En t’appuyant sur le lexique, le cadrage et les acteurs validés, '
          'pose les questions nécessaires (ou propose la structure) pour détailler les modules, exigences fonctionnelles MoSCoW, cas d’usage et exigences non fonctionnelles.',
    SpecForgeStage.businessObjects =>
      'Nous passons à l’étape 4 (Objets métiers). En t’appuyant sur le lexique, le cadrage et le cahier des charges, '
          'pose les questions nécessaires pour modéliser les entités métiers, leurs sous-objets, leurs attributs typés, leurs relations et leurs cycles de vie.\n\n'
          '${businessObjectLanguageDirective(project, modelPreferencesOverride: modelPreferencesOverride)}',
    SpecForgeStage.businessRules =>
      'Nous passons à l’étape 5 (Règles de gestion). En t’appuyant sur les objets métiers, le lexique et le cahier des charges, '
          'pose les questions nécessaires pour formaliser les règles RG-xxx (validations, calculs, transitions d’état, habilitations et déclencheurs).',
    SpecForgeStage.reviewExport =>
      'Nous passons à l’étape 6 (Revue globale & Cohérence). Audite l’ensemble du projet (lexique métier, cadrage, cahier des charges, objets métiers et règles de gestion), '
          'signale toute incohérence ou oubli éventuel et propose un résumé ou des questions d’arbitrage final.',
  };

  /// Assemble le prompt complet envoyé à l'agent de [stage] pour le tour courant.
  static String buildTurnPrompt({
    required SpecForgeProject project,
    required SpecForgeStage stage,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    int maxHistoryEntries = 10,
    CompanyGlossary? companyGlossary,
    BusinessObjectModelPreferences? modelPreferencesOverride,
    String? focusedObjectId,
    List<String> focusedAttributePath = const <String>[],
    String businessObjectFilter = '',
  }) {
    final agent = SpecStageAgent.forStage(stage);
    final stageState = project.stageStateFor(stage);
    final effectivePrefs =
        modelPreferencesOverride ?? project.businessObjectModelPreferences;
    final contextJson = const JsonEncoder.withIndent('  ')
        .convert(project.toCompactContextJson(stage));

    final previousSummaries = <String>[];
    for (final s in SpecForgeStage.values) {
      if (s.index >= stage.index) break;
      final summary = project.stageStateFor(s).stageSummary.trim();
      if (summary.isNotEmpty) {
        previousSummaries.add(
          '- Étape ${s.stepNumber} (${s.title}) : $summary',
        );
      }
    }

    final history = _buildHistory(
      stageState.messages,
      maxEntries: maxHistoryEntries,
    );

    final buffer = StringBuffer()
      ..writeln(
        'ÉTAPE ACTIVE : ${stage.stepNumber}/${SpecForgeStage.values.length} — ${stage.title} (Agent : ${agent.stage.agentTitle})',
      )
      ..writeln()
      ..writeln(
        questioningDirective(
          level: questioningLevel,
          afterAskUserReply: afterAskUserReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
        ),
      );

    if (stage == SpecForgeStage.businessObjects ||
        (stage.index > SpecForgeStage.businessObjects.index &&
            !effectivePrefs.isDefault)) {
      buffer
        ..writeln()
        ..writeln(
          businessObjectPreferencesDirective(
            project,
            modelPreferencesOverride: modelPreferencesOverride,
          ),
        );
    }

    final glossaryBlock = companyGlossaryBlock(companyGlossary);
    if (glossaryBlock.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(glossaryBlock);
    }

    if (previousSummaries.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('SYNTHÈSE DES ÉTAPES PRÉCÉDENTES :')
        ..writeln(previousSummaries.join('\n'));
    }

    buffer
      ..writeln()
      ..writeln('ÉTAT COURANT DU PROJET (JSON) :')
      ..writeln(contextJson);

    final focusBlock = buildFocusScopeBlock(
      project: project,
      focusedObjectId: focusedObjectId,
      focusedAttributePath: focusedAttributePath,
      businessObjectFilter: businessObjectFilter,
    );
    if (focusBlock.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(focusBlock);
    }

    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT DE CETTE ÉTAPE :')
        ..writeln(history);
    }

    buffer
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR POUR CE TOUR :')
      ..writeln(userInput.trim());

    return buffer.toString();
  }

  /// Bloc « GLOSSAIRE D’ENTREPRISE » partagé par les agents de la spec et du
  /// design (chaîne vide si [companyGlossary] est absent ou vide).
  static String companyGlossaryBlock(CompanyGlossary? companyGlossary) {
    if (companyGlossary == null || !companyGlossary.hasContent) return '';
    final glossaryJson = const JsonEncoder.withIndent('  ')
        .convert(companyGlossary.toPromptContextJson());
    return 'GLOSSAIRE D’ENTREPRISE (RÉFÉRENTIEL PRIORITAIRE — respecte les termes validés et évite les "forbiddenTerms") :\n'
        '$glossaryJson';
  }

  /// Bloc « FOCUS COURANT » décrivant l'objet, l'attribut sélectionné et le
  /// filtre actif de l'arbre [treeLabel] (chaîne vide sans objet ni filtre).
  static String buildFocusScopeBlock({
    required SpecForgeProject project,
    required String? focusedObjectId,
    required List<String> focusedAttributePath,
    required String businessObjectFilter,
    String treeLabel = 'Arbre & Inspecteur',
  }) {
    final buf = StringBuffer();
    final trimmedFilter = businessObjectFilter.trim();
    final focusedObj = (focusedObjectId != null && focusedObjectId.isNotEmpty)
        ? project.findBusinessObject(focusedObjectId)
        : null;

    if (focusedObj == null && trimmedFilter.isEmpty) {
      return '';
    }

    buf.writeln('FOCUS COURANT DANS L’ATELIER (SCOPE DE SÉLECTION) :');
    if (focusedObj != null) {
      buf.writeln(
        '- Objet métier sélectionné : ${focusedObj.name} (${focusedObj.technicalName}, id: ${focusedObj.id})',
      );
      final resolvedAttr = _resolveAttributeChain(
        focusedObj.attributes,
        focusedAttributePath,
      );
      if (resolvedAttr != null) {
        final dotPath = resolvedAttr.names.join('.');
        final attrJson = const JsonEncoder.withIndent('  ')
            .convert(resolvedAttr.attribute.toJson());
        buf
          ..writeln(
            '- Attribut sélectionné : ${focusedObj.technicalName}.$dotPath (id: ${resolvedAttr.attribute.id}, type: ${resolvedAttr.attribute.type.name})',
          )
          ..writeln('- Détail JSON de l’attribut sélectionné :')
          ..writeln(attrJson)
          ..writeln(
            '- Consigne scope ciblé : si l’utilisateur fait référence à « cet attribut », « celui sélectionné », « modifie-le », etc., applique la modification directement sur cet attribut en conservant son `id` (${resolvedAttr.attribute.id}).',
          );
      } else {
        buf.writeln(
          '- Attribut sélectionné : aucun sous-attribut ciblé (l’objet métier entier est sélectionné).',
        );
      }
    }
    if (trimmedFilter.isNotEmpty) {
      buf.writeln('- Filtre actif dans « $treeLabel » : "$trimmedFilter"');
    }
    return buf.toString().trimRight();
  }

  static ({BusinessAttribute attribute, List<String> names})?
  _resolveAttributeChain(List<BusinessAttribute> roots, List<String> pathIds) {
    if (pathIds.isEmpty) return null;
    var current = roots;
    final names = <String>[];
    BusinessAttribute? last;
    for (final id in pathIds) {
      final found = current.where((a) => a.id == id).firstOrNull;
      if (found == null) return null;
      names.add(found.name);
      last = found;
      current = found.children;
    }
    return last == null ? null : (attribute: last, names: names);
  }

  /// Assemble le prompt complet du chat global de questions sur l'ensemble du projet.
  static String buildGlobalQuestionPrompt({
    required SpecForgeProject project,
    required String userInput,
    int maxHistoryEntries = 12,
    CompanyGlossary? companyGlossary,
  }) {
    final fullSnapshot = const JsonEncoder.withIndent('  ')
        .convert(project.toCompactContextJson(SpecForgeStage.reviewExport));

    final stageSummaries = <String>[
      for (final s in SpecForgeStage.values)
        if (project.stageStateFor(s).stageSummary.trim().isNotEmpty)
          '- Étape ${s.stepNumber} (${s.title}) [${project.stageStateFor(s).status.label}] : ${project.stageStateFor(s).stageSummary.trim()}',
    ];

    final history = _buildHistory(
      project.globalChatMessages,
      maxEntries: maxHistoryEntries,
    );

    final buffer = StringBuffer()
      ..writeln('MODE : CHAT GLOBAL DE QUESTIONS SUR LE PROJET')
      ..writeln(
        'ÉTAPE ACTIVE DU WIZARD : ${project.currentStage.stepNumber}/${SpecForgeStage.values.length} (${project.currentStage.title})',
      );

    if (stageSummaries.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('SYNTHÈSES DES ÉTAPES :')
        ..writeln(stageSummaries.join('\n'));
    }

    if (companyGlossary != null && companyGlossary.hasContent) {
      final glossaryJson = const JsonEncoder.withIndent('  ')
          .convert(companyGlossary.toPromptContextJson());
      buffer
        ..writeln()
        ..writeln('GLOSSAIRE D’ENTREPRISE GLOBAL :')
        ..writeln(glossaryJson);
    }

    buffer
      ..writeln()
      ..writeln('ÉTAT GLOBAL DU PROJET (JSON) :')
      ..writeln(fullSnapshot);

    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT DU CHAT GLOBAL :')
        ..writeln(history);
    }

    buffer
      ..writeln()
      ..writeln('QUESTION UTILISATEUR :')
      ..writeln(userInput.trim());

    return buffer.toString();
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
