/// Shell Desktop principal de `super_spec_forge` ([SpecForgeShell]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_forge_stage.dart';
import '../services/spec_forge_controller.dart';
import 'idea_launcher_view.dart';
import 'spec_wizard_stepper.dart';
import 'stage_ai_chat_pane.dart';
import 'workspace/business_objects_editor_view.dart';
import 'workspace/business_rules_editor_view.dart';
import 'workspace/review_export_view.dart';
import 'workspace/specifications_editor_view.dart';
import 'workspace/vision_editor_view.dart';

/// Interface Desktop principale combinant écran d'accueil, stepper 5 étapes,
/// chat IA spécialisé et atelier structuré.
class SpecForgeShell extends StatefulWidget {
  /// Crée le shell connecté au [controller].
  const SpecForgeShell({required this.controller, super.key});

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  State<SpecForgeShell> createState() => _SpecForgeShellState();
}

class _SpecForgeShellState extends State<SpecForgeShell> {
  double _chatPaneFraction = 0.42;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        final colors = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    project == null
                        ? 'SuperSpecForge'
                        : 'SuperSpecForge — ${project.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.controller.isSaving) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            actions: [
              _SpeedModeSelector(
                mode: widget.controller.speedMode,
                onChanged: widget.controller.setSpeedMode,
              ),
              const SizedBox(width: 10),
              _QuestioningLevelControl(
                level: widget.controller.questioningLevel,
                onChanged: widget.controller.setQuestioningLevel,
              ),
              if (project != null) ...[
                const VerticalDivider(width: 20, indent: 12, endIndent: 12),
                IconButton(
                  tooltip: 'Annuler (Undo)',
                  icon: const Icon(Icons.undo_rounded),
                  onPressed: widget.controller.canUndo
                      ? widget.controller.undo
                      : null,
                ),
                IconButton(
                  tooltip: 'Rétablir (Redo)',
                  icon: const Icon(Icons.redo_rounded),
                  onPressed: widget.controller.canRedo
                      ? widget.controller.redo
                      : null,
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: widget.controller.closeProject,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Projets'),
                ),
              ],
              const SizedBox(width: 12),
            ],
          ),
          body: project == null
              ? IdeaLauncherView(controller: widget.controller)
              : Column(
                  children: [
                    SpecWizardStepper(
                      project: project,
                      disabled: widget.controller.isSending,
                      onSelectStage: (stage) => widget.controller.goToStage(
                        stage,
                        validateCurrent:
                            stage.index > project.currentStage.index,
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final totalWidth = constraints.maxWidth;
                          final chatWidth =
                              (totalWidth * _chatPaneFraction).clamp(
                                320.0,
                                (totalWidth - 360.0).clamp(320.0, totalWidth),
                              );
                          return Row(
                            children: [
                              SizedBox(
                                width: chatWidth,
                                child: StageAiChatPane(
                                  controller: widget.controller,
                                ),
                              ),
                              MouseRegion(
                                cursor: SystemMouseCursors.resizeColumn,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragUpdate: (details) {
                                    if (totalWidth <= 0) return;
                                    setState(() {
                                      _chatPaneFraction =
                                          ((chatWidth + details.delta.dx) /
                                                  totalWidth)
                                              .clamp(0.28, 0.65);
                                    });
                                  },
                                  child: Container(
                                    width: 6,
                                    color: colors.outlineVariant.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _buildWorkspaceForStage(
                                  project.currentStage,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildWorkspaceForStage(SpecForgeStage stage) => switch (stage) {
    SpecForgeStage.vision => VisionEditorView(controller: widget.controller),
    SpecForgeStage.specifications => SpecificationsEditorView(
      controller: widget.controller,
    ),
    SpecForgeStage.businessObjects => BusinessObjectsEditorView(
      controller: widget.controller,
    ),
    SpecForgeStage.businessRules => BusinessRulesEditorView(
      controller: widget.controller,
    ),
    SpecForgeStage.reviewExport => ReviewExportView(
      controller: widget.controller,
    ),
  };
}

class _SpeedModeSelector extends StatelessWidget {
  const _SpeedModeSelector({required this.mode, required this.onChanged});

  final VibeAiSpeedMode mode;
  final ValueChanged<VibeAiSpeedMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Profil modèle Gemini : ${mode.tooltip}',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<VibeAiSpeedMode>(
          value: mode,
          isDense: true,
          items: [
            for (final m in VibeAiSpeedMode.values)
              DropdownMenuItem(value: m, child: Text(m.label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _QuestioningLevelControl extends StatelessWidget {
  const _QuestioningLevelControl({
    required this.level,
    required this.onChanged,
  });

  final VibeQuestioningLevel level;
  final ValueChanged<VibeQuestioningLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Niveau de questionnement IA : ${level.tooltip}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.help_outline_rounded, size: 16),
          const SizedBox(width: 4),
          SizedBox(
            width: 110,
            child: Slider(
              value: level.index.toDouble(),
              min: 0,
              max: (VibeQuestioningLevel.values.length - 1).toDouble(),
              divisions: VibeQuestioningLevel.values.length - 1,
              label: level.label,
              onChanged: (v) =>
                  onChanged(VibeQuestioningLevel.fromSliderValue(v)),
            ),
          ),
          Text(
            level.label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
