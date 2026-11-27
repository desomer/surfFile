/// Shell Desktop principal de `super_spec_forge` ([SpecForgeShell]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/cost/cost_forge_stage.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/ux/ux_forge_stage.dart';
import '../services/spec_forge_controller.dart';
import '../services/spec_project_store.dart';
import 'build/build_design_items_view.dart';
import 'build/build_links_view.dart';
import 'build/build_tech_stacks_dialog.dart';
import 'cost_stage_ai_chat_pane.dart';
import 'cost_wizard_stepper.dart';
import 'design/company_glossary_view.dart';
import 'design/domain_management_view.dart';
import 'design/enterprise_rate_card_view.dart';
import 'design/model_dictionary_view.dart';
import 'design/models_contracts_view.dart';
import 'design/systems_services_view.dart';
import 'design/usecase_orchestration_view.dart';
import 'design_links_view.dart';
import 'global_question_chat_pane.dart';
import 'idea_launcher_view.dart';
import 'portfolio/project_initiatives_view.dart';
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
import 'workspace/cost_assumptions_editor_view.dart';
import 'workspace/cost_run_editor_view.dart';
import 'workspace/cost_tco_review_export_view.dart';
import 'workspace/cost_wbs_editor_view.dart';
import 'workspace/event_storming_editor_view.dart';
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
  final GlobalKey _costSplitRowKey = GlobalKey();
  final ModelsContractsNavigationController _modelsNavController =
      ModelsContractsNavigationController();
  final BuildNavigationController _buildNavController =
      BuildNavigationController();
  double _chatPaneFraction = 0.50;
  double _chatDragOffset = SpecSplitHandle.width / 2;
  int _selectedRailIndex = 0;
  String? _activeSpecLinkId;
  bool _wizardOpenedFromInitiatives = false;
  String? _activeDesignLinkId;
  String? _activeBuildLinkId;
  String? _initialModelsDomainId;
  ({SpecProjectStore workspace, String domainId, String? entryId})?
  _designDetail;

  @override
  void dispose() {
    _modelsNavController.dispose();
    _buildNavController.dispose();
    super.dispose();
  }

  void _selectRail(int index) {
    if (index == 2 &&
        _selectedRailIndex == 2 &&
        _activeBuildLinkId == 'agentic_prompts' &&
        _buildNavController.level > 0) {
      _buildNavController.goBack();
      return;
    }
    setState(() {
      if (index == 0 && _selectedRailIndex == 0) {
        _activeSpecLinkId = null;
        _wizardOpenedFromInitiatives = false;
      }
      if (index == 1 && _selectedRailIndex == 1) _activeDesignLinkId = null;
      if (index == 2 && _selectedRailIndex == 2) {
        _activeBuildLinkId = null;
        _buildNavController.reset();
      }
      if (index != _selectedRailIndex || index == 1) {
        _designDetail = null;
        _modelsNavController.reset();
      }
      if (index != 2) {
        _buildNavController.reset();
      }
      _selectedRailIndex = index;
    });
  }

  void _selectDesignPage(String? id, {String? initialDomainId}) => setState(() {
    _activeDesignLinkId = id;
    _initialModelsDomainId = initialDomainId;
    _designDetail = null;
    _modelsNavController.reset();
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

  static bool _isWizardSpecLink(String? id) =>
      id == 'wizard' ||
      id == 'ux_wizard' ||
      id == 'qa_wizard' ||
      id == 'cost_wizard';

  ({
    String tooltip,
    VoidCallback onBack,
    String menuTooltip,
    VoidCallback onMainMenu,
  })?
  _resolveBackAction() {
    switch (_selectedRailIndex) {
      case 0:
        if (_activeSpecLinkId == null) return null;
        void goToSpecMenu() => setState(() {
          _activeSpecLinkId = null;
          _wizardOpenedFromInitiatives = false;
        });
        if (_isWizardSpecLink(_activeSpecLinkId) &&
            _wizardOpenedFromInitiatives &&
            widget.controller.project != null) {
          return (
            tooltip: 'Retour aux Initiatives & Features',
            onBack: () => setState(() {
              _activeSpecLinkId = 'initiatives';
              _wizardOpenedFromInitiatives = false;
            }),
            menuTooltip: 'Menu Spec',
            onMainMenu: goToSpecMenu,
          );
        }
        return (
          tooltip: 'Retour au menu Spec',
          onBack: goToSpecMenu,
          menuTooltip: 'Menu Spec',
          onMainMenu: goToSpecMenu,
        );
      case 1:
        if (_activeDesignLinkId == null) return null;
        void goToDesignMenu() => _selectDesignPage(null);
        if (_activeDesignLinkId == 'models_contracts') {
          final tooltip = switch (_modelsNavController.level) {
            0 => 'Retour au menu Design',
            1 => 'Retour à la liste des modèles et contrats',
            _ => 'Retour à la fiche du modèle',
          };
          return (
            tooltip: tooltip,
            onBack: _modelsNavController.goBack,
            menuTooltip: 'Menu Design',
            onMainMenu: goToDesignMenu,
          );
        }
        return (
          tooltip: 'Retour au menu Design',
          onBack: goToDesignMenu,
          menuTooltip: 'Menu Design',
          onMainMenu: goToDesignMenu,
        );
      case 2:
        if (_activeBuildLinkId == null) return null;
        void goToBuildMenu() => setState(() {
          _activeBuildLinkId = null;
          _buildNavController.reset();
        });
        if (_activeBuildLinkId == 'agentic_prompts' &&
            _buildNavController.level > 0) {
          return (
            tooltip: 'Retour aux items de design',
            onBack: _buildNavController.goBack,
            menuTooltip: 'Menu Build',
            onMainMenu: goToBuildMenu,
          );
        }
        return (
          tooltip: 'Retour au menu Build',
          onBack: goToBuildMenu,
          menuTooltip: 'Menu Build',
          onMainMenu: goToBuildMenu,
        );
      default:
        return null;
    }
  }

  String _appBarTitle(SpecForgeProject? project) {
    switch (_selectedRailIndex) {
      case 0:
        final wizardSuffix = project == null
            ? ''
            : (project.hasSingleDefaultFeature
                  ? project.name
                  : '${project.activeFeature.displayLabel} (${project.name})');
        return switch (_activeSpecLinkId) {
          'company_glossary' => 'Spec › ${SpecLinksView.glossaryLabel}',
          'modeling_dictionary' =>
            'Spec › ${SpecLinksView.modelingDictionaryLabel}',
          'enterprise_rates' =>
            'Spec › ${SpecLinksView.enterpriseRatesLabel}',
          'projects' => 'Spec › ${SpecLinksView.projectsLabel}',
          'initiatives' when project != null =>
            'Spec › ${project.name} › ${SpecLinksView.initiativesLabel}',
          'initiatives' => 'Spec › ${SpecLinksView.initiativesLabel}',
          'wizard' when project != null =>
            '${project.currentStage.title} — $wizardSuffix',
          'ux_wizard' when project != null =>
            'UX · ${project.uxSpec.currentStage.title} — $wizardSuffix',
          'qa_wizard' when project != null =>
            'BDD/TDD · ${project.qaSpec.currentStage.title} — $wizardSuffix',
          'cost_wizard' when project != null =>
            'Coûts IT · ${project.costSpec.currentStage.title} — $wizardSuffix',
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
          final name = (id == 'domain_management' || id == 'systems_services')
              ? domain?.name
              : domain?.contracts?.entryById(detail.entryId)?.name;
          if (name != null) {
            if (id == 'models_contracts' && _modelsNavController.level >= 2) {
              return '$page › $name › Couche Domain';
            }
            return '$page › $name';
          }
        }
        return 'Design › $page';
      case 2:
        return switch (_activeBuildLinkId) {
          'tech_stacks' => 'Build › ${BuildLinksView.techStacksLabel}',
          'agentic_prompts' =>
            _buildNavController.level > 0
                ? 'Build › ${BuildLinksView.agenticPromptsLabel} › Sélection des Prompts IA'
                : 'Build › ${BuildLinksView.agenticPromptsLabel}',
          _ => 'Build',
        };
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
      if ((_isWizardSpecLink(_activeSpecLinkId) ||
              _activeSpecLinkId == 'initiatives') &&
          widget.controller.project == null) {
        _activeSpecLinkId = 'projects';
        _wizardOpenedFromInitiatives = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        _modelsNavController,
        _buildNavController,
      ]),
      builder: (context, _) {
        final project = widget.controller.project;
        final colors = Theme.of(context).colorScheme;
        final workspaceLabel =
            widget.controller.workspaceMetadata?.name ??
            widget.controller.workspaceDirectory.path;
        final backAction = _resolveBackAction();

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: Theme.of(context).appBarTheme.toolbarHeight ?? 40,
            automaticallyImplyLeading: false,
            leadingWidth: backAction != null ? 80 : null,
            leading: backAction != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('spec-forge-appbar-back-btn'),
                          tooltip: backAction.tooltip,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: backAction.onBack,
                        ),
                        IconButton(
                          key: const ValueKey('spec-forge-appbar-menu-btn'),
                          tooltip: backAction.menuTooltip,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: const Icon(Icons.apps_rounded),
                          onPressed: backAction.onMainMenu,
                        ),
                      ],
                    ),
                  )
                : null,
            title: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _appBarTitle(project),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
              if (_selectedRailIndex == 0 &&
                  project != null &&
                  _isWizardSpecLink(_activeSpecLinkId)) ...[
                _ActiveFeatureAppBarMenu(
                  project: project,
                  disabled: widget.controller.isSending,
                  onManagePortfolio: () => setState(() {
                    _activeSpecLinkId = 'initiatives';
                    _wizardOpenedFromInitiatives = false;
                  }),
                  onSelectFeature: widget.controller.selectActiveFeature,
                ),
                const SizedBox(width: 6),
              ],
              Tooltip(
                message:
                    'Workspace Git actif : ${widget.controller.workspaceDirectory.path}',
                child: TextButton.icon(
                  key: const ValueKey('spec-workspace-selector-btn'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
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
                const VerticalDivider(width: 20, indent: 10, endIndent: 10),
                IconButton(
                  tooltip: 'Annuler (Undo)',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: const Icon(Icons.undo_rounded),
                  onPressed: widget.controller.canUndo
                      ? widget.controller.undo
                      : null,
                ),
                IconButton(
                  tooltip: 'Rétablir (Redo)',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
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
                  2 => _buildBuildContent(),
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

  Widget _buildBuildContent() {
    final catalog = widget.controller.domainCatalog;
    if (_activeBuildLinkId == 'tech_stacks') {
      final activeDomainId = widget.controller.activeDesignDomainId;
      final activeDomain = catalog.domains
          .where((d) => d.id == activeDomainId)
          .firstOrNull;
      return BuildTechStacksView(
        key: ObjectKey(widget.controller.store),
        controller: widget.controller,
        initialStackId: activeDomain?.techStackId,
      );
    }
    if (_activeBuildLinkId == 'agentic_prompts') {
      return KeyedSubtree(
        key: const ValueKey('spec-forge-build-view'),
        child: BuildDesignItemsView(
          key: ObjectKey(widget.controller.store),
          controller: widget.controller,
          navigationController: _buildNavController,
          onManageDomains: () {
            setState(() {
              _selectedRailIndex = 1;
              _activeDesignLinkId = 'domain_management';
              _designDetail = null;
              _modelsNavController.reset();
              _buildNavController.reset();
            });
          },
        ),
      );
    }
    return BuildLinksView(
      key: const ValueKey('spec-forge-build-menu-view'),
      techStacksCount: catalog.techStacks.length,
      domainsCount: catalog.domains.length,
      onLinkTap: (item) {
        if (item.id == 'tech_stacks' || item.id == 'agentic_prompts') {
          setState(() {
            _activeBuildLinkId = item.id;
            _buildNavController.reset();
          });
        }
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
        navigationController: _modelsNavController,
        pickAttachments: widget.pickAttachments,
        pasteAttachments: widget.pasteAttachments,
        hasClipboardMedia: widget.hasClipboardMedia,
        pasteClipboardMedia: widget.pasteClipboardMedia,
      );
    }
    if (_activeDesignLinkId == 'usecase_orchestration') {
      return UseCaseOrchestrationView(
        key: ObjectKey(widget.controller.store),
        controller: widget.controller,
        initialDomainId: _initialModelsDomainId,
        onBack: () => _selectDesignPage(null),
        onManageDomains: () => _selectDesignPage('domain_management'),
        pickAttachments: widget.pickAttachments,
        pasteAttachments: widget.pasteAttachments,
        hasClipboardMedia: widget.hasClipboardMedia,
        pasteClipboardMedia: widget.pasteClipboardMedia,
      );
    }
    if (_activeDesignLinkId == 'systems_services') {
      return SystemsServicesView(
        key: ObjectKey(widget.controller.store),
        controller: widget.controller,
        initialDomainId: _initialModelsDomainId,
        onBack: () => _selectDesignPage(null),
        onManageDomains: () => _selectDesignPage('domain_management'),
        onDomainChanged: (id) => _selectDesignDetail(id, null),
        onOpenEventStorming: widget.controller.project == null
            ? null
            : () {
                setState(() {
                  _selectedRailIndex = 0;
                  _activeSpecLinkId = 'wizard';
                  _activeDesignLinkId = null;
                  _designDetail = null;
                });
                widget.controller.goToStage(SpecForgeStage.eventStorming);
              },
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
        onDomainSelected: (id) => _selectDesignDetail(id, null),
      );
    }
    return DesignLinksView(
      key: const ValueKey('spec-forge-design-view'),
      onLinkTap: (item) {
        if (item.id == 'domain_management' ||
            item.id == 'systems_services' ||
            item.id == 'models_contracts' ||
            item.id == 'usecase_orchestration') {
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
        pickAttachments: widget.pickAttachments,
      );
    }
    if (_activeSpecLinkId == 'enterprise_rates') {
      return EnterpriseRateCardView(
        controller: widget.controller,
        pickAttachments: widget.pickAttachments,
      );
    }
    if (_activeSpecLinkId == 'company_glossary') {
      return CompanyGlossaryView(
        controller: widget.controller,
        pickAttachments: widget.pickAttachments,
        pasteAttachments: widget.pasteAttachments,
        hasClipboardMedia: widget.hasClipboardMedia,
        pasteClipboardMedia: widget.pasteClipboardMedia,
      );
    }
    if (_activeSpecLinkId == 'projects') {
      return IdeaLauncherView(
        controller: widget.controller,
        onProjectActivated: () => setState(() {
          _activeSpecLinkId = 'wizard';
          _wizardOpenedFromInitiatives = false;
        }),
        onOpenInitiatives: () => setState(() {
          _activeSpecLinkId = 'initiatives';
          _wizardOpenedFromInitiatives = false;
        }),
        onSelectWorkspace: () => _openWorkspaceSelector(context),
      );
    }
    if (_activeSpecLinkId == 'initiatives' && project != null) {
      return ProjectInitiativesView(
        controller: widget.controller,
        onOpenSharedLexicon: () {
          widget.controller.goToStage(SpecForgeStage.lexicon);
          setState(() {
            _wizardOpenedFromInitiatives = true;
            _activeSpecLinkId = 'wizard';
          });
        },
        onOpenWizard: (target) {
          setState(() {
            _wizardOpenedFromInitiatives = true;
            _activeSpecLinkId = switch (target) {
              SpecPortfolioWizardTarget.spec => 'wizard',
              SpecPortfolioWizardTarget.ux => 'ux_wizard',
              SpecPortfolioWizardTarget.qa => 'qa_wizard',
              SpecPortfolioWizardTarget.cost => 'cost_wizard',
            };
          });
        },
        pickAttachments: widget.pickAttachments,
        pasteAttachments: widget.pasteAttachments,
        hasClipboardMedia: widget.hasClipboardMedia,
        pasteClipboardMedia: widget.pasteClipboardMedia,
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
    if (_activeSpecLinkId == 'cost_wizard' && project != null) {
      return _buildCostWizard(project, colors);
    }
    return SpecLinksView(
      key: const ValueKey('spec-forge-spec-menu-view'),
      activeProject: project,
      recentProjectsCount: widget.controller.recentProjects.length,
      companyGlossaryTermsCount: widget.controller.companyGlossary.terms.length,
      enterpriseRateCardProfilesCount:
          widget.controller.enterpriseRateCard.profiles.length,
      onLinkTap: (item) {
        if (item.id == 'projects' ||
            item.id == 'company_glossary' ||
            item.id == 'modeling_dictionary' ||
            item.id == 'enterprise_rates') {
          setState(() {
            _activeSpecLinkId = item.id;
            _wizardOpenedFromInitiatives = false;
          });
          return;
        }
        if (item.id == 'initiatives' ||
            item.id == 'wizard' ||
            item.id == 'ux_wizard' ||
            item.id == 'qa_wizard' ||
            item.id == 'cost_wizard') {
          if (project != null) {
            setState(() {
              _wizardOpenedFromInitiatives = false;
              _activeSpecLinkId = item.id;
            });
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
    SpecForgeStage.eventStorming => EventStormingEditorView(
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
      onOpenDesignModelsContracts: (domainId) {
        if (domainId != null) {
          widget.controller.setActiveDesignDomainId(domainId);
        }
        setState(() {
          _selectedRailIndex = 1;
          _activeDesignLinkId = 'models_contracts';
          _initialModelsDomainId = domainId;
          _designDetail = null;
          _modelsNavController.reset();
        });
      },
    ),
  };

  Widget _buildUxWizard(SpecForgeProject project, ColorScheme colors) {
    return Column(
      key: const ValueKey('spec-forge-ux-wizard-view'),
      children: [
        UxWizardStepper(
          project: project,
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
      onContinueToCostWizard: widget.controller.isSending
          ? null
          : () {
              final current = widget.controller.project;
              if (current != null) {
                final state = current.qaSpec.stageStateFor(
                  QaForgeStage.qaReviewExport,
                );
                if (state.status != SpecStageStatus.validated) {
                  widget.controller.updateQaSpec(
                    current.qaSpec.withStageState(
                      state.copyWith(status: SpecStageStatus.validated),
                    ),
                    recordUndo: false,
                  );
                }
              }
              setState(() => _activeSpecLinkId = 'cost_wizard');
            },
    ),
  };

  Widget _buildCostWizard(SpecForgeProject project, ColorScheme colors) {
    return Column(
      key: const ValueKey('spec-forge-cost-wizard-view'),
      children: [
        CostWizardStepper(
          project: project,
          onSwitchToSpecWizard: () =>
              setState(() => _activeSpecLinkId = 'wizard'),
          onSwitchToUxWizard: () =>
              setState(() => _activeSpecLinkId = 'ux_wizard'),
          onSwitchToQaWizard: () =>
              setState(() => _activeSpecLinkId = 'qa_wizard'),
          disabled: widget.controller.isSending,
          onSelectStage: (stage) => widget.controller.goToCostStage(
            stage,
            validateCurrent: stage.index > project.costSpec.currentStage.index,
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
                key: _costSplitRowKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCollapsed)
                    Container(
                      key: const ValueKey('cost-chat-collapsed-bar'),
                      width: collapsedRailWidth,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          IconButton(
                            key: const ValueKey('cost-chat-expand-btn'),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher le chat IA FinOps / Coûts (50 %)',
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
                      key: const ValueKey('cost-chat-pane'),
                      width: chatWidth,
                      child: CostStageAiChatPane(
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
                    key: const ValueKey('cost-chat-split-handle'),
                    onDoubleTap: () => setState(() => _chatPaneFraction = 0.50),
                    onHorizontalDragDown: (details) {
                      final box =
                          _costSplitRowKey.currentContext?.findRenderObject()
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
                          _costSplitRowKey.currentContext?.findRenderObject()
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
                    child: _buildWorkspaceForCostStage(
                      project.costSpec.currentStage,
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

  Widget _buildWorkspaceForCostStage(CostForgeStage stage) => switch (stage) {
    CostForgeStage.rateCardAssumptions => CostAssumptionsEditorView(
      controller: widget.controller,
    ),
    CostForgeStage.buildWbs => CostWbsEditorView(
      controller: widget.controller,
    ),
    CostForgeStage.runOpex => CostRunEditorView(
      controller: widget.controller,
    ),
    CostForgeStage.tcoReviewExport => CostTcoReviewExportView(
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

class _ActiveFeatureAppBarMenu extends StatelessWidget {
  const _ActiveFeatureAppBarMenu({
    required this.project,
    required this.disabled,
    required this.onManagePortfolio,
    required this.onSelectFeature,
  });

  final SpecForgeProject project;
  final bool disabled;
  final VoidCallback onManagePortfolio;
  final ValueChanged<String> onSelectFeature;

  static const String _manageActionValue = '__manage_portfolio__';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activeFeat = project.activeFeature;

    return PopupMenuButton<String>(
      key: const ValueKey('spec-appbar-feature-switcher'),
      enabled: !disabled,
      tooltip:
          'Feature active : ${activeFeat.displayLabel} — changer de feature ou gérer les initiatives',
      onSelected: (value) {
        if (value == _manageActionValue) {
          onManagePortfolio();
        } else {
          onSelectFeature(value);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: _manageActionValue,
          child: Row(
            children: [
              Icon(
                Icons.account_tree_rounded,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Gérer les Initiatives & Features…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        for (final init in project.initiatives) ...[
          PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(
              init.displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
          for (final feat in init.features)
            CheckedPopupMenuItem<String>(
              key: ValueKey('spec-appbar-feature-item-${feat.id}'),
              value: feat.id,
              checked: feat.id == project.activeFeatureId,
              child: Text(
                feat.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colors.secondary.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_rounded,
              size: 15,
              color: colors.onSecondaryContainer,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                activeFeat.code.trim().isNotEmpty
                    ? activeFeat.code.trim()
                    : activeFeat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: colors.onSecondaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

