/// Boîtes de dialogue d'import et de synchronisation 3-voies d'objets métiers
/// depuis une autre Feature du projet ou un domaine Design
/// ([ImportSyncBusinessObjectsDialog], [CrossFeatureImpactDetailsDialog]).
library;

import 'package:material_ui/material_ui.dart';

import '../../models/domain_catalog.dart';
import '../../models/feature_object_sync_baseline.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_initiative.dart';
import '../../services/cross_feature_object_analyzer.dart';
import '../../services/feature_object_sync_engine.dart';
import '../../services/spec_design_merge_engine.dart';
import '../../services/spec_forge_controller.dart';

/// Cible de synchronisation inter-features sélectionnée depuis [CrossFeatureImpactDetailsDialog].
typedef CrossFeatureSyncRequest = ({
  String featureId,
  String objectIdOrTechName,
});

/// Construit un résumé français concis d'un [FeatureObjectSyncResult] pour notification (`SnackBar`).
String formatFeatureObjectSyncSummary(FeatureObjectSyncResult result) {
  final parts = <String>[];
  final imported = result.importedObjectIds.length;
  final merged = result.mergedObjectIds.length;
  final overwritten = result.overwrittenObjectIds.length;
  final skipped = result.skippedObjectNames.length;

  if (imported > 0) {
    parts.add('$imported objet(s) importé(s)');
  }
  if (merged > 0) {
    parts.add(
      merged == 1 ? '1 fusionné en 3-voies' : '$merged fusionnés en 3-voies',
    );
  }
  if (overwritten > 0) {
    parts.add(
      overwritten == 1
          ? '1 remplacé depuis la source'
          : '$overwritten remplacés depuis la source',
    );
  }
  if (skipped > 0) {
    parts.add('$skipped ignoré(s)');
  }
  if (parts.isEmpty) {
    return 'Aucune modification appliquée (objet(s) déjà aligné(s)).';
  }
  return '${parts.join(', ')}.';
}

/// Modale d'import et de re-synchronisation 3-voies d'objets métiers vers la
/// Feature active depuis une autre Feature du portefeuille ou un domaine Design.
class ImportSyncBusinessObjectsDialog extends StatefulWidget {
  /// Crée la modale d'import et de synchronisation d'objets métiers.
  const ImportSyncBusinessObjectsDialog({
    required this.controller,
    this.initialSourceKind,
    this.initialSourceFeatureId,
    this.initialSourceDomainId,
    this.preselectedObjectIdOrTechName,
    super.key,
  });

  /// Contrôleur portant le projet courant et le catalogue de domaines Design.
  final SpecForgeController controller;

  /// Mode de source présélectionné à l'ouverture, le cas échéant.
  final ObjectSyncSourceKind? initialSourceKind;

  /// Identifiant de la Feature sœur source présélectionnée, le cas échéant.
  final String? initialSourceFeatureId;

  /// Identifiant du domaine fonctionnel Design présélectionné, le cas échéant.
  final String? initialSourceDomainId;

  /// Identifiant ou `technicalName` d'un objet candidat à pré-cocher à l'ouverture.
  final String? preselectedObjectIdOrTechName;

  /// Affiche la modale et retourne le [FeatureObjectSyncResult] exécuté, ou `null` en cas d'annulation.
  static Future<FeatureObjectSyncResult?> show(
    BuildContext context, {
    required SpecForgeController controller,
    ObjectSyncSourceKind? initialSourceKind,
    String? initialSourceFeatureId,
    String? initialSourceDomainId,
    String? preselectedObjectIdOrTechName,
  }) => showDialog<FeatureObjectSyncResult>(
    context: context,
    builder: (_) => ImportSyncBusinessObjectsDialog(
      controller: controller,
      initialSourceKind: initialSourceKind,
      initialSourceFeatureId: initialSourceFeatureId,
      initialSourceDomainId: initialSourceDomainId,
      preselectedObjectIdOrTechName: preselectedObjectIdOrTechName,
    ),
  );

  @override
  State<ImportSyncBusinessObjectsDialog> createState() =>
      _ImportSyncBusinessObjectsDialogState();
}

class _SyncCandidateDraft {
  _SyncCandidateDraft({
    this.resolution = FeatureObjectSyncResolution.smartMerge,
  });

  bool checked = false;
  FeatureObjectSyncResolution resolution;
}

