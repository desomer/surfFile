/// Abstraction d'appel IA pour `super_spec_forge` ([SpecAiService]) et implémentation Gemini SSE ([GeminiSpecAiService]).
library;

import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_forge_stage.dart';
import 'spec_app_tools.dart';
import 'spec_stage_agent.dart';

/// Service abstrait d'exécution d'un tour de conversation avec un agent spécialisé.
abstract interface class SpecAiService {
  /// Diffuse en flux SSE la réponse JSON pour l'agent de [stage] (ou une instruction transverse).
  Stream<GeminiStreamEvent> streamTurn({
    required SpecForgeStage stage,
    required String prompt,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
    List<Map<String, Object?>>? conversationContents,
    bool enforceJsonResponse = true,
    String? systemInstructionOverride,
    String? staticGuideOverride,
  });

  /// Préchauffe silencieusement la connexion et le cache pour [stage].
  Future<void> warmUp(
    SpecForgeStage stage, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
  });
}

/// Implémentation par défaut appuyée sur `streamGemini` et `warmUpGemini` de `super_container_layout`.
class GeminiSpecAiService implements SpecAiService {
  /// Crée le connecteur Gemini pour `super_spec_forge`.
  const GeminiSpecAiService();

  /// Instruction système par défaut pour l'agent de l'étape [stage].
  static String defaultSystemInstructionFor(SpecForgeStage stage) =>
      SpecStageAgent.forStage(stage).systemInstruction;

  /// Guide statique par défaut (schéma de patch + guide outils) pour l'étape [stage].
  static String defaultStaticGuideFor(SpecForgeStage stage) =>
      '${SpecStageAgent.forStage(stage).patchSchemaGuide}\n\n---\n\n${SpecForgeToolRegistry.toolsGuide()}';

  @override
  Stream<GeminiStreamEvent> streamTurn({
    required SpecForgeStage stage,
    required String prompt,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
    List<Map<String, Object?>>? conversationContents,
    bool enforceJsonResponse = true,
    String? systemInstructionOverride,
    String? staticGuideOverride,
  }) {
    return streamGemini(
      prompt,
      systemInstruction:
          systemInstructionOverride ?? defaultSystemInstructionFor(stage),
      staticGuide: staticGuideOverride ?? defaultStaticGuideFor(stage),
      attachments: attachments,
      speedMode: speedMode,
      tools: tools,
      conversationContents: conversationContents,
      enforceJsonResponse: enforceJsonResponse,
    );
  }

  @override
  Future<void> warmUp(
    SpecForgeStage stage, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
  }) {
    return warmUpGemini(
      systemInstruction: defaultSystemInstructionFor(stage),
      staticGuide: defaultStaticGuideFor(stage),
      speedMode: speedMode,
      tools: tools,
    );
  }
}
