/// Deuxième page de l'onglet Build ([BuildPromptsSelectionView]) affichant,
/// regroupés par élément de design sélectionné (`Value Object`, `Modèle`,
/// `Use Case`, `Saga`), les prompts IA d'implémentation en Architecture
/// Hexagonale ainsi que le sélecteur de mode de génération inter-itérations
/// ([BuildPromptGenerationMode]).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/build_design_item.dart';
import '../../models/build_tech_stack_profile.dart';
import '../../models/domain_catalog.dart';
import '../../models/domain_contracts.dart';
import '../../services/design_evolution_analyzer.dart';
import '../../services/exporters/build_hexa_prompt_generator.dart';
import '../design/contract_entry_view.dart'
    show ContractPhaseStatusStrip, contractTypeColor;
import '../design/iteration_snapshot_dialogs.dart' show EvolutionDriftBadge;
import '../workspace/markdown_viewer_dialog.dart';
import 'build_tech_stacks_dialog.dart';

/// Vue « Sélection des Prompts IA » regroupant :
/// - pour chaque **Value Object** sélectionné : 2 prompts (`Domain Impl/TU`),
/// - pour chaque **Modèle** sélectionné : 4 prompts (`Domain Impl/TU`, `Persistance Impl/TU`),
/// - pour chaque **Use Case** ou **Saga** sélectionné : 2 prompts (`UseCase / Saga Impl/TU`),
/// - en bas de la liste (sans rattachement) : les groupes autonomes **Outbound**, **Inbound**, **Boilerplate**, **Dev Tools**, **Check Integration** et **Playground** (`Impl/TU`).
class BuildPromptsSelectionView extends StatefulWidget {
  /// Crée la vue de sélection et copie des prompts IA.
  const BuildPromptsSelectionView({
    required this.domain,
    required this.groups,
    this.techStacks = const <BuildTechStackProfile>[],
    this.selectedTechStackId,
    this.onTechStackChanged,
    this.onManageTechStacks,
    this.onBackToItems,
    this.onStageTap,
    this.onCopiedPrompt,
    this.markdownViewerSurfaceBuilder,
    this.markdownBrowserLauncher,
    this.promptMode = BuildPromptGenerationMode.autoByBaseline,
    this.hasActiveBaseline = false,
    this.activeBaselineLabel,
    this.onPromptModeChanged,
    super.key,
  });

  /// Domaine fonctionnel actif.
  final FunctionalDomain domain;

  /// Groupes de prompts par élément de design sélectionné.
  final List<BuildItemPromptGroup> groups;

  /// Profils de stacks techniques disponibles dans le catalogue.
  final List<BuildTechStackProfile> techStacks;

  /// Identifiant de la stack technique actuellement affectée à [domain].
  final String? selectedTechStackId;

  /// Déclenché lors du changement de stack technique depuis la page Prompts IA.
  final ValueChanged<String?>? onTechStackChanged;

  /// Ouvre l'éditeur modal de configuration des stacks techniques.
  final VoidCallback? onManageTechStacks;

  /// Retourne à la liste de sélection des items Build (niveau 0).
  final VoidCallback? onBackToItems;

  /// Callback optionnelle pour faire évoluer les 4 indicateurs d'un item.
  final void Function(BuildDesignItem item, ContractStage stage)? onStageTap;

  /// Callback optionnelle notifiée avec le texte Markdown copié (utile en test).
  final ValueChanged<String>? onCopiedPrompt;

  /// Substitut optionnel de la WebView pour le visualisateur Markdown (tests).
  final SpecMarkdownViewerSurfaceBuilder? markdownViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour le visualisateur Markdown (tests).
  final SpecMarkdownBrowserLauncher? markdownBrowserLauncher;

  /// Mode courant de génération des prompts vis-à-vis du jalon d'itération actif.
  final BuildPromptGenerationMode promptMode;

  /// Indique si le domaine possède un jalon d'itération de référence actif.
  final bool hasActiveBaseline;

