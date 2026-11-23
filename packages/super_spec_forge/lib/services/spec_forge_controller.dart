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
import '../ai/domain_layer_ai.dart';
import '../ai/domain_model_ai.dart';
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
import '../ai/ux_patch_applier.dart';
import '../ai/ux_prompt_builder.dart';
import '../ai/ux_stage_agent.dart';
import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/company_glossary.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/domain_layer_spec.dart';
import '../models/qa/qa_coherence_issue.dart';
import '../models/qa/qa_forge_spec.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_lexicon.dart';
import '../models/spec_stage_chat.dart';
import '../models/technical_modeling_rule.dart';
import '../models/ux/ux_coherence_issue.dart';
import '../models/ux/ux_forge_spec.dart';
import '../models/ux/ux_forge_stage.dart';
import '../models/ux/ux_screen_spec.dart';
import 'business_object_operations.dart';
import 'company_glossary_store.dart';
import 'domain_catalog_store.dart';
import 'example_mapping_operations.dart';
import 'exporters/qa_tdd_prompt_exporter.dart';
import 'model_dictionary_store.dart';
import 'qa_coherence_analyzer.dart';
import 'spec_coherence_analyzer.dart';
import 'spec_design_promoter.dart';
import 'spec_project_store.dart';
import 'spec_workspace_store.dart';
import 'ux_coherence_analyzer.dart';

/// Orchestre l'état du projet actif, l'historique Undo/Redo, la persistance et les échanges IA.
class SpecForgeController extends ChangeNotifier {
  /// Nombre maximal de tentatives automatiques en cas d'exception de parsing ou validation IA.
  static const int maxRecoveryAttempts = 3;

  /// Nombre maximal de tours d'appels d'outils par tentative IA.
  static const int maxToolRounds = 6;

  /// Crée un contrôleur avec workspace, stores, service IA et registre d'outils injectables.
  SpecForgeController({
    SpecProjectStore? store,
    CompanyGlossaryStore? glossaryStore,
    ModelDictionaryStore? modelDictionaryStore,
    DomainCatalogStore? domainCatalogStore,
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
           domainCatalogStore != null,
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
  DomainCatalog _domainCatalog = DomainCatalog.empty;
  final List<BusinessObjectModelPreferences> _modelPrefsUndoStack =
      <BusinessObjectModelPreferences>[];
  final List<BusinessObjectModelPreferences> _modelPrefsRedoStack =
      <BusinessObjectModelPreferences>[];

  VibeAiSpeedMode _speedMode;
  VibeQuestioningLevel _questioningLevel;

  bool _isSending = false;
  bool _sendingGlobalQuestion = false;
  bool _sendingGlossary = false;

  /// `domaine/entrée` du modèle dont le tour IA est en cours.
  String? _sendingDomainModelKey;
  SpecForgeStage? _sendingStage;
  UxForgeStage? _sendingUxStage;
  QaForgeStage? _sendingQaStage;
  String? _streamingMessage;
  String _streamingStatus = '';
  List<VibeToolTrace> _streamingToolTraces = const <VibeToolTrace>[];
  String? _focusedObjectId;
  List<String> _focusedAttributePath = const <String>[];
  String _businessObjectFilter = '';
  String? _focusedExampleStoryId;
  String? _focusedJourneyId;
  String? _focusedRouteId;
  String? _focusedScreenId;
  UxLayoutZoneName? _focusedScreenZone;
  String? _focusedFixtureId;
  String? _focusedFeatureId;
  String? _focusedScenarioId;
  String? _focusedTddSuiteId;

  /// Sélection et filtre de l'arbre de chaque fiche, indexés par `domaine/entrée`.
  final Map<String, ({List<String> attributePath, String filter})>
  _domainModelFocus = {};

  /// `domaine/entrée` dont le tour IA de la couche Domain est en cours.
  String? _sendingDomainLayerKey;

  /// Onglet actif de la page Couche Domain, indexé par `domaine/entrée`.
  final Map<String, DomainLayerTab> _domainLayerActiveTab = {};
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

  /// Magasin disque du catalogue de domaines.
  DomainCatalogStore get domainCatalogStore => _domainCatalogStore;

  /// Indique si un Undo est disponible sur le dictionnaire technique.
  bool get canUndoModelPreferences => _modelPrefsUndoStack.isNotEmpty;

  /// Indique si un Redo est disponible sur le dictionnaire technique.
  bool get canRedoModelPreferences => _modelPrefsRedoStack.isNotEmpty;

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

  /// Met à jour le tableau Example Mapping sélectionné dans l'atelier.
  void focusExampleStory(String? storyId) {
    if (_focusedExampleStoryId == storyId) return;
    _focusedExampleStoryId = storyId;
    notifyListeners();
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
  }

  void _clearProjectFocusState() {
    _focusedObjectId = null;
    _focusedAttributePath = const <String>[];
    _businessObjectFilter = '';
    _focusedExampleStoryId = null;
    _focusedJourneyId = null;
    _focusedRouteId = null;
    _focusedScreenId = null;
    _focusedScreenZone = null;
    _focusedFixtureId = null;
    _focusedFeatureId = null;
    _focusedScenarioId = null;
    _focusedTddSuiteId = null;
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
    _domainCatalog = DomainCatalog.empty;
    _modelPrefsUndoStack.clear();
    _modelPrefsRedoStack.clear();
    _clearProjectFocusState();
    _domainModelFocus.clear();
    _domainLayerActiveTab.clear();
    _sendingDomainLayerKey = null;
    _lastError = null;
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
  }) async {
    final trimmedCode = domainCode.trim();
    if (_domainCatalog.domains.any((d) => d.domainCode == trimmedCode)) {
      throw const FormatException('Ce code de domaine existe déjà.');
    }
    final domain = FunctionalDomain(
      id: 'domain_${shortid.generate()}',
      domainCode: trimmedCode,
      name: name.trim(),
      description: description.trim(),
      isActive: isActive,
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
    _project = updated;
    notifyListeners();
    await _persistProject(updated);
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
        SpecForgeStage.businessObjects =>
          'Modéliser les objets métiers à partir du cahier des charges.',
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
      modelPreferencesOverride: _modelPreferences,
      focusedObjectId: _focusedObjectId,
      focusedAttributePath: _focusedAttributePath,
      businessObjectFilter: _businessObjectFilter,
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
              modelPreferencesOverride: _modelPreferences,
              focusedObjectId: _focusedObjectId,
              focusedAttributePath: _focusedAttributePath,
              businessObjectFilter: _businessObjectFilter,
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
                      !SpecForgeToolRegistry.qaToolNames.contains(decl.name)))
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
