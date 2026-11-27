/// Contrôleur réactif principal du wizard `super_spec_forge` ([SpecForgeController]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart' show JsonNode;

import '../ai/company_glossary_ai.dart';
import '../ai/cost_patch_applier.dart';
import '../ai/cost_prompt_builder.dart';
import '../ai/cost_stage_agent.dart';
import '../ai/domain_layer_ai.dart';
import '../ai/domain_model_ai.dart';
import '../ai/portfolio_slicing_ai.dart';
import '../ai/qa_patch_applier.dart';
import '../ai/qa_prompt_builder.dart';
import '../ai/qa_stage_agent.dart';
import '../ai/spec_ai_service.dart';
import '../ai/spec_app_tools.dart';
import '../ai/spec_delta_recovery.dart';
import '../ai/spec_patch_applier.dart';
import '../ai/spec_prompt_builder.dart';
import '../ai/spec_stage_agent.dart';
import '../ai/spec_stream_parser.dart';
import '../ai/systems_services_ai.dart';
import '../ai/usecase_orchestration_ai.dart';
import '../ai/ux_patch_applier.dart';
import '../ai/ux_prompt_builder.dart';
import '../ai/ux_stage_agent.dart';
import '../ai/value_objects_ai.dart';
import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/company_glossary.dart';
import '../models/cost/cost_forge_spec.dart';
import '../models/cost/cost_forge_stage.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/domain_layer_spec.dart';
import '../models/enterprise_rate_card.dart';
import '../models/qa/qa_coherence_issue.dart';
import '../models/qa/qa_forge_spec.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_initiative.dart';
import '../models/spec_lexicon.dart';
import '../models/spec_stage_chat.dart';
import '../models/technical_modeling_rule.dart';
import '../models/usecase_orchestration_spec.dart';
import '../models/ux/ux_coherence_issue.dart';
import '../models/ux/ux_forge_spec.dart';
import '../models/ux/ux_forge_stage.dart';
import '../models/ux/ux_screen_spec.dart';
import '../models/value_object_spec.dart';
import 'business_object_operations.dart';
import 'company_glossary_store.dart';
import 'cost_auto_seeder.dart';
import 'cost_coherence_analyzer.dart';
import 'domain_catalog_store.dart';
import 'enterprise_rate_card_store.dart';
import 'event_storming_operations.dart';
import 'example_mapping_operations.dart';
import 'exporters/qa_tdd_prompt_exporter.dart';
import 'model_dictionary_store.dart';
import 'qa_coherence_analyzer.dart';
import 'spec_coherence_analyzer.dart';
import 'spec_design_promoter.dart';
import 'spec_project_store.dart';
import 'spec_workspace_store.dart';
import 'ux_coherence_analyzer.dart';
import 'value_object_primitive_detector.dart';

/// Orchestre l'état du projet actif, l'historique Undo/Redo, la persistance et les échanges IA.
class SpecForgeController extends ChangeNotifier {
  /// Nombre maximal de tentatives automatiques en cas d'exception de parsing ou validation IA.
  static const int maxRecoveryAttempts = 3;

  /// Nombre maximal de tours d'appels d'outils par tentative IA.
  static const int maxToolRounds = 6;

  /// Clé de persistance de la largeur du panneau gauche d'Event Storming.
  static const String eventStormingMasterPanelKey =
      'event_storming.master_width';

  /// Clé de persistance de la largeur du panneau gauche d'Example Mapping.
  static const String exampleMappingMasterPanelKey =
      'example_mapping.master_width';

  /// Clé de persistance de la largeur de l'arbre Initiatives & Features.
  static const String portfolioTreePanelKey = 'portfolio.tree_width';

  /// Crée un contrôleur avec workspace, stores, service IA et registre d'outils injectables.
  SpecForgeController({
    SpecProjectStore? store,
    CompanyGlossaryStore? glossaryStore,
    ModelDictionaryStore? modelDictionaryStore,
    DomainCatalogStore? domainCatalogStore,
    EnterpriseRateCardStore? enterpriseRateCardStore,
    SpecWorkspaceStore? workspaceStore,
    SpecAiService? aiService,
    VibeAppToolRegistry? toolRegistry,
    VibeAiSpeedMode initialSpeedMode = VibeAiSpeedMode.fast,
    VibeQuestioningLevel initialQuestioningLevel =
        VibeQuestioningLevel.balanced,
  }) : _hasCustomStores =
           store != null ||
           glossaryStore != null ||
           modelDictionaryStore != null ||
           domainCatalogStore != null ||
           enterpriseRateCardStore != null,
       _workspaceStore = workspaceStore ?? SpecWorkspaceStore(),
       _store = store ?? SpecProjectStore(),
       _glossaryStore =
           glossaryStore ??
           CompanyGlossaryStore((store ?? SpecProjectStore()).rootDirectory),
       _modelDictionaryStore =
           modelDictionaryStore ??
           ModelDictionaryStore((store ?? SpecProjectStore()).rootDirectory),
       _domainCatalogStore =
           domainCatalogStore ??
           DomainCatalogStore((store ?? SpecProjectStore()).rootDirectory),
       _enterpriseRateCardStore =
           enterpriseRateCardStore ??
           EnterpriseRateCardStore(
             (store ?? SpecProjectStore()).rootDirectory,
           ),
       _aiService = aiService ?? const GeminiSpecAiService(),
       _customToolRegistry = toolRegistry,
       _speedMode = initialSpeedMode,
       _questioningLevel = initialQuestioningLevel;

  final bool _hasCustomStores;
  final SpecWorkspaceStore _workspaceStore;
  SpecProjectStore _store;
  CompanyGlossaryStore _glossaryStore;
  ModelDictionaryStore _modelDictionaryStore;
  DomainCatalogStore _domainCatalogStore;
  EnterpriseRateCardStore _enterpriseRateCardStore;
  final SpecAiService _aiService;
  final VibeAppToolRegistry? _customToolRegistry;

  SpecWorkspaceMetadata? _workspaceMetadata;
  List<SpecWorkspaceEntry> _recentWorkspaces = const <SpecWorkspaceEntry>[];

  SpecForgeProject? _project;
  List<SpecProjectSummary> _recentProjects = const <SpecProjectSummary>[];
  final List<SpecForgeProject> _undoStack = <SpecForgeProject>[];
  final List<SpecForgeProject> _redoStack = <SpecForgeProject>[];

  CompanyGlossary _companyGlossary = CompanyGlossary.empty;
  List<SpecChatMessage> _glossaryChatMessages = const <SpecChatMessage>[];
  final List<CompanyGlossary> _glossaryUndoStack = <CompanyGlossary>[];
  final List<CompanyGlossary> _glossaryRedoStack = <CompanyGlossary>[];

  BusinessObjectModelPreferences _modelPreferences =
      BusinessObjectModelPreferences.defaults;
  EnterpriseRateCard _enterpriseRateCard = EnterpriseRateCard.defaults;
  DomainCatalog _domainCatalog = DomainCatalog.empty;
  String? _activeDesignDomainId;
  final List<BusinessObjectModelPreferences> _modelPrefsUndoStack =
      <BusinessObjectModelPreferences>[];
  final List<BusinessObjectModelPreferences> _modelPrefsRedoStack =
      <BusinessObjectModelPreferences>[];
  final List<EnterpriseRateCard> _rateCardUndoStack = <EnterpriseRateCard>[];
  final List<EnterpriseRateCard> _rateCardRedoStack = <EnterpriseRateCard>[];

  VibeAiSpeedMode _speedMode;
  VibeQuestioningLevel _questioningLevel;

  bool _isSending = false;
  bool _sendingGlobalQuestion = false;
  bool _sendingGlossary = false;
  bool _sendingPortfolio = false;

  /// `domaine/entrée` du modèle dont le tour IA est en cours.
  String? _sendingDomainModelKey;
  SpecForgeStage? _sendingStage;
  UxForgeStage? _sendingUxStage;
  QaForgeStage? _sendingQaStage;
  CostForgeStage? _sendingCostStage;
  String? _streamingMessage;
  String _streamingStatus = '';
  List<VibeToolTrace> _streamingToolTraces = const <VibeToolTrace>[];
  String? _focusedObjectId;
  List<String> _focusedAttributePath = const <String>[];
  String _businessObjectFilter = '';
  String? _focusedEventStormFlowId;
  String? _focusedEventStormNodeId;
  String? _focusedExampleStoryId;
  String? _focusedJourneyId;
  String? _focusedRouteId;
  String? _focusedScreenId;
  UxLayoutZoneName? _focusedScreenZone;
  String? _focusedFixtureId;
  String? _focusedFeatureId;
  String? _focusedScenarioId;
  String? _focusedTddSuiteId;
  String? _focusedCostProfileId;
  String? _focusedWbsItemId;
  String? _focusedRunItemId;
  String? _focusedRiskItemId;

  /// Sélection et filtre de l'arbre de chaque fiche, indexés par `domaine/entrée`.
  final Map<String, ({List<String> attributePath, String filter})>
  _domainModelFocus = {};

  /// `domaine/entrée` dont le tour IA de la couche Domain est en cours.
  String? _sendingDomainLayerKey;

  /// Onglet actif de la page Couche Domain, indexé par `domaine/entrée`.
  final Map<String, DomainLayerTab> _domainLayerActiveTab = {};

  /// `domainId` dont le tour IA « Cas d’usage & orchestration » est en cours.
  String? _sendingUseCaseDomainId;

  /// Onglet actif de la page « Cas d’usage & orchestration », indexé par `domainId`.
  final Map<String, UseCaseOrchestrationTab> _useCaseActiveTab = {};

  /// `domainId` dont le tour IA « Systèmes & Services » est en cours.
  String? _sendingSystemsServicesDomainId;

  /// Clé de portée (`shared` ou `domain:<domainId>`) dont le tour IA Value Objects est en cours.
  String? _sendingValueObjectsKey;

  /// Filtre de catégorie actif sur la page « Systèmes & Services », indexé par `domainId`.
  final Map<String, DomainSystemKind?> _systemsServicesActiveFilter = {};
  final Map<String, double> _panelWidths = <String, double>{};
  String? _lastError;
  bool _isSaving = false;
  int _saveGeneration = 0;
  bool _stopRequested = false;
  StreamSubscription<GeminiStreamEvent>? _activeStreamSubscription;
  Completer<void>? _activeStreamCompleter;

  @override
  void dispose() {
    _stopRequested = true;
    final sub = _activeStreamSubscription;
    _activeStreamSubscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    final completer = _activeStreamCompleter;
    _activeStreamCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    super.dispose();
  }

  /// Gestionnaire de dossiers Workspace Git.
  SpecWorkspaceStore get workspaceStore => _workspaceStore;

  /// Dossier racine du workspace actif.
  Directory get workspaceDirectory => _store.rootDirectory;

  /// Métadonnées du workspace actif (`workspace.json`), ou `null` en mode mémoire.
  SpecWorkspaceMetadata? get workspaceMetadata => _workspaceMetadata;

  /// Liste locale des workspaces récemment ouverts.
  List<SpecWorkspaceEntry> get recentWorkspaces => _recentWorkspaces;

  /// Magasin disque associé.
  SpecProjectStore get store => _store;

  /// Magasin disque du glossaire d'entreprise.
  CompanyGlossaryStore get glossaryStore => _glossaryStore;

  /// Glossaire terminologique d'entreprise global.
  CompanyGlossary get companyGlossary => _companyGlossary;

  /// Historique des échanges IA dédiés au glossaire d'entreprise.
  List<SpecChatMessage> get glossaryChatMessages => _glossaryChatMessages;

  /// Vrai lorsqu'un tour IA du glossaire d'entreprise est en cours.
  bool get isSendingGlossary => _isSending && _sendingGlossary;

  /// Historique du chat IA du modèle [entryId] du domaine [domainId].
  List<SpecChatMessage> domainModelChat(String domainId, String entryId) =>
      _domainContractsOf(domainId)?.chats[entryId] ?? const [];

  /// Vrai lorsqu'un tour IA du modèle [entryId] du domaine [domainId] est en cours.
  bool isSendingDomainModel(String domainId, String entryId) =>
      _isSending && _sendingDomainModelKey == '$domainId/$entryId';

  /// Historique du chat IA de la couche Domain de l'entrée [entryId] du domaine [domainId].
  List<SpecChatMessage> domainLayerChat(String domainId, String entryId) =>
      _domainContractsOf(domainId)?.domainLayerChats[entryId] ?? const [];

  /// Vrai lorsqu'un tour IA de la couche Domain de [entryId] dans [domainId] est en cours.
  bool isSendingDomainLayer(String domainId, String entryId) =>
      _isSending && _sendingDomainLayerKey == '$domainId/$entryId';

  /// Onglet actif consulté sur la page Couche Domain de [entryId] dans [domainId].
  DomainLayerTab domainLayerActiveTab(String domainId, String entryId) =>
      _domainLayerActiveTab['$domainId/$entryId'] ?? DomainLayerTab.invariants;

  /// Mémorise l'onglet actif consulté sur la page Couche Domain de [entryId].
  void setDomainLayerActiveTab(
    String domainId,
    String entryId,
    DomainLayerTab tab,
  ) {
    final key = '$domainId/$entryId';
    if (_domainLayerActiveTab[key] == tab) return;
    _domainLayerActiveTab[key] = tab;
    notifyListeners();
  }

  /// Spécification « Cas d’usage & orchestration » du domaine [domainId].
  UseCaseOrchestrationSpec useCaseOrchestrationOf(String domainId) =>
      _domainCatalog.domains
          .where((d) => d.id == domainId)
          .firstOrNull
          ?.useCaseOrchestration ??
      UseCaseOrchestrationSpec.empty;

  /// Historique du chat IA « Cas d’usage & orchestration » du domaine [domainId].
  List<SpecChatMessage> useCaseOrchestrationChat(String domainId) =>
      useCaseOrchestrationOf(domainId).chatMessages;

  /// Vrai lorsqu'un tour IA « Cas d’usage & orchestration » est en cours pour [domainId].
  bool isSendingUseCaseOrchestration(String domainId) =>
      _isSending && _sendingUseCaseDomainId == domainId;

  /// Onglet actif consulté sur la page « Cas d’usage & orchestration » de [domainId].
  UseCaseOrchestrationTab useCaseOrchestrationActiveTab(String domainId) =>
      _useCaseActiveTab[domainId] ?? UseCaseOrchestrationTab.cartography;

  /// Mémorise l'onglet actif de « Cas d’usage & orchestration » pour [domainId].
  void setUseCaseOrchestrationActiveTab(
    String domainId,
    UseCaseOrchestrationTab tab,
  ) {
    if (_useCaseActiveTab[domainId] == tab) return;
    _useCaseActiveTab[domainId] = tab;
    notifyListeners();
  }

  /// Historique du chat IA « Systèmes & Services » du domaine [domainId].
  List<SpecChatMessage> systemsServicesChat(String domainId) =>
      _domainCatalog.domains
          .where((d) => d.id == domainId)
          .firstOrNull
          ?.systemsServicesChat ??
      const <SpecChatMessage>[];

  /// Vrai lorsqu'un tour IA « Systèmes & Services » est en cours pour [domainId].
  bool isSendingSystemsServices(String domainId) =>
      _isSending && _sendingSystemsServicesDomainId == domainId;

  /// Filtre de catégorie actif sur la page « Systèmes & Services » de [domainId].
  DomainSystemKind? systemsServicesActiveFilter(String domainId) =>
      _systemsServicesActiveFilter[domainId];

  /// Mémorise le filtre de catégorie actif de « Systèmes & Services » pour [domainId].
  void setSystemsServicesActiveFilter(
    String domainId,
    DomainSystemKind? filterKind,
  ) {
    if (_systemsServicesActiveFilter[domainId] == filterKind) return;
    _systemsServicesActiveFilter[domainId] = filterKind;
    notifyListeners();
  }

  /// Chemin d'IDs de l'attribut sélectionné dans la fiche du modèle [entryId]
  /// (vide = objet entier), piloté par l'arbre ou l'outil `focus_stage_or_object`.
  List<String> domainModelAttributePath(String domainId, String entryId) =>
      _domainModelFocus['$domainId/$entryId']?.attributePath ?? const [];

  /// Filtre de l'arbre de la fiche du modèle [entryId], piloté par l'interface
  /// ou l'outil `filter_business_objects`.
  String domainModelFilter(String domainId, String entryId) =>
      _domainModelFocus['$domainId/$entryId']?.filter ?? '';

  /// Sélectionne l'attribut [attributePath] (vide = objet entier) dans la fiche.
  void focusDomainModelAttribute(
    String domainId,
    String entryId,
    List<String> attributePath,
  ) => _setDomainModelFocus(
    domainId,
    entryId,
    attributePath: List.unmodifiable(attributePath),
  );

  /// Met à jour le filtre de l'arbre de la fiche du modèle [entryId].
  void setDomainModelFilter(String domainId, String entryId, String query) =>
      _setDomainModelFocus(domainId, entryId, filter: query);

  void _setDomainModelFocus(
    String domainId,
    String entryId, {
    List<String>? attributePath,
    String? filter,
  }) {
    final key = '$domainId/$entryId';
    final current = _domainModelFocus[key];
    final next = (
      attributePath: attributePath ?? current?.attributePath ?? const [],
      filter: filter ?? current?.filter ?? '',
    );
    if (current != null &&
        listEquals(current.attributePath, next.attributePath) &&
        current.filter == next.filter) {
      return;
    }
    _domainModelFocus[key] = next;
    notifyListeners();
  }

  /// Indique si un Undo est disponible sur le glossaire d'entreprise.
  bool get canUndoGlossary => _glossaryUndoStack.isNotEmpty;

  /// Indique si un Redo est disponible sur le glossaire d'entreprise.
  bool get canRedoGlossary => _glossaryRedoStack.isNotEmpty;

  /// Magasin disque du dictionnaire technique global.
  ModelDictionaryStore get modelDictionaryStore => _modelDictionaryStore;

  /// Préférences et règles techniques globales héritées par tous les projets.
  BusinessObjectModelPreferences get modelPreferences => _modelPreferences;

  /// Catalogue partagé des domaines fonctionnels du workspace actif.
  DomainCatalog get domainCatalog => _domainCatalog;

  /// Identifiant du domaine fonctionnel actif dans l'espace Design, s'il
  /// existe toujours dans [domainCatalog], sinon `null`.
  String? get activeDesignDomainId {
    final id = _activeDesignDomainId;
    if (id == null) return null;
    return _domainCatalog.domains.any((d) => d.id == id) ? id : null;
  }

  /// Domaine fonctionnel actif dans l'espace Design (ou premier domaine du
  /// catalogue par défaut).
  FunctionalDomain? get activeDesignDomain {
    final id = activeDesignDomainId;
    if (id != null) {
      return _domainCatalog.domains.where((d) => d.id == id).firstOrNull;
    }
    return _domainCatalog.domains.firstOrNull;
  }

  /// Définit le domaine fonctionnel actif dans l'espace Design.
  void setActiveDesignDomainId(String? domainId) {
    final normalized =
        domainId != null && _domainCatalog.domains.any((d) => d.id == domainId)
        ? domainId
        : null;
    if (_activeDesignDomainId == normalized) return;
    _activeDesignDomainId = normalized;
    notifyListeners();
  }

  /// Magasin disque du catalogue de domaines.
  DomainCatalogStore get domainCatalogStore => _domainCatalogStore;

  /// Indique si un Undo est disponible sur le dictionnaire technique.
  bool get canUndoModelPreferences => _modelPrefsUndoStack.isNotEmpty;

  /// Indique si un Redo est disponible sur le dictionnaire technique.
  bool get canRedoModelPreferences => _modelPrefsRedoStack.isNotEmpty;

  /// Magasin disque de la grille tarifaire TJM d'entreprise.
  EnterpriseRateCardStore get enterpriseRateCardStore =>
      _enterpriseRateCardStore;

  /// Grille tarifaire et abaques TJM d'entreprise partagés entre tous les projets.
  EnterpriseRateCard get enterpriseRateCard => _enterpriseRateCard;

  /// Indique si un Undo est disponible sur la grille tarifaire d'entreprise.
  bool get canUndoEnterpriseRateCard => _rateCardUndoStack.isNotEmpty;

  /// Indique si un Redo est disponible sur la grille tarifaire d'entreprise.
  bool get canRedoEnterpriseRateCard => _rateCardRedoStack.isNotEmpty;

  /// Projet actuellement ouvert, ou `null` sur l'écran d'accueil.
  SpecForgeProject? get project => _project;

  /// Liste des projets sauvegardés disponibles.
  List<SpecProjectSummary> get recentProjects => _recentProjects;

  /// Mode de vitesse Gemini actif.
  VibeAiSpeedMode get speedMode => _speedMode;

  /// Niveau de questionnement actif.
  VibeQuestioningLevel get questioningLevel => _questioningLevel;

  /// Vrai pendant un tour d'appel IA en cours.
  bool get isSending => _isSending;

  /// Vrai lorsqu'une question globale du chat « Question » est en cours de traitement.
  bool get isSendingGlobalQuestion => _isSending && _sendingGlobalQuestion;

  /// Vrai lorsqu'un tour IA de découpage produit (Initiatives & Features) est en cours.
  bool get isSendingPortfolio => _isSending && _sendingPortfolio;

  /// Étape en cours de génération IA.
  SpecForgeStage? get sendingStage => _sendingStage;

  /// Étape UX en cours de génération IA.
  UxForgeStage? get sendingUxStage => _sendingUxStage;

  /// Vrai lorsqu'un tour IA de l'atelier UX est en cours.
  bool get isSendingUx => _isSending && _sendingUxStage != null;

  /// Étape QA en cours de génération IA.
  QaForgeStage? get sendingQaStage => _sendingQaStage;

  /// Vrai lorsqu'un tour IA de l'atelier QA est en cours.
  bool get isSendingQa => _isSending && _sendingQaStage != null;

  /// Étape FinOps / Coûts en cours de génération IA.
  CostForgeStage? get sendingCostStage => _sendingCostStage;

  /// Vrai lorsqu'un tour IA de l'atelier FinOps / Coûts est en cours.
  bool get isSendingCost => _isSending && _sendingCostStage != null;

  /// Texte streaming reçu jusqu'ici pour le message en cours.
  String? get streamingMessage => _streamingMessage;

  /// Indicateur d'activité streaming (ex. « Rédaction des questions… »).
  String get streamingStatus => _streamingStatus;

  /// Traces d'outils déjà exécutés pendant le tour en streaming courant.
  List<VibeToolTrace> get streamingToolTraces => _streamingToolTraces;

  /// Identifiant d'objet métier ciblé par un outil IA ou l'interface.
  String? get focusedObjectId => _focusedObjectId;

  /// Chemin d'IDs d'attribut focalisé dans l'objet métier courant (vide = objet racine).
  List<String> get focusedAttributePath => _focusedAttributePath;

  /// Filtre texte courant sur les objets métiers et attributs dans « Arbre & Inspecteur ».
  String get businessObjectFilter => _businessObjectFilter;

  /// Identifiant du flux Event Storming focalisé dans l'atelier.
  String? get focusedEventStormFlowId => _focusedEventStormFlowId;

  /// Identifiant de la carte Event Storming focalisée dans le flux courant.
  String? get focusedEventStormNodeId => _focusedEventStormNodeId;

  /// Identifiant du tableau Example Mapping focalisé dans l'atelier.
  String? get focusedExampleStoryId => _focusedExampleStoryId;

  /// Identifiant du parcours utilisateur focalisé dans l'atelier UX.
  String? get focusedJourneyId => _focusedJourneyId;

  /// Identifiant de la route focalisée dans l'atelier UX.
  String? get focusedRouteId => _focusedRouteId;

  /// Identifiant de l'écran focalisé dans l'atelier UX.
  String? get focusedScreenId => _focusedScreenId;

  /// Zone cardinale focalisée sur l'écran courant dans l'atelier UX.
  UxLayoutZoneName? get focusedScreenZone => _focusedScreenZone;

  /// Met à jour la sélection courante dans l'atelier UX (parcours, route, écran et/ou zone).
  void focusUxItem({
    String? journeyId,
    String? routeId,
    String? screenId,
    UxLayoutZoneName? zone,
  }) {
    if (_focusedJourneyId == journeyId &&
        _focusedRouteId == routeId &&
        _focusedScreenId == screenId &&
        _focusedScreenZone == zone) {
      return;
    }
    _focusedJourneyId = journeyId;
    _focusedRouteId = routeId;
    _focusedScreenId = screenId;
    _focusedScreenZone = zone;
    notifyListeners();
  }

  /// Identifiant de la fixture focalisée dans l'atelier QA.
  String? get focusedFixtureId => _focusedFixtureId;

  /// Identifiant de la feature Gherkin focalisée dans l'atelier QA.
  String? get focusedFeatureId => _focusedFeatureId;

  /// Identifiant du scénario Gherkin focalisé dans l'atelier QA.
  String? get focusedScenarioId => _focusedScenarioId;

  /// Identifiant de la suite TDD focalisée dans l'atelier QA.
  String? get focusedTddSuiteId => _focusedTddSuiteId;

  /// Met à jour la sélection courante dans l'atelier QA (fixture, feature, scénario et/ou suite TDD).
  void focusQaItem({
    String? fixtureId,
    String? featureId,
    String? scenarioId,
    String? tddSuiteId,
  }) {
    if (_focusedFixtureId == fixtureId &&
        _focusedFeatureId == featureId &&
        _focusedScenarioId == scenarioId &&
        _focusedTddSuiteId == tddSuiteId) {
      return;
    }
    _focusedFixtureId = fixtureId;
    _focusedFeatureId = featureId;
    _focusedScenarioId = scenarioId;
    _focusedTddSuiteId = tddSuiteId;
    notifyListeners();
  }

  /// Identifiant du profil TJM focalisé dans l'atelier Coûts.
  String? get focusedCostProfileId => _focusedCostProfileId;

  /// Identifiant du lot WBS focalisé dans l'atelier Coûts.
  String? get focusedWbsItemId => _focusedWbsItemId;

  /// Identifiant du poste Run OPEX focalisé dans l'atelier Coûts.
  String? get focusedRunItemId => _focusedRunItemId;

  /// Identifiant du risque budgétaire focalisé dans l'atelier Coûts.
  String? get focusedRiskItemId => _focusedRiskItemId;

  /// Met à jour la sélection courante dans l'atelier FinOps / Coûts.
  void focusCostItem({
    String? profileId,
    String? wbsItemId,
    String? runItemId,
    String? riskItemId,
  }) {
    if (_focusedCostProfileId == profileId &&
        _focusedWbsItemId == wbsItemId &&
        _focusedRunItemId == runItemId &&
        _focusedRiskItemId == riskItemId) {
      return;
    }
    _focusedCostProfileId = profileId;
    _focusedWbsItemId = wbsItemId;
    _focusedRunItemId = runItemId;
    _focusedRiskItemId = riskItemId;
    notifyListeners();
  }

  /// Met à jour l'objet métier focalisé dans l'atelier (en réinitialisant l'attribut).
  void focusBusinessObject(String? objectId) =>
      focusBusinessSelection(objectId: objectId);

  /// Met à jour la sélection courante (objet métier + éventuel chemin d'attribut).
  void focusBusinessSelection({
    String? objectId,
    List<String> attributePath = const <String>[],
  }) {
    final normalizedPath = List<String>.unmodifiable(attributePath);
    if (_focusedObjectId == objectId &&
        listEquals(_focusedAttributePath, normalizedPath)) {
      return;
    }
    _focusedObjectId = objectId;
    _focusedAttributePath = normalizedPath;
    notifyListeners();
  }

  /// Met à jour le filtre recherche sur les objets métiers et attributs.
  void setBusinessObjectFilter(String query) {
    if (_businessObjectFilter == query) return;
    _businessObjectFilter = query;
    notifyListeners();
  }

  /// Met à jour le flux Event Storming sélectionné dans l'atelier.
  void focusEventStormFlow(String? flowId) =>
      focusEventStormSelection(flowId: flowId);

  /// Met à jour le flux et/ou la carte Event Storming sélectionnés dans l'atelier.
  void focusEventStormSelection({String? flowId, String? nodeId}) {
    if (_focusedEventStormFlowId == flowId &&
        _focusedEventStormNodeId == nodeId) {
      return;
    }
    _focusedEventStormFlowId = flowId;
    _focusedEventStormNodeId = nodeId;
    notifyListeners();
  }

  /// Met à jour le tableau Example Mapping sélectionné dans l'atelier.
  void focusExampleStory(String? storyId) {
    if (_focusedExampleStoryId == storyId) return;
    _focusedExampleStoryId = storyId;
    notifyListeners();
  }

  /// Largeur mémorisée (en pixels logiques) du panneau identifié par [key],
  /// ou `null` si la largeur par défaut s'applique.
  double? panelWidth(String key) => _panelWidths[key];

