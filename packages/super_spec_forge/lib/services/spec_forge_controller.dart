/// Contrôleur réactif principal du wizard `super_spec_forge` ([SpecForgeController]).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../ai/spec_ai_service.dart';
import '../ai/spec_app_tools.dart';
import '../ai/spec_delta_recovery.dart';
import '../ai/spec_patch_applier.dart';
import '../ai/spec_prompt_builder.dart';
import '../ai/spec_stage_agent.dart';
import '../ai/spec_stream_parser.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_stage_chat.dart';
import 'spec_coherence_analyzer.dart';
import 'spec_project_store.dart';

/// Orchestre l'état du projet actif, l'historique Undo/Redo, la persistance et les échanges IA.
class SpecForgeController extends ChangeNotifier {
  /// Nombre maximal de tentatives automatiques en cas d'exception de parsing ou validation IA.
  static const int maxRecoveryAttempts = 3;

  /// Nombre maximal de tours d'appels d'outils par tentative IA.
  static const int maxToolRounds = 6;

  /// Crée un contrôleur avec store, service IA et registre d'outils injectables.
  SpecForgeController({
    SpecProjectStore? store,
    SpecAiService? aiService,
    VibeAppToolRegistry? toolRegistry,
    VibeAiSpeedMode initialSpeedMode = VibeAiSpeedMode.fast,
    VibeQuestioningLevel initialQuestioningLevel =
        VibeQuestioningLevel.balanced,
  }) : _store = store ?? SpecProjectStore(),
       _aiService = aiService ?? const GeminiSpecAiService(),
       _customToolRegistry = toolRegistry,
       _speedMode = initialSpeedMode,
       _questioningLevel = initialQuestioningLevel;

  final SpecProjectStore _store;
  final SpecAiService _aiService;
  final VibeAppToolRegistry? _customToolRegistry;

  SpecForgeProject? _project;
  List<SpecProjectSummary> _recentProjects = const <SpecProjectSummary>[];
  final List<SpecForgeProject> _undoStack = <SpecForgeProject>[];
  final List<SpecForgeProject> _redoStack = <SpecForgeProject>[];

  VibeAiSpeedMode _speedMode;
  VibeQuestioningLevel _questioningLevel;

  bool _isSending = false;
  bool _sendingGlobalQuestion = false;
  SpecForgeStage? _sendingStage;
  String? _streamingMessage;
  String _streamingStatus = '';
  List<VibeToolTrace> _streamingToolTraces = const <VibeToolTrace>[];
  String? _focusedObjectId;
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

  /// Vrai lorsqu'une question globale du chat « Question » est en cours de traitement.
  bool get isSendingGlobalQuestion => _isSending && _sendingGlobalQuestion;

  /// Étape en cours de génération IA.
  SpecForgeStage? get sendingStage => _sendingStage;

  /// Texte streaming reçu jusqu'ici pour le message en cours.
  String? get streamingMessage => _streamingMessage;

  /// Indicateur d'activité streaming (ex. « Rédaction des questions… »).
  String get streamingStatus => _streamingStatus;

  /// Traces d'outils déjà exécutés pendant le tour en streaming courant.
  List<VibeToolTrace> get streamingToolTraces => _streamingToolTraces;

  /// Identifiant d'objet métier ciblé par un outil IA ou l'interface.
  String? get focusedObjectId => _focusedObjectId;

  /// Met à jour l'objet métier focalisé dans l'atelier.
  void focusBusinessObject(String? objectId) {
    if (_focusedObjectId == objectId) return;
    _focusedObjectId = objectId;
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
      '[SpecForge IA] Réflexion interrompue par l’utilisateur (${_sendingStage?.agentTitle ?? 'agent'}).',
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
    var retryText = 'Réponds à ma dernière question sur la globalité du projet.';
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
    _streamingMessage = null;
    _streamingStatus = 'Analyse transverse du projet…';
    _streamingToolTraces = const <VibeToolTrace>[];
    _lastError = null;
    notifyListeners();

    var workingProject = withUserMsg;
    var currentPrompt = SpecPromptBuilder.buildGlobalQuestionPrompt(
      project: initialProject,
      userInput: questionInput,
    );
    final turnToolTraces = <VibeToolTrace>[];

    final registry =
        _customToolRegistry ??
        SpecForgeToolRegistry.build(
          readProject: () => workingProject,
          onUpdateProject: (updated) async {
            _pushUndo(workingProject);
            workingProject = updated;
            _project = updated;
            notifyListeners();
            await _persistProject(updated);
          },
          onNavigateStage: (targetStage) async {
            final moved = workingProject.moveToStage(targetStage);
            workingProject = moved;
            _project = moved;
            notifyListeners();
          },
          onFocusObject: focusBusinessObject,
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
              if (roundParsed.specPatch == null &&
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
          saveError('[SpecForge Global Q&A] Tentative ${attempt + 1} : $cause', stack);
          debugPrint('[SpecForge Global Q&A] Échec tentative ${attempt + 1} : $cause');
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
    return SpecCoherenceAnalyzer.analyze(current);
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
    );

    final priorCauses = <String>[];
    final checkpointSummaries = <String>[];
    final turnToolTraces = <VibeToolTrace>[];
    var recovered = false;

    final registry =
        _customToolRegistry ??
        SpecForgeToolRegistry.build(
          readProject: () => workingProject,
          onUpdateProject: (updated) async {
            _pushUndo(workingProject);
            workingProject = updated;
            _project = updated;
            notifyListeners();
            await _persistProject(updated);
          },
          onNavigateStage: (targetStage) async {
            final moved = workingProject.moveToStage(targetStage);
            workingProject = moved;
            _project = moved;
            notifyListeners();
          },
          onFocusObject: focusBusinessObject,
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
                  stage: stage,
                  prompt: roundPrompt,
                  attachments: attachments,
                  speedMode: _speedMode,
                  tools: allowTools ? registry.declarations : const [],
                  conversationContents: conversationContents,
                  enforceJsonResponse: !allowTools,
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
                      } else if (snap.hasSpecPatch) {
                        _streamingStatus = 'Structuration des spécifications…';
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

            List<VibeToolCall> callsToRun = nativeCalls;
            SpecAgentResponse? roundParsed;
            if (callsToRun.isEmpty && parser.rawText.trim().isNotEmpty) {
              roundParsed = SpecAgentResponse.parse(parser.rawText);
              if (roundParsed.specPatch == null &&
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
                final summary = SpecForgeToolRegistry.summarizeResult(
                  call,
                  res,
                );
                turnToolTraces.add(
                  VibeToolTrace(
                    name: call.name,
                    arguments: call.arguments,
                    isError: res.isError,
                    summary: summary,
                  ),
                );
                debugPrint(
                  '[SpecForge IA Tool] ${call.name} -> $summary',
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
                  '$roundPrompt\n\nRÉSULTATS DES OUTILS (round ${round + 1}) :\n'
                  '${jsonEncode([for (final r in results) r.toJson()])}\n'
                  'Poursuis ou conclus maintenant avec la réponse JSON finale.';
              continue;
            }

            final response =
                roundParsed ?? SpecAgentResponse.parse(parser.rawText);
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
          }
          if (recovered) break;
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
      _streamingMessage = null;
      _streamingStatus = '';
      _streamingToolTraces = const <VibeToolTrace>[];
      notifyListeners();
    }
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
