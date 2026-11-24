/// Vue principale de l'onglet Build du `NavigationRail` ([BuildDesignItemsView]),
/// présentant par domaine fonctionnel la liste des items de design porteurs des
/// 4 indicateurs d'avancement (Modèles & Contrats, Cas d'usage et Sagas).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../models/build_design_item.dart';
import '../../models/domain_catalog.dart';
import '../../models/domain_contracts.dart';
import '../../services/exporters/build_hexa_prompt_generator.dart';
import '../../services/spec_forge_controller.dart';
import '../design/contract_entry_view.dart'
    show
        ContractPhaseStatusStrip,
        contractStageIcons,
        contractStageLabels,
        contractStatusLabels,
        contractTypeColor;
import '../design/design_domain_breadcrumb.dart';
import '../workspace/markdown_viewer_dialog.dart';
import 'build_prompts_selection_view.dart';
import 'build_tech_stacks_dialog.dart';

/// Contrôleur permettant au shell parent d'observer le niveau courant de
/// [BuildDesignItemsView] (`0` = items de design, `1` = sélection des prompts IA)
/// et de déclencher le retour arrière depuis l'`AppBar`.
class BuildNavigationController extends ChangeNotifier {
  int _level = 0;
  VoidCallback? _backCallback;
  Object? _owner;

  /// Niveau courant du fil d'Ariane (`0` = liste des items, `1` = prompts IA).
  int get level => _level;

  void _attach(Object owner, int level, VoidCallback backCallback) {
    _owner = owner;
    _level = level;
    _backCallback = backCallback;
  }

  void _detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _backCallback = null;
    _level = 0;
  }

  void _updateLevel(int level) {
    if (_level == level) return;
    _level = level;
    notifyListeners();
  }

  /// Réinitialise le niveau mémorisé sans notifier (appelé lors du changement d'onglet).
  void reset() {
    _level = 0;
  }

  /// Remonte d'un niveau dans [BuildDesignItemsView].
  void goBack() {
    _backCallback?.call();
  }
}

/// Vue de suivi Build affichant, pour le domaine sélectionné dans le fil
/// d'Ariane, la sélection multiple des cartes des modèles/contrats, cas d'usage
/// et sagas ainsi que leurs 4 indicateurs d'avancement ([ContractStage]), puis
/// la page « Sélection des Prompts IA » en Architecture Hexagonale.
class BuildDesignItemsView extends StatefulWidget {
  /// Crée la vue Build connectée au [controller].
  const BuildDesignItemsView({
    required this.controller,
    this.onManageDomains,
    this.onItemTap,
    this.initialDomainId,
    this.navigationController,
    this.editableIndicators = true,
    this.showFilters = true,
    this.onCopiedPrompt,
    this.markdownViewerSurfaceBuilder,
    this.markdownBrowserLauncher,
    super.key,
  });

  /// Contrôleur principal exposant le catalogue des domaines et la persistance.
  final SpecForgeController controller;

  /// Ouvre la gestion des domaines lorsqu'aucun domaine n'existe encore.
  final VoidCallback? onManageDomains;

  /// Callback optionnelle notifiée lors du clic sur la carte d'un item Build
  /// (en complément du basculement de sa sélection multiple).
  final ValueChanged<BuildDesignItem>? onItemTap;

  /// Identifiant optionnel du domaine sélectionné à l'ouverture.
  final String? initialDomainId;

  /// Contrôleur optionnel exposant le niveau courant à l'`AppBar` du shell.
  final BuildNavigationController? navigationController;

  /// Autorise la modification directe des 4 indicateurs d'avancement au clic.
  final bool editableIndicators;

  /// Affiche la barre de recherche et de filtrage rapide en haut du domaine.
  final bool showFilters;

  /// Callback optionnelle notifiée avec le Markdown copié dans la page Prompts IA (tests).
  final ValueChanged<String>? onCopiedPrompt;

  /// Substitut optionnel de la WebView pour l'aperçu Markdown des prompts (tests).
  final SpecMarkdownViewerSurfaceBuilder? markdownViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour l'aperçu Markdown des prompts (tests).
  final SpecMarkdownBrowserLauncher? markdownBrowserLauncher;