  /// Met à jour en mémoire la largeur du panneau [key] et la persiste si [persist] vaut `true`.
  void setPanelWidth(
    String key,
    double width, {
    bool persist = false,
    bool notify = false,
  }) {
    if (!width.isFinite || width <= 0) return;
    if (_panelWidths[key] == width && !persist) return;
    _panelWidths[key] = width;
    if (notify) notifyListeners();
    if (persist) {
      unawaited(persistPanelWidths());
    }
  }

  /// Persiste l'ensemble des largeurs personnalisées de panneaux dans [SpecWorkspaceStore].
  Future<void> persistPanelWidths() =>
      _workspaceStore.savePanelWidths(Map<String, double>.from(_panelWidths));

  /// Réinitialise la largeur mémorisée du panneau [key] et persiste la suppression.
  Future<void> clearPanelWidth(String key, {bool notify = false}) async {
    final removed = _panelWidths.remove(key) != null;
    if (notify && removed) notifyListeners();
    await persistPanelWidths();
  }

  /// Dernière erreur rencontrée, le cas échéant.
  String? get lastError => _lastError;

  /// Vrai lorsqu'une sauvegarde disque est en cours.
  bool get isSaving => _isSaving;

  /// Indique si un retour arrière Undo est disponible.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Indique si un rétablissement Redo est disponible.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Charge la liste des projets récents, les référentiels globaux et restaure optionnellement le dernier projet actif.
  Future<void> initialize({bool restoreLastProject = true}) async {
    await _loadPanelWidths();
    if (!_hasCustomStores) {
      var targetDir = await _workspaceStore.resolveInitialWorkspaceDirectory();
      try {
        _workspaceMetadata = await _workspaceStore.openWorkspace(targetDir);
      } on NonEmptyNonWorkspaceException {
        targetDir = _workspaceStore.effectiveFallbackRootDirectory;
        _workspaceMetadata = await _workspaceStore.openWorkspace(
          targetDir,
          initializeNonEmpty: true,
        );
      }
      _bindStoresForDirectory(targetDir);
      _recentWorkspaces = await _workspaceStore.listRecentWorkspaces();
    }
    await _loadWorkspaceState(restoreLastProject: restoreLastProject);
  }

  /// Ouvre un dossier Workspace Git différent et recharge tous les projets et référentiels.
  Future<void> switchWorkspace(
    Directory directory, {
    bool initializeNonEmpty = false,
    String? defaultName,
    bool restoreLastProject = true,
  }) async {
    if (_isSending) {
      throw StateError(
        'Impossible de changer de workspace pendant une génération IA en cours.',
      );
    }
    final metadata = await _workspaceStore.openWorkspace(
      directory,
      initializeNonEmpty: initializeNonEmpty,
      defaultName: defaultName,
    );
    _resetInMemoryState();
    _workspaceMetadata = metadata;
    _bindStoresForDirectory(directory);
    _recentWorkspaces = await _workspaceStore.listRecentWorkspaces();
    await _loadWorkspaceState(restoreLastProject: restoreLastProject);
  }

  /// Crée ou réinitialise un nouveau dossier Workspace Git nommé [name] et l'active.
  Future<void> createWorkspace(
    Directory directory, {
    required String name,
    bool allowNonEmpty = true,
    bool restoreLastProject = true,
  }) async {
    if (_isSending) {
      throw StateError(
        'Impossible de créer un workspace pendant une génération IA en cours.',
      );
    }
    final metadata = await _workspaceStore.createWorkspace(
      directory,
      name: name,
      allowNonEmpty: allowNonEmpty,
    );
    _resetInMemoryState();
    _workspaceMetadata = metadata;
    _bindStoresForDirectory(directory);
    _recentWorkspaces = await _workspaceStore.listRecentWorkspaces();
    await _loadWorkspaceState(restoreLastProject: restoreLastProject);
  }

  /// Rafraîchit la liste locale des workspaces récents.
  Future<void> refreshRecentWorkspaces() async {
    _recentWorkspaces = await _workspaceStore.listRecentWorkspaces();
    notifyListeners();
  }

  void _bindStoresForDirectory(Directory directory) {
    _store = SpecProjectStore(directory);
    _glossaryStore = CompanyGlossaryStore(directory);
    _modelDictionaryStore = ModelDictionaryStore(directory);
    _domainCatalogStore = DomainCatalogStore(directory);
    _enterpriseRateCardStore = EnterpriseRateCardStore(directory);
  }

  void _clearProjectFocusState() {
    _focusedObjectId = null;
    _focusedAttributePath = const <String>[];
    _businessObjectFilter = '';
    _focusedEventStormFlowId = null;
    _focusedEventStormNodeId = null;
    _focusedExampleStoryId = null;
    _focusedJourneyId = null;
    _focusedRouteId = null;
    _focusedScreenId = null;
    _focusedScreenZone = null;
    _focusedFixtureId = null;
    _focusedFeatureId = null;
    _focusedScenarioId = null;
    _focusedTddSuiteId = null;
    _focusedCostProfileId = null;
    _focusedWbsItemId = null;
    _focusedRunItemId = null;
    _focusedRiskItemId = null;
  }

  void _resetInMemoryState() {
    _project = null;
    _recentProjects = const <SpecProjectSummary>[];
    _undoStack.clear();
    _redoStack.clear();
    _companyGlossary = CompanyGlossary.empty;
    _glossaryChatMessages = const <SpecChatMessage>[];
    _glossaryUndoStack.clear();
    _glossaryRedoStack.clear();
    _modelPreferences = BusinessObjectModelPreferences.defaults;
    _enterpriseRateCard = EnterpriseRateCard.defaults;
    _domainCatalog = DomainCatalog.empty;
    _activeDesignDomainId = null;
    _modelPrefsUndoStack.clear();
    _modelPrefsRedoStack.clear();
    _rateCardUndoStack.clear();
    _rateCardRedoStack.clear();
    _clearProjectFocusState();
    _domainModelFocus.clear();
    _domainLayerActiveTab.clear();
    _sendingDomainLayerKey = null;
    _useCaseActiveTab.clear();
    _sendingUseCaseDomainId = null;
    _systemsServicesActiveFilter.clear();
    _sendingSystemsServicesDomainId = null;
    _sendingPortfolio = false;
    _lastError = null;
  }

  Future<void> _loadPanelWidths() async {
    final loaded = await _workspaceStore.loadPanelWidths();
    if (loaded.isEmpty) return;
    for (final entry in loaded.entries) {
      _panelWidths.putIfAbsent(entry.key, () => entry.value);
    }
  }

  Future<void> _loadWorkspaceState({required bool restoreLastProject}) async {
    _recentProjects = await _store.listProjects();
    try {
      _companyGlossary = await _glossaryStore.loadGlossary();
      _glossaryChatMessages = await _glossaryStore.loadChatMessages();
    } catch (_) {
      _companyGlossary = CompanyGlossary.empty;
      _glossaryChatMessages = const <SpecChatMessage>[];
    }
    try {
      _modelPreferences = await _modelDictionaryStore.load();
    } catch (_) {
      _modelPreferences = BusinessObjectModelPreferences.defaults;
    }
    try {
      _enterpriseRateCard = await _enterpriseRateCardStore.load();
    } catch (_) {
      _enterpriseRateCard = EnterpriseRateCard.defaults;
    }
    _domainCatalog = await _domainCatalogStore.load();
    if (restoreLastProject) {
      final lastId = await _store.getLastActiveProjectId();
      if (lastId != null) {
        final loaded = await _store.loadProject(lastId);
        if (loaded != null) {
          _project = loaded;
        }
      }
    }
    notifyListeners();
  }

  /// Valide, persiste et publie le catalogue [updated].
  Future<void> updateDomainCatalog(DomainCatalog updated) async {
    updated.validate();
    if (_domainCatalog == updated) return;
    for (final environment in _domainCatalog.environments.where(
      (item) => item.status == LogicalEnvironmentStatus.archived,
    )) {
      final previousEntries = _configurationSnapshot(
        _domainCatalog,
        environment.id,
      );
      final nextEntries = _configurationSnapshot(updated, environment.id);
      if (previousEntries != nextEntries) {
        throw StateError(
          'L’environnement ${environment.environmentCode} est archivé et ses configurations sont en lecture seule.',
        );
      }
    }
    await _domainCatalogStore.save(updated);
    _domainCatalog = updated;
    if (_activeDesignDomainId != null &&
        !updated.domains.any((d) => d.id == _activeDesignDomainId)) {
      _activeDesignDomainId = null;
    }
    notifyListeners();
  }

