/// Page « Cas d’usage & orchestration » de l'espace Design, contextualisée
/// par le domaine en cours via son fil d'Ariane ([UseCaseOrchestrationView]) :
/// chat IA dédié à gauche et atelier structuré en 3 onglets (`Cartographie`,
/// `Use Cases`, `Sagas & Compensations`) avec édition manuelle à droite.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;

import '../../models/domain_catalog.dart';
import '../../models/domain_contracts.dart';
import '../../models/spec_forge_project.dart';
import '../../models/usecase_orchestration_spec.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_split_handle.dart';
import '../workspace/markdown_viewer_dialog.dart';
import 'contract_entry_view.dart'
    show
        contractStageIcons,
        contractStageLabels,
        contractStatusColor,
        contractStatusLabels;
import 'design_domain_breadcrumb.dart';
import 'saga_compensation_table.dart';
import 'usecase_fields_tree.dart';
import 'usecase_orchestration_chat_pane.dart';

List<String> _splitLines(String raw) => [
  for (final line in raw.split(RegExp(r'\r?\n')))
    if (line.trim().isNotEmpty) line.trim(),
];

List<String> _splitCommasOrLines(String raw) => [
  for (final part in raw.split(RegExp(r'[\r\n,]+')))
    if (part.trim().isNotEmpty) part.trim(),
];

List<UseCaseFieldSpec> _parseFieldLines(String raw) => [
  for (final line in _splitLines(raw)) UseCaseFieldSpec.fromJson(line),
];

String _formatFieldLines(List<UseCaseFieldSpec> fields) => [
  for (final f in fields)
    '${f.name}: ${f.type}'
        '${f.isArray && !f.type.trim().endsWith('[]') ? '[]' : ''}'
        '${f.required == true && !f.type.trim().endsWith('!') ? '!' : ''}'
        '${f.nullable && !f.type.trim().endsWith('?') ? '?' : ''}'
        '${f.constraints.isEmpty ? '' : ' (${f.constraints})'}',
].join('\n');

/// Affiche la page « Cas d’usage & orchestration » avec le fil d’Ariane
/// permettant de consulter et changer le domaine en cours, le chat IA à gauche
/// et la cartographie, les Use Cases CQRS et les Sagas Mermaid à droite.
class UseCaseOrchestrationView extends StatefulWidget {
  /// Crée la page à partir des domaines du catalogue actif de [controller].
  const UseCaseOrchestrationView({
    required this.controller,
    required this.onBack,
    required this.onManageDomains,
    this.initialDomainId,
    this.onDomainChanged,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    this.markdownViewerSurfaceBuilder,
    this.markdownBrowserLauncher,
    super.key,
  });

  /// Contrôleur principal portant le catalogue des domaines et le projet actif.
  final SpecForgeController controller;

  /// Revient au menu Design.
  final VoidCallback onBack;

  /// Ouvre la gestion des domaines lorsqu'aucun domaine n'est défini.
  final VoidCallback onManageDomains;

  /// Identifiant optionnel du domaine sélectionné à l'ouverture de la vue.
  final String? initialDomainId;

  /// Notifie le parent lorsqu'un autre domaine est sélectionné.
  final ValueChanged<String?>? onDomainChanged;

  /// Sélecteurs optionnels de pièces jointes et presse-papiers pour le chat IA.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  /// Substitut optionnel de la WebView dans le visualisateur Markdown/Mermaid (tests).
  final SpecMarkdownViewerSurfaceBuilder? markdownViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour le visualisateur Markdown/Mermaid (tests).
  final SpecMarkdownBrowserLauncher? markdownBrowserLauncher;

  @override
  State<UseCaseOrchestrationView> createState() =>
      _UseCaseOrchestrationViewState();
}

