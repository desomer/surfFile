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

export 'ai/company_glossary_ai.dart';
export 'ai/domain_model_ai.dart';
export 'ai/spec_ai_service.dart';
export 'ai/spec_app_tools.dart';
export 'ai/spec_delta_recovery.dart';
export 'ai/spec_patch_applier.dart';
export 'ai/spec_prompt_builder.dart';
export 'ai/spec_stage_agent.dart';
export 'ai/spec_stream_parser.dart';
export 'ai/ux_patch_applier.dart';
export 'ai/ux_prompt_builder.dart';
export 'ai/ux_stage_agent.dart';
export 'models/business_object_model_preferences.dart';
export 'models/business_object_spec.dart';
export 'models/business_rule_spec.dart';
export 'models/company_glossary.dart';
export 'models/domain_catalog.dart';
export 'models/domain_contracts.dart';
export 'models/json_schema_constraints.dart';
export 'models/spec_cahier_des_charges.dart';
export 'models/spec_coherence_issue.dart';
export 'models/spec_forge_project.dart';
export 'models/spec_forge_stage.dart';
export 'models/spec_lexicon.dart';
export 'models/spec_stage_chat.dart';
export 'models/spec_vision.dart';
export 'models/technical_modeling_rule.dart';
export 'models/ux/ux_coherence_issue.dart';
export 'models/ux/ux_forge_spec.dart';
export 'models/ux/ux_forge_stage.dart';
export 'models/ux/ux_journey_spec.dart';
export 'models/ux/ux_navigation_spec.dart';
export 'models/ux/ux_screen_spec.dart';
export 'services/business_object_operations.dart';
export 'services/company_glossary_store.dart';
export 'services/domain_catalog_store.dart';
export 'services/domain_env_exporter.dart';
export 'services/domain_secret_cipher.dart';
export 'services/exporters/company_glossary_codec.dart';
export 'services/exporters/model_dictionary_codec.dart';
export 'services/exporters/spec_json_exporter.dart';
export 'services/exporters/spec_json_schema_html_builder.dart';
export 'services/exporters/spec_markdown_exporter.dart';
export 'services/exporters/spec_markdown_html_builder.dart';
export 'services/exporters/spec_super_designer_exporter.dart';
export 'services/exporters/ux_design_md_exporter.dart';
export 'services/exporters/ux_markdown_exporter.dart';
export 'services/exporters/ux_super_designer_prompt_exporter.dart';
export 'services/model_dictionary_store.dart';
export 'services/spec_coherence_analyzer.dart';
export 'services/spec_forge_controller.dart';
export 'services/spec_project_store.dart';
export 'services/spec_schema_dsl_bridge.dart';
export 'services/spec_storage_slug.dart';
export 'services/spec_workspace_store.dart';
export 'services/ux_coherence_analyzer.dart';
export 'widgets/design/company_glossary_view.dart';
export 'widgets/design/domain_management_view.dart';
export 'widgets/design/model_dictionary_view.dart';
export 'widgets/design/models_contracts_view.dart';
export 'widgets/design_links_view.dart';
export 'widgets/global_question_chat_pane.dart';
export 'widgets/idea_launcher_view.dart';
export 'widgets/spec_chat_widgets.dart';
export 'widgets/spec_forge_shell.dart';
export 'widgets/spec_links_view.dart';
export 'widgets/spec_wizard_stepper.dart';
export 'widgets/spec_workspace_selector_dialog.dart';
export 'widgets/stage_ai_chat_pane.dart';
export 'widgets/ux_stage_ai_chat_pane.dart';
export 'widgets/ux_wizard_stepper.dart';
export 'widgets/ux_workspace/ux_journeys_editor_view.dart';
export 'widgets/ux_workspace/ux_navigation_editor_view.dart';
export 'widgets/ux_workspace/ux_review_export_view.dart';
export 'widgets/ux_workspace/ux_screens_editor_view.dart';
export 'widgets/workspace/attribute_constraints_editor.dart';
export 'widgets/workspace/business_objects_editor_view.dart';
export 'widgets/workspace/business_rules_editor_view.dart';
export 'widgets/workspace/json_schema_viewer_dialog.dart';
export 'widgets/workspace/lexicon_editor_view.dart';
export 'widgets/workspace/markdown_viewer_dialog.dart';
export 'widgets/workspace/model_preferences_dialog.dart';
export 'widgets/workspace/review_export_view.dart';
export 'widgets/workspace/specifications_editor_view.dart';
export 'widgets/workspace/vision_editor_view.dart';