  /// Met à jour le document de contrats sans modifier les autres domaines.
  Future<void> updateDomainContracts(
    String domainId,
    DomainContracts document,
  ) {
    if (!_domainCatalog.domains.any((d) => d.id == domainId)) {
      throw StateError('Le domaine sélectionné n’existe plus.');
    }
    return updateDomainCatalog(
      _domainCatalog.copyWith(
        domains: [
          for (final domain in _domainCatalog.domains)
            if (domain.id == domainId)
              domain.copyWith(contracts: document)
            else
              domain,
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Crée et persiste un nouveau [FunctionalDomain] dans le catalogue actif.
  Future<FunctionalDomain> createFunctionalDomain({
    required String domainCode,
    required String name,
    String description = '',
    bool isActive = true,
    String? techStackId,
    bool assignDefaultTechStack = true,
  }) async {
    final trimmedCode = domainCode.trim();
    if (_domainCatalog.domains.any((d) => d.domainCode == trimmedCode)) {
      throw const FormatException('Ce code de domaine existe déjà.');
    }
    final resolvedStackId = techStackId?.trim().isNotEmpty == true
        ? techStackId!.trim()
        : (assignDefaultTechStack
              ? _domainCatalog.techStacks.firstOrNull?.id
              : null);
    final domain = FunctionalDomain(
      id: 'domain_${shortid.generate()}',
      domainCode: trimmedCode,
      name: name.trim(),
      description: description.trim(),
      isActive: isActive,
      techStackId: resolvedStackId,
    );
    domain.validate();
    final now = DateTime.now().toUtc();
    final event = AuditLogEntry(
      id: 'audit_${shortid.generate()}',
      recordedAt: now,
      actorUsername: 'local-user',
      domainId: domain.id,
      actionType: DomainAuditAction.create,
      details: 'Domaine créé.',
    );
    await updateDomainCatalog(
      _domainCatalog.copyWith(
        domains: [..._domainCatalog.domains, domain],
        auditLog: [..._domainCatalog.auditLog, event],
        updatedAt: now,
      ),
    );
    return domain;
  }

  /// Promeut une sélection d'objets métiers du projet courant vers les domaines
  /// fonctionnels choisis de l'espace Design et persiste le catalogue mis à jour.
  Future<PromotionExecutionResult> promoteBusinessObjectsToDesign(
    List<ObjectPromotionChoice> choices,
  ) async {
    final currentProject = _project;
    if (currentProject == null) {
      throw StateError('Aucun projet actif pour la promotion.');
    }
    final result = SpecDesignPromoter.promote(
      project: currentProject,
      catalog: _domainCatalog,
      choices: choices,
      modelPreferences: _modelPreferences,
    );
    if (result.updatedCatalog != _domainCatalog) {
      await updateDomainCatalog(result.updatedCatalog);
    }
    return result;
  }

  DomainContracts? _domainContractsOf(String domainId) => _domainCatalog.domains
      .where((domain) => domain.id == domainId)
      .firstOrNull
      ?.contracts;

  /// Enregistre le détail (attributs) d'un modèle du domaine [domainId] ;
  /// [object] porte l'ID de l'entrée du catalogue.
  Future<void> updateDomainModelObject(
    String domainId,
    BusinessObjectSpec object,
  ) {
    final contracts = _domainContractsOf(domainId);
    if (contracts == null) {
      throw StateError('Le domaine sélectionné n’existe plus.');
    }
    return updateDomainContracts(
      domainId,
      contracts.withModel(object.id, object: object),
    );
  }

  /// Enregistre la spécification de la couche Domain (Architecture Hexagonale)
  /// de l'entrée [entryId] du domaine [domainId].
  Future<void> updateDomainModelLayer(
    String domainId,
    String entryId,
    HexagonalDomainLayerSpec layer,
  ) {
    final contracts = _domainContractsOf(domainId);
    if (contracts == null || contracts.entryById(entryId) == null) {
      throw StateError('Le modèle sélectionné n’existe plus.');
    }
    return updateDomainContracts(
      domainId,
      contracts.withDomainLayer(entryId, layer: layer),
    );
  }

  Future<bool> _updateDomainLayerChat(
    String domainId,
    String entryId,
    List<SpecChatMessage> Function(List<SpecChatMessage> chat) update,
  ) async {
    final contracts = _domainContractsOf(domainId);
    if (contracts?.entryById(entryId) == null) return false;
    await updateDomainContracts(
      domainId,
      contracts!.withDomainLayer(
        entryId,
        chat: update(contracts.domainLayerChats[entryId] ?? const []),
      ),
    );
    return true;
  }

  /// Remplace l'historique du chat d'un modèle ; `false` si l'entrée a disparu.
  Future<bool> _updateDomainModelChat(
    String domainId,
    String entryId,
    List<SpecChatMessage> Function(List<SpecChatMessage> chat) update,
  ) async {
    final contracts = _domainContractsOf(domainId);
    if (contracts?.entryById(entryId) == null) return false;
    await updateDomainContracts(
      domainId,
      contracts!.withModel(
        entryId,
        chat: update(contracts.chats[entryId] ?? const []),
      ),
    );
    return true;
  }

  String _configurationSnapshot(DomainCatalog catalog, String environmentId) {
    final entries =
        catalog.configurationEntries
            .where((entry) => entry.environmentId == environmentId)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode([for (final entry in entries) entry.toJson()]);
  }

  /// Rafraîchit la liste des projets sauvegardés.
  Future<void> refreshRecentProjects() async {
    _recentProjects = await _store.listProjects();
    notifyListeners();
  }

  /// Met à jour le mode de vitesse Gemini.
  void setSpeedMode(VibeAiSpeedMode mode) {
    if (_speedMode == mode) return;
    _speedMode = mode;
    notifyListeners();
  }

  /// Met à jour le niveau de questionnement.
  void setQuestioningLevel(VibeQuestioningLevel level) {
    if (_questioningLevel == level) return;
    _questioningLevel = level;
    notifyListeners();
  }

  /// Crée un nouveau projet à partir de [idea], le sauvegarde et lance
  /// l'étape 1 uniquement si [autoKickoff] vaut `true` (sinon l'utilisateur
  /// démarre manuellement via le bouton « Commencer » du chat d'étape).
  Future<void> createProjectFromIdea({
    required String idea,
    String? name,
    bool autoKickoff = false,
  }) async {
    final created = SpecForgeProject.fromIdea(idea: idea, name: name);
    _undoStack.clear();
    _redoStack.clear();
    _clearProjectFocusState();
    _lastError = null;
    _project = created;
    await _persistProject(created);
    notifyListeners();

    if (autoKickoff) {
      await kickoffStageIfEmpty(SpecForgeStage.lexicon);
    }
  }

  /// Ouvre un projet existant par son identifiant.
  Future<void> openProject(String projectId) async {
    final loaded = await _store.loadProject(projectId);
    if (loaded == null) return;
    _undoStack.clear();
    _redoStack.clear();
    _clearProjectFocusState();
    _lastError = null;
    _project = loaded;
    await _store.setLastActiveProjectId(loaded.id);
    notifyListeners();
  }

  /// Ferme le projet courant pour revenir à l'écran d'accueil.
  Future<void> closeProject() async {
    _project = null;
    _undoStack.clear();
    _redoStack.clear();
    _clearProjectFocusState();
    _lastError = null;
    await refreshRecentProjects();
    notifyListeners();
  }

  /// Supprime un projet du disque.
  Future<void> deleteProject(String projectId) async {
    await _store.deleteProject(projectId);
    if (_project?.id == projectId) {
      _project = null;
      _undoStack.clear();
      _redoStack.clear();
      _clearProjectFocusState();
    }
    await refreshRecentProjects();
    notifyListeners();
  }

  /// Met à jour le projet manuellement (avec support Undo/Redo et sauvegarde automatique).
  Future<void> updateProject(
    SpecForgeProject updated, {
    bool recordUndo = true,
  }) async {
    final current = _project;
    if (current == null || current == updated) return;
    if (recordUndo) {
      _pushUndo(current);
    }
    if (current.activeFeatureId != updated.activeFeatureId) {
      _clearProjectFocusState();
    }
    _project = updated;
    notifyListeners();
    await _persistProject(updated);
  }

  /// Sélectionne [featureId] comme feature active du projet et réinitialise les focus d'ateliers.
  Future<void> selectActiveFeature(String featureId) async {
    if (_isSending) return;
    final current = _project;
    if (current == null || current.activeFeatureId == featureId) return;
    if (current.featureById(featureId) == null) return;
    _clearProjectFocusState();
    final next = current.selectFeature(featureId);
    _project = next;
    notifyListeners();
    await _persistProject(next);
  }

  /// Crée une nouvelle initiative dans le projet actif (avec une première feature optionnelle).
  Future<SpecInitiative?> addInitiative({
    String? code,
    required String name,
    String description = '',
    String owner = '',
    String targetTimeframe = '',
    RequirementPriority priority = RequirementPriority.must,
    SpecPortfolioStatus status = SpecPortfolioStatus.draft,
    bool createInitialFeature = true,
  }) async {
    final current = _project;
    if (current == null) return null;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;

    final initCode = (code != null && code.trim().isNotEmpty)
        ? code.trim()
        : current.nextInitiativeCode();
    final initialFeatures = <SpecFeatureSpec>[
      if (createInitialFeature)
        SpecFeatureSpec.create(
          code: current.nextFeatureCode(),
          name: trimmedName,
          description: description,
          priority: priority,
        ),
    ];
    final created = SpecInitiative.create(
      code: initCode,
      name: trimmedName,
      description: description,
      owner: owner,
      targetTimeframe: targetTimeframe,
      priority: priority,
      status: status,
      features: initialFeatures,
    );
    final next = current.copyWith(
      initiatives: <SpecInitiative>[...current.initiatives, created],
      activeFeatureId: initialFeatures.isNotEmpty
          ? initialFeatures.first.id
          : current.activeFeatureId,
    );
    next.validate();
    await updateProject(next);
    return created;
  }

  /// Met à jour les métadonnées d'une initiative existante.
  Future<void> updateInitiativeMetadata({
    required String initiativeId,
    String? code,
    String? name,
    String? description,
    String? owner,
    String? targetTimeframe,
    RequirementPriority? priority,
    SpecPortfolioStatus? status,
  }) async {
    final current = _project;
    if (current == null) return;
    final existing = current.initiativeById(initiativeId);
    if (existing == null) return;
    final updatedInit = existing.copyWith(
      code: code?.trim(),
      name: name != null && name.trim().isNotEmpty
          ? name.trim()
          : existing.name,
      description: description?.trim(),
      owner: owner?.trim(),
      targetTimeframe: targetTimeframe?.trim(),
      priority: priority,
      status: status,
    );
    if (updatedInit == existing) return;
    final next = current.copyWith(
      initiatives: <SpecInitiative>[
        for (final i in current.initiatives)
          if (i.id == initiativeId) updatedInit else i,
      ],
    );
    next.validate();
    await updateProject(next);
  }

  /// Supprime une initiative du projet (en conservant toujours au moins 1 initiative et 1 feature).
  Future<void> deleteInitiative(String initiativeId) async {
    final current = _project;
    if (current == null || current.initiatives.length <= 1) return;
    final remaining = <SpecInitiative>[
      for (final i in current.initiatives)
        if (i.id != initiativeId) i,
    ];
    if (remaining.isEmpty) return;
    final hasAnyFeature = remaining.any((i) => i.features.isNotEmpty);
    if (!hasAnyFeature) {
      remaining[0] = remaining[0].copyWith(
        features: <SpecFeatureSpec>[
          SpecFeatureSpec.create(
            code: 'FEAT-01',
            name: remaining[0].name,
            description: remaining[0].description,
          ),
        ],
      );
    }
    final next = current.copyWith(initiatives: remaining);
    next.validate();
    await updateProject(next);
  }

  /// Réordonne une initiative vers le haut (`delta < 0`) ou vers le bas (`delta > 0`).
  Future<void> moveInitiative(String initiativeId, int delta) async {
    final current = _project;
    if (current == null || delta == 0) return;
    final list = List<SpecInitiative>.from(current.initiatives);
    final idx = list.indexWhere((i) => i.id == initiativeId);
    if (idx < 0) return;
    final target = (idx + delta).clamp(0, list.length - 1);
    if (target == idx) return;
    final moved = list.removeAt(idx);
    list.insert(target, moved);
    await updateProject(current.copyWith(initiatives: list));
  }

  /// Ajoute une nouvelle feature à l'initiative [initiativeId] et l'active optionnellement.
  Future<SpecFeatureSpec?> addFeature({
    required String initiativeId,
    String? code,
    required String name,
    String description = '',
    String targetRelease = '',
    RequirementPriority priority = RequirementPriority.must,
    SpecPortfolioStatus status = SpecPortfolioStatus.draft,
    bool activate = true,
  }) async {
    final current = _project;
    if (current == null) return null;
    final targetInit = current.initiativeById(initiativeId);
    if (targetInit == null) return null;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;

    final featCode = (code != null && code.trim().isNotEmpty)
        ? code.trim()
        : current.nextFeatureCode();
    final created = SpecFeatureSpec.create(
      code: featCode,
      name: trimmedName,
      description: description,
      targetRelease: targetRelease,
      priority: priority,
      status: status,
    );

    final nextInitiatives = <SpecInitiative>[
      for (final i in current.initiatives)
        if (i.id == initiativeId)
          i.copyWith(features: <SpecFeatureSpec>[...i.features, created])
        else
          i,
    ];
    final next = current.copyWith(
      initiatives: nextInitiatives,
      activeFeatureId: activate ? created.id : current.activeFeatureId,
    );
    next.validate();
    await updateProject(next);
    return created;
  }

  /// Met à jour les métadonnées d'une feature (et la déplace vers [targetInitiativeId] si précisé).
  Future<void> updateFeatureMetadata({
    required String featureId,
    String? targetInitiativeId,
    String? code,
    String? name,
    String? description,
    String? targetRelease,
    RequirementPriority? priority,
    SpecPortfolioStatus? status,
  }) async {
    final current = _project;
    if (current == null) return;
    final existing = current.featureById(featureId);
    final sourceInit = current.initiativeOfFeature(featureId);
    if (existing == null || sourceInit == null) return;

    final nextDesc = description?.trim() ?? existing.description;
    final nextVision =
        (existing.vision.ideaSummary.trim().isEmpty && nextDesc.isNotEmpty)
        ? existing.vision.copyWith(ideaSummary: nextDesc)
        : existing.vision;

    final updatedFeat = existing.copyWith(
      code: code?.trim(),
      name: name != null && name.trim().isNotEmpty
          ? name.trim()
          : existing.name,
      description: nextDesc,
      targetRelease: targetRelease?.trim(),
      priority: priority,
      status: status,
      vision: nextVision,
    );

    final destInitId =
        (targetInitiativeId != null &&
            current.initiativeById(targetInitiativeId) != null)
        ? targetInitiativeId
        : sourceInit.id;

    if (destInitId == sourceInit.id && updatedFeat == existing) return;

    final nextInitiatives = <SpecInitiative>[
      for (final i in current.initiatives)
        if (i.id == sourceInit.id && destInitId == sourceInit.id)
          i.copyWith(
            features: <SpecFeatureSpec>[
              for (final f in i.features)
                if (f.id == featureId) updatedFeat else f,
            ],
          )
        else if (i.id == sourceInit.id)
          i.copyWith(
            features: <SpecFeatureSpec>[
              for (final f in i.features)
                if (f.id != featureId) f,
            ],
          )
        else if (i.id == destInitId)
          i.copyWith(features: <SpecFeatureSpec>[...i.features, updatedFeat])
        else
          i,
    ];

    final next = current.copyWith(initiatives: nextInitiatives);
    next.validate();
    await updateProject(next);
  }

  /// Supprime une feature du projet (tant qu'il reste au moins une autre feature).
  Future<void> deleteFeature(String featureId) async {
    final current = _project;
    if (current == null || current.totalFeatureCount <= 1) return;
    final nextInitiatives = <SpecInitiative>[
      for (final i in current.initiatives)
        i.copyWith(
          features: <SpecFeatureSpec>[
            for (final f in i.features)
              if (f.id != featureId) f,
          ],
        ),
    ];
    final next = current.copyWith(initiatives: nextInitiatives);
    next.validate();
    await updateProject(next);
  }

  /// Réordonne une feature à l'intérieur de son initiative (`delta < 0` haut, `delta > 0` bas).
  Future<void> moveFeature(
    String initiativeId,
    String featureId,
    int delta,
  ) async {
    final current = _project;
    if (current == null || delta == 0) return;
    final init = current.initiativeById(initiativeId);
    if (init == null) return;
    final list = List<SpecFeatureSpec>.from(init.features);
    final idx = list.indexWhere((f) => f.id == featureId);
    if (idx < 0) return;
    final target = (idx + delta).clamp(0, list.length - 1);
    if (target == idx) return;
    final moved = list.removeAt(idx);
    list.insert(target, moved);
    final nextInitiatives = <SpecInitiative>[
      for (final i in current.initiatives)
        if (i.id == initiativeId) i.copyWith(features: list) else i,
    ];
    await updateProject(current.copyWith(initiatives: nextInitiatives));
  }

  /// Valide et met à jour le volet UX du projet actif (avec support Undo/Redo unifié et sauvegarde automatique).
  Future<void> updateUxSpec(
    UxForgeSpec updatedUx, {
    bool recordUndo = true,
  }) async {
    updatedUx.validate();
    final current = _project;
    if (current == null || current.uxSpec == updatedUx) return;
    final next = current.copyWith(uxSpec: updatedUx);
    next.validate();
    await updateProject(next, recordUndo: recordUndo);
  }

  /// Valide et met à jour le volet QA BDD/TDD du projet actif (avec support Undo/Redo unifié et sauvegarde automatique).
  Future<void> updateQaSpec(
    QaForgeSpec updatedQa, {
    bool recordUndo = true,
  }) async {
    updatedQa.validate();
    final current = _project;
    if (current == null || current.qaSpec == updatedQa) return;
    final next = current.copyWith(qaSpec: updatedQa);
    next.validate();
    await updateProject(next, recordUndo: recordUndo);
  }

  /// Valide et met à jour le volet FinOps / Estimation de coût IT du projet actif (avec Undo/Redo et sauvegarde).
  Future<void> updateCostSpec(
    CostForgeSpec updatedCost, {
    bool recordUndo = true,
  }) async {
    updatedCost.validate();
    final current = _project;
    if (current == null || current.costSpec == updatedCost) return;
    final next = current.copyWith(costSpec: updatedCost);
    next.validate();
    await updateProject(next, recordUndo: recordUndo);
  }

  /// Pré-remplit en 1 clic de manière non destructive les lots WBS, le socle Run et les risques depuis les artefacts du projet.
  Future<CostSeedResult> seedCostFromProject() async {
    final current = _project;
    if (current == null) {
      return CostSeedResult(spec: CostForgeSpec.empty);
    }
    final seeded = CostAutoSeeder.seedFromProject(
      current,
      enterpriseRateCard: _enterpriseRateCard,
    );
    if (seeded.spec != current.costSpec) {
      await updateCostSpec(seeded.spec);
    }
    return seeded;
  }

  /// Applique la grille tarifaire d'entreprise ([enterpriseRateCard] ou [overrideCard]) au projet actif.
  Future<bool> applyEnterpriseRateCardToProject([
    EnterpriseRateCard? overrideCard,
  ]) async {
    final current = _project;
    if (current == null) return false;
    final targetCard = overrideCard ?? _enterpriseRateCard;
    final nextCost = current.costSpec.applyEnterpriseRateCard(targetCard);
    if (nextCost == current.costSpec) return false;
    await updateCostSpec(nextCost);
    return true;
  }

  /// Promeut la grille TJM et les abaques du projet actif vers la grille tarifaire d'entreprise partagée.
  Future<void> promoteProjectRateCardToEnterprise() async {
    final current = _project;
    if (current == null) return;
    await updateEnterpriseRateCard(current.costSpec.toEnterpriseRateCard());
  }

  /// Définit la langue officielle des mots-clés Gherkin (`fr` / `en`) du projet actif (annulable via Undo/Redo).
  Future<void> setGherkinLanguage(GherkinKeywordLanguage language) async {
    final current = _project;
    if (current == null || current.qaSpec.gherkinLanguage == language) return;
    await updateQaSpec(current.qaSpec.copyWith(gherkinLanguage: language));
  }

  /// Génère en 1 clic des fixtures déterministes nominales et aux bornes/invalides pour les objets métiers non couverts.
  Future<int> seedQaFixturesFromSchema() async {
    final current = _project;
    if (current == null) return 0;
    final added = QaAutoSeeder.seedFixturesFromSchema(current);
    if (added.isEmpty) return 0;
    await updateQaSpec(
      current.qaSpec.copyWith(
        fixtures: [...current.qaSpec.fixtures, ...added],
      ),
    );
    return added.length;
  }

  /// Génère en 1 clic des fonctionnalités Gherkin initiales à partir des parcours UX, cas d'usage et exigences non couverts.
  Future<int> seedQaFeaturesFromSpecAndUx() async {
    final current = _project;
    if (current == null) return 0;
    final added = QaAutoSeeder.seedFeaturesFromSpecAndUx(current);
    if (added.isEmpty) return 0;
    await updateQaSpec(
      current.qaSpec.copyWith(
        features: [...current.qaSpec.features, ...added],
      ),
    );
    return added.length;
  }

  /// Génère en 1 clic des suites TDD unitaires initiales à partir des règles de gestion actives non couvertes.
  Future<int> seedQaTddSuitesFromRules() async {
    final current = _project;
    if (current == null) return 0;
    final added = QaAutoSeeder.seedTddSuitesFromRules(current);
    if (added.isEmpty) return 0;
    await updateQaSpec(
      current.qaSpec.copyWith(
        tddSuites: [...current.qaSpec.tddSuites, ...added],
      ),
    );
    return added.length;
  }

  /// Initialise des documents Event Storming DSL v1.0 (1 par Bounded Context)
  /// depuis le Cahier des charges et retourne le nombre de documents et d'étapes ajoutés.
  Future<({int addedDocumentsCount, int addedStepsCount})>
  seedEventStormingFromSpecifications() async {
    final current = _project;
    if (current == null) {
      return (addedDocumentsCount: 0, addedStepsCount: 0);
    }
    final res = EventStormingOperations.seedFromCahierDesCharges(current);
    if (res.addedDocumentsCount == 0 && res.addedStepsCount == 0) {
      return (addedDocumentsCount: 0, addedStepsCount: 0);
    }
    final next = current.copyWith(eventStorming: res.updated);
    await updateProject(next);
    if (_focusedEventStormFlowId == null && res.updated.documents.isNotEmpty) {
      focusEventStormFlow(res.updated.documents.first.id);
    }
    return (
      addedDocumentsCount: res.addedDocumentsCount,
      addedStepsCount: res.addedStepsCount,
    );
  }

  /// Importe ou met à jour un document Event Storming depuis du YAML `.es.yaml`.
  Future<({String documentId, String boundedContext, bool createdNew})?>
  importEventStormingYaml(String yamlContent, {String? idHint}) async {
    final current = _project;
    if (current == null) return null;
    final res = EventStormingOperations.upsertDocumentFromYaml(
      current.eventStorming,
      yamlContent,
      idHint: idHint,
    );
    final next = current.copyWith(eventStorming: res.updated);
    await updateProject(next);
    focusEventStormFlow(res.document.id);
    return (
      documentId: res.document.id,
      boundedContext: res.document.meta.boundedContext,
      createdNew: res.createdNew,
    );
  }

  /// Synthétise ou enrichit les objets métiers (et cycles de vie) à partir des
  /// agrégats, commandes et événements modélisés dans l'Event Storming.
  Future<({int createdObjectsCount, int enrichedObjectsCount})>
  generateBusinessObjectsFromEventStorming() async {
    final current = _project;
    if (current == null) {
      return (createdObjectsCount: 0, enrichedObjectsCount: 0);
    }
    final res =
        EventStormingOperations.synthesizeBusinessObjectsFromEventStorming(
          current,
        );
    if (res.project == current) {
      return (createdObjectsCount: 0, enrichedObjectsCount: 0);
    }
    await updateProject(res.project);
    return (
      createdObjectsCount: res.createdObjectsCount,
      enrichedObjectsCount: res.enrichedObjectsCount,
    );
  }

  /// Promeut la politique d'une étape Event Storming en règle de gestion `RG-xxx`.
  Future<({BusinessRuleSpec rule, bool createdNew})?>
  promoteEventStormPolicyToBusinessRule({
    required String documentId,
    required int stepNumber,
  }) async {
    final current = _project;
    if (current == null) return null;
    final res = EventStormingOperations.promotePolicyToBusinessRule(
      current,
      documentId: documentId,
      stepNumber: stepNumber,
    );
    await updateProject(res.project);
    return (rule: res.rule, createdNew: res.createdNew);
  }

  /// Initialise des tableaux Jaunes d'Example Mapping pour les objets métiers
  /// non encore couverts et retourne le nombre de tableaux créés.
  Future<int> seedExampleMappingStories() async {
    final current = _project;
    if (current == null) return 0;
    final added = ExampleMappingOperations.seedStoriesFromObjectsAndUseCases(
      current,
    );
    if (added.isEmpty) return 0;
    final next = current.copyWith(
      exampleMappings: [...current.exampleMappings, ...added],
    );
    await updateProject(next);
    if (_focusedExampleStoryId == null) {
      focusExampleStory(added.first.id);
    }
    return added.length;
  }

  /// Promeut une carte bleue d'Example Mapping en règle de gestion `RG-xxx`
  /// (ou synchronise ses exemples avec la règle déjà liée).
  Future<({BusinessRuleSpec rule, bool createdNew})?>
  promoteExampleRuleToBusinessRule({
    required String storyId,
    required String ruleId,
  }) async {
    final current = _project;
    if (current == null) return null;
    final result = ExampleMappingOperations.promoteRuleToBusinessRule(
      current,
      storyId: storyId,
      ruleId: ruleId,
    );
    await updateProject(result.project);
    return (rule: result.rule, createdNew: result.createdNew);
  }

  /// Injecte les valeurs concrètes des cartes vertes d'un tableau d'Example Mapping
  /// dans les `examples` JSON Schema des attributs correspondants de l'objet métier cible.
  Future<int> enrichBusinessObjectFromExampleMapping({
    required String storyId,
    String? exampleId,
  }) async {
    final current = _project;
    if (current == null) return 0;
    final result = ExampleMappingOperations.enrichObjectExamplesFromStory(
      current,
      storyId: storyId,
      exampleId: exampleId,
    );
    if (result.injectedValuesCount == 0) return 0;
    await updateProject(result.project);
    return result.injectedValuesCount;
  }

  /// Applique la sélection utilisateur issue de la popup de comparaison/choix
  /// pour injecter des exemples dans le schéma de l'objet métier cible.
  Future<({int injectedValuesCount, int updatedAttributesCount})>
  applyExampleInjectionSelection({
    required String storyId,
    required Map<String, List<Object?>> selectedByAttributePath,
    ExampleInjectionMode mode = ExampleInjectionMode.append,
  }) async {
    final current = _project;
    if (current == null) {
      return (injectedValuesCount: 0, updatedAttributesCount: 0);
    }
    final result = ExampleMappingOperations.applyExampleInjectionSelection(
      current,
      storyId: storyId,
      selectedByAttributePath: selectedByAttributePath,
      mode: mode,
    );
    if (result.updatedAttributesCount == 0) {
      return (injectedValuesCount: 0, updatedAttributesCount: 0);
    }
    await updateProject(result.project);
    return (
      injectedValuesCount: result.injectedValuesCount,
      updatedAttributesCount: result.updatedAttributesCount,
    );
  }

  /// Crée ou met à jour un objet métier depuis l'atelier UX (annulable en 1 clic via Undo/Redo).
  Future<void> upsertBusinessObjectFromUx(BusinessObjectSpec object) async {
    object.validate();
    final current = _project;
    if (current == null) return;
    final nextObjects = BusinessObjectOperations.upsertObject(
      current.businessObjects,
      object,
    );
    if (listEquals(nextObjects, current.businessObjects)) return;
    final next = current.copyWith(businessObjects: nextObjects);
    next.validate();
    await updateProject(next);
  }

  /// Ajoute ou met à jour un attribut (ou sous-attribut via [parentAttrPath]) sur l'objet
  /// métier [objectId] depuis l'atelier UX (annulable en 1 clic via Undo/Redo).
  Future<void> upsertBusinessAttributeFromUx({
    required String objectId,
    List<String> parentAttrPath = const <String>[],
    required BusinessAttribute attribute,
  }) async {
    attribute.validate();
    final current = _project;
    if (current == null) return;
    final targetObject =
        current.businessObjects.where((o) => o.id == objectId).firstOrNull ??
        current.findBusinessObject(objectId);
    if (targetObject == null) {
      throw StateError('Objet métier introuvable : $objectId');
    }
    final updatedObject = BusinessObjectOperations.upsertAttributeAtPath(
      targetObject,
      parentAttrPath: parentAttrPath,
      attribute: attribute,
    );
    updatedObject.validate();
    if (updatedObject == targetObject) return;
    final nextObjects = BusinessObjectOperations.replaceObject(
      current.businessObjects,
      updatedObject,
    );
    final next = current.copyWith(businessObjects: nextObjects);
    next.validate();
    await updateProject(next);
  }

  /// Crée ou met à jour une règle de gestion [rule] par identifiant depuis l'atelier UX
  /// sans supprimer aucune autre règle existante (annulable en 1 clic via Undo/Redo).
  Future<void> upsertBusinessRuleFromUx(BusinessRuleSpec rule) async {
    rule.validate();
    final current = _project;
    if (current == null) return;
    final nextRules = List<BusinessRuleSpec>.from(current.businessRules);
    final idx = nextRules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      if (nextRules[idx] == rule) return;
      nextRules[idx] = rule;
    } else {
      nextRules.add(rule);
    }
    final next = current.copyWith(businessRules: nextRules);
    next.validate();
    await updateProject(next);
  }

  /// Annule la dernière modification structurelle.
  Future<void> undo() async {
    final current = _project;
    if (current == null || _undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    _redoStack.add(current);
    _project = previous;
    notifyListeners();
    await _persistProject(previous);
  }

  /// Rétablit une modification annulée.
  Future<void> redo() async {
    final current = _project;
    if (current == null || _redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(current);
    _project = next;
    notifyListeners();
    await _persistProject(next);
  }

  /// Navigue vers [targetStage], valide optionnellement l'étape précédente et
  /// lance l'agent spécialisé de [targetStage] uniquement si [autoKickoffIfEmpty]
  /// vaut `true` et que sa conversation est vide.
  Future<void> goToStage(
    SpecForgeStage targetStage, {
    bool validateCurrent = false,
    bool autoKickoffIfEmpty = false,
  }) async {
    final current = _project;
    if (current == null) return;
    final moved = current.moveToStage(
      targetStage,
      validateCurrentStage: validateCurrent,
    );
    if (moved != current) {
      _project = moved;
      notifyListeners();
      await _persistProject(moved);
    }
    if (autoKickoffIfEmpty &&
        !_isSending &&
        moved.stageStateFor(targetStage).messages.isEmpty) {
      await kickoffStageIfEmpty(targetStage);
    }
  }

  /// Déclenche le message initial de l'agent spécialisé si l'étape n'a aucun échange.
  Future<void> kickoffStageIfEmpty(SpecForgeStage stage) async {
    final current = _project;
    if (current == null || _isSending) return;
    if (current.stageStateFor(stage).messages.isNotEmpty) return;
    final kickoffPrompt = SpecPromptBuilder.buildStageKickoffPrompt(
      current,
      stage,
      modelPreferencesOverride: _modelPreferences,
    );
    await _runAgentTurn(
      stage: stage,
      userDisplayText: switch (stage) {
        SpecForgeStage.lexicon => 'Idée initiale : ${current.initialIdea}',
        SpecForgeStage.vision =>
          'Démarrer le cadrage & acteurs à partir du lexique métier.',
        SpecForgeStage.specifications =>
          'Démarrer le cahier des charges à partir du cadrage.',
        SpecForgeStage.eventStorming =>
          'Lancer l’atelier Event Storming à partir du cahier des charges.',
        SpecForgeStage.businessObjects =>
          'Modéliser les objets métiers à partir de l’Event Storming et du cahier des charges.',
        SpecForgeStage.exampleMapping =>
          'Lancer l’Example Mapping pour affiner les objets métiers par des exemples concrets.',
        SpecForgeStage.businessRules =>
          'Formaliser les règles de gestion sur les objets métiers.',
        SpecForgeStage.reviewExport =>
          'Lancer l’audit de cohérence global du projet.',
      },
      promptInput: kickoffPrompt,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Envoie un message utilisateur libre (avec pièces jointes éventuelles) à l'agent de l'étape courante.
  Future<void> sendUserMessage(
    String text, {
    bool requestsMoreQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !requestsMoreQuestions && attachments.isEmpty) {
      return;
    }
    final stage = current.currentStage;
    final effectiveDisplay = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour approfondir cette étape.'
              : 'Analyse les pièces jointes et mets à jour les spécifications correspondantes.');
    await _runAgentTurn(
      stage: stage,
      userDisplayText: effectiveDisplay,
      promptInput: effectiveDisplay,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Lance une recherche ciblée de complément de lexique métier pour la feature active.
  Future<void> requestLexiconComplementForActiveFeature() async {
    var current = _project;
    if (current == null || _isSending) return;
    if (current.currentStage != SpecForgeStage.lexicon) {
      await goToStage(SpecForgeStage.lexicon);
      current = _project;
      if (current == null) return;
    }
    final displayText = current.hasSingleDefaultFeature
        ? 'Rechercher un complément de lexique pour le projet.'
        : 'Compléter le lexique métier pour ${current.activeFeature.displayLabel}.';
    final promptInput = SpecPromptBuilder.buildLexiconComplementPrompt(current);
    await _runAgentTurn(
      stage: SpecForgeStage.lexicon,
      userDisplayText: displayText,
      promptInput: promptInput,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Soumet les réponses d'un questionnaire `VibeAskUserCard` à l'agent de l'étape.
  Future<void> submitAskUserAnswers(
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.currentStage;
    final stageState = current.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final updatedMsg = targetMsg.copyWith(
      askUserAnswers: answers,
      askUserUsedDefaults: usedDefaults,
      askUserRequestedMore: askMore,
    );
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = updatedMsg;
    _project = current.withStageState(
      stageState.copyWith(messages: updatedMessages),
    );
    notifyListeners();

    final formattedSummary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    final displaySummary = askMore
        ? '$formattedSummary\n(+ questions complémentaires demandées)'
        : formattedSummary;

    await _runAgentTurn(
      stage: stage,
      userDisplayText: displaySummary,
      promptInput: formattedSummary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
    );
  }

  /// Ignore un questionnaire en proposant de passer directement à la génération avec hypothèses.
  Future<void> skipAskUser(String messageId) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.currentStage;
    final stageState = current.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final defaults = askUser.defaultAnswers();
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = targetMsg.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      );
    _project = current.withStageState(
      stageState.copyWith(messages: updatedMessages),
    );
    notifyListeners();

    final formatted =
        'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}';
    await _runAgentTurn(
      stage: stage,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput: formatted,
      afterAskUserReply: true,
      forceFollowUpQuestions: false,
    );
  }

  /// Stoppe immédiatement la réflexion / génération IA en cours.
  void stopAiGeneration() {
    if (!_isSending) return;
    _stopRequested = true;
    debugPrint(
      '[SpecForge IA] Réflexion interrompue par l’utilisateur (${_sendingStage?.agentTitle ?? _sendingUxStage?.agentTitle ?? _sendingQaStage?.agentTitle ?? 'agent'}).',
    );
    final sub = _activeStreamSubscription;
    _activeStreamSubscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    final completer = _activeStreamCompleter;
    _activeStreamCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Relance manuellement le dernier tour en erreur sur l'étape active avec contexte de correction.
  Future<void> retryLastFailedTurn() async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.currentStage;
    final messages = current.stageStateFor(stage).messages;
    String retryInput =
        'La tentative précédente a échoué. Corrige le format JSON et applique la mise à jour demandée.';
    List<VibeChatAttachment> lastAttachments = const <VibeChatAttachment>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.isUser) {
        retryInput = (msg.promptText ?? msg.text).trim();
        lastAttachments = msg.attachments;
        break;
      }
    }
    await _runAgentTurn(
      stage: stage,
      userDisplayText: 'Reprise de la génération suite à erreur…',
      promptInput:
          '$retryInput\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastAttachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Efface l'historique conversationnel de l'étape active (ou de [stage]) du wizard Spec.
  Future<void> clearStageChat([SpecForgeStage? stage]) async {
    final current = _project;
    if (current == null || _isSending) return;
    final targetStage = stage ?? current.currentStage;
    final stageState = current.stageStateFor(targetStage);
    if (stageState.messages.isEmpty && !stageState.readyToAdvance) return;
    final cleared = current.withStageState(
      stageState.copyWith(
        messages: const <SpecChatMessage>[],
        readyToAdvance: false,
      ),
    );
    _project = cleared;
    notifyListeners();
    await _persistProject(cleared);
  }

  /// Pose une question libre portant sur la globalité du projet dans l'onglet « Question ».
  Future<void> sendGlobalQuestion(
    String text, {
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : 'Analyse les pièces jointes au regard de l’ensemble du projet.';
    await _runGlobalQuestionTurn(
      userDisplayText: effectiveText,
      questionInput: effectiveText,
      attachments: attachments,
    );
  }

  /// Relance la dernière question globale en erreur.
  Future<void> retryLastGlobalQuestion() async {
    final current = _project;
    if (current == null || _isSending) return;
    final messages = current.globalChatMessages;
    var retryText =
        'Réponds à ma dernière question sur la globalité du projet.';
    var lastAttachments = const <VibeChatAttachment>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        retryText = (messages[i].promptText ?? messages[i].text).trim();
        lastAttachments = messages[i].attachments;
        break;
      }
    }
    await _runGlobalQuestionTurn(
      userDisplayText: 'Nouvelle tentative sur la question précédente…',
      questionInput: retryText,
      attachments: lastAttachments,
    );
  }

  /// Efface l'historique du chat global de questions sur le projet courant.
  Future<void> clearGlobalChat() async {
    final current = _project;
    if (current == null || _isSending) return;
    final cleared = current.copyWith(globalChatMessages: const []);
    _project = cleared;
    notifyListeners();
    await _persistProject(cleared);
  }

  Future<void> _runGlobalQuestionTurn({
    required String userDisplayText,
    required String questionInput,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final initialProject = _project;
    if (initialProject == null) return;

    final userMessage = SpecChatMessage(
      id: 'gmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: questionInput,
      attachments: attachments,
    );

    final withUserMsg = initialProject.copyWith(
      globalChatMessages: [...initialProject.globalChatMessages, userMessage],
    );
    _project = withUserMsg;
    _isSending = true;
    _sendingGlobalQuestion = true;
    _stopRequested = false;
    _sendingStage = null;
    _sendingUxStage = null;
    _sendingQaStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Analyse transverse du projet…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    var workingProject = withUserMsg;
    var currentPrompt = SpecPromptBuilder.buildGlobalQuestionPrompt(
      project: initialProject,
      userInput: questionInput,
      companyGlossary: _companyGlossary,
    );
    final turnToolTraces = <VibeToolTrace>[];

    final registry = _buildProjectToolRegistry(
      readWorkingProject: () => workingProject,
      writeWorkingProject: (next) => workingProject = next,
    );

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (_stopRequested) break;
        final parser = SpecStreamParser();
        try {
          var roundPrompt = currentPrompt;
          final conversationContents = <Map<String, Object?>>[
            <String, Object?>{
              'role': 'user',
              'parts': GeminiRestClient.buildUserParts(
                currentPrompt,
                attachments,
              ),
            },
          ];

          for (var round = 0; round <= maxToolRounds; round++) {
            if (_stopRequested) break;
            final allowTools = round < maxToolRounds;
            parser.reset();
            var nativeCalls = const <VibeToolCall>[];
            var rawModelParts = const <Map<String, Object?>>[];

            final completer = Completer<void>();
            _activeStreamCompleter = completer;
            _activeStreamSubscription = _aiService
                .streamTurn(
                  stage: SpecForgeStage.reviewExport,
                  prompt: roundPrompt,
                  attachments: attachments,
                  speedMode: _speedMode,
                  tools: allowTools ? registry.declarations : const [],
                  conversationContents: conversationContents,
                  enforceJsonResponse: !allowTools,
                  systemInstructionOverride:
                      SpecStageAgent.globalQuestionSystemInstruction,
                  staticGuideOverride: SpecForgeToolRegistry.toolsGuide(),
                )
                .listen(
                  (event) {
                    if (_stopRequested) return;
                    if (event.functionCalls.isNotEmpty) {
                      nativeCalls = event.functionCalls;
                    }
                    if (event.rawModelParts.isNotEmpty) {
                      rawModelParts = event.rawModelParts;
                    }
                    if (event.deltaText.isNotEmpty) {
                      final snap = parser.addChunk(event.deltaText);
                      _streamingMessage = snap.message;
                      if (snap.message != null) {
                        _streamingStatus = 'Rédaction de la réponse…';
                      }
                      notifyListeners();
                    }
                  },
                  onError: (Object error, StackTrace stack) {
                    _activeStreamSubscription = null;
                    if (!completer.isCompleted) {
                      completer.completeError(error, stack);
                    }
                  },
                  onDone: () {
                    _activeStreamSubscription = null;
                    if (!completer.isCompleted) {
                      completer.complete();
                    }
                  },
                  cancelOnError: true,
                );

            await completer.future;
            _activeStreamSubscription = null;
            _activeStreamCompleter = null;

            if (_stopRequested) {
              final partialText = parser.snapshot().message?.trim() ?? '';
              final stoppedMsg = SpecChatMessage(
                id: 'gmsg_${shortid.generate()}',
                isUser: false,
                text: partialText.isNotEmpty
                    ? '$partialText\n\n[Réflexion IA interrompue par l’utilisateur.]'
                    : 'Réflexion IA interrompue par l’utilisateur.',
                toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              );
              _project = workingProject.copyWith(
                globalChatMessages: [
                  ...workingProject.globalChatMessages,
                  stoppedMsg,
                ],
              );
              await _persistProject(_project!);
              return;
            }

            List<VibeToolCall> callsToRun = nativeCalls;
            SpecAgentResponse? roundParsed;
            if (callsToRun.isEmpty && parser.rawText.trim().isNotEmpty) {
              roundParsed = SpecAgentResponse.parse(parser.rawText);
              if (roundParsed.uxPatch == null &&
                  roundParsed.qaPatch == null &&
                  roundParsed.costPatch == null &&
                  roundParsed.specPatch == null &&
                  roundParsed.toolCalls.isNotEmpty) {
                callsToRun = roundParsed.toolCalls;
              }
            }

            if (callsToRun.isNotEmpty && allowTools) {
              _streamingMessage = null;
              _streamingStatus =
                  'Outil : ${callsToRun.map((c) => c.name).join(', ')}…';
              notifyListeners();

              final results = await registry.executeAll(callsToRun);
              for (var i = 0; i < callsToRun.length; i++) {
                final call = callsToRun[i];
                final res = results[i];
                turnToolTraces.add(
                  VibeToolTrace(
                    name: call.name,
                    arguments: call.arguments,
                    isError: res.isError,
                    summary: SpecForgeToolRegistry.summarizeResult(call, res),
                  ),
                );
              }
              _streamingToolTraces = List<VibeToolTrace>.unmodifiable(
                turnToolTraces,
              );
              notifyListeners();

              conversationContents.add(<String, Object?>{
                'role': 'model',
                'parts': rawModelParts.isNotEmpty
                    ? rawModelParts
                    : <Map<String, Object?>>[
                        for (final c in callsToRun)
                          <String, Object?>{
                            'functionCall': c.toGeminiFunctionCall(),
                          },
                      ],
              });
              conversationContents.add(<String, Object?>{
                'role': 'user',
                'parts': <Map<String, Object?>>[
                  for (final r in results)
                    <String, Object?>{
                      'functionResponse': <String, Object?>{
                        'name': r.name,
                        'response': r.toGeminiFunctionResponsePayload(),
                      },
                    },
                ],
              });
              roundPrompt =
                  '$roundPrompt\n\nRÉSULTATS DES OUTILS :\n'
                  '${jsonEncode([for (final r in results) r.toJson()])}\n'
                  'Réponds maintenant au format {"message":"...","askUser":null,"specPatch":null}.';
              continue;
            }

            final response =
                roundParsed ?? SpecAgentResponse.parse(parser.rawText);
            final assistantMessage = SpecChatMessage(
              id: 'gmsg_${shortid.generate()}',
              isUser: false,
              text: response.message,
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            );
            _project = workingProject.copyWith(
              globalChatMessages: [
                ...workingProject.globalChatMessages,
                assistantMessage,
              ],
            );
            await _persistProject(_project!);
            return;
          }
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          saveError(
            '[SpecForge Global Q&A] Tentative ${attempt + 1} : $cause',
            stack,
          );
          debugPrint(
            '[SpecForge Global Q&A] Échec tentative ${attempt + 1} : $cause',
          );
          if (attempt == 0 &&
              (error is FormatException ||
                  error is ArgumentError ||
                  error is StateError)) {
            currentPrompt =
                '$currentPrompt\n\nErreur JSON précédente ($cause). Renvoie uniquement {"message":"...","askUser":null,"specPatch":null}.';
            continue;
          }
          final errMessage = SpecChatMessage(
            id: 'gmsg_${shortid.generate()}',
            isUser: false,
            text: 'Erreur lors de l’analyse du projet : $cause',
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
          );
          _project = workingProject.copyWith(
            globalChatMessages: [
              ...workingProject.globalChatMessages,
              errMessage,
            ],
          );
          _lastError = cause;
          await _persistProject(_project!);
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingGlobalQuestion = false;
      _sendingStage = null;
      _sendingUxStage = null;
      _sendingQaStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  /// Exécute immédiatement l'analyse de cohérence locale déterministe.
  List<SpecCoherenceIssue> runLocalCoherenceAudit() {
    final current = _project;
    if (current == null) return const <SpecCoherenceIssue>[];
    return SpecCoherenceAnalyzer.analyze(
      current,
      companyGlossary: _companyGlossary,
      modelPreferences: _modelPreferences,
    );
  }

  /// Exécute immédiatement l'analyse déterministe de cohérence Métier↔UX sur le projet actif.
  List<UxCoherenceIssue> runLocalUxCoherenceAudit() {
    final current = _project;
    if (current == null) return const <UxCoherenceIssue>[];
    return UxCoherenceAnalyzer.analyze(
      current,
      companyGlossary: _companyGlossary,
    );
  }

  /// Exécute immédiatement l'analyse déterministe de couverture 360° et cohérence Métier+UX↔QA sur le projet actif.
  List<QaCoherenceIssue> runLocalQaCoherenceAudit() {
    final current = _project;
    if (current == null) return const <QaCoherenceIssue>[];
    return QaCoherenceAnalyzer.analyze(
      current,
      companyGlossary: _companyGlossary,
    );
  }

  /// Navigue vers l'étape UX [targetStage], valide optionnellement l'étape UX courante
  /// et amorce l'agent spécialisé de [targetStage] si [autoKickoffIfEmpty] vaut `true`
  /// et que sa conversation est vide.
  Future<void> goToUxStage(
    UxForgeStage targetStage, {
    bool validateCurrent = false,
    bool autoKickoffIfEmpty = false,
  }) async {
    final current = _project;
    if (current == null) return;
    final movedUx = current.uxSpec.moveToStage(
      targetStage,
      validateCurrentStage: validateCurrent,
    );
    var effectiveProject = current;
    if (movedUx != current.uxSpec) {
      effectiveProject = current.copyWith(uxSpec: movedUx);
      _project = effectiveProject;
      notifyListeners();
      await _persistProject(effectiveProject);
    }
    if (autoKickoffIfEmpty &&
        !_isSending &&
        effectiveProject.uxSpec.stageStateFor(targetStage).messages.isEmpty) {
      await kickoffUxStageIfEmpty(targetStage);
    }
  }

  /// Déclenche le message initial de l'agent UX spécialisé si l'étape [stage] n'a aucun échange.
  Future<void> kickoffUxStageIfEmpty(UxForgeStage stage) async {
    final current = _project;
    if (current == null || _isSending) return;
    if (current.uxSpec.stageStateFor(stage).messages.isNotEmpty) return;
    final kickoffPrompt = UxPromptBuilder.buildStageKickoffPrompt(
      current,
      stage,
      modelPreferencesOverride: _modelPreferences,
    );
    await _runUxAgentTurn(
      stage: stage,
      userDisplayText: switch (stage) {
        UxForgeStage.userJourneys =>
          'Modéliser les parcours utilisateurs à partir des personas et du cahier des charges.',
        UxForgeStage.iaNavigation =>
          'Structurer l’architecture de navigation, les routes et le thème visuel.',
        UxForgeStage.screenBlueprints =>
          'Concevoir les schémas directeurs d’écrans, zones et interactions.',
        UxForgeStage.uxReviewExport =>
          'Lancer l’audit de cohérence Métier↔UX et préparer l’export SuperDesigner.',
      },
      promptInput: kickoffPrompt,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Envoie un message utilisateur libre (avec pièces jointes éventuelles) à l'agent de l'étape UX courante.
  Future<void> sendUxUserMessage(
    String text, {
    bool requestsMoreQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !requestsMoreQuestions && attachments.isEmpty) {
      return;
    }
    final stage = current.uxSpec.currentStage;
    final effectiveDisplay = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour approfondir cette étape UX.'
              : 'Analyse les pièces jointes et mets à jour la spécification UX correspondante.');
    await _runUxAgentTurn(
      stage: stage,
      userDisplayText: effectiveDisplay,
      promptInput: effectiveDisplay,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire `VibeAskUserCard` à l'agent de l'étape UX courante.
  Future<void> submitUxAskUserAnswers(
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.uxSpec.currentStage;
    final stageState = current.uxSpec.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final updatedMsg = targetMsg.copyWith(
      askUserAnswers: answers,
      askUserUsedDefaults: usedDefaults,
      askUserRequestedMore: askMore,
    );
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = updatedMsg;
    _project = current.copyWith(
      uxSpec: current.uxSpec.withStageState(
        stageState.copyWith(messages: updatedMessages),
      ),
    );
    notifyListeners();

    final formattedSummary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    final displaySummary = askMore
        ? '$formattedSummary\n(+ questions complémentaires demandées)'
        : formattedSummary;

    await _runUxAgentTurn(
      stage: stage,
      userDisplayText: displaySummary,
      promptInput: formattedSummary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
    );
  }

  /// Ignore un questionnaire UX en appliquant ses valeurs par défaut pour passer à la génération.
  Future<void> skipUxAskUser(String messageId) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.uxSpec.currentStage;
    final stageState = current.uxSpec.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final defaults = askUser.defaultAnswers();
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = targetMsg.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      );
    _project = current.copyWith(
      uxSpec: current.uxSpec.withStageState(
        stageState.copyWith(messages: updatedMessages),
      ),
    );
    notifyListeners();

    final formatted =
        'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}';
    await _runUxAgentTurn(
      stage: stage,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput: formatted,
      afterAskUserReply: true,
      forceFollowUpQuestions: false,
    );
  }

  /// Relance manuellement le dernier tour en erreur sur l'étape UX active avec contexte de correction.
  Future<void> retryLastFailedUxTurn() async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.uxSpec.currentStage;
    final messages = current.uxSpec.stageStateFor(stage).messages;
    String retryInput =
        'La tentative précédente a échoué. Corrige le format JSON et applique la mise à jour UX demandée.';
    List<VibeChatAttachment> lastAttachments = const <VibeChatAttachment>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.isUser) {
        retryInput = (msg.promptText ?? msg.text).trim();
        lastAttachments = msg.attachments;
        break;
      }
    }
    await _runUxAgentTurn(
      stage: stage,
      userDisplayText: 'Reprise de la génération UX suite à erreur…',
      promptInput:
          '$retryInput\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastAttachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Efface l'historique conversationnel de l'étape UX active (ou de [stage]) du wizard UX.
  Future<void> clearUxStageChat([UxForgeStage? stage]) async {
    final current = _project;
    if (current == null || _isSending) return;
    final targetStage = stage ?? current.uxSpec.currentStage;
    final stageState = current.uxSpec.stageStateFor(targetStage);
    if (stageState.messages.isEmpty && !stageState.readyToAdvance) return;
    final cleared = current.copyWith(
      uxSpec: current.uxSpec.withStageState(
        stageState.copyWith(
          messages: const <SpecChatMessage>[],
          readyToAdvance: false,
        ),
      ),
    );
    _project = cleared;
    notifyListeners();
    await _persistProject(cleared);
  }

  Future<void> _runUxAgentTurn({
    required UxForgeStage stage,
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    required bool forceFollowUpQuestions,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final initialProject = _project;
    if (initialProject == null) return;

    final userMessage = SpecChatMessage(
      id: 'uxmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );

    final initialStageState = initialProject.uxSpec.stageStateFor(stage);
    final withUserMsg = initialProject.copyWith(
      uxSpec: initialProject.uxSpec.withStageState(
        initialStageState.copyWith(
          status: initialStageState.status == SpecStageStatus.notStarted
              ? SpecStageStatus.inProgress
              : initialStageState.status,
          messages: [...initialStageState.messages, userMessage],
        ),
      ),
    );
    _project = withUserMsg;
    _isSending = true;
    _stopRequested = false;
    _sendingUxStage = stage;
    _sendingQaStage = null;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Analyse par ${stage.agentTitle}…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    final uxAgent = UxStageAgent.forStage(stage);
    final staticGuide =
        '${uxAgent.patchSchemaGuide}\n\n---\n\n'
        '${SpecForgeToolRegistry.toolsGuide(toolNames: SpecForgeToolRegistry.uxStageToolNames)}';

    var workingProject = withUserMsg;
    final baseSnapshotBeforeTurn = initialProject;
    var currentPrompt = UxPromptBuilder.buildTurnPrompt(
      project: initialProject,
      stage: stage,
      userInput: promptInput,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterAskUserReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
      companyGlossary: _companyGlossary,
      modelPreferencesOverride: _modelPreferences,
      focusedJourneyId: _focusedJourneyId,
      focusedRouteId: _focusedRouteId,
      focusedScreenId: _focusedScreenId,
      focusedZone: _focusedScreenZone,
      toolNames: SpecForgeToolRegistry.uxStageToolNames,
    );

    final priorCauses = <String>[];
    final checkpointSummaries = <String>[];
    final turnToolTraces = <VibeToolTrace>[];
    var recovered = false;

    final registry = _buildProjectToolRegistry(
      readWorkingProject: () => workingProject,
      writeWorkingProject: (next) => workingProject = next,
      toolNames: SpecForgeToolRegistry.uxStageToolNames,
    );

    try {
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        debugPrint(
          '[SpecForge UX IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
          '(${stage.agentTitle}) — prompt ${currentPrompt.length} car., '
          'pièces jointes: ${attachments.length}…',
        );
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }

        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.reviewExport,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour de la spécification UX…',
            writingStatus: 'Rédaction de la réponse…',
            systemInstructionOverride: uxAgent.systemInstruction,
            staticGuideOverride: staticGuide,
            allowedToolNames: SpecForgeToolRegistry.uxStageToolNames,
          );
          if (response == null) {
            final partialText = parser.snapshot().message?.trim() ?? '';
            if (checkpointSummaries.isNotEmpty) {
              _pushUndo(baseSnapshotBeforeTurn);
            }
            final stoppedMessage = SpecChatMessage(
              id: 'uxmsg_${shortid.generate()}',
              isUser: false,
              text: partialText.isNotEmpty
                  ? '$partialText\n\n[Réflexion IA interrompue par l’utilisateur.]'
                  : 'Réflexion IA interrompue par l’utilisateur.',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              appliedPatchSummary: checkpointSummaries.join(', '),
            );
            final currentStageState = workingProject.uxSpec.stageStateFor(
              stage,
            );
            _project = workingProject.copyWith(
              uxSpec: workingProject.uxSpec.withStageState(
                currentStageState.copyWith(
                  messages: [...currentStageState.messages, stoppedMessage],
                ),
              ),
            );
            await _persistProject(_project!);
            recovered = true;
            break;
          }
          parsedResponse = response;

          var updatedProject = workingProject;
          var patchSummary = '';
          final hasUxPatch =
              response.uxPatch != null && response.uxPatch!.isNotEmpty;
          final hasSpecPatch =
              response.specPatch != null && response.specPatch!.isNotEmpty;

          if (hasUxPatch || hasSpecPatch) {
            final applied = UxPatchApplier.apply(
              workingProject,
              uxPatch: response.uxPatch,
              specPatch: response.specPatch,
            );
            final didMutate = applied.project != workingProject;
            if (didMutate || checkpointSummaries.isNotEmpty) {
              _pushUndo(baseSnapshotBeforeTurn);
            }
            updatedProject = applied.project;
            patchSummary = [
              ...checkpointSummaries,
              if (didMutate && applied.summary.isNotEmpty) applied.summary,
            ].join(', ');
          } else if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
            patchSummary = checkpointSummaries.join(', ');
          }

          final assistantMessage = SpecChatMessage(
            id: 'uxmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
            stageReadyToAdvance: response.stageReadyToAdvance,
          );

          final currentStageState = updatedProject.uxSpec.stageStateFor(stage);
          updatedProject = updatedProject.copyWith(
            uxSpec: updatedProject.uxSpec.withStageState(
              currentStageState.copyWith(
                messages: [...currentStageState.messages, assistantMessage],
                stageSummary: response.stageSummary.isNotEmpty
                    ? response.stageSummary
                    : currentStageState.stageSummary,
                readyToAdvance:
                    response.stageReadyToAdvance ||
                    currentStageState.readyToAdvance,
              ),
            ),
          );

          _project = updatedProject;
          await _persistProject(updatedProject);
          recovered = true;
          break;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );

          debugPrint(
            '[SpecForge UX IA] Échec tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.agentTitle}) : $cause',
          );
          saveError(
            '[SpecForge UX IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.name}) : $cause',
            stack,
          );

          final salvage = UxPatchApplier.salvageFailedAttempt(
            workingProject: workingProject,
            rawResponse: parser.rawText,
            decodedUxPatch: parsedResponse?.uxPatch,
            decodedSpecPatch: parsedResponse?.specPatch,
          );
          if (salvage.hasCheckpoint) {
            workingProject = salvage.checkpointProject;
            if (salvage.appliedSummary.isNotEmpty) {
              checkpointSummaries.add(salvage.appliedSummary);
            }
            _project = workingProject;
            notifyListeners();
          }

          if (attempt < maxRecoveryAttempts - 1 && isValidationError) {
            debugPrint(
              salvage.hasCheckpoint
                  ? '[SpecForge UX IA] Checkpoint partiel conservé (${salvage.appliedSummary}), relance delta…'
                  : '[SpecForge UX IA] Aucun checkpoint partiel, relance corrective…',
            );

            final refreshedTurnPrompt = UxPromptBuilder.buildTurnPrompt(
              project: workingProject,
              stage: stage,
              userInput: promptInput,
              questioningLevel: _questioningLevel,
              afterAskUserReply: afterAskUserReply || salvage.hasCheckpoint,
              forceFollowUpQuestions: forceFollowUpQuestions,
              companyGlossary: _companyGlossary,
              modelPreferencesOverride: _modelPreferences,
              focusedJourneyId: _focusedJourneyId,
              focusedRouteId: _focusedRouteId,
              focusedScreenId: _focusedScreenId,
              focusedZone: _focusedScreenZone,
              toolNames: SpecForgeToolRegistry.uxStageToolNames,
            );
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: refreshedTurnPrompt,
              priorCauses: priorCauses,
              salvage: salvage,
              rawFailedResponse: parser.rawText,
            );
            continue;
          }

          if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
          }

          final failedDetail = priorCauses.length > 1
              ? priorCauses.join('\n')
              : cause;
          final errMessage = SpecChatMessage(
            id: 'uxmsg_${shortid.generate()}',
            isUser: false,
            text:
                'Erreur lors de l’appel à ${stage.agentTitle} '
                '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n$failedDetail',
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            appliedPatchSummary: checkpointSummaries.join(', '),
            failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
          );
          final currentStageState = workingProject.uxSpec.stageStateFor(stage);
          _project = workingProject.copyWith(
            uxSpec: workingProject.uxSpec.withStageState(
              currentStageState.copyWith(
                messages: [...currentStageState.messages, errMessage],
              ),
            ),
          );
          _lastError = cause;
          await _persistProject(_project!);
          break;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }

      if (!recovered && _lastError != null) {
        debugPrint(
          '[SpecForge UX IA] Fin du tour en erreur (${stage.agentTitle}) : $_lastError',
        );
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingUxStage = null;
      _sendingQaStage = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  /// Navigue vers l'étape QA [targetStage], valide optionnellement l'étape QA courante
  /// et amorce l'agent spécialisé de [targetStage] si [autoKickoffIfEmpty] vaut `true`
  /// et que sa conversation est vide.
  Future<void> goToQaStage(
    QaForgeStage targetStage, {
    bool validateCurrent = false,
    bool autoKickoffIfEmpty = false,
  }) async {
    final current = _project;
    if (current == null) return;
    final movedQa = current.qaSpec.moveToStage(
      targetStage,
      validateCurrentStage: validateCurrent,
    );
    var effectiveProject = current;
    if (movedQa != current.qaSpec) {
      effectiveProject = current.copyWith(qaSpec: movedQa);
      await updateProject(effectiveProject, recordUndo: false);
    }
    if (autoKickoffIfEmpty &&
        !_isSending &&
        effectiveProject.qaSpec.stageStateFor(targetStage).messages.isEmpty) {
      await kickoffQaStageIfEmpty(targetStage);
    }
  }

  /// Déclenche le message initial de l'agent QA spécialisé si l'étape [stage] n'a aucun échange.
  Future<void> kickoffQaStageIfEmpty(QaForgeStage stage) async {
    final current = _project;
    if (current == null || _isSending) return;
    if (current.qaSpec.stageStateFor(stage).messages.isNotEmpty) return;
    final kickoffPrompt = QaPromptBuilder.buildStageKickoffPrompt(
      current,
      stage,
      modelPreferencesOverride: _modelPreferences,
    );
    await _runQaAgentTurn(
      stage: stage,
      userDisplayText: switch (stage) {
        QaForgeStage.testFixtures =>
          'Concevoir les jeux d’essais déterministes et cas aux bornes à partir du modèle métier.',
        QaForgeStage.gherkinFeatures =>
          'Structurer les fonctionnalités et scénarios Gherkin BDD exécutables (.feature).',
        QaForgeStage.tddSuites =>
          'Formaliser les suites unitaires TDD Arrange / Act / Assert en progression Red → Green → Refactor.',
        QaForgeStage.qaReviewExport =>
          'Lancer l’audit de couverture 360° Métier+UX↔QA et préparer l’export BDD/TDD.',
      },
      promptInput: kickoffPrompt,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Envoie un message utilisateur libre (avec pièces jointes éventuelles) à l'agent de l'étape QA courante.
  Future<void> sendQaUserMessage(
    String text, {
    bool requestsMoreQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !requestsMoreQuestions && attachments.isEmpty) {
      return;
    }
    final stage = current.qaSpec.currentStage;
    final effectiveDisplay = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour approfondir cette étape QA.'
              : 'Analyse les pièces jointes et mets à jour les spécifications BDD / TDD correspondantes.');
    await _runQaAgentTurn(
      stage: stage,
      userDisplayText: effectiveDisplay,
      promptInput: effectiveDisplay,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire `VibeAskUserCard` à l'agent de l'étape QA courante.
  Future<void> submitQaAskUserAnswers(
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.qaSpec.currentStage;
    final stageState = current.qaSpec.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final updatedMsg = targetMsg.copyWith(
      askUserAnswers: answers,
      askUserUsedDefaults: usedDefaults,
      askUserRequestedMore: askMore,
    );
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = updatedMsg;
    _project = current.copyWith(
      qaSpec: current.qaSpec.withStageState(
        stageState.copyWith(messages: updatedMessages),
      ),
    );
    notifyListeners();

    final formattedSummary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    final displaySummary = askMore
        ? '$formattedSummary\n(+ questions complémentaires demandées)'
        : formattedSummary;

    await _runQaAgentTurn(
      stage: stage,
      userDisplayText: displaySummary,
      promptInput: formattedSummary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
    );
  }

  /// Ignore un questionnaire QA en appliquant ses valeurs par défaut pour passer à la génération.
  Future<void> skipQaAskUser(String messageId) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.qaSpec.currentStage;
    final stageState = current.qaSpec.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final defaults = askUser.defaultAnswers();
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = targetMsg.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      );
    _project = current.copyWith(
      qaSpec: current.qaSpec.withStageState(
        stageState.copyWith(messages: updatedMessages),
      ),
    );
    notifyListeners();

    final formatted =
        'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}';
    await _runQaAgentTurn(
      stage: stage,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput: formatted,
      afterAskUserReply: true,
      forceFollowUpQuestions: false,
    );
  }

  /// Relance manuellement le dernier tour en erreur sur l'étape QA active avec contexte de correction.
  Future<void> retryLastFailedQaTurn() async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.qaSpec.currentStage;
    final messages = current.qaSpec.stageStateFor(stage).messages;
    String retryInput =
        'La tentative précédente a échoué. Corrige le format JSON et applique la mise à jour QA demandée.';
    List<VibeChatAttachment> lastAttachments = const <VibeChatAttachment>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.isUser) {
        retryInput = (msg.promptText ?? msg.text).trim();
        lastAttachments = msg.attachments;
        break;
      }
    }
    await _runQaAgentTurn(
      stage: stage,
      userDisplayText: 'Reprise de la génération QA suite à erreur…',
      promptInput:
          '$retryInput\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastAttachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Efface l'historique conversationnel de l'étape QA active (ou de [stage]) du wizard QA.
  Future<void> clearQaStageChat([QaForgeStage? stage]) async {
    final current = _project;
    if (current == null || _isSending) return;
    final targetStage = stage ?? current.qaSpec.currentStage;
    final stageState = current.qaSpec.stageStateFor(targetStage);
    if (stageState.messages.isEmpty && !stageState.readyToAdvance) return;
    final cleared = current.copyWith(
      qaSpec: current.qaSpec.withStageState(
        stageState.copyWith(
          messages: const <SpecChatMessage>[],
          readyToAdvance: false,
        ),
      ),
    );
    _project = cleared;
    notifyListeners();
    await _persistProject(cleared);
  }

  Future<void> _runQaAgentTurn({
    required QaForgeStage stage,
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    required bool forceFollowUpQuestions,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final initialProject = _project;
    if (initialProject == null) return;

    final userMessage = SpecChatMessage(
      id: 'qamsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );

    final initialStageState = initialProject.qaSpec.stageStateFor(stage);
    final withUserMsg = initialProject.copyWith(
      qaSpec: initialProject.qaSpec.withStageState(
        initialStageState.copyWith(
          status: initialStageState.status == SpecStageStatus.notStarted
              ? SpecStageStatus.inProgress
              : initialStageState.status,
          messages: [...initialStageState.messages, userMessage],
        ),
      ),
    );
    _project = withUserMsg;
    _isSending = true;
    _stopRequested = false;
    _sendingQaStage = stage;
    _sendingUxStage = null;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Analyse par ${stage.agentTitle}…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    final qaAgent = QaStageAgent.forStage(stage);
    final staticGuide =
        '${qaAgent.patchSchemaGuide}\n\n---\n\n'
        '${SpecForgeToolRegistry.toolsGuide(toolNames: SpecForgeToolRegistry.qaStageToolNames)}';

    var workingProject = withUserMsg;
    final baseSnapshotBeforeTurn = initialProject;
    var currentPrompt = QaPromptBuilder.buildTurnPrompt(
      project: initialProject,
      stage: stage,
      userInput: promptInput,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterAskUserReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
      companyGlossary: _companyGlossary,
      modelPreferencesOverride: _modelPreferences,
      focusedFixtureId: _focusedFixtureId,
      focusedFeatureId: _focusedFeatureId,
      focusedScenarioId: _focusedScenarioId,
      focusedTddSuiteId: _focusedTddSuiteId,
      toolNames: SpecForgeToolRegistry.qaStageToolNames,
    );

    final priorCauses = <String>[];
    final checkpointSummaries = <String>[];
    final turnToolTraces = <VibeToolTrace>[];
    var recovered = false;

    final registry = _buildProjectToolRegistry(
      readWorkingProject: () => workingProject,
      writeWorkingProject: (next) => workingProject = next,
      toolNames: SpecForgeToolRegistry.qaStageToolNames,
    );

    try {
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        debugPrint(
          '[SpecForge QA IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
          '(${stage.agentTitle}) — prompt ${currentPrompt.length} car., '
          'pièces jointes: ${attachments.length}…',
        );
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }

        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.reviewExport,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour des tests BDD / TDD…',
            writingStatus: 'Rédaction de la réponse…',
            systemInstructionOverride: qaAgent.systemInstruction,
            staticGuideOverride: staticGuide,
            allowedToolNames: SpecForgeToolRegistry.qaStageToolNames,
          );
          if (response == null) {
            final partialText = parser.snapshot().message?.trim() ?? '';
            if (checkpointSummaries.isNotEmpty) {
              _pushUndo(baseSnapshotBeforeTurn);
            }
            final stoppedMessage = SpecChatMessage(
              id: 'qamsg_${shortid.generate()}',
              isUser: false,
              text: partialText.isNotEmpty
                  ? '$partialText\n\n[Réflexion IA interrompue par l’utilisateur.]'
                  : 'Réflexion IA interrompue par l’utilisateur.',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              appliedPatchSummary: checkpointSummaries.join(', '),
            );
            final currentStageState = workingProject.qaSpec.stageStateFor(
              stage,
            );
            _project = workingProject.copyWith(
              qaSpec: workingProject.qaSpec.withStageState(
                currentStageState.copyWith(
                  messages: [...currentStageState.messages, stoppedMessage],
                ),
              ),
            );
            await _persistProject(_project!);
            recovered = true;
            break;
          }
          parsedResponse = response;

          var updatedProject = workingProject;
          var patchSummary = '';
          final hasQaPatch =
              response.qaPatch != null && response.qaPatch!.isNotEmpty;
          final hasSpecPatch =
              response.specPatch != null && response.specPatch!.isNotEmpty;

          if (hasQaPatch || hasSpecPatch) {
            final applied = QaPatchApplier.apply(
              workingProject,
              qaPatch: response.qaPatch,
              specPatch: response.specPatch,
            );
            final didMutate = applied.project != workingProject;
            if (didMutate || checkpointSummaries.isNotEmpty) {
              _pushUndo(baseSnapshotBeforeTurn);
            }
            updatedProject = applied.project;
            patchSummary = [
              ...checkpointSummaries,
              if (didMutate && applied.summary.isNotEmpty) applied.summary,
            ].join(', ');
          } else if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
            patchSummary = checkpointSummaries.join(', ');
          }

          final assistantMessage = SpecChatMessage(
            id: 'qamsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
            stageReadyToAdvance: response.stageReadyToAdvance,
          );

          final currentStageState = updatedProject.qaSpec.stageStateFor(stage);
          updatedProject = updatedProject.copyWith(
            qaSpec: updatedProject.qaSpec.withStageState(
              currentStageState.copyWith(
                messages: [...currentStageState.messages, assistantMessage],
                stageSummary: response.stageSummary.isNotEmpty
                    ? response.stageSummary
                    : currentStageState.stageSummary,
                readyToAdvance:
                    response.stageReadyToAdvance ||
                    currentStageState.readyToAdvance,
              ),
            ),
          );

          _project = updatedProject;
          await _persistProject(updatedProject);
          recovered = true;
          break;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );

          debugPrint(
            '[SpecForge QA IA] Échec tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.agentTitle}) : $cause',
          );
          saveError(
            '[SpecForge QA IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.name}) : $cause',
            stack,
          );

          final salvage = QaPatchApplier.salvageFailedAttempt(
            workingProject: workingProject,
            rawResponse: parser.rawText,
            decodedQaPatch: parsedResponse?.qaPatch,
            decodedSpecPatch: parsedResponse?.specPatch,
          );
          if (salvage.hasCheckpoint) {
            workingProject = salvage.checkpointProject;
            if (salvage.appliedSummary.isNotEmpty) {
              checkpointSummaries.add(salvage.appliedSummary);
            }
            _project = workingProject;
            notifyListeners();
          }

          if (attempt < maxRecoveryAttempts - 1 && isValidationError) {
            debugPrint(
              salvage.hasCheckpoint
                  ? '[SpecForge QA IA] Checkpoint partiel conservé (${salvage.appliedSummary}), relance delta…'
                  : '[SpecForge QA IA] Aucun checkpoint partiel, relance corrective…',
            );

            final refreshedTurnPrompt = QaPromptBuilder.buildTurnPrompt(
              project: workingProject,
              stage: stage,
              userInput: promptInput,
              questioningLevel: _questioningLevel,
              afterAskUserReply: afterAskUserReply || salvage.hasCheckpoint,
              forceFollowUpQuestions: forceFollowUpQuestions,
              companyGlossary: _companyGlossary,
              modelPreferencesOverride: _modelPreferences,
              focusedFixtureId: _focusedFixtureId,
              focusedFeatureId: _focusedFeatureId,
              focusedScenarioId: _focusedScenarioId,
              focusedTddSuiteId: _focusedTddSuiteId,
              toolNames: SpecForgeToolRegistry.qaStageToolNames,
            );
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: refreshedTurnPrompt,
              priorCauses: priorCauses,
              salvage: salvage,
              rawFailedResponse: parser.rawText,
            );
            continue;
          }

          if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
          }

          final failedDetail = priorCauses.length > 1
              ? priorCauses.join('\n')
              : cause;
          final errMessage = SpecChatMessage(
            id: 'qamsg_${shortid.generate()}',
            isUser: false,
            text:
                'Erreur lors de l’appel à ${stage.agentTitle} '
                '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n$failedDetail',
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            appliedPatchSummary: checkpointSummaries.join(', '),
            failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
          );
          final currentStageState = workingProject.qaSpec.stageStateFor(stage);
          _project = workingProject.copyWith(
            qaSpec: workingProject.qaSpec.withStageState(
              currentStageState.copyWith(
                messages: [...currentStageState.messages, errMessage],
              ),
            ),
          );
          _lastError = cause;
          await _persistProject(_project!);
          break;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }

      if (!recovered && _lastError != null) {
        debugPrint(
          '[SpecForge QA IA] Fin du tour en erreur (${stage.agentTitle}) : $_lastError',
        );
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingQaStage = null;
      _sendingCostStage = null;
      _sendingUxStage = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  /// Navigue vers l'étape Coûts [targetStage], valide optionnellement l'étape courante
  /// et amorce l'agent spécialisé de [targetStage] si [autoKickoffIfEmpty] vaut `true`.
  Future<void> goToCostStage(
    CostForgeStage targetStage, {
    bool validateCurrent = false,
    bool autoKickoffIfEmpty = false,
  }) async {
    final current = _project;
    if (current == null) return;
    final movedCost = current.costSpec.moveToStage(
      targetStage,
      validateCurrentStage: validateCurrent,
    );
    var effectiveProject = current;
    if (movedCost != current.costSpec) {
      effectiveProject = current.copyWith(costSpec: movedCost);
      await updateProject(effectiveProject, recordUndo: false);
    }
    if (autoKickoffIfEmpty &&
        !_isSending &&
        effectiveProject.costSpec.stageStateFor(targetStage).messages.isEmpty) {
      await kickoffCostStageIfEmpty(targetStage);
    }
  }

  /// Déclenche le message initial de l'agent FinOps spécialisé si l'étape [stage] n'a aucun échange.
  Future<void> kickoffCostStageIfEmpty(CostForgeStage stage) async {
    final current = _project;
    if (current == null || _isSending) return;
    if (current.costSpec.stageStateFor(stage).messages.isNotEmpty) return;
    final kickoffPrompt = CostPromptBuilder.buildStageKickoffPrompt(
      current,
      stage,
      enterpriseRateCard: _enterpriseRateCard,
      modelPreferencesOverride: _modelPreferences,
    );
    await _runCostAgentTurn(
      stage: stage,
      userDisplayText: switch (stage) {
        CostForgeStage.rateCardAssumptions =>
          'Calibrer les hypothèses, la grille TJM, le mode de réalisation et les gains IA du projet.',
        CostForgeStage.buildWbs =>
          'Chiffrer la structure de découpage Build (WBS) en jours/homme PERT et par lot MoSCoW.',
        CostForgeStage.runOpex =>
          'Dimensionner les coûts récurrents Run, Cloud, APIs/LLM, licences et TMA/MCO.',
        CostForgeStage.tcoReviewExport =>
          'Auditer les risques financiers (EMV), la cohérence du chiffrage et la synthèse TCO à 1, 3 et 5 ans.',
      },
      promptInput: kickoffPrompt,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Envoie un message utilisateur libre (avec pièces jointes éventuelles) à l'agent de l'étape Coûts courante.
  Future<void> sendCostUserMessage(
    String text, {
    bool requestsMoreQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !requestsMoreQuestions && attachments.isEmpty) {
      return;
    }
    final stage = current.costSpec.currentStage;
    final effectiveDisplay = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour affiner cette étape de chiffrage IT.'
              : 'Analyse les pièces jointes et mets à jour le chiffrage IT correspondant.');
    await _runCostAgentTurn(
      stage: stage,
      userDisplayText: effectiveDisplay,
      promptInput: effectiveDisplay,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire `VibeAskUserCard` à l'agent de l'étape Coûts courante.
  Future<void> submitCostAskUserAnswers(
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.costSpec.currentStage;
    final stageState = current.costSpec.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final updatedMsg = targetMsg.copyWith(
      askUserAnswers: answers,
      askUserUsedDefaults: usedDefaults,
      askUserRequestedMore: askMore,
    );
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = updatedMsg;
    _project = current.copyWith(
      costSpec: current.costSpec.withStageState(
        stageState.copyWith(messages: updatedMessages),
      ),
    );
    notifyListeners();

    final formattedSummary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    final displaySummary = askMore
        ? '$formattedSummary\n(+ questions complémentaires demandées)'
        : formattedSummary;

    await _runCostAgentTurn(
      stage: stage,
      userDisplayText: displaySummary,
      promptInput: formattedSummary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
    );
  }

  /// Ignore un questionnaire Coûts en appliquant ses valeurs par défaut pour passer à la génération.
  Future<void> skipCostAskUser(String messageId) async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.costSpec.currentStage;
    final stageState = current.costSpec.stageStateFor(stage);
    final idx = stageState.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = stageState.messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final defaults = askUser.defaultAnswers();
    final updatedMessages = List<SpecChatMessage>.from(stageState.messages)
      ..[idx] = targetMsg.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      );
    _project = current.copyWith(
      costSpec: current.costSpec.withStageState(
        stageState.copyWith(messages: updatedMessages),
      ),
    );
    notifyListeners();

    final formatted =
        'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}';
    await _runCostAgentTurn(
      stage: stage,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput: formatted,
      afterAskUserReply: true,
      forceFollowUpQuestions: false,
    );
  }

  /// Relance manuellement le dernier tour en erreur sur l'étape Coûts active avec contexte de correction.
  Future<void> retryLastFailedCostTurn() async {
    final current = _project;
    if (current == null || _isSending) return;
    final stage = current.costSpec.currentStage;
    final messages = current.costSpec.stageStateFor(stage).messages;
    String retryInput =
        'La tentative précédente a échoué. Corrige le format JSON et applique la mise à jour du chiffrage IT demandée.';
    List<VibeChatAttachment> lastAttachments = const <VibeChatAttachment>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.isUser) {
        retryInput = (msg.promptText ?? msg.text).trim();
        lastAttachments = msg.attachments;
        break;
      }
    }
    await _runCostAgentTurn(
      stage: stage,
      userDisplayText: 'Reprise de la génération FinOps suite à erreur…',
      promptInput:
          '$retryInput\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastAttachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: false,
    );
  }

  /// Efface l'historique conversationnel de l'étape Coûts active (ou de [stage]) du wizard Coûts.
  Future<void> clearCostStageChat([CostForgeStage? stage]) async {
    final current = _project;
    if (current == null || _isSending) return;
    final targetStage = stage ?? current.costSpec.currentStage;
    final stageState = current.costSpec.stageStateFor(targetStage);
    if (stageState.messages.isEmpty && !stageState.readyToAdvance) return;
    final cleared = current.copyWith(
      costSpec: current.costSpec.withStageState(
        stageState.copyWith(
          messages: const <SpecChatMessage>[],
          readyToAdvance: false,
        ),
      ),
    );
    _project = cleared;
    notifyListeners();
    await _persistProject(cleared);
  }

  Future<void> _runCostAgentTurn({
    required CostForgeStage stage,
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    required bool forceFollowUpQuestions,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final initialProject = _project;
    if (initialProject == null) return;

    final userMessage = SpecChatMessage(
      id: 'costmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );

    final initialStageState = initialProject.costSpec.stageStateFor(stage);
    final withUserMsg = initialProject.copyWith(
      costSpec: initialProject.costSpec.withStageState(
        initialStageState.copyWith(
          status: initialStageState.status == SpecStageStatus.notStarted
              ? SpecStageStatus.inProgress
              : initialStageState.status,
          messages: [...initialStageState.messages, userMessage],
        ),
      ),
    );
    _project = withUserMsg;
    _isSending = true;
    _stopRequested = false;
    _sendingCostStage = stage;
    _sendingQaStage = null;
    _sendingUxStage = null;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Analyse par ${stage.agentTitle}…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    final costAgent = CostStageAgent.forStage(stage);
    final staticGuide = CostPromptBuilder.buildStaticGuide(stage);

    var workingProject = withUserMsg;
    final baseSnapshotBeforeTurn = initialProject;
    var currentPrompt = CostPromptBuilder.buildTurnPrompt(
      project: initialProject,
      stage: stage,
      userInput: promptInput,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterAskUserReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
      enterpriseRateCard: _enterpriseRateCard,
      companyGlossary: _companyGlossary,
      modelPreferencesOverride: _modelPreferences,
      focusedProfileId: _focusedCostProfileId,
      focusedWbsItemId: _focusedWbsItemId,
      focusedRunItemId: _focusedRunItemId,
      focusedRiskItemId: _focusedRiskItemId,
      toolNames: SpecForgeToolRegistry.costStageToolNames,
    );

    final priorCauses = <String>[];
    final checkpointSummaries = <String>[];
    final turnToolTraces = <VibeToolTrace>[];
    var recovered = false;

    final registry = _buildProjectToolRegistry(
      readWorkingProject: () => workingProject,
      writeWorkingProject: (next) => workingProject = next,
      toolNames: SpecForgeToolRegistry.costStageToolNames,
    );

    try {
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        debugPrint(
          '[SpecForge Cost IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
          '(${stage.agentTitle}) — prompt ${currentPrompt.length} car., '
          'pièces jointes: ${attachments.length}…',
        );
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }

        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.reviewExport,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour du chiffrage FinOps…',
            writingStatus: 'Rédaction de la réponse…',
            systemInstructionOverride: costAgent.systemInstruction,
            staticGuideOverride: staticGuide,
            allowedToolNames: SpecForgeToolRegistry.costStageToolNames,
          );
          if (response == null) {
            final partialText = parser.snapshot().message?.trim() ?? '';
            if (checkpointSummaries.isNotEmpty) {
              _pushUndo(baseSnapshotBeforeTurn);
            }
            final stoppedMessage = SpecChatMessage(
              id: 'costmsg_${shortid.generate()}',
              isUser: false,
              text: partialText.isNotEmpty
                  ? '$partialText\n\n[Réflexion IA interrompue par l’utilisateur.]'
                  : 'Réflexion IA interrompue par l’utilisateur.',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              appliedPatchSummary: checkpointSummaries.join(', '),
            );
            final currentStageState = workingProject.costSpec.stageStateFor(
              stage,
            );
            _project = workingProject.copyWith(
              costSpec: workingProject.costSpec.withStageState(
                currentStageState.copyWith(
                  messages: [...currentStageState.messages, stoppedMessage],
                ),
              ),
            );
            await _persistProject(_project!);
            recovered = true;
            break;
          }
          parsedResponse = response;

          var updatedProject = workingProject;
          var patchSummary = '';
          final hasCostPatch =
              response.costPatch != null && response.costPatch!.isNotEmpty;
          final hasSpecPatch =
              response.specPatch != null && response.specPatch!.isNotEmpty;

          if (hasCostPatch || hasSpecPatch) {
            final applied = CostPatchApplier.apply(
              workingProject,
              costPatch: response.costPatch,
              specPatch: response.specPatch,
            );
            final didMutate = applied.project != workingProject;
            if (didMutate || checkpointSummaries.isNotEmpty) {
              _pushUndo(baseSnapshotBeforeTurn);
            }
            updatedProject = applied.project;
            patchSummary = [
              ...checkpointSummaries,
              if (didMutate && applied.summary.isNotEmpty) applied.summary,
            ].join(', ');
          } else if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
            patchSummary = checkpointSummaries.join(', ');
          }

          final assistantMessage = SpecChatMessage(
            id: 'costmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
            stageReadyToAdvance: response.stageReadyToAdvance,
          );

          final currentStageState = updatedProject.costSpec.stageStateFor(
            stage,
          );
          updatedProject = updatedProject.copyWith(
            costSpec: updatedProject.costSpec.withStageState(
              currentStageState.copyWith(
                messages: [...currentStageState.messages, assistantMessage],
                stageSummary: response.stageSummary.isNotEmpty
                    ? response.stageSummary
                    : currentStageState.stageSummary,
                readyToAdvance:
                    response.stageReadyToAdvance ||
                    currentStageState.readyToAdvance,
              ),
            ),
          );

          _project = updatedProject;
          await _persistProject(updatedProject);
          recovered = true;
          break;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );

          debugPrint(
            '[SpecForge Cost IA] Échec tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.agentTitle}) : $cause',
          );
          saveError(
            '[SpecForge Cost IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.name}) : $cause',
            stack,
          );

          final salvage = CostPatchApplier.salvageFailedAttempt(
            workingProject: workingProject,
            rawResponse: parser.rawText,
            decodedCostPatch: parsedResponse?.costPatch,
            decodedSpecPatch: parsedResponse?.specPatch,
          );
          if (salvage.hasCheckpoint) {
            workingProject = salvage.checkpointProject;
            if (salvage.appliedSummary.isNotEmpty) {
              checkpointSummaries.add(salvage.appliedSummary);
            }
            _project = workingProject;
            notifyListeners();
          }

          if (attempt < maxRecoveryAttempts - 1 && isValidationError) {
            final refreshedTurnPrompt = CostPromptBuilder.buildTurnPrompt(
              project: workingProject,
              stage: stage,
              userInput: promptInput,
              questioningLevel: _questioningLevel,
              afterAskUserReply: afterAskUserReply || salvage.hasCheckpoint,
              forceFollowUpQuestions: forceFollowUpQuestions,
              enterpriseRateCard: _enterpriseRateCard,
              companyGlossary: _companyGlossary,
              modelPreferencesOverride: _modelPreferences,
              focusedProfileId: _focusedCostProfileId,
              focusedWbsItemId: _focusedWbsItemId,
              focusedRunItemId: _focusedRunItemId,
              focusedRiskItemId: _focusedRiskItemId,
              toolNames: SpecForgeToolRegistry.costStageToolNames,
            );
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: refreshedTurnPrompt,
              priorCauses: priorCauses,
              salvage: salvage,
              rawFailedResponse: parser.rawText,
            );
            continue;
          }

          if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
          }

          final failedDetail = priorCauses.length > 1
              ? priorCauses.join('\n')
              : cause;
          final errMessage = SpecChatMessage(
            id: 'costmsg_${shortid.generate()}',
            isUser: false,
            text:
                'Erreur lors de l’appel à ${stage.agentTitle} '
                '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n$failedDetail',
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            appliedPatchSummary: checkpointSummaries.join(', '),
            failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
          );
          final currentStageState = workingProject.costSpec.stageStateFor(
            stage,
          );
          _project = workingProject.copyWith(
            costSpec: workingProject.costSpec.withStageState(
              currentStageState.copyWith(
                messages: [...currentStageState.messages, errMessage],
              ),
            ),
          );
          _lastError = cause;
          await _persistProject(_project!);
          break;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }

      if (!recovered && _lastError != null) {
        debugPrint(
          '[SpecForge Cost IA] Fin du tour en erreur (${stage.agentTitle}) : $_lastError',
        );
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingCostStage = null;
      _sendingQaStage = null;
      _sendingUxStage = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  Future<void> _runAgentTurn({
    required SpecForgeStage stage,
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    required bool forceFollowUpQuestions,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final initialProject = _project;
    if (initialProject == null) return;

    final userMessage = SpecChatMessage(
      id: 'msg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );

    final initialStageState = initialProject.stageStateFor(stage);
    final withUserMsg = initialProject.withStageState(
      initialStageState.copyWith(
        status: initialStageState.status == SpecStageStatus.notStarted
            ? SpecStageStatus.inProgress
            : initialStageState.status,
        messages: [...initialStageState.messages, userMessage],
      ),
    );
    _project = withUserMsg;
    _isSending = true;
    _stopRequested = false;
    _sendingStage = stage;
    _sendingUxStage = null;
    _sendingQaStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Analyse par ${stage.agentTitle}…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    var workingProject = withUserMsg;
    final baseSnapshotBeforeTurn = initialProject;
    var currentPrompt = SpecPromptBuilder.buildTurnPrompt(
      project: initialProject,
      stage: stage,
      userInput: promptInput,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterAskUserReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
      companyGlossary: _companyGlossary,
      domainCatalog: _domainCatalog,
      modelPreferencesOverride: _modelPreferences,
      focusedObjectId: _focusedObjectId,
      focusedAttributePath: _focusedAttributePath,
      businessObjectFilter: _businessObjectFilter,
      focusedEventStormFlowId: _focusedEventStormFlowId,
      focusedEventStormNodeId: _focusedEventStormNodeId,
      focusedExampleStoryId: _focusedExampleStoryId,
    );

    final priorCauses = <String>[];
    final checkpointSummaries = <String>[];
    final turnToolTraces = <VibeToolTrace>[];
    var recovered = false;

    final registry = _buildProjectToolRegistry(
      readWorkingProject: () => workingProject,
      writeWorkingProject: (next) => workingProject = next,
    );

    try {
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        debugPrint(
          '[SpecForge IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
          '(${stage.agentTitle}) — prompt ${currentPrompt.length} car., '
          'pièces jointes: ${attachments.length}…',
        );
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }

        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: stage,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
          );
          if (response == null) {
            final partialText = parser.snapshot().message?.trim() ?? '';
            if (checkpointSummaries.isNotEmpty) {
              _pushUndo(baseSnapshotBeforeTurn);
            }
            final stoppedMessage = SpecChatMessage(
              id: 'msg_${shortid.generate()}',
              isUser: false,
              text: partialText.isNotEmpty
                  ? '$partialText\n\n[Réflexion IA interrompue par l’utilisateur.]'
                  : 'Réflexion IA interrompue par l’utilisateur.',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              appliedPatchSummary: checkpointSummaries.join(', '),
            );
            final currentStageState = workingProject.stageStateFor(stage);
            _project = workingProject.withStageState(
              currentStageState.copyWith(
                messages: [...currentStageState.messages, stoppedMessage],
              ),
            );
            await _persistProject(_project!);
            recovered = true;
            break;
          }
          parsedResponse = response;

          var updatedProject = workingProject;
          var patchSummary = '';

          if (response.specPatch != null && response.specPatch!.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
            final applied = SpecPatchApplier.apply(
              workingProject,
              response.specPatch!,
            );
            updatedProject = applied.project;
            patchSummary = [
              ...checkpointSummaries,
              if (applied.summary.isNotEmpty) applied.summary,
            ].join(', ');
          } else if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
            patchSummary = checkpointSummaries.join(', ');
          }

          final assistantMessage = SpecChatMessage(
            id: 'msg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
            stageReadyToAdvance: response.stageReadyToAdvance,
          );

          final currentStageState = updatedProject.stageStateFor(stage);
          updatedProject = updatedProject.withStageState(
            currentStageState.copyWith(
              messages: [...currentStageState.messages, assistantMessage],
              stageSummary: response.stageSummary.isNotEmpty
                  ? response.stageSummary
                  : currentStageState.stageSummary,
              readyToAdvance:
                  response.stageReadyToAdvance ||
                  currentStageState.readyToAdvance,
            ),
          );

          _project = updatedProject;
          await _persistProject(updatedProject);
          recovered = true;
          break;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );

          debugPrint(
            '[SpecForge IA] Échec tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.agentTitle}) : $cause',
          );
          saveError(
            '[SpecForge IA] Tentative ${attempt + 1}/$maxRecoveryAttempts '
            '(${stage.name}) : $cause',
            stack,
          );

          if (attempt < maxRecoveryAttempts - 1 && isValidationError) {
            final salvage = SpecDeltaRecovery.salvageFailedAttempt(
              workingProject: workingProject,
              rawResponse: parser.rawText,
              decodedPatch: parsedResponse?.specPatch,
            );
            if (salvage.hasCheckpoint) {
              workingProject = salvage.checkpointProject;
              if (salvage.appliedSummary.isNotEmpty) {
                checkpointSummaries.add(salvage.appliedSummary);
              }
              _project = workingProject;
              notifyListeners();
              debugPrint(
                '[SpecForge IA] Checkpoint partiel conservé '
                '(${salvage.appliedSummary}), relance delta…',
              );
            } else {
              debugPrint(
                '[SpecForge IA] Aucun checkpoint partiel, relance corrective…',
              );
            }

            final refreshedTurnPrompt = SpecPromptBuilder.buildTurnPrompt(
              project: workingProject,
              stage: stage,
              userInput: promptInput,
              questioningLevel: _questioningLevel,
              afterAskUserReply: afterAskUserReply || salvage.hasCheckpoint,
              forceFollowUpQuestions: forceFollowUpQuestions,
              companyGlossary: _companyGlossary,
              domainCatalog: _domainCatalog,
              modelPreferencesOverride: _modelPreferences,
              focusedObjectId: _focusedObjectId,
              focusedAttributePath: _focusedAttributePath,
              businessObjectFilter: _businessObjectFilter,
              focusedEventStormFlowId: _focusedEventStormFlowId,
              focusedEventStormNodeId: _focusedEventStormNodeId,
              focusedExampleStoryId: _focusedExampleStoryId,
            );
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: refreshedTurnPrompt,
              priorCauses: priorCauses,
              salvage: salvage,
              rawFailedResponse: parser.rawText,
            );
            continue;
          }

          if (checkpointSummaries.isNotEmpty) {
            _pushUndo(baseSnapshotBeforeTurn);
          }

          final failedDetail = priorCauses.length > 1
              ? priorCauses.join('\n')
              : cause;
          final errMessage = SpecChatMessage(
            id: 'msg_${shortid.generate()}',
            isUser: false,
            text:
                'Erreur lors de l’appel à ${stage.agentTitle} '
                '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n$failedDetail',
            toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
            appliedPatchSummary: checkpointSummaries.join(', '),
            failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
          );
          final currentStageState = workingProject.stageStateFor(stage);
          _project = workingProject.withStageState(
            currentStageState.copyWith(
              messages: [...currentStageState.messages, errMessage],
            ),
          );
          _lastError = cause;
          await _persistProject(_project!);
          break;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }

      if (!recovered && _lastError != null) {
        debugPrint(
          '[SpecForge IA] Fin du tour en erreur (${stage.agentTitle}) : $_lastError',
        );
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingStage = null;
      _sendingUxStage = null;
      _sendingQaStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  VibeAppToolRegistry _buildProjectToolRegistry({
    required SpecForgeProject Function() readWorkingProject,
    required void Function(SpecForgeProject next) writeWorkingProject,
    Set<String>? toolNames,
  }) {
    if (_customToolRegistry != null) return _customToolRegistry;
    return SpecForgeToolRegistry.build(
      readProject: readWorkingProject,
      readCompanyGlossary: () => _companyGlossary,
      readModelPreferences: () => _modelPreferences,
      onUpdateProject: (updated) async {
        _pushUndo(readWorkingProject());
        writeWorkingProject(updated);
        _project = updated;
        notifyListeners();
        await _persistProject(updated);
      },
      onNavigateStage: (targetStage) async {
        final moved = readWorkingProject().moveToStage(targetStage);
        writeWorkingProject(moved);
        _project = moved;
        notifyListeners();
      },
      onFocusObject: focusBusinessObject,
      onFocusSelection: focusBusinessSelection,
      onFocusEventStormFlow: focusEventStormFlow,
      onFocusExampleStory: focusExampleStory,
      onFilterBusinessObjects: setBusinessObjectFilter,
      onRunUxCoherenceAudit: (p) => UxCoherenceAnalyzer.analyze(
        p,
        companyGlossary: _companyGlossary,
      ),
      onFocusUxItem: ({stage, journeyId, routeId, screenId, zone}) {
        var stageChanged = false;
        final currentWorking = readWorkingProject();
        if (stage != null) {
          final movedUx = currentWorking.uxSpec.moveToStage(stage);
          if (movedUx != currentWorking.uxSpec) {
            final nextProject = currentWorking.copyWith(uxSpec: movedUx);
            writeWorkingProject(nextProject);
            _project = nextProject;
            stageChanged = true;
          }
        }
        final nextScreenId =
            screenId ?? (zone != null ? _focusedScreenId : null);
        final hadFocusChange =
            _focusedJourneyId != journeyId ||
            _focusedRouteId != routeId ||
            _focusedScreenId != nextScreenId ||
            _focusedScreenZone != zone;
        if (hadFocusChange) {
          focusUxItem(
            journeyId: journeyId,
            routeId: routeId,
            screenId: nextScreenId,
            zone: zone,
          );
        } else if (stageChanged) {
          notifyListeners();
        }
      },
      onRunQaCoherenceAudit: (p) => QaCoherenceAnalyzer.analyze(
        p,
        companyGlossary: _companyGlossary,
      ),
      onFocusQaItem: ({
        stage,
        fixtureId,
        featureId,
        scenarioId,
        tddSuiteId,
      }) {
        var stageChanged = false;
        final currentWorking = readWorkingProject();
        if (stage != null) {
          final movedQa = currentWorking.qaSpec.moveToStage(stage);
          if (movedQa != currentWorking.qaSpec) {
            final nextProject = currentWorking.copyWith(qaSpec: movedQa);
            writeWorkingProject(nextProject);
            _project = nextProject;
            stageChanged = true;
          }
        }
        final nextFeatureId =
            featureId ?? (scenarioId != null ? _focusedFeatureId : null);
        final hadFocusChange =
            _focusedFixtureId != fixtureId ||
            _focusedFeatureId != nextFeatureId ||
            _focusedScenarioId != scenarioId ||
            _focusedTddSuiteId != tddSuiteId;
        if (hadFocusChange) {
          focusQaItem(
            fixtureId: fixtureId,
            featureId: nextFeatureId,
            scenarioId: scenarioId,
            tddSuiteId: tddSuiteId,
          );
        } else if (stageChanged) {
          notifyListeners();
        }
      },
      onRunCostCoherenceAudit: CostCoherenceAnalyzer.analyze,
      onFocusCostItem: ({
        stage,
        profileId,
        wbsItemId,
        runItemId,
        riskItemId,
      }) {
        var stageChanged = false;
        final currentWorking = readWorkingProject();
        if (stage != null) {
          final movedCost = currentWorking.costSpec.moveToStage(stage);
          if (movedCost != currentWorking.costSpec) {
            final nextProject = currentWorking.copyWith(costSpec: movedCost);
            writeWorkingProject(nextProject);
            _project = nextProject;
            stageChanged = true;
          }
        }
        final hadFocusChange =
            _focusedCostProfileId != profileId ||
            _focusedWbsItemId != wbsItemId ||
            _focusedRunItemId != runItemId ||
            _focusedRiskItemId != riskItemId;
        if (hadFocusChange) {
          focusCostItem(
            profileId: profileId,
            wbsItemId: wbsItemId,
            runItemId: runItemId,
            riskItemId: riskItemId,
          );
        } else if (stageChanged) {
          notifyListeners();
        }
      },
      toolNames: toolNames,
    );
  }

  /// Diffuse un tour IA avec function calling : exécute les appels d'outils de
  /// [registry] (tracés dans [toolTraces] et le flux) jusqu'à la réponse JSON
  /// finale, en au plus [maxToolRounds] rounds. Partagé par les agents de la
  /// spec, de l'atelier UX, de l'atelier QA et des modèles de domaine ; renvoie `null` si
  /// l'utilisateur a arrêté la génération, [parser] conservant le texte du
  /// dernier round.
  Future<SpecAgentResponse?> _streamAgentResponse({
    required SpecStreamParser parser,
    required SpecForgeStage stage,
    required String prompt,
    required List<VibeChatAttachment> attachments,
    required VibeAppToolRegistry registry,
    required List<VibeToolTrace> toolTraces,
    String patchStatus = 'Structuration des spécifications…',
    String writingStatus = 'Rédaction en cours…',
    String? systemInstructionOverride,
    String? staticGuideOverride,
    Set<String>? allowedToolNames,
  }) async {
    var roundPrompt = prompt;
    final effectiveDeclarations = allowedToolNames == null
        ? registry.declarations
        : [
            for (final decl in registry.declarations)
              if (allowedToolNames.contains(decl.name) ||
                  (!SpecForgeToolRegistry.specToolNames.contains(decl.name) &&
                      !SpecForgeToolRegistry.uxToolNames.contains(decl.name) &&
                      !SpecForgeToolRegistry.qaToolNames.contains(decl.name) &&
                      !SpecForgeToolRegistry.costToolNames.contains(
                        decl.name,
                      )))
                decl,
          ];
    final conversationContents = <Map<String, Object?>>[
      <String, Object?>{
        'role': 'user',
        'parts': GeminiRestClient.buildUserParts(prompt, attachments),
      },
    ];

    for (var round = 0; round <= maxToolRounds; round++) {
      if (_stopRequested) return null;
      final allowTools = round < maxToolRounds;
      parser.reset();
      var nativeCalls = const <VibeToolCall>[];
      var rawModelParts = const <Map<String, Object?>>[];

      final completer = Completer<void>();
      _activeStreamCompleter = completer;
      _activeStreamSubscription = _aiService
          .streamTurn(
            stage: stage,
            prompt: roundPrompt,
            attachments: attachments,
            speedMode: _speedMode,
            tools: allowTools ? effectiveDeclarations : const [],
            conversationContents: conversationContents,
            enforceJsonResponse: !allowTools,
            systemInstructionOverride: systemInstructionOverride,
            staticGuideOverride: staticGuideOverride,
          )
          .listen(
            (event) {
              if (_stopRequested) return;
              if (event.functionCalls.isNotEmpty) {
                nativeCalls = event.functionCalls;
              }
              if (event.rawModelParts.isNotEmpty) {
                rawModelParts = event.rawModelParts;
              }
              if (event.deltaText.isNotEmpty) {
                final snap = parser.addChunk(event.deltaText);
                _streamingMessage = snap.message;
                if (snap.hasAskUser) {
                  _streamingStatus = 'Préparation des questions…';
                } else if (snap.hasCostPatch) {
                  _streamingStatus = 'Mise à jour du chiffrage FinOps…';
                } else if (snap.hasQaPatch) {
                  _streamingStatus = 'Mise à jour des tests BDD / TDD…';
                } else if (snap.hasUxPatch || snap.hasSpecPatch) {
                  _streamingStatus = patchStatus;
                } else if (snap.message != null) {
                  _streamingStatus = writingStatus;
                }
                notifyListeners();
              }
            },
            onError: (Object error, StackTrace stack) {
              _activeStreamSubscription = null;
              if (!completer.isCompleted) {
                completer.completeError(error, stack);
              }
            },
            onDone: () {
              _activeStreamSubscription = null;
              if (!completer.isCompleted) {
                completer.complete();
              }
            },
            cancelOnError: true,
          );

      await completer.future;
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      if (_stopRequested) return null;

      List<VibeToolCall> callsToRun = nativeCalls;
      SpecAgentResponse? roundParsed;
      if (callsToRun.isEmpty && parser.rawText.trim().isNotEmpty) {
        roundParsed = SpecAgentResponse.parse(parser.rawText);
        if (roundParsed.uxPatch == null &&
            roundParsed.qaPatch == null &&
            roundParsed.costPatch == null &&
            roundParsed.specPatch == null &&
            roundParsed.toolCalls.isNotEmpty) {
          callsToRun = roundParsed.toolCalls;
        }
      }

      if (callsToRun.isEmpty || !allowTools) {
        return roundParsed ?? SpecAgentResponse.parse(parser.rawText);
      }

      _streamingMessage = null;
      _streamingStatus = 'Outil : ${callsToRun.map((c) => c.name).join(', ')}…';
      notifyListeners();

      final results = await registry.executeAll(callsToRun);
      for (var i = 0; i < callsToRun.length; i++) {
        final call = callsToRun[i];
        final res = results[i];
        final summary = SpecForgeToolRegistry.summarizeResult(call, res);
        toolTraces.add(
          VibeToolTrace(
            name: call.name,
            arguments: call.arguments,
            isError: res.isError,
            summary: summary,
          ),
        );
        debugPrint('[SpecForge IA Tool] ${call.name} -> $summary');
      }
      _streamingToolTraces = List<VibeToolTrace>.unmodifiable(toolTraces);
      notifyListeners();

      conversationContents.add(<String, Object?>{
        'role': 'model',
        'parts': rawModelParts.isNotEmpty
            ? rawModelParts
            : <Map<String, Object?>>[
                for (final c in callsToRun)
                  <String, Object?>{'functionCall': c.toGeminiFunctionCall()},
              ],
      });
      conversationContents.add(<String, Object?>{
        'role': 'user',
        'parts': <Map<String, Object?>>[
          for (final r in results)
            <String, Object?>{
              'functionResponse': <String, Object?>{
                'name': r.name,
                'response': r.toGeminiFunctionResponsePayload(),
              },
            },
        ],
      });
      roundPrompt =
          '$roundPrompt\n\nRÉSULTATS DES OUTILS (round ${round + 1}) :\n'
          '${jsonEncode([for (final r in results) r.toJson()])}\n'
          'Poursuis ou conclus maintenant avec la réponse JSON finale.';
    }
    return null;
  }

  static String _describeErrorCause(Object error) {
    if (error is FormatException) return error.message;
    if (error is ArgumentError) return error.message?.toString() ?? '$error';
    if (error is StateError) return error.message;
    return error.toString();
  }

  void _pushUndo(SpecForgeProject snapshot) {
    _undoStack.add(snapshot);
    if (_undoStack.length > 40) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Met à jour le glossaire d'entreprise et le persiste sur disque.
  Future<void> updateCompanyGlossary(
    CompanyGlossary updated, {
    bool recordUndo = true,
  }) async {
    updated.validate();
    if (updated == _companyGlossary) return;
    if (recordUndo) {
      _pushGlossaryUndo(_companyGlossary);
    }
    _companyGlossary = updated;
    notifyListeners();
    await _persistGlossary(updated);
  }

  /// Ajoute ou met à jour un terme dans le glossaire d'entreprise.
  Future<void> upsertCompanyGlossaryTerm(CompanyGlossaryTerm term) =>
      updateCompanyGlossary(_companyGlossary.upsertTerm(term));

  /// Supprime un terme du glossaire d'entreprise par [termId].
  Future<void> deleteCompanyGlossaryTerm(String termId) =>
      updateCompanyGlossary(_companyGlossary.removeTerm(termId));

  /// Annule la dernière modification du glossaire d'entreprise.
  Future<void> undoCompanyGlossary() async {
    if (_glossaryUndoStack.isEmpty) return;
    final previous = _glossaryUndoStack.removeLast();
    _glossaryRedoStack.add(_companyGlossary);
    _companyGlossary = previous;
    notifyListeners();
    await _persistGlossary(previous);
  }

  /// Rétablit la dernière modification annulée du glossaire d'entreprise.
  Future<void> redoCompanyGlossary() async {
    if (_glossaryRedoStack.isEmpty) return;
    final next = _glossaryRedoStack.removeLast();
    _glossaryUndoStack.add(_companyGlossary);
    _companyGlossary = next;
    notifyListeners();
    await _persistGlossary(next);
  }

  /// Importe des termes sélectionnés du glossaire d'entreprise dans le lexique du projet actif.
  Future<({int added, int updated})> importCompanyGlossaryToProject({
    required List<String> termIds,
    bool overwriteExisting = false,
    bool includeConventions = false,
  }) async {
    final current = _project;
    if (current == null) {
      return (added: 0, updated: 0);
    }
    final wanted = termIds.toSet();
    final selected = [
      for (final t in _companyGlossary.terms)
        if (wanted.contains(t.id)) t,
    ];
    if (selected.isEmpty && !includeConventions) {
      return (added: 0, updated: 0);
    }

    final nextTerms = List<LexiconTerm>.from(current.lexicon.terms);
    var added = 0;
    var updated = 0;

    for (final cgTerm in selected) {
      final lexCandidate = cgTerm.toLexiconTerm();
      final byId = nextTerms.indexWhere((t) => t.id == lexCandidate.id);
      final idx = byId >= 0
          ? byId
          : nextTerms.indexWhere(
              (t) => t.term.toLowerCase() == lexCandidate.term.toLowerCase(),
            );
      if (idx >= 0) {
        if (overwriteExisting) {
          final existing = nextTerms[idx];
          nextTerms[idx] = lexCandidate.copyWith(id: existing.id);
          updated++;
        }
      } else {
        final existingIds = {for (final t in nextTerms) t.id};
        final safeId = existingIds.contains(lexCandidate.id)
            ? 'term_${shortid.generate()}'
            : lexCandidate.id;
        nextTerms.add(lexCandidate.copyWith(id: safeId));
        added++;
      }
    }

    var nextConventions = current.lexicon.conventions;
    if (includeConventions && _companyGlossary.conventions.isNotEmpty) {
      final seen = {for (final c in nextConventions) c.toLowerCase()};
      nextConventions = [
        ...nextConventions,
        for (final c in _companyGlossary.conventions)
          if (seen.add(c.toLowerCase())) c,
      ];
    }

    final nextLexicon = current.lexicon.copyWith(
      terms: nextTerms,
      conventions: nextConventions,
    );
    if (nextLexicon != current.lexicon) {
      await updateProject(current.copyWith(lexicon: nextLexicon));
    }
    return (added: added, updated: updated);
  }

  /// Promeut un terme du lexique projet vers le glossaire d'entreprise global.
  Future<({bool created, CompanyGlossaryTerm term})>
  promoteLexiconTermToCompanyGlossary(
    LexiconTerm term, {
    CompanyGlossaryStatus status = CompanyGlossaryStatus.approved,
    String owner = '',
    String technicalNameHint = '',
    List<String> forbiddenTerms = const <String>[],
  }) async {
    final now = DateTime.now().toUtc();
    final existingIdx = _companyGlossary.terms.indexWhere(
      (t) => t.id == term.id || t.term.toLowerCase() == term.term.toLowerCase(),
    );
    if (existingIdx >= 0) {
      final prev = _companyGlossary.terms[existingIdx];
      final merged = prev.copyWith(
        definition: term.definition.trim().isNotEmpty
            ? term.definition.trim()
            : prev.definition,
        synonyms: [...prev.synonyms, ...term.synonyms],
        forbiddenTerms: [...prev.forbiddenTerms, ...forbiddenTerms],
        domain: term.domain.trim().isNotEmpty
            ? term.domain.trim()
            : prev.domain,
        owner: owner.trim().isNotEmpty ? owner.trim() : prev.owner,
        technicalNameHint: technicalNameHint.trim().isNotEmpty
            ? technicalNameHint.trim()
            : prev.technicalNameHint,
        examples: [...prev.examples, ...term.examples],
        status: status,
        createdAt: prev.createdAt ?? now,
        updatedAt: now,
      );
      await upsertCompanyGlossaryTerm(merged);
      return (created: false, term: merged);
    }

    final newId = term.id.startsWith('cg_')
        ? term.id
        : 'cg_${shortid.generate()}';
    final createdTerm = CompanyGlossaryTerm.fromLexiconTerm(
      term,
      idOverride: newId,
      status: status,
      owner: owner,
      technicalNameHint: technicalNameHint,
      forbiddenTerms: forbiddenTerms,
      now: now,
    );
    await upsertCompanyGlossaryTerm(createdTerm);
    return (created: true, term: createdTerm);
  }

  /// Envoie un message utilisateur à l'agent IA dédié au glossaire d'entreprise.
  Future<void> sendGlossaryMessage(
    String text, {
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    if (_isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : 'Analyse les pièces jointes et propose les termes à intégrer au glossaire d’entreprise.';
    await _runGlossaryTurn(
      userDisplayText: effectiveText,
      promptInput: effectiveText,
      attachments: attachments,
      afterAskUserReply: false,
    );
  }

  /// Soumet les réponses d'un questionnaire `VibeAskUserCard` dans le chat du glossaire.
  Future<void> submitGlossaryAskUserAnswers(
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
  }) async {
    if (_isSending) return;
    final idx = _glossaryChatMessages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = _glossaryChatMessages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final updatedMsg = targetMsg.copyWith(
      askUserAnswers: answers,
      askUserUsedDefaults: usedDefaults,
    );
    final updatedMessages = List<SpecChatMessage>.from(_glossaryChatMessages)
      ..[idx] = updatedMsg;
    _glossaryChatMessages = List<SpecChatMessage>.unmodifiable(updatedMessages);
    notifyListeners();

    final summary =
        'Arbitrage enregistré :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    await _runGlossaryTurn(
      userDisplayText: summary,
      promptInput: summary,
      afterAskUserReply: true,
    );
  }

  /// Ignore un questionnaire dans le chat du glossaire en appliquant les valeurs par défaut.
  Future<void> skipGlossaryAskUser(String messageId) async {
    if (_isSending) return;
    final idx = _glossaryChatMessages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = _glossaryChatMessages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final defaults = askUser.defaultAnswers();
    final updatedMessages = List<SpecChatMessage>.from(_glossaryChatMessages)
      ..[idx] = targetMsg.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      );
    _glossaryChatMessages = List<SpecChatMessage>.unmodifiable(updatedMessages);
    notifyListeners();

    final summary =
        'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}';
    await _runGlossaryTurn(
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput: summary,
      afterAskUserReply: true,
    );
  }

  /// Relance le dernier tour en erreur du chat du glossaire.
  Future<void> retryLastGlossaryTurn() async {
    if (_isSending) return;
    var retryText =
        'La tentative précédente a échoué. Corrige le format JSON et mets à jour le glossaire.';
    var lastAttachments = const <VibeChatAttachment>[];
    for (var i = _glossaryChatMessages.length - 1; i >= 0; i--) {
      if (_glossaryChatMessages[i].isUser) {
        retryText =
            (_glossaryChatMessages[i].promptText ??
                    _glossaryChatMessages[i].text)
                .trim();
        lastAttachments = _glossaryChatMessages[i].attachments;
        break;
      }
    }
    await _runGlossaryTurn(
      userDisplayText: 'Reprise de la génération suite à erreur…',
      promptInput:
          '$retryText\n\nNOTE DE REPRISE : renvoie strictement un JSON valide.',
      attachments: lastAttachments,
      afterAskUserReply: false,
    );
  }

  /// Efface l'historique du chat IA dédié au glossaire d'entreprise.
  Future<void> clearGlossaryChat() async {
    if (_isSending) return;
    _glossaryChatMessages = const <SpecChatMessage>[];
    notifyListeners();
    await _glossaryStore.saveChatMessages(_glossaryChatMessages);
  }

  /// Envoie un message utilisateur à l'agent IA de découpage produit (Initiatives & Features).
  Future<void> sendPortfolioMessage(
    String text, {
    bool requestsMoreQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    if (_isSending || _project == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !requestsMoreQuestions && attachments.isEmpty) {
      return;
    }
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose des questions complémentaires pour affiner le découpage en initiatives et features.'
              : 'Analyse les pièces jointes et découpe le projet en initiatives et features.');
    await _runPortfolioTurn(
      userDisplayText: effectiveText,
      promptInput: effectiveText,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire `VibeAskUserCard` dans le chat Initiatives & Features.
  Future<void> submitPortfolioAskUserAnswers(
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
  }) async {
    final current = _project;
    if (_isSending || current == null) return;
    final messages = current.portfolioChatMessages;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final updatedMessages = List<SpecChatMessage>.from(messages)
      ..[idx] = targetMsg.copyWith(
        askUserAnswers: answers,
        askUserUsedDefaults: usedDefaults,
      );
    _project = current.copyWith(portfolioChatMessages: updatedMessages);
    notifyListeners();

    final summary =
        'Arbitrage enregistré :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    await _runPortfolioTurn(
      userDisplayText: summary,
      promptInput: summary,
      afterAskUserReply: true,
    );
  }

  /// Ignore un questionnaire dans le chat Initiatives & Features en appliquant les valeurs par défaut.
  Future<void> skipPortfolioAskUser(String messageId) async {
    final current = _project;
    if (_isSending || current == null) return;
    final messages = current.portfolioChatMessages;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final targetMsg = messages[idx];
    final askUser = targetMsg.askUser;
    if (askUser == null) return;

    final defaults = askUser.defaultAnswers();
    final updatedMessages = List<SpecChatMessage>.from(messages)
      ..[idx] = targetMsg.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      );
    _project = current.copyWith(portfolioChatMessages: updatedMessages);
    notifyListeners();

    final summary =
        'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}';
    await _runPortfolioTurn(
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput: summary,
      afterAskUserReply: true,
    );
  }

  /// Relance le dernier tour en erreur du chat Initiatives & Features.
  Future<void> retryLastPortfolioTurn() async {
    final current = _project;
    if (_isSending || current == null) return;
    var retryText =
        'Découpe le projet en initiatives et features structurées et renvoie un JSON valide.';
    var lastAttachments = const <VibeChatAttachment>[];
    for (var i = current.portfolioChatMessages.length - 1; i >= 0; i--) {
      final msg = current.portfolioChatMessages[i];
      if (msg.isUser) {
        retryText = (msg.promptText ?? msg.text).trim();
        lastAttachments = msg.attachments;
        break;
      }
    }
    await _runPortfolioTurn(
      userDisplayText: 'Reprise du découpage IA suite à erreur…',
      promptInput:
          '$retryText\n\nNOTE DE REPRISE : renvoie strictement un JSON valide.',
      attachments: lastAttachments,
      afterAskUserReply: false,
    );
  }

  /// Efface l'historique du chat IA de découpage produit du projet actif.
  Future<void> clearPortfolioChat() async {
    final current = _project;
    if (_isSending || current == null || current.portfolioChatMessages.isEmpty) {
      return;
    }
    final next = current.copyWith(
      portfolioChatMessages: const <SpecChatMessage>[],
    );
    _project = next;
    notifyListeners();
    await _persistProject(next);
  }

  Future<void> _runPortfolioTurn({
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final initialProject = _project;
    if (initialProject == null) return;

    final userMessage = SpecChatMessage(
      id: 'pfmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
    );
    final withUserMsg = initialProject.copyWith(
      portfolioChatMessages: <SpecChatMessage>[
        ...initialProject.portfolioChatMessages,
        userMessage,
      ],
    );
    _project = withUserMsg;
    _isSending = true;
    _sendingPortfolio = true;
    _stopRequested = false;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Découpage en initiatives et features…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    var currentPrompt = PortfolioSlicingAiAgent.buildTurnPrompt(
      project: withUserMsg,
      history: withUserMsg.portfolioChatMessages,
      userInput: promptInput,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterAskUserReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
    );

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (_stopRequested) break;
        final parser = SpecStreamParser();
        try {
          final completer = Completer<void>();
          _activeStreamCompleter = completer;
          _activeStreamSubscription = _aiService
              .streamTurn(
                stage: SpecForgeStage.vision,
                prompt: currentPrompt,
                attachments: attachments,
                speedMode: _speedMode,
                systemInstructionOverride:
                    PortfolioSlicingAiAgent.systemInstruction,
                staticGuideOverride: PortfolioSlicingAiAgent.patchSchemaGuide,
              )
              .listen(
                (event) {
                  if (_stopRequested) return;
                  if (event.deltaText.isNotEmpty) {
                    final snap = parser.addChunk(event.deltaText);
                    _streamingMessage = snap.message;
                    if (snap.hasAskUser) {
                      _streamingStatus = 'Préparation des arbitrages produit…';
                    } else if (snap.hasSpecPatch) {
                      _streamingStatus =
                          'Structuration des initiatives et features…';
                    } else if (snap.message != null) {
                      _streamingStatus = 'Rédaction en cours…';
                    }
                    notifyListeners();
                  }
                },
                onError: (Object error, StackTrace stack) {
                  _activeStreamSubscription = null;
                  if (!completer.isCompleted) {
                    completer.completeError(error, stack);
                  }
                },
                onDone: () {
                  _activeStreamSubscription = null;
                  if (!completer.isCompleted) {
                    completer.complete();
                  }
                },
                cancelOnError: true,
              );

          await completer.future;
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;

          final baseProject = _project;
          if (baseProject == null) return;

          if (_stopRequested) {
            final partial = parser.snapshot().message?.trim() ?? '';
            final stoppedMsg = SpecChatMessage(
              id: 'pfmsg_${shortid.generate()}',
              isUser: false,
              text: partial.isNotEmpty
                  ? '$partial\n\n[Réflexion IA interrompue par l’utilisateur.]'
                  : 'Réflexion IA interrompue par l’utilisateur.',
            );
            final stoppedProject = baseProject.copyWith(
              portfolioChatMessages: <SpecChatMessage>[
                ...baseProject.portfolioChatMessages,
                stoppedMsg,
              ],
            );
            _project = stoppedProject;
            await _persistProject(stoppedProject);
            return;
          }

          final response = SpecAgentResponse.parse(parser.rawText);
          var workingProject = baseProject;
          var patchSummary = '';
          if (response.specPatch != null && response.specPatch!.isNotEmpty) {
            final applied = PortfolioSlicingAiAgent.applyPatch(
              baseProject,
              response.specPatch!,
            );
            if (applied.project != baseProject) {
              _pushUndo(initialProject);
              if (applied.project.activeFeatureId !=
                  baseProject.activeFeatureId) {
                _clearProjectFocusState();
              }
              workingProject = applied.project;
              patchSummary = applied.summary;
            }
          }

          final assistantMsg = SpecChatMessage(
            id: 'pfmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
          );
          final finalProject = workingProject.copyWith(
            portfolioChatMessages: <SpecChatMessage>[
              ...workingProject.portfolioChatMessages,
              assistantMsg,
            ],
          );
          _project = finalProject;
          await _persistProject(finalProject);
          return;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          saveError(
            '[SpecForge Portfolio IA] Tentative ${attempt + 1} : $cause',
            stack,
          );
          if (attempt == 0 &&
              (error is FormatException ||
                  error is ArgumentError ||
                  error is StateError)) {
            currentPrompt =
                '$currentPrompt\n\nErreur JSON précédente ($cause). Renvoie uniquement un objet JSON valide.';
            continue;
          }
          final baseProject = _project;
          if (baseProject != null) {
            final errMsg = SpecChatMessage(
              id: 'pfmsg_${shortid.generate()}',
              isUser: false,
              text: 'Erreur lors du découpage produit : $cause',
              failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
            );
            final erroredProject = baseProject.copyWith(
              portfolioChatMessages: <SpecChatMessage>[
                ...baseProject.portfolioChatMessages,
                errMsg,
              ],
            );
            _project = erroredProject;
            await _persistProject(erroredProject);
          }
          _lastError = cause;
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingPortfolio = false;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  Future<void> _runGlossaryTurn({
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    final baseGlossary = _companyGlossary;
    final userMessage = SpecChatMessage(
      id: 'cgmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
    );
    _glossaryChatMessages = List<SpecChatMessage>.unmodifiable([
      ..._glossaryChatMessages,
      userMessage,
    ]);
    _isSending = true;
    _sendingGlossary = true;
    _stopRequested = false;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Analyse du glossaire d’entreprise…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    var currentPrompt = CompanyGlossaryAiAgent.buildTurnPrompt(
      glossary: baseGlossary,
      history: _glossaryChatMessages,
      userInput: promptInput,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterAskUserReply,
    );

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (_stopRequested) break;
        final parser = SpecStreamParser();
        try {
          final completer = Completer<void>();
          _activeStreamCompleter = completer;
          _activeStreamSubscription = _aiService
              .streamTurn(
                stage: SpecForgeStage.lexicon,
                prompt: currentPrompt,
                attachments: attachments,
                speedMode: _speedMode,
                systemInstructionOverride:
                    CompanyGlossaryAiAgent.systemInstruction,
                staticGuideOverride: CompanyGlossaryAiAgent.patchSchemaGuide,
              )
              .listen(
                (event) {
                  if (_stopRequested) return;
                  if (event.deltaText.isNotEmpty) {
                    final snap = parser.addChunk(event.deltaText);
                    _streamingMessage = snap.message;
                    if (snap.hasAskUser) {
                      _streamingStatus = 'Préparation des arbitrages…';
                    } else if (snap.hasSpecPatch) {
                      _streamingStatus = 'Mise à jour du glossaire…';
                    } else if (snap.message != null) {
                      _streamingStatus = 'Rédaction en cours…';
                    }
                    notifyListeners();
                  }
                },
                onError: (Object error, StackTrace stack) {
                  _activeStreamSubscription = null;
                  if (!completer.isCompleted) {
                    completer.completeError(error, stack);
                  }
                },
                onDone: () {
                  _activeStreamSubscription = null;
                  if (!completer.isCompleted) {
                    completer.complete();
                  }
                },
                cancelOnError: true,
              );

          await completer.future;
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;

          if (_stopRequested) {
            final partial = parser.snapshot().message?.trim() ?? '';
            final stoppedMsg = SpecChatMessage(
              id: 'cgmsg_${shortid.generate()}',
              isUser: false,
              text: partial.isNotEmpty
                  ? '$partial\n\n[Réflexion IA interrompue par l’utilisateur.]'
                  : 'Réflexion IA interrompue par l’utilisateur.',
            );
            _glossaryChatMessages = List<SpecChatMessage>.unmodifiable([
              ..._glossaryChatMessages,
              stoppedMsg,
            ]);
            await _glossaryStore.saveChatMessages(_glossaryChatMessages);
            return;
          }

          final response = SpecAgentResponse.parse(parser.rawText);
          var patchSummary = '';
          if (response.specPatch != null && response.specPatch!.isNotEmpty) {
            final applied = CompanyGlossaryAiAgent.applyPatch(
              _companyGlossary,
              response.specPatch!,
            );
            if (applied.glossary != _companyGlossary) {
              _pushGlossaryUndo(_companyGlossary);
              _companyGlossary = applied.glossary;
              patchSummary = applied.summary;
              await _persistGlossary(_companyGlossary);
            }
          }

          final assistantMsg = SpecChatMessage(
            id: 'cgmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
          );
          _glossaryChatMessages = List<SpecChatMessage>.unmodifiable([
            ..._glossaryChatMessages,
            assistantMsg,
          ]);
          await _glossaryStore.saveChatMessages(_glossaryChatMessages);
          return;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          saveError(
            '[SpecForge Glossaire IA] Tentative ${attempt + 1} : $cause',
            stack,
          );
          if (attempt == 0 &&
              (error is FormatException ||
                  error is ArgumentError ||
                  error is StateError)) {
            currentPrompt =
                '$currentPrompt\n\nErreur JSON précédente ($cause). Renvoie uniquement un objet JSON valide.';
            continue;
          }
          final errMsg = SpecChatMessage(
            id: 'cgmsg_${shortid.generate()}',
            isUser: false,
            text: 'Erreur lors de l’analyse du glossaire : $cause',
            failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
          );
          _glossaryChatMessages = List<SpecChatMessage>.unmodifiable([
            ..._glossaryChatMessages,
            errMsg,
          ]);
          _lastError = cause;
          await _glossaryStore.saveChatMessages(_glossaryChatMessages);
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingGlossary = false;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  /// Envoie un message à l'agent IA du modèle [entryId] du domaine [domainId] ;
  /// [requestsMoreQuestions] demande des questions complémentaires (« + Questions »).
  Future<void> sendDomainModelMessage(
    String domainId,
    String entryId,
    String text, {
    bool requestsMoreQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) async {
    if (_isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !requestsMoreQuestions && attachments.isEmpty) {
      return;
    }
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour approfondir ce modèle.'
              : 'Analyse les pièces jointes et propose les attributs du modèle.');
    await _runDomainModelTurn(
      domainId,
      entryId,
      userDisplayText: effectiveText,
      promptInput: effectiveText,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire du chat d'un modèle de domaine ;
  /// [askMore] enchaîne sur des questions complémentaires.
  Future<void> submitDomainModelAskUserAnswers(
    String domainId,
    String entryId,
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    if (_isSending) return;
    final target = domainModelChat(
      domainId,
      entryId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final summary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    await _runDomainModelTurn(
      domainId,
      entryId,
      userDisplayText: askMore
          ? '$summary\n(+ questions complémentaires demandées)'
          : summary,
      promptInput: summary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
      answered: target.copyWith(
        askUserAnswers: answers,
        askUserUsedDefaults: usedDefaults,
        askUserRequestedMore: askMore,
      ),
    );
  }

  /// Ignore un questionnaire du chat d'un modèle en appliquant les valeurs par défaut.
  Future<void> skipDomainModelAskUser(
    String domainId,
    String entryId,
    String messageId,
  ) async {
    if (_isSending) return;
    final target = domainModelChat(
      domainId,
      entryId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final defaults = askUser.defaultAnswers();
    await _runDomainModelTurn(
      domainId,
      entryId,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput:
          'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}',
      afterAskUserReply: true,
      answered: target.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      ),
    );
  }

  /// Relance le dernier tour en erreur du chat d'un modèle de domaine.
  Future<void> retryLastDomainModelTurn(String domainId, String entryId) async {
    if (_isSending) return;
    final lastUser = domainModelChat(domainId, entryId).lastWhere(
      (m) => m.isUser,
      orElse: () => SpecChatMessage(
        id: '',
        isUser: true,
        text: 'La tentative précédente a échoué. Corrige le format JSON et mets à jour le modèle.',
      ),
    );
    await _runDomainModelTurn(
      domainId,
      entryId,
      userDisplayText: 'Reprise de la génération suite à erreur…',
      promptInput:
          '${(lastUser.promptText ?? lastUser.text).trim()}\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastUser.attachments,
      afterAskUserReply: false,
    );
  }

  /// Efface l'historique du chat IA d'un modèle de domaine.
  Future<void> clearDomainModelChat(String domainId, String entryId) async {
    if (_isSending) return;
    await _updateDomainModelChat(domainId, entryId, (_) => const []);
  }

  /// Tour IA sur le détail d'un modèle, avec les mêmes mécanismes que l'étape
  /// Objets métier (outils, traces, scope sélectionné, reprises automatiques)
  /// appliqués au projet temporaire de la fiche. Le document est relu à
  /// chaque écriture : une saisie DSL pendant la réponse n'est pas écrasée,
  /// et une entrée supprimée entre-temps termine le tour sans rien enregistrer.
  Future<void> _runDomainModelTurn(
    String domainId,
    String entryId, {
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    SpecChatMessage? answered,
  }) async {
    final contracts = _domainContractsOf(domainId);
    final entry = contracts?.entryById(entryId);
    if (contracts == null || entry == null) return;
    final domainName = _domainCatalog.domains
        .firstWhere((d) => d.id == domainId)
        .name;

    SpecForgeProject? readModelProject() {
      final current = _domainContractsOf(domainId);
      final currentEntry = current?.entryById(entryId);
      if (current == null || currentEntry == null) return null;
      return DomainModelAiAgent.modelProject(
        current,
        currentEntry,
        domainId: domainId,
        modelPreferences: _modelPreferences,
      );
    }

    String buildPrompt(
      DomainContracts document,
      JsonNode target, {
      required bool afterReply,
    }) => DomainModelAiAgent.buildTurnPrompt(
      domainName: domainName,
      domainId: domainId,
      contracts: document,
      entry: target,
      history: document.chats[entryId] ?? const <SpecChatMessage>[],
      userInput: promptInput,
      modelPreferences: _modelPreferences,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
      companyGlossary: _companyGlossary,
      valueObjects: _domainCatalog.resolvedValueObjectsForDomain(domainId),
      focusedAttributePath: domainModelAttributePath(domainId, entryId),
      filter: domainModelFilter(domainId, entryId),
    );

    var currentPrompt = buildPrompt(
      contracts,
      entry,
      afterReply: afterAskUserReply,
    );
    final userMessage = SpecChatMessage(
      id: 'dmmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );
    final turnToolTraces = <VibeToolTrace>[];
    final priorCauses = <String>[];
    Future<bool> append(SpecChatMessage message) =>
        _updateDomainModelChat(domainId, entryId, (chat) => [...chat, message]);

    final registry =
        _customToolRegistry ??
        SpecForgeToolRegistry.build(
          readProject: readModelProject,
          readCompanyGlossary: () => _companyGlossary,
          readModelPreferences: () => _modelPreferences,
          onUpdateProject: (updated) async {
            final object = updated.businessObjects
                .where((o) => o.id == entryId)
                .firstOrNull;
            if (object != null) {
              await updateDomainModelObject(domainId, object);
            }
          },
          onNavigateStage: (_) async {},
          onFocusObject: (objectId) {
            if (objectId == entryId) {
              focusDomainModelAttribute(domainId, entryId, const []);
            }
          },
          onFocusSelection: ({objectId, attributePath = const <String>[]}) {
            if (objectId == entryId) {
              focusDomainModelAttribute(domainId, entryId, attributePath);
            }
          },
          onFilterBusinessObjects: (query) =>
              setDomainModelFilter(domainId, entryId, query),
          toolNames: DomainModelAiAgent.toolNames,
          coherenceIssueFilter: DomainModelAiAgent.coherenceIssueFilterFor(
            entryId,
          ),
        );

    _isSending = true;
    _sendingDomainModelKey = '$domainId/$entryId';
    _stopRequested = false;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Analyse du modèle ${entry.name}…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    try {
      final started = await _updateDomainModelChat(
        domainId,
        entryId,
        (chat) => [
          for (final message in chat)
            if (message.id == answered?.id) answered! else message,
          userMessage,
        ],
      );
      if (!started) return;
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }
        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.businessObjects,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour des attributs…',
            systemInstructionOverride: DomainModelAiAgent.systemInstruction,
            staticGuideOverride: DomainModelAiAgent.staticGuide,
          );
          final traces = List<VibeToolTrace>.unmodifiable(turnToolTraces);
          if (response == null) {
            final partial = parser.snapshot().message?.trim() ?? '';
            await append(
              SpecChatMessage(
                id: 'dmmsg_${shortid.generate()}',
                isUser: false,
                text: partial.isNotEmpty
                    ? '$partial\n\n[Réflexion IA interrompue par l’utilisateur.]'
                    : 'Réflexion IA interrompue par l’utilisateur.',
                toolTraces: traces,
              ),
            );
            return;
          }
          parsedResponse = response;

          final current = _domainContractsOf(domainId);
          final currentEntry = current?.entryById(entryId);
          if (current == null || currentEntry == null) return;
          var next = current;
          var patchSummary = '';
          final patch = response.specPatch;
          if (patch != null && patch.isNotEmpty) {
            final applied = DomainModelAiAgent.applyPatch(
              current.objectFor(currentEntry),
              patch,
              referenceTargets: current.referenceTargetsOf(currentEntry),
              valueObjects: _domainCatalog.valueObjectsForDomain(domainId),
            );
            if (applied.summary.isNotEmpty) {
              next = next.withModel(entryId, object: applied.object);
              patchSummary = applied.summary;
            }
          }
          final assistantMessage = SpecChatMessage(
            id: 'dmmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: traces,
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
          );
          await updateDomainContracts(
            domainId,
            next.withModel(
              entryId,
              chat: [...?next.chats[entryId], assistantMessage],
            ),
          );
          return;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );
          saveError(
            '[SpecForge Modèle IA] Tentative ${attempt + 1}/$maxRecoveryAttempts : $cause',
            stack,
          );
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          final document = _domainContractsOf(domainId);
          final target = document?.entryById(entryId);
          final project = readModelProject();
          if (attempt < maxRecoveryAttempts - 1 &&
              isValidationError &&
              document != null &&
              target != null &&
              project != null) {
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: buildPrompt(
                document,
                target,
                afterReply: afterAskUserReply,
              ),
              priorCauses: priorCauses,
              salvage: SpecSalvageOutcome.none(
                project,
                wasTruncated: parsedResponse == null,
              ),
              rawFailedResponse: parser.rawText,
            );
            continue;
          }
          _lastError = cause;
          await append(
            SpecChatMessage(
              id: 'dmmsg_${shortid.generate()}',
              isUser: false,
              text:
                  'Erreur lors de l’appel à l’assistant du modèle '
                  '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n'
                  '${priorCauses.length > 1 ? priorCauses.join('\n') : cause}',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
            ),
          );
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingDomainModelKey = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  /// Envoie un message à l'agent IA de la couche Domain de l'entrée [entryId] du domaine [domainId].
  Future<void> sendDomainLayerMessage(
    String domainId,
    String entryId,
    String text, {
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    bool requestsMoreQuestions = false,
  }) async {
    if (_isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && !requestsMoreQuestions) {
      return;
    }
    final activeTab = domainLayerActiveTab(domainId, entryId);
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour affiner la couche Domain (${activeTab.label}).'
              : 'Analyse les pièces jointes et propose les éléments de la couche Domain.');
    await _runDomainLayerTurn(
      domainId,
      entryId,
      userDisplayText: effectiveText,
      promptInput: effectiveText,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire du chat de la couche Domain.
  Future<void> submitDomainLayerAskUserAnswers(
    String domainId,
    String entryId,
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    if (_isSending) return;
    final target = domainLayerChat(
      domainId,
      entryId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final summary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    await _runDomainLayerTurn(
      domainId,
      entryId,
      userDisplayText: askMore
          ? '$summary\n(+ questions complémentaires demandées)'
          : summary,
      promptInput: summary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
      answered: target.copyWith(
        askUserAnswers: answers,
        askUserUsedDefaults: usedDefaults,
        askUserRequestedMore: askMore,
      ),
    );
  }

  /// Ignore un questionnaire du chat de la couche Domain en appliquant les valeurs par défaut.
  Future<void> skipDomainLayerAskUser(
    String domainId,
    String entryId,
    String messageId,
  ) async {
    if (_isSending) return;
    final target = domainLayerChat(
      domainId,
      entryId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final defaults = askUser.defaultAnswers();
    await _runDomainLayerTurn(
      domainId,
      entryId,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput:
          'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}',
      afterAskUserReply: true,
      answered: target.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      ),
    );
  }

  /// Relance le dernier tour en erreur du chat de la couche Domain.
  Future<void> retryLastDomainLayerTurn(String domainId, String entryId) async {
    if (_isSending) return;
    final lastUser = domainLayerChat(domainId, entryId).lastWhere(
      (m) => m.isUser,
      orElse: () => SpecChatMessage(
        id: '',
        isUser: true,
        text:
            'La tentative précédente a échoué. Corrige le format JSON et mets à jour la couche Domain.',
      ),
    );
    await _runDomainLayerTurn(
      domainId,
      entryId,
      userDisplayText: 'Reprise de la génération suite à erreur…',
      promptInput:
          '${(lastUser.promptText ?? lastUser.text).trim()}\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastUser.attachments,
      afterAskUserReply: false,
    );
  }

  /// Efface l'historique du chat IA de la couche Domain d'un modèle.
  Future<void> clearDomainLayerChat(String domainId, String entryId) async {
    if (_isSending) return;
    await _updateDomainLayerChat(domainId, entryId, (_) => const []);
  }

  Future<void> _runDomainLayerTurn(
    String domainId,
    String entryId, {
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    SpecChatMessage? answered,
  }) async {
    final contracts = _domainContractsOf(domainId);
    final entry = contracts?.entryById(entryId);
    if (contracts == null || entry == null) return;
    final domainName = _domainCatalog.domains
        .firstWhere((d) => d.id == domainId)
        .name;

    SpecForgeProject? readModelProject() {
      final current = _domainContractsOf(domainId);
      final currentEntry = current?.entryById(entryId);
      if (current == null || currentEntry == null) return null;
      return DomainModelAiAgent.modelProject(
        current,
        currentEntry,
        domainId: domainId,
        modelPreferences: _modelPreferences,
      );
    }

    String buildPrompt(
      DomainContracts document,
      JsonNode target, {
      required bool afterReply,
    }) => DomainLayerAiAgent.buildTurnPrompt(
      domainName: domainName,
      contracts: document,
      entry: target,
      activeTab: domainLayerActiveTab(domainId, entryId),
      history: document.domainLayerChats[entryId] ?? const <SpecChatMessage>[],
      userInput: promptInput,
      modelPreferences: _modelPreferences,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
      companyGlossary: _companyGlossary,
    );

    var currentPrompt = buildPrompt(
      contracts,
      entry,
      afterReply: afterAskUserReply,
    );
    final userMessage = SpecChatMessage(
      id: 'dlmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );
    final turnToolTraces = <VibeToolTrace>[];
    final priorCauses = <String>[];
    Future<bool> append(SpecChatMessage message) =>
        _updateDomainLayerChat(domainId, entryId, (chat) => [...chat, message]);

    final registry =
        _customToolRegistry ??
        SpecForgeToolRegistry.build(
          readProject: readModelProject,
          readCompanyGlossary: () => _companyGlossary,
          readModelPreferences: () => _modelPreferences,
          onUpdateProject: (_) async {},
          onNavigateStage: (_) async {},
          toolNames: DomainLayerAiAgent.toolNames,
        );

    _isSending = true;
    _sendingDomainLayerKey = '$domainId/$entryId';
    _stopRequested = false;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = 'Conception de la couche Domain (${entry.name})…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    try {
      final started = await _updateDomainLayerChat(
        domainId,
        entryId,
        (chat) => [
          for (final message in chat)
            if (message.id == answered?.id) answered! else message,
          userMessage,
        ],
      );
      if (!started) return;
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }
        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.businessRules,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour de la couche Domain…',
            systemInstructionOverride: DomainLayerAiAgent.systemInstruction,
            staticGuideOverride: DomainLayerAiAgent.staticGuide,
          );
          final traces = List<VibeToolTrace>.unmodifiable(turnToolTraces);
          if (response == null) {
            final partial = parser.snapshot().message?.trim() ?? '';
            await append(
              SpecChatMessage(
                id: 'dlmsg_${shortid.generate()}',
                isUser: false,
                text: partial.isNotEmpty
                    ? '$partial\n\n[Réflexion IA interrompue par l’utilisateur.]'
                    : 'Réflexion IA interrompue par l’utilisateur.',
                toolTraces: traces,
              ),
            );
            return;
          }
          parsedResponse = response;

          final current = _domainContractsOf(domainId);
          final currentEntry = current?.entryById(entryId);
          if (current == null || currentEntry == null) return;
          var next = current;
          var patchSummary = '';
          final patch = response.specPatch;
          if (patch != null && patch.isNotEmpty) {
            final applied = DomainLayerAiAgent.applyPatch(
              current.domainLayerFor(currentEntry),
              patch,
              modelObject: current.objectFor(currentEntry),
            );
            if (applied.summary.isNotEmpty) {
              next = next.withDomainLayer(entryId, layer: applied.layer);
              patchSummary = applied.summary;
            }
          }
          final assistantMessage = SpecChatMessage(
            id: 'dlmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: traces,
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
          );
          await updateDomainContracts(
            domainId,
            next.withDomainLayer(
              entryId,
              chat: [...?next.domainLayerChats[entryId], assistantMessage],
            ),
          );
          return;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );
          saveError(
            '[SpecForge Domain Layer IA] Tentative ${attempt + 1}/$maxRecoveryAttempts : $cause',
            stack,
          );
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          final document = _domainContractsOf(domainId);
          final target = document?.entryById(entryId);
          final project = readModelProject();
          if (attempt < maxRecoveryAttempts - 1 &&
              isValidationError &&
              document != null &&
              target != null &&
              project != null) {
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: buildPrompt(
                document,
                target,
                afterReply: afterAskUserReply,
              ),
              priorCauses: priorCauses,
              salvage: SpecSalvageOutcome.none(
                project,
                wasTruncated: parsedResponse == null,
              ),
              rawFailedResponse: parser.rawText,
            );
            continue;
          }
          _lastError = cause;
          await append(
            SpecChatMessage(
              id: 'dlmsg_${shortid.generate()}',
              isUser: false,
              text:
                  'Erreur lors de l’appel à l’assistant Couche Domain '
                  '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n'
                  '${priorCauses.length > 1 ? priorCauses.join('\n') : cause}',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
            ),
          );
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingDomainLayerKey = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  /// Enregistre la spécification « Cas d’usage & orchestration » du domaine [domainId].
  Future<void> updateUseCaseOrchestration(
    String domainId,
    UseCaseOrchestrationSpec spec,
  ) {
    if (!_domainCatalog.domains.any((d) => d.id == domainId)) {
      throw StateError('Le domaine sélectionné n’existe plus.');
    }
    spec.validate();
    return updateDomainCatalog(
      _domainCatalog.copyWith(
        domains: [
          for (final domain in _domainCatalog.domains)
            if (domain.id == domainId)
              domain.copyWith(useCaseOrchestration: spec)
            else
              domain,
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<bool> _updateUseCaseOrchestrationChat(
    String domainId,
    List<SpecChatMessage> Function(List<SpecChatMessage> chat) update,
  ) async {
    final domain = _domainCatalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    if (domain == null) return false;
    final current =
        domain.useCaseOrchestration ?? UseCaseOrchestrationSpec.empty;
    await updateUseCaseOrchestration(
      domainId,
      current.copyWith(chatMessages: update(current.chatMessages)),
    );
    return true;
  }

  /// Envoie un message à l'agent IA « Cas d’usage & orchestration » pour [domainId].
  Future<void> sendUseCaseOrchestrationMessage(
    String domainId,
    String text, {
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    bool requestsMoreQuestions = false,
  }) async {
    if (_isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && !requestsMoreQuestions) {
      return;
    }
    final activeTab = useCaseOrchestrationActiveTab(domainId);
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour affiner « ${activeTab.label} ».'
              : 'Analyse les pièces jointes et complète les cas d’usage et Sagas.');
    await _runUseCaseOrchestrationTurn(
      domainId,
      userDisplayText: effectiveText,
      promptInput: effectiveText,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire du chat « Cas d’usage & orchestration ».
  Future<void> submitUseCaseOrchestrationAskUserAnswers(
    String domainId,
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    if (_isSending) return;
    final target = useCaseOrchestrationChat(
      domainId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final summary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    await _runUseCaseOrchestrationTurn(
      domainId,
      userDisplayText: askMore
          ? '$summary\n(+ questions complémentaires demandées)'
          : summary,
      promptInput: summary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
      answered: target.copyWith(
        askUserAnswers: answers,
        askUserUsedDefaults: usedDefaults,
        askUserRequestedMore: askMore,
      ),
    );
  }

  /// Ignore un questionnaire du chat « Cas d’usage & orchestration » avec les valeurs par défaut.
  Future<void> skipUseCaseOrchestrationAskUser(
    String domainId,
    String messageId,
  ) async {
    if (_isSending) return;
    final target = useCaseOrchestrationChat(
      domainId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final defaults = askUser.defaultAnswers();
    await _runUseCaseOrchestrationTurn(
      domainId,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput:
          'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}',
      afterAskUserReply: true,
      answered: target.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      ),
    );
  }

  /// Relance le dernier tour en erreur du chat « Cas d’usage & orchestration ».
  Future<void> retryLastUseCaseOrchestrationTurn(String domainId) async {
    if (_isSending) return;
    final lastUser = useCaseOrchestrationChat(domainId).lastWhere(
      (m) => m.isUser,
      orElse: () => SpecChatMessage(
        id: '',
        isUser: true,
        text:
            'La tentative précédente a échoué. Corrige le format JSON et complète les cas d’usage et Sagas.',
      ),
    );
    await _runUseCaseOrchestrationTurn(
      domainId,
      userDisplayText: 'Reprise de la génération suite à erreur…',
      promptInput:
          '${(lastUser.promptText ?? lastUser.text).trim()}\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastUser.attachments,
      afterAskUserReply: false,
    );
  }

  /// Efface l'historique du chat IA « Cas d’usage & orchestration » d'un domaine.
  Future<void> clearUseCaseOrchestrationChat(String domainId) async {
    if (_isSending) return;
    await _updateUseCaseOrchestrationChat(domainId, (_) => const []);
  }

  Future<void> _runUseCaseOrchestrationTurn(
    String domainId, {
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    SpecChatMessage? answered,
  }) async {
    final initialDomain = _domainCatalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    if (initialDomain == null) return;

    String buildPrompt(FunctionalDomain domain, {required bool afterReply}) =>
        UseCaseOrchestrationAiAgent.buildTurnPrompt(
          domain: domain,
          catalog: _domainCatalog,
          activeTab: useCaseOrchestrationActiveTab(domainId),
          history:
              domain.useCaseOrchestration?.chatMessages ??
              const <SpecChatMessage>[],
          userInput: promptInput,
          modelPreferences: _modelPreferences,
          questioningLevel: _questioningLevel,
          afterAskUserReply: afterReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
          activeProject: _project,
          companyGlossary: _companyGlossary,
        );

    var currentPrompt = buildPrompt(
      initialDomain,
      afterReply: afterAskUserReply,
    );
    final userMessage = SpecChatMessage(
      id: 'ucmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );
    final turnToolTraces = <VibeToolTrace>[];
    final priorCauses = <String>[];
    Future<bool> append(SpecChatMessage message) =>
        _updateUseCaseOrchestrationChat(
          domainId,
          (chat) => [...chat, message],
        );

    final activeProject = _project;
    final registry =
        _customToolRegistry ??
        (activeProject != null
            ? SpecForgeToolRegistry.build(
                readProject: () => _project,
                readCompanyGlossary: () => _companyGlossary,
                readModelPreferences: () => _modelPreferences,
                onUpdateProject: (_) async {},
                onNavigateStage: (_) async {},
                toolNames: UseCaseOrchestrationAiAgent.toolNames,
              )
            : VibeAppToolRegistry(const []));

    _isSending = true;
    _sendingUseCaseDomainId = domainId;
    _stopRequested = false;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus =
        'Conception des Use Cases & Sagas (${initialDomain.name})…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    try {
      final started = await _updateUseCaseOrchestrationChat(
        domainId,
        (chat) => [
          for (final message in chat)
            if (message.id == answered?.id) answered! else message,
          userMessage,
        ],
      );
      if (!started) return;
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }
        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.specifications,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour des Use Cases & Sagas…',
            systemInstructionOverride:
                UseCaseOrchestrationAiAgent.systemInstruction,
            staticGuideOverride: UseCaseOrchestrationAiAgent.staticGuide,
            allowedToolNames: activeProject != null
                ? UseCaseOrchestrationAiAgent.toolNames
                : const <String>{},
          );
          final traces = List<VibeToolTrace>.unmodifiable(turnToolTraces);
          if (response == null) {
            final partial = parser.snapshot().message?.trim() ?? '';
            await append(
              SpecChatMessage(
                id: 'ucmsg_${shortid.generate()}',
                isUser: false,
                text: partial.isNotEmpty
                    ? '$partial\n\n[Réflexion IA interrompue par l’utilisateur.]'
                    : 'Réflexion IA interrompue par l’utilisateur.',
                toolTraces: traces,
              ),
            );
            return;
          }
          parsedResponse = response;

          final currentDomain = _domainCatalog.domains
              .where((d) => d.id == domainId)
              .firstOrNull;
          if (currentDomain == null) return;
          var nextSpec =
              currentDomain.useCaseOrchestration ??
              UseCaseOrchestrationSpec.empty;
          var patchSummary = '';
          final patch = response.specPatch;
          if (patch != null && patch.isNotEmpty) {
            final applied = UseCaseOrchestrationAiAgent.applyPatch(
              nextSpec,
              patch,
            );
            nextSpec = applied.spec;
            patchSummary = applied.summary;
          }
          final assistantMessage = SpecChatMessage(
            id: 'ucmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: traces,
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
          );
          await updateUseCaseOrchestration(
            domainId,
            nextSpec.copyWith(
              chatMessages: [...nextSpec.chatMessages, assistantMessage],
            ),
          );
          return;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );
          saveError(
            '[SpecForge UseCase Orchestration IA] Tentative ${attempt + 1}/$maxRecoveryAttempts : $cause',
            stack,
          );
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          final latestDomain = _domainCatalog.domains
              .where((d) => d.id == domainId)
              .firstOrNull;
          if (attempt < maxRecoveryAttempts - 1 &&
              isValidationError &&
              latestDomain != null) {
            final retryProject =
                _project ??
                SpecForgeProject.fromIdea(
                  idea: latestDomain.name,
                  name: latestDomain.name,
                  id: 'uc_retry_$domainId',
                );
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: buildPrompt(
                latestDomain,
                afterReply: afterAskUserReply,
              ),
              priorCauses: priorCauses,
              salvage: SpecSalvageOutcome.none(
                retryProject,
                wasTruncated: parsedResponse == null,
              ),
              rawFailedResponse: parser.rawText,
            );
            continue;
          }
          _lastError = cause;
          await append(
            SpecChatMessage(
              id: 'ucmsg_${shortid.generate()}',
              isUser: false,
              text:
                  'Erreur lors de l’appel à l’assistant Cas d’usage & orchestration '
                  '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n'
                  '${priorCauses.length > 1 ? priorCauses.join('\n') : cause}',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
            ),
          );
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingUseCaseDomainId = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  Future<bool> _updateSystemsServicesChat(
    String domainId,
    List<SpecChatMessage> Function(List<SpecChatMessage> chat) update,
  ) async {
    final domain = _domainCatalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    if (domain == null) return false;
    final nextMessages = update(domain.systemsServicesChat);
    await updateDomainCatalog(
      _domainCatalog.copyWith(
        domains: [
          for (final item in _domainCatalog.domains)
            if (item.id == domainId)
              item.copyWith(systemsServicesChat: nextMessages)
            else
              item,
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return true;
  }

  /// Envoie un message à l'agent IA « Systèmes & Services » pour [domainId].
  Future<void> sendSystemsServicesMessage(
    String domainId,
    String text, {
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    bool requestsMoreQuestions = false,
  }) async {
    if (_isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && !requestsMoreQuestions) {
      return;
    }
    final filterKind = systemsServicesActiveFilter(domainId);
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions complémentaires pour affiner les '
                    '${filterKind == null ? 'systèmes et services du domaine' : filterKind.pluralLabel.toLowerCase()}.'
              : 'Analyse les pièces jointes et complète les systèmes et services du domaine.');
    await _runSystemsServicesTurn(
      domainId,
      userDisplayText: effectiveText,
      promptInput: effectiveText,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire du chat « Systèmes & Services ».
  Future<void> submitSystemsServicesAskUserAnswers(
    String domainId,
    String messageId,
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    if (_isSending) return;
    final target = systemsServicesChat(
      domainId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final summary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    await _runSystemsServicesTurn(
      domainId,
      userDisplayText: askMore
          ? '$summary\n(+ questions complémentaires demandées)'
          : summary,
      promptInput: summary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
      answered: target.copyWith(
        askUserAnswers: answers,
        askUserUsedDefaults: usedDefaults,
        askUserRequestedMore: askMore,
      ),
    );
  }

  /// Ignore un questionnaire du chat « Systèmes & Services » avec les valeurs par défaut.
  Future<void> skipSystemsServicesAskUser(
    String domainId,
    String messageId,
  ) async {
    if (_isSending) return;
    final target = systemsServicesChat(
      domainId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final defaults = askUser.defaultAnswers();
    await _runSystemsServicesTurn(
      domainId,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput:
          'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}',
      afterAskUserReply: true,
      answered: target.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      ),
    );
  }

  /// Relance le dernier tour en erreur du chat « Systèmes & Services ».
  Future<void> retryLastSystemsServicesTurn(String domainId) async {
    if (_isSending) return;
    final lastUser = systemsServicesChat(domainId).lastWhere(
      (m) => m.isUser,
      orElse: () => SpecChatMessage(
        id: '',
        isUser: true,
        text:
            'La tentative précédente a échoué. Corrige le format JSON et complète la cartographie Systèmes & Services.',
      ),
    );
    await _runSystemsServicesTurn(
      domainId,
      userDisplayText: 'Reprise de la génération suite à erreur…',
      promptInput:
          '${(lastUser.promptText ?? lastUser.text).trim()}\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastUser.attachments,
      afterAskUserReply: false,
    );
  }

  /// Efface l'historique du chat IA « Systèmes & Services » d'un domaine.
  Future<void> clearSystemsServicesChat(String domainId) async {
    if (_isSending) return;
    await _updateSystemsServicesChat(domainId, (_) => const []);
  }

  Future<void> _runSystemsServicesTurn(
    String domainId, {
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    SpecChatMessage? answered,
  }) async {
    final initialDomain = _domainCatalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    if (initialDomain == null) return;

    String buildPrompt(FunctionalDomain domain, {required bool afterReply}) =>
        SystemsServicesAiAgent.buildTurnPrompt(
          domain: domain,
          catalog: _domainCatalog,
          activeFilterKind: systemsServicesActiveFilter(domainId),
          history: domain.systemsServicesChat,
          userInput: promptInput,
          questioningLevel: _questioningLevel,
          afterAskUserReply: afterReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
          activeProject: _project,
          companyGlossary: _companyGlossary,
        );

    var currentPrompt = buildPrompt(
      initialDomain,
      afterReply: afterAskUserReply,
    );
    final userMessage = SpecChatMessage(
      id: 'sysmsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );
    final turnToolTraces = <VibeToolTrace>[];
    final priorCauses = <String>[];
    Future<bool> append(SpecChatMessage message) =>
        _updateSystemsServicesChat(domainId, (chat) => [...chat, message]);

    final activeProject = _project;
    final registry =
        _customToolRegistry ??
        (activeProject != null
            ? SpecForgeToolRegistry.build(
                readProject: () => _project,
                readCompanyGlossary: () => _companyGlossary,
                readModelPreferences: () => _modelPreferences,
                onUpdateProject: (_) async {},
                onNavigateStage: (_) async {},
                toolNames: SystemsServicesAiAgent.toolNames,
              )
            : VibeAppToolRegistry(const []));

    _isSending = true;
    _sendingSystemsServicesDomainId = domainId;
    _stopRequested = false;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus =
        'Cartographie Systèmes & Services (${initialDomain.name})…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    try {
      final started = await _updateSystemsServicesChat(
        domainId,
        (chat) => [
          for (final message in chat)
            if (message.id == answered?.id) answered! else message,
          userMessage,
        ],
      );
      if (!started) return;
      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }
        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.specifications,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour des Systèmes & Services…',
            systemInstructionOverride: SystemsServicesAiAgent.systemInstruction,
            staticGuideOverride: SystemsServicesAiAgent.staticGuide,
            allowedToolNames: activeProject != null
                ? SystemsServicesAiAgent.toolNames
                : const <String>{},
          );
          final traces = List<VibeToolTrace>.unmodifiable(turnToolTraces);
          if (response == null) {
            final partial = parser.snapshot().message?.trim() ?? '';
            await append(
              SpecChatMessage(
                id: 'sysmsg_${shortid.generate()}',
                isUser: false,
                text: partial.isNotEmpty
                    ? '$partial\n\n[Réflexion IA interrompue par l’utilisateur.]'
                    : 'Réflexion IA interrompue par l’utilisateur.',
                toolTraces: traces,
              ),
            );
            return;
          }
          parsedResponse = response;

          final currentDomain = _domainCatalog.domains
              .where((d) => d.id == domainId)
              .firstOrNull;
          if (currentDomain == null) return;
          var nextCatalog = _domainCatalog;
          var patchSummary = '';
          final patch = response.specPatch;
          if (patch != null && patch.isNotEmpty) {
            final applied = SystemsServicesAiAgent.applyPatch(
              nextCatalog,
              domainId: domainId,
              patch: patch,
            );
            nextCatalog = applied.catalog;
            patchSummary = applied.summary;
          }
          final assistantMessage = SpecChatMessage(
            id: 'sysmsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: traces,
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
          );
          await updateDomainCatalog(
            nextCatalog.copyWith(
              domains: [
                for (final item in nextCatalog.domains)
                  if (item.id == domainId)
                    item.copyWith(
                      systemsServicesChat: [
                        ...item.systemsServicesChat,
                        assistantMessage,
                      ],
                    )
                  else
                    item,
              ],
              updatedAt: DateTime.now().toUtc(),
            ),
          );
          return;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );
          saveError(
            '[SpecForge Systèmes & Services IA] Tentative ${attempt + 1}/$maxRecoveryAttempts : $cause',
            stack,
          );
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          final latestDomain = _domainCatalog.domains
              .where((d) => d.id == domainId)
              .firstOrNull;
          if (attempt < maxRecoveryAttempts - 1 &&
              isValidationError &&
              latestDomain != null) {
            final retryProject =
                _project ??
                SpecForgeProject.fromIdea(
                  idea: latestDomain.name,
                  name: latestDomain.name,
                  id: 'sys_retry_$domainId',
                );
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: buildPrompt(
                latestDomain,
                afterReply: afterAskUserReply,
              ),
              priorCauses: priorCauses,
              salvage: SpecSalvageOutcome.none(
                retryProject,
                wasTruncated: parsedResponse == null,
              ),
              rawFailedResponse: parser.rawText,
            );
            continue;
          }
          _lastError = cause;
          await append(
            SpecChatMessage(
              id: 'sysmsg_${shortid.generate()}',
              isUser: false,
              text:
                  'Erreur lors de l’appel à l’assistant Systèmes & Services '
                  '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n'
                  '${priorCauses.length > 1 ? priorCauses.join('\n') : cause}',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
            ),
          );
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingSystemsServicesDomainId = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  static String _valueObjectsScopeKey(
    ValueObjectScope scope,
    String? domainId,
  ) => scope == ValueObjectScope.shared ? 'shared' : 'domain:${domainId ?? ''}';

  /// Retourne l'historique du chat IA du catalogue des Value Objects pour [scope]/[domainId].
  List<SpecChatMessage> valueObjectsChat({
    required ValueObjectScope scope,
    String? domainId,
  }) {
    if (scope == ValueObjectScope.shared) {
      return _domainCatalog.sharedValueObjectsChat;
    }
    return _domainCatalog.domains
            .where((d) => d.id == domainId)
            .firstOrNull
            ?.valueObjectsChat ??
        const <SpecChatMessage>[];
  }

  /// Indique si un tour IA Value Objects est en cours pour [scope]/[domainId].
  bool isSendingValueObjects({
    required ValueObjectScope scope,
    String? domainId,
  }) =>
      _isSending &&
      _sendingValueObjectsKey == _valueObjectsScopeKey(scope, domainId);

  /// Crée ou met à jour un [ValueObjectSpec] dans la portée [scope] (`shared` ou `domain`).
  Future<void> upsertValueObject(
    ValueObjectSpec vo, {
    required ValueObjectScope scope,
    String? domainId,
  }) async {
    vo.validate();
    final now = DateTime.now().toUtc();
    if (scope == ValueObjectScope.shared) {
      final list = List<ValueObjectSpec>.from(_domainCatalog.sharedValueObjects);
      final idx = list.indexWhere((item) => item.id == vo.id);
      if (idx >= 0) {
        list[idx] = vo;
      } else {
        list.add(vo);
      }
      await updateDomainCatalog(
        _domainCatalog.copyWith(sharedValueObjects: list, updatedAt: now),
      );
      return;
    }
    if (domainId == null ||
        !_domainCatalog.domains.any((d) => d.id == domainId)) {
      throw FormatException('Domaine introuvable : $domainId');
    }
    await updateDomainCatalog(
      _domainCatalog.copyWith(
        domains: [
          for (final d in _domainCatalog.domains)
            if (d.id == domainId)
              d.copyWith(
                valueObjects: [
                  for (final item in d.valueObjects)
                    if (item.id == vo.id) vo else item,
                  if (!d.valueObjects.any((item) => item.id == vo.id)) vo,
                ],
              )
            else
              d,
        ],
        updatedAt: now,
      ),
    );
  }

  /// Supprime le Value Object [voId] de la portée [scope]/[domainId].
  Future<void> deleteValueObject(
    String voId, {
    required ValueObjectScope scope,
    String? domainId,
  }) async {
    final now = DateTime.now().toUtc();
    if (scope == ValueObjectScope.shared) {
      await updateDomainCatalog(
        _domainCatalog.copyWith(
          sharedValueObjects: [
            for (final vo in _domainCatalog.sharedValueObjects)
              if (vo.id != voId) vo,
          ],
          updatedAt: now,
        ),
      );
      return;
    }
    if (domainId == null) return;
    await updateDomainCatalog(
      _domainCatalog.copyWith(
        domains: [
          for (final d in _domainCatalog.domains)
            if (d.id == domainId)
              d.copyWith(
                valueObjects: [
                  for (final vo in d.valueObjects)
                    if (vo.id != voId) vo,
                ],
              )
            else
              d,
        ],
        updatedAt: now,
      ),
    );
  }

  /// Importe une sélection de [presets] (en ignorant les doublons de `technicalName`)
  /// dans la portée [scope]/[domainId] et retourne le nombre d'ajouts effectifs.
  Future<int> importValueObjectPresets(
    List<ValueObjectSpec> presets, {
    required ValueObjectScope scope,
    String? domainId,
  }) async {
    final existing = scope == ValueObjectScope.shared
        ? _domainCatalog.sharedValueObjects
        : (_domainCatalog.domains
                  .where((d) => d.id == domainId)
                  .firstOrNull
                  ?.valueObjects ??
              const <ValueObjectSpec>[]);
    final takenTech = {for (final v in existing) v.technicalName.toLowerCase()};
    final takenIds = {
      for (final v in existing) v.id,
      for (final v in _domainCatalog.sharedValueObjects) v.id,
    };
    final toAdd = <ValueObjectSpec>[];
    for (final preset in presets) {
      if (!takenTech.add(preset.technicalName.toLowerCase())) continue;
      var id = preset.id;
      if (takenIds.contains(id)) {
        id = 'vo_${shortid.generate()}';
      }
      takenIds.add(id);
      toAdd.add(preset.copyWith(id: id));
    }
    if (toAdd.isEmpty) return 0;
    final now = DateTime.now().toUtc();
    if (scope == ValueObjectScope.shared) {
      await updateDomainCatalog(
        _domainCatalog.copyWith(
          sharedValueObjects: [...existing, ...toAdd],
          updatedAt: now,
        ),
      );
    } else if (domainId != null) {
      await updateDomainCatalog(
        _domainCatalog.copyWith(
          domains: [
            for (final d in _domainCatalog.domains)
              if (d.id == domainId)
                d.copyWith(valueObjects: [...d.valueObjects, ...toAdd])
              else
                d,
          ],
          updatedAt: now,
        ),
      );
    }
    return toAdd.length;
  }

  /// Déplace un Value Object [voId] entre le Shared Kernel et un domaine.
  Future<void> moveValueObjectScope(
    String voId, {
    required ValueObjectScope fromScope,
    String? fromDomainId,
    required ValueObjectScope toScope,
    String? toDomainId,
  }) async {
    if (fromScope == toScope && fromDomainId == toDomainId) return;
    final sourceList = fromScope == ValueObjectScope.shared
        ? _domainCatalog.sharedValueObjects
        : (_domainCatalog.domains
                  .where((d) => d.id == fromDomainId)
                  .firstOrNull
                  ?.valueObjects ??
              const <ValueObjectSpec>[]);
    final target = sourceList.where((v) => v.id == voId).firstOrNull;
    if (target == null) return;

    var nextShared = List<ValueObjectSpec>.from(
      _domainCatalog.sharedValueObjects,
    );
    var nextDomains = List<FunctionalDomain>.from(_domainCatalog.domains);

    if (fromScope == ValueObjectScope.shared) {
      nextShared = [for (final v in nextShared) if (v.id != voId) v];
    } else {
      nextDomains = [
        for (final d in nextDomains)
          if (d.id == fromDomainId)
            d.copyWith(
              valueObjects: [
                for (final v in d.valueObjects)
                  if (v.id != voId) v,
              ],
            )
          else
            d,
      ];
    }

    if (toScope == ValueObjectScope.shared) {
      nextShared.add(target);
    } else {
      if (toDomainId == null || !nextDomains.any((d) => d.id == toDomainId)) {
        throw FormatException('Domaine cible introuvable : $toDomainId');
      }
      nextDomains = [
        for (final d in nextDomains)
          if (d.id == toDomainId)
            d.copyWith(valueObjects: [...d.valueObjects, target])
          else
            d,
      ];
    }

    await updateDomainCatalog(
      _domainCatalog.copyWith(
        sharedValueObjects: nextShared,
        domains: nextDomains,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Crée (ou réutilise) [valueObject] dans [scope] et remplace atomiquement
  /// l'attribut à [attributePath] du modèle [entryId] par ce Value Object.
  Future<void> promoteAttributeToValueObject({
    required String domainId,
    required String entryId,
    required List<String> attributePath,
    required ValueObjectSpec valueObject,
    required ValueObjectScope scope,
    bool createIfMissing = true,
  }) async {
    final domain = _domainCatalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    final contracts = domain?.contracts;
    final entry = contracts?.entryById(entryId);
    if (domain == null || contracts == null || entry == null) return;

    var catalog = _domainCatalog;
    var effectiveVoId = valueObject.id;

    if (createIfMissing) {
      valueObject.validate();
      final existingList = scope == ValueObjectScope.shared
          ? catalog.sharedValueObjects
          : domain.valueObjects;
      final existingSameTech = existingList
          .where(
            (v) =>
                v.id == valueObject.id ||
                v.technicalName.toLowerCase() ==
                    valueObject.technicalName.toLowerCase(),
          )
          .firstOrNull;
      if (existingSameTech != null) {
        effectiveVoId = existingSameTech.id;
      } else if (scope == ValueObjectScope.shared) {
        catalog = catalog.copyWith(
          sharedValueObjects: [...catalog.sharedValueObjects, valueObject],
        );
      } else {
        catalog = catalog.copyWith(
          domains: [
            for (final d in catalog.domains)
              if (d.id == domainId)
                d.copyWith(valueObjects: [...d.valueObjects, valueObject])
              else
                d,
          ],
        );
      }
    }

    final currentObject = contracts.objectFor(entry);
    final updatedObject = ValueObjectPrimitiveDetector.replaceAttributeAtPath(
      currentObject,
      attributePath,
      valueObjectId: effectiveVoId,
    );
    final updatedContracts = contracts.withModel(entryId, object: updatedObject);
    await updateDomainCatalog(
      catalog.copyWith(
        domains: [
          for (final d in catalog.domains)
            if (d.id == domainId) d.copyWith(contracts: updatedContracts) else d,
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Remplace l'attribut à [attributePath] du modèle [entryId] par un VO existant [valueObjectId].
  Future<void> replaceAttributeWithExistingValueObject({
    required String domainId,
    required String entryId,
    required List<String> attributePath,
    required String valueObjectId,
  }) async {
    final domain = _domainCatalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    final contracts = domain?.contracts;
    final entry = contracts?.entryById(entryId);
    if (domain == null || contracts == null || entry == null) return;
    final updatedObject = ValueObjectPrimitiveDetector.replaceAttributeAtPath(
      contracts.objectFor(entry),
      attributePath,
      valueObjectId: valueObjectId,
    );
    await updateDomainModelObject(domainId, updatedObject);
  }

  Future<bool> _updateValueObjectsChat(
    ValueObjectScope scope,
    String? domainId,
    List<SpecChatMessage> Function(List<SpecChatMessage> chat) transform,
  ) async {
    final now = DateTime.now().toUtc();
    if (scope == ValueObjectScope.shared) {
      await updateDomainCatalog(
        _domainCatalog.copyWith(
          sharedValueObjectsChat: transform(
            _domainCatalog.sharedValueObjectsChat,
          ),
          updatedAt: now,
        ),
      );
      return true;
    }
    final domain = _domainCatalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    if (domain == null) return false;
    await updateDomainCatalog(
      _domainCatalog.copyWith(
        domains: [
          for (final d in _domainCatalog.domains)
            if (d.id == domainId)
              d.copyWith(valueObjectsChat: transform(d.valueObjectsChat))
            else
              d,
        ],
        updatedAt: now,
      ),
    );
    return true;
  }

  /// Envoie un message à l'agent IA du Catalogue des Value Objects.
  Future<void> sendValueObjectsMessage({
    required ValueObjectScope scope,
    String? domainId,
    required String text,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    bool requestsMoreQuestions = false,
  }) async {
    if (_isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && !requestsMoreQuestions) {
      return;
    }
    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : (requestsMoreQuestions
              ? 'Pose-moi des questions pour concevoir et affiner les Value Objects hexagonaux.'
              : 'Analyse les pièces jointes et complète le catalogue des Value Objects.');
    await _runValueObjectsTurn(
      scope: scope,
      domainId: domainId,
      userDisplayText: effectiveText,
      promptInput: effectiveText,
      attachments: attachments,
      afterAskUserReply: false,
      forceFollowUpQuestions: requestsMoreQuestions,
    );
  }

  /// Soumet les réponses d'un questionnaire du chat Value Objects.
  Future<void> submitValueObjectsAskUserAnswers({
    required ValueObjectScope scope,
    String? domainId,
    required String messageId,
    required Map<String, Object?> answers,
    bool usedDefaults = false,
    bool askMore = false,
  }) async {
    if (_isSending) return;
    final target = valueObjectsChat(
      scope: scope,
      domainId: domainId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final summary =
        'Réponses enregistrées :\n${askUser.formatDisplaySummary(answers, usedDefaults: usedDefaults)}';
    await _runValueObjectsTurn(
      scope: scope,
      domainId: domainId,
      userDisplayText: askMore
          ? '$summary\n(+ questions complémentaires demandées)'
          : summary,
      promptInput: summary,
      afterAskUserReply: !askMore,
      forceFollowUpQuestions: askMore,
      answered: target.copyWith(
        askUserAnswers: answers,
        askUserUsedDefaults: usedDefaults,
        askUserRequestedMore: askMore,
      ),
    );
  }

  /// Ignore un questionnaire du chat Value Objects en appliquant les valeurs par défaut.
  Future<void> skipValueObjectsAskUser({
    required ValueObjectScope scope,
    String? domainId,
    required String messageId,
  }) async {
    if (_isSending) return;
    final target = valueObjectsChat(
      scope: scope,
      domainId: domainId,
    ).where((m) => m.id == messageId).firstOrNull;
    final askUser = target?.askUser;
    if (target == null || askUser == null) return;
    final defaults = askUser.defaultAnswers();
    await _runValueObjectsTurn(
      scope: scope,
      domainId: domainId,
      userDisplayText: 'Valeurs par défaut appliquées.',
      promptInput:
          'Valeurs par défaut retenues :\n${askUser.formatDisplaySummary(defaults, usedDefaults: true)}',
      afterAskUserReply: true,
      answered: target.copyWith(
        askUserAnswers: defaults,
        askUserUsedDefaults: true,
        askUserDismissed: true,
      ),
    );
  }

  /// Relance le dernier tour en erreur du chat Value Objects.
  Future<void> retryLastValueObjectsTurn({
    required ValueObjectScope scope,
    String? domainId,
  }) async {
    if (_isSending) return;
    final lastUser = valueObjectsChat(scope: scope, domainId: domainId)
        .lastWhere(
          (m) => m.isUser,
          orElse: () => SpecChatMessage(
            id: '',
            isUser: true,
            text:
                'La tentative précédente a échoué. Corrige le format JSON et mets à jour le catalogue des Value Objects.',
          ),
        );
    await _runValueObjectsTurn(
      scope: scope,
      domainId: domainId,
      userDisplayText: 'Reprise de la génération suite à erreur…',
      promptInput:
          '${(lastUser.promptText ?? lastUser.text).trim()}\n\nNOTE DE REPRISE : corrige l’erreur précédente et renvoie strictement un JSON valide.',
      attachments: lastUser.attachments,
      afterAskUserReply: false,
    );
  }

  /// Efface l'historique du chat Value Objects pour [scope]/[domainId].
  Future<void> clearValueObjectsChat({
    required ValueObjectScope scope,
    String? domainId,
  }) async {
    if (_isSending) return;
    await _updateValueObjectsChat(scope, domainId, (_) => const []);
  }

  Future<void> _runValueObjectsTurn({
    required ValueObjectScope scope,
    String? domainId,
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    SpecChatMessage? answered,
  }) async {
    final initialDomain = scope == ValueObjectScope.domain
        ? _domainCatalog.domains.where((d) => d.id == domainId).firstOrNull
        : null;
    if (scope == ValueObjectScope.domain && initialDomain == null) return;

    String buildPrompt({required bool afterReply}) {
      final currentDomain = scope == ValueObjectScope.domain
          ? _domainCatalog.domains.where((d) => d.id == domainId).firstOrNull
          : null;
      return ValueObjectsAiAgent.buildTurnPrompt(
        catalog: _domainCatalog,
        scope: scope,
        domain: currentDomain,
        history: valueObjectsChat(scope: scope, domainId: domainId),
        userInput: promptInput,
        modelPreferences: _modelPreferences,
        questioningLevel: _questioningLevel,
        afterAskUserReply: afterReply,
        forceFollowUpQuestions: forceFollowUpQuestions,
        activeProject: _project,
        companyGlossary: _companyGlossary,
      );
    }

    var currentPrompt = buildPrompt(afterReply: afterAskUserReply);
    final userMessage = SpecChatMessage(
      id: 'vomsg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
      attachments: attachments,
      requestsMoreQuestions: forceFollowUpQuestions,
    );
    final turnToolTraces = <VibeToolTrace>[];
    final priorCauses = <String>[];
    Future<bool> append(SpecChatMessage message) =>
        _updateValueObjectsChat(scope, domainId, (chat) => [...chat, message]);

    final activeProject = _project;
    final registry =
        _customToolRegistry ??
        (activeProject != null
            ? SpecForgeToolRegistry.build(
                readProject: () => _project,
                readCompanyGlossary: () => _companyGlossary,
                readModelPreferences: () => _modelPreferences,
                onUpdateProject: (_) async {},
                onNavigateStage: (_) async {},
                toolNames: ValueObjectsAiAgent.toolNames,
              )
            : VibeAppToolRegistry(const []));

    _isSending = true;
    _sendingValueObjectsKey = _valueObjectsScopeKey(scope, domainId);
    _stopRequested = false;
    _sendingStage = null;
    _streamingMessage = null;
    _streamingStatus = scope == ValueObjectScope.shared
        ? 'Conception des Value Objects (Shared Kernel)…'
        : 'Conception des Value Objects (${initialDomain!.name})…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    try {
      final started = await _updateValueObjectsChat(
        scope,
        domainId,
        (chat) => [
          for (final message in chat)
            if (message.id == answered?.id) answered! else message,
          userMessage,
        ],
      );
      if (!started) return;

      for (var attempt = 0; attempt < maxRecoveryAttempts; attempt++) {
        if (_stopRequested) break;
        if (attempt > 0) {
          _streamingMessage = null;
          _streamingStatus =
              'Reprise automatique (${attempt + 1}/$maxRecoveryAttempts)…';
          notifyListeners();
        }
        final parser = SpecStreamParser();
        SpecAgentResponse? parsedResponse;
        try {
          final response = await _streamAgentResponse(
            parser: parser,
            stage: SpecForgeStage.businessObjects,
            prompt: currentPrompt,
            attachments: attachments,
            registry: registry,
            toolTraces: turnToolTraces,
            patchStatus: 'Mise à jour du catalogue des Value Objects…',
            systemInstructionOverride: ValueObjectsAiAgent.systemInstruction,
            staticGuideOverride: ValueObjectsAiAgent.staticGuide,
            allowedToolNames: activeProject != null
                ? ValueObjectsAiAgent.toolNames
                : const <String>{},
          );
          final traces = List<VibeToolTrace>.unmodifiable(turnToolTraces);
          if (response == null) {
            final partial = parser.snapshot().message?.trim() ?? '';
            await append(
              SpecChatMessage(
                id: 'vomsg_${shortid.generate()}',
                isUser: false,
                text: partial.isNotEmpty
                    ? '$partial\n\n[Réflexion IA interrompue par l’utilisateur.]'
                    : 'Réflexion IA interrompue par l’utilisateur.',
                toolTraces: traces,
              ),
            );
            return;
          }
          parsedResponse = response;

          var nextCatalog = _domainCatalog;
          var patchSummary = '';
          final patch = response.specPatch;
          if (patch != null && patch.isNotEmpty) {
            final applied = ValueObjectsAiAgent.applyPatch(
              nextCatalog,
              scope: scope,
              domainId: domainId,
              patch: patch,
            );
            nextCatalog = applied.catalog;
            patchSummary = applied.summary;
          }
          final assistantMessage = SpecChatMessage(
            id: 'vomsg_${shortid.generate()}',
            isUser: false,
            text: response.message,
            toolTraces: traces,
            askUser: response.askUser,
            appliedPatchSummary: patchSummary,
          );
          if (scope == ValueObjectScope.shared) {
            await updateDomainCatalog(
              nextCatalog.copyWith(
                sharedValueObjectsChat: [
                  ...nextCatalog.sharedValueObjectsChat,
                  assistantMessage,
                ],
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          } else {
            await updateDomainCatalog(
              nextCatalog.copyWith(
                domains: [
                  for (final item in nextCatalog.domains)
                    if (item.id == domainId)
                      item.copyWith(
                        valueObjectsChat: [
                          ...item.valueObjectsChat,
                          assistantMessage,
                        ],
                      )
                    else
                      item,
                ],
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }
          return;
        } catch (error, stack) {
          final cause = _describeErrorCause(error);
          priorCauses.add(
            'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
          );
          saveError(
            '[SpecForge Value Objects IA] Tentative ${attempt + 1}/$maxRecoveryAttempts : $cause',
            stack,
          );
          final isValidationError =
              error is FormatException ||
              error is ArgumentError ||
              error is StateError;
          if (attempt < maxRecoveryAttempts - 1 && isValidationError) {
            final retryProject =
                _project ??
                SpecForgeProject.fromIdea(
                  idea: initialDomain?.name ?? 'Shared Kernel',
                  name: initialDomain?.name ?? 'Shared Kernel',
                  id: 'vo_retry_${domainId ?? 'shared'}',
                );
            currentPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: buildPrompt(afterReply: afterAskUserReply),
              priorCauses: priorCauses,
              salvage: SpecSalvageOutcome.none(
                retryProject,
                wasTruncated: parsedResponse == null,
              ),
              rawFailedResponse: parser.rawText,
            );
            continue;
          }
          _lastError = cause;
          await append(
            SpecChatMessage(
              id: 'vomsg_${shortid.generate()}',
              isUser: false,
              text:
                  'Erreur lors de l’appel à l’assistant Value Objects '
                  '(${attempt + 1}/$maxRecoveryAttempts tentative(s)) :\n'
                  '${priorCauses.length > 1 ? priorCauses.join('\n') : cause}',
              toolTraces: List<VibeToolTrace>.unmodifiable(turnToolTraces),
              failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
            ),
          );
          return;
        } finally {
          _activeStreamSubscription = null;
          _activeStreamCompleter = null;
        }
      }
    } finally {
      _activeStreamSubscription = null;
      _activeStreamCompleter = null;
      _stopRequested = false;
      _isSending = false;
      _sendingValueObjectsKey = null;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
  }

  void _pushGlossaryUndo(CompanyGlossary snapshot) {
    _glossaryUndoStack.add(snapshot);
    if (_glossaryUndoStack.length > 40) {
      _glossaryUndoStack.removeAt(0);
    }
    _glossaryRedoStack.clear();
  }

  Future<void> _persistGlossary(CompanyGlossary glossary) async {
    final gen = ++_saveGeneration;
    _isSaving = true;
    notifyListeners();
    try {
      await _glossaryStore.saveGlossary(glossary);
    } finally {
      if (gen == _saveGeneration) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// Met à jour les préférences et règles techniques globales puis persiste sur disque.
  Future<void> updateModelPreferences(
    BusinessObjectModelPreferences updated, {
    bool recordUndo = true,
  }) async {
    updated.validate();
    if (updated == _modelPreferences) return;
    if (recordUndo) {
      _modelPrefsUndoStack.add(_modelPreferences);
      if (_modelPrefsUndoStack.length > 40) {
        _modelPrefsUndoStack.removeAt(0);
      }
      _modelPrefsRedoStack.clear();
    }
    _modelPreferences = updated;
    notifyListeners();
    await _persistModelPreferences(updated);
  }

  /// Ajoute ou met à jour une règle technique dans le dictionnaire global.
  Future<void> upsertTechnicalRule(TechnicalModelingRule rule) {
    rule.validate();
    final rules = List<TechnicalModelingRule>.from(
      _modelPreferences.technicalRules,
    );
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      rules[idx] = rule;
    } else {
      rules.add(rule);
    }
    return updateModelPreferences(
      _modelPreferences.copyWith(technicalRules: rules),
    );
  }

  /// Supprime une règle technique du dictionnaire global par [ruleId].
  Future<void> deleteTechnicalRule(String ruleId) {
    final next = _modelPreferences.technicalRules
        .where((r) => r.id != ruleId)
        .toList();
    return updateModelPreferences(
      _modelPreferences.copyWith(technicalRules: next),
    );
  }

  /// Réinitialise le dictionnaire technique et les préférences globales par défaut.
  Future<void> resetModelPreferencesToDefaults() =>
      updateModelPreferences(BusinessObjectModelPreferences.defaults);

  /// Annule la dernière modification du dictionnaire technique global.
  Future<void> undoModelPreferences() async {
    if (_modelPrefsUndoStack.isEmpty) return;
    final previous = _modelPrefsUndoStack.removeLast();
    _modelPrefsRedoStack.add(_modelPreferences);
    _modelPreferences = previous;
    notifyListeners();
    await _persistModelPreferences(previous);
  }

  /// Rétablit la dernière modification annulée du dictionnaire technique global.
  Future<void> redoModelPreferences() async {
    if (_modelPrefsRedoStack.isEmpty) return;
    final next = _modelPrefsRedoStack.removeLast();
    _modelPrefsUndoStack.add(_modelPreferences);
    _modelPreferences = next;
    notifyListeners();
    await _persistModelPreferences(next);
  }

  /// Convertit rétroactivement les identifiants/énums du projet actif selon les règles globales.
  Future<bool> applyModelCaseToActiveProject({
    bool applyAttributeCase = true,
    bool applyEnumCase = true,
  }) async {
    final current = _project;
    if (current == null || current.businessObjects.isEmpty) return false;
    final attrCase = applyAttributeCase
        ? _modelPreferences.attributeCase
        : null;
    final enumCase = applyEnumCase ? _modelPreferences.enumCase : null;
    if (attrCase == null && enumCase == null) return false;

    List<BusinessAttribute> convertAttrs(List<BusinessAttribute> list) {
      final used = <String>{};
      return [
        for (final attr in list)
          () {
            final base = attrCase != null
                ? attrCase.formatIdentifier(attr.name)
                : attr.name;
            var candidate = base;
            var suffix = 2;
            while (!used.add(candidate)) {
              candidate = '${base}_$suffix';
              suffix++;
            }
            final nextEnumValues =
                enumCase != null && attr.enumValues.isNotEmpty
                ? [for (final v in attr.enumValues) enumCase.formatValue(v)]
                : attr.enumValues;
            return attr.copyWith(
              name: candidate,
              enumValues: nextEnumValues,
              children: attr.children.isEmpty
                  ? const []
                  : convertAttrs(attr.children),
            );
          }(),
      ];
    }

    final updatedObjects = [
      for (final obj in current.businessObjects)
        obj.copyWith(
          attributes: convertAttrs(obj.attributes),
          relations: attrCase == null
              ? obj.relations
              : [
                  for (final rel in obj.relations)
                    rel.copyWith(name: attrCase.formatIdentifier(rel.name)),
                ],
          lifecycleStates: enumCase == null
              ? obj.lifecycleStates
              : [
                  for (final st in obj.lifecycleStates)
                    st.copyWith(name: enumCase.formatValue(st.name)),
                ],
          lifecycleTransitions: enumCase == null
              ? obj.lifecycleTransitions
              : [
                  for (final tr in obj.lifecycleTransitions)
                    tr.copyWith(
                      fromState: enumCase.formatValue(tr.fromState),
                      toState: enumCase.formatValue(tr.toState),
                    ),
                ],
        ),
    ];

    if (listEquals(updatedObjects, current.businessObjects)) return false;
    await updateProject(current.copyWith(businessObjects: updatedObjects));
    return true;
  }

  Future<void> _persistModelPreferences(
    BusinessObjectModelPreferences prefs,
  ) async {
    final gen = ++_saveGeneration;
    _isSaving = true;
    notifyListeners();
    try {
      await _modelDictionaryStore.save(prefs);
    } finally {
      if (gen == _saveGeneration) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// Met à jour la grille tarifaire TJM d'entreprise et la persiste sur disque.
  Future<void> updateEnterpriseRateCard(
    EnterpriseRateCard updated, {
    bool recordUndo = true,
  }) async {
    updated.validate();
    if (updated == _enterpriseRateCard) return;
    if (recordUndo) {
      _rateCardUndoStack.add(_enterpriseRateCard);
      if (_rateCardUndoStack.length > 40) {
        _rateCardUndoStack.removeAt(0);
      }
      _rateCardRedoStack.clear();
    }
    _enterpriseRateCard = updated;
    notifyListeners();
    await _persistEnterpriseRateCard(updated);
  }

  /// Réinitialise la grille tarifaire TJM d'entreprise aux valeurs par défaut.
  Future<void> resetEnterpriseRateCardToDefaults() =>
      updateEnterpriseRateCard(EnterpriseRateCard.defaults);

  /// Annule la dernière modification de la grille tarifaire d'entreprise.
  Future<void> undoEnterpriseRateCard() async {
    if (_rateCardUndoStack.isEmpty) return;
    final previous = _rateCardUndoStack.removeLast();
    _rateCardRedoStack.add(_enterpriseRateCard);
    _enterpriseRateCard = previous;
    notifyListeners();
    await _persistEnterpriseRateCard(previous);
  }

  /// Rétablit la dernière modification annulée de la grille tarifaire d'entreprise.
  Future<void> redoEnterpriseRateCard() async {
    if (_rateCardRedoStack.isEmpty) return;
    final next = _rateCardRedoStack.removeLast();
    _rateCardUndoStack.add(_enterpriseRateCard);
    _enterpriseRateCard = next;
    notifyListeners();
    await _persistEnterpriseRateCard(next);
  }

  Future<void> _persistEnterpriseRateCard(EnterpriseRateCard card) async {
    final gen = ++_saveGeneration;
    _isSaving = true;
    notifyListeners();
    try {
      await _enterpriseRateCardStore.save(card);
    } finally {
      if (gen == _saveGeneration) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> _persistProject(SpecForgeProject project) async {
    final gen = ++_saveGeneration;
    _isSaving = true;
    notifyListeners();
    try {
      await _store.saveProject(project);
      _recentProjects = await _store.listProjects();
    } finally {
      if (gen == _saveGeneration) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }
}
