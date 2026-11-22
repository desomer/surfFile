/// Atelier structuré de l'étape UX 1 : Parcours utilisateurs bout-en-bout,
/// filtres par persona et timeline interactive des étapes ([UxJourneysEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_vision.dart';
import '../../models/ux/ux_forge_stage.dart';
import '../../models/ux/ux_journey_spec.dart';
import '../../models/ux/ux_navigation_spec.dart';
import '../../services/spec_forge_controller.dart';

/// Vue Maître / Détail permettant de concevoir, filtrer et ordonner les
/// parcours utilisateurs ([UxJourneySpec]) et leurs étapes ([UxJourneyStep]).
class UxJourneysEditorView extends StatefulWidget {
  /// Crée l'atelier des parcours utilisateurs connecté au [controller].
  const UxJourneysEditorView({required this.controller, super.key});

  /// Contrôleur principal orchestrant l'état du projet et l'historique Undo/Redo.
  final SpecForgeController controller;

  @override
  State<UxJourneysEditorView> createState() => _UxJourneysEditorViewState();
}

class _UxJourneysEditorViewState extends State<UxJourneysEditorView> {
  String? _personaFilterId;

  String _generateShortId(String prefix) {
    final raw = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final token = raw.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : raw;
    return '${prefix}_$token';
  }

