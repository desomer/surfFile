/// Contrôleur réactif principal du wizard `super_spec_forge` ([SpecForgeController]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../ai/spec_ai_service.dart';
import '../ai/spec_patch_applier.dart';
import '../ai/spec_prompt_builder.dart';
import '../ai/spec_stream_parser.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_stage_chat.dart';
import 'spec_coherence_analyzer.dart';
import 'spec_project_store.dart';

/// Orchestre l'état du projet actif, l'historique Undo/Redo, la persistance et les échanges IA.
class SpecForgeController extends ChangeNotifier {
  /// Crée un contrôleur avec store et service IA injectables (pratique pour les tests).
  SpecForgeController({
    SpecProjectStore? store,
    SpecAiService? aiService,
    VibeAiSpeedMode initialSpeedMode = VibeAiSpeedMode.fast,
    VibeQuestioningLevel initialQuestioningLevel =
        VibeQuestioningLevel.balanced,
  }) : _store = store ?? SpecProjectStore(),
       _aiService = aiService ?? const GeminiSpecAiService(),
       _speedMode = initialSpeedMode,
       _questioningLevel = initialQuestioningLevel;

  final SpecProjectStore _store;
  final SpecAiService _aiService;

  SpecForgeProject? _project;
  List<SpecProjectSummary> _recentProjects = const <SpecProjectSummary>[];
  final List<SpecForgeProject> _undoStack = <SpecForgeProject>[];
  final List<SpecForgeProject> _redoStack = <SpecForgeProject>[];

  VibeAiSpeedMode _speedMode;
  VibeQuestioningLevel _questioningLevel;

  bool _isSending = false;
  SpecForgeStage? _sendingStage;
  String? _streamingMessage;
  String _streamingStatus = '';
  String? _lastError;
  bool _isSaving = false;
  int _saveGeneration = 0;

  /// Magasin disque associé.
  SpecProjectStore get store => _store;

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

  /// Étape en cours de génération IA.
  SpecForgeStage? get sendingStage => _sendingStage;

  /// Texte streaming reçu jusqu'ici pour le message en cours.
  String? get streamingMessage => _streamingMessage;

  /// Indicateur d'activité streaming (ex. « Rédaction des questions… »).
  String get streamingStatus => _streamingStatus;

  /// Dernière erreur rencontrée, le cas échéant.
  String? get lastError => _lastError;

  /// Vrai lorsqu'une sauvegarde disque est en cours.
  bool get isSaving => _isSaving;