class _UseCaseOrchestrationViewState extends State<UseCaseOrchestrationView>
    with SingleTickerProviderStateMixin {
  static const double _defaultChatFraction = 0.36;

  final GlobalKey _splitKey = GlobalKey();
  double _chatFraction = _defaultChatFraction;
  double _dragOffset = SpecSplitHandle.width / 2;
  String? _selectedId;
  late final TabController _tabController;
  final Set<String> _collapsedUseCaseIds = <String>{};
  final Set<String> _collapsedUseCaseSectionKeys = <String>{};
  final Set<String> _collapsedSagaIds = <String>{};
  final Set<String> _collapsedSagaSectionKeys = <String>{};

  void _toggleSetKey(Set<String> set, String key) {
    setState(() {
      if (!set.remove(key)) {
        set.add(key);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedId =
        widget.initialDomainId ?? widget.controller.activeDesignDomainId;
    final initialTab = _selectedId != null
        ? widget.controller.useCaseOrchestrationActiveTab(_selectedId!)
        : UseCaseOrchestrationTab.cartography;
    _tabController = TabController(
      length: UseCaseOrchestrationTab.values.length,
      vsync: this,
      initialIndex: initialTab.index,
    );
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(UseCaseOrchestrationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDomainId != null &&
        widget.initialDomainId != oldWidget.initialDomainId) {
      _selectedId = widget.initialDomainId;
      _syncTabWithDomain(_selectedId);
    }
  }

  void _syncTabWithDomain(String? domainId) {
    if (domainId == null) return;
    final stored = widget.controller.useCaseOrchestrationActiveTab(domainId);
    if (_tabController.index != stored.index) {
      _tabController.index = stored.index;
    }
  }

  void _onTabChanged() {
    if (!mounted) return;
    final domain = _resolveSelectedDomain();
    if (domain != null) {
      widget.controller.setUseCaseOrchestrationActiveTab(
        domain.id,
        UseCaseOrchestrationTab.values[_tabController.index],
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  FunctionalDomain? _resolveSelectedDomain() {
    final domains = widget.controller.domainCatalog.domains;
    final effectiveDomainId =
        _selectedId ?? widget.controller.activeDesignDomainId;
    return domains
            .where((domain) => domain.id == effectiveDomainId)
            .firstOrNull ??
        domains.firstOrNull;
  }

  void _selectDomain(FunctionalDomain domain) {
    if (domain.id == _selectedId &&
        widget.controller.activeDesignDomainId == domain.id) {
      return;
    }
    setState(() => _selectedId = domain.id);
    widget.controller.setActiveDesignDomainId(domain.id);
    _syncTabWithDomain(domain.id);
    widget.onDomainChanged?.call(domain.id);
  }

  static ContractStatus _nextStatus(ContractStatus? current) => switch (current) {
    null || ContractStatus.pending => ContractStatus.inProgress,
    ContractStatus.inProgress => ContractStatus.done,
    ContractStatus.done => ContractStatus.pending,
  };

  Future<void> _cycleUseCaseStage(
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec,
    ApplicationUseCaseSpec useCase,
    ContractStage stage,
  ) {
    final nextStates = Map<ContractStage, ContractStatus>.from(useCase.states)
      ..[stage] = _nextStatus(useCase.states[stage]);
    final updated = useCase.copyWith(states: nextStates);
    return _saveSpec(
      domain.id,
      spec.copyWith(
        useCases: [
          for (final item in spec.useCases)
            if (item.id == useCase.id) updated else item,
        ],
      ),
    );
  }

  Future<void> _cycleSagaStage(
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec,
    OrchestrationSagaSpec saga,
    ContractStage stage,
  ) {
    final nextStates = Map<ContractStage, ContractStatus>.from(saga.states)
      ..[stage] = _nextStatus(saga.states[stage]);
    final updated = saga.copyWith(states: nextStates);
    return _saveSpec(
      domain.id,
      spec.copyWith(
        sagas: [
          for (final item in spec.sagas)
            if (item.id == saga.id) updated else item,
        ],
      ),
    );
  }

  Future<void> _saveSpec(String domainId, UseCaseOrchestrationSpec next) async {
    try {
      next.validate();
      await widget.controller.updateUseCaseOrchestration(domainId, next);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error is FormatException ? error.message : '$error'),
        ),
      );
    }
  }

  void _triggerGenerateFromProject(
    FunctionalDomain domain,
    SpecForgeProject? project,
  ) {
    if (widget.controller.isSending) return;
    if (_chatFraction <= 0) {
      setState(() => _chatFraction = _defaultChatFraction);
    }
    final prompt = project == null
        ? 'Analyse les contrats et couches Domain du domaine « ${domain.name} » '
            'et propose la cartographie par Bounded Context, les Use Cases CQRS '
            'détaillés (10 sections + scénarios Given/When/Then) ainsi que les '
            'Sagas en Mermaid avec leur matrice des compensations.'
        : 'À partir des cas d’usage, exigences, règles de gestion, Event Storming '
            'du projet « ${project.name} » et des contrats du domaine « ${domain.name} », '
            'génère ou complète la cartographie par Bounded Context, la spécification '
            'détaillée des Use Cases CQRS (10 sections + scénarios Given/When/Then) '
            'et les Sagas orchestrées (Mermaid + matrice des compensations).';
    unawaited(
      widget.controller.sendUseCaseOrchestrationMessage(domain.id, prompt),
    );
  }

  void _openMarkdownPreview(
    BuildContext context,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec,
  ) {
    unawaited(
      showSpecMarkdownViewerDialog(
        context,
        markdown: spec.toMarkdown(domainName: domain.name),
        title: 'Cas d’usage & orchestration — ${domain.name}',
        filenameStem: 'usecase_orchestration_${domain.domainCode}',
        surfaceBuilder: widget.markdownViewerSurfaceBuilder,
        openInBrowser: widget.markdownBrowserLauncher,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final catalog = widget.controller.domainCatalog;
    final domains = catalog.domains;
    final selected = _resolveSelectedDomain();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesignDomainBreadcrumbBar(
          domains: domains,
          selectedDomain: selected,
          onDomainSelected: _selectDomain,
          segments: const [
            DesignBreadcrumbSegment(
              key: ValueKey('usecase-orchestration-crumb'),
              label: 'Cas d’usage & orchestration',
            ),
          ],
        ),
        Expanded(
          child: selected == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 12,
                      children: [
                        Text(
                          'Ajoutez un domaine pour commencer.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('usecase-manage-domains-btn'),
                          onPressed: widget.onManageDomains,
                          icon: const Icon(Icons.domain),
                          label: const Text('Gestion des domaines'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildDomainWorkspace(context, catalog, selected),
        ),
      ],
    );
  }

  Widget _buildDomainWorkspace(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final spec =
        domain.useCaseOrchestration ?? UseCaseOrchestrationSpec.empty;
    final project = widget.controller.project;
    final contracts = domain.contracts ?? DomainContracts.empty;
    final contractsCount = contracts.groups.fold<int>(
      0,
      (sum, group) => sum + group.children.length,
    );
    final servicesCount = catalog.microservices
        .where((service) => service.domainId == domain.id)
        .length;
    final hasAnyContent =
        spec.cartography.isNotEmpty ||
        spec.useCases.isNotEmpty ||
        spec.sagas.isNotEmpty;
    final activeTab =
        UseCaseOrchestrationTab.values[_tabController.index];

    return Column(
      key: const ValueKey('usecase-orchestration-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 22,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Cas d’usage & orchestration',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Chip(
                          key: const ValueKey('usecase-active-domain-chip'),
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.domain, size: 15),
                          label: Text('${domain.name} (${domain.domainCode})'),
                        ),
                        if (project != null)
                          Chip(
                            key: const ValueKey('usecase-source-project-chip'),
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.description_outlined,
                              size: 15,
                            ),
                            label: Text(
                              'Projet : ${project.name} '
                              '(${project.cahierDesCharges.useCases.length} UC Spec)',
                            ),
                          ),
                        if (!domain.isActive)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('Inactif'),
                            backgroundColor: colors.errorContainer,
                          ),
                      ],
                    ),
                    Text(
                      '${spec.cartography.length} contexte(s) · '
                      '${spec.useCases.length} Use Case(s) · '
                      '${spec.sagas.length} Saga(s) · '
                      '$contractsCount contrat(s) · $servicesCount microservice(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('usecase-generate-from-project-btn'),
                    onPressed: widget.controller.isSending
                        ? null
                        : () => _triggerGenerateFromProject(domain, project),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                    label: Text(
                      project != null
                          ? 'Compléter depuis le projet'
                          : 'Compléter avec l’IA',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('usecase-preview-markdown-btn'),
                    onPressed: hasAnyContent
                        ? () => _openMarkdownPreview(context, domain, spec)
                        : null,
                    icon: const Icon(Icons.preview_outlined, size: 17),
                    label: const Text('Aperçu Markdown / Mermaid'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              const minLeading = 250.0;
              const minTrailing = 440.0;
              final collapsed = _chatFraction <= 0;
              final available = math.max(
                0.0,
                bounds.maxWidth - SpecSplitHandle.width,
              );
              final roomy = available > minLeading + minTrailing;
              final minFrac = roomy ? minLeading / available : 0.2;
              final maxFrac = roomy
                  ? (available - minTrailing) / available
                  : 0.72;
              final leadingWidth = collapsed
                  ? 38.0
                  : available * _chatFraction.clamp(minFrac, maxFrac);

              return Row(
                key: _splitKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (collapsed)
                    Container(
                      key: const ValueKey('usecase-orchestration-chat-collapsed'),
                      width: 38,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        spacing: 8,
                        children: [
                          IconButton(
                            key: const ValueKey(
                              'usecase-orchestration-chat-expand',
                            ),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher le chat IA',
                            onPressed: () => setState(
                              () => _chatFraction = _defaultChatFraction,
                            ),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
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
                      key: const ValueKey('usecase-orchestration-chat-pane'),
                      width: leadingWidth,
                      child: UseCaseOrchestrationChatPane(
                        key: ValueKey('usecase-chat-${domain.id}'),
                        controller: widget.controller,
                        domain: domain,
                        activeTab: activeTab,
                        onCollapse: () => setState(() => _chatFraction = 0),
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                    ),
                  SpecSplitHandle(
                    key: const ValueKey('usecase-orchestration-split-handle'),
                    onDoubleTap: () =>
                        setState(() => _chatFraction = _defaultChatFraction),
                    onHorizontalDragDown: (drag) {
                      final box =
                          _splitKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      _dragOffset = box == null || collapsed
                          ? SpecSplitHandle.width / 2
                          : (box.globalToLocal(drag.globalPosition).dx -
                                    leadingWidth)
                                .clamp(0.0, SpecSplitHandle.width);
                    },
                    onHorizontalDragUpdate: (drag) {
                      final box =
                          _splitKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null || available <= 0) return;
                      final width =
                          box.globalToLocal(drag.globalPosition).dx -
                          _dragOffset;
                      if (collapsed) {
                        if (width > 60) {
                          setState(
                            () => _chatFraction = (width / available).clamp(
                              minFrac,
                              maxFrac,
                            ),
                          );
                        }
                      } else if (width < 140) {
                        setState(() => _chatFraction = 0);
                      } else {
                        setState(
                          () => _chatFraction = (width / available).clamp(
                            minFrac,
                            maxFrac,
                          ),
                        );
                      }
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ColoredBox(
                          color: colors.surfaceContainerLow,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            indicatorColor: colors.primary,
                            indicatorWeight: 3,
                            tabs: [
                              for (final tab in UseCaseOrchestrationTab.values)
                                Tab(
                                  key: ValueKey('usecase-tab-${tab.name}'),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: 6,
                                    children: [
                                      Text(tab.label),
                                      if (spec.countForTab(tab) > 0)
                                        _CountBadge(
                                          count: spec.countForTab(tab),
                                          colors: colors,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildCartographyTab(
                                context,
                                theme,
                                colors,
                                domain,
                                spec,
                              ),
                              _buildUseCasesTab(
                                context,
                                theme,
                                colors,
                                domain,
                                spec,
                              ),
                              _buildSagasTab(
                                context,
                                theme,
                                colors,
                                domain,
                                spec,
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildCartographyTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabToolbar(
          subtitle: UseCaseOrchestrationTab.cartography.subtitle,
          addButtonKey: const ValueKey('usecase-add-cartography-btn'),
          addLabel: 'Ajouter un Bounded Context',
          onAdd: () => _editCartographyItem(context, domain, spec),
        ),
        const Divider(height: 1),
        Expanded(
          child: spec.cartography.isEmpty
              ? _EmptyTabPlaceholder(
                  icon: Icons.hub_outlined,
                  title: 'Aucune cartographie définie pour « ${domain.name} »',
                  description:
                      'Utilisez le chat IA à gauche (ou « Compléter depuis le projet ») '
                      'pour cartographier les Use Cases et Sagas par Bounded Context, '
                      'ou ajoutez un contexte manuellement.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: spec.cartography.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = spec.cartography[index];
                    return Card(
                      key: ValueKey('usecase-carto-card-${item.id}'),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 10,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.workspaces_outline,
                                  size: 20,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.boundedContext,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Modifier',
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => _editCartographyItem(
                                    context,
                                    domain,
                                    spec,
                                    existing: item,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () => _saveSpec(
                                    domain.id,
                                    spec.copyWith(
                                      cartography: spec.cartography
                                          .where((c) => c.id != item.id)
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (item.description.isNotEmpty)
                              Text(
                                item.description,
                                style: theme.textTheme.bodyMedium,
                              ),
                            if (item.useCaseCodes.isNotEmpty)
                              _ChipGroup(
                                label: 'Use Cases :',
                                items: item.useCaseCodes,
                                color: colors.primaryContainer,
                                textColor: colors.onPrimaryContainer,
                              ),
                            if (item.sagaCodes.isNotEmpty)
                              _ChipGroup(
                                label: 'Sagas :',
                                items: item.sagaCodes,
                                color: colors.tertiaryContainer,
                                textColor: colors.onTertiaryContainer,
                              ),
                            if (item.notes.isNotEmpty)
                              Text(
                                item.notes,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUseCasesTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec,
  ) {
    final allCollapsed =
        spec.useCases.isNotEmpty &&
        spec.useCases.every((uc) => _collapsedUseCaseIds.contains(uc.id));
    final anyCollapsed =
        spec.useCases.any((uc) => _collapsedUseCaseIds.contains(uc.id)) ||
        _collapsedUseCaseSectionKeys.any(
          (k) => spec.useCases.any((uc) => k.startsWith('${uc.id}:')),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabToolbar(
          subtitle: UseCaseOrchestrationTab.useCases.subtitle,
          addButtonKey: const ValueKey('usecase-add-usecase-btn'),
          addLabel: 'Ajouter un Use Case',
          onAdd: () => _editUseCase(context, domain, spec),
          extraActions: spec.useCases.isEmpty
              ? const []
              : [
                  TextButton.icon(
                    key: const ValueKey('usecase-collapse-all-btn'),
                    onPressed: allCollapsed
                        ? null
                        : () => setState(() {
                            _collapsedUseCaseIds.addAll(
                              spec.useCases.map((u) => u.id),
                            );
                          }),
                    icon: const Icon(Icons.unfold_less_rounded, size: 17),
                    label: const Text('Tout replier'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('usecase-expand-all-btn'),
                    onPressed: anyCollapsed
                        ? () => setState(() {
                            for (final uc in spec.useCases) {
                              _collapsedUseCaseIds.remove(uc.id);
                              _collapsedUseCaseSectionKeys.removeWhere(
                                (k) => k.startsWith('${uc.id}:'),
                              );
                            }
                          })
                        : null,
                    icon: const Icon(Icons.unfold_more_rounded, size: 17),
                    label: const Text('Tout déplier'),
                  ),
                ],
        ),
        const Divider(height: 1),
        Expanded(
          child: spec.useCases.isEmpty
              ? _EmptyTabPlaceholder(
                  icon: Icons.rule_folder_outlined,
                  title: 'Aucun Use Case spécifié pour « ${domain.name} »',
                  description:
                      'Demandez à l’IA de générer les Use Cases CQRS détaillés '
                      '(10 sections, ports, événements et scénarios Given/When/Then) '
                      'ou créez-en un manuellement.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: spec.useCases.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final uc = spec.useCases[index];
                    return _UseCaseCard(
                      key: ValueKey('usecase-card-${uc.id}'),
                      useCase: uc,
                      theme: theme,
                      colors: colors,
                      isAiBusy: widget.controller.isSending,
                      expanded: !_collapsedUseCaseIds.contains(uc.id),
                      onToggleExpanded: () =>
                          _toggleSetKey(_collapsedUseCaseIds, uc.id),
                      isSectionExpanded: (sectionId) =>
                          !_collapsedUseCaseSectionKeys.contains(
                            '${uc.id}:$sectionId',
                          ),
                      onToggleSection: (sectionId) => _toggleSetKey(
                        _collapsedUseCaseSectionKeys,
                        '${uc.id}:$sectionId',
                      ),
                      onStageTap: (stage) =>
                          _cycleUseCaseStage(domain, spec, uc, stage),
                      onAskAiRefine: () {
                        if (_chatFraction <= 0) {
                          setState(() => _chatFraction = _defaultChatFraction);
                        }
                        unawaited(
                          widget.controller.sendUseCaseOrchestrationMessage(
                            domain.id,
                            'Approfondis et complète toutes les 10 sections et scénarios Given/When/Then du Use Case ${uc.code} (${uc.name}).',
                          ),
                        );
                      },
                      onEdit: () =>
                          _editUseCase(context, domain, spec, existing: uc),
                      onDelete: () => _saveSpec(
                        domain.id,
                        spec.copyWith(
                          useCases: spec.useCases
                              .where((item) => item.id != uc.id)
                              .toList(),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSagasTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec,
  ) {
    final allCollapsed =
        spec.sagas.isNotEmpty &&
        spec.sagas.every((s) => _collapsedSagaIds.contains(s.id));
    final anyCollapsed =
        spec.sagas.any((s) => _collapsedSagaIds.contains(s.id)) ||
        _collapsedSagaSectionKeys.any(
          (k) => spec.sagas.any((s) => k.startsWith('${s.id}:')),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabToolbar(
          subtitle: UseCaseOrchestrationTab.sagas.subtitle,
          addButtonKey: const ValueKey('usecase-add-saga-btn'),
          addLabel: 'Ajouter une Saga',
          onAdd: () => _editSaga(context, domain, spec),
          extraActions: spec.sagas.isEmpty
              ? const []
              : [
                  TextButton.icon(
                    key: const ValueKey('usecase-sagas-collapse-all-btn'),
                    onPressed: allCollapsed
                        ? null
                        : () => setState(() {
                            _collapsedSagaIds.addAll(
                              spec.sagas.map((s) => s.id),
                            );
                          }),
                    icon: const Icon(Icons.unfold_less_rounded, size: 17),
                    label: const Text('Tout replier'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('usecase-sagas-expand-all-btn'),
                    onPressed: anyCollapsed
                        ? () => setState(() {
                            for (final s in spec.sagas) {
                              _collapsedSagaIds.remove(s.id);
                              _collapsedSagaSectionKeys.removeWhere(
                                (k) => k.startsWith('${s.id}:'),
                              );
                            }
                          })
                        : null,
                    icon: const Icon(Icons.unfold_more_rounded, size: 17),
                    label: const Text('Tout déplier'),
                  ),
                ],
        ),
        const Divider(height: 1),
        Expanded(
          child: spec.sagas.isEmpty
              ? _EmptyTabPlaceholder(
                  icon: Icons.account_tree_outlined,
                  title: 'Aucune Saga modélisée pour « ${domain.name} »',
                  description:
                      'Les Sagas orchestrent les transactions distribuées multi-agrégats '
                      'ou inter-Bounded Contexts avec diagramme Mermaid et matrice de compensations.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: spec.sagas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final saga = spec.sagas[index];
                    return _SagaCard(
                      key: ValueKey('usecase-saga-card-${saga.id}'),
                      saga: saga,
                      theme: theme,
                      colors: colors,
                      isAiBusy: widget.controller.isSending,
                      expanded: !_collapsedSagaIds.contains(saga.id),
                      onToggleExpanded: () =>
                          _toggleSetKey(_collapsedSagaIds, saga.id),
                      isSectionExpanded: (sectionId) =>
                          !_collapsedSagaSectionKeys.contains(
                            '${saga.id}:$sectionId',
                          ),
                      onToggleSection: (sectionId) => _toggleSetKey(
                        _collapsedSagaSectionKeys,
                        '${saga.id}:$sectionId',
                      ),
                      onStageTap: (stage) =>
                          _cycleSagaStage(domain, spec, saga, stage),
                      onCopyMermaid: () {
                        unawaited(
                          Clipboard.setData(
                            ClipboardData(text: saga.mermaidDiagram),
                          ),
                        );
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(
                            content: Text('Diagramme Mermaid copié.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      onPreviewMermaid: () {
                        final diagram = saga.mermaidDiagram.trim();
                        final fenced = diagram.startsWith('```')
                            ? diagram
                            : '```mermaid\n$diagram\n```';
                        final md =
                            '# ${saga.code} · ${saga.name}'
                            '${saga.title.isNotEmpty && saga.title != saga.name ? ' — ${saga.title}' : ''}'
                            '\n\n$fenced';
                        unawaited(
                          showSpecMarkdownViewerDialog(
                            context,
                            markdown: md,
                            title: 'Aperçu Mermaid — ${saga.name}',
                            filenameStem: 'saga_${saga.code}_${saga.name}',
                            surfaceBuilder: widget.markdownViewerSurfaceBuilder,
                            openInBrowser: widget.markdownBrowserLauncher,
                            initialShowToc: false,
                            initialFullscreen: true,
                          ),
                        );
                      },
                      onAddCompensationRow: () =>
                          _editCompensationRow(context, domain, spec, saga),
                      onEditCompensationRow: (row) => _editCompensationRow(
                        context,
                        domain,
                        spec,
                        saga,
                        existing: row,
                      ),
                      onToggleCompensationRow: (updatedRow) {
                        final updatedSaga = saga.copyWith(
                          compensationMatrix: [
                            for (final r in saga.compensationMatrix)
                              if (r.id == updatedRow.id) updatedRow else r,
                          ],
                        );
                        unawaited(
                          _saveSpec(
                            domain.id,
                            spec.copyWith(
                              sagas: [
                                for (final s in spec.sagas)
                                  if (s.id == saga.id) updatedSaga else s,
                              ],
                            ),
                          ),
                        );
                      },
                      onDeleteCompensationRow: (row) {
                        final updatedSaga = saga.copyWith(
                          compensationMatrix: saga.compensationMatrix
                              .where((r) => r.id != row.id)
                              .toList(),
                        );
                        unawaited(
                          _saveSpec(
                            domain.id,
                            spec.copyWith(
                              sagas: [
                                for (final s in spec.sagas)
                                  if (s.id == saga.id) updatedSaga else s,
                              ],
                            ),
                          ),
                        );
                      },
                      onEdit: () =>
                          _editSaga(context, domain, spec, existing: saga),
                      onDelete: () => _saveSpec(
                        domain.id,
                        spec.copyWith(
                          sagas: spec.sagas
                              .where((item) => item.id != saga.id)
                              .toList(),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editCartographyItem(
    BuildContext context,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec, {
    BoundedContextUseCaseMap? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final ctxCtrl = TextEditingController(
      text: existing?.boundedContext ?? '',
    );
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final ucCtrl = TextEditingController(
      text: existing?.useCaseCodes.join(', ') ?? '',
    );
    final sagaCtrl = TextEditingController(
      text: existing?.sagaCodes.join(', ') ?? '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    final saved = await showDialog<BoundedContextUseCaseMap>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [ctxCtrl, descCtrl, ucCtrl, sagaCtrl, notesCtrl],
        child: AlertDialog(
          title: Text(
            existing == null
                ? 'Ajouter un Bounded Context'
                : 'Modifier ${existing.boundedContext}',
          ),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: ListView(
                shrinkWrap: true,
                children: [
                  TextFormField(
                    key: const ValueKey('usecase-carto-field-context'),
                    controller: ctxCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bounded Context *',
                      hintText: 'Catalogue Produits',
                    ),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? 'Nom du Bounded Context requis.'
                        : null,
                  ),
                  TextFormField(
                    key: const ValueKey('usecase-carto-field-description'),
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Responsabilité'),
                  ),
                  TextFormField(
                    key: const ValueKey('usecase-carto-field-usecases'),
                    controller: ucCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Use Cases associés (séparés par virgule ou ligne)',
                      hintText: 'UC-001, UC-002',
                    ),
                  ),
                  TextFormField(
                    key: const ValueKey('usecase-carto-field-sagas'),
                    controller: sagaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sagas associées (séparées par virgule ou ligne)',
                      hintText: 'SAGA-001',
                    ),
                  ),
                  TextFormField(
                    key: const ValueKey('usecase-carto-field-notes'),
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes d’architecture',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('usecase-carto-save-btn'),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  dialogContext,
                  BoundedContextUseCaseMap(
                    id: existing?.id ?? 'bcmap_${shortid.generate()}',
                    boundedContext: ctxCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    useCaseCodes: _splitCommasOrLines(ucCtrl.text),
                    sagaCodes: _splitCommasOrLines(sagaCtrl.text),
                    notes: notesCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (saved == null || !mounted) return;
    final nextList = existing == null
        ? [...spec.cartography, saved]
        : [
            for (final item in spec.cartography)
              if (item.id == saved.id) saved else item,
          ];
    await _saveSpec(domain.id, spec.copyWith(cartography: nextList));
  }

  Future<void> _editUseCase(
    BuildContext context,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec, {
    ApplicationUseCaseSpec? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(
      text:
          existing?.code ??
          'UC-${(spec.useCases.length + 1).toString().padLeft(3, '0')}',
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bcCtrl = TextEditingController(
      text: existing?.boundedContext ?? domain.name,
    );
    final aggCtrl = TextEditingController(text: existing?.targetAggregate ?? '');
    final goalCtrl = TextEditingController(text: existing?.businessGoal ?? '');
    final inputsCtrl = TextEditingController(
      text: _formatFieldLines(existing?.triggerInputs ?? const []),
    );
    final rulesCtrl = TextEditingController(
      text: (existing?.businessRules ?? const []).join('\n'),
    );
    final inboundCtrl = TextEditingController(text: existing?.inboundPort ?? '');
    final outboundCtrl = TextEditingController(
      text: (existing?.outboundPorts ?? const []).join('\n'),
    );
    final eventsCtrl = TextEditingController(
      text: (existing?.emittedEvents ?? const []).join('\n'),
    );
    final processCtrl = TextEditingController(
      text: (existing?.detailedProcess ?? const []).join('\n'),
    );
    final outputsCtrl = TextEditingController(
      text: _formatFieldLines(existing?.outputs ?? const []),
    );
    final errorsCtrl = TextEditingController(
      text: (existing?.possibleErrors ?? const []).join('\n'),
    );
    final acCtrl = TextEditingController(
      text: (existing?.acceptanceCriteria ?? const []).join('\n'),
    );
    final nonGoalsCtrl = TextEditingController(
      text: (existing?.nonGoals ?? const []).join('\n'),
    );
    final concurrencyCtrl = TextEditingController(
      text: existing?.concurrencyAndIdempotency ?? '',
    );
    final refsCtrl = TextEditingController(
      text: (existing?.linkedSpecRefs ?? const []).join(', '),
    );
    var cqrsType = existing?.cqrsType ?? UseCaseCqrsType.command;
    final states = Map<ContractStage, ContractStatus>.from(
      existing?.states ?? const {},
    );

    final saved = await showDialog<ApplicationUseCaseSpec>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [
          codeCtrl,
          nameCtrl,
          titleCtrl,
          bcCtrl,
          aggCtrl,
          goalCtrl,
          inputsCtrl,
          rulesCtrl,
          inboundCtrl,
          outboundCtrl,
          eventsCtrl,
          processCtrl,
          outputsCtrl,
          errorsCtrl,
          acCtrl,
          nonGoalsCtrl,
          concurrencyCtrl,
          refsCtrl,
        ],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Ajouter un Use Case'
                  : 'Modifier ${existing.code} · ${existing.name}',
            ),
            content: SizedBox(
              width: 600,
              child: Form(
                key: formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Row(
                      spacing: 10,
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextFormField(
                            key: const ValueKey('usecase-form-code'),
                            controller: codeCtrl,
                            decoration: const InputDecoration(labelText: 'Code'),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('usecase-form-name'),
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom technique *',
                              hintText: 'UpdateProductPrice',
                            ),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? 'Nom requis.'
                                : null,
                          ),
                        ),
                        SizedBox(
                          width: 155,
                          child: DropdownButtonFormField<UseCaseCqrsType>(
                            key: const ValueKey('usecase-form-cqrs'),
                            isExpanded: true,
                            initialValue: cqrsType,
                            decoration: const InputDecoration(
                              labelText: 'CQRS',
                            ),
                            items: [
                              for (final t in UseCaseCqrsType.values)
                                DropdownMenuItem(
                                  value: t,
                                  child: Text(t.label),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => cqrsType = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  TextFormField(
                    key: const ValueKey('usecase-form-title'),
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titre fonctionnel',
                    ),
                  ),
                  Row(
                    spacing: 10,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: bcCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Bounded Context',
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: aggCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Agrégat / Read Model cible',
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    key: const ValueKey('usecase-form-goal'),
                    controller: goalCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '1. Objectif métier',
                    ),
                  ),
                  TextFormField(
                    controller: inputsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '2. Déclencheur / Input (1 champ par ligne : nom: type)',
                      hintText: 'productId: string (UUID)',
                    ),
                  ),
                  TextFormField(
                    controller: rulesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '3. Règles métier (1 par ligne)',
                    ),
                  ),
                  Row(
                    spacing: 10,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: inboundCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Port entrant',
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: concurrencyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Concurrence / Idempotence',
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: outboundCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '4. Ports sortants utilisés (1 par ligne)',
                    ),
                  ),
                  TextFormField(
                    controller: eventsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Événements publiés (1 par ligne)',
                    ),
                  ),
                  TextFormField(
                    controller: processCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '5. Processus détaillé (1 étape par ligne)',
                    ),
                  ),
                  TextFormField(
                    controller: outputsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '6. Sortie / Output (1 champ par ligne : nom: type)',
                    ),
                  ),
                  TextFormField(
                    controller: errorsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '7. Erreurs possibles (1 par ligne)',
                    ),
                  ),
                  TextFormField(
                    controller: acCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '9. Critères d’acceptation (1 par ligne)',
                    ),
                  ),
                  TextFormField(
                    controller: nonGoalsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '10. Non-objectifs (1 par ligne)',
                    ),
                  ),
                  TextFormField(
                    controller: refsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Références Spec liées (EXF-xxx, RG-xxx)',
                    ),
                  ),
                  for (final stage in ContractStage.values)
                    DropdownButtonFormField<ContractStatus>(
                      initialValue: states[stage] ?? ContractStatus.pending,
                      decoration: InputDecoration(
                        labelText: contractStageLabels[stage],
                        icon: Icon(contractStageIcons[stage]),
                      ),
                      items: [
                        for (final status in ContractStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(contractStatusLabels[status]!),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => states[stage] = value);
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('usecase-form-save-btn'),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  dialogContext,
                  ApplicationUseCaseSpec(
                    id: existing?.id ?? 'uc_${shortid.generate()}',
                    code: codeCtrl.text.trim().isEmpty
                        ? 'UC-${(spec.useCases.length + 1).toString().padLeft(3, '0')}'
                        : codeCtrl.text.trim(),
                    name: nameCtrl.text.trim(),
                    title: titleCtrl.text.trim(),
                    boundedContext: bcCtrl.text.trim(),
                    cqrsType: cqrsType,
                    targetAggregate: aggCtrl.text.trim(),
                    businessGoal: goalCtrl.text.trim(),
                    triggerInputs: _parseFieldLines(inputsCtrl.text),
                    businessRules: _splitLines(rulesCtrl.text),
                    inboundPort: inboundCtrl.text.trim(),
                    outboundPorts: _splitLines(outboundCtrl.text),
                    emittedEvents: _splitLines(eventsCtrl.text),
                    detailedProcess: _splitLines(processCtrl.text),
                    outputs: _parseFieldLines(outputsCtrl.text),
                    possibleErrors: _splitLines(errorsCtrl.text),
                    scenarios: existing?.scenarios ?? const [],
                    acceptanceCriteria: _splitLines(acCtrl.text),
                    nonGoals: _splitLines(nonGoalsCtrl.text),
                    concurrencyAndIdempotency: concurrencyCtrl.text.trim(),
                    linkedSpecRefs: _splitCommasOrLines(refsCtrl.text),
                    states: states,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    ),
    );

    if (saved == null || !mounted) return;
    final nextList = existing == null
        ? [...spec.useCases, saved]
        : [
            for (final item in spec.useCases)
              if (item.id == saved.id) saved else item,
          ];
    await _saveSpec(domain.id, spec.copyWith(useCases: nextList));
  }

  Future<void> _editSaga(
    BuildContext context,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec, {
    OrchestrationSagaSpec? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(
      text:
          existing?.code ??
          'SAGA-${(spec.sagas.length + 1).toString().padLeft(3, '0')}',
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contextsCtrl = TextEditingController(
      text: existing?.boundedContexts.join(', ') ?? domain.name,
    );
    final triggerCtrl = TextEditingController(
      text: existing?.triggerEventOrCommand ?? '',
    );
    final correlationCtrl = TextEditingController(
      text: existing?.correlationKey ?? '',
    );
    final recoveryCtrl = TextEditingController(
      text: existing?.failureRecoveryStrategy ?? '',
    );
    final mermaidCtrl = TextEditingController(
      text: existing?.mermaidDiagram ?? '',
    );
    var mode =
        existing?.coordinationMode ?? SagaCoordinationMode.orchestration;
    final states = Map<ContractStage, ContractStatus>.from(
      existing?.states ?? const {},
    );

    final saved = await showDialog<OrchestrationSagaSpec>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [
          codeCtrl,
          nameCtrl,
          titleCtrl,
          contextsCtrl,
          triggerCtrl,
          correlationCtrl,
          recoveryCtrl,
          mermaidCtrl,
        ],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Ajouter une Saga'
                  : 'Modifier ${existing.code} · ${existing.name}',
            ),
            content: SizedBox(
              width: 580,
              child: Form(
                key: formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Row(
                      spacing: 10,
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextFormField(
                            controller: codeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Code',
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('usecase-saga-form-name'),
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom technique *',
                              hintText: 'OrderFulfillmentSaga',
                            ),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? 'Nom requis.'
                                : null,
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<SagaCoordinationMode>(
                            isExpanded: true,
                            initialValue: mode,
                            decoration: const InputDecoration(
                              labelText: 'Coordination',
                            ),
                            items: [
                              for (final m in SagaCoordinationMode.values)
                                DropdownMenuItem(
                                  value: m,
                                  child: Text(m.label),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => mode = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  TextFormField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titre fonctionnel',
                    ),
                  ),
                  TextFormField(
                    controller: contextsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bounded Contexts impliqués',
                    ),
                  ),
                  Row(
                    spacing: 10,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: triggerCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Déclencheur',
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: correlationCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Clé de corrélation',
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: recoveryCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Stratégie de reprise / DLQ',
                    ),
                  ),
                  TextFormField(
                    key: const ValueKey('usecase-saga-form-mermaid'),
                    controller: mermaidCtrl,
                    maxLines: 6,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Spécification Mermaid',
                      hintText: 'sequenceDiagram\n  ...',
                    ),
                  ),
                  for (final stage in ContractStage.values)
                    DropdownButtonFormField<ContractStatus>(
                      initialValue: states[stage] ?? ContractStatus.pending,
                      decoration: InputDecoration(
                        labelText: contractStageLabels[stage],
                        icon: Icon(contractStageIcons[stage]),
                      ),
                      items: [
                        for (final status in ContractStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(contractStatusLabels[status]!),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => states[stage] = value);
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('usecase-saga-form-save-btn'),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  dialogContext,
                  OrchestrationSagaSpec(
                    id: existing?.id ?? 'saga_${shortid.generate()}',
                    code: codeCtrl.text.trim().isEmpty
                        ? 'SAGA-${(spec.sagas.length + 1).toString().padLeft(3, '0')}'
                        : codeCtrl.text.trim(),
                    name: nameCtrl.text.trim(),
                    title: titleCtrl.text.trim(),
                    boundedContexts: _splitCommasOrLines(contextsCtrl.text),
                    coordinationMode: mode,
                    triggerEventOrCommand: triggerCtrl.text.trim(),
                    correlationKey: correlationCtrl.text.trim(),
                    failureRecoveryStrategy: recoveryCtrl.text.trim(),
                    mermaidDiagram: mermaidCtrl.text.trim(),
                    compensationMatrix:
                        existing?.compensationMatrix ?? const [],
                    states: states,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    ),
    );

    if (saved == null || !mounted) return;
    final nextList = existing == null
        ? [...spec.sagas, saved]
        : [
            for (final item in spec.sagas)
              if (item.id == saved.id) saved else item,
          ];
    await _saveSpec(domain.id, spec.copyWith(sagas: nextList));
  }

  Future<void> _editCompensationRow(
    BuildContext context,
    FunctionalDomain domain,
    UseCaseOrchestrationSpec spec,
    OrchestrationSagaSpec saga, {
    SagaCompensationRow? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final stepCtrl = TextEditingController(text: existing?.step ?? '');
    final nominalCtrl = TextEditingController(
      text: existing?.nominalAction ?? '',
    );
    final compCtrl = TextEditingController(
      text: existing?.compensationAction ?? '',
    );
    final triggerCtrl = TextEditingController(
      text: existing?.rollbackTrigger ?? '',
    );
    final timeoutCtrl = TextEditingController(text: existing?.timeout ?? '5s');
    var criticality = existing?.criticality ?? SagaStepCriticality.medium;
    var idempotent = existing?.idempotent ?? true;
    var retryable = existing?.retryable ?? true;

    final saved = await showDialog<SagaCompensationRow>(
      context: context,
      builder: (dialogContext) => _DialogDisposalScope(
        disposables: [
          stepCtrl,
          nominalCtrl,
          compCtrl,
          triggerCtrl,
          timeoutCtrl,
        ],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Ajouter une étape de compensation'
                  : 'Modifier l’étape « ${existing.step} »',
            ),
            content: SizedBox(
              width: 500,
              child: Form(
                key: formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    TextFormField(
                      key: const ValueKey('usecase-comp-field-step'),
                      controller: stepCtrl,
                      decoration: const InputDecoration(labelText: 'Étape *'),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Étape requise.'
                          : null,
                    ),
                    TextFormField(
                      controller: nominalCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Action Nominale',
                      ),
                    ),
                    TextFormField(
                      controller: compCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Action de Compensation (Rollback)',
                      ),
                    ),
                    TextFormField(
                      controller: triggerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Déclencheur du Rollback',
                      ),
                    ),
                    Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<SagaStepCriticality>(
                            isExpanded: true,
                            initialValue: criticality,
                            decoration: const InputDecoration(
                              labelText: 'Criticité',
                            ),
                            items: [
                              for (final c in SagaStepCriticality.values)
                                DropdownMenuItem(
                                  value: c,
                                  child: Text(c.label),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => criticality = v);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: timeoutCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Timeout',
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Idempotente'),
                      value: idempotent,
                      onChanged: (v) => setDialogState(() => idempotent = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Retryable'),
                      value: retryable,
                      onChanged: (v) => setDialogState(() => retryable = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const ValueKey('usecase-comp-save-btn'),
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    dialogContext,
                    SagaCompensationRow(
                      id: existing?.id ?? 'comp_${shortid.generate()}',
                      step: stepCtrl.text.trim(),
                      nominalAction: nominalCtrl.text.trim(),
                      compensationAction: compCtrl.text.trim(),
                      rollbackTrigger: triggerCtrl.text.trim(),
                      criticality: criticality,
                      idempotent: idempotent,
                      retryable: retryable,
                      timeout: timeoutCtrl.text.trim().isEmpty
                          ? '5s'
                          : timeoutCtrl.text.trim(),
                    ),
                  );
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == null || !mounted) return;
    final nextRows = existing == null
        ? [...saga.compensationMatrix, saved]
        : [
            for (final row in saga.compensationMatrix)
              if (row.id == saved.id) saved else row,
          ];
    final updatedSaga = saga.copyWith(compensationMatrix: nextRows);
    await _saveSpec(
      domain.id,
      spec.copyWith(
        sagas: [
          for (final s in spec.sagas)
            if (s.id == saga.id) updatedSaga else s,
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.colors});

  final int count;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _TabToolbar extends StatelessWidget {
  const _TabToolbar({
    required this.subtitle,
    required this.addButtonKey,
    required this.addLabel,
    required this.onAdd,
    this.extraActions = const <Widget>[],
  });

  final String subtitle;
  final Key addButtonKey;
  final String addLabel;
  final VoidCallback onAdd;
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth.clamp(160.0, 520.0),
              ),
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...extraActions,
                FilledButton.tonalIcon(
                  key: addButtonKey,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: Text(addLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTabPlaceholder extends StatelessWidget {
  const _EmptyTabPlaceholder({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: colors.outline),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.label,
    required this.items,
    required this.color,
    required this.textColor,
  });

  final String label;
  final List<String> items;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
      ],
    );
  }
}

class _UseCaseCard extends StatelessWidget {
  const _UseCaseCard({
    required this.useCase,
    required this.theme,
    required this.colors,
    required this.isAiBusy,
    required this.expanded,
    required this.onToggleExpanded,
    required this.isSectionExpanded,
    required this.onToggleSection,
    required this.onStageTap,
    required this.onAskAiRefine,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final ApplicationUseCaseSpec useCase;
  final ThemeData theme;
  final ColorScheme colors;
  final bool isAiBusy;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool Function(String sectionId) isSectionExpanded;
  final ValueChanged<String> onToggleSection;
  final ValueChanged<ContractStage> onStageTap;
  final VoidCallback onAskAiRefine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isQuery = useCase.cqrsType == UseCaseCqrsType.query;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    key: ValueKey('usecase-toggle-${useCase.id}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: onToggleExpanded,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedRotation(
                            turns: expanded ? 0.0 : -0.25,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: Icon(
                              Icons.expand_more_rounded,
                              size: 22,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _PillBadge(
                                  label: useCase.code,
                                  background: colors.secondaryContainer,
                                  foreground: colors.onSecondaryContainer,
                                ),
                                _PillBadge(
                                  label: useCase.cqrsType.label,
                                  background: isQuery
                                      ? Colors.teal.withValues(alpha: 0.16)
                                      : Colors.indigo.withValues(alpha: 0.16),
                                  foreground: isQuery
                                      ? Colors.teal.shade700
                                      : Colors.indigo.shade700,
                                ),
                                Text(
                                  useCase.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (useCase.title.isNotEmpty &&
                                    useCase.title != useCase.name)
                                  Text(
                                    '— ${useCase.title}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _PhaseStatusStrip(
                  keyPrefix: 'usecase-phase-${useCase.id}',
                  states: useCase.states,
                  onStageTap: onStageTap,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Approfondir avec l’IA',
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  onPressed: isAiBusy ? null : onAskAiRefine,
                ),
                IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topLeft,
              child: !expanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 10,
                        children: [
                          if (useCase.boundedContext.isNotEmpty ||
                              useCase.targetAggregate.isNotEmpty ||
                              useCase.linkedSpecRefs.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (useCase.boundedContext.isNotEmpty)
                                  Text(
                                    'Contexte : ${useCase.boundedContext}',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                if (useCase.targetAggregate.isNotEmpty)
                                  Text(
                                    'Agrégat : ${useCase.targetAggregate}',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                for (final ref in useCase.linkedSpecRefs)
                                  _PillBadge(
                                    label: ref,
                                    background: colors.surfaceContainerHighest,
                                    foreground: colors.onSurfaceVariant,
                                  ),
                              ],
                            ),
                          if (useCase.businessGoal.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-goal',
                              ),
                              title: '1. Objectif métier',
                              expanded: isSectionExpanded('goal'),
                              onToggle: () => onToggleSection('goal'),
                              child: Text(useCase.businessGoal),
                            ),
                          if (useCase.triggerInputs.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-inputs',
                              ),
                              title: '2. Déclencheur (Input)',
                              expanded: isSectionExpanded('inputs'),
                              onToggle: () => onToggleSection('inputs'),
                              child: UseCaseFieldsObjectTree(
                                key: ValueKey(
                                  'usecase-inputs-tree-${useCase.id}',
                                ),
                                treeId: 'usecase-inputs-${useCase.id}',
                                fields: useCase.triggerInputs,
                              ),
                            ),
                          if (useCase.businessRules.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-rules',
                              ),
                              title: '3. Règles métier',
                              expanded: isSectionExpanded('rules'),
                              onToggle: () => onToggleSection('rules'),
                              child: _BulletLines(useCase.businessRules),
                            ),
                          if (useCase.inboundPort.isNotEmpty ||
                              useCase.outboundPorts.isNotEmpty ||
                              useCase.emittedEvents.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-ports',
                              ),
                              title: '4. Ports utilisés & événements',
                              expanded: isSectionExpanded('ports'),
                              onToggle: () => onToggleSection('ports'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 4,
                                children: [
                                  if (useCase.inboundPort.isNotEmpty)
                                    Text(
                                      'Port entrant : ${useCase.inboundPort}',
                                    ),
                                  if (useCase.outboundPorts.isNotEmpty)
                                    _BulletLines([
                                      for (final p in useCase.outboundPorts)
                                        'Port sortant : $p',
                                    ]),
                                  if (useCase.emittedEvents.isNotEmpty)
                                    Text(
                                      'Événements publiés : ${useCase.emittedEvents.join(', ')}',
                                    ),
                                  if (useCase
                                      .concurrencyAndIdempotency
                                      .isNotEmpty)
                                    Text(
                                      'Concurrence / Idempotence : ${useCase.concurrencyAndIdempotency}',
                                    ),
                                ],
                              ),
                            ),
                          if (useCase.detailedProcess.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-process',
                              ),
                              title: '5. Processus détaillé',
                              expanded: isSectionExpanded('process'),
                              onToggle: () => onToggleSection('process'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 2,
                                children: [
                                  for (
                                    var i = 0;
                                    i < useCase.detailedProcess.length;
                                    i++
                                  )
                                    Text('${i + 1}. ${useCase.detailedProcess[i]}'),
                                ],
                              ),
                            ),
                          if (useCase.outputs.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-outputs',
                              ),
                              title: '6. Sortie (Output)',
                              expanded: isSectionExpanded('outputs'),
                              onToggle: () => onToggleSection('outputs'),
                              child: UseCaseFieldsObjectTree(
                                key: ValueKey(
                                  'usecase-outputs-tree-${useCase.id}',
                                ),
                                treeId: 'usecase-outputs-${useCase.id}',
                                fields: useCase.outputs,
                              ),
                            ),
                          if (useCase.possibleErrors.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-errors',
                              ),
                              title: '7. Erreurs possibles',
                              expanded: isSectionExpanded('errors'),
                              onToggle: () => onToggleSection('errors'),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final err in useCase.possibleErrors)
                                    _PillBadge(
                                      label: err,
                                      background: colors.errorContainer,
                                      foreground: colors.onErrorContainer,
                                    ),
                                ],
                              ),
                            ),
                          if (useCase.scenarios.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-scenarios',
                              ),
                              title:
                                  '8. Scénarios (Given / When / Then) (${useCase.scenarios.length})',
                              expanded: isSectionExpanded('scenarios'),
                              onToggle: () => onToggleSection('scenarios'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 8,
                                children: [
                                  for (final scn in useCase.scenarios)
                                    _ScenarioTile(
                                      scenario: scn,
                                      theme: theme,
                                      colors: colors,
                                      expanded: isSectionExpanded(
                                        'scn:${scn.id}',
                                      ),
                                      onToggle: () =>
                                          onToggleSection('scn:${scn.id}'),
                                    ),
                                ],
                              ),
                            ),
                          if (useCase.acceptanceCriteria.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-acceptance',
                              ),
                              title: '9. Critères d’acceptation',
                              expanded: isSectionExpanded('acceptance'),
                              onToggle: () => onToggleSection('acceptance'),
                              child: _BulletLines(useCase.acceptanceCriteria),
                            ),
                          if (useCase.nonGoals.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-section-${useCase.id}-nongoals',
                              ),
                              title: '10. Non-objectifs',
                              expanded: isSectionExpanded('nongoals'),
                              onToggle: () => onToggleSection('nongoals'),
                              child: _BulletLines(useCase.nonGoals),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({
    required this.scenario,
    required this.theme,
    required this.colors,
    required this.expanded,
    required this.onToggle,
  });

  final UseCaseScenarioSpec scenario;
  final ThemeData theme;
  final ColorScheme colors;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scenario.isNominal
              ? Colors.green.withValues(alpha: 0.35)
              : colors.error.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('usecase-scenario-toggle-${scenario.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.0 : -0.25,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      scenario.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PillBadge(
                    label: scenario.isNominal ? 'Nominal' : 'Erreur',
                    background: scenario.isNominal
                        ? Colors.green.withValues(alpha: 0.14)
                        : colors.errorContainer,
                    foreground: scenario.isNominal
                        ? Colors.green.shade700
                        : colors.onErrorContainer,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: !expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        for (var i = 0; i < scenario.given.length; i++)
                          Text(
                            '${i == 0 ? 'Given' : 'And'} ${scenario.given[i]}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        for (var i = 0; i < scenario.when.length; i++)
                          Text(
                            '${i == 0 ? 'When' : 'And'} ${scenario.when[i]}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        for (var i = 0; i < scenario.then.length; i++)
                          Text(
                            '${i == 0 ? 'Then' : 'And'} ${scenario.then[i]}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SagaCard extends StatelessWidget {
  const _SagaCard({
    required this.saga,
    required this.theme,
    required this.colors,
    required this.isAiBusy,
    required this.expanded,
    required this.onToggleExpanded,
    required this.isSectionExpanded,
    required this.onToggleSection,
    required this.onStageTap,
    required this.onCopyMermaid,
    required this.onPreviewMermaid,
    required this.onAddCompensationRow,
    required this.onEditCompensationRow,
    required this.onToggleCompensationRow,
    required this.onDeleteCompensationRow,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final OrchestrationSagaSpec saga;
  final ThemeData theme;
  final ColorScheme colors;
  final bool isAiBusy;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool Function(String sectionId) isSectionExpanded;
  final ValueChanged<String> onToggleSection;
  final ValueChanged<ContractStage> onStageTap;
  final VoidCallback onCopyMermaid;
  final VoidCallback onPreviewMermaid;
  final VoidCallback onAddCompensationRow;
  final ValueChanged<SagaCompensationRow> onEditCompensationRow;
  final ValueChanged<SagaCompensationRow> onToggleCompensationRow;
  final ValueChanged<SagaCompensationRow> onDeleteCompensationRow;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hasMeta =
        saga.boundedContexts.isNotEmpty ||
        saga.triggerEventOrCommand.isNotEmpty ||
        saga.correlationKey.isNotEmpty ||
        saga.failureRecoveryStrategy.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    key: ValueKey('usecase-saga-toggle-${saga.id}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: onToggleExpanded,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedRotation(
                            turns: expanded ? 0.0 : -0.25,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: Icon(
                              Icons.expand_more_rounded,
                              size: 22,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _PillBadge(
                                  label: saga.code,
                                  background: colors.tertiaryContainer,
                                  foreground: colors.onTertiaryContainer,
                                ),
                                _PillBadge(
                                  label: saga.coordinationMode.label,
                                  background: colors.secondaryContainer,
                                  foreground: colors.onSecondaryContainer,
                                ),
                                Text(
                                  saga.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (saga.title.isNotEmpty &&
                                    saga.title != saga.name)
                                  Text(
                                    '— ${saga.title}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _PhaseStatusStrip(
                  keyPrefix: 'usecase-saga-phase-${saga.id}',
                  states: saga.states,
                  onStageTap: onStageTap,
                ),
                const SizedBox(width: 4),
                if (saga.mermaidDiagram.isNotEmpty) ...[
                  IconButton(
                    key: ValueKey('usecase-saga-header-copy-${saga.id}'),
                    tooltip: 'Copier Mermaid',
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    onPressed: onCopyMermaid,
                  ),
                  IconButton(
                    key: ValueKey('usecase-saga-header-preview-${saga.id}'),
                    tooltip: 'Aperçu Mermaid',
                    icon: const Icon(Icons.preview_outlined, size: 18),
                    onPressed: onPreviewMermaid,
                  ),
                ],
                IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topLeft,
              child: !expanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          if (hasMeta)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-saga-section-${saga.id}-meta',
                              ),
                              title: 'Contexte & stratégie de reprise',
                              expanded: isSectionExpanded('meta'),
                              onToggle: () => onToggleSection('meta'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 6,
                                children: [
                                  if (saga.boundedContexts.isNotEmpty ||
                                      saga.triggerEventOrCommand.isNotEmpty ||
                                      saga.correlationKey.isNotEmpty)
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        if (saga.boundedContexts.isNotEmpty)
                                          Text(
                                            'Contextes : ${saga.boundedContexts.join(', ')}',
                                            style: theme.textTheme.labelMedium,
                                          ),
                                        if (saga
                                            .triggerEventOrCommand
                                            .isNotEmpty)
                                          Text(
                                            'Déclencheur : ${saga.triggerEventOrCommand}',
                                            style: theme.textTheme.labelMedium,
                                          ),
                                        if (saga.correlationKey.isNotEmpty)
                                          Text(
                                            'Clé de corrélation : ${saga.correlationKey}',
                                            style: theme.textTheme.labelMedium,
                                          ),
                                      ],
                                    ),
                                  if (saga.failureRecoveryStrategy.isNotEmpty)
                                    Text(
                                      'Stratégie de reprise : ${saga.failureRecoveryStrategy}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (saga.mermaidDiagram.isNotEmpty)
                            _CollapsibleSection(
                              toggleKey: ValueKey(
                                'usecase-saga-section-${saga.id}-mermaid',
                              ),
                              title: 'Spécification de la Saga (Mermaid)',
                              expanded: isSectionExpanded('mermaid'),
                              onToggle: () => onToggleSection('mermaid'),
                              trailing: Wrap(
                                spacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  TextButton.icon(
                                    key: ValueKey(
                                      'usecase-saga-mermaid-copy-${saga.id}',
                                    ),
                                    onPressed: onCopyMermaid,
                                    icon: const Icon(
                                      Icons.copy_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Copier'),
                                  ),
                                  FilledButton.tonalIcon(
                                    key: ValueKey(
                                      'usecase-saga-mermaid-preview-${saga.id}',
                                    ),
                                    onPressed: onPreviewMermaid,
                                    icon: const Icon(
                                      Icons.preview_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Aperçu Mermaid'),
                                  ),
                                ],
                              ),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: SelectableText(
                                  saga.mermaidDiagram,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          _CollapsibleSection(
                            toggleKey: ValueKey(
                              'usecase-saga-section-${saga.id}-matrix',
                            ),
                            title:
                                'Matrice des Compensations de la Saga (${saga.compensationMatrix.length})',
                            expanded: isSectionExpanded('matrix'),
                            onToggle: () => onToggleSection('matrix'),
                            trailing: TextButton.icon(
                              onPressed: onAddCompensationRow,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Ajouter une étape'),
                            ),
                            child: saga.compensationMatrix.isEmpty
                                ? Text(
                                    'Aucune étape de compensation définie.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  )
                                : SagaCompensationSuperTable(
                                    sagaId: saga.id,
                                    rows: saga.compensationMatrix,
                                    onEditRow: onEditCompensationRow,
                                    onDeleteRow: onDeleteCompensationRow,
                                    onToggleIdempotent: (row) =>
                                        onToggleCompensationRow(
                                          row.copyWith(
                                            idempotent: !row.idempotent,
                                          ),
                                        ),
                                    onToggleRetryable: (row) =>
                                        onToggleCompensationRow(
                                          row.copyWith(
                                            retryable: !row.retryable,
                                          ),
                                        ),
                                  ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseStatusStrip extends StatelessWidget {
  const _PhaseStatusStrip({
    required this.keyPrefix,
    required this.states,
    required this.onStageTap,
  });

  final String keyPrefix;
  final Map<ContractStage, ContractStatus> states;
  final ValueChanged<ContractStage> onStageTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        for (final stage in ContractStage.values)
          Tooltip(
            message:
                '${contractStageLabels[stage]} : '
                '${contractStatusLabels[states[stage] ?? ContractStatus.pending]}'
                ' (cliquer pour changer)',
            child: InkWell(
              key: ValueKey('$keyPrefix-${stage.name}'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => onStageTap(stage),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  contractStageIcons[stage],
                  size: 16,
                  color: contractStatusColor(states[stage], colors),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.toggleKey,
    this.trailing,
  });

  final Key? toggleKey;
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                key: toggleKey,
                borderRadius: BorderRadius.circular(6),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        turns: expanded ? 0.0 : -0.25,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 22, top: 4),
                  child: child,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _BulletLines extends StatelessWidget {
  const _BulletLines(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [for (final line in lines) Text('• $line')],
    );
  }
}

class _DialogDisposalScope extends StatefulWidget {
  const _DialogDisposalScope({required this.disposables, required this.child});

  final List<ChangeNotifier> disposables;
  final Widget child;

  @override
  State<_DialogDisposalScope> createState() => _DialogDisposalScopeState();
}

class _DialogDisposalScopeState extends State<_DialogDisposalScope> {
  @override
  void dispose() {
    for (final item in widget.disposables) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