class _ImportSyncBusinessObjectsDialogState
    extends State<ImportSyncBusinessObjectsDialog> {
  final TextEditingController _filterCtrl = TextEditingController();
  final Map<String, _SyncCandidateDraft> _draftsByScopeKey =
      <String, _SyncCandidateDraft>{};

  late ObjectSyncSourceKind _sourceKind;
  String? _selectedFeatureId;
  String? _selectedDomainId;
  bool _includeDtos = false;
  String _filterQuery = '';
  FeatureObjectSyncResolution _batchResolution =
      FeatureObjectSyncResolution.smartMerge;
  bool _submitting = false;
  String? _errorMessage;

  SpecForgeProject? get _project => widget.controller.project;
  List<FunctionalDomain> get _domains =>
      widget.controller.domainCatalog.domains;

  static List<SpecFeatureSpec> _siblingFeaturesOf(SpecForgeProject project) => [
    for (final f in project.allFeatures)
      if (f.id != project.activeFeatureId &&
          f.effectiveStatus != SpecPortfolioStatus.archived)
        f,
  ];

  static bool _domainHasContracts(FunctionalDomain domain) =>
      domain.contracts?.groups.any((g) => g.children.isNotEmpty) ?? false;

  static int _domainEntryCount(FunctionalDomain domain) {
    final contracts = domain.contracts;
    if (contracts == null) return 0;
    return contracts.groups.fold<int>(0, (sum, g) => sum + g.children.length);
  }

  @override
  void initState() {
    super.initState();
    final project = _project;
    final siblings = project == null
        ? const <SpecFeatureSpec>[]
        : _siblingFeaturesOf(project);
    final domains = _domains;

    final requestedFeatId = widget.initialSourceFeatureId?.trim();
    if (requestedFeatId != null &&
        siblings.any((f) => f.id == requestedFeatId)) {
      _selectedFeatureId = requestedFeatId;
    } else {
      _selectedFeatureId =
          siblings.where((f) => f.businessObjects.isNotEmpty).firstOrNull?.id ??
          siblings.firstOrNull?.id;
    }

    final requestedDomId = widget.initialSourceDomainId?.trim();
    if (requestedDomId != null && domains.any((d) => d.id == requestedDomId)) {
      _selectedDomainId = requestedDomId;
    } else {
      _selectedDomainId =
          domains.where(_domainHasContracts).firstOrNull?.id ??
          domains.firstOrNull?.id;
    }

    if (widget.initialSourceKind != null) {
      _sourceKind = widget.initialSourceKind!;
    } else if (requestedDomId != null && requestedDomId.isNotEmpty) {
      _sourceKind = ObjectSyncSourceKind.designDomain;
    } else if (requestedFeatId != null && requestedFeatId.isNotEmpty) {
      _sourceKind = ObjectSyncSourceKind.feature;
    } else if (siblings.any((f) => f.businessObjects.isNotEmpty)) {
      _sourceKind = ObjectSyncSourceKind.feature;
    } else if (domains.any(_domainHasContracts)) {
      _sourceKind = ObjectSyncSourceKind.designDomain;
    } else if (siblings.isNotEmpty) {
      _sourceKind = ObjectSyncSourceKind.feature;
    } else {
      _sourceKind = ObjectSyncSourceKind.designDomain;
    }

    _applyPreselectionIfNeeded(project);
  }

  void _applyPreselectionIfNeeded(SpecForgeProject? project) {
    final needle = widget.preselectedObjectIdOrTechName?.trim() ?? '';
    if (project == null || needle.isEmpty) return;

    var candidates = _currentCandidates(project);
    var matched = _findCandidateMatching(candidates, needle);
    if (matched == null &&
        _sourceKind == ObjectSyncSourceKind.designDomain &&
        !_includeDtos &&
        _selectedDomainId != null) {
      final domain = _domains
          .where((d) => d.id == _selectedDomainId)
          .firstOrNull;
      if (domain != null) {
        final expanded = FeatureObjectSyncEngine.listCandidatesFromDesignDomain(
          domain: domain,
          catalog: widget.controller.domainCatalog,
          project: project,
          modelPreferences: widget.controller.modelPreferences,
          includeDtosAndMessages: true,
        );
        final dtoMatch = _findCandidateMatching(expanded, needle);
        if (dtoMatch != null) {
          _includeDtos = true;
          candidates = expanded;
          matched = dtoMatch;
        }
      }
    }

    if (matched != null) {
      _draftFor(matched).checked = true;
    }
  }

  static FeatureObjectSyncCandidate? _findCandidateMatching(
    List<FeatureObjectSyncCandidate> pool,
    String needle,
  ) {
    final lower = needle.toLowerCase();
    for (final c in pool) {
      if (c.id == needle ||
          c.sourceEntryId == needle ||
          c.rawObject.id == needle) {
        return c;
      }
    }
    for (final c in pool) {
      if (c.id.toLowerCase() == lower ||
          c.sourceEntryId.toLowerCase() == lower ||
          c.rawObject.id.toLowerCase() == lower ||
          c.rawObject.technicalName.toLowerCase() == lower) {
        return c;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  String _scopeKeyFor(FeatureObjectSyncCandidate candidate) =>
      '${candidate.sourceKind.name}:${candidate.sourceFeatureId}:'
      '${candidate.sourceDomainId}:${candidate.id}';

  _SyncCandidateDraft _draftFor(FeatureObjectSyncCandidate candidate) =>
      _draftsByScopeKey.putIfAbsent(
        _scopeKeyFor(candidate),
        () => _SyncCandidateDraft(resolution: _batchResolution),
      );

  List<FeatureObjectSyncCandidate> _currentCandidates(
    SpecForgeProject project,
  ) {
    switch (_sourceKind) {
      case ObjectSyncSourceKind.feature:
        final featId = _selectedFeatureId;
        if (featId == null || featId.isEmpty) {
          return const <FeatureObjectSyncCandidate>[];
        }
        return FeatureObjectSyncEngine.listCandidatesFromFeature(
          project: project,
          sourceFeatureId: featId,
        );
      case ObjectSyncSourceKind.designDomain:
        final domId = _selectedDomainId;
        if (domId == null || domId.isEmpty) {
          return const <FeatureObjectSyncCandidate>[];
        }
        final domain = _domains.where((d) => d.id == domId).firstOrNull;
        if (domain == null) {
          return const <FeatureObjectSyncCandidate>[];
        }
        return FeatureObjectSyncEngine.listCandidatesFromDesignDomain(
          domain: domain,
          catalog: widget.controller.domainCatalog,
          project: project,
          modelPreferences: widget.controller.modelPreferences,
          includeDtosAndMessages: _includeDtos,
        );
    }
  }

  List<FeatureObjectSyncCandidate> _filterCandidates(
    List<FeatureObjectSyncCandidate> all,
  ) {
    final q = _filterQuery.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (c) =>
              c.rawObject.name.toLowerCase().contains(q) ||
              c.rawObject.technicalName.toLowerCase().contains(q) ||
              c.rawObject.description.toLowerCase().contains(q) ||
              c.contractType.toLowerCase().contains(q),
        )
        .toList();
  }

  List<FeatureObjectSyncChoice> _selectedChoicesFor(
    List<FeatureObjectSyncCandidate> candidates,
  ) => <FeatureObjectSyncChoice>[
    for (final c in candidates)
      if (_draftFor(c).checked) c.toChoice(resolution: _draftFor(c).resolution),
  ];

  Map<String, FeatureObjectSyncPreview> _computePreviews({
    required List<FeatureObjectSyncCandidate> allCandidates,
    required List<FeatureObjectSyncCandidate> visibleCandidates,
  }) {
    final byCandidateId = <String, FeatureObjectSyncPreview>{};
    final checkedChoices = _selectedChoicesFor(allCandidates);
    if (checkedChoices.isNotEmpty) {
      try {
        final checkedPreviews = widget.controller
            .previewBusinessObjectSyncIntoActiveFeature(checkedChoices);
        for (final preview in checkedPreviews) {
          byCandidateId[preview.choice.sourceObjectKey] = preview;
        }
      } on Object {
        // Ignore un état intermédiaire le temps de l'édition.
      }
    }

    for (final candidate in visibleCandidates) {
      if (byCandidateId.containsKey(candidate.id)) continue;
      final draft = _draftFor(candidate);
      final probeChoice = candidate.toChoice(resolution: draft.resolution);
      try {
        final probePreviews = widget.controller
            .previewBusinessObjectSyncIntoActiveFeature(
              <FeatureObjectSyncChoice>[...checkedChoices, probeChoice],
            );
        final match = probePreviews
            .where((p) => p.choice.sourceObjectKey == candidate.id)
            .firstOrNull;
        if (match != null) {
          byCandidateId[candidate.id] = match;
        }
      } on Object {
        // Ignore un état intermédiaire invalide.
      }
    }
    return byCandidateId;
  }

  void _selectAllVisible(List<FeatureObjectSyncCandidate> visible) {
    setState(() {
      for (final c in visible) {
        _draftFor(c).checked = true;
      }
      _errorMessage = null;
    });
  }

  void _clearAllInSource(List<FeatureObjectSyncCandidate> allCandidates) {
    setState(() {
      for (final c in allCandidates) {
        _draftFor(c).checked = false;
      }
      _errorMessage = null;
    });
  }

  void _applyBatchResolution(
    FeatureObjectSyncResolution resolution,
    List<FeatureObjectSyncCandidate> allCandidates,
  ) {
    setState(() {
      _batchResolution = resolution;
      final anyChecked = allCandidates.any((c) => _draftFor(c).checked);
      for (final c in allCandidates) {
        final draft = _draftFor(c);
        if (!anyChecked || draft.checked) {
          draft.resolution = resolution;
        }
      }
      _errorMessage = null;
    });
  }

  Future<void> _submit(List<FeatureObjectSyncChoice> choices) async {
    if (_submitting || choices.isEmpty) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.controller
          .syncBusinessObjectsIntoActiveFeature(choices);
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
        if (project == null) return const SizedBox.shrink();

        final screen = MediaQuery.sizeOf(context);
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final siblings = _siblingFeaturesOf(project);
        final domains = _domains;

        if (_selectedFeatureId != null &&
            !siblings.any((f) => f.id == _selectedFeatureId)) {
          _selectedFeatureId =
              siblings
                  .where((f) => f.businessObjects.isNotEmpty)
                  .firstOrNull
                  ?.id ??
              siblings.firstOrNull?.id;
        }
        if (_selectedDomainId != null &&
            !domains.any((d) => d.id == _selectedDomainId)) {
          _selectedDomainId =
              domains.where(_domainHasContracts).firstOrNull?.id ??
              domains.firstOrNull?.id;
        }

        final allCandidates = _currentCandidates(project);
        final visible = _filterCandidates(allCandidates);
        final selectedChoices = _selectedChoicesFor(allCandidates);
        final checkedCount = selectedChoices.length;
        final previewsByCandidateId = _computePreviews(
          allCandidates: allCandidates,
          visibleCandidates: visible,
        );
        final activeFeatureLabel = project.activeFeature.displayLabel;
        final canSubmit = !_submitting && selectedChoices.isNotEmpty;

        return AlertDialog(
          key: const ValueKey('import-sync-business-objects-dialog'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          title: Row(
            children: [
              Icon(Icons.sync_alt_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importer / Synchroniser des objets métier',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Cible : $activeFeatureLabel · '
                      '$checkedCount / ${allCandidates.length} objet(s) sélectionné(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: (screen.width * 0.86).clamp(520.0, 920.0),
            height: (screen.height * 0.76).clamp(360.0, 580.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSourceSelectorBar(
                  theme: theme,
                  colors: colors,
                  siblings: siblings,
                  domains: domains,
                ),
                const SizedBox(height: 10),
                _buildToolbar(
                  theme: theme,
                  colors: colors,
                  allCandidates: allCandidates,
                  visible: visible,
                  checkedCount: checkedCount,
                ),
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
                  child: _buildCandidateList(
                    theme: theme,
                    colors: colors,
                    project: project,
                    siblings: siblings,
                    domains: domains,
                    allCandidates: allCandidates,
                    visible: visible,
                    previewsByCandidateId: previewsByCandidateId,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('import-sync-cancel-btn'),
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              key: const ValueKey('import-sync-submit-btn'),
              onPressed: canSubmit ? () => _submit(selectedChoices) : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done_rounded, size: 17),
              label: Text(
                selectedChoices.isEmpty
                    ? 'Synchroniser'
                    : 'Synchroniser (${selectedChoices.length})',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSourceSelectorBar({
    required ThemeData theme,
    required ColorScheme colors,
    required List<SpecFeatureSpec> siblings,
    required List<FunctionalDomain> domains,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            key: const ValueKey('import-sync-mode-feature'),
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.auto_awesome_motion_rounded, size: 16),
            label: const Text('Depuis une autre Feature du projet'),
            selected: _sourceKind == ObjectSyncSourceKind.feature,
            onSelected: _submitting
                ? null
                : (_) {
                    setState(() {
                      _sourceKind = ObjectSyncSourceKind.feature;
                      _errorMessage = null;
                    });
                  },
          ),
          ChoiceChip(
            key: const ValueKey('import-sync-mode-design'),
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.architecture_rounded, size: 16),
            label: const Text('Depuis un Domaine Design'),
            selected: _sourceKind == ObjectSyncSourceKind.designDomain,
            onSelected: _submitting
                ? null
                : (_) {
                    setState(() {
                      _sourceKind = ObjectSyncSourceKind.designDomain;
                      _errorMessage = null;
                    });
                  },
          ),
          if (_sourceKind == ObjectSyncSourceKind.feature &&
              siblings.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
              child: InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Feature source',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const ValueKey('import-sync-feature-dropdown'),
                    value: _selectedFeatureId,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final feat in siblings)
                        DropdownMenuItem<String>(
                          value: feat.id,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  feat.displayLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _FeatureStatusBadge(status: feat.effectiveStatus),
                              const SizedBox(width: 6),
                              Text(
                                '${feat.businessObjects.length} objet(s)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedFeatureId = value;
                              _errorMessage = null;
                            });
                          },
                  ),
                ),
              ),
            ),
          if (_sourceKind == ObjectSyncSourceKind.designDomain &&
              domains.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
              child: InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Domaine Design',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const ValueKey('import-sync-domain-dropdown'),
                    value: _selectedDomainId,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final domain in domains)
                        DropdownMenuItem<String>(
                          value: domain.id,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  domain.isActive
                                      ? domain.name
                                      : '${domain.name} (inactif)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_domainEntryCount(domain)} contrat(s)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedDomainId = value;
                              _errorMessage = null;
                            });
                          },
                  ),
                ),
              ),
            ),
            FilterChip(
              key: const ValueKey('import-sync-include-dtos-checkbox'),
              visualDensity: VisualDensity.compact,
              selected: _includeDtos,
              label: const Text('Inclure DTOs & Messages'),
              tooltip:
                  'Par défaut seuls les contrats model, part et component sont proposés',
              onSelected: _submitting
                  ? null
                  : (value) => setState(() => _includeDtos = value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar({
    required ThemeData theme,
    required ColorScheme colors,
    required List<FeatureObjectSyncCandidate> allCandidates,
    required List<FeatureObjectSyncCandidate> visible,
    required int checkedCount,
  }) {
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
                key: const ValueKey('import-sync-filter-field'),
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
              key: const ValueKey('import-sync-select-all-btn'),
              onPressed: _submitting || visible.isEmpty
                  ? null
                  : () => _selectAllVisible(visible),
              child: const Text('Tout cocher'),
            ),
            TextButton(
              key: const ValueKey('import-sync-clear-all-btn'),
              onPressed: _submitting || checkedCount == 0
                  ? null
                  : () => _clearAllInSource(allCandidates),
              child: const Text('Tout décocher'),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 230, maxWidth: 295),
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Résolution groupée (objets existants)',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FeatureObjectSyncResolution>(
                key: const ValueKey('import-sync-batch-resolution-dropdown'),
                value: _batchResolution,
                isDense: true,
                isExpanded: true,
                items: [
                  for (final option in FeatureObjectSyncResolution.values)
                    DropdownMenuItem<FeatureObjectSyncResolution>(
                      value: option,
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
                onChanged: _submitting || allCandidates.isEmpty
                    ? null
                    : (value) {
                        if (value == null) return;
                        _applyBatchResolution(value, allCandidates);
                      },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCandidateList({
    required ThemeData theme,
    required ColorScheme colors,
    required SpecForgeProject project,
    required List<SpecFeatureSpec> siblings,
    required List<FunctionalDomain> domains,
    required List<FeatureObjectSyncCandidate> allCandidates,
    required List<FeatureObjectSyncCandidate> visible,
    required Map<String, FeatureObjectSyncPreview> previewsByCandidateId,
  }) {
    if (_sourceKind == ObjectSyncSourceKind.feature && siblings.isEmpty) {
      return Center(
        child: Text(
          'Aucune autre Feature active n’est disponible dans ce projet.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_sourceKind == ObjectSyncSourceKind.designDomain && domains.isEmpty) {
      return Center(
        child: Text(
          'Aucun domaine fonctionnel Design n’est configuré dans ce workspace.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }
    if (allCandidates.isEmpty) {
      return Center(
        child: Text(
          _sourceKind == ObjectSyncSourceKind.feature
              ? 'La Feature sélectionnée ne contient encore aucun objet métier.'
              : 'Aucun contrat éligible dans ce domaine Design'
                    '${_includeDtos ? '.' : ' (cochez « Inclure DTOs & Messages » si nécessaire).'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          'Aucun objet candidat ne correspond au filtre « ${_filterQuery.trim()} ».',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final candidate = visible[index];
        return _buildCandidateRow(
          theme: theme,
          colors: colors,
          project: project,
          candidate: candidate,
          preview: previewsByCandidateId[candidate.id],
        );
      },
    );
  }

  Widget _buildCandidateRow({
    required ThemeData theme,
    required ColorScheme colors,
    required SpecForgeProject project,
    required FeatureObjectSyncCandidate candidate,
    required FeatureObjectSyncPreview? preview,
  }) {
    final draft = _draftFor(candidate);
    final obj = candidate.rawObject;
    final isDark = colors.brightness == Brightness.dark;
    final activeRef = project.activeFeature.code.trim().isNotEmpty
        ? project.activeFeature.code.trim()
        : project.activeFeature.name.trim();

    final statusPills = <Widget>[];
    if (preview != null) {
      if (preview.isNewInTarget) {
        statusPills.add(
          _SyncStatusPill(
            key: ValueKey('import-sync-status-${candidate.id}'),
            label: 'Nouveau dans $activeRef',
            icon: Icons.fiber_new_rounded,
            backgroundColor: Colors.teal.withValues(alpha: isDark ? 0.22 : 0.12),
            foregroundColor: isDark
                ? Colors.teal.shade200
                : Colors.teal.shade800,
            borderColor: Colors.teal.withValues(alpha: isDark ? 0.50 : 0.35),
          ),
        );
      } else if (preview.willSkip) {
        statusPills.add(
          _SyncStatusPill(
            key: ValueKey('import-sync-status-${candidate.id}'),
            label: 'Ignoré',
            icon: Icons.block_rounded,
            backgroundColor: colors.surfaceContainerHighest,
            foregroundColor: colors.onSurfaceVariant,
            borderColor: colors.outlineVariant,
          ),
        );
      } else if (preview.isIdentical) {
        statusPills.add(
          _SyncStatusPill(
            key: ValueKey('import-sync-status-${candidate.id}'),
            label: 'Identique',
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
      } else if (preview.choice.resolution ==
              FeatureObjectSyncResolution.smartMerge &&
          preview.mergeResult != null) {
        final mergeResult = preview.mergeResult!;
        statusPills.add(
          _SyncStatusPill(
            key: ValueKey('import-sync-status-${candidate.id}'),
            label:
                'Δ +${mergeResult.addedCount} / ~${mergeResult.updatedCount} / -${mergeResult.removedCount}',
            icon: Icons.merge_type_rounded,
            backgroundColor: Colors.orange.withValues(
              alpha: isDark ? 0.22 : 0.13,
            ),
            foregroundColor: isDark
                ? Colors.amber.shade200
                : Colors.orange.shade900,
            borderColor: Colors.orange.withValues(alpha: isDark ? 0.50 : 0.36),
          ),
        );
      } else {
        statusPills.add(
          _SyncStatusPill(
            key: ValueKey('import-sync-status-${candidate.id}'),
            label: 'Remplacement complet',
            icon: Icons.published_with_changes_rounded,
            backgroundColor: Colors.blue.withValues(
              alpha: isDark ? 0.22 : 0.12,
            ),
            foregroundColor: isDark
                ? Colors.lightBlue.shade200
                : Colors.blue.shade800,
            borderColor: Colors.blue.withValues(alpha: isDark ? 0.48 : 0.34),
          ),
        );
      }

      if (preview.localImpactedArtifactWarnings.isNotEmpty) {
        statusPills.add(
          _SyncStatusPill(
            key: ValueKey('import-sync-impact-pill-${candidate.id}'),
            label:
                '⚠ ${preview.localImpactedArtifactWarnings.length} impact(s) local(aux) RG/UX/QA',
            backgroundColor: Colors.amber.withValues(
              alpha: isDark ? 0.24 : 0.16,
            ),
            foregroundColor: isDark
                ? Colors.amber.shade200
                : Colors.amber.shade900,
            borderColor: Colors.amber.withValues(alpha: isDark ? 0.55 : 0.42),
          ),
        );
      }

      if (preview.unresolvedExternalRefCount > 0) {
        statusPills.add(
          _SyncStatusPill(
            key: ValueKey('import-sync-extref-pill-${candidate.id}'),
            label:
                '${preview.unresolvedExternalRefCount} réf. convertie(s) en ID',
            icon: Icons.swap_horiz_rounded,
            backgroundColor: colors.secondaryContainer.withValues(alpha: 0.7),
            foregroundColor: colors.onSecondaryContainer,
            borderColor: colors.secondary.withValues(alpha: 0.35),
          ),
        );
      }
    }

    final showExistingControls = preview != null && !preview.isNewInTarget;
    final borderColor = draft.checked
        ? colors.primary.withValues(alpha: 0.6)
        : colors.outlineVariant;

    Widget buildResolutionDropdown() => InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Résolution',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<FeatureObjectSyncResolution>(
          key: ValueKey('import-sync-resolution-${candidate.id}'),
          value: draft.resolution,
          isDense: true,
          isExpanded: true,
          items: [
            for (final option in FeatureObjectSyncResolution.values)
              DropdownMenuItem<FeatureObjectSyncResolution>(
                value: option,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          onChanged: _submitting
              ? null
              : (next) {
                  if (next == null) return;
                  setState(() {
                    draft.resolution = next;
                    _errorMessage = null;
                  });
                },
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, rowConstraints) {
        final inlineResolution =
            showExistingControls && rowConstraints.maxWidth >= 660;
        return DecoratedBox(
          key: ValueKey('import-sync-row-${candidate.id}'),
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
                      key: ValueKey('import-sync-check-${candidate.id}'),
                      value: draft.checked,
                      onChanged: _submitting
                          ? null
                          : (value) {
                              setState(() {
                                draft.checked = value ?? false;
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
                                obj.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                obj.technicalName,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (candidate.contractType.trim().isNotEmpty)
                                _ContractTypeBadge(
                                  contractType: candidate.contractType,
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
                                  obj.aggregateRoot ? 'Agrégat' : 'Sous-objet',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                              Text(
                                '${obj.totalAttributeCount} attr.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              ...statusPills,
                              if (showExistingControls)
                                TextButton.icon(
                                  key: ValueKey(
                                    'import-sync-preview-${candidate.id}',
                                  ),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _showSyncMergePreviewDialog(
                                    context,
                                    candidate: candidate,
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
                          if (obj.description.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                obj.description,
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
                    if (inlineResolution) ...[
                      const SizedBox(width: 12),
                      SizedBox(width: 255, child: buildResolutionDropdown()),
                    ],
                  ],
                ),
                if (showExistingControls && !inlineResolution)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 8, 0, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: buildResolutionDropdown(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Modale de détails de gouvernance inter-features (`additive_warn_on_validated`)
/// listant les features sœurs, les écarts structurels et les impacts aval (`RG`, `UX`, `QA`).
class CrossFeatureImpactDetailsDialog extends StatelessWidget {
  /// Crée la modale d'analyse d'impact et de partage inter-features.
  const CrossFeatureImpactDetailsDialog({
    required this.project,
    required this.reports,
    this.focusedObjectName,
    super.key,
  });

  /// Projet actif portant les features comparées.
  final SpecForgeProject project;

  /// Rapports inter-features d'objets métiers à inspecter.
  final List<ObjectCrossFeatureReport> reports;

  /// Nom optionnel d'un objet unique lorsque la modale est ouverte depuis le badge d'un objet.
  final String? focusedObjectName;

  /// Affiche la modale et retourne une [CrossFeatureSyncRequest] si l'utilisateur
  /// clique sur « `Synchroniser depuis <FEAT-xx>…` », ou `null` sinon.
  static Future<CrossFeatureSyncRequest?> show(
    BuildContext context, {
    required SpecForgeProject project,
    required List<ObjectCrossFeatureReport> reports,
    String? focusedObjectName,
  }) => showDialog<CrossFeatureSyncRequest>(
    context: context,
    builder: (_) => CrossFeatureImpactDetailsDialog(
      project: project,
      reports: reports,
      focusedObjectName: focusedObjectName,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final hasAnyWarning = reports.any((r) => r.hasBreakingValidatedWarning);

    return AlertDialog(
      key: const ValueKey('cross-feature-impact-details-dialog'),
      insetPadding: const EdgeInsets.all(20),
      title: Row(
        children: [
          Icon(
            hasAnyWarning ? Icons.warning_amber_rounded : Icons.hub_outlined,
            color: hasAnyWarning ? Colors.orange : colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  focusedObjectName != null
                      ? 'Partage & impacts inter-features — $focusedObjectName'
                      : 'Impacts inter-features (${reports.length} objet(s))',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Feature analysée : ${project.activeFeature.displayLabel} · '
                  'Politique : extensions additives libres, alerte sur rupture Validée',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: (screen.width * 0.72).clamp(500.0, 840.0),
        height: (screen.height * 0.68).clamp(320.0, 560.0),
        child: reports.isEmpty
            ? Center(
                child: Text(
                  'Aucun partage ni impact inter-features détecté.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _buildObjectReportCard(
                  context: context,
                  theme: theme,
                  colors: colors,
                  isDark: isDark,
                  report: reports[index],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cross-feature-impact-close-btn'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  Widget _buildObjectReportCard({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colors,
    required bool isDark,
    required ObjectCrossFeatureReport report,
  }) {
    return Container(
      key: ValueKey('cross-impact-card-${report.objectId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: report.hasBreakingValidatedWarning
              ? Colors.orange.withValues(alpha: isDark ? 0.55 : 0.45)
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.hub_rounded, size: 17, color: colors.primary),
              Text(
                report.objectName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                report.technicalName,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFamily: 'monospace',
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          for (final link in report.siblingLinks)
            _buildSiblingLinkTile(
              context: context,
              theme: theme,
              colors: colors,
              isDark: isDark,
              report: report,
              link: link,
            ),
        ],
      ),
    );
  }

  Widget _buildSiblingLinkTile({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colors,
    required bool isDark,
    required ObjectCrossFeatureReport report,
    required SiblingFeatureObjectLink link,
  }) {
    final divPalette = _divergencePalette(link.divergence, colors, isDark);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: link.hasValidatedWarning
              ? Colors.orange.withValues(alpha: isDark ? 0.50 : 0.40)
              : colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    link.featureDisplayLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _FeatureStatusBadge(status: link.effectiveStatus),
                  _SyncStatusPill(
                    label: link.divergence.label,
                    icon: divPalette.icon,
                    backgroundColor: divPalette.bg,
                    foregroundColor: divPalette.fg,
                    borderColor: divPalette.border,
                  ),
                ],
              ),
              OutlinedButton.icon(
                key: ValueKey(
                  'cross-impact-sync-${report.objectId}-${link.featureId}',
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => Navigator.pop(context, (
                  featureId: link.featureId,
                  objectIdOrTechName: link.siblingObjectId,
                )),
                icon: const Icon(Icons.sync_rounded, size: 15),
                label: Text('Synchroniser depuis ${link.effectiveFeatureRef}…'),
              ),
            ],
          ),
          if (link.differenceSummaries.isEmpty)
            Text(
              'Aucune divergence structurelle détectée avec ${link.effectiveFeatureRef}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                for (final diff in link.differenceSummaries)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: Text(diff, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
              ],
            ),
          if (link.downstreamImpacts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: isDark ? 0.45 : 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Text(
                    'Livrables ${link.effectiveFeatureRef} impactés (${link.downstreamImpacts.length})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Colors.amber.shade200
                          : Colors.amber.shade900,
                    ),
                  ),
                  for (final impact in link.downstreamImpacts)
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SyncStatusPill(
                          label: '${impact.area.label} · ${impact.artifactRef}',
                          backgroundColor: colors.surfaceContainerHighest,
                          foregroundColor: colors.onSurface,
                          borderColor: colors.outlineVariant,
                        ),
                        if (impact.artifactTitle.trim().isNotEmpty)
                          Text(
                            impact.artifactTitle,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          '— ${impact.summary}',
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
    );
  }

  static ({Color bg, Color fg, Color border, IconData icon}) _divergencePalette(
    CrossFeatureDivergenceKind kind,
    ColorScheme colors,
    bool isDark,
  ) => switch (kind) {
    CrossFeatureDivergenceKind.identical => (
      bg: Colors.green.withValues(alpha: isDark ? 0.20 : 0.11),
      fg: isDark ? Colors.green.shade200 : Colors.green.shade800,
      border: Colors.green.withValues(alpha: isDark ? 0.46 : 0.32),
      icon: Icons.check_circle_outline_rounded,
    ),
    CrossFeatureDivergenceKind.additive => (
      bg: Colors.teal.withValues(alpha: isDark ? 0.20 : 0.11),
      fg: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
      border: Colors.teal.withValues(alpha: isDark ? 0.46 : 0.32),
      icon: Icons.add_circle_outline_rounded,
    ),
    CrossFeatureDivergenceKind.behindSibling => (
      bg: Colors.blue.withValues(alpha: isDark ? 0.20 : 0.11),
      fg: isDark ? Colors.lightBlue.shade200 : Colors.blue.shade800,
      border: Colors.blue.withValues(alpha: isDark ? 0.46 : 0.32),
      icon: Icons.download_for_offline_outlined,
    ),
    CrossFeatureDivergenceKind.breaking => (
      bg: Colors.red.withValues(alpha: isDark ? 0.22 : 0.12),
      fg: isDark ? Colors.red.shade200 : Colors.red.shade800,
      border: Colors.red.withValues(alpha: isDark ? 0.52 : 0.38),
      icon: Icons.warning_amber_rounded,
    ),
  };
}

Future<void> _showSyncMergePreviewDialog(
  BuildContext context, {
  required FeatureObjectSyncCandidate candidate,
  required FeatureObjectSyncPreview preview,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _ImportSyncMergePreviewDialog(candidate: candidate, preview: preview),
);

class _ImportSyncMergePreviewDialog extends StatelessWidget {
  const _ImportSyncMergePreviewDialog({
    required this.candidate,
    required this.preview,
  });

  final FeatureObjectSyncCandidate candidate;
  final FeatureObjectSyncPreview preview;

  static ({Color bg, Color fg, Color border, IconData icon, String label})
  _paletteForKind(AttributeMergeKind kind, ColorScheme colors) {
    final isDark = colors.brightness == Brightness.dark;
    return switch (kind) {
      AttributeMergeKind.addedFromSpec => (
        bg: Colors.green.withValues(alpha: isDark ? 0.22 : 0.12),
        fg: isDark ? Colors.green.shade200 : Colors.green.shade800,
        border: Colors.green.withValues(alpha: isDark ? 0.50 : 0.35),
        icon: Icons.add_circle_outline_rounded,
        label: 'Ajouté depuis la source',
      ),
      AttributeMergeKind.updatedFromSpec => (
        bg: Colors.orange.withValues(alpha: isDark ? 0.22 : 0.13),
        fg: isDark ? Colors.amber.shade200 : Colors.orange.shade900,
        border: Colors.orange.withValues(alpha: isDark ? 0.50 : 0.36),
        icon: Icons.sync_rounded,
        label: 'Mis à jour depuis la source',
      ),
      AttributeMergeKind.preservedDesignValueObject => (
        bg: Colors.teal.withValues(alpha: isDark ? 0.22 : 0.12),
        fg: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
        border: Colors.teal.withValues(alpha: isDark ? 0.50 : 0.35),
        icon: Icons.diamond_outlined,
        label: 'Typage local conservé',
      ),
      AttributeMergeKind.preservedDesignOnly => (
        bg: Colors.indigo.withValues(alpha: isDark ? 0.22 : 0.11),
        fg: isDark ? Colors.indigo.shade200 : Colors.indigo.shade800,
        border: Colors.indigo.withValues(alpha: isDark ? 0.48 : 0.34),
        icon: Icons.shield_outlined,
        label: 'Ajout local conservé',
      ),
      AttributeMergeKind.removedFromSpec => (
        bg: Colors.red.withValues(alpha: isDark ? 0.22 : 0.11),
        fg: isDark ? Colors.red.shade200 : Colors.red.shade800,
        border: Colors.red.withValues(alpha: isDark ? 0.52 : 0.36),
        icon: Icons.remove_circle_outline_rounded,
        label: 'Retiré (supprimé en amont)',
      ),
      AttributeMergeKind.conflictKeptDesign => (
        bg: Colors.amber.withValues(alpha: isDark ? 0.24 : 0.16),
        fg: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
        border: Colors.amber.withValues(alpha: isDark ? 0.55 : 0.42),
        icon: Icons.warning_amber_rounded,
        label: 'Conflit — cible conservée',
      ),
    };
  }

  ObjectMergeResult? _effectiveMergeOrDiff() {
    if (preview.mergeResult != null) return preview.mergeResult;
    final existing = preview.existingTargetObject;
    if (existing == null) return null;
    return SpecDesignMergeEngine.merge(
      baseSpec: existing,
      nextSpecResolved: preview.projectedSourceObject,
      currentDesign: existing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final mergeView = _effectiveMergeOrDiff();
    final decisions = mergeView?.decisions ?? const <AttributeMergeDecision>[];

    return AlertDialog(
      key: const ValueKey('import-sync-merge-preview-dialog'),
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
                'Aperçu du merge — ${candidate.rawObject.name}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Text(
            'Source : ${candidate.sourceDisplayLabel} · '
            'Stratégie : ${preview.choice.resolution.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: (screen.width * 0.66).clamp(500.0, 820.0),
        height: (screen.height * 0.65).clamp(320.0, 560.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (mergeView != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _SyncStatusPill(
                      label: '+${mergeView.addedCount} ajouté(s)',
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
                    _SyncStatusPill(
                      label: '~${mergeView.updatedCount} mis à jour',
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
                    _SyncStatusPill(
                      label: '-${mergeView.removedCount} retiré(s)',
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
                    if (mergeView.preservedDesignOnlyCount > 0 &&
                        preview.choice.resolution ==
                            FeatureObjectSyncResolution.smartMerge)
                      _SyncStatusPill(
                        label:
                            '${mergeView.preservedDesignOnlyCount} ajout(s) local(aux) conservé(s)',
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
                    if (mergeView.conflictCount > 0)
                      _SyncStatusPill(
                        label: '${mergeView.conflictCount} conflit(s)',
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
              if (preview.localImpactedArtifactWarnings.isNotEmpty)
                Container(
                  key: const ValueKey('import-sync-preview-local-warnings'),
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
                          Expanded(
                            child: Text(
                              'Impacts locaux RG / UX / QA (${preview.localImpactedArtifactWarnings.length})',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      for (final warning
                          in preview.localImpactedArtifactWarnings)
                        Text('• $warning', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              if (mergeView != null && mergeView.warnings.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        'Notes de fusion (${mergeView.warnings.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      for (final w in mergeView.warnings)
                        Text('• $w', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              if (decisions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text(
                    'Aucune différence d’attribut détectée entre la source et la Feature active.',
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
                      for (var i = 0; i < decisions.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: colors.outlineVariant.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        Builder(
                          builder: (_) {
                            final d = decisions[i];
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
                                      _SyncStatusPill(
                                        label: palette.label,
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
          key: const ValueKey('import-sync-preview-close-btn'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _FeatureStatusBadge extends StatelessWidget {
  const _FeatureStatusBadge({required this.status});

  final SpecPortfolioStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final (bg, fg, border, icon) = switch (status) {
      SpecPortfolioStatus.validated => (
        Colors.green.withValues(alpha: isDark ? 0.22 : 0.12),
        isDark ? Colors.green.shade200 : Colors.green.shade800,
        Colors.green.withValues(alpha: isDark ? 0.48 : 0.34),
        Icons.verified_rounded,
      ),
      SpecPortfolioStatus.inProgress => (
        Colors.blue.withValues(alpha: isDark ? 0.22 : 0.12),
        isDark ? Colors.lightBlue.shade200 : Colors.blue.shade800,
        Colors.blue.withValues(alpha: isDark ? 0.48 : 0.34),
        Icons.timelapse_rounded,
      ),
      SpecPortfolioStatus.draft => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        colors.outlineVariant,
        Icons.edit_note_rounded,
      ),
      SpecPortfolioStatus.archived => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        colors.outlineVariant,
        Icons.inventory_2_outlined,
      ),
    };

    return _SyncStatusPill(
      label: status.label,
      icon: icon,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: border,
    );
  }
}

class _ContractTypeBadge extends StatelessWidget {
  const _ContractTypeBadge({required this.contractType});

  final String contractType;

  static Color _colorFor(String rawType) {
    return switch (rawType.trim().toLowerCase()) {
      'model' => const Color(0xFF2563EB),
      'component' => const Color(0xFF0D9488),
      'part' => const Color(0xFF7C3AED),
      'eventxpayloaddto' || 'eventxenvelopedto' => const Color(0xFFD97706),
      _ => const Color(0xFF4F46E5),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = _colorFor(contractType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: isDark ? 0.22 : 0.11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: base.withValues(alpha: isDark ? 0.48 : 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: base, shape: BoxShape.circle),
            child: const SizedBox(width: 6, height: 6),
          ),
          Text(
            contractType,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white.withValues(alpha: 0.9) : base,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusPill extends StatelessWidget {
  const _SyncStatusPill({
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