  /// Libellé du jalon d'itération actif lorsque [hasActiveBaseline] vaut `true`.
  final String? activeBaselineLabel;

  /// Callback optionnelle déclenchée lors du changement de [BuildPromptGenerationMode].
  final ValueChanged<BuildPromptGenerationMode>? onPromptModeChanged;

  @override
  State<BuildPromptsSelectionView> createState() =>
      _BuildPromptsSelectionViewState();
}

class _BuildPromptsSelectionViewState extends State<BuildPromptsSelectionView> {
  static const Set<BuildTechStackSection> _defaultDisabledSections =
      <BuildTechStackSection>{
        BuildTechStackSection.outbound,
        BuildTechStackSection.inbound,
        BuildTechStackSection.boilerplate,
        BuildTechStackSection.devTools,
        BuildTechStackSection.checkIntegration,
        BuildTechStackSection.playground,
      };

  final Set<String> _deselectedPromptIds = <String>{};
  final Set<String> _initializedPromptIds = <String>{};
  final Set<String> _collapsedGroupKeys = <String>{};
  final Set<String> _expandedPromptIds = <String>{};
  BuildHexaPromptRole? _roleFilter;
  BuildTechStackSection? _sectionFilter;

  @override
  void initState() {
    super.initState();
    _initializeDefaultSelections(widget.groups);
  }

