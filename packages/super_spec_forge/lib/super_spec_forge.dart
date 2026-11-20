/// Bibliothèque publique principale du package `super_spec_forge`.
///
/// Réexporte les modèles métier ([SpecForgeProject], [SpecVision],
/// [SpecCahierDesCharges], [BusinessObjectSpec], [BusinessRuleSpec]),
/// les agents IA spécialisés par étape ([SpecStageAgent], [SpecPromptBuilder],
/// [SpecStreamParser], [SpecPatchApplier], [SpecAiService]), les services de
/// persistance/cohérence/export ([SpecProjectStore], [SpecCoherenceAnalyzer],
/// [SpecMarkdownExporter], [SpecJsonExporter], [SpecSuperDesignerExporter],
/// [SpecForgeController]) ainsi que les widgets du wizard ([SpecForgeShell]).
library;

export 'ai/spec_ai_service.dart';
export 'ai/spec_patch_applier.dart';
export 'ai/spec_prompt_builder.dart';
export 'ai/spec_stage_agent.dart';
export 'ai/spec_stream_parser.dart';
export 'models/business_object_spec.dart';
export 'models/business_rule_spec.dart';
export 'models/spec_cahier_des_charges.dart';
export 'models/spec_coherence_issue.dart';
export 'models/spec_forge_project.dart';
export 'models/spec_forge_stage.dart';
export 'models/spec_stage_chat.dart';
export 'models/spec_vision.dart';
export 'services/exporters/spec_json_exporter.dart';
export 'services/exporters/spec_markdown_exporter.dart';
export 'services/exporters/spec_super_designer_exporter.dart';
export 'services/spec_coherence_analyzer.dart';
export 'services/spec_forge_controller.dart';
export 'services/spec_project_store.dart';
export 'widgets/idea_launcher_view.dart';
export 'widgets/spec_forge_shell.dart';
export 'widgets/spec_wizard_stepper.dart';
export 'widgets/stage_ai_chat_pane.dart';
export 'widgets/workspace/business_objects_editor_view.dart';
export 'widgets/workspace/business_rules_editor_view.dart';
export 'widgets/workspace/review_export_view.dart';
export 'widgets/workspace/specifications_editor_view.dart';
export 'widgets/workspace/vision_editor_view.dart';
