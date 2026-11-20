/// Abstraction d'appel IA pour `super_spec_forge` ([SpecAiService]) et implémentation Gemini SSE ([GeminiSpecAiService]).
library;

import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_forge_stage.dart';
import 'spec_stage_agent.dart';

/// Service abstrait d'exécution d'un tour de conversation avec un agent spécialisé.
abstract interface class SpecAiService {
  /// Diffuse en flux SSE la réponse JSON pour l'agent de [stage].
  Stream<GeminiStreamEvent> streamTurn({
    required SpecForgeStage stage,
    required String prompt,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  });

  /// Préchauffe silencieusement la connexion et le cache pour [stage].
  Future<void> warmUp(
    SpecForgeStage stage, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  });
}

/// Implémentation par défaut appuyée sur `streamGemini` et `warmUpGemini` de `super_container_layout`.
class GeminiSpecAiService implements SpecAiService {
  /// Crée le connecteur Gemini pour `super_spec_forge`.
  const GeminiSpecAiService();

  @override
  Stream<GeminiStreamEvent> streamTurn({
    required SpecForgeStage stage,
    required String prompt,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) {
    final agent = SpecStageAgent.forStage(stage);
    return streamGemini(
      prompt,
      systemInstruction: agent.systemInstruction,
      staticGuide: agent.patchSchemaGuide,
      attachments: attachments,
      speedMode: speedMode,
      enforceJsonResponse: true,
    );
  }

  @override
  Future<void> warmUp(
    SpecForgeStage stage, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) {
    final agent = SpecStageAgent.forStage(stage);
    return warmUpGemini(
      systemInstruction: agent.systemInstruction,
      staticGuide: agent.patchSchemaGuide,
      speedMode: speedMode,
    );
  }
}