  /// Indique si un retour arrière Undo est disponible.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Indique si un rétablissement Redo est disponible.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Charge la liste des projets récents et restaure optionnellement le dernier projet actif.
  Future<void> initialize({bool restoreLastProject = true}) async {
    _recentProjects = await _store.listProjects();
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

  /// Crée un nouveau projet à partir de [idea], le sauvegarde et lance automatiquement
  /// l'étape 1 si [autoKickoff] vaut `true`.
  Future<void> createProjectFromIdea({
    required String idea,
    String? name,
    bool autoKickoff = true,
  }) async {
    final created = SpecForgeProject.fromIdea(idea: idea, name: name);
    _undoStack.clear();
    _redoStack.clear();
    _lastError = null;
    _project = created;
    await _persistProject(created);
    notifyListeners();

    if (autoKickoff) {
      await kickoffStageIfEmpty(SpecForgeStage.vision);
    }
  }

  /// Ouvre un projet existant par son identifiant.
  Future<void> openProject(String projectId) async {
    final loaded = await _store.loadProject(projectId);
    if (loaded == null) return;
    _undoStack.clear();
    _redoStack.clear();
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
  /// lance l'agent spécialisé de [targetStage] si sa conversation est vide.
  Future<void> goToStage(
    SpecForgeStage targetStage, {
    bool validateCurrent = false,
    bool autoKickoffIfEmpty = true,
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
    );
    await _runAgentTurn(
      stage: stage,
      userDisplayText: switch (stage) {
        SpecForgeStage.vision => 'Idée initiale : ${current.initialIdea}',
        SpecForgeStage.specifications =>
          'Démarrer le cahier des charges à partir du cadrage.',
        SpecForgeStage.businessObjects =>
          'Modéliser les objets métiers à partir du cahier des charges.',
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

  /// Envoie un message utilisateur libre à l'agent de l'étape courante.
  Future<void> sendUserMessage(
    String text, {
    bool requestsMoreQuestions = false,
  }) async {
    final current = _project;
    if (current == null || _isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !requestsMoreQuestions) return;
    final stage = current.currentStage;
    final effectiveDisplay = trimmed.isEmpty
        ? 'Pose-moi des questions complémentaires pour approfondir cette étape.'
        : trimmed;
    await _runAgentTurn(
      stage: stage,
      userDisplayText: effectiveDisplay,
      promptInput: effectiveDisplay,
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

  /// Exécute immédiatement l'analyse de cohérence locale déterministe.
  List<SpecCoherenceIssue> runLocalCoherenceAudit() {
    final current = _project;
    if (current == null) return const <SpecCoherenceIssue>[];
    return SpecCoherenceAnalyzer.analyze(current);
  }

  Future<void> _runAgentTurn({
    required SpecForgeStage stage,
    required String userDisplayText,
    required String promptInput,
    required bool afterAskUserReply,
    required bool forceFollowUpQuestions,
  }) async {
    final initialProject = _project;
    if (initialProject == null) return;

    final userMessage = SpecChatMessage(
      id: 'msg_${shortid.generate()}',
      isUser: true,
      text: userDisplayText,
      promptText: promptInput,
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
    _sendingStage = stage;
    _streamingMessage = null;
    _streamingStatus = 'Analyse par ${stage.agentTitle}…';
    _lastError = null;
    notifyListeners();

    final prompt = SpecPromptBuilder.buildTurnPrompt(
      project: initialProject,
      stage: stage,
      userInput: promptInput,
      questioningLevel: _questioningLevel,
      afterAskUserReply: afterAskUserReply,
      forceFollowUpQuestions: forceFollowUpQuestions,
    );

    final parser = SpecStreamParser();
    try {
      await for (final event in _aiService.streamTurn(
        stage: stage,
        prompt: prompt,
        speedMode: _speedMode,
      )) {
        if (event.deltaText.isNotEmpty) {
          final snap = parser.addChunk(event.deltaText);
          _streamingMessage = snap.message;
          if (snap.hasAskUser) {
            _streamingStatus = 'Préparation des questions…';
          } else if (snap.hasSpecPatch) {
            _streamingStatus = 'Structuration des spécifications…';
          } else if (snap.message != null) {
            _streamingStatus = 'Rédaction en cours…';
          }
          notifyListeners();
        }
      }

      final response = SpecAgentResponse.parse(parser.rawText);
      final latestProject = _project ?? withUserMsg;
      var updatedProject = latestProject;
      var patchSummary = '';

      if (response.specPatch != null && response.specPatch!.isNotEmpty) {
        _pushUndo(latestProject);
        final applied = SpecPatchApplier.apply(
          latestProject,
          response.specPatch!,
        );
        updatedProject = applied.project;
        patchSummary = applied.summary;
      }

      final assistantMessage = SpecChatMessage(
        id: 'msg_${shortid.generate()}',
        isUser: false,
        text: response.message,
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
              response.stageReadyToAdvance || currentStageState.readyToAdvance,
        ),
      );

      _project = updatedProject;
      await _persistProject(updatedProject);
    } catch (error) {
      final latestProject = _project ?? withUserMsg;
      final errMessage = SpecChatMessage(
        id: 'msg_${shortid.generate()}',
        isUser: false,
        text: 'Erreur lors de l’appel à ${stage.agentTitle} : $error',
        failedResponse: parser.rawText.isEmpty ? null : parser.rawText,
      );
      final currentStageState = latestProject.stageStateFor(stage);
      _project = latestProject.withStageState(
        currentStageState.copyWith(
          messages: [...currentStageState.messages, errMessage],
        ),
      );
      _lastError = error.toString();
      await _persistProject(_project!);
    } finally {
      _isSending = false;
      _sendingStage = null;
      _streamingMessage = null;
      _streamingStatus = '';
      notifyListeners();
    }
  }

  void _pushUndo(SpecForgeProject snapshot) {
    _undoStack.add(snapshot);
    if (_undoStack.length > 40) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
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