  @override
  void didUpdateWidget(BuildPromptsSelectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.domain.id != widget.domain.id) {
      _deselectedPromptIds.clear();
      _initializedPromptIds.clear();
    }
    _initializeDefaultSelections(widget.groups);
  }

  void _initializeDefaultSelections(List<BuildItemPromptGroup> groups) {
    for (final group in groups) {
      for (final prompt in group.prompts) {
        if (_initializedPromptIds.add(prompt.id) &&
            _defaultDisabledSections.contains(prompt.section)) {
          _deselectedPromptIds.add(prompt.id);
        }
      }
    }
  }

  bool _isPromptSelected(BuildHexaPromptSpec prompt) =>
      !_deselectedPromptIds.contains(prompt.id);

  bool _matchesFilters(BuildHexaPromptSpec prompt) =>
      (_roleFilter == null || prompt.role == _roleFilter) &&
      (_sectionFilter == null || prompt.section == _sectionFilter);

  List<BuildHexaPromptSpec> get _allPrompts => <BuildHexaPromptSpec>[
    for (final group in widget.groups) ...group.prompts,
  ];

  List<BuildHexaPromptSpec> get _selectedPrompts => <BuildHexaPromptSpec>[
    for (final group in widget.groups)
      for (final prompt in group.prompts)
        if (_isPromptSelected(prompt) && _matchesFilters(prompt)) prompt,
  ];

  List<BuildTechStackSection> get _availableSections {
    final present = {for (final p in _allPrompts) p.section};
    return <BuildTechStackSection>[
      for (final section in BuildTechStackSection.values)
        if (present.contains(section)) section,
    ];
  }

  void _togglePromptSelection(String promptId) {
    setState(() {
      if (!_deselectedPromptIds.remove(promptId)) {
        _deselectedPromptIds.add(promptId);
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      for (final prompt in _allPrompts) {
        if (_matchesFilters(prompt)) {
          _deselectedPromptIds.remove(prompt.id);
        }
      }
    });
  }

  void _clearAllVisible() {
    setState(() {
      for (final prompt in _allPrompts) {
        if (_matchesFilters(prompt)) {
          _deselectedPromptIds.add(prompt.id);
        }
      }
    });
  }

  void _toggleGroupCollapsed(BuildItemPromptGroup group) {
    final key = group.groupId;
    setState(() {
      if (!_collapsedGroupKeys.remove(key)) {
        _collapsedGroupKeys.add(key);
      }
    });
  }

  void _togglePromptExpanded(String promptId) {
    setState(() {
      if (!_expandedPromptIds.remove(promptId)) {
        _expandedPromptIds.add(promptId);
      }
    });
  }

  Future<void> _copyMarkdown(
    BuildContext context, {
    required String markdown,
    required String feedbackMessage,
  }) async {
    if (markdown.trim().isEmpty) return;
    widget.onCopiedPrompt?.call(markdown);
    await Clipboard.setData(ClipboardData(text: markdown));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(feedbackMessage),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _previewMarkdown(
    BuildContext context, {
    required String markdown,
    required String title,
    required String filenameStem,
  }) {
    if (markdown.trim().isEmpty) return;
    unawaited(
      showSpecMarkdownViewerDialog(
        context,
        markdown: markdown,
        title: title,
        filenameStem: filenameStem,
        surfaceBuilder: widget.markdownViewerSurfaceBuilder,
        openInBrowser: widget.markdownBrowserLauncher,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (widget.groups.isEmpty) {
      return Center(
        key: const ValueKey('build-prompts-empty-state'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Icon(
                Icons.playlist_add_check_rounded,
                size: 36,
                color: colors.onSurfaceVariant,
              ),
              Text(
                'Aucun élément sélectionné pour générer les prompts IA.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (widget.onBackToItems != null)
                FilledButton.tonalIcon(
                  key: const ValueKey('build-prompts-back-empty-btn'),
                  onPressed: widget.onBackToItems,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Sélectionner des items'),
                ),
            ],
          ),
        ),
      );
    }

    final allPrompts = _allPrompts;
    final selectedPrompts = _selectedPrompts;
    final availableRoles = BuildHexaPromptRole.values;
    final availableSections = _availableSections;

    return Column(
      key: const ValueKey('build-prompts-selection-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(
          context,
          theme: theme,
          colors: colors,
          allPromptsCount: allPrompts.length,
          selectedPrompts: selectedPrompts,
          availableRoles: availableRoles,
          availableSections: availableSections,
        ),
        if (widget.selectedTechStackId == null &&
            widget.techStacks.isNotEmpty &&
            widget.onTechStackChanged != null)
          Container(
            key: const ValueKey('build-prompts-no-stack-banner'),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer.withValues(alpha: 0.45),
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
            ),
            child: Row(
              spacing: 12,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: colors.onTertiaryContainer,
                ),
                Expanded(
                  child: Text(
                    'Aucune stack technique affectée au domaine « ${widget.domain.name} » : les contraintes et dossiers de stack ne sont pas ajoutés en fin de prompt.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('build-prompts-apply-default-stack-btn'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      widget.onTechStackChanged!(widget.techStacks.first.id),
                  icon: const Icon(Icons.layers_rounded, size: 15),
                  label: Text('Appliquer ${widget.techStacks.first.name}'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            itemCount: widget.groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 18),
            itemBuilder: (context, index) {
              final group = widget.groups[index];
              final visiblePrompts = <BuildHexaPromptSpec>[
                for (final p in group.prompts)
                  if (_matchesFilters(p)) p,
              ];
              if (visiblePrompts.isEmpty) {
                return const SizedBox.shrink();
              }
              final collapsed = _collapsedGroupKeys.contains(group.groupId);
              final selectedInGroup = visiblePrompts
                  .where(_isPromptSelected)
                  .toList(growable: false);

              return _BuildPromptGroupCard(
                group: group,
                visiblePrompts: visiblePrompts,
                selectedCount: selectedInGroup.length,
                collapsed: collapsed,
                hasActiveBaseline: widget.hasActiveBaseline,
                isPromptSelected: _isPromptSelected,
                isPromptExpanded: _expandedPromptIds.contains,
                onToggleCollapsed: () => _toggleGroupCollapsed(group),
                onTogglePromptSelected: _togglePromptSelection,
                onTogglePromptExpanded: _togglePromptExpanded,
                onStageTap: widget.onStageTap != null && group.item != null
                    ? (stage) => widget.onStageTap!(group.item!, stage)
                    : null,
                onCopyGroup: selectedInGroup.isEmpty
                    ? null
                    : () => unawaited(
                        _copyMarkdown(
                          context,
                          markdown:
                              BuildHexaPromptGenerator.combinePromptsMarkdown(
                                domain: widget.domain,
                                prompts: selectedInGroup,
                              ),
                          feedbackMessage:
                              '${selectedInGroup.length} prompt(s) de « ${group.groupTitle} » copié(s)',
                        ),
                      ),
                onCopyPrompt: (prompt) => unawaited(
                  _copyMarkdown(
                    context,
                    markdown: prompt.promptMarkdown,
                    feedbackMessage: 'Prompt « ${prompt.title} » copié',
                  ),
                ),
                onPreviewPrompt: (prompt) => _previewMarkdown(
                  context,
                  markdown: prompt.promptMarkdown,
                  title: prompt.title,
                  filenameStem:
                      'prompt_${widget.domain.domainCode}_${group.groupTitle}_${prompt.section.name}_${prompt.role.name}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme colors,
    required int allPromptsCount,
    required List<BuildHexaPromptSpec> selectedPrompts,
    required List<BuildHexaPromptRole> availableRoles,
    required List<BuildTechStackSection> availableSections,
  }) {
    return Container(
      key: const ValueKey('build-prompts-toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Icon(Icons.terminal_rounded, size: 18, color: colors.primary),
              Text(
                '${selectedPrompts.length} / $allPromptsCount prompt(s) · ${widget.groups.length} groupe(s)',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          ChoiceChip(
            key: const ValueKey('build-prompts-filter-all'),
            label: const Text('Tous les rôles'),
            selected: _roleFilter == null,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _roleFilter = null),
          ),
          for (final role in availableRoles)
            ChoiceChip(
              key: ValueKey('build-prompts-filter-${role.name}'),
              avatar: Icon(_iconForRole(role), size: 15),
              label: Text(role.label),
              selected: _roleFilter == role,
              visualDensity: VisualDensity.compact,
              onSelected: (selected) =>
                  setState(() => _roleFilter = selected ? role : null),
            ),
          if (availableSections.length > 1)
            for (final section in availableSections)
              ChoiceChip(
                key: ValueKey('build-prompts-section-filter-${section.name}'),
                avatar: Icon(_iconForSection(section), size: 14),
                label: Text(section.label),
                selected: _sectionFilter == section,
                visualDensity: VisualDensity.compact,
                onSelected: (selected) =>
                    setState(() => _sectionFilter = selected ? section : null),
              ),
          if (widget.onTechStackChanged != null)
            DomainTechStackSelector(
              dropdownKey: const ValueKey('build-prompts-stack-selector'),
              manageButtonKey: const ValueKey(
                'build-prompts-manage-stacks-btn',
              ),
              techStacks: widget.techStacks,
              selectedStackId: widget.selectedTechStackId,
              onChanged: widget.onTechStackChanged!,
              onManageStacks: widget.onManageTechStacks,
            ),
          _PromptGenerationModeSelector(
            promptMode: widget.promptMode,
            hasActiveBaseline: widget.hasActiveBaseline,
            activeBaselineLabel: widget.activeBaselineLabel,
            onChanged: widget.onPromptModeChanged,
          ),
          TextButton(
            key: const ValueKey('build-prompts-select-all-btn'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _selectAllVisible,
            child: const Text('Tout cocher'),
          ),
          TextButton(
            key: const ValueKey('build-prompts-clear-all-btn'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _clearAllVisible,
            child: const Text('Tout décocher'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('build-prompts-preview-all-btn'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            onPressed: selectedPrompts.isEmpty
                ? null
                : () => _previewMarkdown(
                    context,
                    markdown: BuildHexaPromptGenerator.combinePromptsMarkdown(
                      domain: widget.domain,
                      prompts: selectedPrompts,
                    ),
                    title:
                        'Prompts — ${widget.domain.name} (${selectedPrompts.length})',
                    filenameStem: 'prompts_${widget.domain.domainCode}',
                  ),
            icon: const Icon(Icons.preview_outlined, size: 16),
            label: const Text('Aperçu'),
          ),
          FilledButton.icon(
            key: const ValueKey('build-copy-selected-prompts-btn'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: selectedPrompts.isEmpty
                ? null
                : () => unawaited(
                    _copyMarkdown(
                      context,
                      markdown: BuildHexaPromptGenerator.combinePromptsMarkdown(
                        domain: widget.domain,
                        prompts: selectedPrompts,
                      ),
                      feedbackMessage:
                          '${selectedPrompts.length} prompt(s) copié(s)',
                    ),
                  ),
            icon: const Icon(Icons.copy_all_rounded, size: 17),
            label: Text('Copier les prompts (${selectedPrompts.length})'),
          ),
        ],
      ),
    );
  }
}

class _PromptGenerationModeSelector extends StatelessWidget {
  const _PromptGenerationModeSelector({
    required this.promptMode,
    required this.hasActiveBaseline,
    required this.activeBaselineLabel,
    required this.onChanged,
  });

  final BuildPromptGenerationMode promptMode;
  final bool hasActiveBaseline;
  final String? activeBaselineLabel;
  final ValueChanged<BuildPromptGenerationMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = onChanged != null;
    final cleanBaseline = activeBaselineLabel?.trim() ?? '';
    final baselineSubtitle = hasActiveBaseline
        ? 'Jalon actif : ${cleanBaseline.isNotEmpty ? cleanBaseline : 'Référence'}'
        : 'Aucun jalon actif — génération complète';

    return Container(
      key: const ValueKey('build-prompt-mode-selector'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: enabled
            ? colors.surfaceContainerLow
            : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? colors.primary.withValues(alpha: 0.35)
              : colors.outlineVariant,
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Icon(
                Icons.published_with_changes_rounded,
                size: 15,
                color: enabled ? colors.primary : colors.onSurfaceVariant,
              ),
              Text(
                'Mode :',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          for (final mode in BuildPromptGenerationMode.values)
            _buildModeSegment(
              context,
              mode: mode,
              selected: promptMode == mode,
              enabled: enabled,
              colors: colors,
              theme: theme,
            ),
          Text(
            baselineSubtitle,
            key: const ValueKey('build-prompt-mode-baseline-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: hasActiveBaseline
                  ? colors.onSecondaryContainer
                  : colors.onSurfaceVariant,
              fontWeight: hasActiveBaseline ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSegment(
    BuildContext context, {
    required BuildPromptGenerationMode mode,
    required bool selected,
    required bool enabled,
    required ColorScheme colors,
    required ThemeData theme,
  }) {
    final bg = selected
        ? (enabled
              ? colors.primaryContainer
              : colors.surfaceContainerHighest)
        : Colors.transparent;
    final fg = selected
        ? (enabled ? colors.onPrimaryContainer : colors.onSurface)
        : (enabled
              ? colors.onSurfaceVariant
              : colors.onSurfaceVariant.withValues(alpha: 0.65));
    final border = selected
        ? (enabled ? colors.primary : colors.outline)
        : colors.outlineVariant.withValues(alpha: 0.6);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border),
      ),
      child: Text(
        mode.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: fg,
        ),
      ),
    );

    return Tooltip(
      message: mode.subtitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('build-prompt-mode-${mode.name}'),
          borderRadius: BorderRadius.circular(7),
          onTap: enabled ? () => onChanged!(mode) : null,
          child: pill,
        ),
      ),
    );
  }
}

class _BuildPromptGroupCard extends StatelessWidget {
  const _BuildPromptGroupCard({
    required this.group,
    required this.visiblePrompts,
    required this.selectedCount,
    required this.collapsed,
    required this.hasActiveBaseline,
    required this.isPromptSelected,
    required this.isPromptExpanded,
    required this.onToggleCollapsed,
    required this.onTogglePromptSelected,
    required this.onTogglePromptExpanded,
    required this.onCopyPrompt,
    required this.onPreviewPrompt,
    this.onStageTap,
    this.onCopyGroup,
  });

  final BuildItemPromptGroup group;
  final List<BuildHexaPromptSpec> visiblePrompts;
  final int selectedCount;
  final bool collapsed;
  final bool hasActiveBaseline;
  final bool Function(BuildHexaPromptSpec) isPromptSelected;
  final bool Function(String promptId) isPromptExpanded;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String> onTogglePromptSelected;
  final ValueChanged<String> onTogglePromptExpanded;
  final ValueChanged<BuildHexaPromptSpec> onCopyPrompt;
  final ValueChanged<BuildHexaPromptSpec> onPreviewPrompt;
  final ValueChanged<ContractStage>? onStageTap;
  final VoidCallback? onCopyGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final item = group.item;
    final (badgeBg, badgeFg) = _groupBadgeColors(group, colors);
    final keySlug = item != null
        ? '${item.kind.name}-${item.id}'
        : 'standalone-${group.standaloneSection!.name}';
    final hasDeltaInGroup = visiblePrompts.any((p) => p.isEvolutionDelta);

    return Container(
      key: ValueKey('build-prompt-group-$keySlug'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: ValueKey('build-prompt-group-toggle-$keySlug'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: onToggleCollapsed,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          AnimatedRotation(
                            turns: collapsed ? -0.25 : 0.0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: Icon(
                              Icons.expand_more_rounded,
                              size: 22,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            item != null
                                ? _iconForItemKind(item.kind)
                                : _iconForSection(group.standaloneSection!),
                            size: 20,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _GroupPill(
                                  label: group.kindLabel,
                                  background: colors.primaryContainer,
                                  foreground: colors.onPrimaryContainer,
                                ),
                                if (group.primaryBadge.isNotEmpty)
                                  _GroupPill(
                                    label: group.primaryBadge,
                                    background: badgeBg,
                                    foreground: badgeFg,
                                  ),
                                Text(
                                  group.groupTitle,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (group.groupSubtitle.isNotEmpty)
                                  Text(
                                    '— ${group.groupSubtitle}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                _GroupPill(
                                  label:
                                      '$selectedCount/${visiblePrompts.length} prompt(s)',
                                  background: colors.surfaceContainerHighest,
                                  foreground: colors.onSurfaceVariant,
                                ),
                                if (hasActiveBaseline && item != null)
                                  EvolutionDriftBadge(
                                    report: item.evolution,
                                    compact: true,
                                  )
                                else if (hasActiveBaseline && hasDeltaInGroup)
                                  _GroupPill(
                                    key: ValueKey(
                                      'prompt-group-delta-badge-$keySlug',
                                    ),
                                    label: 'Migration / décommissionnement',
                                    background: Colors.amber.withValues(
                                      alpha: isDark ? 0.22 : 0.16,
                                    ),
                                    foreground: isDark
                                        ? Colors.amber.shade200
                                        : Colors.orange.shade900,
                                    icon: Icons.compare_arrows_rounded,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (item != null) ...[
                  ContractPhaseStatusStrip(
                    keyPrefix: 'build-prompt-group-phase-$keySlug',
                    states: item.states,
                    iconSize: 15,
                    onStageTap: onStageTap,
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton.icon(
                  key: ValueKey('build-prompt-group-copy-$keySlug'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onCopyGroup,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copier le groupe'),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      spacing: 10,
                      children: [
                        for (final prompt in visiblePrompts)
                          _BuildPromptTile(
                            prompt: prompt,
                            selected: isPromptSelected(prompt),
                            expanded: isPromptExpanded(prompt.id),
                            hasActiveBaseline: hasActiveBaseline,
                            onToggleSelected: () =>
                                onTogglePromptSelected(prompt.id),
                            onToggleExpanded: () =>
                                onTogglePromptExpanded(prompt.id),
                            onCopy: () => onCopyPrompt(prompt),
                            onPreview: () => onPreviewPrompt(prompt),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static (Color, Color) _groupBadgeColors(
    BuildItemPromptGroup group,
    ColorScheme colors,
  ) {
    final item = group.item;
    if (item == null) {
      return switch (group.standaloneSection) {
        BuildTechStackSection.outbound => (
          colors.tertiaryContainer,
          colors.onTertiaryContainer,
        ),
        BuildTechStackSection.inbound => (
          colors.secondaryContainer,
          colors.onSecondaryContainer,
        ),
        BuildTechStackSection.boilerplate => (
          Colors.blueGrey.withValues(alpha: 0.16),
          Colors.blueGrey.shade800,
        ),
        BuildTechStackSection.devTools => (
          Colors.cyan.withValues(alpha: 0.16),
          Colors.cyan.shade900,
        ),
        BuildTechStackSection.checkIntegration => (
          Colors.green.withValues(alpha: 0.16),
          Colors.green.shade800,
        ),
        BuildTechStackSection.playground => (
          Colors.pink.withValues(alpha: 0.15),
          Colors.pink.shade800,
        ),
        _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
      };
    }
    switch (item.kind) {
      case BuildDesignItemKind.valueObject:
        final base = Colors.cyan.shade700;
        return (base.withValues(alpha: 0.15), base);
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

class _BuildPromptTile extends StatelessWidget {
  const _BuildPromptTile({
    required this.prompt,
    required this.selected,
    required this.expanded,
    required this.hasActiveBaseline,
    required this.onToggleSelected,
    required this.onToggleExpanded,
    required this.onCopy,
    required this.onPreview,
  });

  final BuildHexaPromptSpec prompt;
  final bool selected;
  final bool expanded;
  final bool hasActiveBaseline;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleExpanded;
  final VoidCallback onCopy;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final (roleBg, roleFg) = _roleBadgeColors(prompt.role, colors);
    final (sectionBg, sectionFg) = _sectionBadgeColors(prompt.section, colors);
    final isImpactedOnly =
        prompt.item?.evolutionState == ArtifactEvolutionState.impacted;
    final deltaBg = isImpactedOnly
        ? Colors.indigo.withValues(alpha: isDark ? 0.24 : 0.14)
        : Colors.amber.withValues(alpha: isDark ? 0.22 : 0.16);
    final deltaFg = isImpactedOnly
        ? (isDark ? Colors.indigo.shade200 : Colors.indigo.shade800)
        : (isDark ? Colors.amber.shade200 : Colors.orange.shade900);

    return Container(
      key: ValueKey('build-prompt-card-${prompt.id}'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colors.primary.withValues(alpha: 0.55)
              : colors.outlineVariant,
          width: selected ? 1.3 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  key: ValueKey('build-prompt-check-${prompt.id}'),
                  value: selected,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => onToggleSelected(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onToggleExpanded,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _GroupPill(
                                label: prompt.section.label,
                                background: sectionBg,
                                foreground: sectionFg,
                                icon: _iconForSection(prompt.section),
                              ),
                              _GroupPill(
                                label: prompt.role.label,
                                background: roleBg,
                                foreground: roleFg,
                                icon: _iconForRole(prompt.role),
                              ),
                              if (prompt.isEvolutionDelta)
                                _GroupPill(
                                  key: ValueKey(
                                    'prompt-delta-badge-${prompt.id}',
                                  ),
                                  label:
                                      'Delta v${prompt.baselineVersion ?? '—'} → v${prompt.item?.version ?? '—'}',
                                  background: deltaBg,
                                  foreground: deltaFg,
                                  icon: Icons.compare_arrows_rounded,
                                )
                              else if (hasActiveBaseline)
                                _GroupPill(
                                  key: ValueKey(
                                    'prompt-full-badge-${prompt.id}',
                                  ),
                                  label: 'Création complète',
                                  background: Colors.teal.withValues(
                                    alpha: isDark ? 0.20 : 0.12,
                                  ),
                                  foreground: isDark
                                      ? Colors.teal.shade200
                                      : Colors.teal.shade800,
                                  icon: Icons.fiber_new_outlined,
                                ),
                              Text(
                                prompt.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            prompt.summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('build-prompt-expand-${prompt.id}'),
                  tooltip: expanded ? 'Masquer le prompt' : 'Voir le prompt',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    expanded ? Icons.unfold_less_rounded : Icons.code_rounded,
                    size: 18,
                  ),
                  onPressed: onToggleExpanded,
                ),
                IconButton(
                  key: ValueKey('build-prompt-preview-${prompt.id}'),
                  tooltip: 'Aperçu Markdown',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.preview_outlined, size: 18),
                  onPressed: onPreview,
                ),
                FilledButton.tonalIcon(
                  key: ValueKey('build-prompt-copy-${prompt.id}'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copier'),
                ),
              ],
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: SelectableText(
                prompt.promptMarkdown,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static (Color, Color) _roleBadgeColors(
    BuildHexaPromptRole role,
    ColorScheme colors,
  ) => switch (role) {
    BuildHexaPromptRole.implementation => (
      Colors.indigo.withValues(alpha: 0.14),
      Colors.indigo.shade700,
    ),
    BuildHexaPromptRole.unitTest => (
      Colors.teal.withValues(alpha: 0.15),
      Colors.teal.shade700,
    ),
  };

  static (Color, Color) _sectionBadgeColors(
    BuildTechStackSection section,
    ColorScheme colors,
  ) => switch (section) {
    BuildTechStackSection.domain => (
      colors.primaryContainer,
      colors.onPrimaryContainer,
    ),
    BuildTechStackSection.useCaseSaga => (
      colors.secondaryContainer,
      colors.onSecondaryContainer,
    ),
    BuildTechStackSection.outbound => (
      Colors.amber.withValues(alpha: 0.18),
      Colors.amber.shade900,
    ),
    BuildTechStackSection.inbound => (
      Colors.purple.withValues(alpha: 0.14),
      Colors.purple.shade800,
    ),
    BuildTechStackSection.persistence => (
      Colors.deepOrange.withValues(alpha: 0.14),
      Colors.deepOrange.shade800,
    ),
    BuildTechStackSection.boilerplate => (
      Colors.blueGrey.withValues(alpha: 0.16),
      Colors.blueGrey.shade800,
    ),
    BuildTechStackSection.devTools => (
      Colors.cyan.withValues(alpha: 0.16),
      Colors.cyan.shade900,
    ),
    BuildTechStackSection.checkIntegration => (
      Colors.green.withValues(alpha: 0.16),
      Colors.green.shade800,
    ),
    BuildTechStackSection.playground => (
      Colors.pink.withValues(alpha: 0.15),
      Colors.pink.shade800,
    ),
  };
}

class _GroupPill extends StatelessWidget {
  const _GroupPill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (icon != null) Icon(icon, size: 13, color: foreground),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForItemKind(BuildDesignItemKind kind) => switch (kind) {
  BuildDesignItemKind.valueObject => Icons.verified_outlined,
  BuildDesignItemKind.model => Icons.data_object_rounded,
  BuildDesignItemKind.useCase => Icons.check_circle_outline_rounded,
  BuildDesignItemKind.saga => Icons.account_tree_outlined,
};

IconData _iconForSection(BuildTechStackSection section) => switch (section) {
  BuildTechStackSection.domain => Icons.data_object_rounded,
  BuildTechStackSection.useCaseSaga => Icons.account_tree_outlined,
  BuildTechStackSection.outbound => Icons.call_made_rounded,
  BuildTechStackSection.inbound => Icons.call_received_rounded,
  BuildTechStackSection.persistence => Icons.storage_rounded,
  BuildTechStackSection.boilerplate => Icons.foundation_rounded,
  BuildTechStackSection.devTools => Icons.build_circle_outlined,
  BuildTechStackSection.checkIntegration => Icons.fact_check_outlined,
  BuildTechStackSection.playground => Icons.play_circle_outline_rounded,
};

IconData _iconForRole(BuildHexaPromptRole role) => switch (role) {
  BuildHexaPromptRole.implementation => Icons.code_rounded,
  BuildHexaPromptRole.unitTest => Icons.science_outlined,
};