  @override
  State<BuildDesignItemsView> createState() => _BuildDesignItemsViewState();
}

class _BuildDesignItemsViewState extends State<BuildDesignItemsView> {
  final TextEditingController _searchController = TextEditingController();
  final PageController _pages = PageController();
  final Set<BuildDesignItemKind> _collapsedKinds = <BuildDesignItemKind>{};
  final Map<String, Set<String>> _selectedKeysByDomain =
      <String, Set<String>>{};
  String? _selectedDomainId;
  int _level = 0;
  BuildDesignItemKind? _kindFilter;
  ContractStage? _stageFilter;
  ContractStatus? _statusFilter;

  static String _selectionKey(BuildDesignItem item) =>
      '${item.kind.name}:${item.id}';

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      _kindFilter != null ||
      _stageFilter != null ||
      _statusFilter != null;

  @override
  void initState() {
    super.initState();
    _selectedDomainId =
        widget.initialDomainId ?? widget.controller.activeDesignDomainId;
    _searchController.addListener(_onSearchChanged);
    widget.navigationController?._attach(this, _level, _handleBackFromShell);
  }

  @override
  void didUpdateWidget(BuildDesignItemsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationController != widget.navigationController) {
      oldWidget.navigationController?._detach(this);
      widget.navigationController?._attach(this, _level, _handleBackFromShell);
    }
    if (widget.initialDomainId != null &&
        widget.initialDomainId != oldWidget.initialDomainId) {
      _selectedDomainId = widget.initialDomainId;
      _level = 0;
      widget.navigationController?._updateLevel(0);
      if (_pages.hasClients) {
        _pages.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    widget.navigationController?._detach(this);
    _pages.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleBackFromShell() {
    if (_level > 0) {
      _goToLevel(_level - 1);
    }
  }

  void _goToLevel(int level) {
    final clamped = level.clamp(0, 1);
    if (_level == clamped) return;
    setState(() => _level = clamped);
    widget.navigationController?._updateLevel(clamped);
    if (_pages.hasClients) {
      unawaited(
        _pages.animateToPage(
          clamped,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  FunctionalDomain? _resolveSelectedDomain(List<FunctionalDomain> domains) {
    final effectiveId =
        _selectedDomainId ?? widget.controller.activeDesignDomainId;
    return domains.where((domain) => domain.id == effectiveId).firstOrNull ??
        domains.firstOrNull;
  }

  void _selectDomain(FunctionalDomain domain, FunctionalDomain? current) {
    final changed = domain.id != current?.id;
    if (!changed && widget.controller.activeDesignDomainId == domain.id) {
      return;
    }
    if (changed && _pages.hasClients) {
      _pages.jumpToPage(0);
    }
    setState(() {
      if (changed) _level = 0;
      _selectedDomainId = domain.id;
    });
    widget.controller.setActiveDesignDomainId(domain.id);
    if (changed) {
      widget.navigationController?._updateLevel(0);
    }
  }

  bool _isItemSelected(String domainId, BuildDesignItem item) =>
      _selectedKeysByDomain[domainId]?.contains(_selectionKey(item)) ?? false;

  List<BuildDesignItem> _selectedItemsOf(BuildDomainDesignItems projection) {
    final selectedKeys = _selectedKeysByDomain[projection.domainId];
    if (selectedKeys == null || selectedKeys.isEmpty) {
      return const <BuildDesignItem>[];
    }
    return <BuildDesignItem>[
      for (final item in projection.allItems)
        if (selectedKeys.contains(_selectionKey(item))) item,
    ];
  }

  void _toggleItemSelection(String domainId, BuildDesignItem item) {
    setState(() {
      final set = _selectedKeysByDomain.putIfAbsent(
        domainId,
        () => <String>{},
      );
      final key = _selectionKey(item);
      if (!set.remove(key)) {
        set.add(key);
      }
    });
    widget.onItemTap?.call(item);
  }

  void _toggleItemsBatch(
    String domainId,
    Iterable<BuildDesignItem> items, {
    required bool select,
  }) {
    setState(() {
      final set = _selectedKeysByDomain.putIfAbsent(
        domainId,
        () => <String>{},
      );
      for (final item in items) {
        final key = _selectionKey(item);
        if (select) {
          set.add(key);
        } else {
          set.remove(key);
        }
      }
    });
  }

  void _clearDomainSelection(String domainId) {
    setState(() {
      _selectedKeysByDomain[domainId]?.clear();
    });
  }

  void _toggleSection(BuildDesignItemKind kind) {
    setState(() {
      if (!_collapsedKinds.remove(kind)) {
        _collapsedKinds.add(kind);
      }
    });
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _kindFilter = null;
      _stageFilter = null;
      _statusFilter = null;
    });
  }

  Future<void> _cycleItemStage(
    FunctionalDomain domain,
    BuildDesignItem item,
    ContractStage stage,
  ) async {
    try {
      switch (item.kind) {
        case BuildDesignItemKind.model:
          final contracts = domain.contracts;
          final node = contracts?.entryById(item.id);
          if (contracts == null || node == null) return;
          final prevDetail =
              contracts.details[node.id] ?? ContractDetails.defaults;
          final nextStates = Map<ContractStage, ContractStatus>.from(
            prevDetail.states,
          )..[stage] = nextContractStatus(prevDetail.states[stage]);
          final updated = contracts.edit(
            node,
            node.type,
            prevDetail.copyWith(states: nextStates),
          );
          await widget.controller.updateDomainContracts(domain.id, updated);
        case BuildDesignItemKind.useCase:
          final spec = domain.useCaseOrchestration;
          if (spec == null) return;
          var found = false;
          final nextUseCases = [
            for (final uc in spec.useCases)
              if (uc.id == item.id)
                () {
                  found = true;
                  final nextStates = Map<ContractStage, ContractStatus>.from(
                    uc.states,
                  )..[stage] = nextContractStatus(uc.states[stage]);
                  return uc.copyWith(states: nextStates);
                }()
              else
                uc,
          ];
          if (!found) return;
          await widget.controller.updateUseCaseOrchestration(
            domain.id,
            spec.copyWith(useCases: nextUseCases),
          );
        case BuildDesignItemKind.saga:
          final spec = domain.useCaseOrchestration;
          if (spec == null) return;
          var found = false;
          final nextSagas = [
            for (final saga in spec.sagas)
              if (saga.id == item.id)
                () {
                  found = true;
                  final nextStates = Map<ContractStage, ContractStatus>.from(
                    saga.states,
                  )..[stage] = nextContractStatus(saga.states[stage]);
                  return saga.copyWith(states: nextStates);
                }()
              else
                saga,
          ];
          if (!found) return;
          await widget.controller.updateUseCaseOrchestration(
            domain.id,
            spec.copyWith(sagas: nextSagas),
          );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error is FormatException ? error.message : '$error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final domains = widget.controller.domainCatalog.domains;
    final selected = _resolveSelectedDomain(domains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesignDomainBreadcrumbBar(
          domainCrumbKey: const ValueKey('build-domain-crumb'),
          domains: domains,
          selectedDomain: selected,
          onDomainSelected: (domain) => _selectDomain(domain, selected),
          segments: [
            DesignBreadcrumbSegment(
              key: const ValueKey('build-items-crumb'),
              label: 'Items de design & avancement',
              isParent: true,
              onTap: _level > 0 ? () => _goToLevel(0) : null,
            ),
            if (_level >= 1)
              const DesignBreadcrumbSegment(
                key: ValueKey('build-prompts-crumb'),
                label: 'Sélection des Prompts IA',
              ),
          ],
        ),
        Expanded(
          child: selected == null
              ? _buildNoDomainState(context)
              : _buildDomainPages(context, selected),
        ),
      ],
    );
  }

  Future<void> _updateDomainTechStack(
    FunctionalDomain domain,
    String? stackId,
  ) async {
    final catalog = widget.controller.domainCatalog;
    final normalized = (stackId == null || stackId.trim().isEmpty)
        ? null
        : stackId.trim();
    if (domain.techStackId == normalized) return;
    try {
      await widget.controller.updateDomainCatalog(
        catalog.copyWith(
          domains: <FunctionalDomain>[
            for (final item in catalog.domains)
              if (item.id == domain.id)
                normalized == null
                    ? item.copyWith(clearTechStackId: true)
                    : item.copyWith(techStackId: normalized)
              else
                item,
          ],
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error is FormatException ? error.message : '$error'),
        ),
      );
    }
  }

  Future<void> _openTechStacksDialog(
    BuildContext context,
    FunctionalDomain domain,
  ) => showBuildTechStacksDialog(
    context,
    controller: widget.controller,
    initialStackId: domain.techStackId,
  );

  Widget _buildDomainPages(BuildContext context, FunctionalDomain domain) {
    final catalog = widget.controller.domainCatalog;
    final projection = BuildDomainDesignItems.fromDomain(domain);
    final selectedItems = _selectedItemsOf(projection);
    final promptGroups = _level >= 1
        ? BuildHexaPromptGenerator.generateGroups(
            domain: domain,
            selectedItems: selectedItems,
            catalog: catalog,
            glossary: widget.controller.companyGlossary,
            modelPreferences: widget.controller.modelPreferences,
          )
        : const <BuildItemPromptGroup>[];

    return PageView(
      controller: _pages,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _KeepAlive(
          child: _buildDomainBody(context, domain, projection, selectedItems),
        ),
        BuildPromptsSelectionView(
          key: ValueKey('build-prompts-view-${domain.id}'),
          domain: domain,
          groups: promptGroups,
          techStacks: catalog.techStacks,
          selectedTechStackId: domain.techStackId,
          onTechStackChanged: (stackId) =>
              unawaited(_updateDomainTechStack(domain, stackId)),
          onManageTechStacks: () =>
              unawaited(_openTechStacksDialog(context, domain)),
          onBackToItems: () => _goToLevel(0),
          onStageTap: widget.editableIndicators
              ? (item, stage) => unawaited(_cycleItemStage(domain, item, stage))
              : null,
          onCopiedPrompt: widget.onCopiedPrompt,
          markdownViewerSurfaceBuilder: widget.markdownViewerSurfaceBuilder,
          markdownBrowserLauncher: widget.markdownBrowserLauncher,
        ),
      ],
    );
  }

  Widget _buildNoDomainState(BuildContext context) {
    return Center(
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
            if (widget.onManageDomains != null)
              FilledButton.tonalIcon(
                key: const ValueKey('build-manage-domains-btn'),
                onPressed: widget.onManageDomains,
                icon: const Icon(Icons.domain),
                label: const Text('Gestion des domaines'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainBody(
    BuildContext context,
    FunctionalDomain domain,
    BuildDomainDesignItems projection,
    List<BuildDesignItem> selectedItems,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final query = _searchController.text;

    final filteredByKind = <BuildDesignItemKind, List<BuildDesignItem>>{
      for (final kind in BuildDesignItemKind.values)
        kind: projection.filterItems(
          kind,
          query: query,
          kindFilter: _kindFilter,
          stageFilter: _stageFilter,
          statusFilter: _statusFilter,
        ),
    };
    final visibleFilteredItems = <BuildDesignItem>[
      for (final kind in BuildDesignItemKind.values)
        if (_kindFilter == null || _kindFilter == kind) ...filteredByKind[kind]!,
    ];
    final totalFiltered = filteredByKind.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    final visibleKinds = <BuildDesignItemKind>[
      for (final kind in BuildDesignItemKind.values)
        if (_kindFilter == null || _kindFilter == kind)
          if (!_hasActiveFilters || filteredByKind[kind]!.isNotEmpty) kind,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!projection.isEmpty)
          _buildTopToolbar(
            theme: theme,
            colors: colors,
            domain: domain,
            projection: projection,
            visibleFilteredItems: visibleFilteredItems,
            selectedItems: selectedItems,
          ),
        Expanded(
          child: projection.isEmpty
              ? _buildEmptyDomainItemsState(theme, colors, domain)
              : (_hasActiveFilters && totalFiltered == 0)
              ? _buildFilteredEmptyState(theme, colors)
              : Align(
                  alignment: Alignment.topLeft,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < visibleKinds.length; i++) ...[
                          if (i > 0) const SizedBox(height: 28),
                          _buildSection(
                            context,
                            theme: theme,
                            colors: colors,
                            domain: domain,
                            kind: visibleKinds[i],
                            items: filteredByKind[visibleKinds[i]]!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTopToolbar({
    required ThemeData theme,
    required ColorScheme colors,
    required FunctionalDomain domain,
    required BuildDomainDesignItems projection,
    required List<BuildDesignItem> visibleFilteredItems,
    required List<BuildDesignItem> selectedItems,
  }) {
    final allVisibleSelected =
        visibleFilteredItems.isNotEmpty &&
        visibleFilteredItems.every(
          (item) => _isItemSelected(domain.id, item),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.showFilters) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 200,
                      maxWidth: 250,
                    ),
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        key: const ValueKey('build-search-field'),
                        controller: _searchController,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un item…',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 17,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  key: const ValueKey('build-search-clear-btn'),
                                  tooltip: 'Effacer la recherche',
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  onPressed: _searchController.clear,
                                ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ChoiceChip(
                    key: const ValueKey('build-filter-kind-all'),
                    label: Text('Tous (${projection.totalCount})'),
                    selected: _kindFilter == null,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _kindFilter = null),
                  ),
                  for (final kind in BuildDesignItemKind.values)
                    ChoiceChip(
                      key: ValueKey('build-filter-kind-${kind.name}'),
                      avatar: Icon(_iconForKind(kind), size: 15),
                      label: Text(
                        '${kind.shortLabel}s (${projection.itemsOf(kind).length})',
                      ),
                      selected: _kindFilter == kind,
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) =>
                          setState(() => _kindFilter = selected ? kind : null),
                    ),
                  _StageFilterDropdown(
                    selectedStage: _stageFilter,
                    onChanged: (value) => setState(() => _stageFilter = value),
                  ),
                  _StatusFilterDropdown(
                    selectedStatus: _statusFilter,
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                  if (_hasActiveFilters)
                    TextButton.icon(
                      key: const ValueKey('build-filter-reset-btn'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                      label: const Text('Réinitialiser'),
                    ),
                ],
                DomainTechStackSelector(
                  dropdownKey: const ValueKey('build-domain-stack-selector'),
                  manageButtonKey: const ValueKey('build-manage-stacks-btn'),
                  techStacks: widget.controller.domainCatalog.techStacks,
                  selectedStackId: domain.techStackId,
                  onChanged: (stackId) =>
                      unawaited(_updateDomainTechStack(domain, stackId)),
                  onManageStacks: () =>
                      unawaited(_openTechStacksDialog(context, domain)),
                ),
                TextButton.icon(
                  key: const ValueKey('build-select-all-btn'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: visibleFilteredItems.isEmpty
                      ? null
                      : () => _toggleItemsBatch(
                          domain.id,
                          visibleFilteredItems,
                          select: !allVisibleSelected,
                        ),
                  icon: Icon(
                    allVisibleSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    size: 16,
                  ),
                  label: Text(
                    allVisibleSelected
                        ? 'Désélectionner visibles'
                        : 'Tout sélectionner',
                  ),
                ),
                if (selectedItems.isNotEmpty)
                  TextButton(
                    key: const ValueKey('build-clear-selection-btn'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _clearDomainSelection(domain.id),
                    child: const Text('Effacer la sélection'),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: const ValueKey('build-next-prompts-btn'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: selectedItems.isEmpty ? null : () => _goToLevel(1),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 17),
            label: Text(
              selectedItems.isEmpty
                  ? 'Sélection des Prompts IA'
                  : 'Sélection des Prompts IA (${selectedItems.length})',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDomainItemsState(
    ThemeData theme,
    ColorScheme colors,
    FunctionalDomain domain,
  ) {
    return Center(
      key: const ValueKey('build-domain-empty-state'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 36,
              color: colors.onSurfaceVariant,
            ),
            Text(
              'Aucun élément de design dans le domaine « ${domain.name} ».',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Définissez vos modèles & contrats, cas d’usage ou sagas dans l’espace Design pour suivre leur avancement ici.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredEmptyState(ThemeData theme, ColorScheme colors) {
    return Center(
      key: const ValueKey('build-filtered-empty-state'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 32,
              color: colors.onSurfaceVariant,
            ),
            Text(
              'Aucun élément ne correspond aux filtres actifs.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            FilledButton.tonalIcon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Réinitialiser les filtres'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme colors,
    required FunctionalDomain domain,
    required BuildDesignItemKind kind,
    required List<BuildDesignItem> items,
  }) {
    final isCollapsed = _collapsedKinds.contains(kind);
    final selectedInSection = items
        .where((item) => _isItemSelected(domain.id, item))
        .length;
    final allSectionSelected =
        items.isNotEmpty && selectedInSection == items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              key: ValueKey('build-section-header-${kind.name}'),
              onTap: () => _toggleSection(kind),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconForKind(kind), size: 20, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      '${kind.sectionTitle} (${items.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedRotation(
                      turns: isCollapsed ? -0.25 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: Icon(
                        Icons.arrow_circle_down_outlined,
                        size: 22,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (items.isNotEmpty)
              TextButton(
                key: ValueKey('build-section-select-all-${kind.name}'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _toggleItemsBatch(
                  domain.id,
                  items,
                  select: !allSectionSelected,
                ),
                child: Text(
                  allSectionSelected
                      ? 'Désélectionner (${items.length})'
                      : selectedInSection > 0
                      ? 'Tout sélectionner ($selectedInSection/${items.length})'
                      : 'Tout sélectionner',
                ),
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: isCollapsed
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            'Aucun élément dans cette catégorie.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Wrap(
                          spacing: 16,
                          runSpacing: 14,
                          children: [
                            for (final item in items)
                              _BuildDesignItemCard(
                                item: item,
                                selected: _isItemSelected(domain.id, item),
                                onTap: () =>
                                    _toggleItemSelection(domain.id, item),
                                onStageTap: widget.editableIndicators
                                    ? (stage) => unawaited(
                                        _cycleItemStage(domain, item, stage),
                                      )
                                    : null,
                              ),
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

IconData _iconForKind(BuildDesignItemKind kind) => switch (kind) {
  BuildDesignItemKind.model => Icons.data_object_rounded,
  BuildDesignItemKind.useCase => Icons.check_circle_outline_rounded,
  BuildDesignItemKind.saga => Icons.account_tree_outlined,
};

class _StageFilterDropdown extends StatelessWidget {
  const _StageFilterDropdown({
    required this.selectedStage,
    required this.onChanged,
  });

  final ContractStage? selectedStage;
  final ValueChanged<ContractStage?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selectedStage != null ? colors.primary : colors.outlineVariant,
        ),
        color: selectedStage != null
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : colors.surface,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ContractStage?>(
          key: const ValueKey('build-filter-stage'),
          value: selectedStage,
          isDense: true,
          style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurface),
          items: [
            const DropdownMenuItem<ContractStage?>(
              value: null,
              child: Text('Toutes étapes'),
            ),
            for (final stage in ContractStage.values)
              DropdownMenuItem<ContractStage?>(
                value: stage,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Icon(contractStageIcons[stage], size: 14),
                    Text(contractStageLabels[stage]!),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _StatusFilterDropdown extends StatelessWidget {
  const _StatusFilterDropdown({
    required this.selectedStatus,
    required this.onChanged,
  });

  final ContractStatus? selectedStatus;
  final ValueChanged<ContractStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selectedStatus != null
              ? colors.primary
              : colors.outlineVariant,
        ),
        color: selectedStatus != null
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : colors.surface,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ContractStatus?>(
          key: const ValueKey('build-filter-status'),
          value: selectedStatus,
          isDense: true,
          style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurface),
          items: [
            const DropdownMenuItem<ContractStatus?>(
              value: null,
              child: Text('Tous statuts'),
            ),
            for (final status in ContractStatus.values)
              DropdownMenuItem<ContractStatus?>(
                value: status,
                child: Text(contractStatusLabels[status]!),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _BuildDesignItemCard extends StatefulWidget {
  const _BuildDesignItemCard({
    required this.item,
    required this.selected,
    required this.onTap,
    this.onStageTap,
  });

  final BuildDesignItem item;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<ContractStage>? onStageTap;

  @override
  State<_BuildDesignItemCard> createState() => _BuildDesignItemCardState();
}

class _BuildDesignItemCardState extends State<_BuildDesignItemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;
    final isSelected = widget.selected;

    final topColor = isSelected
        ? Color.lerp(
            colors.surfaceContainerLowest,
            colors.primaryContainer,
            isDark ? 0.36 : 0.45,
          )!
        : (isDark
              ? Color.lerp(
                  colors.surfaceContainerHighest,
                  colors.onSurface,
                  _hovered ? 0.16 : 0.10,
                )!
              : Color.lerp(
                  colors.surfaceContainerLowest,
                  colors.primary,
                  _hovered ? 0.07 : 0.02,
                )!);
    final bottomColor = isSelected
        ? Color.lerp(
            colors.surfaceContainer,
            colors.primaryContainer,
            isDark ? 0.24 : 0.30,
          )!
        : (isDark
              ? Color.lerp(
                  colors.surfaceContainerHigh,
                  colors.surfaceContainer,
                  _hovered ? 0.10 : 0.45,
                )!
              : Color.lerp(
                  colors.surfaceContainerHigh,
                  colors.surfaceContainer,
                  _hovered ? 0.25 : 0.55,
                )!);
    final borderColor = isSelected
        ? colors.primary
        : (isDark
              ? colors.outline.withValues(alpha: _hovered ? 0.85 : 0.55)
              : (_hovered
                    ? colors.primary.withValues(alpha: 0.55)
                    : colors.outlineVariant));

    final (primaryBg, primaryFg) = _badgeColors(item, colors);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(
          minWidth: 332,
          maxWidth: 332,
          minHeight: 78,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topColor, bottomColor],
          ),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.8 : 1.15,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: isDark ? 0.22 : 0.06),
              blurRadius: _hovered || isSelected ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('build-item-${item.kind.name}-${item.id}'),
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    key: ValueKey(
                      'build-item-check-${item.kind.name}-${item.id}',
                    ),
                    size: 20,
                    color: isSelected ? colors.primary : colors.outline,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _iconForKind(item.kind),
                    size: 20,
                    color: colors.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            height: 1.22,
                            color: colors.onSurface,
                          ),
                        ),
                        if (item.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (item.primaryBadge.isNotEmpty)
                                    _CompactBadge(
                                      label: item.primaryBadge,
                                      background: primaryBg,
                                      foreground: primaryFg,
                                    ),
                                  if (item.secondaryBadge.isNotEmpty)
                                    _CompactBadge(
                                      label: item.secondaryBadge,
                                      background:
                                          colors.surfaceContainerHighest,
                                      foreground: colors.onSurfaceVariant,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            ContractPhaseStatusStrip(
                              keyPrefix:
                                  'build-item-phase-${item.kind.name}-${item.id}',
                              states: item.states,
                              iconSize: 15,
                              onStageTap: widget.onStageTap,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static (Color, Color) _badgeColors(BuildDesignItem item, ColorScheme colors) {
    switch (item.kind) {
      case BuildDesignItemKind.model:
        final base = contractTypeColor(item.primaryBadge);
        return (base.withValues(alpha: 0.15), base);
      case BuildDesignItemKind.useCase:
        return (colors.secondaryContainer, colors.onSecondaryContainer);
      case BuildDesignItemKind.saga:
        return (colors.tertiaryContainer, colors.onTertiaryContainer);
    }
  }
}

class _CompactBadge extends StatelessWidget {
  const _CompactBadge({
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
