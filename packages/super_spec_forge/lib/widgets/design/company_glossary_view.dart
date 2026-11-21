/// Sous-vue de l'onglet Spec dédiée au Glossaire d'entreprise global ([CompanyGlossaryView]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/company_glossary.dart';
import '../../models/spec_stage_chat.dart';
import '../../services/exporters/company_glossary_codec.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_split_handle.dart';

/// Éditeur complet du glossaire terminologique d'entreprise avec assistant IA,
/// filtrage par statut/domaine, import/export et passerelle vers le projet actif.
class CompanyGlossaryView extends StatefulWidget {
  /// Crée la sous-vue connectée au [controller].
  const CompanyGlossaryView({
    required this.controller,
    required this.onBack,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Callback de retour vers le menu Spec.
  final VoidCallback onBack;

  /// Sélecteur optionnel de pièces jointes pour le chat IA.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers pour le chat IA.
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant la présence d'un média dans le presse-papiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers sur `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<CompanyGlossaryView> createState() => _CompanyGlossaryViewState();
}

enum _GlossarySortOrder {
  defaultOrder('Ordre par défaut'),
  recentlyUpdated('Modifiés récemment'),
  recentlyCreated('Ajoutés récemment'),
  alphabetical('Nom (A–Z)');

  const _GlossarySortOrder(this.label);

  final String label;
}

class _CompanyGlossaryViewState extends State<CompanyGlossaryView> {
  final GlobalKey _splitRowKey = GlobalKey();
  double _chatPaneFraction = 0.36;
  double _chatDragOffset = SpecSplitHandle.width / 2;

  String _search = '';
  CompanyGlossaryStatus? _statusFilter;
  String? _domainFilter;
  _GlossarySortOrder _sortOrder = _GlossarySortOrder.defaultOrder;

  void _cycleChatSize() {
    setState(() {
      if (_chatPaneFraction <= 0.0) {
        _chatPaneFraction = 0.36;
      } else {
        _chatPaneFraction = 0.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final glossary = widget.controller.companyGlossary;
    final project = widget.controller.project;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final domains = glossary.domains;
    final effectiveDomainFilter =
        _domainFilter != null && domains.contains(_domainFilter)
        ? _domainFilter
        : null;

    final filteredTerms = glossary.terms.where((t) {
      if (_statusFilter != null && t.status != _statusFilter) return false;
      if (effectiveDomainFilter != null &&
          t.domain.trim() != effectiveDomainFilter) {
        return false;
      }
      if (!t.matchesQuery(_search)) return false;
      return true;
    }).toList();

    switch (_sortOrder) {
      case _GlossarySortOrder.defaultOrder:
        break;
      case _GlossarySortOrder.recentlyUpdated:
        filteredTerms.sort((a, b) {
          final da = a.updatedAt ?? a.createdAt;
          final db = b.updatedAt ?? b.createdAt;
          if (da == null && db == null) {
            return a.term.toLowerCase().compareTo(b.term.toLowerCase());
          }
          if (da == null) return 1;
          if (db == null) return -1;
          final cmp = db.compareTo(da);
          return cmp != 0
              ? cmp
              : a.term.toLowerCase().compareTo(b.term.toLowerCase());
        });
      case _GlossarySortOrder.recentlyCreated:
        filteredTerms.sort((a, b) {
          final da = a.createdAt ?? a.updatedAt;
          final db = b.createdAt ?? b.updatedAt;
          if (da == null && db == null) {
            return a.term.toLowerCase().compareTo(b.term.toLowerCase());
          }
          if (da == null) return 1;
          if (db == null) return -1;
          final cmp = db.compareTo(da);
          return cmp != 0
              ? cmp
              : a.term.toLowerCase().compareTo(b.term.toLowerCase());
        });
      case _GlossarySortOrder.alphabetical:
        filteredTerms.sort(
          (a, b) => a.term.toLowerCase().compareTo(b.term.toLowerCase()),
        );
    }

    return Column(
      key: const ValueKey('company-glossary-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, theme, colors, glossary, project != null),
        const Divider(height: 1, thickness: 1),
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
                      key: const ValueKey('company-glossary-chat-collapsed'),
                      width: collapsedRailWidth,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          IconButton(
                            key: const ValueKey('company-glossary-chat-expand'),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher l’assistant IA du glossaire',
                            onPressed: _cycleChatSize,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      key: const ValueKey('company-glossary-chat-pane'),
                      width: chatWidth,
                      child: _GlossaryAiChatPane(
                        controller: widget.controller,
                        onCollapse: _cycleChatSize,
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                    ),
                  SpecSplitHandle(
                    key: const ValueKey('company-glossary-split-handle'),
                    onDoubleTap: () =>
                        setState(() => _chatPaneFraction = 0.36),
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
                    child: _buildWorkspace(
                      context,
                      theme,
                      colors,
                      glossary,
                      filteredTerms,
                      domains,
                      effectiveDomainFilter,
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

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    CompanyGlossary glossary,
    bool hasActiveProject,
  ) {
    final approvedCount = glossary.countByStatus(
      CompanyGlossaryStatus.approved,
    );
    final draftCount = glossary.countByStatus(CompanyGlossaryStatus.draft);

    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('spec-subview-back-btn'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Spec'),
              ),
              const SizedBox(width: 14),
              Icon(Icons.language_rounded, size: 22, color: colors.primary),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Glossaire d’entreprise (${glossary.terms.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$approvedCount validé(s) · $draftCount brouillon(s) · Référentiel partagé multi-projets'
                      '${glossary.updatedAt != null ? ' · Dernière maj ${_formatGlossaryDateTime(glossary.updatedAt!)}' : ''}',
                      maxLines: 2,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Annuler (Glossaire)',
                icon: const Icon(Icons.undo_rounded, size: 18),
                onPressed: widget.controller.canUndoGlossary
                    ? widget.controller.undoCompanyGlossary
                    : null,
              ),
              IconButton(
                tooltip: 'Rétablir (Glossaire)',
                icon: const Icon(Icons.redo_rounded, size: 18),
                onPressed: widget.controller.canRedoGlossary
                    ? widget.controller.redoCompanyGlossary
                    : null,
              ),
              if (hasActiveProject && glossary.terms.isNotEmpty)
                OutlinedButton.icon(
                  key: const ValueKey('company-glossary-sync-project-btn'),
                  onPressed: () => _syncToActiveProject(context, glossary),
                  icon: const Icon(Icons.sync_alt_rounded, size: 16),
                  label: const Text('Importer vers le projet'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('company-glossary-import-export-btn'),
                onPressed: () => _openImportExportDialog(context, glossary),
                icon: const Icon(Icons.import_export_rounded, size: 16),
                label: const Text('Importer / Exporter'),
              ),
              FilledButton.icon(
                key: const ValueKey('company-glossary-add-term-btn'),
                onPressed: () => _editTermDialog(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Nouveau terme'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    CompanyGlossary glossary,
    List<CompanyGlossaryTerm> filteredTerms,
    List<String> domains,
    String? effectiveDomainFilter,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('company-glossary-search-input'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText:
                      'Rechercher un terme, définition, synonyme, terme proscrit, référent ou nom technique…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            if (domains.isNotEmpty) ...[
              const SizedBox(width: 12),
              DropdownButtonHideUnderline(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.outline),
                  ),
                  child: DropdownButton<String?>(
                    key: const ValueKey('company-glossary-domain-filter'),
                    value: effectiveDomainFilter,
                    hint: const Text('Tous domaines'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tous domaines'),
                      ),
                      for (final d in domains)
                        DropdownMenuItem<String?>(value: d, child: Text(d)),
                    ],
                    onChanged: (v) => setState(() => _domainFilter = v),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outline),
                ),
                child: DropdownButton<_GlossarySortOrder>(
                  key: const ValueKey('company-glossary-sort'),
                  value: _sortOrder,
                  items: [
                    for (final order in _GlossarySortOrder.values)
                      DropdownMenuItem<_GlossarySortOrder>(
                        value: order,
                        child: Text(order.label),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortOrder = v);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilterChip(
              key: const ValueKey('company-glossary-filter-all'),
              label: Text('Tous (${glossary.terms.length})'),
              selected: _statusFilter == null,
              onSelected: (_) => setState(() => _statusFilter = null),
            ),
            for (final status in CompanyGlossaryStatus.values)
              FilterChip(
                key: ValueKey('company-glossary-filter-${status.name}'),
                label: Text(
                  '${status.label} (${glossary.countByStatus(status)})',
                ),
                selected: _statusFilter == status,
                onSelected: (_) => setState(
                  () => _statusFilter = _statusFilter == status ? null : status,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (filteredTerms.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                glossary.terms.isEmpty
                    ? 'Le glossaire d’entreprise est encore vide.\nAjoutez un terme, importez un fichier JSON/CSV, ou utilisez l’assistant IA à gauche pour extraire votre vocabulaire.'
                    : 'Aucun terme ne correspond aux filtres actuels.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final term in filteredTerms)
            _CompanyGlossaryTermCard(
              term: term,
              onEdit: () => _editTermDialog(context, existing: term),
              onDelete: () =>
                  widget.controller.deleteCompanyGlossaryTerm(term.id),
            ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StringListCard(
                title:
                    'Conventions d’entreprise (${glossary.conventions.length})',
                items: glossary.conventions,
                emptyText: 'Aucune convention d’entreprise enregistrée.',
                onAdd: () => _addStringItem(
                  context,
                  title: 'Nouvelle convention d’entreprise',
                  onSave: (val) => widget.controller.updateCompanyGlossary(
                    glossary.copyWith(
                      conventions: [...glossary.conventions, val],
                      updatedAt: DateTime.now().toUtc(),
                    ),
                  ),
                ),
                onRemove: (idx) {
                  final next = List<String>.from(glossary.conventions)
                    ..removeAt(idx);
                  widget.controller.updateCompanyGlossary(
                    glossary.copyWith(
                      conventions: next,
                      updatedAt: DateTime.now().toUtc(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _StringListCard(
                title:
                    'Ambiguïtés à surveiller (${glossary.ambiguousTerms.length})',
                items: glossary.ambiguousTerms,
                emptyText: 'Aucune ambiguïté recensée.',
                onAdd: () => _addStringItem(
                  context,
                  title: 'Nouvelle ambiguïté terminologique',
                  onSave: (val) => widget.controller.updateCompanyGlossary(
                    glossary.copyWith(
                      ambiguousTerms: [...glossary.ambiguousTerms, val],
                      updatedAt: DateTime.now().toUtc(),
                    ),
                  ),
                ),
                onRemove: (idx) {
                  final next = List<String>.from(glossary.ambiguousTerms)
                    ..removeAt(idx);
                  widget.controller.updateCompanyGlossary(
                    glossary.copyWith(
                      ambiguousTerms: next,
                      updatedAt: DateTime.now().toUtc(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _syncToActiveProject(
    BuildContext context,
    CompanyGlossary glossary,
  ) async {
    final project = widget.controller.project;
    if (project == null) return;
    final selectedIds = <String>{
      for (final t in glossary.terms)
        if (t.status == CompanyGlossaryStatus.approved) t.id,
    };
    if (selectedIds.isEmpty) {
      for (final t in glossary.terms) {
        if (t.status != CompanyGlossaryStatus.deprecated) {
          selectedIds.add(t.id);
        }
      }
    }
    var overwriteExisting = false;
    var includeConventions = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Importer vers « ${project.name} »'),
          content: SizedBox(
            width: 500,
            height: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sélectionnez les termes d’entreprise à copier dans le lexique du projet actif :',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final t in glossary.terms)
                        CheckboxListTile(
                          dense: true,
                          value: selectedIds.contains(t.id),
                          title: Text('${t.term} (${t.status.label})'),
                          subtitle: t.definition.isNotEmpty
                              ? Text(
                                  t.definition,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selectedIds.add(t.id);
                              } else {
                                selectedIds.remove(t.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(height: 12),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: overwriteExisting,
                  title: const Text(
                    'Mettre à jour les termes déjà présents dans le projet',
                  ),
                  onChanged: (v) =>
                      setDialogState(() => overwriteExisting = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: includeConventions,
                  title: const Text('Copier aussi les conventions d’entreprise'),
                  onChanged: (v) =>
                      setDialogState(() => includeConventions = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: selectedIds.isEmpty && !includeConventions
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('Importer (${selectedIds.length})'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final res = await widget.controller.importCompanyGlossaryToProject(
      termIds: selectedIds.toList(),
      overwriteExisting: overwriteExisting,
      includeConventions: includeConventions,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Projet mis à jour : +${res.added} terme(s), ${res.updated} mis à jour.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openImportExportDialog(
    BuildContext context,
    CompanyGlossary glossary,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _GlossaryImportExportDialog(
        controller: widget.controller,
        glossary: glossary,
        pickAttachments: widget.pickAttachments,
      ),
    );
  }

  Future<void> _addStringItem(
    BuildContext context, {
    required String title,
    required ValueChanged<String> onSave,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _AddStringItemDialog(title: title),
    );
    if (result != null && result.isNotEmpty) {
      onSave(result);
    }
  }

  Future<void> _editTermDialog(
    BuildContext context, {
    CompanyGlossaryTerm? existing,
  }) async {
    final item = await showDialog<CompanyGlossaryTerm>(
      context: context,
      builder: (_) => _EditGlossaryTermDialog(existing: existing),
    );
    if (item != null) {
      await widget.controller.upsertCompanyGlossaryTerm(item);
    }
  }
}

class _AddStringItemDialog extends StatefulWidget {
  const _AddStringItemDialog({required this.title});

  final String title;

  @override
  State<_AddStringItemDialog> createState() => _AddStringItemDialogState();
}

class _AddStringItemDialogState extends State<_AddStringItemDialog> {
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _textCtrl,
      autofocus: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _textCtrl.text.trim()),
        child: const Text('Ajouter'),
      ),
    ],
  );
}

class _EditGlossaryTermDialog extends StatefulWidget {
  const _EditGlossaryTermDialog({this.existing});

  final CompanyGlossaryTerm? existing;

  @override
  State<_EditGlossaryTermDialog> createState() =>
      _EditGlossaryTermDialogState();
}

class _EditGlossaryTermDialogState extends State<_EditGlossaryTermDialog> {
  late final TextEditingController _termCtrl;
  late final TextEditingController _domainCtrl;
  late final TextEditingController _ownerCtrl;
  late final TextEditingController _techCtrl;
  late final TextEditingController _defCtrl;
  late final TextEditingController _synCtrl;
  late final TextEditingController _forbiddenCtrl;
  late final TextEditingController _exCtrl;
  late CompanyGlossaryStatus _status;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _termCtrl = TextEditingController(text: existing?.term ?? '');
    _domainCtrl = TextEditingController(text: existing?.domain ?? '');
    _ownerCtrl = TextEditingController(text: existing?.owner ?? '');
    _techCtrl = TextEditingController(
      text: existing?.technicalNameHint ?? '',
    );
    _defCtrl = TextEditingController(text: existing?.definition ?? '');
    _synCtrl = TextEditingController(
      text: existing?.synonyms.join(', ') ?? '',
    );
    _forbiddenCtrl = TextEditingController(
      text: existing?.forbiddenTerms.join(', ') ?? '',
    );
    _exCtrl = TextEditingController(
      text: existing?.examples.join('\n') ?? '',
    );
    _status = existing?.status ?? CompanyGlossaryStatus.approved;
  }

  @override
  void dispose() {
    _termCtrl.dispose();
    _domainCtrl.dispose();
    _ownerCtrl.dispose();
    _techCtrl.dispose();
    _defCtrl.dispose();
    _synCtrl.dispose();
    _forbiddenCtrl.dispose();
    _exCtrl.dispose();
    super.dispose();
  }

  List<String> _splitCommaList(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(
        existing == null
            ? 'Nouveau terme d’entreprise'
            : 'Modifier « ${existing.term} »',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('company-glossary-field-term'),
                      controller: _termCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Terme canonique *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<CompanyGlossaryStatus>(
                      key: const ValueKey('company-glossary-field-status'),
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Statut',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in CompanyGlossaryStatus.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _status = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('company-glossary-field-domain'),
                      controller: _domainCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Domaine métier',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('company-glossary-field-owner'),
                      controller: _ownerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Référent / Propriétaire',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('company-glossary-field-tech'),
                controller: _techCtrl,
                decoration: const InputDecoration(
                  labelText:
                      'Indice de nommage technique (ex. DeliveryNote)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('company-glossary-field-definition'),
                controller: _defCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Définition métier',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('company-glossary-field-synonyms'),
                controller: _synCtrl,
                decoration: const InputDecoration(
                  labelText: 'Synonymes tolérés (séparés par virgule)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('company-glossary-field-forbidden'),
                controller: _forbiddenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Termes à proscrire (séparés par virgule)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('company-glossary-field-examples'),
                controller: _exCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Exemples (un par ligne)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (existing != null &&
                  (existing.createdAt != null ||
                      existing.updatedAt != null)) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      if (existing.createdAt != null)
                        Text(
                          'Ajouté le ${_formatGlossaryDateTime(existing.createdAt!)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (existing.updatedAt != null)
                        Text(
                          'Modifié le ${_formatGlossaryDateTime(existing.updatedAt!)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('company-glossary-save-term-btn'),
          onPressed: () {
            final termText = _termCtrl.text.trim();
            if (termText.isEmpty) {
              Navigator.pop(context);
              return;
            }
            final now = DateTime.now().toUtc();
            Navigator.pop(
              context,
              CompanyGlossaryTerm(
                id: existing?.id ?? 'cg_${shortid.generate()}',
                term: termText,
                domain: _domainCtrl.text.trim(),
                owner: _ownerCtrl.text.trim(),
                technicalNameHint: _techCtrl.text.trim(),
                definition: _defCtrl.text.trim(),
                synonyms: _splitCommaList(_synCtrl.text),
                forbiddenTerms: _splitCommaList(_forbiddenCtrl.text),
                examples: _exCtrl.text
                    .split(RegExp(r'[\r\n]+'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
                status: _status,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
              ),
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _CompanyGlossaryTermCard extends StatelessWidget {
  const _CompanyGlossaryTermCard({
    required this.term,
    required this.onEdit,
    required this.onDelete,
  });

  final CompanyGlossaryTerm term;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final (statusBg, statusFg) = switch (term.status) {
      CompanyGlossaryStatus.approved => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      CompanyGlossaryStatus.draft => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      CompanyGlossaryStatus.deprecated => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        term.term,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration:
                              term.status == CompanyGlossaryStatus.deprecated
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          term.status.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusFg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (term.domain.isNotEmpty)
                        Chip(
                          label: Text(term.domain),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (term.technicalNameHint.isNotEmpty)
                        Chip(
                          avatar: const Icon(Icons.code_rounded, size: 14),
                          label: Text(term.technicalNameHint),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (term.owner.isNotEmpty)
                        Chip(
                          avatar: const Icon(
                            Icons.person_outline_rounded,
                            size: 14,
                          ),
                          label: Text(term.owner),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('company-glossary-edit-${term.id}'),
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  key: ValueKey('company-glossary-delete-${term.id}'),
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (term.definition.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(term.definition),
            ],
            if (term.synonyms.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Synonymes tolérés :',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  for (final s in term.synonyms)
                    Chip(label: Text(s), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
            if (term.forbiddenTerms.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'À proscrire :',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final f in term.forbiddenTerms)
                    Chip(
                      backgroundColor: colors.errorContainer.withValues(
                        alpha: 0.55,
                      ),
                      label: Text(
                        f,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (term.examples.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final ex in term.examples)
                Text(
                  '• $ex',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
            if (term.createdAt != null || term.updatedAt != null) ...[
              const SizedBox(height: 8),
              Wrap(
                key: ValueKey('company-glossary-dates-${term.id}'),
                spacing: 14,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (term.createdAt != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          size: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Ajouté le ${_formatGlossaryDateTime(term.createdAt!)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  if (term.updatedAt != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.update_rounded,
                          size: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Modifié le ${_formatGlossaryDateTime(term.updatedAt!)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
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

String _formatGlossaryDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  String pad2(int n) => n.toString().padLeft(2, '0');
  return '${pad2(local.day)}/${pad2(local.month)}/${local.year} '
      '${pad2(local.hour)}:${pad2(local.minute)}';
}

class _StringListCard extends StatelessWidget {
  const _StringListCard({
    required this.title,
    required this.items,
    required this.emptyText,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<String> items;
  final String emptyText;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: onAdd,
                ),
              ],
            ),
            if (items.isEmpty)
              Text(
                emptyText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              for (var i = 0; i < items.length; i++)
                Row(
                  children: [
                    const Text('• '),
                    Expanded(child: Text(items[i])),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => onRemove(i),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _GlossaryAiChatPane extends StatefulWidget {
  const _GlossaryAiChatPane({
    required this.controller,
    required this.onCollapse,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
  });

  final SpecForgeController controller;
  final VoidCallback onCollapse;
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<_GlossaryAiChatPane> createState() => _GlossaryAiChatPaneState();
}

class _GlossaryAiChatPaneState extends State<_GlossaryAiChatPane> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<VibeChatAttachment> _pendingAttachments = [];
  String? _attachmentError;
  int _lastCount = 0;

  static const List<String> _quickPrompts = [
    'Détecte les doublons, chevauchements et termes ambigus du glossaire.',
    'Suggère des noms techniques (technicalNameHint) pour chaque terme.',
    'Propose les conventions et termes à proscrire manquants.',
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _appendAttachments(Iterable<VibeChatAttachment> incoming) {
    final used = {for (final a in _pendingAttachments) a.name};
    for (final a in incoming) {
      var name = a.name;
      if (used.contains(name)) {
        final dot = name.lastIndexOf('.');
        final stem = dot > 0 ? name.substring(0, dot) : name;
        final ext = dot > 0 ? name.substring(dot) : '';
        var suffix = 2;
        while (used.contains('$stem-$suffix$ext')) {
          suffix++;
        }
        name = '$stem-$suffix$ext';
      }
      used.add(name);
      _pendingAttachments.add(name == a.name ? a : a.withName(name));
    }
  }

  Future<void> _attachFromPicker() async {
    if (widget.controller.isSending) return;
    setState(() => _attachmentError = null);
    try {
      final picker = widget.pickAttachments ?? VibeChatAttachment.pickFiles;
      final picked = await picker();
      if (!mounted || picked.isEmpty) return;
      setState(() => _appendAttachments(picked));
    } catch (e) {
      if (mounted) setState(() => _attachmentError = 'Import impossible : $e');
    }
  }

  Future<void> _attachFromClipboard() async {
    if (widget.controller.isSending) return;
    setState(() => _attachmentError = null);
    try {
      final paster =
          widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
      final pasted = await paster();
      if (!mounted) return;
      if (pasted.isEmpty) {
        setState(
          () => _attachmentError =
              'Aucune image, fichier ou texte trouvé dans le presse-papiers.',
        );
        return;
      }
      setState(() => _appendAttachments(pasted));
    } catch (e) {
      if (mounted) {
        setState(() => _attachmentError = 'Collage impossible : $e');
      }
    }
  }

  Future<void> _attachMediaFromShortcut() async {
    if (widget.controller.isSending) return;
    try {
      final paster =
          widget.pasteClipboardMedia ??
          (widget.hasClipboardMedia != null ? widget.pasteAttachments : null) ??
          VibeChatAttachment.fromClipboardImagesOrFiles;
      final pasted = await paster();
      if (!mounted || pasted.isEmpty) return;
      setState(() => _appendAttachments(pasted));
    } catch (_) {}
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.controller.isSending || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !keyboard.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    final isCtrlOrMetaV =
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    if (!isCtrlOrMetaV) return KeyEventResult.ignored;
    final hasMedia =
        (widget.hasClipboardMedia ??
            VibeChatAttachment.hasClipboardImageOrFiles)();
    if (!hasMedia) return KeyEventResult.ignored;
    unawaited(_attachMediaFromShortcut());
    return KeyEventResult.handled;
  }

  void _send([String? preset]) {
    if (widget.controller.isSending) return;
    final text = (preset ?? _inputCtrl.text).trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    if (preset == null) {
      _inputCtrl.clear();
    }
    setState(() {
      _pendingAttachments.clear();
      _attachmentError = null;
    });
    widget.controller.sendGlossaryMessage(text, attachments: attachments);
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.glossaryChatMessages;
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToBottom();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isSendingThis = widget.controller.isSendingGlossary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Assistant Glossaire IA',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (messages.isNotEmpty)
                IconButton(
                  tooltip: 'Effacer la conversation',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  onPressed: widget.controller.isSending
                      ? null
                      : widget.controller.clearGlossaryChat,
                ),
              IconButton(
                key: const ValueKey('company-glossary-chat-collapse'),
                tooltip: 'Masquer le chat IA',
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                onPressed: widget.onCollapse,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: messages.isEmpty && !isSendingThis
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Décrivez un domaine métier, collez un document ou joignez un fichier (spec, PDF, CSV) pour extraire et harmoniser le vocabulaire.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final prompt in _quickPrompts)
                            ActionChip(
                              label: Text(prompt),
                              onPressed: widget.controller.isSending
                                  ? null
                                  : () => _send(prompt),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length + (isSendingThis ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return Card(
                        elevation: 0,
                        color: colors.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      widget.controller.streamingStatus
                                              .isNotEmpty
                                          ? widget.controller.streamingStatus
                                          : 'Analyse en cours…',
                                      style: theme.textTheme.labelMedium,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        widget.controller.stopAiGeneration,
                                    child: const Text('Arrêter'),
                                  ),
                                ],
                              ),
                              if ((widget.controller.streamingMessage ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(widget.controller.streamingMessage!),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                    final msg = messages[index];
                    return _GlossaryMessageBubble(
                      message: msg,
                      sending: widget.controller.isSending,
                      onSubmitAskUser: (answers) => widget.controller
                          .submitGlossaryAskUserAnswers(msg.id, answers),
                      onSkipAskUser: () =>
                          widget.controller.skipGlossaryAskUser(msg.id),
                      onRetry: widget.controller.retryLastGlossaryTurn,
                    );
                  },
                ),
        ),
        if (_attachmentError != null)
          Container(
            color: colors.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              _attachmentError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onErrorContainer,
              ),
            ),
          ),
        if (_pendingAttachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _pendingAttachments.length; i++)
                  InputChip(
                    label: Text(_pendingAttachments[i].name),
                    onDeleted: widget.controller.isSending
                        ? null
                        : () => setState(() => _pendingAttachments.removeAt(i)),
                  ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Joindre un fichier',
                icon: const Icon(Icons.attach_file_rounded, size: 18),
                onPressed: widget.controller.isSending
                    ? null
                    : _attachFromPicker,
              ),
              IconButton(
                tooltip: 'Coller depuis le presse-papiers',
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                onPressed: widget.controller.isSending
                    ? null
                    : _attachFromClipboard,
              ),
              Expanded(
                child: Focus(
                  onKeyEvent: _handleKeyEvent,
                  child: TextField(
                    key: const ValueKey('company-glossary-chat-input'),
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !widget.controller.isSending,
                    decoration: const InputDecoration(
                      hintText:
                          'Demander à extraire ou vérifier des termes…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const ValueKey('company-glossary-chat-send'),
                onPressed: widget.controller.isSending ? null : () => _send(),
                icon: const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlossaryMessageBubble extends StatelessWidget {
  const _GlossaryMessageBubble({
    required this.message,
    required this.sending,
    required this.onSubmitAskUser,
    required this.onSkipAskUser,
    required this.onRetry,
  });

  final SpecChatMessage message;
  final bool sending;
  final ValueChanged<Map<String, Object?>> onSubmitAskUser;
  final VoidCallback onSkipAskUser;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final align = message.isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: message.isUser
                  ? colors.primaryContainer
                  : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: message.isUser
                  ? null
                  : Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: message.isUser
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
                if (message.appliedPatchSummary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Mis à jour : ${message.appliedPatchSummary}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (message.failedResponse != null) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: sending ? null : onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Réessayer'),
                  ),
                ],
              ],
            ),
          ),
          if (!message.isUser &&
              message.askUser != null &&
              message.askUserAnswers == null &&
              !message.askUserDismissed) ...[
            const SizedBox(height: 8),
            VibeAskUserCard(
              request: message.askUser!,
              sending: sending,
              onSubmit: onSubmitAskUser,
              onSkip: onSkipAskUser,
            ),
          ],
        ],
      ),
    );
  }
}

class _GlossaryImportExportDialog extends StatefulWidget {
  const _GlossaryImportExportDialog({
    required this.controller,
    required this.glossary,
    this.pickAttachments,
  });

  final SpecForgeController controller;
  final CompanyGlossary glossary;
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  @override
  State<_GlossaryImportExportDialog> createState() =>
      _GlossaryImportExportDialogState();
}

class _GlossaryImportExportDialogState
    extends State<_GlossaryImportExportDialog> {
  String _exportFormat = 'json';
  late final TextEditingController _exportPathCtrl;
  final TextEditingController _importTextCtrl = TextEditingController();
  bool _replaceAll = false;
  CompanyGlossaryImportPreview? _preview;
  String? _importError;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _exportPathCtrl = TextEditingController(text: _defaultExportPath('json'));
  }

  @override
  void dispose() {
    _exportPathCtrl.dispose();
    _importTextCtrl.dispose();
    super.dispose();
  }

  String _defaultExportPath(String format) {
    final sep = Platform.pathSeparator;
    final base = '${widget.controller.glossaryStore.rootDirectory.path}$sep'
        'exports';
    return '$base${sep}company_glossary.$format';
  }

  String _currentExportContent() => switch (_exportFormat) {
    'md' => CompanyGlossaryCodec.toMarkdown(widget.glossary),
    'csv' => CompanyGlossaryCodec.toCsv(widget.glossary),
    _ => CompanyGlossaryCodec.toJsonString(widget.glossary),
  };

  void _recomputePreview() {
    final raw = _importTextCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _preview = null;
        _importError = null;
      });
      return;
    }
    try {
      final incoming = raw.startsWith('{') || raw.startsWith('[')
          ? CompanyGlossaryCodec.parseJson(raw)
          : CompanyGlossaryCodec.parseCsv(raw);
      final preview = CompanyGlossaryCodec.previewMerge(
        current: widget.glossary,
        incoming: incoming,
        replaceAll: _replaceAll,
      );
      setState(() {
        _preview = preview;
        _importError = null;
      });
    } catch (e) {
      setState(() {
        _preview = null;
        _importError = e.toString();
      });
    }
  }

  Future<void> _pickImportFile() async {
    try {
      final picker = widget.pickAttachments ?? VibeChatAttachment.pickFiles;
      final picked = await picker();
      if (!mounted || picked.isEmpty) return;
      final text = picked.first.textContent;
      if (text == null || text.trim().isEmpty) {
        setState(() {
          _importError =
              'Le fichier sélectionné ne contient pas de texte JSON ou CSV lisible.';
        });
        return;
      }
      _importTextCtrl.text = text;
      _recomputePreview();
    } catch (e) {
      if (mounted) {
        setState(() => _importError = 'Lecture du fichier impossible : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final exportContent = _currentExportContent();
    return AlertDialog(
      title: const Text('Importer / Exporter le glossaire d’entreprise'),
      content: SizedBox(
        width: 680,
        height: 470,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Exporter'),
                  Tab(text: 'Importer (JSON / CSV)'),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('JSON'),
                              selected: _exportFormat == 'json',
                              onSelected: (_) => setState(() {
                                _exportFormat = 'json';
                                _exportPathCtrl.text = _defaultExportPath(
                                  'json',
                                );
                              }),
                            ),
                            ChoiceChip(
                              label: const Text('Markdown (.md)'),
                              selected: _exportFormat == 'md',
                              onSelected: (_) => setState(() {
                                _exportFormat = 'md';
                                _exportPathCtrl.text = _defaultExportPath('md');
                              }),
                            ),
                            ChoiceChip(
                              label: const Text('CSV'),
                              selected: _exportFormat == 'csv',
                              onSelected: (_) => setState(() {
                                _exportFormat = 'csv';
                                _exportPathCtrl.text = _defaultExportPath(
                                  'csv',
                                );
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                exportContent,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _exportPathCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Chemin d’enregistrement',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: exportContent),
                                );
                                if (mounted) {
                                  setState(
                                    () => _statusMessage =
                                        'Contenu copié dans le presse-papiers.',
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copier'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () async {
                                final file = File(_exportPathCtrl.text.trim());
                                await file.parent.create(recursive: true);
                                await file.writeAsString(exportContent);
                                if (mounted) {
                                  setState(
                                    () => _statusMessage =
                                        'Fichier enregistré : ${file.path}',
                                  );
                                }
                              },
                              icon: const Icon(Icons.save_alt_rounded, size: 16),
                              label: const Text('Enregistrer'),
                            ),
                          ],
                        ),
                        if (_statusMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _statusMessage!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ],
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickImportFile,
                              icon: const Icon(
                                Icons.upload_file_rounded,
                                size: 16,
                              ),
                              label: const Text('Charger un fichier…'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _replaceAll,
                                title: const Text(
                                  'Remplacer tout le glossaire existant',
                                ),
                                onChanged: (v) {
                                  setState(() => _replaceAll = v ?? false);
                                  _recomputePreview();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey(
                              'company-glossary-import-text-input',
                            ),
                            controller: _importTextCtrl,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              hintText: 'Collez ici un contenu JSON ou CSV…',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _recomputePreview(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_importError != null)
                          Text(
                            _importError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          )
                        else if (_preview != null)
                          Text(
                            'Aperçu : +${_preview!.addedTerms.length} ajout(s), '
                            '${_preview!.updatedTerms.length} mise(s) à jour, '
                            '${_preview!.unchangedCount} inchangé(s).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            key: const ValueKey('company-glossary-apply-import'),
                            onPressed: _preview == null
                                ? null
                                : () async {
                                    await widget.controller
                                        .updateCompanyGlossary(
                                          _preview!.mergedGlossary,
                                        );
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Appliquer l’import'),
                          ),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
