/// Atelier structuré de l'étape QA 3 : Suites TDD unitaires, contrats techniques
/// et progression Red → Green → Refactor ([QaTddEditorView]).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/qa/qa_forge_stage.dart';
import '../../models/qa/tdd_suite_spec.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_forge_stage.dart';
import '../../models/ux/ux_screen_spec.dart';
import '../../services/spec_forge_controller.dart';

/// Vue Maître / Détail permettant de concevoir, filtrer, amorcer depuis les
/// règles `RG-xxx` et ordonner les suites et cas unitaires TDD ([TddTestSuiteSpec]).
class QaTddEditorView extends StatefulWidget {
  /// Construit l'atelier d'édition des suites TDD connecté au [controller].
  const QaTddEditorView({
    required this.controller,
    this.onJumpToSpecStage,
    super.key,
  });

  /// Contrôleur principal orchestrant l'état du projet et l'historique Undo/Redo.
  final SpecForgeController controller;

  /// Callback optionnel de navigation croisée vers une étape du wizard métier ([SpecForgeStage]).
  final void Function(SpecForgeStage stage, {String? objectId})?
  onJumpToSpecStage;

  @override
  State<QaTddEditorView> createState() => _QaTddEditorViewState();
}

class _QaTddEditorViewState extends State<QaTddEditorView> {
  TddTargetLayer? _layerFilter;

  String _generateShortId(String prefix) {
    final raw = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final token = raw.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : raw;
    return '${prefix}_$token';
  }