  String _nextJourneyCode(List<UxJourneySpec> existing) {
    final pattern = RegExp(r'^JRN-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final journey in existing) {
      final match = pattern.firstMatch(journey.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'JRN-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  List<UxJourneyStep> _normalizedSteps(List<UxJourneyStep> steps) => [
    for (var i = 0; i < steps.length; i++) steps[i].copyWith(order: i + 1),
  ];

  List<UxJourneyStep> _orderedSteps(List<UxJourneyStep> steps) {
    final copy = List<UxJourneyStep>.from(steps);
    copy.sort((a, b) => a.order.compareTo(b.order));
    return copy;
  }

  SpecPersona? _findPersona(SpecForgeProject project, String personaId) {
    if (personaId.trim().isEmpty) return null;
    for (final persona in project.vision.personas) {
      if (persona.id == personaId) return persona;
    }
    return null;
  }

  UseCaseSpec? _findUseCase(SpecForgeProject project, String useCaseId) {
    for (final uc in project.cahierDesCharges.useCases) {
      if (uc.id == useCaseId) return uc;
    }
    return null;
  }

  FunctionalRequirement? _findRequirement(
    SpecForgeProject project,
    String reqIdOrCode,
  ) {
    final needle = reqIdOrCode.trim().toLowerCase();
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (req.id.toLowerCase() == needle || req.code.toLowerCase() == needle) {
        return req;
      }
    }
    return null;
  }

  Future<void> _saveJourney(
    SpecForgeProject project,
    UxJourneySpec journey, {
    bool focusAfterSave = false,
  }) async {
    final currentJourneys = List<UxJourneySpec>.from(project.uxSpec.journeys);
    final idx = currentJourneys.indexWhere((j) => j.id == journey.id);
    if (idx >= 0) {
      currentJourneys[idx] = journey;
    } else {
      currentJourneys.add(journey);
    }
    await widget.controller.updateUxSpec(
      project.uxSpec.copyWith(journeys: currentJourneys),
    );
    if (focusAfterSave) {
      widget.controller.focusUxItem(journeyId: journey.id);
    }
  }

  Future<void> _deleteJourney(
    SpecForgeProject project,
    UxJourneySpec journey,
  ) async {
    final nextJourneys = project.uxSpec.journeys
        .where((j) => j.id != journey.id)
        .toList();
    await widget.controller.updateUxSpec(
      project.uxSpec.copyWith(journeys: nextJourneys),
    );
    if (widget.controller.focusedJourneyId == journey.id) {
      widget.controller.focusUxItem(journeyId: nextJourneys.firstOrNull?.id);
    }
  }

  Future<void> _openJourneyDialog(
    BuildContext context,
    SpecForgeProject project, {
    UxJourneySpec? existing,
    String? defaultPersonaId,
  }) async {
    final suggestedCode =
        existing?.code ?? _nextJourneyCode(project.uxSpec.journeys);
    final result = await showDialog<UxJourneySpec>(
      context: context,
      builder: (_) => _JourneyFormDialog(
        project: project,
        existing: existing,
        suggestedCode: suggestedCode,
        generatedId: existing?.id ?? _generateShortId('jrn'),
        defaultPersonaId: defaultPersonaId,
      ),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    await _saveJourney(freshProject, result, focusAfterSave: existing == null);
  }

  Future<void> _openStepDialog(
    BuildContext context,
    SpecForgeProject project,
    UxJourneySpec journey, {
    UxJourneyStep? existing,
  }) async {
    final ordered = _orderedSteps(journey.steps);
    final persona = _findPersona(project, journey.personaId);
    final result = await showDialog<UxJourneyStep>(
      context: context,
      builder: (_) => _JourneyStepFormDialog(
        routes: project.uxSpec.navigation.routes,
        personaPainPoints: persona?.painPoints ?? const <String>[],
        existing: existing,
        generatedId: existing?.id ?? _generateShortId('step'),
        nextOrder: existing?.order ?? (ordered.length + 1),
      ),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    final freshJourney =
        freshProject.uxSpec.journeys
            .where((j) => j.id == journey.id)
            .firstOrNull ??
        journey;
    final currentSteps = _orderedSteps(freshJourney.steps);
    final idx = currentSteps.indexWhere((s) => s.id == result.id);
    if (idx >= 0) {
      currentSteps[idx] = result;
    } else {
      currentSteps.add(result);
    }
    final updatedJourney = freshJourney.copyWith(
      steps: _normalizedSteps(currentSteps),
    );
    await _saveJourney(freshProject, updatedJourney);
  }

  Future<void> _moveStep(
    SpecForgeProject project,
    UxJourneySpec journey,
    int index,
    int delta,
  ) async {
    final ordered = _orderedSteps(journey.steps);
    final target = index + delta;
    if (index < 0 ||
        index >= ordered.length ||
        target < 0 ||
        target >= ordered.length) {
      return;
    }
    final moved = ordered.removeAt(index);
    ordered.insert(target, moved);
    final updatedJourney = journey.copyWith(steps: _normalizedSteps(ordered));
    await _saveJourney(project, updatedJourney);
  }

  Future<void> _deleteStep(
    SpecForgeProject project,
    UxJourneySpec journey,
    String stepId,
  ) async {
    final remaining = _orderedSteps(journey.steps)
        .where((s) => s.id != stepId)
        .toList();
    final updatedJourney = journey.copyWith(steps: _normalizedSteps(remaining));
    await _saveJourney(project, updatedJourney);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      key: const ValueKey('ux-journeys-editor-view'),
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        if (project == null) return const SizedBox.shrink();

        final journeys = project.uxSpec.journeys;
        final personas = project.vision.personas;
        final effectivePersonaFilter =
            _personaFilterId != null &&
                personas.any((p) => p.id == _personaFilterId)
            ? _personaFilterId
            : null;

        final filteredJourneys = effectivePersonaFilter == null
            ? journeys
            : journeys
                  .where((j) => j.personaId == effectivePersonaFilter)
                  .toList();

        final focusedId = widget.controller.focusedJourneyId;
        final selectedJourney = filteredJourneys.isEmpty
            ? null
            : (filteredJourneys.where((j) => j.id == focusedId).firstOrNull ??
                  filteredJourneys.first);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopHeader(
              context,
              project: project,
              personas: personas,
              effectivePersonaFilter: effectivePersonaFilter,
              filteredCount: filteredJourneys.length,
              totalCount: journeys.length,
            ),
            const Divider(height: 1),
            Expanded(
              child: journeys.isEmpty
                  ? _buildEmptyState(context, project)
                  : filteredJourneys.isEmpty
                  ? _buildFilteredEmptyState(
                      context,
                      project,
                      effectivePersonaFilter!,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final masterPane = _buildMasterList(
                          context,
                          project: project,
                          journeys: filteredJourneys,
                          selectedJourneyId: selectedJourney?.id,
                        );
                        final detailPane = selectedJourney == null
                            ? const SizedBox.shrink()
                            : _buildDetailPanel(
                                context,
                                project: project,
                                journey: selectedJourney,
                              );

                        if (constraints.maxWidth >= 580) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 260, child: masterPane),
                              const VerticalDivider(width: 1),
                              Expanded(child: detailPane),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 210, child: masterPane),
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

  Widget _buildTopHeader(
    BuildContext context, {
    required SpecForgeProject project,
    required List<SpecPersona> personas,
    required String? effectivePersonaFilter,
    required int filteredCount,
    required int totalCount,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route_outlined, size: 22, color: colors.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Parcours utilisateurs & Flows',
                      style: theme.textTheme.titleLarge?.copyWith(
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
                      effectivePersonaFilter == null
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
              FilledButton.icon(
                key: const ValueKey('ux-add-journey-btn'),
                onPressed: () => _openJourneyDialog(
                  context,
                  project,
                  defaultPersonaId: effectivePersonaFilter,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('+ Nouveau parcours'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Persona :',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              FilterChip(
                label: const Text('Tous'),
                selected: effectivePersonaFilter == null,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _personaFilterId = null),
              ),
              for (final persona in personas)
                FilterChip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 15),
                  label: Text(persona.name),
                  selected: effectivePersonaFilter == persona.id,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(
                    () =>
                        _personaFilterId = effectivePersonaFilter == persona.id
                        ? null
                        : persona.id,
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
        padding: const EdgeInsets.all(28),
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
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.route_rounded,
                      size: 28,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucun parcours utilisateur formalisé',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cartographiez les flux bout-en-bout par persona (déclencheur, étapes acteur ↔ système, embranchements et critères de succès), ou collaborez avec le User Journey Architect dans le chat IA à gauche.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('ux-empty-create-journey-btn'),
                        onPressed: () => _openJourneyDialog(context, project),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Créer un premier parcours'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.controller.isSending
                            ? null
                            : () => widget.controller.kickoffUxStageIfEmpty(
                                UxForgeStage.userJourneys,
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

  Widget _buildFilteredEmptyState(
    BuildContext context,
    SpecForgeProject project,
    String personaId,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final personaName = _findPersona(project, personaId)?.name ?? personaId;

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
              'Aucun parcours rattaché au persona « $personaName ».',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _personaFilterId = null),
                  child: const Text('Afficher tous les parcours'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openJourneyDialog(
                    context,
                    project,
                    defaultPersonaId: personaId,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text('Créer pour $personaName'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterList(
    BuildContext context, {
    required SpecForgeProject project,
    required List<UxJourneySpec> journeys,
    required String? selectedJourneyId,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: journeys.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final journey = journeys[index];
        final isSelected = journey.id == selectedJourneyId;
        final persona = _findPersona(project, journey.personaId);
        final stepCount = journey.steps.length;

        return Material(
          key: ValueKey('ux-journey-tile-${journey.id}'),
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
            onTap: () => widget.controller.focusUxItem(journeyId: journey.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
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
                            journey.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isSelected
                                  ? colors.onPrimary
                                  : colors.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$stepCount étape${stepCount > 1 ? 's' : ''}',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    journey.name,
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
                      _MiniBadge(
                        icon: Icons.person_outline_rounded,
                        label: persona?.name ?? 'Tous acteurs',
                        backgroundColor: colors.surface,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                      _MiniBadge(
                        icon: _channelIcon(journey.channel),
                        label: journey.channel.label,
                        backgroundColor: colors.tertiaryContainer.withValues(
                          alpha: 0.65,
                        ),
                        foregroundColor: colors.onTertiaryContainer,
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

  Widget _buildDetailPanel(
    BuildContext context, {
    required SpecForgeProject project,
    required UxJourneySpec journey,
  }) {
    final orderedSteps = _orderedSteps(journey.steps);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetadataCard(context, project: project, journey: journey),
          const SizedBox(height: 18),
          _buildTimelineSection(
            context,
            project: project,
            journey: journey,
            orderedSteps: orderedSteps,
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataCard(
    BuildContext context, {
    required SpecForgeProject project,
    required UxJourneySpec journey,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final persona = _findPersona(project, journey.personaId);

    return Card(
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
            LayoutBuilder(
              builder: (context, constraints) {
                final infoColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            journey.code,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _MiniBadge(
                          icon: Icons.person_outline_rounded,
                          label: persona != null
                              ? (persona.role.isEmpty
                                    ? persona.name
                                    : '${persona.name} · ${persona.role}')
                              : 'Tous acteurs',
                          backgroundColor: colors.surfaceContainerHighest,
                          foregroundColor: colors.onSurfaceVariant,
                        ),
                        _MiniBadge(
                          icon: _channelIcon(journey.channel),
                          label: journey.channel.label,
                          backgroundColor: colors.secondaryContainer,
                          foregroundColor: colors.onSecondaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      journey.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
                final actionButtons = Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('ux-edit-journey-btn'),
                      onPressed: () => _openJourneyDialog(
                        context,
                        project,
                        existing: journey,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Modifier'),
                    ),
                    IconButton(
                      key: const ValueKey('ux-delete-journey-btn'),
                      tooltip: 'Supprimer ce parcours',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: colors.error,
                      ),
                      onPressed: () => _deleteJourney(project, journey),
                    ),
                  ],
                );
                if (constraints.maxWidth >= 460) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: infoColumn),
                      const SizedBox(width: 8),
                      actionButtons,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    infoColumn,
                    const SizedBox(height: 8),
                    actionButtons,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final triggerBlock = _MetaInfoBox(
                  icon: Icons.bolt_outlined,
                  label: 'Déclencheur',
                  value: journey.trigger,
                  emptyText: 'Non précisé',
                );
                final goalBlock = _MetaInfoBox(
                  icon: Icons.flag_outlined,
                  label: 'Objectif utilisateur',
                  value: journey.goal,
                  emptyText: 'Non précisé',
                );
                if (constraints.maxWidth >= 520) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: triggerBlock),
                      const SizedBox(width: 12),
                      Expanded(child: goalBlock),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    triggerBlock,
                    const SizedBox(height: 8),
                    goalBlock,
                  ],
                );
              },
            ),
            if (journey.useCaseIds.isNotEmpty ||
                journey.requirementIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ucId in journey.useCaseIds)
                    Chip(
                      avatar: const Icon(
                        Icons.theater_comedy_outlined,
                        size: 15,
                      ),
                      label: Text(_findUseCase(project, ucId)?.title ?? ucId),
                      visualDensity: VisualDensity.compact,
                    ),
                  for (final reqId in journey.requirementIds)
                    Chip(
                      avatar: const Icon(Icons.check_box_outlined, size: 15),
                      label: Text(switch (_findRequirement(project, reqId)) {
                        final req? => '${req.code} · ${req.title}',
                        null => reqId,
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (journey.successCriteria.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Critères de succès UX (${journey.successCriteria.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              for (final criterion in journey.successCriteria)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          criterion,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineSection(
    BuildContext context, {
    required SpecForgeProject project,
    required UxJourneySpec journey,
    required List<UxJourneyStep> orderedSteps,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timeline_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Timeline des étapes (${orderedSteps.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('ux-add-journey-step-btn'),
              onPressed: () => _openStepDialog(context, project, journey),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('+ Ajouter une étape'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (orderedSteps.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.linear_scale_rounded,
                  size: 28,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  'Aucune étape détaillée dans ce parcours.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cliquez sur « + Ajouter une étape » pour décrire les interactions Acteur ↔ Système et les routes associées.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < orderedSteps.length; i++)
            _TimelineStepRow(
              key: ValueKey('ux-journey-step-card-${orderedSteps[i].id}'),
              step: orderedSteps[i],
              stepIndex: i,
              isLast: i == orderedSteps.length - 1,
              resolvedRoute: orderedSteps[i].targetRouteId.isEmpty
                  ? null
                  : project.uxSpec.navigation.findRoute(
                      orderedSteps[i].targetRouteId,
                    ),
              onFocusRoute: (routeId) => widget.controller.focusUxItem(
                journeyId: journey.id,
                routeId: routeId,
              ),
              onMoveUp: i > 0 ? () => _moveStep(project, journey, i, -1) : null,
              onMoveDown: i < orderedSteps.length - 1
                  ? () => _moveStep(project, journey, i, 1)
                  : null,
              onEdit: () => _openStepDialog(
                context,
                project,
                journey,
                existing: orderedSteps[i],
              ),
              onDelete: () => _deleteStep(project, journey, orderedSteps[i].id),
            ),
      ],
    );
  }

  IconData _channelIcon(UxTargetChannel channel) => switch (channel) {
    UxTargetChannel.desktop => Icons.desktop_windows_outlined,
    UxTargetChannel.webResponsive => Icons.language_outlined,
    UxTargetChannel.tablet => Icons.tablet_mac_outlined,
    UxTargetChannel.mobile => Icons.smartphone_outlined,
  };
}

class _TimelineStepRow extends StatelessWidget {
  const _TimelineStepRow({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.isLast,
    required this.resolvedRoute,
    required this.onFocusRoute,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
  });

  final UxJourneyStep step;
  final int stepIndex;
  final bool isLast;
  final UxRouteNode? resolvedRoute;
  final ValueChanged<String> onFocusRoute;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: 17,
            top: 32,
            bottom: 4,
            width: 2,
            child: ColoredBox(color: colors.outlineVariant),
          ),
        Positioned(
          left: 4,
          top: 0,
          width: 28,
          height: 28,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${stepIndex + 1}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 44, bottom: isLast ? 0 : 12),
          child: SizedBox(
            width: double.infinity,
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              step.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (step.targetRouteId.isNotEmpty)
                              ActionChip(
                                avatar: Icon(
                                  resolvedRoute?.pageType.icon ??
                                      Icons.link_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  resolvedRoute != null
                                      ? '${resolvedRoute!.path} · ${resolvedRoute!.title}'
                                      : step.targetRouteId,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: resolvedRoute != null
                                    ? () => onFocusRoute(resolvedRoute!.id)
                                    : null,
                              ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('ux-step-up-btn-${step.id}'),
                              tooltip: 'Monter',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 17,
                              ),
                              onPressed: onMoveUp,
                            ),
                            IconButton(
                              key: ValueKey('ux-step-down-btn-${step.id}'),
                              tooltip: 'Descendre',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.arrow_downward_rounded,
                                size: 17,
                              ),
                              onPressed: onMoveDown,
                            ),
                            IconButton(
                              key: ValueKey('ux-step-edit-btn-${step.id}'),
                              tooltip: 'Modifier l’étape',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              onPressed: onEdit,
                            ),
                            IconButton(
                              key: ValueKey('ux-step-delete-btn-${step.id}'),
                              tooltip: 'Supprimer l’étape',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 17,
                                color: colors.error,
                              ),
                              onPressed: onDelete,
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (step.actorAction.isNotEmpty ||
                        step.systemResponse.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final actorBox = _ExchangePane(
                            icon: Icons.person_outline_rounded,
                            label: 'Action utilisateur',
                            value: step.actorAction,
                            accentColor: colors.primary,
                          );
                          final systemBox = _ExchangePane(
                            icon: Icons.bolt_rounded,
                            label: 'Réponse système',
                            value: step.systemResponse,
                            accentColor: colors.secondary,
                          );
                          if (constraints.maxWidth >= 460) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: actorBox),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 16,
                                  ),
                                  child: Icon(
                                    Icons.sync_alt_rounded,
                                    size: 18,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                Expanded(child: systemBox),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              actorBox,
                              const SizedBox(height: 6),
                              systemBox,
                            ],
                          );
                        },
                      ),
                    ],
                    if (step.branchCondition.isNotEmpty ||
                        step.painPointResolved.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (step.branchCondition.isNotEmpty)
                            _MiniBadge(
                              icon: Icons.call_split_rounded,
                              label: 'Branche : ${step.branchCondition}',
                              backgroundColor: colors.tertiaryContainer,
                              foregroundColor: colors.onTertiaryContainer,
                            ),
                          if (step.painPointResolved.isNotEmpty)
                            _MiniBadge(
                              icon: Icons.healing_outlined,
                              label:
                                  'Irritant résolu : ${step.painPointResolved}',
                              backgroundColor: colors.secondaryContainer,
                              foregroundColor: colors.onSecondaryContainer,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExchangePane extends StatelessWidget {
  const _ExchangePane({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasText = value.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasText ? value : 'Non renseigné',
            style: theme.textTheme.bodySmall?.copyWith(
              color: hasText ? colors.onSurface : colors.onSurfaceVariant,
              fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaInfoBox extends StatelessWidget {
  const _MetaInfoBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.emptyText,
  });

  final IconData icon;
  final String label;
  final String value;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasValue = value.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: colors.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasValue ? value : emptyText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hasValue ? colors.onSurface : colors.onSurfaceVariant,
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foregroundColor),
          const SizedBox(width: 4),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyFormDialog extends StatefulWidget {
  const _JourneyFormDialog({
    required this.project,
    required this.existing,
    required this.suggestedCode,
    required this.generatedId,
    this.defaultPersonaId,
  });

  final SpecForgeProject project;
  final UxJourneySpec? existing;
  final String suggestedCode;
  final String generatedId;
  final String? defaultPersonaId;

  @override
  State<_JourneyFormDialog> createState() => _JourneyFormDialogState();
}

class _JourneyFormDialogState extends State<_JourneyFormDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _triggerCtrl;
  late final TextEditingController _goalCtrl;
  late final TextEditingController _criteriaCtrl;
  late String _personaId;
  late UxTargetChannel _channel;
  late Set<String> _selectedUseCaseIds;
  late Set<String> _selectedRequirementIds;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeCtrl = TextEditingController(text: widget.suggestedCode);
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _triggerCtrl = TextEditingController(text: existing?.trigger ?? '');
    _goalCtrl = TextEditingController(text: existing?.goal ?? '');
    _criteriaCtrl = TextEditingController(
      text: existing?.successCriteria.join('\n') ?? '',
    );
    final candidatePersona =
        existing?.personaId ?? widget.defaultPersonaId ?? '';
    _personaId =
        widget.project.vision.personas.any((p) => p.id == candidatePersona)
        ? candidatePersona
        : '';
    _channel = existing?.channel ?? UxTargetChannel.desktop;
    _selectedUseCaseIds = Set<String>.from(existing?.useCaseIds ?? const []);
    _selectedRequirementIds = Set<String>.from(
      existing?.requirementIds ?? const [],
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _triggerCtrl.dispose();
    _goalCtrl.dispose();
    _criteriaCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.isEmpty) {
      setState(() => _errorText = 'L’intitulé du parcours est requis.');
      return;
    }
    final trimmedCode = _codeCtrl.text.trim();
    final criteria = _criteriaCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final spec = UxJourneySpec(
      id: widget.generatedId,
      code: trimmedCode.isEmpty ? widget.suggestedCode : trimmedCode,
      name: trimmedName,
      personaId: _personaId,
      channel: _channel,
      trigger: _triggerCtrl.text.trim(),
      goal: _goalCtrl.text.trim(),
      useCaseIds: _selectedUseCaseIds.toList(),
      requirementIds: _selectedRequirementIds.toList(),
      steps: widget.existing?.steps ?? const <UxJourneyStep>[],
      successCriteria: criteria,
    );
    Navigator.pop(context, spec);
  }

  @override
  Widget build(BuildContext context) {
    final personas = widget.project.vision.personas;
    final useCases = widget.project.cahierDesCharges.useCases;
    final requirements = widget.project.cahierDesCharges.functionalRequirements;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouveau parcours utilisateur'
            : 'Modifier ${widget.existing!.code}',
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<UxTargetChannel>(
                      key: ValueKey('channel_${_channel.name}'),
                      initialValue: _channel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Canal cible',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final ch in UxTargetChannel.values)
                          DropdownMenuItem(
                            value: ch,
                            child: Text(
                              ch.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _channel = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                autofocus: widget.existing == null,
                decoration: InputDecoration(
                  labelText: 'Intitulé du parcours *',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('persona_$_personaId'),
                initialValue: _personaId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Persona principal',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Tous / Non spécifique',
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
              const SizedBox(height: 12),
              TextField(
                controller: _triggerCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Déclencheur initial',
                  hintText: 'Ex. Réception d’une alerte de rupture de stock',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _goalCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Objectif visé',
                  hintText: 'Ex. Valider une commande de réapprovisionnement en moins de 3 clics',
                  border: OutlineInputBorder(),
                ),
              ),
              if (useCases.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Cas d’usage couverts',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final uc in useCases)
                      FilterChip(
                        label: Text(uc.title),
                        selected: _selectedUseCaseIds.contains(uc.id),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _selectedUseCaseIds.add(uc.id);
                          } else {
                            _selectedUseCaseIds.remove(uc.id);
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
                            _selectedRequirementIds.contains(req.id) ||
                            _selectedRequirementIds.contains(req.code),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          _selectedRequirementIds.remove(req.code);
                          if (selected) {
                            _selectedRequirementIds.add(req.id);
                          } else {
                            _selectedRequirementIds.remove(req.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _criteriaCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Critères de succès UX (un par ligne)',
                  border: OutlineInputBorder(),
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
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _JourneyStepFormDialog extends StatefulWidget {
  const _JourneyStepFormDialog({
    required this.routes,
    required this.personaPainPoints,
    required this.existing,
    required this.generatedId,
    required this.nextOrder,
  });

  final List<UxRouteNode> routes;
  final List<String> personaPainPoints;
  final UxJourneyStep? existing;
  final String generatedId;
  final int nextOrder;

  @override
  State<_JourneyStepFormDialog> createState() => _JourneyStepFormDialogState();
}

class _JourneyStepFormDialogState extends State<_JourneyStepFormDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _actorCtrl;
  late final TextEditingController _systemCtrl;
  late final TextEditingController _branchCtrl;
  late final TextEditingController _painCtrl;
  late String _targetRouteId;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _actorCtrl = TextEditingController(text: existing?.actorAction ?? '');
    _systemCtrl = TextEditingController(text: existing?.systemResponse ?? '');
    _branchCtrl = TextEditingController(text: existing?.branchCondition ?? '');
    _painCtrl = TextEditingController(text: existing?.painPointResolved ?? '');
    _targetRouteId = existing?.targetRouteId ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _actorCtrl.dispose();
    _systemCtrl.dispose();
    _branchCtrl.dispose();
    _painCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedTitle = _titleCtrl.text.trim();
    if (trimmedTitle.isEmpty) {
      setState(() => _errorText = 'L’intitulé de l’étape est requis.');
      return;
    }
    final step = UxJourneyStep(
      id: widget.generatedId,
      order: widget.nextOrder < 1 ? 1 : widget.nextOrder,
      title: trimmedTitle,
      actorAction: _actorCtrl.text.trim(),
      systemResponse: _systemCtrl.text.trim(),
      targetRouteId: _targetRouteId,
      branchCondition: _branchCtrl.text.trim(),
      painPointResolved: _painCtrl.text.trim(),
    );
    Navigator.pop(context, step);
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomRoute =
        _targetRouteId.isNotEmpty &&
        !widget.routes.any((r) => r.id == _targetRouteId);

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouvelle étape (#${widget.nextOrder})'
            : 'Modifier l’étape #${widget.nextOrder}',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                autofocus: widget.existing == null,
                decoration: InputDecoration(
                  labelText: 'Intitulé de l’étape *',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _actorCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Action utilisateur',
                  hintText: 'Ce que fait ou saisit le persona',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _systemCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Réponse système',
                  hintText:
                      'Retour visuel, calcul ou validation métier affiché',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('step_route_$_targetRouteId'),
                initialValue: _targetRouteId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Route ou vue cible (optionnel)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Aucune route liée',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasCustomRoute)
                    DropdownMenuItem(
                      value: _targetRouteId,
                      child: Text(
                        '$_targetRouteId (non cataloguée)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final route in widget.routes)
                    DropdownMenuItem(
                      value: route.id,
                      child: Text(
                        '${route.path} — ${route.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _targetRouteId = val ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _branchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Condition d’embranchement (optionnel)',
                  hintText: 'Ex. Si le plafond budgétaire est dépassé',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _painCtrl,
                decoration: const InputDecoration(
                  labelText: 'Point de friction résolu (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.personaPainPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final pain in widget.personaPainPoints)
                      ActionChip(
                        label: Text(pain),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _painCtrl.text = pain),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
