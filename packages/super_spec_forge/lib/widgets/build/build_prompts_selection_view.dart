/// Deuxième page de l'onglet Build ([BuildPromptsSelectionView]) affichant,
/// regroupés par élément de design sélectionné (`Modèle`, `Use Case`, `Saga`),
/// les prompts IA d'implémentation en Architecture Hexagonale.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/build_design_item.dart';
import '../../models/build_tech_stack_profile.dart';
import '../../models/domain_catalog.dart';
import '../../models/domain_contracts.dart';
import '../../services/exporters/build_hexa_prompt_generator.dart';
import '../design/contract_entry_view.dart'
    show ContractPhaseStatusStrip, contractTypeColor;
import '../workspace/markdown_viewer_dialog.dart';
import 'build_tech_stacks_dialog.dart';

/// Vue « Sélection des Prompts IA » regroupant par élément sélectionné :
/// - pour un **Modèle** : 3 prompts (`Implémentation`, `Tests unitaires`, `Persistance`),
/// - pour un **Use Case** ou une **Saga** : 2 prompts (`Implémentation`, `Tests unitaires`).
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

  @override
  State<BuildPromptsSelectionView> createState() =>
      _BuildPromptsSelectionViewState();
}

class _BuildPromptsSelectionViewState extends State<BuildPromptsSelectionView> {
  final Set<String> _deselectedPromptIds = <String>{};
  final Set<String> _collapsedGroupKeys = <String>{};
  final Set<String> _expandedPromptIds = <String>{};
  BuildHexaPromptRole? _roleFilter;

  String _groupKey(BuildDesignItem item) => '${item.kind.name}:${item.id}';

  bool _isPromptSelected(BuildHexaPromptSpec prompt) =>
      !_deselectedPromptIds.contains(prompt.id);

  List<BuildHexaPromptSpec> get _allPrompts => <BuildHexaPromptSpec>[
    for (final group in widget.groups) ...group.prompts,
  ];

  List<BuildHexaPromptSpec> get _selectedPrompts => <BuildHexaPromptSpec>[
    for (final group in widget.groups)
      for (final prompt in group.prompts)
        if (_isPromptSelected(prompt) &&
            (_roleFilter == null || prompt.role == _roleFilter))
          prompt,
  ];

  bool get _hasAnyPersistencePrompt => widget.groups.any(
    (g) => g.prompts.any((p) => p.role == BuildHexaPromptRole.persistence),
  );

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
        if (_roleFilter == null || prompt.role == _roleFilter) {
          _deselectedPromptIds.remove(prompt.id);
        }
      }
    });
  }

  void _clearAllVisible() {
    setState(() {
      for (final prompt in _allPrompts) {
        if (_roleFilter == null || prompt.role == _roleFilter) {
          _deselectedPromptIds.add(prompt.id);
        }
      }
    });
  }

  void _toggleGroupCollapsed(BuildDesignItem item) {
    final key = _groupKey(item);
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
    final availableRoles = <BuildHexaPromptRole>[
      BuildHexaPromptRole.implementation,
      BuildHexaPromptRole.unitTest,
      if (_hasAnyPersistencePrompt) BuildHexaPromptRole.persistence,
    ];

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
                  if (_roleFilter == null || p.role == _roleFilter) p,
              ];
              if (visiblePrompts.isEmpty) {
                return const SizedBox.shrink();
              }
              final collapsed = _collapsedGroupKeys.contains(
                _groupKey(group.item),
              );
              final selectedInGroup = visiblePrompts
                  .where(_isPromptSelected)
                  .toList(growable: false);

              return _BuildPromptGroupCard(
                group: group,
                visiblePrompts: visiblePrompts,
                selectedCount: selectedInGroup.length,
                collapsed: collapsed,
                isPromptSelected: _isPromptSelected,
                isPromptExpanded: _expandedPromptIds.contains,
                onToggleCollapsed: () => _toggleGroupCollapsed(group.item),
                onTogglePromptSelected: _togglePromptSelection,
                onTogglePromptExpanded: _togglePromptExpanded,
                onStageTap: widget.onStageTap != null
                    ? (stage) => widget.onStageTap!(group.item, stage)
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
                              '${selectedInGroup.length} prompt(s) de « ${group.item.name} » copié(s)',
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
                      'prompt_${widget.domain.domainCode}_${group.item.name}_${prompt.role.name}',
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
                '${selectedPrompts.length} / $allPromptsCount prompt(s) · ${widget.groups.length} élément(s)',
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

class _BuildPromptGroupCard extends StatelessWidget {
  const _BuildPromptGroupCard({
    required this.group,
    required this.visiblePrompts,
    required this.selectedCount,
    required this.collapsed,
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
    final item = group.item;
    final (badgeBg, badgeFg) = _itemBadgeColors(item, colors);

    return Container(
      key: ValueKey('build-prompt-group-${item.kind.name}-${item.id}'),
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
                    key: ValueKey(
                      'build-prompt-group-toggle-${item.kind.name}-${item.id}',
                    ),
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
                            _iconForItemKind(item.kind),
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
                                  label: item.kind.shortLabel,
                                  background: colors.primaryContainer,
                                  foreground: colors.onPrimaryContainer,
                                ),
                                if (item.primaryBadge.isNotEmpty)
                                  _GroupPill(
                                    label: item.primaryBadge,
                                    background: badgeBg,
                                    foreground: badgeFg,
                                  ),
                                Text(
                                  item.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (item.subtitle.isNotEmpty)
                                  Text(
                                    '— ${item.subtitle}',
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ContractPhaseStatusStrip(
                  keyPrefix:
                      'build-prompt-group-phase-${item.kind.name}-${item.id}',
                  states: item.states,
                  iconSize: 15,
                  onStageTap: onStageTap,
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: ValueKey(
                    'build-prompt-group-copy-${item.kind.name}-${item.id}',
                  ),
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

  static (Color, Color) _itemBadgeColors(
    BuildDesignItem item,
    ColorScheme colors,
  ) {
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

class _BuildPromptTile extends StatelessWidget {
  const _BuildPromptTile({
    required this.prompt,
    required this.selected,
    required this.expanded,
    required this.onToggleSelected,
    required this.onToggleExpanded,
    required this.onCopy,
    required this.onPreview,
  });

  final BuildHexaPromptSpec prompt;
  final bool selected;
  final bool expanded;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleExpanded;
  final VoidCallback onCopy;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (roleBg, roleFg) = _roleBadgeColors(prompt.role, colors);

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
                                label: prompt.role.label,
                                background: roleBg,
                                foreground: roleFg,
                                icon: _iconForRole(prompt.role),
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
                    expanded
                        ? Icons.unfold_less_rounded
                        : Icons.code_rounded,
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
    BuildHexaPromptRole.persistence => (
      Colors.deepOrange.withValues(alpha: 0.14),
      Colors.deepOrange.shade800,
    ),
  };
}

class _GroupPill extends StatelessWidget {
  const _GroupPill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
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
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForItemKind(BuildDesignItemKind kind) => switch (kind) {
  BuildDesignItemKind.model => Icons.data_object_rounded,
  BuildDesignItemKind.useCase => Icons.check_circle_outline_rounded,
  BuildDesignItemKind.saga => Icons.account_tree_outlined,
};

IconData _iconForRole(BuildHexaPromptRole role) => switch (role) {
  BuildHexaPromptRole.implementation => Icons.layers_outlined,
  BuildHexaPromptRole.unitTest => Icons.science_outlined,
  BuildHexaPromptRole.persistence => Icons.storage_rounded,
};