  String _nextSuiteCode(List<TddTestSuiteSpec> existing) {
    final pattern = RegExp(r'^TDD-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final suite in existing) {
      final match = pattern.firstMatch(suite.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'TDD-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  String _nextCaseCode(List<TddTestCaseSpec> existing) {
    final pattern = RegExp(r'^TC-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final testCase in existing) {
      final match = pattern.firstMatch(testCase.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'TC-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  String _nextRuleCode(List<BusinessRuleSpec> existing) {
    final pattern = RegExp(r'^RG-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final rule in existing) {
      final match = pattern.firstMatch(rule.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'RG-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  List<TddTestCaseSpec> _orderedCases(List<TddTestCaseSpec> cases) {
    final copy = List<TddTestCaseSpec>.from(cases);
    copy.sort((a, b) => a.order.compareTo(b.order));
    return copy;
  }

  List<TddTestCaseSpec> _normalizedCases(List<TddTestCaseSpec> cases) => [
    for (var i = 0; i < cases.length; i++) cases[i].copyWith(order: i + 1),
  ];

  BusinessObjectSpec? _resolveObject(SpecForgeProject project, String rawRef) {
    if (rawRef.trim().isEmpty) return null;
    return project.findBusinessObject(rawRef);
  }

  SpecModule? _resolveModule(SpecForgeProject project, String moduleId) {
    final needle = moduleId.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final mod in project.cahierDesCharges.modules) {
      if (mod.id.toLowerCase() == needle || mod.name.toLowerCase() == needle) {
        return mod;
      }
    }
    return null;
  }

  BusinessRuleSpec? _resolveRule(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final rule in project.businessRules) {
      if (rule.id.toLowerCase() == needle ||
          rule.code.toLowerCase() == needle) {
        return rule;
      }
    }
    return null;
  }

  String _resolveRequirementLabel(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    for (final exf in project.cahierDesCharges.functionalRequirements) {
      if (exf.id.toLowerCase() == needle || exf.code.toLowerCase() == needle) {
        return '${exf.code} · ${exf.title}';
      }
    }
    for (final enf in project.cahierDesCharges.nonFunctionalRequirements) {
      if (enf.id.toLowerCase() == needle || enf.code.toLowerCase() == needle) {
        return '${enf.code} · ${enf.title}';
      }
    }
    return ref;
  }

  UxScreenSpec? _resolveScreen(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final screen in project.uxSpec.screens) {
      if (screen.id.toLowerCase() == needle ||
          screen.code.toLowerCase() == needle ||
          screen.name.toLowerCase() == needle) {
        return screen;
      }
    }
    return null;
  }

  Future<void> _seedSuitesFromRules(BuildContext context) async {
    final addedCount = await widget.controller.seedQaTddSuitesFromRules();
    if (!context.mounted) return;
    final updatedProject = widget.controller.project;
    if (addedCount > 0 &&
        updatedProject != null &&
        updatedProject.qaSpec.tddSuites.isNotEmpty &&
        widget.controller.focusedTddSuiteId == null) {
      widget.controller.focusQaItem(
        tddSuiteId: updatedProject.qaSpec.tddSuites.first.id,
      );
    }
    final message = addedCount > 0
        ? '$addedCount suite${addedCount > 1 ? 's' : ''} TDD générée${addedCount > 1 ? 's' : ''} depuis les règles RG-xxx.'
        : 'Aucune nouvelle suite TDD à générer (règles RG déjà couvertes ou absentes).';
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveSuite(
    SpecForgeProject project,
    TddTestSuiteSpec suite, {
    bool focusAfterSave = false,
  }) async {
    final list = List<TddTestSuiteSpec>.from(project.qaSpec.tddSuites);
    final idx = list.indexWhere((s) => s.id == suite.id);
    if (idx >= 0) {
      list[idx] = suite;
    } else {
      list.add(suite);
    }
    await widget.controller.updateQaSpec(
      project.qaSpec.copyWith(tddSuites: list),
    );
    if (focusAfterSave) {
      widget.controller.focusQaItem(tddSuiteId: suite.id);
    }
  }

  Future<void> _deleteSuite(
    SpecForgeProject project,
    TddTestSuiteSpec suite,
  ) async {
    final remaining = project.qaSpec.tddSuites
        .where((s) => s.id != suite.id)
        .toList();
    await widget.controller.updateQaSpec(
      project.qaSpec.copyWith(tddSuites: remaining),
    );
    if (widget.controller.focusedTddSuiteId == suite.id) {
      widget.controller.focusQaItem(tddSuiteId: remaining.firstOrNull?.id);
    }
  }

  Future<void> _openSuiteDialog(
    BuildContext context,
    SpecForgeProject project, {
    TddTestSuiteSpec? existing,
  }) async {
    final suggestedCode =
        existing?.code ?? _nextSuiteCode(project.qaSpec.tddSuites);
    final result = await showDialog<TddTestSuiteSpec>(
      context: context,
      builder: (_) => _TddSuiteFormDialog(
        project: project,
        existing: existing,
        suggestedCode: suggestedCode,
        generatedId: existing?.id ?? _generateShortId('tdd'),
        defaultLayer: _layerFilter,
      ),
    );
    if (result == null || !mounted) return;
    final freshProject = widget.controller.project ?? project;
    await _saveSuite(freshProject, result, focusAfterSave: existing == null);
  }

  Future<void> _openQuickAddRuleDialog(
    BuildContext context,
    SpecForgeProject project,
    TddTestSuiteSpec? selectedSuite,
  ) async {
    final preselectedObj = selectedSuite != null
        ? _resolveObject(project, selectedSuite.targetObjectId)
        : null;
    final created = await showDialog<BusinessRuleSpec>(
      context: context,
      builder: (_) => _QuickAddBusinessRuleDialog(
        project: project,
        suggestedCode: _nextRuleCode(project.businessRules),
        generatedId: _generateShortId('rule'),
        initialTargetObjectId: preselectedObj?.id,
      ),
    );
    if (created == null || !mounted) return;
    await widget.controller.upsertBusinessRuleFromUx(created);
  }

  Future<void> _openCaseDialog(
    BuildContext context,
    SpecForgeProject project,
    TddTestSuiteSpec suite, {
    TddTestCaseSpec? existing,
  }) async {
    final ordered = _orderedCases(suite.cases);
    final suggestedCode = existing?.code ?? _nextCaseCode(ordered);
    final result = await showDialog<TddTestCaseSpec>(
      context: context,
      builder: (_) => _TddCaseFormDialog(
        project: project,
        existing: existing,
        suggestedCode: suggestedCode,
        generatedId: existing?.id ?? _generateShortId('tc'),
        nextOrder: existing?.order ?? (ordered.length + 1),
      ),
    );
    if (result == null || !mounted) return;
    final freshProject = widget.controller.project ?? project;
    final freshSuite =
        freshProject.qaSpec.tddSuites
            .where((s) => s.id == suite.id)
            .firstOrNull ??
        suite;
    final currentCases = _orderedCases(freshSuite.cases);
    final idx = currentCases.indexWhere((c) => c.id == result.id);
    if (idx >= 0) {
      currentCases[idx] = result;
    } else {
      currentCases.add(result);
    }
    await _saveSuite(
      freshProject,
      freshSuite.copyWith(cases: _normalizedCases(currentCases)),
    );
  }

  Future<void> _moveCase(
    SpecForgeProject project,
    TddTestSuiteSpec suite,
    int index,
    int delta,
  ) async {
    final ordered = _orderedCases(suite.cases);
    final target = index + delta;
    if (index < 0 ||
        index >= ordered.length ||
        target < 0 ||
        target >= ordered.length) {
      return;
    }
    final moved = ordered.removeAt(index);
    ordered.insert(target, moved);
    await _saveSuite(project, suite.copyWith(cases: _normalizedCases(ordered)));
  }

  Future<void> _deleteCase(
    SpecForgeProject project,
    TddTestSuiteSpec suite,
    String caseId,
  ) async {
    final remaining = _orderedCases(suite.cases)
        .where((c) => c.id != caseId)
        .toList();
    await _saveSuite(
      project,
      suite.copyWith(cases: _normalizedCases(remaining)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      key: const ValueKey('qa-tdd-editor-view'),
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        if (project == null) return const SizedBox.shrink();

        final allSuites = project.qaSpec.tddSuites;
        final filteredSuites = _layerFilter == null
            ? allSuites
            : allSuites.where((s) => s.layer == _layerFilter).toList();

        final focusedId = widget.controller.focusedTddSuiteId;
        final selectedSuite = filteredSuites.isEmpty
            ? null
            : (filteredSuites
                      .where(
                        (s) =>
                            s.id == focusedId ||
                            (focusedId != null &&
                                focusedId.isNotEmpty &&
                                s.code.toLowerCase() ==
                                    focusedId.toLowerCase()),
                      )
                      .firstOrNull ??
                  filteredSuites.first);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              context,
              project: project,
              selectedSuite: selectedSuite,
              filteredCount: filteredSuites.length,
              totalCount: allSuites.length,
            ),
            const Divider(height: 1),
            Expanded(
              child: allSuites.isEmpty
                  ? _buildEmptyState(context, project)
                  : filteredSuites.isEmpty
                  ? _buildFilteredEmptyState(context)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final masterPane = _buildMasterList(
                          context,
                          project: project,
                          suites: filteredSuites,
                          selectedSuiteId: selectedSuite?.id,
                        );
                        final detailPane = selectedSuite == null
                            ? const SizedBox.shrink()
                            : _buildDetailView(
                                context,
                                project: project,
                                suite: selectedSuite,
                              );

                        if (constraints.maxWidth >= 720) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 270, child: masterPane),
                              const VerticalDivider(width: 1),
                              Expanded(child: detailPane),
                            ],
                          );
                        }

                        final listHeight = constraints.maxHeight.isFinite
                            ? math.min(
                                210.0,
                                math.max(110.0, constraints.maxHeight * 0.34),
                              )
                            : 200.0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: listHeight, child: masterPane),
                            const Divider(height: 1),
                            Expanded(child: detailPane),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required SpecForgeProject project,
    required TddTestSuiteSpec? selectedSuite,
    required int filteredCount,
    required int totalCount,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Icon(Icons.science_outlined, size: 22, color: colors.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Suites TDD Unitaires & Contrats',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _layerFilter == null
                          ? '$totalCount'
                          : '$filteredCount/$totalCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('qa-seed-tdd-btn'),
                    onPressed: () => _seedSuitesFromRules(context),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                    label: const Text(
                      'Générer depuis les règles RG-xxx',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('qa-quick-add-rule-btn'),
                    onPressed: () => _openQuickAddRuleDialog(
                      context,
                      project,
                      selectedSuite,
                    ),
                    icon: const Icon(Icons.gavel_rounded, size: 16),
                    label: const Text(
                      '+ Règle RG',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onJumpToSpecStage != null)
                    TextButton.icon(
                      key: const ValueKey('qa-jump-to-business-rules-btn'),
                      onPressed: () => widget.onJumpToSpecStage?.call(
                        SpecForgeStage.businessRules,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Règles RG ↗'),
                    ),
                  FilledButton.icon(
                    key: const ValueKey('qa-add-tdd-suite-btn'),
                    onPressed: () => _openSuiteDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      '+ Nouvelle suite TDD',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Couche :',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ChoiceChip(
                label: const Text('Tous'),
                selected: _layerFilter == null,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _layerFilter = null),
              ),
              for (final layer in TddTargetLayer.values)
                ChoiceChip(
                  label: Text(layer.label),
                  selected: _layerFilter == layer,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(
                    () => _layerFilter = _layerFilter == layer ? null : layer,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, SpecForgeProject project) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.science_outlined,
                      size: 26,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Aucune suite TDD unitaire définie',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Formalisez vos suites de contrats unitaires Arrange / Act / Assert dans un ordre progressif Red → Green → Refactor à partir des règles RG-xxx.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _openSuiteDialog(context, project),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Créer une première suite'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _seedSuitesFromRules(context),
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        label: const Text('Amorcer depuis les règles RG'),
                      ),
                      TextButton.icon(
                        onPressed: widget.controller.isSending
                            ? null
                            : () => widget.controller.kickoffQaStageIfEmpty(
                                QaForgeStage.tddSuites,
                              ),
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                        label: const Text('Démarrer avec le chat IA'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 36,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'Aucune suite TDD dans la couche « ${_layerFilter?.label ?? ''} ».',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _layerFilter = null),
              child: const Text('Afficher toutes les suites'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterList(
    BuildContext context, {
    required SpecForgeProject project,
    required List<TddTestSuiteSpec> suites,
    required String? selectedSuiteId,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: suites.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final suite = suites[index];
        final isSelected = suite.id == selectedSuiteId;
        final targetObj = _resolveObject(project, suite.targetObjectId);
        final objectLabel =
            targetObj?.name ??
            (suite.targetObjectId.trim().isNotEmpty
                ? suite.targetObjectId
                : 'Transverse');

        return Material(
          key: ValueKey('qa-tdd-suite-tile-${suite.id}'),
          color: isSelected
              ? colors.primaryContainer.withValues(alpha: 0.45)
              : colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? colors.primary : colors.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.controller.focusQaItem(tddSuiteId: suite.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.primary
                              : colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          suite.code,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isSelected
                                ? colors.onPrimary
                                : colors.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${suite.cases.length} cas',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    suite.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _TddBadge(
                        icon: _layerIcon(suite.layer),
                        label: suite.layer.label,
                        backgroundColor: colors.tertiaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        foregroundColor: colors.onTertiaryContainer,
                      ),
                      _TddBadge(
                        icon: Icons.category_outlined,
                        label: objectLabel,
                        backgroundColor: colors.surface,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailView(
    BuildContext context, {
    required SpecForgeProject project,
    required TddTestSuiteSpec suite,
  }) {
    final orderedCases = _orderedCases(suite.cases);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSuiteMetadataCard(context, project: project, suite: suite),
          const SizedBox(height: 18),
          _buildRedGreenRefactorSection(
            context,
            project: project,
            suite: suite,
            orderedCases: orderedCases,
          ),
        ],
      ),
    );
  }

  Widget _buildSuiteMetadataCard(
    BuildContext context, {
    required SpecForgeProject project,
    required TddTestSuiteSpec suite,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final targetObj = _resolveObject(project, suite.targetObjectId);
    final targetModule = _resolveModule(project, suite.moduleId);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        suite.code,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _TddBadge(
                      icon: _layerIcon(suite.layer),
                      label: suite.layer.label,
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                    ),
                    if (suite.targetObjectId.trim().isNotEmpty)
                      _TddBadge(
                        icon: Icons.category_outlined,
                        label: targetObj != null
                            ? targetObj.name
                            : suite.targetObjectId,
                        backgroundColor: colors.surfaceContainerHighest,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                    if (suite.moduleId.trim().isNotEmpty)
                      _TddBadge(
                        icon: Icons.folder_outlined,
                        label: targetModule != null
                            ? targetModule.name
                            : suite.moduleId,
                        backgroundColor: colors.surfaceContainerHighest,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                  ],
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    IconButton(
                      key: const ValueKey('qa-edit-tdd-suite-btn'),
                      tooltip: 'Modifier la suite TDD',
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _openSuiteDialog(context, project, existing: suite),
                    ),
                    IconButton(
                      key: const ValueKey('qa-delete-tdd-suite-btn'),
                      tooltip: 'Supprimer la suite TDD',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: colors.error,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteSuite(project, suite),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              suite.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (suite.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                suite.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRedGreenRefactorSection(
    BuildContext context, {
    required SpecForgeProject project,
    required TddTestSuiteSpec suite,
    required List<TddTestCaseSpec> orderedCases,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 20,
                  color: colors.primary,
                ),
                Text(
                  'Progression Red → Green → Refactor',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _TddBadge(
                  label: '${orderedCases.length} cas',
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                ),
              ],
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('qa-add-tdd-case-btn'),
              onPressed: () => _openCaseDialog(context, project, suite),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('+ Ajouter un cas TDD'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (orderedCases.isEmpty)
          Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Aucun cas TDD dans cette suite. Ajoutez des cas Arrange / Act / Assert ordonnés du plus simple au plus complexe.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < orderedCases.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCaseCard(
                context,
                project: project,
                suite: suite,
                testCase: orderedCases[i],
                index: i,
                totalCount: orderedCases.length,
              ),
            ),
      ],
    );
  }

  Widget _buildCaseCard(
    BuildContext context, {
    required SpecForgeProject project,
    required TddTestSuiteSpec suite,
    required TddTestCaseSpec testCase,
    required int index,
    required int totalCount,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final linkedFixture = testCase.fixtureId.trim().isNotEmpty
        ? project.qaSpec.findFixture(testCase.fixtureId)
        : null;
    final isRejection =
        testCase.outcomeKind == TddExpectedOutcomeKind.rejectsWithError ||
        testCase.outcomeKind == TddExpectedOutcomeKind.deniesAction;

    return Card(
      key: ValueKey('qa-tdd-case-card-${testCase.id}'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '#${testCase.order}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        testCase.code,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _TddBadge(
                      icon: isRejection
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      label: testCase.outcomeKind.label,
                      backgroundColor: isRejection
                          ? colors.errorContainer
                          : colors.tertiaryContainer,
                      foregroundColor: isRejection
                          ? colors.onErrorContainer
                          : colors.onTertiaryContainer,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    IconButton(
                      key: ValueKey('qa-tdd-case-up-${testCase.id}'),
                      tooltip: 'Monter dans l’ordre TDD',
                      icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                      visualDensity: VisualDensity.compact,
                      onPressed: index > 0
                          ? () => _moveCase(project, suite, index, -1)
                          : null,
                    ),
                    IconButton(
                      key: ValueKey('qa-tdd-case-down-${testCase.id}'),
                      tooltip: 'Descendre dans l’ordre TDD',
                      icon: const Icon(Icons.arrow_downward_rounded, size: 17),
                      visualDensity: VisualDensity.compact,
                      onPressed: index < totalCount - 1
                          ? () => _moveCase(project, suite, index, 1)
                          : null,
                    ),
                    IconButton(
                      key: ValueKey('qa-edit-tdd-case-${testCase.id}'),
                      tooltip: 'Modifier le cas TDD',
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openCaseDialog(
                        context,
                        project,
                        suite,
                        existing: testCase,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('qa-delete-tdd-case-${testCase.id}'),
                      tooltip: 'Supprimer le cas TDD',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 17,
                        color: colors.error,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteCase(project, suite, testCase.id),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              testCase.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _AaaBlock(
              tag: 'Arrange',
              accentColor: colors.primary,
              content: testCase.arrange.trim().isEmpty
                  ? 'Non renseigné'
                  : testCase.arrange,
              trailingChip: testCase.fixtureId.trim().isEmpty
                  ? null
                  : _TddBadge(
                      icon: Icons.dataset_outlined,
                      label: linkedFixture != null
                          ? '${linkedFixture.code} · ${linkedFixture.name}'
                          : testCase.fixtureId,
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                    ),
            ),
            const SizedBox(height: 6),
            _AaaBlock(
              tag: 'Act',
              accentColor: colors.secondary,
              content: testCase.act.trim().isEmpty
                  ? 'Non renseigné'
                  : testCase.act,
            ),
            const SizedBox(height: 6),
            _AaaBlock(
              tag: 'Assert',
              accentColor: isRejection ? colors.error : colors.tertiary,
              content: testCase.assertExpected.trim().isEmpty
                  ? 'Non renseigné'
                  : testCase.assertExpected,
              errorDetail:
                  (testCase.outcomeKind ==
                              TddExpectedOutcomeKind.rejectsWithError ||
                          testCase.expectedErrorMessage.trim().isNotEmpty) &&
                      testCase.expectedErrorMessage.trim().isNotEmpty
                  ? testCase.expectedErrorMessage
                  : null,
            ),
            if (testCase.businessRuleIds.isNotEmpty ||
                testCase.requirementIds.isNotEmpty ||
                testCase.screenIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ruleRef in testCase.businessRuleIds)
                    Builder(
                      builder: (context) {
                        final rule = _resolveRule(project, ruleRef);
                        return _TddBadge(
                          icon: Icons.gavel_rounded,
                          label: rule != null ? rule.code : ruleRef,
                          backgroundColor: colors.surfaceContainerHighest,
                          foregroundColor: colors.onSurface,
                        );
                      },
                    ),
                  for (final reqRef in testCase.requirementIds)
                    _TddBadge(
                      icon: Icons.checklist_rounded,
                      label: _resolveRequirementLabel(project, reqRef),
                      backgroundColor: colors.secondaryContainer.withValues(
                        alpha: 0.7,
                      ),
                      foregroundColor: colors.onSecondaryContainer,
                    ),
                  for (final screenRef in testCase.screenIds)
                    Builder(
                      builder: (context) {
                        final screen = _resolveScreen(project, screenRef);
                        return _TddBadge(
                          icon: Icons.desktop_windows_outlined,
                          label: screen != null
                              ? '${screen.code} · ${screen.name}'
                              : screenRef,
                          backgroundColor: colors.tertiaryContainer.withValues(
                            alpha: 0.7,
                          ),
                          foregroundColor: colors.onTertiaryContainer,
                        );
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _layerIcon(TddTargetLayer layer) => switch (layer) {
    TddTargetLayer.calculationFormula => Icons.calculate_outlined,
    TddTargetLayer.domainValidation => Icons.verified_user_outlined,
    TddTargetLayer.stateMachine => Icons.sync_alt_rounded,
    TddTargetLayer.permissionPolicy => Icons.admin_panel_settings_outlined,
    TddTargetLayer.schemaContract => Icons.schema_outlined,
    TddTargetLayer.uiBehavior => Icons.widgets_outlined,
  };
}

class _AaaBlock extends StatelessWidget {
  const _AaaBlock({
    required this.tag,
    required this.accentColor,
    required this.content,
    this.trailingChip,
    this.errorDetail,
  });

  final String tag;
  final Color accentColor;
  final String content;
  final Widget? trailingChip;
  final String? errorDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                tag.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              ?trailingChip,
            ],
          ),
          const SizedBox(height: 4),
          Text(content, style: theme.textTheme.bodySmall),
          if (errorDetail != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Message attendu : $errorDetail',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TddBadge extends StatelessWidget {
  const _TddBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.icon,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TddSuiteFormDialog extends StatefulWidget {
  const _TddSuiteFormDialog({
    required this.project,
    required this.existing,
    required this.suggestedCode,
    required this.generatedId,
    this.defaultLayer,
  });

  final SpecForgeProject project;
  final TddTestSuiteSpec? existing;
  final String suggestedCode;
  final String generatedId;
  final TddTargetLayer? defaultLayer;

  @override
  State<_TddSuiteFormDialog> createState() => _TddSuiteFormDialogState();
}

class _TddSuiteFormDialogState extends State<_TddSuiteFormDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late TddTargetLayer _layer;
  late String _targetObjectId;
  late String _moduleId;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeCtrl = TextEditingController(text: widget.suggestedCode);
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _descCtrl = TextEditingController(text: existing?.description ?? '');
    _layer =
        existing?.layer ??
        widget.defaultLayer ??
        TddTargetLayer.domainValidation;
    _targetObjectId = existing?.targetObjectId ?? '';
    _moduleId = existing?.moduleId ?? '';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.isEmpty) {
      setState(() => _nameError = 'L’intitulé de la suite TDD est requis.');
      return;
    }
    final trimmedCode = _codeCtrl.text.trim();
    final suite = TddTestSuiteSpec(
      id: widget.generatedId,
      code: trimmedCode.isEmpty ? widget.suggestedCode : trimmedCode,
      name: trimmedName,
      layer: _layer,
      targetObjectId: _targetObjectId,
      moduleId: _moduleId,
      description: _descCtrl.text.trim(),
      cases: widget.existing?.cases ?? const <TddTestCaseSpec>[],
    );
    Navigator.of(context).pop(suite);
  }

  @override
  Widget build(BuildContext context) {
    final objects = widget.project.businessObjects;
    final modules = widget.project.cahierDesCharges.modules;
    final hasCustomObj =
        _targetObjectId.isNotEmpty &&
        !objects.any((o) => o.id == _targetObjectId);
    final hasCustomModule =
        _moduleId.isNotEmpty && !modules.any((m) => m.id == _moduleId);

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouvelle suite TDD'
            : 'Modifier ${widget.existing!.code}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final codeField = TextField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                  );
                  final layerField = DropdownButtonFormField<TddTargetLayer>(
                    key: ValueKey('suite_layer_${_layer.name}'),
                    initialValue: _layer,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Couche cible',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final layer in TddTargetLayer.values)
                        DropdownMenuItem(
                          value: layer,
                          child: Text(
                            layer.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _layer = val);
                    },
                  );
                  if (constraints.maxWidth >= 400) {
                    return Row(
                      children: [
                        SizedBox(width: 130, child: codeField),
                        const SizedBox(width: 10),
                        Expanded(child: layerField),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      codeField,
                      const SizedBox(height: 10),
                      layerField,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                autofocus: widget.existing == null,
                decoration: InputDecoration(
                  labelText: 'Intitulé de la suite TDD *',
                  errorText: _nameError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('suite_obj_$_targetObjectId'),
                initialValue: _targetObjectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Objet métier cible (optionnel)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Aucun / Transverse',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasCustomObj)
                    DropdownMenuItem(
                      value: _targetObjectId,
                      child: Text(
                        '$_targetObjectId (non catalogué)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final obj in objects)
                    DropdownMenuItem(
                      value: obj.id,
                      child: Text(
                        obj.technicalName.isEmpty
                            ? obj.name
                            : '${obj.name} (${obj.technicalName})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _targetObjectId = val ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('suite_mod_$_moduleId'),
                initialValue: _moduleId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Module fonctionnel (optionnel)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Aucun module rattaché',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasCustomModule)
                    DropdownMenuItem(
                      value: _moduleId,
                      child: Text(
                        '$_moduleId (non catalogué)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final mod in modules)
                    DropdownMenuItem(
                      value: mod.id,
                      child: Text(mod.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) => setState(() => _moduleId = val ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description & stratégie Red → Green → Refactor',
                  border: OutlineInputBorder(),
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
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _TddCaseFormDialog extends StatefulWidget {
  const _TddCaseFormDialog({
    required this.project,
    required this.existing,
    required this.suggestedCode,
    required this.generatedId,
    required this.nextOrder,
  });

  final SpecForgeProject project;
  final TddTestCaseSpec? existing;
  final String suggestedCode;
  final String generatedId;
  final int nextOrder;

  @override
  State<_TddCaseFormDialog> createState() => _TddCaseFormDialogState();
}

class _TddCaseFormDialogState extends State<_TddCaseFormDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _arrangeCtrl;
  late final TextEditingController _actCtrl;
  late final TextEditingController _assertCtrl;
  late final TextEditingController _errorMsgCtrl;
  late String _fixtureId;
  late TddExpectedOutcomeKind _outcomeKind;
  late Set<String> _selectedRuleIds;
  late Set<String> _selectedReqIds;
  late Set<String> _selectedScreenIds;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeCtrl = TextEditingController(text: widget.suggestedCode);
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _arrangeCtrl = TextEditingController(text: existing?.arrange ?? '');
    _actCtrl = TextEditingController(text: existing?.act ?? '');
    _assertCtrl = TextEditingController(text: existing?.assertExpected ?? '');
    _errorMsgCtrl = TextEditingController(
      text: existing?.expectedErrorMessage ?? '',
    );
    _fixtureId = existing?.fixtureId ?? '';
    _outcomeKind = existing?.outcomeKind ?? TddExpectedOutcomeKind.returnsValue;
    _selectedRuleIds = Set<String>.from(existing?.businessRuleIds ?? const []);
    _selectedReqIds = Set<String>.from(existing?.requirementIds ?? const []);
    _selectedScreenIds = Set<String>.from(existing?.screenIds ?? const []);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _arrangeCtrl.dispose();
    _actCtrl.dispose();
    _assertCtrl.dispose();
    _errorMsgCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedTitle = _titleCtrl.text.trim();
    if (trimmedTitle.isEmpty) {
      setState(() => _titleError = 'L’intitulé du cas TDD est requis.');
      return;
    }
    final trimmedCode = _codeCtrl.text.trim();
    final spec = TddTestCaseSpec(
      id: widget.generatedId,
      code: trimmedCode.isEmpty ? widget.suggestedCode : trimmedCode,
      order: widget.nextOrder < 1 ? 1 : widget.nextOrder,
      title: trimmedTitle,
      fixtureId: _fixtureId,
      arrange: _arrangeCtrl.text.trim(),
      act: _actCtrl.text.trim(),
      outcomeKind: _outcomeKind,
      assertExpected: _assertCtrl.text.trim(),
      expectedErrorMessage: _errorMsgCtrl.text.trim(),
      businessRuleIds: _selectedRuleIds.toList(),
      requirementIds: _selectedReqIds.toList(),
      screenIds: _selectedScreenIds.toList(),
    );
    Navigator.of(context).pop(spec);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixtures = widget.project.qaSpec.fixtures;
    final rules = widget.project.businessRules;
    final requirements = widget.project.cahierDesCharges.functionalRequirements;
    final screens = widget.project.uxSpec.screens;
    final hasCustomFixture =
        _fixtureId.isNotEmpty &&
        !fixtures.any((f) => f.id == _fixtureId || f.code == _fixtureId);

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouveau cas TDD (#${widget.nextOrder})'
            : 'Modifier ${widget.existing!.code}',
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final codeField = TextField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                  );
                  final outcomeDropdown =
                      DropdownButtonFormField<TddExpectedOutcomeKind>(
                        key: ValueKey('tc_outcome_${_outcomeKind.name}'),
                        initialValue: _outcomeKind,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Nature du résultat attendu',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final kind in TddExpectedOutcomeKind.values)
                            DropdownMenuItem(
                              value: kind,
                              child: Text(
                                kind.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _outcomeKind = val);
                        },
                      );
                  if (constraints.maxWidth >= 400) {
                    return Row(
                      children: [
                        SizedBox(width: 130, child: codeField),
                        const SizedBox(width: 10),
                        Expanded(child: outcomeDropdown),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      codeField,
                      const SizedBox(height: 10),
                      outcomeDropdown,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                autofocus: widget.existing == null,
                decoration: InputDecoration(
                  labelText: 'Intitulé du comportement vérifié *',
                  errorText: _titleError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('tc_fixture_$_fixtureId'),
                initialValue: _fixtureId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Fixture d’entrée (Arrange, optionnel)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Aucune fixture liée',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasCustomFixture)
                    DropdownMenuItem(
                      value: _fixtureId,
                      child: Text(
                        '$_fixtureId (non cataloguée)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final f in fixtures)
                    DropdownMenuItem(
                      value: _fixtureId == f.code ? f.code : f.id,
                      child: Text(
                        '${f.code} · ${f.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _fixtureId = val ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _arrangeCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Arrange (préparation du contexte)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _actCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Act (opération ou commande invoquée)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _assertCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Assert (état ou valeur attendue)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_outcomeKind == TddExpectedOutcomeKind.rejectsWithError ||
                  _errorMsgCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _errorMsgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Message ou code d’erreur attendu',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (rules.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Règles de gestion RG couvertes',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final rule in rules)
                      FilterChip(
                        label: Text('${rule.code} · ${rule.title}'),
                        selected:
                            _selectedRuleIds.contains(rule.id) ||
                            _selectedRuleIds.contains(rule.code),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          _selectedRuleIds.remove(rule.id);
                          if (selected) {
                            _selectedRuleIds.add(rule.code);
                          } else {
                            _selectedRuleIds.remove(rule.code);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              if (requirements.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Exigences fonctionnelles liées',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final req in requirements)
                      FilterChip(
                        label: Text('${req.code} · ${req.title}'),
                        selected:
                            _selectedReqIds.contains(req.id) ||
                            _selectedReqIds.contains(req.code),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          _selectedReqIds.remove(req.id);
                          if (selected) {
                            _selectedReqIds.add(req.code);
                          } else {
                            _selectedReqIds.remove(req.code);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              if (screens.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Écrans UX liés',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final scr in screens)
                      FilterChip(
                        label: Text('${scr.code} · ${scr.name}'),
                        selected:
                            _selectedScreenIds.contains(scr.id) ||
                            _selectedScreenIds.contains(scr.code),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          _selectedScreenIds.remove(scr.id);
                          if (selected) {
                            _selectedScreenIds.add(scr.code);
                          } else {
                            _selectedScreenIds.remove(scr.code);
                          }
                        }),
                      ),
                  ],
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
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _QuickAddBusinessRuleDialog extends StatefulWidget {
  const _QuickAddBusinessRuleDialog({
    required this.project,
    required this.suggestedCode,
    required this.generatedId,
    this.initialTargetObjectId,
  });

  final SpecForgeProject project;
  final String suggestedCode;
  final String generatedId;
  final String? initialTargetObjectId;

  @override
  State<_QuickAddBusinessRuleDialog> createState() =>
      _QuickAddBusinessRuleDialogState();
}

class _QuickAddBusinessRuleDialogState
    extends State<_QuickAddBusinessRuleDialog> {
  late final TextEditingController _codeCtrl;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _conditionCtrl = TextEditingController();
  final TextEditingController _effectCtrl = TextEditingController();
  final TextEditingController _errorMsgCtrl = TextEditingController();
  BusinessRuleCategory _category = BusinessRuleCategory.validation;
  BusinessRulePriority _priority = BusinessRulePriority.high;
  late Set<String> _targetObjectIds;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.suggestedCode);
    _targetObjectIds = <String>{
      if (widget.initialTargetObjectId != null &&
          widget.project.businessObjects.any(
            (o) => o.id == widget.initialTargetObjectId,
          ))
        widget.initialTargetObjectId!,
    };
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _conditionCtrl.dispose();
    _effectCtrl.dispose();
    _errorMsgCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedTitle = _titleCtrl.text.trim();
    if (trimmedTitle.isEmpty) {
      setState(() => _titleError = 'L’intitulé de la règle est requis.');
      return;
    }
    final trimmedCode = _codeCtrl.text.trim();
    final created = BusinessRuleSpec(
      id: widget.generatedId,
      code: trimmedCode.isEmpty ? widget.suggestedCode : trimmedCode,
      title: trimmedTitle,
      category: _category,
      priority: _priority,
      targetObjectIds: _targetObjectIds.toList(),
      condition: _conditionCtrl.text.trim(),
      effect: _effectCtrl.text.trim(),
      errorMessage: _errorMsgCtrl.text.trim(),
    );
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final objects = widget.project.businessObjects;

    return AlertDialog(
      title: const Text('Nouvelle règle de gestion RG'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final codeField = TextField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                  );
                  final catDropdown =
                      DropdownButtonFormField<BusinessRuleCategory>(
                        key: ValueKey('rg_cat_${_category.name}'),
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Catégorie',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final cat in BusinessRuleCategory.values)
                            DropdownMenuItem(
                              value: cat,
                              child: Text(
                                cat.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _category = val);
                        },
                      );
                  if (constraints.maxWidth >= 400) {
                    return Row(
                      children: [
                        SizedBox(width: 120, child: codeField),
                        const SizedBox(width: 10),
                        Expanded(child: catDropdown),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      codeField,
                      const SizedBox(height: 10),
                      catDropdown,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<BusinessRulePriority>(
                key: ValueKey('rg_prio_${_priority.name}'),
                initialValue: _priority,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Priorité',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final prio in BusinessRulePriority.values)
                    DropdownMenuItem(
                      value: prio,
                      child: Text(prio.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _priority = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Intitulé de la règle *',
                  errorText: _titleError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _conditionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Condition (Si ...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _effectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Effet ou calcul attendu (Alors ...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _errorMsgCtrl,
                decoration: const InputDecoration(
                  labelText: 'Message d’erreur métier (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (objects.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Objets métiers ciblés',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final obj in objects)
                      FilterChip(
                        label: Text(obj.name),
                        selected: _targetObjectIds.contains(obj.id),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _targetObjectIds.add(obj.id);
                          } else {
                            _targetObjectIds.remove(obj.id);
                          }
                        }),
                      ),
                  ],
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
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
