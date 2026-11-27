/// Boîte de dialogue de promotion des objets métiers de la Spec vers les
/// domaines fonctionnels de l'espace Design ([PromoteBusinessObjectsDialog]).
library;

import 'package:material_ui/material_ui.dart';

import '../../models/business_object_spec.dart';
import '../../models/domain_catalog.dart';
import '../../models/domain_contracts.dart';
import '../../models/spec_forge_project.dart';
import '../../services/spec_design_merge_engine.dart';
import '../../services/spec_design_promoter.dart';
import '../../services/spec_forge_controller.dart';
import '../design/contract_entry_view.dart' show contractTypeColor;

final RegExp _kebabDomainCodePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// Modale permettant de sélectionner les objets métiers du projet courant et
/// d'affecter à chacun un domaine cible, un type DSL et une règle de conflit.
class PromoteBusinessObjectsDialog extends StatefulWidget {
  /// Crée la modale de promotion connectée au [controller].
  const PromoteBusinessObjectsDialog({
    required this.controller,
    super.key,
  });

  /// Contrôleur portant le projet courant et le catalogue de domaines.
  final SpecForgeController controller;

  /// Affiche la modale et retourne le [PromotionExecutionResult] en cas de succès.
  static Future<PromotionExecutionResult?> show(
    BuildContext context, {
    required SpecForgeController controller,
  }) => showDialog<PromotionExecutionResult>(
    context: context,
    builder: (_) => PromoteBusinessObjectsDialog(controller: controller),
  );

  @override
  State<PromoteBusinessObjectsDialog> createState() =>
      _PromoteBusinessObjectsDialogState();
}

class _RowDraft {
  _RowDraft({
    required this.checked,
    required this.domainId,
    required this.contractType,
  });

  bool checked;
  String? domainId;
  String contractType;
  PromotionConflictResolution conflictResolution =
      PromotionConflictResolution.smartMerge;
}

