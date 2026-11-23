/// Shell Desktop principal de `super_spec_forge` ([SpecForgeShell]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/qa/qa_forge_stage.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/ux/ux_forge_stage.dart';
import '../services/spec_forge_controller.dart';
import '../services/spec_project_store.dart';
import 'design/company_glossary_view.dart';
import 'design/domain_management_view.dart';
import 'design/model_dictionary_view.dart';
import 'design/models_contracts_view.dart';
import 'design_links_view.dart';
import 'global_question_chat_pane.dart';
import 'idea_launcher_view.dart';
import 'qa_stage_ai_chat_pane.dart';
import 'qa_wizard_stepper.dart';
import 'qa_workspace/qa_fixtures_editor_view.dart';
import 'qa_workspace/qa_gherkin_editor_view.dart';
import 'qa_workspace/qa_review_export_view.dart';
import 'qa_workspace/qa_tdd_editor_view.dart';
import 'spec_links_view.dart';
import 'spec_split_handle.dart';
import 'spec_wizard_stepper.dart';
import 'spec_workspace_selector_dialog.dart';
import 'stage_ai_chat_pane.dart';
import 'ux_stage_ai_chat_pane.dart';
import 'ux_wizard_stepper.dart';
import 'ux_workspace/ux_journeys_editor_view.dart';
import 'ux_workspace/ux_navigation_editor_view.dart';
import 'ux_workspace/ux_review_export_view.dart';
import 'ux_workspace/ux_screens_editor_view.dart';
import 'workspace/business_objects_editor_view.dart';
import 'workspace/business_rules_editor_view.dart';
import 'workspace/example_mapping_editor_view.dart';
import 'workspace/lexicon_editor_view.dart';
import 'workspace/review_export_view.dart';
import 'workspace/specifications_editor_view.dart';
import 'workspace/vision_editor_view.dart';

