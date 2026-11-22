/// Atelier structuré de l'étape QA 1 : Jeux de données concrets, cas aux limites
/// JSON Schema et cas d'erreur métier ([QaFixturesEditorView]).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/qa/qa_fixture_spec.dart';
import '../../models/qa/qa_forge_stage.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_vision.dart';
import '../../services/spec_forge_controller.dart';

/// Vue Maître / Détail permettant de concevoir, filtrer, générer depuis les
/// JSON Schemas et inspecter/éditer les jeux de données QA ([QaFixtureSpec]).
class QaFixturesEditorView extends StatefulWidget {
  /// Construit l'atelier d'édition des jeux d'essais QA connecté au [controller].
  const QaFixturesEditorView({required this.controller, super.key});

  /// Contrôleur principal orchestrant l'état du projet et l'historique Undo/Redo.
  final SpecForgeController controller;

  @override
  State<QaFixturesEditorView> createState() => _QaFixturesEditorViewState();
}

class _QaFixturesEditorViewState extends State<QaFixturesEditorView> {
  QaFixtureKind? _kindFilter;
  String? _objectFilterId;

  String _generateShortId(String prefix) {
    final raw = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final token = raw.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : raw;
    return '${prefix}_$token';
  }

  String _nextFixtureCode(List<QaFixtureSpec> existing) {
    final pattern = RegExp(r'^FIX-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final fixture in existing) {
      final match = pattern.firstMatch(fixture.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'FIX-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  BusinessObjectSpec? _resolveObject(SpecForgeProject project, String rawRef) {
    if (rawRef.trim().isEmpty) return null;
    return project.findBusinessObject(rawRef);
  }

  SpecPersona? _resolvePersona(SpecForgeProject project, String personaId) {
    final needle = personaId.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final persona in project.vision.personas) {
      if (persona.id.toLowerCase() == needle ||
          persona.name.toLowerCase() == needle) {
        return persona;
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

  bool _fixtureMatchesObject(
    SpecForgeProject project,
    QaFixtureSpec fixture,
    String objectId,
  ) {
    if (fixture.businessObjectId == objectId) return true;
    final resolved = _resolveObject(project, fixture.businessObjectId);
    return resolved?.id == objectId;
  }

  String _formatPayloadJson(Map<String, Object?> payload) =>
      const JsonEncoder.withIndent('  ').convert(payload);

  Future<void> _seedFromSchemas(BuildContext context) async {
    final addedCount = await widget.controller.seedQaFixturesFromSchema();
    if (!context.mounted) return;
    final updatedProject = widget.controller.project;
    if (addedCount > 0 &&
        updatedProject != null &&
        updatedProject.qaSpec.fixtures.isNotEmpty &&
        widget.controller.focusedFixtureId == null) {
      widget.controller.focusQaItem(
        fixtureId: updatedProject.qaSpec.fixtures.first.id,
      );
    }
    final message = addedCount > 0
        ? '$addedCount fixture${addedCount > 1 ? 's' : ''} générée${addedCount > 1 ? 's' : ''} depuis les JSON Schemas.'
        : 'Aucune nouvelle fixture à générer (objets métiers déjà couverts ou absents).';
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveFixture(
    SpecForgeProject project,
    QaFixtureSpec updated, {
    bool focusAfterSave = false,
  }) async {
    final list = List<QaFixtureSpec>.from(project.qaSpec.fixtures);
    final index = list.indexWhere((f) => f.id == updated.id);
    if (index >= 0) {
      list[index] = updated;
    } else {
      list.add(updated);
    }
    await widget.controller.updateQaSpec(
      project.qaSpec.copyWith(fixtures: list),
    );
    if (focusAfterSave) {
      widget.controller.focusQaItem(fixtureId: updated.id);
    }
  }

  Future<void> _deleteFixture(
    SpecForgeProject project,
    QaFixtureSpec target,
  ) async {
    final remaining = project.qaSpec.fixtures
        .where((f) => f.id != target.id)
        .toList();
    await widget.controller.updateQaSpec(
      project.qaSpec.copyWith(fixtures: remaining),
    );
    if (widget.controller.focusedFixtureId == target.id) {
      widget.controller.focusQaItem(fixtureId: remaining.firstOrNull?.id);
    }
  }

  Future<void> _openFixtureDialog(
    BuildContext context,
    SpecForgeProject project, {
    QaFixtureSpec? existing,
  }) async {
    final suggestedCode =
        existing?.code ?? _nextFixtureCode(project.qaSpec.fixtures);
    final result = await showDialog<QaFixtureSpec>(
      context: context,
      builder: (_) => _FixtureFormDialog(
        project: project,
        existing: existing,
        suggestedCode: suggestedCode,
        generatedId: existing?.id ?? _generateShortId('fix'),
        defaultKind: _kindFilter,
        defaultObjectId: _objectFilterId,
      ),
    );
    if (result == null || !mounted) return;
    final freshProject = widget.controller.project ?? project;
    await _saveFixture(freshProject, result, focusAfterSave: existing == null);
  }

  Future<void> _openJsonPayloadDialog(
    BuildContext context,
    SpecForgeProject project,
    QaFixtureSpec fixture,
  ) async {
    final updatedPayload = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _FixturePayloadJsonDialog(
        fixtureCode: fixture.code,
        initialJson: _formatPayloadJson(fixture.payload),
      ),
    );
    if (updatedPayload == null || !mounted) return;
    final freshProject = widget.controller.project ?? project;
    final freshFixture =
        freshProject.qaSpec.fixtures
            .where((f) => f.id == fixture.id)
            .firstOrNull ??
        fixture;
    await _saveFixture(
      freshProject,
      freshFixture.copyWith(payload: updatedPayload),
    );
  }

  Future<void> _copyPayloadJson(
    BuildContext context,
    QaFixtureSpec fixture,
  ) async {
    final formatted = _formatPayloadJson(fixture.payload);
    await Clipboard.setData(ClipboardData(text: formatted));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Payload JSON de ${fixture.code} copié dans le presse-papiers.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      key: const ValueKey('qa-fixtures-editor-view'),
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        if (project == null) return const SizedBox.shrink();

        final allFixtures = project.qaSpec.fixtures;
        final objects = project.businessObjects;
        final effectiveObjectFilter =
            _objectFilterId != null &&
                objects.any((o) => o.id == _objectFilterId)
            ? _objectFilterId
            : null;

        final filteredFixtures = allFixtures.where((f) {
          if (_kindFilter != null && f.kind != _kindFilter) return false;
          if (effectiveObjectFilter != null &&
              !_fixtureMatchesObject(project, f, effectiveObjectFilter)) {
            return false;
          }
          return true;
        }).toList();

        final focusedId = widget.controller.focusedFixtureId;
        final selectedFixture = filteredFixtures.isEmpty
            ? null
            : (filteredFixtures
                      .where(
                        (f) =>
                            f.id == focusedId ||
                            (focusedId != null &&
                                focusedId.isNotEmpty &&
                                f.code.toLowerCase() ==
                                    focusedId.toLowerCase()),
                      )
                      .firstOrNull ??
                  filteredFixtures.first);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              context,
              project: project,
              objects: objects,
              effectiveObjectFilter: effectiveObjectFilter,
              filteredCount: filteredFixtures.length,
              totalCount: allFixtures.length,
            ),
            const Divider(height: 1),
            Expanded(
              child: allFixtures.isEmpty
                  ? _buildEmptyState(context, project)
                  : filteredFixtures.isEmpty
                  ? _buildFilteredEmptyState(context)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final masterPane = _buildMasterList(
                          context,
                          project: project,
                          fixtures: filteredFixtures,
                          selectedFixtureId: selectedFixture?.id,
                        );
                        final detailPane = selectedFixture == null
                            ? const SizedBox.shrink()
                            : _buildDetailView(
                                context,
                                project: project,
                                fixture: selectedFixture,
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
    required List<BusinessObjectSpec> objects,
    required String? effectiveObjectFilter,
    required int filteredCount,
    required int totalCount,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasActiveFilter = _kindFilter != null || effectiveObjectFilter != null;

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
                  Icon(
                    Icons.dataset_outlined,
                    size: 22,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Jeux de données & Cas aux limites',
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
                      hasActiveFilter
                          ? '$filteredCount/$totalCount'
                          : '$totalCount',
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
                    key: const ValueKey('qa-seed-fixtures-btn'),
                    onPressed: () => _seedFromSchemas(context),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                    label: const Text(
                      'Générer depuis les JSON Schemas',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('qa-add-fixture-btn'),
                    onPressed: () => _openFixtureDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      '+ Nouvelle fixture',
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
                'Catégorie :',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ChoiceChip(
                label: const Text('Tous'),
                selected: _kindFilter == null,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _kindFilter = null),
              ),
              for (final kind in QaFixtureKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _kindFilter == kind,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(
                    () => _kindFilter = _kindFilter == kind ? null : kind,
                  ),
                ),
            ],
          ),
          if (objects.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Objet métier :',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: effectiveObjectFilter == null,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _objectFilterId = null),
                ),
                for (final obj in objects)
                  ChoiceChip(
                    label: Text(obj.name),
                    selected: effectiveObjectFilter == obj.id,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(
                      () => _objectFilterId = effectiveObjectFilter == obj.id
                          ? null
                          : obj.id,
                    ),
                  ),
              ],
            ),
          ],
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
          constraints: const BoxConstraints(maxWidth: 500),
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
                      Icons.dataset_outlined,
                      size: 26,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Aucun jeu de données QA défini',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Préparez des fixtures JSON nominales, aux bornes des contraintes JSON Schema et invalides pour alimenter vos scénarios Gherkin et vos suites TDD.',
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
                        onPressed: () => _openFixtureDialog(context, project),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Créer une première fixture'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _seedFromSchemas(context),
                        icon: const Icon(
                          Icons.auto_fix_high_rounded,
                          size: 18,
                        ),
                        label: const Text('Amorcer depuis les schémas'),
                      ),
                      TextButton.icon(
                        onPressed: widget.controller.isSending
                            ? null
                            : () => widget.controller.kickoffQaStageIfEmpty(
                                QaForgeStage.testFixtures,
                              ),
                        icon: const Icon(
                          Icons.auto_awesome_outlined,
                          size: 18,
                        ),
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
              'Aucune fixture ne correspond aux filtres sélectionnés.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() {
                _kindFilter = null;
                _objectFilterId = null;
              }),
              child: const Text('Réinitialiser les filtres'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterList(
    BuildContext context, {
    required SpecForgeProject project,
    required List<QaFixtureSpec> fixtures,
    required String? selectedFixtureId,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: fixtures.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final fixture = fixtures[index];
        final isSelected = fixture.id == selectedFixtureId;
        final targetObj = _resolveObject(project, fixture.businessObjectId);
        final objectLabel = targetObj?.name ??
            (fixture.businessObjectId.trim().isNotEmpty
                ? fixture.businessObjectId
                : 'Objet global');

        return Material(
          key: ValueKey('qa-fixture-tile-${fixture.id}'),
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
            onTap: () => widget.controller.focusQaItem(fixtureId: fixture.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          color: isSelected
                              ? colors.primary
                              : colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          fixture.code,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isSelected
                                ? colors.onPrimary
                                : colors.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _FixtureBadge(
                        icon: fixture.expectedValid
                            ? Icons.check_circle_outline_rounded
                            : Icons.cancel_outlined,
                        label: fixture.expectedValid ? 'Valide' : 'Invalide',
                        backgroundColor: fixture.expectedValid
                            ? colors.tertiaryContainer
                            : colors.errorContainer,
                        foregroundColor: fixture.expectedValid
                            ? colors.onTertiaryContainer
                            : colors.onErrorContainer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fixture.name,
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
                      _FixtureBadge(
                        icon: _kindIcon(fixture.kind),
                        label: fixture.kind.label,
                        backgroundColor: colors.surfaceContainerHighest,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                      _FixtureBadge(
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
    required QaFixtureSpec fixture,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetadataCard(context, project: project, fixture: fixture),
          const SizedBox(height: 16),
          _buildPayloadCard(context, project: project, fixture: fixture),
        ],
      ),
    );
  }

  Widget _buildMetadataCard(
    BuildContext context, {
    required SpecForgeProject project,
    required QaFixtureSpec fixture,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final objects = project.businessObjects;
    final personas = project.vision.personas;

    final resolvedObject = _resolveObject(project, fixture.businessObjectId);
    final effectiveObjectId =
        resolvedObject?.id ?? fixture.businessObjectId.trim();
    final hasUncataloguedObject =
        effectiveObjectId.isNotEmpty &&
        !objects.any((o) => o.id == effectiveObjectId);

    final resolvedPersona = _resolvePersona(project, fixture.personaId);
    final effectivePersonaId = resolvedPersona?.id ?? fixture.personaId.trim();
    final hasUncataloguedPersona =
        effectivePersonaId.isNotEmpty &&
        !personas.any((p) => p.id == effectivePersonaId);

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
                        fixture.code,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _FixtureBadge(
                      icon: _kindIcon(fixture.kind),
                      label: fixture.kind.label,
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                    ),
                    _FixtureBadge(
                      icon: fixture.expectedValid
                          ? Icons.verified_outlined
                          : Icons.error_outline_rounded,
                      label: fixture.expectedValid
                          ? 'Attendu : Valide'
                          : 'Attendu : Rejeté',
                      backgroundColor: fixture.expectedValid
                          ? colors.tertiaryContainer
                          : colors.errorContainer,
                      foregroundColor: fixture.expectedValid
                          ? colors.onTertiaryContainer
                          : colors.onErrorContainer,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    IconButton(
                      key: const ValueKey('qa-edit-fixture-btn'),
                      tooltip: 'Modifier la fixture',
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openFixtureDialog(
                        context,
                        project,
                        existing: fixture,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('qa-delete-fixture-btn'),
                      tooltip: 'Supprimer la fixture',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: colors.error,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteFixture(project, fixture),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              fixture.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (fixture.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                fixture.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final objectDropdown = DropdownButtonFormField<String>(
                  key: ValueKey('fixture_obj_${fixture.id}_$effectiveObjectId'),
                  initialValue: effectiveObjectId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Objet métier cible',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text(
                        'Aucun objet spécifique',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasUncataloguedObject)
                      DropdownMenuItem(
                        value: effectiveObjectId,
                        child: Text(
                          '$effectiveObjectId (non catalogué)',
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
                  onChanged: (nextVal) {
                    final nextId = nextVal ?? '';
                    if (nextId == fixture.businessObjectId) return;
                    _saveFixture(
                      project,
                      fixture.copyWith(businessObjectId: nextId),
                    );
                  },
                );

                final personaDropdown = DropdownButtonFormField<String>(
                  key: ValueKey(
                    'fixture_persona_${fixture.id}_$effectivePersonaId',
                  ),
                  initialValue: effectivePersonaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Persona associé',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text(
                        'Tous personas / Non spécifique',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasUncataloguedPersona)
                      DropdownMenuItem(
                        value: effectivePersonaId,
                        child: Text(
                          '$effectivePersonaId (non catalogué)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final persona in personas)
                      DropdownMenuItem(
                        value: persona.id,
                        child: Text(
                          persona.role.isEmpty
                              ? persona.name
                              : '${persona.name} (${persona.role})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (nextVal) {
                    final nextId = nextVal ?? '';
                    if (nextId == fixture.personaId) return;
                    _saveFixture(project, fixture.copyWith(personaId: nextId));
                  },
                );

                if (constraints.maxWidth >= 520) {
                  return Row(
                    children: [
                      Expanded(child: objectDropdown),
                      const SizedBox(width: 12),
                      Expanded(child: personaDropdown),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    objectDropdown,
                    const SizedBox(height: 10),
                    personaDropdown,
                  ],
                );
              },
            ),
            if (!fixture.expectedValid ||
                fixture.expectedErrorHint.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colors.onErrorContainer,
                    ),
                    Text(
                      fixture.expectedErrorHint.trim().isEmpty
                          ? 'Erreur ou rejet attendu (aucun message précis renseigné).'
                          : 'Erreur attendue : ${fixture.expectedErrorHint}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (fixture.businessRuleIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Règles de gestion exercées',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ruleRef in fixture.businessRuleIds)
                    Builder(
                      builder: (context) {
                        final rule = _resolveRule(project, ruleRef);
                        return Tooltip(
                          message: rule != null
                              ? '${rule.code} — ${rule.title}'
                              : ruleRef,
                          child: _FixtureBadge(
                            icon: Icons.gavel_rounded,
                            label: rule != null
                                ? '${rule.code} · ${rule.title}'
                                : ruleRef,
                            backgroundColor: rule != null
                                ? colors.surfaceContainerHighest
                                : colors.errorContainer,
                            foregroundColor: rule != null
                                ? colors.onSurface
                                : colors.onErrorContainer,
                          ),
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

  Widget _buildPayloadCard(
    BuildContext context, {
    required SpecForgeProject project,
    required QaFixtureSpec fixture,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formattedJson = _formatPayloadJson(fixture.payload);

    return Card(
      key: const ValueKey('qa-fixture-payload-card'),
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
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.data_object_rounded,
                      size: 19,
                      color: colors.primary,
                    ),
                    Text(
                      'Payload JSON',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _FixtureBadge(
                      label:
                          '${fixture.payload.length} champ${fixture.payload.length > 1 ? 's' : ''}',
                      backgroundColor: colors.surfaceContainerHighest,
                      foregroundColor: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('qa-copy-fixture-json-btn'),
                      onPressed: () => _copyPayloadJson(context, fixture),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copier'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('qa-edit-fixture-json-btn'),
                      onPressed: () =>
                          _openJsonPayloadDialog(context, project, fixture),
                      icon: const Icon(Icons.code_rounded, size: 16),
                      label: const Text('Éditer le JSON'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: SelectableText(
                formattedJson,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(QaFixtureKind kind) => switch (kind) {
    QaFixtureKind.nominal => Icons.check_circle_outline_rounded,
    QaFixtureKind.boundary => Icons.straighten_rounded,
    QaFixtureKind.invalid => Icons.block_rounded,
    QaFixtureKind.permission => Icons.admin_panel_settings_outlined,
    QaFixtureKind.lifecycle => Icons.sync_alt_rounded,
  };
}

class _FixtureBadge extends StatelessWidget {
  const _FixtureBadge({
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

class _FixtureFormDialog extends StatefulWidget {
  const _FixtureFormDialog({
    required this.project,
    required this.existing,
    required this.suggestedCode,
    required this.generatedId,
    this.defaultKind,
    this.defaultObjectId,
  });

  final SpecForgeProject project;
  final QaFixtureSpec? existing;
  final String suggestedCode;
  final String generatedId;
  final QaFixtureKind? defaultKind;
  final String? defaultObjectId;

  @override
  State<_FixtureFormDialog> createState() => _FixtureFormDialogState();
}

class _FixtureFormDialogState extends State<_FixtureFormDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _errorHintCtrl;
  late QaFixtureKind _kind;
  late String _businessObjectId;
  late String _personaId;
  late bool _expectedValid;
  late Set<String> _selectedRuleIds;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeCtrl = TextEditingController(text: widget.suggestedCode);
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _descCtrl = TextEditingController(text: existing?.description ?? '');
    _errorHintCtrl = TextEditingController(
      text: existing?.expectedErrorHint ?? '',
    );
    _kind = existing?.kind ?? widget.defaultKind ?? QaFixtureKind.nominal;
    _businessObjectId =
        existing?.businessObjectId ?? widget.defaultObjectId ?? '';
    _personaId = existing?.personaId ?? '';
    _expectedValid = existing != null
        ? existing.expectedValid
        : _kind != QaFixtureKind.invalid;
    _selectedRuleIds = Set<String>.from(existing?.businessRuleIds ?? const []);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _errorHintCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.isEmpty) {
      setState(() => _nameError = 'L’intitulé de la fixture est requis.');
      return;
    }
    final trimmedCode = _codeCtrl.text.trim();
    final spec = QaFixtureSpec(
      id: widget.generatedId,
      code: trimmedCode.isEmpty ? widget.suggestedCode : trimmedCode,
      name: trimmedName,
      kind: _kind,
      businessObjectId: _businessObjectId,
      personaId: _personaId,
      businessRuleIds: _selectedRuleIds.toList(),
      description: _descCtrl.text.trim(),
      payload: widget.existing?.payload ?? const <String, Object?>{},
      expectedValid: _expectedValid,
      expectedErrorHint: _errorHintCtrl.text.trim(),
    );
    Navigator.of(context).pop(spec);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final objects = widget.project.businessObjects;
    final personas = widget.project.vision.personas;
    final rules = widget.project.businessRules;

    final hasCustomObj =
        _businessObjectId.isNotEmpty &&
        !objects.any((o) => o.id == _businessObjectId);
    final hasCustomPersona =
        _personaId.isNotEmpty && !personas.any((p) => p.id == _personaId);

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouvelle fixture QA'
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
                  final kindDropdown = DropdownButtonFormField<QaFixtureKind>(
                    key: ValueKey('dlg_kind_${_kind.name}'),
                    initialValue: _kind,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final kind in QaFixtureKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(
                            kind.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _kind = val;
                        if (val == QaFixtureKind.invalid) {
                          _expectedValid = false;
                        }
                      });
                    },
                  );
                  if (constraints.maxWidth >= 400) {
                    return Row(
                      children: [
                        SizedBox(width: 130, child: codeField),
                        const SizedBox(width: 10),
                        Expanded(child: kindDropdown),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      codeField,
                      const SizedBox(height: 10),
                      kindDropdown,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                autofocus: widget.existing == null,
                decoration: InputDecoration(
                  labelText: 'Intitulé de la fixture *',
                  errorText: _nameError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('dlg_obj_$_businessObjectId'),
                initialValue: _businessObjectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Objet métier cible',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Aucun objet spécifique',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasCustomObj)
                    DropdownMenuItem(
                      value: _businessObjectId,
                      child: Text(
                        '$_businessObjectId (non catalogué)',
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
                onChanged: (val) =>
                    setState(() => _businessObjectId = val ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('dlg_persona_$_personaId'),
                initialValue: _personaId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Persona associé',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Tous personas / Non spécifique',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasCustomPersona)
                    DropdownMenuItem(
                      value: _personaId,
                      child: Text(
                        '$_personaId (non catalogué)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final persona in personas)
                    DropdownMenuItem(
                      value: persona.id,
                      child: Text(
                        persona.role.isEmpty
                            ? persona.name
                            : '${persona.name} (${persona.role})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _personaId = val ?? ''),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jeu de données attendu comme valide'),
                subtitle: Text(
                  _expectedValid
                      ? 'Doit passer la validation JSON Schema et métier'
                      : 'Doit être rejeté avec une erreur explicite',
                ),
                value: _expectedValid,
                onChanged: (val) => setState(() => _expectedValid = val),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _errorHintCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code ou message d’erreur attendu (si invalide)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description / Intention de test',
                  border: OutlineInputBorder(),
                ),
              ),
              if (rules.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Règles de gestion RG liées',
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

class _FixturePayloadJsonDialog extends StatefulWidget {
  const _FixturePayloadJsonDialog({
    required this.fixtureCode,
    required this.initialJson,
  });

  final String fixtureCode;
  final String initialJson;

  @override
  State<_FixturePayloadJsonDialog> createState() =>
      _FixturePayloadJsonDialogState();
}

class _FixturePayloadJsonDialogState extends State<_FixturePayloadJsonDialog> {
  late final TextEditingController _jsonCtrl;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _jsonCtrl = TextEditingController(text: widget.initialJson);
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final rawText = _jsonCtrl.text.trim();
    if (rawText.isEmpty) {
      setState(
        () => _validationError = 'Veuillez saisir un objet JSON valide (ex. {}).',
      );
      return;
    }
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is! Map) {
        setState(
          () => _validationError =
              'La racine du payload JSON doit être un objet JSON ({ ... }).',
        );
        return;
      }
      final map = <String, Object?>{
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      };
      Navigator.of(context).pop(map);
    } on FormatException catch (e) {
      setState(() => _validationError = 'JSON invalide : ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Éditer le JSON — ${widget.fixtureCode}'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('qa-fixture-json-textfield'),
                controller: _jsonCtrl,
                autofocus: true,
                minLines: 8,
                maxLines: 18,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  labelText: 'Enregistrement JSON ({ ... })',
                  errorText: _validationError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  }
                },
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
          key: const ValueKey('qa-save-fixture-json-btn'),
          onPressed: _validateAndSubmit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
