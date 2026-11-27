/// Page intermédiaire de gestion du portefeuille d'Initiatives et de Features
/// d'un projet ([ProjectInitiativesView]), point d'entrée vers les 4 Wizards.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/enterprise_rate_card.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_forge_stage.dart';
import '../../models/spec_initiative.dart';
import '../../services/cost_calculator.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_split_handle.dart';
import 'portfolio_ai_chat_pane.dart';

/// Cible d'ouverture de Wizard depuis une [SpecFeatureSpec].
enum SpecPortfolioWizardTarget {
  /// Wizard de spécification métier (8 étapes).
  spec,

  /// Wizard UX & Parcours (4 étapes).
  ux,

  /// Wizard BDD / Gherkin & TDD (4 étapes).
  qa,

  /// Wizard d'estimation de coût IT (4 étapes).
  cost,
}

/// Vue Desktop Maître / Détail listant les Initiatives et Features du projet actif,
/// avec assistant IA de découpage produit et lancement direct des 4 Wizards sur la feature choisie.
class ProjectInitiativesView extends StatefulWidget {
  /// Crée la vue intermédiaire connectée au [controller].
  const ProjectInitiativesView({
    required this.controller,
    required this.onOpenWizard,
    this.onOpenSharedLexicon,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Callback appelé lorsqu'on ouvre l'un des 4 Wizards sur la feature sélectionnée.
  final ValueChanged<SpecPortfolioWizardTarget> onOpenWizard;

  /// Callback optionnel ouvrant directement l'étape 1 (Lexique métier partagé du projet).
  final VoidCallback? onOpenSharedLexicon;

  /// Sélecteur optionnel de pièces jointes transmis au chat IA.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers transmis au chat IA.
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant la présence d'un média dans le presse-papiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers sur `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<ProjectInitiativesView> createState() => _ProjectInitiativesViewState();
}

class _ProjectInitiativesViewState extends State<ProjectInitiativesView> {
  static const double _defaultTreeWidth = 370.0;
  static const double _minTreeWidth = 240.0;
  static const double _minDetailWidth = 340.0;

  final GlobalKey _splitRowKey = GlobalKey();
  final GlobalKey _treeSplitRowKey = GlobalKey();
  double _chatPaneFraction = 0.30;
  double _chatDragOffset = SpecSplitHandle.width / 2;
  double _treeDragOffset = SpecSplitHandle.width / 2;

  String _searchQuery = '';
  SpecPortfolioStatus? _statusFilter;
  RequirementPriority? _priorityFilter;
  final Set<String> _collapsedInitiativeIds = <String>{};

  /// Lorsqu'il est non nul, le panneau droit affiche la fiche de cette initiative
  /// plutôt que la fiche de la feature active.
  String? _inspectedInitiativeId;

  void _toggleChatPane() {
    setState(() {
      _chatPaneFraction = _chatPaneFraction <= 0.0 ? 0.30 : 0.0;
    });
  }

  bool _matchesFeature(SpecFeatureSpec feat, SpecInitiative parentInit) {
    if (_statusFilter != null && feat.effectiveStatus != _statusFilter) {
      return false;
    }
    if (_priorityFilter != null && feat.priority != _priorityFilter) {
      return false;
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return feat.code.toLowerCase().contains(q) ||
        feat.name.toLowerCase().contains(q) ||
        feat.description.toLowerCase().contains(q) ||
        feat.targetRelease.toLowerCase().contains(q) ||
        parentInit.code.toLowerCase().contains(q) ||
        parentInit.name.toLowerCase().contains(q);
  }

  static ({
    double totalDays,
    double totalBuildCost,
    double monthlyRun,
    String currencyCode,
    int pricedFeatures,
  })
  _computeMacroCost(Iterable<SpecFeatureSpec> features) {
    var totalDays = 0.0;
    var totalBuild = 0.0;
    var monthlyRun = 0.0;
    var pricedCount = 0;
    var currency = CostCurrency.eur;
    for (final feat in features) {
      final cs = feat.costSpec;
      if (cs.wbsItems.isEmpty && cs.runItems.isEmpty) continue;
      final summary = CostCalculator.compute(cs);
      if (pricedCount == 0) currency = summary.currency;
      totalDays += summary.fullLot.effectiveTotalDays;
      totalBuild += summary.fullLot.effectiveTotalCost;
      monthlyRun += summary.monthlyRunYear1;
      pricedCount++;
    }
    return (
      totalDays: totalDays,
      totalBuildCost: totalBuild,
      monthlyRun: monthlyRun,
      currencyCode: currency.symbol,
      pricedFeatures: pricedCount,
    );
  }

  Future<void> _showInitiativeDialog(
    BuildContext context, {
    SpecInitiative? existing,
  }) async {
    final project = widget.controller.project;
    if (project == null) return;

    final result = await showDialog<_InitiativeDialogResult>(
      context: context,
      builder: (_) => _PortfolioInitiativeDialog(
        existing: existing,
        defaultCode: existing?.code ?? project.nextInitiativeCode(),
      ),
    );
    if (result == null || !mounted) return;

    if (existing == null) {
      final created = await widget.controller.addInitiative(
        code: result.code,
        name: result.name,
        description: result.description,
        owner: result.owner,
        targetTimeframe: result.targetTimeframe,
        priority: result.priority,
        status: result.status,
        createInitialFeature: result.createFirstFeature,
      );
      if (created != null && mounted) {
        setState(() {
          _inspectedInitiativeId = result.createFirstFeature
              ? null
              : created.id;
        });
      }
    } else {
      await widget.controller.updateInitiativeMetadata(
        initiativeId: existing.id,
        code: result.code,
        name: result.name,
        description: result.description,
        owner: result.owner,
        targetTimeframe: result.targetTimeframe,
        priority: result.priority,
        status: result.status,
      );
    }
  }

  Future<void> _showFeatureDialog(
    BuildContext context, {
    SpecFeatureSpec? existing,
    String? initialInitiativeId,
  }) async {
    final project = widget.controller.project;
    if (project == null) return;

    final defaultInitId =
        initialInitiativeId ??
        (existing != null
            ? project.initiativeOfFeature(existing.id)?.id
            : null) ??
        project.activeInitiative.id;

    final result = await showDialog<_FeatureDialogResult>(
      context: context,
      builder: (_) => _PortfolioFeatureDialog(
        initiatives: project.initiatives,
        existing: existing,
        initialInitiativeId: defaultInitId,
        defaultCode: existing?.code ?? project.nextFeatureCode(),
      ),
    );
    if (result == null || !mounted) return;

    if (existing == null) {
      final created = await widget.controller.addFeature(
        initiativeId: result.initiativeId,
        code: result.code,
        name: result.name,
        description: result.description,
        targetRelease: result.targetRelease,
        priority: result.priority,
        status: result.status,
        disabledSpecStages: result.disabledSpecStages,
      );
      if (created != null && mounted) {
        setState(() {
          _inspectedInitiativeId = null;
          _collapsedInitiativeIds.remove(result.initiativeId);
        });
      }
    } else {
      await widget.controller.updateFeatureMetadata(
        featureId: existing.id,
        targetInitiativeId: result.initiativeId,
        code: result.code,
        name: result.name,
        description: result.description,
        targetRelease: result.targetRelease,
        priority: result.priority,
        status: result.status,
        disabledSpecStages: result.disabledSpecStages,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inspectedInitiative = _inspectedInitiativeId == null
        ? null
        : project.initiativeById(_inspectedInitiativeId);

    return KeyedSubtree(
      key: const ValueKey('spec-project-initiatives-view'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProjectHeader(context, theme, colors, project),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dividerWidth = SpecSplitHandle.width;
                const collapsedRailWidth = 38.0;
                const minChatWidth = 260.0;
                const minWorkspaceWidth = 640.0;
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
                        key: const ValueKey('portfolio-chat-collapsed-bar'),
                        width: collapsedRailWidth,
                        color: colors.surfaceContainerLow,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            IconButton(
                              key: const ValueKey('portfolio-chat-expand-btn'),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Ouvrir le chat IA de découpage produit',
                              onPressed: _toggleChatPane,
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                            const SizedBox(height: 8),
                            Icon(
                              Icons.account_tree_rounded,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      )
                    else
                      SizedBox(
                        key: const ValueKey('portfolio-chat-pane'),
                        width: chatWidth,
                        child: PortfolioAiChatPane(
                          controller: widget.controller,
                          onCollapse: _toggleChatPane,
                          pickAttachments: widget.pickAttachments,
                          pasteAttachments: widget.pasteAttachments,
                          hasClipboardMedia: widget.hasClipboardMedia,
                          pasteClipboardMedia: widget.pasteClipboardMedia,
                        ),
                      ),
                    SpecSplitHandle(
                      key: const ValueKey('portfolio-chat-split-handle'),
                      onDoubleTap: () =>
                          setState(() => _chatPaneFraction = 0.30),
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
                            : 0.55;
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
                      child: LayoutBuilder(
                        builder: (context, workspaceConstraints) {
                          const treeDividerWidth = SpecSplitHandle.width;
                          final workspaceAvailableWidth =
                              (workspaceConstraints.maxWidth - treeDividerWidth)
                                  .clamp(0.0, double.infinity);
                          final minTree =
                              workspaceAvailableWidth >
                                  _minTreeWidth + _minDetailWidth
                              ? _minTreeWidth
                              : workspaceAvailableWidth * 0.25;
                          final maxTree =
                              workspaceAvailableWidth >
                                  _minTreeWidth + _minDetailWidth
                              ? (workspaceAvailableWidth - _minDetailWidth)
                              : workspaceAvailableWidth * 0.65;
                          final storedTreeWidth =
                              widget.controller.panelWidth(
                                SpecForgeController.portfolioTreePanelKey,
                              ) ??
                              _defaultTreeWidth;
                          final double treeWidth = workspaceAvailableWidth <= 0
                              ? 0.0
                              : storedTreeWidth
                                    .clamp(
                                      minTree,
                                      math.max<double>(minTree, maxTree),
                                    )
                                    .toDouble();

                          return Row(
                            key: _treeSplitRowKey,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                key: const ValueKey('portfolio-tree-pane'),
                                width: treeWidth,
                                child: _buildPortfolioTreePane(
                                  context,
                                  theme,
                                  colors,
                                  project,
                                  inspectedInitiative,
                                ),
                              ),
                              SpecSplitHandle(
                                key: const ValueKey(
                                  'portfolio-tree-split-handle',
                                ),
                                onDoubleTap: () => setState(() {
                                  unawaited(
                                    widget.controller.clearPanelWidth(
                                      SpecForgeController.portfolioTreePanelKey,
                                    ),
                                  );
                                }),
                                onHorizontalDragDown: (details) {
                                  final box =
                                      _treeSplitRowKey.currentContext
                                              ?.findRenderObject()
                                          as RenderBox?;
                                  if (box != null) {
                                    final localX = box
                                        .globalToLocal(details.globalPosition)
                                        .dx;
                                    _treeDragOffset = (localX - treeWidth)
                                        .clamp(0.0, SpecSplitHandle.width);
                                  } else {
                                    _treeDragOffset = SpecSplitHandle.width / 2;
                                  }
                                },
                                onHorizontalDragUpdate: (details) {
                                  final box =
                                      _treeSplitRowKey.currentContext
                                              ?.findRenderObject()
                                          as RenderBox?;
                                  if (box == null ||
                                      workspaceAvailableWidth <= 0) {
                                    return;
                                  }
                                  final localX = box
                                      .globalToLocal(details.globalPosition)
                                      .dx;
                                  final nextWidth = localX - _treeDragOffset;
                                  final clamped = nextWidth
                                      .clamp(
                                        minTree,
                                        math.max<double>(minTree, maxTree),
                                      )
                                      .toDouble();
                                  setState(() {
                                    widget.controller.setPanelWidth(
                                      SpecForgeController.portfolioTreePanelKey,
                                      clamped,
                                    );
                                  });
                                },
                                onHorizontalDragEnd: (_) => unawaited(
                                  widget.controller.persistPanelWidths(),
                                ),
                              ),
                              Expanded(
                                child: inspectedInitiative != null
                                    ? _buildInitiativeDetailPane(
                                        context,
                                        theme,
                                        colors,
                                        project,
                                        inspectedInitiative,
                                      )
                                    : _buildFeatureDetailPane(
                                        context,
                                        theme,
                                        colors,
                                        project,
                                        project.activeFeature,
                                        project.activeInitiative,
                                      ),
                              ),
                            ],
                          );
                        },
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
  }

  Widget _buildProjectHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    SpecForgeProject project,
  ) {
    final allFeats = project.allFeatures;
    final validatedCount = allFeats
        .where((f) => f.effectiveStatus == SpecPortfolioStatus.validated)
        .length;
    final inProgressCount = allFeats
        .where((f) => f.effectiveStatus == SpecPortfolioStatus.inProgress)
        .length;
    final macroCost = _computeMacroCost(allFeats);

    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.account_tree_rounded,
                    size: 20,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${project.name} — Initiatives & Features',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${project.initiatives.length} initiative(s) · '
                        '${allFeats.length} feature(s) '
                        '($validatedCount validée(s), $inProgressCount en cours)'
                        '${macroCost.pricedFeatures > 0 ? ' · Cumul chiffré : ${CostCalculator.formatDays(macroCost.totalDays)} (${macroCost.totalBuildCost.toStringAsFixed(0)} ${macroCost.currencyCode})' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.onOpenSharedLexicon != null)
                ActionChip(
                  key: const ValueKey('portfolio-shared-lexicon-chip'),
                  avatar: const Icon(Icons.menu_book_outlined, size: 16),
                  tooltip:
                      'Ouvrir le Lexique métier partagé entre toutes les features du projet',
                  label: Text(
                    'Lexique partagé (${project.lexicon.terms.length})',
                  ),
                  onPressed: widget.controller.isSending
                      ? null
                      : widget.onOpenSharedLexicon,
                ),
              OutlinedButton.icon(
                key: const ValueKey('portfolio-add-initiative-btn'),
                onPressed: widget.controller.isSending
                    ? null
                    : () => _showInitiativeDialog(context),
                icon: const Icon(Icons.create_new_folder_outlined, size: 17),
                label: const Text('+ Initiative'),
              ),
              FilledButton.icon(
                key: const ValueKey('portfolio-add-feature-btn'),
                onPressed: widget.controller.isSending
                    ? null
                    : () => _showFeatureDialog(
                        context,
                        initialInitiativeId:
                            _inspectedInitiativeId ??
                            project.activeInitiative.id,
                      ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('+ Feature'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioTreePane(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    SpecForgeProject project,
    SpecInitiative? inspectedInitiative,
  ) {
    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('portfolio-search-field'),
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: 'Filtrer initiatives ou features…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => setState(() => _searchQuery = ''),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        selected: _priorityFilter == RequirementPriority.must,
                        label: const Text('Must'),
                        onSelected: (sel) => setState(
                          () => _priorityFilter = sel
                              ? RequirementPriority.must
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      for (final status in [
                        SpecPortfolioStatus.draft,
                        SpecPortfolioStatus.inProgress,
                        SpecPortfolioStatus.validated,
                      ]) ...[
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          selected: _statusFilter == status,
                          label: Text(status.label),
                          onSelected: (sel) => setState(
                            () => _statusFilter = sel ? status : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: project.initiatives.length,
              itemBuilder: (context, index) {
                final init = project.initiatives[index];
                final visibleFeatures = [
                  for (final f in init.features)
                    if (_matchesFeature(f, init)) f,
                ];
                final hasFilter =
                    _searchQuery.trim().isNotEmpty ||
                    _statusFilter != null ||
                    _priorityFilter != null;
                if (hasFilter && visibleFeatures.isEmpty) {
                  return const SizedBox.shrink();
                }

                final isCollapsed =
                    !hasFilter && _collapsedInitiativeIds.contains(init.id);
                final isInitiativeInspected =
                    inspectedInitiative?.id == init.id;

                return Card(
                  key: ValueKey('portfolio-initiative-card-${init.id}'),
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isInitiativeInspected
                          ? colors.primary
                          : colors.outlineVariant,
                      width: isInitiativeInspected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        key: ValueKey('portfolio-initiative-header-${init.id}'),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        onTap: () => setState(() {
                          _inspectedInitiativeId = init.id;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isInitiativeInspected
                                ? colors.primaryContainer.withValues(alpha: 0.5)
                                : colors.surfaceContainerLow,
                            borderRadius: BorderRadius.vertical(
                              top: const Radius.circular(11),
                              bottom: isCollapsed
                                  ? const Radius.circular(11)
                                  : Radius.zero,
                            ),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => setState(() {
                                  if (_collapsedInitiativeIds.contains(
                                    init.id,
                                  )) {
                                    _collapsedInitiativeIds.remove(init.id);
                                  } else {
                                    _collapsedInitiativeIds.add(init.id);
                                  }
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    isCollapsed
                                        ? Icons.chevron_right_rounded
                                        : Icons.expand_more_rounded,
                                    size: 18,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      init.displayLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      '${init.features.length} feature(s) · ${init.priority.code}'
                                      '${init.targetTimeframe.isNotEmpty ? ' · ${init.targetTimeframe}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'portfolio-add-feature-in-${init.id}',
                                ),
                                tooltip:
                                    'Ajouter une feature dans ${init.name}',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                onPressed: widget.controller.isSending
                                    ? null
                                    : () => _showFeatureDialog(
                                        context,
                                        initialInitiativeId: init.id,
                                      ),
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!isCollapsed) ...[
                        if (visibleFeatures.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Aucune feature dans cette initiative.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          for (final feat in visibleFeatures)
                            _FeatureTreeTile(
                              feature: feat,
                              isSelected:
                                  inspectedInitiative == null &&
                                  project.activeFeatureId == feat.id,
                              isActiveInProject:
                                  project.activeFeatureId == feat.id,
                              onTap: () {
                                setState(() => _inspectedInitiativeId = null);
                                widget.controller.selectActiveFeature(feat.id);
                              },
                            ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitiativeDetailPane(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    SpecForgeProject project,
    SpecInitiative initiative,
  ) {
    final initIndex = project.initiatives.indexWhere(
      (i) => i.id == initiative.id,
    );
    final initCost = _computeMacroCost(initiative.features);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusBadge(status: initiative.effectiveStatus),
                          const SizedBox(width: 8),
                          _PriorityBadge(priority: initiative.priority),
                          if (initiative.targetTimeframe.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(initiative.targetTimeframe),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Monter l’initiative',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                initIndex > 0 && !widget.controller.isSending
                                ? () => widget.controller.moveInitiative(
                                    initiative.id,
                                    -1,
                                  )
                                : null,
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                          IconButton(
                            tooltip: 'Descendre l’initiative',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                initIndex >= 0 &&
                                    initIndex <
                                        project.initiatives.length - 1 &&
                                    !widget.controller.isSending
                                ? () => widget.controller.moveInitiative(
                                    initiative.id,
                                    1,
                                  )
                                : null,
                            icon: const Icon(Icons.arrow_downward_rounded),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              'portfolio-edit-initiative-btn',
                            ),
                            onPressed: widget.controller.isSending
                                ? null
                                : () => _showInitiativeDialog(
                                    context,
                                    existing: initiative,
                                  ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Modifier'),
                          ),
                          if (project.initiatives.length > 1) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              key: const ValueKey(
                                'portfolio-delete-initiative-btn',
                              ),
                              tooltip: 'Supprimer cette initiative',
                              color: colors.error,
                              onPressed: widget.controller.isSending
                                  ? null
                                  : () async {
                                      await widget.controller.deleteInitiative(
                                        initiative.id,
                                      );
                                      if (mounted) {
                                        setState(
                                          () => _inspectedInitiativeId = null,
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    initiative.displayLabel,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (initiative.owner.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sponsor / Owner : ${initiative.owner}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    initiative.description.isNotEmpty
                        ? initiative.description
                        : 'Aucun objectif stratégique renseigné pour cette initiative.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: initiative.description.isNotEmpty
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                  if (initCost.pricedFeatures > 0) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Consolidation financière de l’initiative (${initCost.pricedFeatures}/${initiative.features.length} feature(s) chiffrée(s)) : '
                        '${CostCalculator.formatDays(initCost.totalDays)} · '
                        'Build ${initCost.totalBuildCost.toStringAsFixed(0)} ${initCost.currencyCode}'
                        '${initCost.monthlyRun > 0 ? ' · Run ${initCost.monthlyRun.toStringAsFixed(0)} ${initCost.currencyCode}/mois' : ''}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Features de l’initiative (${initiative.features.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: widget.controller.isSending
                    ? null
                    : () => _showFeatureDialog(
                        context,
                        initialInitiativeId: initiative.id,
                      ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter une feature'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final feat in initiative.features)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                title: Text(
                  feat.displayLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${feat.effectiveStatus.label} · ${feat.priority.code} · '
                  '${feat.businessObjects.length} objet(s) · ${feat.businessRules.length} règle(s)'
                  '${feat.description.isNotEmpty ? '\n${feat.description}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: () async {
                    setState(() => _inspectedInitiativeId = null);
                    await widget.controller.selectActiveFeature(feat.id);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Ouvrir la feature'),
                ),
                onTap: () {
                  setState(() => _inspectedInitiativeId = null);
                  widget.controller.selectActiveFeature(feat.id);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureDetailPane(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    SpecForgeProject project,
    SpecFeatureSpec feature,
    SpecInitiative parentInitiative,
  ) {
    final featIndex = parentInitiative.features.indexWhere(
      (f) => f.id == feature.id,
    );
    final costSubtitle = _featureCostSummary(feature);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(
                              () =>
                                  _inspectedInitiativeId = parentInitiative.id,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 280),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_outlined,
                                      size: 14,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        parentInitiative.displayLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _StatusBadge(status: feature.effectiveStatus),
                          _PriorityBadge(priority: feature.priority),
                          if (feature.targetRelease.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.tertiaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                feature.targetRelease,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onTertiaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Monter la feature',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                featIndex > 0 && !widget.controller.isSending
                                ? () => widget.controller.moveFeature(
                                    parentInitiative.id,
                                    feature.id,
                                    -1,
                                  )
                                : null,
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                          IconButton(
                            tooltip: 'Descendre la feature',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                featIndex >= 0 &&
                                    featIndex <
                                        parentInitiative.features.length - 1 &&
                                    !widget.controller.isSending
                                ? () => widget.controller.moveFeature(
                                    parentInitiative.id,
                                    feature.id,
                                    1,
                                  )
                                : null,
                            icon: const Icon(Icons.arrow_downward_rounded),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('portfolio-edit-feature-btn'),
                            onPressed: widget.controller.isSending
                                ? null
                                : () => _showFeatureDialog(
                                    context,
                                    existing: feature,
                                  ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Modifier le cadrage'),
                          ),
                          if (project.totalFeatureCount > 1)
                            IconButton(
                              key: const ValueKey(
                                'portfolio-delete-feature-btn',
                              ),
                              tooltip: 'Supprimer cette feature',
                              color: colors.error,
                              onPressed: widget.controller.isSending
                                  ? null
                                  : () => widget.controller.deleteFeature(
                                      feature.id,
                                    ),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    feature.displayLabel,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    feature.description.isNotEmpty
                        ? feature.description
                        : (feature.vision.ideaSummary.isNotEmpty
                              ? feature.vision.ideaSummary
                              : 'Décrivez l’hypothèse de valeur ou ouvrez directement le Wizard de spécification pour cadrer cette feature avec l’IA.'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          (feature.description.isNotEmpty ||
                              feature.vision.ideaSummary.isNotEmpty)
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _FeatureSpecStagesCard(
            feature: feature,
            disabled: widget.controller.isSending,
            onToggleOptionalStage: (stage, enabled) =>
                widget.controller.setFeatureStageEnabled(
                  featureId: feature.id,
                  stage: stage,
                  enabled: enabled,
                ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Icon(Icons.rocket_launch_outlined, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ateliers Wizards de la feature « ${feature.name} »',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Chaque feature dispose de ses propres livrables de spécification (${feature.enabledSpecStages.length}/${SpecForgeStage.values.length} étapes actives), UX, BDD/TDD et Coûts IT, tout en partageant le Lexique métier du projet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, gridConstraints) {
              final twoColumns = gridConstraints.maxWidth >= 500;
              final enabledStagesSummary = feature.enabledSpecStages
                  .map((s) => s.shortLabel)
                  .join(', ');
              final cards = <Widget>[
                _WizardLaunchCard(
                  cardKey: const ValueKey('portfolio-open-wizard-spec'),
                  icon: Icons.auto_awesome_rounded,
                  title: 'Wizard de spécification',
                  badge:
                      'Étape ${feature.stepNumberFor(feature.currentStage)}/${feature.enabledSpecStages.length} · ${feature.currentStage.shortLabel}',
                  metrics:
                      '${feature.validatedFeatureStagesCount}/${feature.enabledFeatureScopedStages.length} étapes validées · '
                      '${feature.businessObjects.length} objet(s) · '
                      '${feature.businessRules.length} règle(s)'
                      '${feature.isStageEnabled(SpecForgeStage.exampleMapping) ? ' · ${feature.exampleMappings.length} Example Map(s)' : ''}',
                  description: '$enabledStagesSummary.',
                  buttonLabel: 'Ouvrir le Wizard Spec',
                  isPrimary: true,
                  onOpen: widget.controller.isSending
                      ? null
                      : () =>
                            widget.onOpenWizard(SpecPortfolioWizardTarget.spec),
                ),
                _WizardLaunchCard(
                  cardKey: const ValueKey('portfolio-open-wizard-ux'),
                  icon: Icons.design_services_rounded,
                  title: 'Wizard UX & Parcours',
                  badge: feature.uxSpec.currentStage.shortLabel,
                  metrics:
                      '${feature.uxSpec.journeys.length} parcours · '
                      '${feature.uxSpec.navigation.routes.length} route(s) · '
                      '${feature.uxSpec.screens.length} écran(s)',
                  description:
                      'Parcours utilisateurs bout-en-bout, architecture de navigation et blueprints d’écrans.',
                  buttonLabel: 'Ouvrir le Wizard UX',
                  onOpen: widget.controller.isSending
                      ? null
                      : () => widget.onOpenWizard(SpecPortfolioWizardTarget.ux),
                ),
                _WizardLaunchCard(
                  cardKey: const ValueKey('portfolio-open-wizard-qa'),
                  icon: Icons.science_rounded,
                  title: 'Wizard BDD / Gherkin & TDD',
                  badge: feature.qaSpec.currentStage.shortLabel,
                  metrics:
                      '${feature.qaSpec.fixtures.length} fixture(s) · '
                      '${feature.qaSpec.features.length} .feature · '
                      '${feature.qaSpec.totalTddCaseCount} cas TDD',
                  description:
                      'Jeux d’essais déterministes, scénarios Gherkin exécutables et suites de tests TDD.',
                  buttonLabel: 'Ouvrir le Wizard BDD / TDD',
                  onOpen: widget.controller.isSending
                      ? null
                      : () => widget.onOpenWizard(SpecPortfolioWizardTarget.qa),
                ),
                _WizardLaunchCard(
                  cardKey: const ValueKey('portfolio-open-wizard-cost'),
                  icon: Icons.calculate_rounded,
                  title: 'Estimation de coût IT',
                  badge: feature.costSpec.currentStage.shortLabel,
                  metrics: costSubtitle,
                  description:
                      'Chiffrage PERT (j/h), lots Build WBS, coûts récurrents Run/OPEX, gains IA et risques.',
                  buttonLabel: 'Ouvrir le Chiffrage',
                  onOpen: widget.controller.isSending
                      ? null
                      : () =>
                            widget.onOpenWizard(SpecPortfolioWizardTarget.cost),
                ),
              ];

              if (!twoColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final card in cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: card,
                      ),
                  ],
                );
              }

              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 14),
                        Expanded(child: cards[1]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[2]),
                        const SizedBox(width: 14),
                        Expanded(child: cards[3]),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _featureCostSummary(SpecFeatureSpec feature) {
    final cs = feature.costSpec;
    if (cs.wbsItems.isEmpty && cs.runItems.isEmpty) {
      return 'À chiffrer · ${cs.currency.code}';
    }
    final summary = CostCalculator.compute(cs);
    final buildDays = CostCalculator.formatDays(
      summary.fullLot.effectiveTotalDays,
    );
    final buildCost = CostCalculator.formatAmount(
      summary.fullLot.effectiveTotalCost,
      summary.currency,
      compact: true,
    );
    if (summary.monthlyRunYear1 > 0) {
      final runMonthly = CostCalculator.formatAmount(
        summary.monthlyRunYear1,
        summary.currency,
        compact: true,
      );
      return '$buildDays · Build $buildCost · Run $runMonthly/mois';
    }
    return '$buildDays · Build $buildCost';
  }
}

class _FeatureTreeTile extends StatelessWidget {
  const _FeatureTreeTile({
    required this.feature,
    required this.isSelected,
    required this.isActiveInProject,
    required this.onTap,
  });

  final SpecFeatureSpec feature;
  final bool isSelected;
  final bool isActiveInProject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return InkWell(
      key: ValueKey('portfolio-feature-tile-${feature.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
            left: BorderSide(
              color: isActiveInProject ? colors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    feature.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isActiveInProject
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _PriorityBadge(priority: feature.priority, compact: true),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusBadge(status: feature.effectiveStatus, compact: true),
                if (feature.targetRelease.isNotEmpty)
                  Text(
                    feature.targetRelease,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.tertiary,
                    ),
                  ),
                Text(
                  '${feature.businessObjects.length} obj · ${feature.businessRules.length} RG',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (feature.uxSpec.screens.isNotEmpty)
                  Text(
                    '· ${feature.uxSpec.screens.length} écr.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (feature.qaSpec.features.isNotEmpty)
                  Text(
                    '· ${feature.qaSpec.features.length} BDD',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureSpecStagesCard extends StatelessWidget {
  const _FeatureSpecStagesCard({
    required this.feature,
    required this.disabled,
    required this.onToggleOptionalStage,
  });

  final SpecFeatureSpec feature;
  final bool disabled;
  final void Function(SpecForgeStage stage, bool enabled) onToggleOptionalStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabledCount = feature.enabledSpecStages.length;
    final hasPreservedDisabledData =
        (!feature.isStageEnabled(SpecForgeStage.eventStorming) &&
            feature.eventStorming.hasContent) ||
        (!feature.isStageEnabled(SpecForgeStage.exampleMapping) &&
            feature.exampleMappings.isNotEmpty);

    return Card(
      key: const ValueKey('portfolio-feature-spec-stages-card'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Étapes de spécification ($enabledCount/${SpecForgeStage.values.length} actives)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Activez ou désactivez les étapes optionnelles (Event Storming, Example Mapping) pour cette feature.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final stage in SpecForgeStage.values)
                  if (stage.isOptional)
                    Tooltip(
                      message: feature.isStageEnabled(stage)
                          ? 'Étape optionnelle active — cliquer pour la désactiver sur cette feature'
                          : 'Étape optionnelle désactivée — cliquer pour l’activer sur cette feature',
                      child: FilterChip(
                        key: ValueKey(
                          'portfolio-feature-stage-toggle-${stage.name}',
                        ),
                        visualDensity: VisualDensity.compact,
                        selected: feature.isStageEnabled(stage),
                        avatar: feature.isStageEnabled(stage)
                            ? null
                            : Icon(
                                stage.icon,
                                size: 15,
                                color: colors.onSurfaceVariant,
                              ),
                        label: Text(
                          feature.isStageEnabled(stage)
                              ? '${feature.stepNumberFor(stage)}. ${stage.shortLabel} (optionnel)'
                              : '${stage.shortLabel} (désactivée)',
                        ),
                        onSelected: disabled
                            ? null
                            : (selected) =>
                                  onToggleOptionalStage(stage, selected),
                      ),
                    )
                  else
                    Container(
                      key: ValueKey(
                        'portfolio-feature-stage-required-${stage.name}',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            stage.icon,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${feature.stepNumberFor(stage)}. ${stage.shortLabel}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
            if (hasPreservedDisabledData) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Les données déjà saisies sur une étape désactivée sont conservées et réapparaîtront si vous la réactivez.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WizardLaunchCard extends StatelessWidget {
  const _WizardLaunchCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.badge,
    required this.metrics,
    required this.description,
    required this.buttonLabel,
    required this.onOpen,
    this.isPrimary = false,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final String badge;
  final String metrics;
  final String description;
  final String buttonLabel;
  final VoidCallback? onOpen;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      key: cardKey,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPrimary
              ? colors.primary.withValues(alpha: 0.6)
              : colors.outlineVariant,
          width: isPrimary ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? colors.primaryContainer
                          : colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isPrimary
                          ? colors.onPrimaryContainer
                          : colors.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  metrics,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: isPrimary
                    ? FilledButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: Text(buttonLabel),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: Text(buttonLabel),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.compact = false});

  final SpecPortfolioStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (Color bg, Color fg) = switch (status) {
      SpecPortfolioStatus.validated => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      SpecPortfolioStatus.inProgress => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      SpecPortfolioStatus.archived => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
      SpecPortfolioStatus.draft => (
        colors.surfaceContainerHigh,
        colors.onSurfaceVariant,
      ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: compact ? 10.5 : null,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority, this.compact = false});

  final RequirementPriority priority;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isMust = priority == RequirementPriority.must;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1.5 : 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isMust
              ? colors.primary.withValues(alpha: 0.5)
              : colors.outlineVariant,
        ),
      ),
      child: Text(
        priority.code,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: compact ? 10 : null,
          fontWeight: FontWeight.w700,
          color: isMust ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InitiativeDialogResult {
  const _InitiativeDialogResult({
    required this.code,
    required this.name,
    required this.description,
    required this.owner,
    required this.targetTimeframe,
    required this.priority,
    required this.status,
    required this.createFirstFeature,
  });

  final String code;
  final String name;
  final String description;
  final String owner;
  final String targetTimeframe;
  final RequirementPriority priority;
  final SpecPortfolioStatus status;
  final bool createFirstFeature;
}

class _PortfolioInitiativeDialog extends StatefulWidget {
  const _PortfolioInitiativeDialog({
    required this.existing,
    required this.defaultCode,
  });

  final SpecInitiative? existing;
  final String defaultCode;

  @override
  State<_PortfolioInitiativeDialog> createState() =>
      _PortfolioInitiativeDialogState();
}

class _PortfolioInitiativeDialogState
    extends State<_PortfolioInitiativeDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _ownerCtrl;
  late final TextEditingController _timeframeCtrl;
  late RequirementPriority _priority;
  late SpecPortfolioStatus _status;
  late bool _createFirstFeature;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.defaultCode);
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _ownerCtrl = TextEditingController(text: widget.existing?.owner ?? '');
    _timeframeCtrl = TextEditingController(
      text: widget.existing?.targetTimeframe ?? '',
    );
    _priority = widget.existing?.priority ?? RequirementPriority.must;
    _status = widget.existing?.status ?? SpecPortfolioStatus.draft;
    _createFirstFeature = widget.existing == null;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _ownerCtrl.dispose();
    _timeframeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouvelle initiative'
            : 'Modifier l’initiative',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: const ValueKey('portfolio-initiative-code-field'),
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: 'INIT-01',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('portfolio-initiative-name-field'),
                      controller: _nameCtrl,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nom de l’initiative *',
                        hintText: 'Ex. Socle Parc & Réservations',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('portfolio-initiative-desc-field'),
                controller: _descCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Objectif stratégique & périmètre',
                  hintText:
                      'Résultat métier attendu, KPIs visés ou périmètre couvert…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ownerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Sponsor / Owner',
                        hintText: 'Ex. Direction Produit',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _timeframeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Horizon cible',
                        hintText: 'Ex. MVP · T1 2027',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<RequirementPriority>(
                      isExpanded: true,
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Priorité MoSCoW',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in RequirementPriority.values)
                          DropdownMenuItem(
                            value: p,
                            child: Text(
                              '${p.code} — ${p.label}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _priority = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<SpecPortfolioStatus>(
                      isExpanded: true,
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Statut',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in SpecPortfolioStatus.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _status = val);
                      },
                    ),
                  ),
                ],
              ),
              if (widget.existing == null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _createFirstFeature,
                  onChanged: (val) =>
                      setState(() => _createFirstFeature = val ?? true),
                  title: const Text(
                    'Créer automatiquement une première feature dans cette initiative',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('portfolio-initiative-save-btn'),
          onPressed: _nameCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _InitiativeDialogResult(
                    code: _codeCtrl.text,
                    name: _nameCtrl.text,
                    description: _descCtrl.text,
                    owner: _ownerCtrl.text,
                    targetTimeframe: _timeframeCtrl.text,
                    priority: _priority,
                    status: _status,
                    createFirstFeature: _createFirstFeature,
                  ),
                ),
          child: Text(widget.existing == null ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }
}

class _FeatureDialogResult {
  const _FeatureDialogResult({
    required this.initiativeId,
    required this.code,
    required this.name,
    required this.description,
    required this.targetRelease,
    required this.priority,
    required this.status,
    required this.disabledSpecStages,
  });

  final String initiativeId;
  final String code;
  final String name;
  final String description;
  final String targetRelease;
  final RequirementPriority priority;
  final SpecPortfolioStatus status;
  final Set<SpecForgeStage> disabledSpecStages;
}

class _PortfolioFeatureDialog extends StatefulWidget {
  const _PortfolioFeatureDialog({
    required this.initiatives,
    required this.existing,
    required this.initialInitiativeId,
    required this.defaultCode,
  });

  final List<SpecInitiative> initiatives;
  final SpecFeatureSpec? existing;
  final String initialInitiativeId;
  final String defaultCode;

  @override
  State<_PortfolioFeatureDialog> createState() =>
      _PortfolioFeatureDialogState();
}

class _PortfolioFeatureDialogState extends State<_PortfolioFeatureDialog> {
  late String _selectedInitId;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _releaseCtrl;
  late RequirementPriority _priority;
  late SpecPortfolioStatus _status;
  late Set<SpecForgeStage> _disabledSpecStages;

  @override
  void initState() {
    super.initState();
    _selectedInitId = widget.initialInitiativeId;
    _codeCtrl = TextEditingController(text: widget.defaultCode);
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _releaseCtrl = TextEditingController(
      text: widget.existing?.targetRelease ?? '',
    );
    _priority = widget.existing?.priority ?? RequirementPriority.must;
    _status = widget.existing?.status ?? SpecPortfolioStatus.draft;
    _disabledSpecStages = Set<SpecForgeStage>.from(
      widget.existing?.disabledSpecStages ?? const <SpecForgeStage>{},
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _releaseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouvelle feature'
            : 'Modifier le cadrage de la feature',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('portfolio-feature-initiative-dropdown'),
                isExpanded: true,
                initialValue: _selectedInitId,
                decoration: const InputDecoration(
                  labelText: 'Initiative parente',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final init in widget.initiatives)
                    DropdownMenuItem(
                      value: init.id,
                      child: Text(
                        init.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedInitId = val);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: const ValueKey('portfolio-feature-code-field'),
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: 'FEAT-01',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('portfolio-feature-name-field'),
                      controller: _nameCtrl,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nom de la feature *',
                        hintText: 'Ex. Réservation de véhicule',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('portfolio-feature-desc-field'),
                controller: _descCtrl,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText:
                      'Description & hypothèse de valeur (transmise aux Wizards)',
                  hintText:
                      'Utilisateurs concernés, parcours principal, règles clés…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('portfolio-feature-release-field'),
                      controller: _releaseCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Lot / Jalon cible',
                        hintText: 'Ex. MVP, Lot 1, V2',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<RequirementPriority>(
                      isExpanded: true,
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Priorité MoSCoW',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in RequirementPriority.values)
                          DropdownMenuItem(
                            value: p,
                            child: Text(
                              '${p.code} — ${p.label}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _priority = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SpecPortfolioStatus>(
                isExpanded: true,
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Statut',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in SpecPortfolioStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _status = val);
                },
              ),
              const SizedBox(height: 14),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Étapes de spécification optionnelles',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choisissez les ateliers facultatifs à inclure dans le Wizard de spécification pour cette feature.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (final stage in SpecForgeStage.optionalStages)
                        CheckboxListTile(
                          key: ValueKey(
                            'portfolio-feature-dialog-stage-${stage.name}',
                          ),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: !_disabledSpecStages.contains(stage),
                          onChanged: (enabled) => setState(() {
                            if (enabled ?? true) {
                              _disabledSpecStages.remove(stage);
                            } else {
                              _disabledSpecStages.add(stage);
                            }
                          }),
                          title: Text(stage.title),
                          subtitle: Text(
                            stage.agentSubtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('portfolio-feature-save-btn'),
          onPressed: _nameCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _FeatureDialogResult(
                    initiativeId: _selectedInitId,
                    code: _codeCtrl.text,
                    name: _nameCtrl.text,
                    description: _descCtrl.text,
                    targetRelease: _releaseCtrl.text,
                    priority: _priority,
                    status: _status,
                    disabledSpecStages: Set<SpecForgeStage>.unmodifiable(
                      _disabledSpecStages,
                    ),
                  ),
                ),
          child: Text(widget.existing == null ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }
}