/// Interface Desktop principale combinant écran d'accueil, stepper 5 étapes,
/// chat IA spécialisé et atelier structuré.
class SpecForgeShell extends StatefulWidget {
  /// Crée le shell connecté au [controller].
  const SpecForgeShell({
    required this.controller,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    this.pickDirectory,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Sélecteur optionnel de pièces jointes transmis à [StageAiChatPane].
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers transmis à [StageAiChatPane].
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant la présence d'un média dans le presse-papiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers sur `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  /// Sélecteur de dossier personnalisable pour le choix du workspace Git.
  final DirectoryPickerCallback? pickDirectory;

  @override
  State<SpecForgeShell> createState() => _SpecForgeShellState();
}

class _SpecForgeShellState extends State<SpecForgeShell> {
  final GlobalKey _splitRowKey = GlobalKey();
  final GlobalKey _uxSplitRowKey = GlobalKey();
  final GlobalKey _qaSplitRowKey = GlobalKey();
  double _chatPaneFraction = 0.50;
  double _chatDragOffset = SpecSplitHandle.width / 2;
  int _selectedRailIndex = 0;
  String? _activeSpecLinkId;
  String? _activeDesignLinkId;
  String? _initialModelsDomainId;
  ({SpecProjectStore workspace, String domainId, String? entryId})?
  _designDetail;

  void _selectRail(int index) => setState(() {
    if (index == 0 && _selectedRailIndex == 0) _activeSpecLinkId = null;
    if (index != _selectedRailIndex) _designDetail = null;
    _selectedRailIndex = index;
  });

  void _selectDesignPage(String? id, {String? initialDomainId}) => setState(() {
    _activeDesignLinkId = id;
    _initialModelsDomainId = initialDomainId;
    _designDetail = null;
  });

  void _selectDesignDetail(String? domainId, String? entryId) => setState(() {
    _designDetail = domainId == null
        ? null
        : (
            workspace: widget.controller.store,
            domainId: domainId,
            entryId: entryId,
          );
  });

  String _appBarTitle(SpecForgeProject? project) {
    switch (_selectedRailIndex) {
      case 0:
        return switch (_activeSpecLinkId) {
          'company_glossary' => 'Spec › ${SpecLinksView.glossaryLabel}',
          'modeling_dictionary' =>
            'Spec › ${SpecLinksView.modelingDictionaryLabel}',
          'projects' => 'Spec › ${SpecLinksView.projectsLabel}',
          'wizard' when project != null =>
            '${project.currentStage.title} — ${project.name}',
          'ux_wizard' when project != null =>
            'UX · ${project.uxSpec.currentStage.title} — ${project.name}',
          'qa_wizard' when project != null =>
            'BDD/TDD · ${project.qaSpec.currentStage.title} — ${project.name}',
          _ => 'Spec',
        };
      case 1:
        final id = _activeDesignLinkId;
        if (id == null) return 'Design';
        final page = DesignLinksView.defaultSections
            .expand((section) => section.items)
            .firstWhere((item) => item.id == id)
            .label;
        final detail = _designDetail;
        if (detail != null && detail.workspace == widget.controller.store) {
          final domain = widget.controller.domainCatalog.domains
              .where((domain) => domain.id == detail.domainId)
              .firstOrNull;
          final name = id == 'domain_management'
              ? domain?.name
              : domain?.contracts?.entryById(detail.entryId)?.name;
          if (name != null) return '$page › $name';
        }
        return 'Design › $page';
      case 2:
        return 'Build';
      default:
        return project == null ? 'Question' : 'Question — ${project.name}';
    }
  }

  void _cycleChatPaneSize() {
    setState(() {
      if (_chatPaneFraction <= 0.0) {
        _chatPaneFraction = 0.50;
      } else if (_chatPaneFraction > 0.32) {
        _chatPaneFraction = 0.30;
      } else {
        _chatPaneFraction = 0.0;
      }
    });
  }

  Future<void> _openWorkspaceSelector(BuildContext context) async {
    final changed = await SpecWorkspaceSelectorDialog.show(
      context,
      controller: widget.controller,
      pickDirectory: widget.pickDirectory,
    );
    if (!changed || !mounted) return;
    setState(() {
      if ((_activeSpecLinkId == 'wizard' ||
              _activeSpecLinkId == 'ux_wizard' ||
              _activeSpecLinkId == 'qa_wizard') &&
          widget.controller.project == null) {
        _activeSpecLinkId = 'projects';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        final colors = Theme.of(context).colorScheme;
        final workspaceLabel =
            widget.controller.workspaceMetadata?.name ??
            widget.controller.workspaceDirectory.path;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _appBarTitle(project),
                    maxLines: 1,
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
              Tooltip(
                message:
                    'Workspace Git actif : ${widget.controller.workspaceDirectory.path}',
                child: TextButton.icon(
                  key: const ValueKey('spec-workspace-selector-btn'),
                  onPressed: widget.controller.isSending
                      ? null
                      : () => _openWorkspaceSelector(context),
                  icon: const Icon(Icons.folder_copy_outlined, size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      workspaceLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
              ],
              const SizedBox(width: 12),
            ],
          ),
          body: Row(
            children: [
              NavigationRail(
                key: const ValueKey('spec-forge-nav-rail'),
                selectedIndex: _selectedRailIndex < 3
                    ? _selectedRailIndex
                    : null,
                onDestinationSelected: _selectRail,
                labelType: NavigationRailLabelType.all,
                minWidth: 64,
                backgroundColor: colors.surfaceContainerLow,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.description_outlined),
                    selectedIcon: Icon(Icons.description_rounded),
                    label: Text('Spec'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.design_services_outlined),
                    selectedIcon: Icon(Icons.design_services_rounded),
                    label: Text('Design'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.construction_outlined),
                    selectedIcon: Icon(Icons.construction_rounded),
                    label: Text('Build'),
                  ),
                ],
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Divider(
                            height: 16,
                            thickness: 1,
                            indent: 14,
                            endIndent: 14,
                            color: colors.outlineVariant.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 4),
                          _RailDestinationButton(
                            selected: _selectedRailIndex == 3,
                            icon: Icons.question_answer_outlined,
                            selectedIcon: Icons.question_answer_rounded,
                            label: 'Question',
                            onTap: () => _selectRail(3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: switch (_selectedRailIndex) {
                  0 => _buildSpecContent(context, project, colors),
                  1 => _buildDesignContent(context),
                  2 => const SizedBox.shrink(
                    key: ValueKey('spec-forge-build-empty'),
                  ),
                  _ => GlobalQuestionChatPane(
                    controller: widget.controller,
                    onNavigateToSpec: () => setState(() {
                      _selectedRailIndex = 0;
                      _activeSpecLinkId = widget.controller.project != null
                          ? 'wizard'
                          : null;
                    }),
                    pickAttachments: widget.pickAttachments,
                    pasteAttachments: widget.pasteAttachments,
                    hasClipboardMedia: widget.hasClipboardMedia,
                    pasteClipboardMedia: widget.pasteClipboardMedia,
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesignContent(BuildContext context) {
    if (_activeDesignLinkId == 'models_contracts') {
      return ModelsContractsView(
        key: ObjectKey(widget.controller.store),
        controller: widget.controller,
        initialDomainId: _initialModelsDomainId,
        onBack: () => _selectDesignPage(null),
        onManageDomains: () => _selectDesignPage('domain_management'),
        onOpenEntryChanged: _selectDesignDetail,
        pickAttachments: widget.pickAttachments,
        pasteAttachments: widget.pasteAttachments,
        hasClipboardMedia: widget.hasClipboardMedia,
        pasteClipboardMedia: widget.pasteClipboardMedia,
      );
    }
    if (_activeDesignLinkId == 'domain_management') {
      return DomainManagementView(
        key: ObjectKey(widget.controller.store),
        controller: widget.controller,
        onBack: () => _selectDesignPage(null),
        onDomainSelected: (id) => _selectDesignDetail(id, null),
      );
    }
    return DesignLinksView(
      key: const ValueKey('spec-forge-design-view'),
      onLinkTap: (item) {
        if (item.id == 'domain_management' || item.id == 'models_contracts') {
          _selectDesignPage(item.id);
          return;
        }
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${item.label} — bientôt disponible'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      },
    );
  }

  Widget _buildSpecContent(
    BuildContext context,
    SpecForgeProject? project,
    ColorScheme colors,
  ) {
    if (_activeSpecLinkId == 'modeling_dictionary') {
      return ModelDictionaryView(
        controller: widget.controller,
        onBack: () => setState(() => _activeSpecLinkId = null),
        pickAttachments: widget.pickAttachments,
      );
    }
    if (_activeSpecLinkId == 'company_glossary') {
      return CompanyGlossaryView(
        controller: widget.controller,
        onBack: () => setState(() => _activeSpecLinkId = null),
        pickAttachments: widget.pickAttachments,
        pasteAttachments: widget.pasteAttachments,
        hasClipboardMedia: widget.hasClipboardMedia,
        pasteClipboardMedia: widget.pasteClipboardMedia,
      );
    }
    if (_activeSpecLinkId == 'projects') {
      return IdeaLauncherView(
        controller: widget.controller,
        onBack: () => setState(() => _activeSpecLinkId = null),
        onProjectActivated: () => setState(() => _activeSpecLinkId = 'wizard'),
        onSelectWorkspace: () => _openWorkspaceSelector(context),
      );
    }
    if (_activeSpecLinkId == 'wizard' && project != null) {
      return _buildSpecWizard(project, colors);
    }
    if (_activeSpecLinkId == 'ux_wizard' && project != null) {
      return _buildUxWizard(project, colors);
    }
    if (_activeSpecLinkId == 'qa_wizard' && project != null) {
      return _buildQaWizard(project, colors);
    }
    return SpecLinksView(
      key: const ValueKey('spec-forge-spec-menu-view'),
      activeProject: project,
      recentProjectsCount: widget.controller.recentProjects.length,
      companyGlossaryTermsCount: widget.controller.companyGlossary.terms.length,
      onLinkTap: (item) {
        if (item.id == 'projects' ||
            item.id == 'company_glossary' ||
            item.id == 'modeling_dictionary') {
          setState(() => _activeSpecLinkId = item.id);
          return;
        }
        if (item.id == 'wizard' ||
            item.id == 'ux_wizard' ||
            item.id == 'qa_wizard') {
          if (project != null) {
            setState(() => _activeSpecLinkId = item.id);
            return;
          }
          ScaffoldMessenger.maybeOf(context)
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Aucun projet actif — ouvrez ou créez un projet dans Projets',
                ),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
        }
      },
    );
  }

  Widget _buildSpecWizard(SpecForgeProject project, ColorScheme colors) {
    return Column(
      children: [
        SpecWizardStepper(
          project: project,
          onBack: () => setState(() => _activeSpecLinkId = null),
          onSwitchToUxWizard: () =>
              setState(() => _activeSpecLinkId = 'ux_wizard'),
          onSwitchToQaWizard: () =>
              setState(() => _activeSpecLinkId = 'qa_wizard'),
          disabled: widget.controller.isSending,
          onSelectStage: (stage) => widget.controller.goToStage(
            stage,
            validateCurrent: stage.index > project.currentStage.index,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const dividerWidth = SpecSplitHandle.width;
              const collapsedRailWidth = 38.0;
              const minChatWidth = 240.0;
              const minWorkspaceWidth = 360.0;
              final totalWidth = constraints.maxWidth;
              final availableWidth = (totalWidth - dividerWidth).clamp(
                0.0,
                double.infinity,
              );
              final isCollapsed = _chatPaneFraction <= 0.0;
              final chatWidth = isCollapsed
                  ? 0.0
                  : (availableWidth <= minChatWidth + minWorkspaceWidth
                        ? availableWidth * _chatPaneFraction
                        : (availableWidth * _chatPaneFraction).clamp(
                            minChatWidth,
                            availableWidth - minWorkspaceWidth,
                          ));

              return Row(
                key: _splitRowKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCollapsed)
                    Container(
                      key: const ValueKey('spec-chat-collapsed-bar'),
                      width: collapsedRailWidth,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          IconButton(
                            key: const ValueKey('spec-chat-cycle-size-btn'),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher le chat IA (50 %)',
                            onPressed: _cycleChatPaneSize,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      key: const ValueKey('spec-chat-pane'),
                      width: chatWidth,
                      child: StageAiChatPane(
                        controller: widget.controller,
                        chatWidthFraction: _chatPaneFraction,
                        onCycleChatSize: _cycleChatPaneSize,
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                    ),
                  SpecSplitHandle(
                    key: const ValueKey('spec-chat-split-handle'),
                    onDoubleTap: () => setState(() => _chatPaneFraction = 0.50),
                    onHorizontalDragDown: (details) {
                      final box =
                          _splitRowKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box != null && !isCollapsed) {
                        final localX = box
                            .globalToLocal(details.globalPosition)
                            .dx;
                        _chatDragOffset = (localX - chatWidth).clamp(
                          0.0,
                          SpecSplitHandle.width,
                        );
                      } else {
                        _chatDragOffset = SpecSplitHandle.width / 2;
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      final box =
                          _splitRowKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null || availableWidth <= 0) return;
                      final localX = box
                          .globalToLocal(details.globalPosition)
                          .dx;
                      final nextWidth = localX - _chatDragOffset;
                      final minFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? (minChatWidth / availableWidth)
                          : 0.20;
                      final maxFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? ((availableWidth - minWorkspaceWidth) /
                                availableWidth)
                          : 0.72;
                      setState(() {
                        if (isCollapsed) {
                          if (nextWidth > 60) {
                            _chatPaneFraction = (nextWidth / availableWidth)
                                .clamp(minFrac, maxFrac);
                          }
                          return;
                        }
                        if (nextWidth < 140) {
                          _chatPaneFraction = 0.0;
                        } else {
                          _chatPaneFraction = (nextWidth / availableWidth)
                              .clamp(minFrac, maxFrac);
                        }
                      });
                    },
                  ),
                  Expanded(
                    child: _buildWorkspaceForStage(project.currentStage),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceForStage(SpecForgeStage stage) => switch (stage) {
    SpecForgeStage.lexicon => LexiconEditorView(controller: widget.controller),
    SpecForgeStage.vision => VisionEditorView(controller: widget.controller),
    SpecForgeStage.specifications => SpecificationsEditorView(
      controller: widget.controller,
    ),
    SpecForgeStage.businessObjects => BusinessObjectsEditorView(
      controller: widget.controller,
    ),
    SpecForgeStage.exampleMapping => ExampleMappingEditorView(
      controller: widget.controller,
    ),
    SpecForgeStage.businessRules => BusinessRulesEditorView(
      controller: widget.controller,
    ),
    SpecForgeStage.reviewExport => ReviewExportView(
      controller: widget.controller,
      onContinueToUxWizard: widget.controller.isSending
          ? null
          : () {
              final current = widget.controller.project;
              if (current != null) {
                final state = current.stageStateFor(
                  SpecForgeStage.reviewExport,
                );
                if (state.status != SpecStageStatus.validated) {
                  widget.controller.updateProject(
                    current.withStageState(
                      state.copyWith(status: SpecStageStatus.validated),
                    ),
                    recordUndo: false,
                  );
                }
              }
              setState(() => _activeSpecLinkId = 'ux_wizard');
            },
      onContinueToQaWizard: widget.controller.isSending
          ? null
          : () {
              final current = widget.controller.project;
              if (current != null) {
                final state = current.stageStateFor(
                  SpecForgeStage.reviewExport,
                );
                if (state.status != SpecStageStatus.validated) {
                  widget.controller.updateProject(
                    current.withStageState(
                      state.copyWith(status: SpecStageStatus.validated),
                    ),
                    recordUndo: false,
                  );
                }
              }
              setState(() => _activeSpecLinkId = 'qa_wizard');
            },
      onOpenDesignModelsContracts: (domainId) => setState(() {
        _selectedRailIndex = 1;
        _activeDesignLinkId = 'models_contracts';
        _initialModelsDomainId = domainId;
        _designDetail = null;
      }),
    ),
  };

  Widget _buildUxWizard(SpecForgeProject project, ColorScheme colors) {
    return Column(
      key: const ValueKey('spec-forge-ux-wizard-view'),
      children: [
        UxWizardStepper(
          project: project,
          onBack: () => setState(() => _activeSpecLinkId = null),
          onSwitchToSpecWizard: () =>
              setState(() => _activeSpecLinkId = 'wizard'),
          onSwitchToQaWizard: () =>
              setState(() => _activeSpecLinkId = 'qa_wizard'),
          disabled: widget.controller.isSending,
          onSelectStage: (stage) => widget.controller.goToUxStage(
            stage,
            validateCurrent: stage.index > project.uxSpec.currentStage.index,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const dividerWidth = SpecSplitHandle.width;
              const collapsedRailWidth = 38.0;
              const minChatWidth = 240.0;
              const minWorkspaceWidth = 360.0;
              final totalWidth = constraints.maxWidth;
              final availableWidth = (totalWidth - dividerWidth).clamp(
                0.0,
                double.infinity,
              );
              final isCollapsed = _chatPaneFraction <= 0.0;
              final chatWidth = isCollapsed
                  ? 0.0
                  : (availableWidth <= minChatWidth + minWorkspaceWidth
                        ? availableWidth * _chatPaneFraction
                        : (availableWidth * _chatPaneFraction).clamp(
                            minChatWidth,
                            availableWidth - minWorkspaceWidth,
                          ));

              return Row(
                key: _uxSplitRowKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCollapsed)
                    Container(
                      key: const ValueKey('ux-chat-collapsed-bar'),
                      width: collapsedRailWidth,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          IconButton(
                            key: const ValueKey('ux-chat-expand-btn'),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher le chat IA UX (50 %)',
                            onPressed: _cycleChatPaneSize,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      key: const ValueKey('ux-chat-pane'),
                      width: chatWidth,
                      child: UxStageAiChatPane(
                        controller: widget.controller,
                        chatWidthFraction: _chatPaneFraction,
                        onCycleChatSize: _cycleChatPaneSize,
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                    ),
                  SpecSplitHandle(
                    key: const ValueKey('ux-chat-split-handle'),
                    onDoubleTap: () => setState(() => _chatPaneFraction = 0.50),
                    onHorizontalDragDown: (details) {
                      final box =
                          _uxSplitRowKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box != null && !isCollapsed) {
                        final localX = box
                            .globalToLocal(details.globalPosition)
                            .dx;
                        _chatDragOffset = (localX - chatWidth).clamp(
                          0.0,
                          SpecSplitHandle.width,
                        );
                      } else {
                        _chatDragOffset = SpecSplitHandle.width / 2;
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      final box =
                          _uxSplitRowKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null || availableWidth <= 0) return;
                      final localX = box
                          .globalToLocal(details.globalPosition)
                          .dx;
                      final nextWidth = localX - _chatDragOffset;
                      final minFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? (minChatWidth / availableWidth)
                          : 0.20;
                      final maxFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? ((availableWidth - minWorkspaceWidth) /
                                availableWidth)
                          : 0.72;
                      setState(() {
                        if (isCollapsed) {
                          if (nextWidth > 60) {
                            _chatPaneFraction = (nextWidth / availableWidth)
                                .clamp(minFrac, maxFrac);
                          }
                          return;
                        }
                        if (nextWidth < 140) {
                          _chatPaneFraction = 0.0;
                        } else {
                          _chatPaneFraction = (nextWidth / availableWidth)
                              .clamp(minFrac, maxFrac);
                        }
                      });
                    },
                  ),
                  Expanded(
                    child: _buildWorkspaceForUxStage(
                      project.uxSpec.currentStage,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceForUxStage(UxForgeStage stage) => switch (stage) {
    UxForgeStage.userJourneys => UxJourneysEditorView(
      controller: widget.controller,
    ),
    UxForgeStage.iaNavigation => UxNavigationEditorView(
      controller: widget.controller,
    ),
    UxForgeStage.screenBlueprints => UxScreensEditorView(
      controller: widget.controller,
      onJumpToSpecStage: (targetStage, {objectId}) {
        if (objectId != null && objectId.isNotEmpty) {
          widget.controller.focusBusinessObject(objectId);
        }
        widget.controller.goToStage(targetStage);
        setState(() => _activeSpecLinkId = 'wizard');
      },
    ),
    UxForgeStage.uxReviewExport => UxReviewExportView(
      controller: widget.controller,
      onContinueToQaWizard: widget.controller.isSending
          ? null
          : () {
              final current = widget.controller.project;
              if (current != null) {
                final state = current.uxSpec.stageStateFor(
                  UxForgeStage.uxReviewExport,
                );
                if (state.status != SpecStageStatus.validated) {
                  widget.controller.updateUxSpec(
                    current.uxSpec.withStageState(
                      state.copyWith(status: SpecStageStatus.validated),
                    ),
                    recordUndo: false,
                  );
                }
              }
              setState(() => _activeSpecLinkId = 'qa_wizard');
            },
    ),
  };

  Widget _buildQaWizard(SpecForgeProject project, ColorScheme colors) {
    return Column(
      key: const ValueKey('spec-forge-qa-wizard-view'),
      children: [
        QaWizardStepper(
          project: project,
          onBack: () => setState(() => _activeSpecLinkId = null),
          onSwitchToSpecWizard: () =>
              setState(() => _activeSpecLinkId = 'wizard'),
          onSwitchToUxWizard: () =>
              setState(() => _activeSpecLinkId = 'ux_wizard'),
          disabled: widget.controller.isSending,
          onSelectStage: (stage) => widget.controller.goToQaStage(
            stage,
            validateCurrent: stage.index > project.qaSpec.currentStage.index,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const dividerWidth = SpecSplitHandle.width;
              const collapsedRailWidth = 38.0;
              const minChatWidth = 240.0;
              const minWorkspaceWidth = 360.0;
              final totalWidth = constraints.maxWidth;
              final availableWidth = (totalWidth - dividerWidth).clamp(
                0.0,
                double.infinity,
              );
              final isCollapsed = _chatPaneFraction <= 0.0;
              final chatWidth = isCollapsed
                  ? 0.0
                  : (availableWidth <= minChatWidth + minWorkspaceWidth
                        ? availableWidth * _chatPaneFraction
                        : (availableWidth * _chatPaneFraction).clamp(
                            minChatWidth,
                            availableWidth - minWorkspaceWidth,
                          ));

              return Row(
                key: _qaSplitRowKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCollapsed)
                    Container(
                      key: const ValueKey('qa-chat-collapsed-bar'),
                      width: collapsedRailWidth,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          IconButton(
                            key: const ValueKey('qa-chat-expand-btn'),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher le chat IA BDD / TDD (50 %)',
                            onPressed: _cycleChatPaneSize,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      key: const ValueKey('qa-chat-pane'),
                      width: chatWidth,
                      child: QaStageAiChatPane(
                        controller: widget.controller,
                        chatWidthFraction: _chatPaneFraction,
                        onCycleChatSize: _cycleChatPaneSize,
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                    ),
                  SpecSplitHandle(
                    key: const ValueKey('qa-chat-split-handle'),
                    onDoubleTap: () => setState(() => _chatPaneFraction = 0.50),
                    onHorizontalDragDown: (details) {
                      final box =
                          _qaSplitRowKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box != null && !isCollapsed) {
                        final localX = box
                            .globalToLocal(details.globalPosition)
                            .dx;
                        _chatDragOffset = (localX - chatWidth).clamp(
                          0.0,
                          SpecSplitHandle.width,
                        );
                      } else {
                        _chatDragOffset = SpecSplitHandle.width / 2;
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      final box =
                          _qaSplitRowKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null || availableWidth <= 0) return;
                      final localX = box
                          .globalToLocal(details.globalPosition)
                          .dx;
                      final nextWidth = localX - _chatDragOffset;
                      final minFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? (minChatWidth / availableWidth)
                          : 0.20;
                      final maxFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? ((availableWidth - minWorkspaceWidth) /
                                availableWidth)
                          : 0.72;
                      setState(() {
                        if (isCollapsed) {
                          if (nextWidth > 60) {
                            _chatPaneFraction = (nextWidth / availableWidth)
                                .clamp(minFrac, maxFrac);
                          }
                          return;
                        }
                        if (nextWidth < 140) {
                          _chatPaneFraction = 0.0;
                        } else {
                          _chatPaneFraction = (nextWidth / availableWidth)
                              .clamp(minFrac, maxFrac);
                        }
                      });
                    },
                  ),
                  Expanded(
                    child: _buildWorkspaceForQaStage(
                      project.qaSpec.currentStage,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceForQaStage(QaForgeStage stage) => switch (stage) {
    QaForgeStage.testFixtures => QaFixturesEditorView(
      controller: widget.controller,
    ),
    QaForgeStage.gherkinFeatures => QaGherkinEditorView(
      controller: widget.controller,
    ),
    QaForgeStage.tddSuites => QaTddEditorView(
      controller: widget.controller,
      onJumpToSpecStage: (targetStage, {objectId}) {
        if (objectId != null && objectId.isNotEmpty) {
          widget.controller.focusBusinessObject(objectId);
        }
        widget.controller.goToStage(targetStage);
        setState(() => _activeSpecLinkId = 'wizard');
      },
    ),
    QaForgeStage.qaReviewExport => QaReviewExportView(
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
          Text(level.label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _RailDestinationButton extends StatelessWidget {
  const _RailDestinationButton({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