class _PromoteBusinessObjectsDialogState
    extends State<PromoteBusinessObjectsDialog> {
  final TextEditingController _filterCtrl = TextEditingController();
  late final Map<String, _RowDraft> _drafts;
  String? _batchDomainId;
  String _filterQuery = '';
  bool _autoBumpVersion = false;
  bool _submitting = false;
  String? _errorMessage;

  SpecForgeProject? get _project => widget.controller.project;
  List<FunctionalDomain> get _domains =>
      widget.controller.domainCatalog.domains;

  @override
  void initState() {
    super.initState();
    final project = _project;
    final domains = _domains;
    _batchDomainId = domains.length == 1 ? domains.first.id : null;
    _drafts = <String, _RowDraft>{};
    if (project != null) {
      for (final obj in project.businessObjects) {
        final existingDomain = domains
            .where(
              (d) =>
                  SpecDesignPromoter.findEntryForSpecObject(
                    d.contracts,
                    obj,
                    projectId: project.id,
                  ) !=
                  null,
            )
            .firstOrNull;
        final existingEntry = existingDomain == null
            ? null
            : SpecDesignPromoter.findEntryForSpecObject(
                existingDomain.contracts,
                obj,
                projectId: project.id,
              );
        _drafts[obj.id] = _RowDraft(
          checked: false,
          domainId: existingDomain?.id,
          contractType:
              existingEntry?.type ??
              SpecDesignPromoter.defaultContractTypeFor(obj),
        );
      }
    }
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  List<BusinessObjectSpec> _filteredObjects(SpecForgeProject project) {
    final q = _filterQuery.trim().toLowerCase();
    if (q.isEmpty) return project.businessObjects;
    return project.businessObjects
        .where(
          (obj) =>
              obj.name.toLowerCase().contains(q) ||
              obj.technicalName.toLowerCase().contains(q) ||
              obj.description.toLowerCase().contains(q),
        )
        .toList();
  }

  Map<String, String?> get _plannedDomainByObjectId => <String, String?>{
    for (final entry in _drafts.entries)
      entry.key: entry.value.checked ? entry.value.domainId : null,
  };

  int get _checkedCount => _drafts.values.where((d) => d.checked).length;

  bool get _hasCheckedWithoutDomain => _drafts.values.any(
    (d) => d.checked && (d.domainId == null || d.domainId!.isEmpty),
  );

  List<ObjectPromotionChoice> get _selectedChoices => <ObjectPromotionChoice>[
    for (final entry in _drafts.entries)
      if (entry.value.checked &&
          entry.value.domainId != null &&
          entry.value.domainId!.isNotEmpty)
        ObjectPromotionChoice(
          objectId: entry.key,
          domainId: entry.value.domainId,
          contractType: entry.value.contractType,
          conflictResolution: entry.value.conflictResolution,
          autoBumpVersion: _autoBumpVersion,
        ),
  ];

  Map<String, ObjectPromotionPreview> _computePreviews(
    SpecForgeProject project,
  ) {
    final catalog = widget.controller.domainCatalog;
    final prefs = widget.controller.modelPreferences;
    final byObjectId = <String, ObjectPromotionPreview>{};
    final checkedChoices = _selectedChoices;
    if (checkedChoices.isNotEmpty) {
      try {
        final checkedPreviews = SpecDesignPromoter.previewPromotion(
          project: project,
          catalog: catalog,
          choices: checkedChoices,
          modelPreferences: prefs,
        );
        for (final p in checkedPreviews) {
          byObjectId[p.specObject.id] = p;
        }
      } on Object {
        // Ignore un état intermédiaire invalide le temps de l'édition.
      }
    }
    for (final entry in _drafts.entries) {
      final draft = entry.value;
      if (draft.checked ||
          draft.domainId == null ||
          draft.domainId!.isEmpty ||
          byObjectId.containsKey(entry.key)) {
        continue;
      }
      final probeChoice = ObjectPromotionChoice(
        objectId: entry.key,
        domainId: draft.domainId,
        contractType: draft.contractType,
        conflictResolution: draft.conflictResolution,
        autoBumpVersion: _autoBumpVersion,
      );
      try {
        final probePreviews = SpecDesignPromoter.previewPromotion(
          project: project,
          catalog: catalog,
          choices: <ObjectPromotionChoice>[...checkedChoices, probeChoice],
          modelPreferences: prefs,
        );
        final match = probePreviews
            .where((p) => p.specObject.id == entry.key)
            .firstOrNull;
        if (match != null) {
          byObjectId[entry.key] = match;
        }
      } on Object {
        // Ignore un état intermédiaire invalide.
      }
    }
    return byObjectId;
  }

  void _selectAllVisible(List<BusinessObjectSpec> visible) {
    setState(() {
      final fallbackDomainId =
          _batchDomainId ?? (_domains.length == 1 ? _domains.first.id : null);
      for (final obj in visible) {
        final draft = _drafts[obj.id];
        if (draft == null) continue;
        draft.checked = true;
        draft.domainId ??= fallbackDomainId;
      }
      _errorMessage = null;
    });
  }

  void _clearAll() {
    setState(() {
      for (final draft in _drafts.values) {
        draft.checked = false;
      }
      _errorMessage = null;
    });
  }

  void _applyBatchDomain(List<BusinessObjectSpec> visible) {
    final domainId = _batchDomainId;
    if (domainId == null) return;
    setState(() {
      final anyChecked = visible.any((o) => _drafts[o.id]?.checked == true);
      for (final obj in visible) {
        final draft = _drafts[obj.id];
        if (draft == null) continue;
        if (!anyChecked || draft.checked) {
          draft.checked = true;
          draft.domainId = domainId;
        }
      }
      _errorMessage = null;
    });
  }

  Future<void> _openCreateDomainDialog() async {
    final created = await _showQuickCreateDomainDialog(
      context,
      controller: widget.controller,
    );
    if (created == null || !mounted) return;
    setState(() {
      _batchDomainId = created.id;
      for (final draft in _drafts.values) {
        if (draft.checked && draft.domainId == null) {
          draft.domainId = created.id;
        }
      }
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_hasCheckedWithoutDomain) {
      setState(() {
        _errorMessage =
            'Choisissez un domaine cible pour chaque objet coché (ou décochez-le).';
      });
      return;
    }
    final choices = _selectedChoices;
    if (choices.isEmpty) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.controller.promoteBusinessObjectsToDesign(
        choices,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = switch (error) {
          FormatException(:final message) => message,
          StateError(:final message) => message,
          _ => '$error',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final project = _project;
        if (project == null) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final domains = _domains;
        final domainIds = {for (final d in domains) d.id};
        if (_batchDomainId != null && !domainIds.contains(_batchDomainId)) {
          _batchDomainId = null;
        }
        for (final draft in _drafts.values) {
          if (draft.domainId != null && !domainIds.contains(draft.domainId)) {
            draft.domainId = null;
          }
        }

        final visible = _filteredObjects(project);
        final plannedDomains = _plannedDomainByObjectId;
        final previewsByObjectId = _computePreviews(project);
        final readyChoices = _selectedChoices;
        final canSubmit =
            !_submitting &&
            readyChoices.isNotEmpty &&
            !_hasCheckedWithoutDomain;

        return AlertDialog(
          key: const ValueKey('promote-business-objects-dialog'),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          title: Row(
            children: [
              Icon(Icons.rocket_launch_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Promouvoir des objets métier vers Design'),
                    Text(
                      '$_checkedCount / ${project.businessObjects.length} objet(s) sélectionné(s) · '
                      'Choisissez le domaine cible de chaque objet',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('promote-dialog-new-domain-btn'),
                onPressed: _submitting ? null : _openCreateDomainDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Nouveau domaine'),
              ),
            ],
          ),
          content: SizedBox(
            width: 880,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (domains.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: colors.onSecondaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aucun domaine fonctionnel n’existe encore dans ce workspace. '
                            'Cliquez sur « Nouveau domaine » pour en créer un avant la promotion.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildToolbar(theme, colors, domains, visible),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            'Aucun objet métier ne correspond au filtre.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _buildObjectRow(
                            theme: theme,
                            colors: colors,
                            project: project,
                            domains: domains,
                            object: visible[index],
                            plannedDomains: plannedDomains,
                            preview: previewsByObjectId[visible[index].id],
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('promote-dialog-cancel-btn'),
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              key: const ValueKey('promote-dialog-submit-btn'),
              onPressed: canSubmit ? _submit : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish_rounded, size: 17),
              label: Text(
                readyChoices.isEmpty
                    ? 'Promouvoir'
                    : 'Promouvoir (${readyChoices.length})',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(
    ThemeData theme,
    ColorScheme colors,
    List<FunctionalDomain> domains,
    List<BusinessObjectSpec> visible,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const ValueKey('promote-dialog-filter-field'),
                controller: _filterCtrl,
                onChanged: (value) => setState(() => _filterQuery = value),
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filtrer un objet métier…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  suffixIcon: _filterQuery.isNotEmpty
                      ? IconButton(
                          iconSize: 15,
                          onPressed: () {
                            _filterCtrl.clear();
                            setState(() => _filterQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('promote-dialog-select-all-btn'),
              onPressed: visible.isEmpty
                  ? null
                  : () => _selectAllVisible(visible),
              child: const Text('Tout cocher'),
            ),
            TextButton(
              key: const ValueKey('promote-dialog-clear-all-btn'),
              onPressed: _checkedCount == 0 ? null : _clearAll,
              child: const Text('Tout décocher'),
            ),
            FilterChip(
              key: const ValueKey('promote-dialog-auto-bump-toggle'),
              visualDensity: VisualDensity.compact,
              selected: _autoBumpVersion,
              label: const Text('Incrémenter SemVer auto'),
              tooltip:
                  'Incrémente automatiquement la version sémantique (Patch/Mineur/Majeur) des contrats mis à jour',
              onSelected: _submitting
                  ? null
                  : (value) => setState(() => _autoBumpVersion = value),
            ),
          ],
        ),
        if (domains.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Affectation groupée',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      key: const ValueKey(
                        'promote-dialog-batch-domain-dropdown',
                      ),
                      value: _batchDomainId,
                      isDense: true,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Choisir un domaine…'),
                        ),
                        for (final domain in domains)
                          DropdownMenuItem<String?>(
                            value: domain.id,
                            child: Text(
                              domain.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _batchDomainId = value),
                    ),
                  ),
                ),
              ),
              FilledButton.tonal(
                key: const ValueKey('promote-dialog-batch-apply-btn'),
                onPressed: _batchDomainId == null || visible.isEmpty
                    ? null
                    : () => _applyBatchDomain(visible),
                child: Text(
                  _checkedCount > 0
                      ? 'Appliquer aux cochés'
                      : 'Appliquer à tous',
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildObjectRow({
    required ThemeData theme,
    required ColorScheme colors,
    required SpecForgeProject project,
    required List<FunctionalDomain> domains,
    required BusinessObjectSpec object,
    required Map<String, String?> plannedDomains,
    required ObjectPromotionPreview? preview,
  }) {
    final draft = _drafts[object.id]!;
    final selectedDomain = domains
        .where((d) => d.id == draft.domainId)
        .firstOrNull;
    final existingEntry = selectedDomain == null
        ? null
        : SpecDesignPromoter.findEntryForSpecObject(
            selectedDomain.contracts,
            object,
            projectId: project.id,
          );
    final hasConflict = draft.checked && existingEntry != null;
    final missingDomain = draft.checked && selectedDomain == null;
    final externalRefCount =
        (draft.checked &&
            selectedDomain != null &&
            (!hasConflict ||
                draft.conflictResolution !=
                    PromotionConflictResolution.skipExisting))
        ? SpecDesignPromoter.countExternalReferencesForObject(
            project: project,
            catalog: widget.controller.domainCatalog,
            object: object,
            targetDomainId: selectedDomain.id,
            plannedDomainByObjectId: plannedDomains,
          )
        : 0;

    final borderColor = missingDomain
        ? colors.error
        : (draft.checked ? colors.primary.withValues(alpha: 0.6) : colors.outlineVariant);

    final statusPills = <Widget>[];
    if (selectedDomain != null && preview != null) {
      final isDark = colors.brightness == Brightness.dark;
      if (preview.isNewEntry) {
        statusPills.add(
          _PromoteStatusPill(
            key: ValueKey('promote-status-${object.id}'),
            label: 'Nouveau contrat',
            icon: Icons.fiber_new_rounded,
            backgroundColor: Colors.blue.withValues(alpha: isDark ? 0.22 : 0.12),
            foregroundColor: isDark ? Colors.lightBlue.shade200 : Colors.blue.shade800,
            borderColor: Colors.blue.withValues(alpha: isDark ? 0.48 : 0.34),
          ),
        );
      } else {
        final mergeResult = preview.mergeResult;
        if (preview.willSkip || mergeResult == null) {
          statusPills.add(
            _PromoteStatusPill(
              key: ValueKey('promote-status-${object.id}'),
              label: 'Ignoré',
              icon: Icons.block_rounded,
              backgroundColor: colors.surfaceContainerHighest,
              foregroundColor: colors.onSurfaceVariant,
              borderColor: colors.outlineVariant,
            ),
          );
        } else if (!mergeResult.hasChanges) {
          statusPills.add(
            _PromoteStatusPill(
              key: ValueKey('promote-status-${object.id}'),
              label: 'À jour avec Design',
              icon: Icons.check_circle_outline_rounded,
              backgroundColor: Colors.green.withValues(
                alpha: isDark ? 0.20 : 0.11,
              ),
              foregroundColor: isDark
                  ? Colors.green.shade200
                  : Colors.green.shade800,
              borderColor: Colors.green.withValues(alpha: isDark ? 0.46 : 0.32),
            ),
          );
          if (mergeResult.preservedValueObjectIds.isNotEmpty &&
              draft.conflictResolution ==
                  PromotionConflictResolution.smartMerge) {
            statusPills.add(
              _PromoteStatusPill(
                key: ValueKey('promote-vo-preserved-${object.id}'),
                label:
                    '${mergeResult.preservedValueObjectIds.length} VO préservé(s)',
                icon: Icons.diamond_outlined,
                backgroundColor: Colors.teal.withValues(
                  alpha: isDark ? 0.22 : 0.12,
                ),
                foregroundColor: isDark
                    ? Colors.teal.shade200
                    : Colors.teal.shade800,
                borderColor: Colors.teal.withValues(
                  alpha: isDark ? 0.50 : 0.35,
                ),
              ),
            );
          }
        } else {
          statusPills.add(
            _PromoteStatusPill(
              key: ValueKey('promote-status-${object.id}'),
              label:
                  'Δ +${mergeResult.addedCount} / ~${mergeResult.updatedCount} / -${mergeResult.removedCount}',
              icon: Icons.merge_type_rounded,
              backgroundColor: Colors.orange.withValues(
                alpha: isDark ? 0.22 : 0.13,
              ),
              foregroundColor: isDark
                  ? Colors.amber.shade200
                  : Colors.orange.shade900,
              borderColor: Colors.orange.withValues(
                alpha: isDark ? 0.50 : 0.36,
              ),
            ),
          );
          if (mergeResult.preservedValueObjectIds.isNotEmpty &&
              draft.conflictResolution ==
                  PromotionConflictResolution.smartMerge) {
            statusPills.add(
              _PromoteStatusPill(
                key: ValueKey('promote-vo-preserved-${object.id}'),
                label:
                    '${mergeResult.preservedValueObjectIds.length} VO préservé(s)',
                icon: Icons.diamond_outlined,
                backgroundColor: Colors.teal.withValues(
                  alpha: isDark ? 0.22 : 0.12,
                ),
                foregroundColor: isDark
                    ? Colors.teal.shade200
                    : Colors.teal.shade800,
                borderColor: Colors.teal.withValues(
                  alpha: isDark ? 0.50 : 0.35,
                ),
              ),
            );
          }
          if (mergeResult.conflictCount > 0) {
            statusPills.add(
              _PromoteStatusPill(
                key: ValueKey('promote-conflicts-pill-${object.id}'),
                label: '${mergeResult.conflictCount} conflit(s)',
                icon: Icons.warning_amber_rounded,
                backgroundColor: Colors.amber.withValues(
                  alpha: isDark ? 0.24 : 0.16,
                ),
                foregroundColor: isDark
                    ? Colors.amber.shade200
                    : Colors.amber.shade900,
                borderColor: Colors.amber.withValues(
                  alpha: isDark ? 0.55 : 0.42,
                ),
              ),
            );
          }
        }
        if (_autoBumpVersion &&
            !preview.willSkip &&
            preview.suggestedVersion != preview.currentVersion) {
          statusPills.add(
            _PromoteStatusPill(
              key: ValueKey('promote-semver-pill-${object.id}'),
              label:
                  'v${preview.currentVersion} → v${preview.suggestedVersion}',
              icon: Icons.auto_fix_high_rounded,
              backgroundColor: colors.secondaryContainer,
              foregroundColor: colors.onSecondaryContainer,
              borderColor: colors.secondary.withValues(alpha: 0.35),
            ),
          );
        }
      }
    }

    final canShowMergePreview =
        selectedDomain != null &&
        preview != null &&
        !preview.isNewEntry &&
        preview.mergeResult != null;

    return DecoratedBox(
      key: ValueKey('promote-row-${object.id}'),
      decoration: BoxDecoration(
        color: draft.checked
            ? colors.primaryContainer.withValues(alpha: 0.14)
            : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  key: ValueKey('promote-check-${object.id}'),
                  value: draft.checked,
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() {
                            final nextChecked = value ?? false;
                            draft.checked = nextChecked;
                            if (nextChecked && draft.domainId == null) {
                              draft.domainId =
                                  _batchDomainId ??
                                  (domains.length == 1
                                      ? domains.first.id
                                      : null);
                            }
                            _errorMessage = null;
                          });
                        },
                ),
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
                            object.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            object.technicalName,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              object.aggregateRoot ? 'Agrégat' : 'Sous-objet',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                          Text(
                            '${object.totalAttributeCount} attr.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          ...statusPills,
                          if (canShowMergePreview)
                            TextButton.icon(
                              key: ValueKey('promote-preview-${object.id}'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _showMergePreviewDialog(
                                context,
                                preview: preview,
                              ),
                              icon: const Icon(
                                Icons.compare_arrows_rounded,
                                size: 15,
                              ),
                              label: const Text('Aperçu du merge'),
                            ),
                        ],
                      ),
                      if (object.description.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            object.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Domaine cible',
                      errorText: missingDomain ? 'Domaine requis' : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        key: ValueKey('promote-domain-${object.id}'),
                        value: draft.domainId,
                        isDense: true,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('— Aucun domaine —'),
                          ),
                          for (final domain in domains)
                            DropdownMenuItem<String?>(
                              value: domain.id,
                              child: Text(
                                domain.isActive
                                    ? domain.name
                                    : '${domain.name} (inactif)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (nextDomainId) {
                                setState(() {
                                  draft.domainId = nextDomainId;
                                  draft.checked = nextDomainId != null;
                                  _errorMessage = null;
                                });
                              },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 165,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Type DSL',
                      border: const OutlineInputBorder(),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: contractTypeColor(draft.contractType),
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 8, height: 8),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: ValueKey('promote-type-${object.id}'),
                        value: draft.contractType,
                        isDense: true,
                        isExpanded: true,
                        items: [
                          for (final type in DomainContracts.types)
                            DropdownMenuItem<String>(
                              value: type,
                              child: Text(
                                type,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => draft.contractType = value);
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (hasConflict || externalRefCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 8, 0, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasConflict &&
                        selectedDomain != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: colors.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Déjà présent dans « ${selectedDomain.name} » (${existingEntry.path})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.tertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SegmentedButton<PromotionConflictResolution>(
                        key: ValueKey('promote-conflict-${object.id}'),
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: [
                          for (final option
                              in PromotionConflictResolution.values)
                            ButtonSegment<PromotionConflictResolution>(
                              value: option,
                              label: Text(option.label),
                            ),
                        ],
                        selected: <PromotionConflictResolution>{
                          draft.conflictResolution,
                        },
                        onSelectionChanged: _submitting
                            ? null
                            : (selection) {
                                setState(() {
                                  draft.conflictResolution = selection.first;
                                });
                              },
                      ),
                    ],
                    if (externalRefCount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 16,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$externalRefCount référence(s) hors domaine convertie(s) en identifiant scalaire',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
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
    );
  }
}

Future<FunctionalDomain?> _showQuickCreateDomainDialog(
  BuildContext context, {
  required SpecForgeController controller,
}) => showDialog<FunctionalDomain>(
  context: context,
  builder: (_) => _QuickCreateDomainDialog(controller: controller),
);

class _QuickCreateDomainDialog extends StatefulWidget {
  const _QuickCreateDomainDialog({required this.controller});

  final SpecForgeController controller;

  @override
  State<_QuickCreateDomainDialog> createState() =>
      _QuickCreateDomainDialogState();
}

class _QuickCreateDomainDialogState extends State<_QuickCreateDomainDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  bool _codeEditedManually = false;
  String? _saveError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  static String _slugify(String raw) {
    final lower = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return lower.length > 64 ? lower.substring(0, 64) : lower;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('promote-quick-create-domain-dialog'),
      title: const Text('Nouveau domaine fonctionnel'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('promote-new-domain-name-field'),
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom du domaine',
                  hintText: 'Facturation',
                ),
                onChanged: (value) {
                  if (!_codeEditedManually) {
                    _codeCtrl.text = _slugify(value);
                  }
                },
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Nom requis (2 caractères minimum).'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('promote-new-domain-code-field'),
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code canonique',
                  hintText: 'facturation',
                  helperText: 'kebab-case, 2 à 64 caractères',
                ),
                onChanged: (_) => _codeEditedManually = true,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.length < 2 ||
                      trimmed.length > 64 ||
                      !_kebabDomainCodePattern.hasMatch(trimmed)) {
                    return 'Code attendu en kebab-case (2 à 64 caractères).';
                  }
                  if (widget.controller.domainCatalog.domains.any(
                    (d) => d.domainCode == trimmed,
                  )) {
                    return 'Ce code de domaine existe déjà.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('promote-new-domain-desc-field'),
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description métier (optionnel)',
                ),
              ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
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
          key: const ValueKey('promote-new-domain-save-btn'),
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            try {
              final domain = await widget.controller.createFunctionalDomain(
                domainCode: _codeCtrl.text.trim(),
                name: _nameCtrl.text.trim(),
                description: _descCtrl.text.trim(),
              );
              if (context.mounted) {
                Navigator.pop(context, domain);
              }
            } on Object catch (e) {
              if (mounted) {
                setState(() => _saveError = '$e');
              }
            }
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

class _PromoteStatusPill extends StatelessWidget {
  const _PromoteStatusPill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    this.icon,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (icon != null) Icon(icon, size: 13, color: foregroundColor),
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showMergePreviewDialog(
  BuildContext context, {
  required ObjectPromotionPreview preview,
}) => showDialog<void>(
  context: context,
  builder: (_) => _MergePreviewDialog(preview: preview),
);

class _MergePreviewDialog extends StatelessWidget {
  const _MergePreviewDialog({required this.preview});

  final ObjectPromotionPreview preview;

  static ({Color bg, Color fg, Color border, IconData icon}) _paletteForKind(
    AttributeMergeKind kind,
    ColorScheme colors,
  ) {
    final isDark = colors.brightness == Brightness.dark;
    return switch (kind) {
      AttributeMergeKind.addedFromSpec => (
        bg: Colors.green.withValues(alpha: isDark ? 0.22 : 0.12),
        fg: isDark ? Colors.green.shade200 : Colors.green.shade800,
        border: Colors.green.withValues(alpha: isDark ? 0.50 : 0.35),
        icon: Icons.add_circle_outline_rounded,
      ),
      AttributeMergeKind.updatedFromSpec => (
        bg: Colors.orange.withValues(alpha: isDark ? 0.22 : 0.13),
        fg: isDark ? Colors.amber.shade200 : Colors.orange.shade900,
        border: Colors.orange.withValues(alpha: isDark ? 0.50 : 0.36),
        icon: Icons.sync_rounded,
      ),
      AttributeMergeKind.preservedDesignValueObject => (
        bg: Colors.teal.withValues(alpha: isDark ? 0.22 : 0.12),
        fg: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
        border: Colors.teal.withValues(alpha: isDark ? 0.50 : 0.35),
        icon: Icons.diamond_outlined,
      ),
      AttributeMergeKind.preservedDesignOnly => (
        bg: Colors.indigo.withValues(alpha: isDark ? 0.22 : 0.11),
        fg: isDark ? Colors.indigo.shade200 : Colors.indigo.shade800,
        border: Colors.indigo.withValues(alpha: isDark ? 0.48 : 0.34),
        icon: Icons.shield_outlined,
      ),
      AttributeMergeKind.removedFromSpec => (
        bg: Colors.red.withValues(alpha: isDark ? 0.22 : 0.11),
        fg: isDark ? Colors.red.shade200 : Colors.red.shade800,
        border: Colors.red.withValues(alpha: isDark ? 0.52 : 0.36),
        icon: Icons.remove_circle_outline_rounded,
      ),
      AttributeMergeKind.conflictKeptDesign => (
        bg: Colors.amber.withValues(alpha: isDark ? 0.24 : 0.16),
        fg: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
        border: Colors.amber.withValues(alpha: isDark ? 0.55 : 0.42),
        icon: Icons.warning_amber_rounded,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final mergeResult = preview.mergeResult!;

    return AlertDialog(
      key: const ValueKey('promote-merge-preview-dialog'),
      insetPadding: const EdgeInsets.all(20),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.compare_arrows_rounded, color: colors.primary),
              Text(
                'Aperçu du merge — ${preview.specObject.name}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              _PromoteStatusPill(
                key: const ValueKey('merge-preview-version-badge'),
                label:
                    'v${preview.currentVersion} → v${preview.suggestedVersion}',
                icon: Icons.tag_rounded,
                backgroundColor: colors.secondaryContainer,
                foregroundColor: colors.onSecondaryContainer,
                borderColor: colors.secondary.withValues(alpha: 0.35),
              ),
            ],
          ),
          Text(
            'Domaine « ${preview.targetDomainName} »'
            '${preview.existingEntryPath != null ? ' · ${preview.existingEntryPath}' : ''}'
            ' · Stratégie : ${preview.choice.conflictResolution.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: (screen.width * 0.66).clamp(520.0, 820.0),
        height: (screen.height * 0.65).clamp(320.0, 560.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _PromoteStatusPill(
                    label: '+${mergeResult.addedCount} ajouté(s)',
                    backgroundColor: Colors.green.withValues(
                      alpha: isDark ? 0.22 : 0.12,
                    ),
                    foregroundColor: isDark
                        ? Colors.green.shade200
                        : Colors.green.shade800,
                    borderColor: Colors.green.withValues(
                      alpha: isDark ? 0.50 : 0.35,
                    ),
                  ),
                  _PromoteStatusPill(
                    label: '~${mergeResult.updatedCount} mis à jour',
                    backgroundColor: Colors.orange.withValues(
                      alpha: isDark ? 0.22 : 0.13,
                    ),
                    foregroundColor: isDark
                        ? Colors.amber.shade200
                        : Colors.orange.shade900,
                    borderColor: Colors.orange.withValues(
                      alpha: isDark ? 0.50 : 0.36,
                    ),
                  ),
                  _PromoteStatusPill(
                    label: '-${mergeResult.removedCount} retiré(s)',
                    backgroundColor: Colors.red.withValues(
                      alpha: isDark ? 0.22 : 0.11,
                    ),
                    foregroundColor: isDark
                        ? Colors.red.shade200
                        : Colors.red.shade800,
                    borderColor: Colors.red.withValues(
                      alpha: isDark ? 0.52 : 0.36,
                    ),
                  ),
                  if (mergeResult.preservedValueObjectIds.isNotEmpty)
                    _PromoteStatusPill(
                      label:
                          '${mergeResult.preservedValueObjectIds.length} VO préservé(s)',
                      icon: Icons.diamond_outlined,
                      backgroundColor: Colors.teal.withValues(
                        alpha: isDark ? 0.22 : 0.12,
                      ),
                      foregroundColor: isDark
                          ? Colors.teal.shade200
                          : Colors.teal.shade800,
                      borderColor: Colors.teal.withValues(
                        alpha: isDark ? 0.50 : 0.35,
                      ),
                    ),
                  if (mergeResult.preservedDesignOnlyCount > 0)
                    _PromoteStatusPill(
                      label:
                          '${mergeResult.preservedDesignOnlyCount} attribut(s) Design conservé(s)',
                      icon: Icons.shield_outlined,
                      backgroundColor: Colors.indigo.withValues(
                        alpha: isDark ? 0.22 : 0.11,
                      ),
                      foregroundColor: isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade800,
                      borderColor: Colors.indigo.withValues(
                        alpha: isDark ? 0.48 : 0.34,
                      ),
                    ),
                  if (mergeResult.conflictCount > 0)
                    _PromoteStatusPill(
                      label: '${mergeResult.conflictCount} conflit(s)',
                      icon: Icons.warning_amber_rounded,
                      backgroundColor: Colors.amber.withValues(
                        alpha: isDark ? 0.24 : 0.16,
                      ),
                      foregroundColor: isDark
                          ? Colors.amber.shade200
                          : Colors.amber.shade900,
                      borderColor: Colors.amber.withValues(
                        alpha: isDark ? 0.55 : 0.42,
                      ),
                    ),
                ],
              ),
              if (mergeResult.warnings.isNotEmpty)
                Container(
                  key: const ValueKey('merge-preview-warnings'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.amber.withValues(
                        alpha: isDark ? 0.48 : 0.38,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      Row(
                        spacing: 6,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: isDark
                                ? Colors.amber.shade200
                                : Colors.amber.shade900,
                          ),
                          Text(
                            'Avertissements (${mergeResult.warnings.length})',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      for (final warning in mergeResult.warnings)
                        Text(warning, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              if (mergeResult.decisions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text(
                    'Aucune différence d’attribut détectée : le contrat Design est aligné avec la Spec.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < mergeResult.decisions.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: colors.outlineVariant.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        Builder(
                          builder: (_) {
                            final d = mergeResult.decisions[i];
                            final palette = _paletteForKind(d.kind, colors);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 4,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _PromoteStatusPill(
                                        label: d.kind.label,
                                        icon: palette.icon,
                                        backgroundColor: palette.bg,
                                        foregroundColor: palette.fg,
                                        borderColor: palette.border,
                                      ),
                                      Text(
                                        d.attributePath,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      if (d.preservedValueObjectId != null &&
                                          d.preservedValueObjectId!
                                              .trim()
                                              .isNotEmpty)
                                        _PromoteStatusPill(
                                          label:
                                              'VO : ${d.preservedValueObjectId}',
                                          icon: Icons.diamond_outlined,
                                          backgroundColor:
                                              colors.surfaceContainerHighest,
                                          foregroundColor: colors.onSurface,
                                          borderColor: colors.outlineVariant,
                                        ),
                                    ],
                                  ),
                                  Text(
                                    d.summary,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('merge-preview-close-btn'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

