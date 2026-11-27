/// Construction des prompts par tour pour les agents IA spécialisés de `super_spec_forge` ([SpecPromptBuilder]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/company_glossary.dart';
import '../models/domain_catalog.dart';
import '../models/event_storming_spec.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_initiative.dart';
import '../models/spec_stage_chat.dart';
import '../services/event_storming_operations.dart';
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

  /// Plafond d'objets métiers inter-features injectés dans le catalogue compact du prompt.
  static const int maxSiblingCatalogObjects = 30;

  /// Plafond d'attributs résumés par objet métier dans le catalogue inter-features du prompt.
  static const int maxSiblingCatalogAttributesPerObject = 20;

  /// Étapes du wizard Spec dans lesquelles le catalogue d'objets des features sœurs est injecté à chaque tour.
  static const Set<SpecForgeStage> _siblingObjectsTurnStages = <SpecForgeStage>{
    SpecForgeStage.eventStorming,
    SpecForgeStage.businessObjects,
    SpecForgeStage.exampleMapping,
    SpecForgeStage.businessRules,
    SpecForgeStage.reviewExport,
  };

  /// Construit le catalogue compact en lecture seule des objets métiers définis
  /// dans les features sœurs non archivées du projet, accompagné des règles
  /// d'architecture `additive_warn_on_validated` (chaîne vide si sans objet).
  static String buildSiblingFeaturesObjectsDirective(SpecForgeProject project) {
    if (project.allFeatures.length <= 1) return '';
    final siblingFeatures = <SpecFeatureSpec>[
      for (final f in project.allFeatures)
        if (f.id != project.activeFeatureId &&
            f.effectiveStatus != SpecPortfolioStatus.archived &&
            f.businessObjects.isNotEmpty)
          f,
    ];
    if (siblingFeatures.isEmpty) return '';

    final groups = <_SiblingObjectPromptGroup>[];
    for (final feature in siblingFeatures) {
      for (final obj in feature.businessObjects) {
        final objIdLower = obj.id.trim().toLowerCase();
        final techLower = obj.technicalName.trim().toLowerCase();
        _SiblingObjectPromptGroup? existing;
        for (final group in groups) {
          if (group.matchesIdentity(objIdLower, techLower)) {
            existing = group;
            break;
          }
        }
        if (existing == null) {
          groups.add(_SiblingObjectPromptGroup.initial(feature, obj));
        } else {
          existing.addDefinition(feature, obj);
        }
      }
    }
    if (groups.isEmpty) return '';

    final activeObjects = project.activeFeature.businessObjects;
    final displayedGroups = groups.length <= maxSiblingCatalogObjects
        ? groups
        : groups.sublist(0, maxSiblingCatalogObjects);

    final buf = StringBuffer()
      ..writeln(
        'CATALOGUE DES OBJETS MÉTIERS DES AUTRES FEATURES DU PROJET (LECTURE SEULE — ${groups.length} objet(s)) :',
      );

    for (final group in displayedGroups) {
      final canonical = group.canonicalObject;
      final isPresentInActive = activeObjects.any(
        (o) => group.matchesIdentity(
          o.id.trim().toLowerCase(),
          o.technicalName.trim().toLowerCase(),
        ),
      );
      final presenceLabel = isPresentInActive
          ? 'déjà présent dans la feature active'
          : 'disponible dans les autres features';
      final attrs = group.mergedAttributes;
      final shownAttrs = attrs.length <= maxSiblingCatalogAttributesPerObject
          ? attrs
          : attrs.sublist(0, maxSiblingCatalogAttributesPerObject);
      final attrTokens = <String>[
        for (final a in shownAttrs) _formatCompactSiblingAttribute(a),
      ];
      final extraAttrCount = attrs.length - shownAttrs.length;
      final attrSummary = attrTokens.isEmpty
          ? 'aucun attribut'
          : (extraAttrCount > 0
                ? '${attrTokens.join(', ')}, … (+$extraAttrCount autre(s))'
                : attrTokens.join(', '));

      buf.writeln(
        '- `${canonical.technicalName}` (id: `${canonical.id}`, nom: « ${canonical.name} ») '
        '— défini dans : ${group.featureBadges.join(', ')} '
        '— statut local : $presenceLabel '
        '— attributs : [$attrSummary]',
      );
    }

    final omittedObjectsCount = groups.length - displayedGroups.length;
    if (omittedObjectsCount > 0) {
      buf.writeln(
        '- … (+$omittedObjectsCount autre(s) objet(s) disponible(s) via l’outil `list_sibling_features_business_objects`).',
      );
    }

    buf
      ..writeln()
      ..writeln(
        'POLITIQUE DE PARTAGE INTER-FEATURES — additive_warn_on_validated :',
      )
      ..writeln(
        '1. **Réutilisation canonique obligatoire** : si la feature active (${project.activeFeature.displayLabel}) doit manipuler ou référencer une entité déjà présente dans une autre feature du projet, réutilise **exactement son `id` et son `technicalName`** (et ses noms d\'attributs existants) au lieu de créer un doublon ou un synonyme. Utilise l\'outil `list_sibling_features_business_objects` pour inspecter sa structure complète avant de la reprendre dans `businessObjects`.',
      )
      ..write(
        '2. **Gouvernance `additive_warn_on_validated`** : privilégie les extensions additives compatibles (nouveaux attributs optionnels, nouvelles valeurs d\'énumération, nouveaux états/transitions). Si un objet appartient à une feature au statut **Validée**, évite de supprimer, renommer ou retyper de manière incompatible ses attributs existants (ou signale explicitement l\'impact à l\'utilisateur dans `message` / `askUser`).',
      );

    return buf.toString();
  }

  static String _formatCompactSiblingAttribute(BusinessAttribute attr) {
    final arraySuffix = attr.isArray ? '[]' : '';
    final requiredSuffix = attr.required ? '!' : '';
    return '${attr.name}: ${attr.type.dslKeyword}$arraySuffix$requiredSuffix';
  }

  /// Construit le prompt automatique d'amorce lorsqu'on entre dans une étape sans historique.
  static String buildStageKickoffPrompt(
    SpecForgeProject project,
    SpecForgeStage stage, {
    BusinessObjectModelPreferences? modelPreferencesOverride,
  }) {
    final step = project.stepNumberFor(stage);
    final hasEventStorming = project.isStageEnabled(
      SpecForgeStage.eventStorming,
    );
    final hasExampleMapping = project.isStageEnabled(
      SpecForgeStage.exampleMapping,
    );
    final siblingDirective =
        (stage == SpecForgeStage.eventStorming ||
            stage == SpecForgeStage.businessObjects)
        ? buildSiblingFeaturesObjectsDirective(project)
        : '';
    final siblingSuffix = siblingDirective.isEmpty
        ? ''
        : '\n\n$siblingDirective';
    return switch (stage) {
      SpecForgeStage.vision =>
        project.hasSingleDefaultFeature
            ? 'Voici l’idée initiale du projet « ${project.name} » : « ${project.initialIdea} ». '
                  '${project.lexicon.terms.isNotEmpty ? 'En tenant compte des ${project.lexicon.terms.length} terme(s) déjà présents dans le lexique partagé, ' : ''}'
                  'pose tes questions de cadrage pour clarifier la vision, les objectifs, les acteurs/personas, le hors-périmètre et les contraintes.'
            : 'Nous démarrons l’étape $step (Cadrage & Acteurs) pour la feature « ${project.activeFeature.displayLabel} » '
                  '(initiative « ${project.activeInitiative.displayLabel} ») du projet « ${project.name} ».'
                  '${project.activeFeature.description.isNotEmpty ? ' Périmètre de la feature : « ${project.activeFeature.description} ».' : ''} '
                  '${project.lexicon.terms.isNotEmpty ? 'En t’appuyant sur les ${project.lexicon.terms.length} terme(s) du lexique partagé du projet, ' : ''}'
                  'pose tes questions de cadrage pour clarifier la vision, les objectifs, les acteurs/personas et les contraintes.',
      SpecForgeStage.lexicon =>
        project.hasSingleDefaultFeature
            ? 'Nous passons à l’étape $step (Lexique métier — référentiel partagé du projet). '
                  'En t’appuyant sur l’idée initiale « ${project.initialIdea} » et le cadrage établi, '
                  'identifie les termes métier clés, acronymes et ambiguïtés terminologiques, et pose tes questions pour établir le lexique métier partagé.'
            : 'Nous travaillons sur le lexique métier partagé (étape $step) pour la feature « ${project.activeFeature.displayLabel} » '
                  '(initiative « ${project.activeInitiative.displayLabel} ») du projet « ${project.name} ».'
                  '${project.activeFeature.description.isNotEmpty ? ' Périmètre de la feature : « ${project.activeFeature.description} ».' : ''} '
                  'En tenant compte du cadrage de la feature, de l’idée du projet (« ${project.initialIdea} ») et des ${project.lexicon.terms.length} terme(s) déjà présents dans le lexique partagé, '
                  'identifie les termes métier clés, sigles et ambiguïtés terminologiques à ajouter ou préciser.',
      SpecForgeStage.specifications =>
        'Nous passons à l’étape $step (Cahier des charges). En t’appuyant sur le cadrage, les acteurs et le lexique métier validés, '
            'pose les questions nécessaires (ou propose la structure) pour détailler les modules, exigences fonctionnelles MoSCoW, cas d’usage et exigences non fonctionnelles.',
      SpecForgeStage.eventStorming =>
        'Nous passons à l’étape $step (Event Storming — DSL v1.0). En t’appuyant sur le lexique, les acteurs et le cahier des charges (modules, exigences et cas d’usage), '
            'modélise un document par Bounded Context (`dsl_version: "1.0"`, `meta`, `catalog` avec `ACT-*`/`AGG-*`/`EXT-*`, `flow[]` chronologique) : '
            'commandes à l’infinitif (bleu), événements au passé composé (orange) ou `outcomes` exclusifs, politiques « Quand…, alors… » (violet), read models (vert), systèmes externes (rose pâle), synchronisations `all_of` / `any_of`, `backlog` et `hotspots` (rose vif).$siblingSuffix',
      SpecForgeStage.businessObjects =>
        'Nous passons à l’étape $step (Objets métiers). En t’appuyant sur le lexique, le cadrage, le cahier des charges${hasEventStorming ? ' et les agrégats/événements de l’Event Storming' : ''}, '
            'pose les questions nécessaires pour modéliser les entités métiers, leurs sous-objets, leurs attributs typés, leurs relations et leurs cycles de vie.\n\n'
            '${businessObjectLanguageDirective(project, modelPreferencesOverride: modelPreferencesOverride)}$siblingSuffix',
      SpecForgeStage.exampleMapping =>
        'Nous passons à l’étape $step (Example Mapping). En t’appuyant sur les objets métiers modélisés, le lexique${hasEventStorming ? ', l’Event Storming' : ''} et les cas d’usage du cahier des charges, '
            'explore avec l’utilisateur les règles (cartes bleues), exemples concrets et cas aux limites (cartes vertes) et zones d’ombre (cartes rouges) '
            'pour affiner les attributs, bornes JSON Schema, énumérations et cycles de vie des objets métiers.\n\n'
            '${businessObjectLanguageDirective(project, modelPreferencesOverride: modelPreferencesOverride)}',
      SpecForgeStage.businessRules =>
        'Nous passons à l’étape $step (Règles de gestion). En t’appuyant sur '
            '${hasEventStorming ? 'l’Event Storming (politiques, commandes, événements), ' : ''}'
            'les objets métiers, '
            '${hasExampleMapping ? 'les tableaux d’Example Mapping (règles bleues, exemples verts et questions résolues), ' : ''}'
            'le lexique et le cahier des charges, '
            'pose les questions nécessaires pour formaliser les règles RG-xxx (validations, calculs, transitions d’état, habilitations et déclencheurs).',
      SpecForgeStage.reviewExport =>
        'Nous passons à l’étape $step (Revue globale & Cohérence). Audite l’ensemble du projet ('
            'lexique métier, cadrage, cahier des charges'
            '${hasEventStorming ? ', Event Storming' : ''}'
            ', objets métiers'
            '${hasExampleMapping ? ', Example Mapping' : ''}'
            ' et règles de gestion), '
            'signale toute incohérence ou oubli éventuel et propose un résumé ou des questions d’arbitrage final.',
    };
  }

  /// Construit le prompt ciblé pour rechercher un complément de lexique métier
  /// propre à la feature active sans dupliquer ni écraser les termes existants.
  static String buildLexiconComplementPrompt(SpecForgeProject project) {
    final feature = project.activeFeature;
    final initiative = project.activeInitiative;
    final existingCount = project.lexicon.terms.length;
    final featureContext = feature.description.trim().isNotEmpty
        ? feature.description.trim()
        : (feature.vision.ideaSummary.trim().isNotEmpty
              ? feature.vision.ideaSummary.trim()
              : project.initialIdea);
    final featureLabel = project.hasSingleDefaultFeature
        ? 'le projet « ${project.name} »'
        : 'la feature « ${feature.displayLabel} » (initiative « ${initiative.displayLabel} ») du projet « ${project.name} »';
    return 'Recherche un complément de lexique métier pour $featureLabel.\n'
        'Contexte fonctionnel ciblé : « $featureContext ».\n'
        'Le lexique partagé du projet contient actuellement $existingCount terme(s). '
        'Identifie uniquement les nouveaux termes métier, acronymes, synonymes ou ambiguïtés spécifiques à cette feature qui manquent encore dans le lexique partagé, '
        'sans supprimer ni réécrire les termes existants déjà validés.';
  }

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
    DomainCatalog? domainCatalog,
    BusinessObjectModelPreferences? modelPreferencesOverride,
    String? focusedObjectId,
    List<String> focusedAttributePath = const <String>[],
    String businessObjectFilter = '',
    String? focusedEventStormFlowId,
    String? focusedEventStormNodeId,
    String? focusedExampleStoryId,
  }) {
    final agent = SpecStageAgent.forStage(stage);
    final stageState = project.stageStateFor(stage);
    final effectivePrefs =
        modelPreferencesOverride ?? project.businessObjectModelPreferences;
    final contextJson = const JsonEncoder.withIndent('  ')
        .convert(project.toCompactContextJson(stage));

    final previousSummaries = <String>[];
    for (final s in project.enabledSpecStages) {
      if (s.index >= stage.index) break;
      final summary = project.stageStateFor(s).stageSummary.trim();
      if (summary.isNotEmpty) {
        previousSummaries.add(
          '- Étape ${project.stepNumberFor(s)} (${s.title}) : $summary',
        );
      }
    }

    final history = _buildHistory(
      stageState.messages,
      maxEntries: maxHistoryEntries,
    );

    final buffer = StringBuffer()
      ..writeln(
        'ÉTAPE ACTIVE : ${project.stepNumberFor(stage)}/${project.enabledSpecStages.length} — ${stage.title} (Agent : ${agent.stage.agentTitle})',
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
        stage == SpecForgeStage.exampleMapping ||
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

    if (stage == SpecForgeStage.eventStorming ||
        stage == SpecForgeStage.reviewExport) {
      final focusedDoc =
          (focusedEventStormFlowId != null &&
              focusedEventStormFlowId.isNotEmpty)
          ? project.eventStorming.findDocument(focusedEventStormFlowId)
          : null;
      final systemsBlock = domainSystemsBlock(
        domainCatalog,
        focusedDocument: focusedDoc,
      );
      if (systemsBlock.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(systemsBlock);
      }
    }

    if (_siblingObjectsTurnStages.contains(stage)) {
      final siblingObjectsBlock = buildSiblingFeaturesObjectsDirective(project);
      if (siblingObjectsBlock.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(siblingObjectsBlock);
      }
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
      focusedEventStormFlowId: focusedEventStormFlowId,
      focusedEventStormNodeId: focusedEventStormNodeId,
      focusedExampleStoryId: focusedExampleStoryId,
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

  /// Bloc « CARTOGRAPHIE SYSTÈMES & SERVICES DU WORKSPACE » destiné à assister
  /// l'Event Storming (`EXT-*` externes, dépendances inter-domaines et fronts).
  static String domainSystemsBlock(
    DomainCatalog? domainCatalog, {
    EventStormDocument? focusedDocument,
  }) {
    if (domainCatalog == null) return '';
    final activeSystems = domainCatalog.microservices
        .where((s) => s.isActive)
        .toList();
    if (activeSystems.isEmpty) return '';

    final domainsById = <String, FunctionalDomain>{
      for (final d in domainCatalog.domains) d.id: d,
    };

    String norm(String v) =>
        v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    final focusedNorms = <String>{
      if (focusedDocument != null) ...[
        norm(focusedDocument.id),
        norm(focusedDocument.meta.boundedContext),
        norm(focusedDocument.meta.domain),
      ],
    }..remove('');

    final matchedDomainIds = <String>{
      for (final d in domainCatalog.domains)
        if (focusedNorms.contains(norm(d.domainCode)) ||
            focusedNorms.contains(norm(d.name)))
          d.id,
    };

    final externalApps = activeSystems
        .where((s) => s.kind.isExternal)
        .toList();
    final openSourceTools = activeSystems
        .where((s) => s.kind.isOpenSourceTool)
        .toList();
    final frontendApps = activeSystems
        .where((s) => s.kind.isFrontend)
        .toList();
    final backendApps = activeSystems.where((s) => s.kind.isBackend).toList();

    final usedExtIds = <String>{};
    String suggestExtId(String name) {
      final id = EventStormingOperations.nextCatalogId('EXT', name, usedExtIds);
      usedExtIds.add(id);
      return id;
    }

    final buf = StringBuffer()
      ..writeln(
        'CARTOGRAPHIE « SYSTÈMES & SERVICES » DU WORKSPACE (RÉFÉRENTIEL POUR L’EVENT STORMING) :',
      )
      ..writeln(
        'Exploite prioritairement ce référentiel d’urbanisme pour peupler `catalog.external_systems` (`EXT-*`), contextualiser les points d’entrée frontaux (`read_model` / `ACT-*`) et aligner les Bounded Contexts :',
      );

    if (externalApps.isNotEmpty) {
      buf.writeln(
        '1. Applications externes déclarées (candidats directs `EXT-*` Rose pâle) :',
      );
      for (final ext in externalApps) {
        final dom = domainsById[ext.domainId];
        final extId = suggestExtId(ext.name);
        buf.writeln(
          '   - $extId -> « ${ext.name} » (code: ${ext.serviceCode}'
          '${dom == null ? '' : ', domaine: ${dom.name}'}'
          '${ext.vendor.isEmpty ? '' : ', fournisseur: ${ext.vendor}'})'
          '${ext.description.isEmpty ? '' : ' : ${ext.description}'}',
        );
      }
    }

    if (openSourceTools.isNotEmpty) {
      buf.writeln(
        '2. Tools openSource déclarés (outils auto-hébergés/open-source — utilisables en `EXT-*` Rose pâle lorsqu’ils interviennent dans le flux) :',
      );
      for (final tool in openSourceTools) {
        final dom = domainsById[tool.domainId];
        final extId = suggestExtId(tool.name);
        buf.writeln(
          '   - $extId -> « ${tool.name} » [Tools openSource] (code: ${tool.serviceCode}'
          '${dom == null ? '' : ', domaine: ${dom.name}'}'
          '${tool.vendor.isEmpty ? '' : ', projet/licence: ${tool.vendor}'})'
          '${tool.description.isEmpty ? '' : ' : ${tool.description}'}',
        );
      }
    }

    if (backendApps.isNotEmpty) {
      buf.writeln(
        '3. Services internes, BFF & Monolithes par domaine (pour un autre Bounded Context, tout appel synchrone vers un autre domaine peut être modélisé en `EXT-*` ou via événement inter-contexte `<CTX>:EVT-*`) :',
      );
      for (final svc in backendApps) {
        final dom = domainsById[svc.domainId];
        final isOtherDomain =
            matchedDomainIds.isNotEmpty &&
            !matchedDomainIds.contains(svc.domainId);
        final crossHint = isOtherDomain
            ? ' [AUTRE DOMAINE -> candidat EXT-* inter-contexte : ${suggestExtId(svc.name)}]'
            : '';
        buf.writeln(
          '   - [${svc.kind.label}] « ${svc.name} » (${svc.serviceCode}'
          '${dom == null ? '' : ', domaine: ${dom.name} (${dom.domainCode})'})$crossHint'
          '${svc.description.isEmpty ? '' : ' : ${svc.description}'}',
        );
      }
    }

    if (frontendApps.isNotEmpty) {
      buf.writeln(
        '4. Applications Frontales (Web & Mobile — repères pour les `read_model` Verts et interactions `ACT-*`) :',
      );
      for (final front in frontendApps) {
        final dom = domainsById[front.domainId];
        buf.writeln(
          '   - [${front.kind.label}] « ${front.name} » (${front.serviceCode}'
          '${dom == null ? '' : ', domaine: ${dom.name}'})'
          '${front.description.isEmpty ? '' : ' : ${front.description}'}',
        );
      }
    }

    return buf.toString().trimRight();
  }

  /// Bloc « FOCUS COURANT » décrivant l'objet, l'attribut sélectionné et le
  /// filtre actif de l'arbre [treeLabel] (chaîne vide sans objet ni filtre).
  static String buildFocusScopeBlock({
    required SpecForgeProject project,
    required String? focusedObjectId,
    required List<String> focusedAttributePath,
    required String businessObjectFilter,
    String? focusedEventStormFlowId,
    String? focusedEventStormNodeId,
    String? focusedExampleStoryId,
    String treeLabel = 'Arbre & Inspecteur',
  }) {
    final buf = StringBuffer();
    final trimmedFilter = businessObjectFilter.trim();
    final focusedObj = (focusedObjectId != null && focusedObjectId.isNotEmpty)
        ? project.findBusinessObject(focusedObjectId)
        : null;
    final focusedDoc =
        (focusedEventStormFlowId != null && focusedEventStormFlowId.isNotEmpty)
        ? project.eventStorming.findDocument(focusedEventStormFlowId)
        : null;
    final focusedStepNum = focusedEventStormNodeId != null
        ? int.tryParse(focusedEventStormNodeId)
        : null;
    final focusedStep = (focusedDoc != null && focusedStepNum != null)
        ? focusedDoc.findStep(focusedStepNum)
        : null;
    final focusedStory =
        (focusedExampleStoryId != null && focusedExampleStoryId.isNotEmpty)
        ? project.exampleMappings
              .where((s) => s.id == focusedExampleStoryId)
              .firstOrNull
        : null;

    if (focusedObj == null &&
        focusedDoc == null &&
        focusedStory == null &&
        trimmedFilter.isEmpty) {
      return '';
    }

    buf.writeln('FOCUS COURANT DANS L’ATELIER (SCOPE DE SÉLECTION) :');
    if (focusedDoc != null) {
      buf.writeln(
        '- Bounded Context Event Storming sélectionné : « ${focusedDoc.meta.boundedContext} » '
        '(${focusedDoc.fileName}, id: ${focusedDoc.id}, ${focusedDoc.flow.length} étape(s), ${focusedDoc.openHotspotCount} hotspot(s) ouvert(s))',
      );
      if (focusedStep != null) {
        buf.writeln(
          '- Étape sélectionnée : step ${focusedStep.step} — Commande « ${focusedStep.command.name} » '
          '(événements émis: ${focusedStep.emittedEvents.map((e) => '${e.id}:${e.name}').join(', ')})',
        );
      }
    }
    if (focusedStory != null) {
      final storyObj = focusedStory.targetObjectId.isEmpty
          ? null
          : project.findBusinessObject(focusedStory.targetObjectId);
      buf.writeln(
        '- Tableau Example Mapping sélectionné : ${focusedStory.code} « ${focusedStory.title} » '
        '(id: ${focusedStory.id}${storyObj == null ? '' : ', objet cible : ${storyObj.technicalName} (${storyObj.id})'}, '
        '${focusedStory.rules.length} règle(s), ${focusedStory.totalExampleCount} exemple(s), ${focusedStory.openQuestionCount} question(s) ouverte(s))',
      );
    }
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
      for (final s in project.enabledSpecStages)
        if (project.stageStateFor(s).stageSummary.trim().isNotEmpty)
          '- Étape ${project.stepNumberFor(s)} (${s.title}) [${project.stageStateFor(s).status.label}] : ${project.stageStateFor(s).stageSummary.trim()}',
    ];

    final history = _buildHistory(
      project.globalChatMessages,
      maxEntries: maxHistoryEntries,
    );

    final buffer = StringBuffer()
      ..writeln('MODE : CHAT GLOBAL DE QUESTIONS SUR LE PROJET')
      ..writeln(
        'ÉTAPE ACTIVE DU WIZARD : ${project.stepNumberFor(project.currentStage)}/${project.enabledSpecStages.length} (${project.currentStage.title})',
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

class _SiblingObjectPromptGroup {
  _SiblingObjectPromptGroup._(this.canonicalObject, this._canonicalIsValidated);

  factory _SiblingObjectPromptGroup.initial(
    SpecFeatureSpec feature,
    BusinessObjectSpec object,
  ) {
    final isVal = feature.effectiveStatus == SpecPortfolioStatus.validated;
    final group = _SiblingObjectPromptGroup._(object, isVal);
    group._register(feature, object);
    return group;
  }

  BusinessObjectSpec canonicalObject;
  bool _canonicalIsValidated;

  final Set<String> _objectIdsLower = <String>{};
  final Set<String> _technicalNamesLower = <String>{};
  final Set<String> _seenFeatureIds = <String>{};
  final List<String> featureBadges = <String>[];
  final List<(SpecFeatureSpec, BusinessObjectSpec)> _definitions =
      <(SpecFeatureSpec, BusinessObjectSpec)>[];

  bool matchesIdentity(String objectIdLower, String technicalNameLower) =>
      (objectIdLower.isNotEmpty && _objectIdsLower.contains(objectIdLower)) ||
      (technicalNameLower.isNotEmpty &&
          _technicalNamesLower.contains(technicalNameLower));

  void addDefinition(SpecFeatureSpec feature, BusinessObjectSpec object) {
    final isVal = feature.effectiveStatus == SpecPortfolioStatus.validated;
    if (isVal && !_canonicalIsValidated) {
      canonicalObject = object;
      _canonicalIsValidated = true;
    }
    _register(feature, object);
  }

  void _register(SpecFeatureSpec feature, BusinessObjectSpec object) {
    final idLower = object.id.trim().toLowerCase();
    final techLower = object.technicalName.trim().toLowerCase();
    if (idLower.isNotEmpty) _objectIdsLower.add(idLower);
    if (techLower.isNotEmpty) _technicalNamesLower.add(techLower);
    if (_seenFeatureIds.add(feature.id)) {
      final codeOrName = feature.code.trim().isNotEmpty
          ? feature.code.trim()
          : feature.name.trim();
      featureBadges.add('$codeOrName (${feature.effectiveStatus.label})');
    }
    _definitions.add((feature, object));
  }

  List<BusinessAttribute> get mergedAttributes {
    final orderedDefs = <(SpecFeatureSpec, BusinessObjectSpec)>[
      for (final entry in _definitions)
        if (entry.$1.effectiveStatus == SpecPortfolioStatus.validated) entry,
      for (final entry in _definitions)
        if (entry.$1.effectiveStatus != SpecPortfolioStatus.validated) entry,
    ];
    final seenNamesLower = <String>{};
    final merged = <BusinessAttribute>[];
    for (final (_, obj) in orderedDefs) {
      for (final attr in obj.attributes) {
        if (seenNamesLower.add(attr.name.toLowerCase())) {
          merged.add(attr);
        }
      }
    }
    return merged;
  }
}
