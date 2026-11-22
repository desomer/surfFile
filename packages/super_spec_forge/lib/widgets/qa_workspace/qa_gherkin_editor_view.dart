/// Atelier structuré de l'étape QA 2 : Fonctionnalités Gherkin BDD (`.feature`),
/// contexte partagé, scénarios, plans de scénarios (`Exemples:`) et aperçu `.feature` ([QaGherkinEditorView]).
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/business_rule_spec.dart';
import '../../models/qa/gherkin_feature_spec.dart';
import '../../models/qa/qa_fixture_spec.dart';
import '../../models/qa/qa_forge_stage.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_vision.dart';
import '../../models/ux/ux_journey_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import '../../services/exporters/gherkin_feature_exporter.dart';
import '../../services/spec_forge_controller.dart';

/// Vue Maître / Détail permettant d'éditer les fonctionnalités Gherkin BDD
/// ([GherkinFeatureSpec]), leurs scénarios ([GherkinScenarioSpec]), leurs étapes
/// ([GherkinStep]), leurs tables d'exemples ([GherkinExamplesTable]) et leur
/// rendu `.feature` bilingue (`# language: fr` / `# language: en`).
class QaGherkinEditorView extends StatefulWidget {
  /// Crée l'atelier d'édition Gherkin BDD connecté au [controller].
  const QaGherkinEditorView({required this.controller, super.key});

  /// Contrôleur principal orchestrant l'état du projet et l'historique Undo/Redo.
  final SpecForgeController controller;

  @override
  State<QaGherkinEditorView> createState() => _QaGherkinEditorViewState();
}

class _QaGherkinEditorViewState extends State<QaGherkinEditorView> {
  String _generateShortId(String prefix) {
    final raw = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final token = raw.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : raw;
    return '${prefix}_$token';
  }

  String _nextFeatureCode(List<GherkinFeatureSpec> existing) {
    final pattern = RegExp(r'^FEAT-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final feature in existing) {
      final match = pattern.firstMatch(feature.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'FEAT-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  String _nextScenarioCode(List<GherkinFeatureSpec> features) {
    final pattern = RegExp(r'^SCN-(\d+)$', caseSensitive: false);
    var totalCount = 0;
    var maxIndex = 0;
    for (final feature in features) {
      for (final scenario in feature.scenarios) {
        totalCount++;
        final match = pattern.firstMatch(scenario.code.trim());
        if (match != null) {
          final parsed = int.tryParse(match.group(1)!) ?? 0;
          if (parsed > maxIndex) maxIndex = parsed;
        }
      }
    }
    final base = maxIndex > totalCount ? maxIndex : totalCount;
    return 'SCN-${(base + 1).toString().padLeft(3, '0')}';
  }

  void _focusSelection({String? featureId, String? scenarioId}) {
    widget.controller.focusQaItem(
      fixtureId: widget.controller.focusedFixtureId,
      featureId: featureId,
      scenarioId: scenarioId,
      tddSuiteId: widget.controller.focusedTddSuiteId,
    );
  }

  SpecModule? _findModule(SpecForgeProject project, String moduleId) {
    final needle = moduleId.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final module in project.cahierDesCharges.modules) {
      if (module.id.toLowerCase() == needle ||
          module.name.toLowerCase() == needle) {
        return module;
      }
    }
    return null;
  }

  SpecPersona? _findPersona(SpecForgeProject project, String personaId) {
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

  FunctionalRequirement? _findRequirement(
    SpecForgeProject project,
    String ref,
  ) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (req.id.toLowerCase() == needle || req.code.toLowerCase() == needle) {
        return req;
      }
    }
    return null;
  }

  UseCaseSpec? _findUseCase(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final uc in project.cahierDesCharges.useCases) {
      if (uc.id.toLowerCase() == needle || uc.title.toLowerCase() == needle) {
        return uc;
      }
    }
    return null;
  }

  BusinessRuleSpec? _findRule(SpecForgeProject project, String ref) {
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

  UxJourneySpec? _findJourney(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final jrn in project.uxSpec.journeys) {
      if (jrn.id.toLowerCase() == needle ||
          (jrn.code.isNotEmpty && jrn.code.toLowerCase() == needle)) {
        return jrn;
      }
    }
    return null;
  }

  UxScreenSpec? _findScreen(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final scr in project.uxSpec.screens) {
      if (scr.id.toLowerCase() == needle ||
          (scr.code.isNotEmpty && scr.code.toLowerCase() == needle)) {
        return scr;
      }
    }
    return null;
  }

  QaFixtureSpec? _findFixture(SpecForgeProject project, String ref) =>
      project.qaSpec.findFixture(ref);

  Future<void> _saveFeature(
    SpecForgeProject project,
    GherkinFeatureSpec feature, {
    bool focusAfterSave = false,
    String? focusScenarioId,
  }) async {
    final nextFeatures = List<GherkinFeatureSpec>.from(project.qaSpec.features);
    final idx = nextFeatures.indexWhere((f) => f.id == feature.id);
    if (idx >= 0) {
      nextFeatures[idx] = feature;
    } else {
      nextFeatures.add(feature);
    }
    await widget.controller.updateQaSpec(
      project.qaSpec.copyWith(features: nextFeatures),
    );
    if (focusAfterSave) {
      _focusSelection(
        featureId: feature.id,
        scenarioId: focusScenarioId ?? feature.scenarios.firstOrNull?.id,
      );
    } else if (focusScenarioId != null) {
      _focusSelection(featureId: feature.id, scenarioId: focusScenarioId);
    }
  }

  Future<void> _deleteFeature(
    SpecForgeProject project,
    GherkinFeatureSpec feature,
  ) async {
    final nextFeatures = project.qaSpec.features
        .where((f) => f.id != feature.id)
        .toList();
    await widget.controller.updateQaSpec(
      project.qaSpec.copyWith(features: nextFeatures),
    );
    if (widget.controller.focusedFeatureId == feature.id) {
      final fallback = nextFeatures.firstOrNull;
      _focusSelection(
        featureId: fallback?.id,
        scenarioId: fallback?.scenarios.firstOrNull?.id,
      );
    }
  }

  Future<void> _seedFeatures(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final added = await widget.controller.seedQaFeaturesFromSpecAndUx();
    final updatedProject = widget.controller.project;
    if (added > 0 &&
        updatedProject != null &&
        widget.controller.focusedFeatureId == null &&
        updatedProject.qaSpec.features.isNotEmpty) {
      final first = updatedProject.qaSpec.features.first;
      _focusSelection(
        featureId: first.id,
        scenarioId: first.scenarios.firstOrNull?.id,
      );
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          added > 0
              ? '$added fonctionnalité(s) Gherkin générée(s) depuis les UC et parcours.'
              : 'Aucune nouvelle feature à générer (UC, exigences et parcours déjà couverts ou vides).',
        ),
      ),
    );
  }

  Future<void> _openFeatureDialog(
    BuildContext context,
    SpecForgeProject project, {
    GherkinFeatureSpec? existing,
  }) async {
    final suggestedCode =
        existing?.code ?? _nextFeatureCode(project.qaSpec.features);
    final result = await showDialog<GherkinFeatureSpec>(
      context: context,
      builder: (_) => _FeatureFormDialog(
        project: project,
        existing: existing,
        suggestedCode: suggestedCode,
        generatedId: existing?.id ?? _generateShortId('feat'),
      ),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    await _saveFeature(freshProject, result, focusAfterSave: existing == null);
  }

  Future<void> _openBackgroundStepDialog(
    BuildContext context,
    SpecForgeProject project,
    GherkinFeatureSpec feature, {
    GherkinStep? existing,
  }) async {
    final defaultKeyword =
        existing?.keyword ??
        (feature.backgroundSteps.isEmpty
            ? GherkinStepKeyword.given
            : GherkinStepKeyword.and);
    final result = await showDialog<GherkinStep>(
      context: context,
      builder: (_) => _GherkinStepFormDialog(
        language: project.qaSpec.gherkinLanguage,
        existing: existing,
        defaultKeyword: defaultKeyword,
        generatedId: existing?.id ?? _generateShortId('bgstep'),
        isOutlineContext: false,
        dialogTitle: existing == null
            ? 'Nouvelle étape de contexte'
            : 'Modifier l’étape de contexte',
      ),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    final freshFeature =
        freshProject.qaSpec.features
            .where((f) => f.id == feature.id)
            .firstOrNull ??
        feature;
    final nextSteps = List<GherkinStep>.from(freshFeature.backgroundSteps);
    final idx = nextSteps.indexWhere((s) => s.id == result.id);
    if (idx >= 0) {
      nextSteps[idx] = result;
    } else {
      nextSteps.add(result);
    }
    await _saveFeature(
      freshProject,
      freshFeature.copyWith(backgroundSteps: nextSteps),
    );
  }

  Future<void> _moveBackgroundStep(
    SpecForgeProject project,
    GherkinFeatureSpec feature,
    int index,
    int delta,
  ) async {
    final nextSteps = List<GherkinStep>.from(feature.backgroundSteps);
    final target = index + delta;
    if (index < 0 ||
        index >= nextSteps.length ||
        target < 0 ||
        target >= nextSteps.length) {
      return;
    }
    final moved = nextSteps.removeAt(index);
    nextSteps.insert(target, moved);
    await _saveFeature(project, feature.copyWith(backgroundSteps: nextSteps));
  }

  Future<void> _deleteBackgroundStep(
    SpecForgeProject project,
    GherkinFeatureSpec feature,
    String stepId,
  ) async {
    final nextSteps = feature.backgroundSteps
        .where((s) => s.id != stepId)
        .toList();
    await _saveFeature(project, feature.copyWith(backgroundSteps: nextSteps));
  }

  Future<void> _openScenarioDialog(
    BuildContext context,
    SpecForgeProject project,
    GherkinFeatureSpec feature, {
    GherkinScenarioSpec? existing,
  }) async {
    final suggestedCode =
        existing?.code ?? _nextScenarioCode(project.qaSpec.features);
    final result = await showDialog<GherkinScenarioSpec>(
      context: context,
      builder: (_) => _ScenarioFormDialog(
        project: project,
        existing: existing,
        suggestedCode: suggestedCode,
        generatedId: existing?.id ?? _generateShortId('scn'),
      ),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    final freshFeature =
        freshProject.qaSpec.features
            .where((f) => f.id == feature.id)
            .firstOrNull ??
        feature;
    final nextScenarios = List<GherkinScenarioSpec>.from(
      freshFeature.scenarios,
    );
    final idx = nextScenarios.indexWhere((s) => s.id == result.id);
    if (idx >= 0) {
      nextScenarios[idx] = result;
    } else {
      nextScenarios.add(result);
    }
    await _saveFeature(
      freshProject,
      freshFeature.copyWith(scenarios: nextScenarios),
      focusScenarioId: result.id,
    );
  }

  Future<void> _deleteScenario(
    SpecForgeProject project,
    GherkinFeatureSpec feature,
    GherkinScenarioSpec scenario,
  ) async {
    final nextScenarios = feature.scenarios
        .where((s) => s.id != scenario.id)
        .toList();
    await _saveFeature(project, feature.copyWith(scenarios: nextScenarios));
    if (widget.controller.focusedScenarioId == scenario.id) {
      _focusSelection(
        featureId: feature.id,
        scenarioId: nextScenarios.firstOrNull?.id,
      );
    }
  }

  Future<void> _openScenarioStepDialog(
    BuildContext context,
    SpecForgeProject project,
    GherkinFeatureSpec feature,
    GherkinScenarioSpec scenario, {
    GherkinStep? existing,
  }) async {
    final defaultKeyword =
        existing?.keyword ?? _suggestNextStepKeyword(scenario.steps);
    final result = await showDialog<GherkinStep>(
      context: context,
      builder: (_) => _GherkinStepFormDialog(
        language: project.qaSpec.gherkinLanguage,
        existing: existing,
        defaultKeyword: defaultKeyword,
        generatedId: existing?.id ?? _generateShortId('step'),
        isOutlineContext: scenario.isOutline,
        dialogTitle: existing == null
            ? 'Nouveau pas Gherkin (${scenario.code})'
            : 'Modifier le pas Gherkin (${scenario.code})',
      ),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    final freshFeature =
        freshProject.qaSpec.features
            .where((f) => f.id == feature.id)
            .firstOrNull ??
        feature;
    final freshScenario =
        freshFeature.scenarios.where((s) => s.id == scenario.id).firstOrNull ??
        scenario;
    final nextSteps = List<GherkinStep>.from(freshScenario.steps);
    final idx = nextSteps.indexWhere((s) => s.id == result.id);
    if (idx >= 0) {
      nextSteps[idx] = result;
    } else {
      nextSteps.add(result);
    }
    final updatedScenario = freshScenario.copyWith(steps: nextSteps);
    final nextScenarios = [
      for (final sc in freshFeature.scenarios)
        if (sc.id == updatedScenario.id) updatedScenario else sc,
    ];
    await _saveFeature(
      freshProject,
      freshFeature.copyWith(scenarios: nextScenarios),
      focusScenarioId: updatedScenario.id,
    );
  }

  GherkinStepKeyword _suggestNextStepKeyword(List<GherkinStep> steps) {
    if (steps.isEmpty) return GherkinStepKeyword.given;
    final hasWhen = steps.any((s) => s.keyword == GherkinStepKeyword.when);
    final hasThen = steps.any((s) => s.keyword == GherkinStepKeyword.then);
    if (!hasWhen) return GherkinStepKeyword.when;
    if (!hasThen) return GherkinStepKeyword.then;
    return GherkinStepKeyword.and;
  }

  Future<void> _moveScenarioStep(
    SpecForgeProject project,
    GherkinFeatureSpec feature,
    GherkinScenarioSpec scenario,
    int index,
    int delta,
  ) async {
    final nextSteps = List<GherkinStep>.from(scenario.steps);
    final target = index + delta;
    if (index < 0 ||
        index >= nextSteps.length ||
        target < 0 ||
        target >= nextSteps.length) {
      return;
    }
    final moved = nextSteps.removeAt(index);
    nextSteps.insert(target, moved);
    final updatedScenario = scenario.copyWith(steps: nextSteps);
    final nextScenarios = [
      for (final sc in feature.scenarios)
        if (sc.id == updatedScenario.id) updatedScenario else sc,
    ];
    await _saveFeature(
      project,
      feature.copyWith(scenarios: nextScenarios),
      focusScenarioId: updatedScenario.id,
    );
  }

  Future<void> _deleteScenarioStep(
    SpecForgeProject project,
    GherkinFeatureSpec feature,
    GherkinScenarioSpec scenario,
    String stepId,
  ) async {
    final nextSteps = scenario.steps.where((s) => s.id != stepId).toList();
    final updatedScenario = scenario.copyWith(steps: nextSteps);
    final nextScenarios = [
      for (final sc in feature.scenarios)
        if (sc.id == updatedScenario.id) updatedScenario else sc,
    ];
    await _saveFeature(
      project,
      feature.copyWith(scenarios: nextScenarios),
      focusScenarioId: updatedScenario.id,
    );
  }

  Future<void> _openExamplesDialog(
    BuildContext context,
    SpecForgeProject project,
    GherkinFeatureSpec feature,
    GherkinScenarioSpec scenario,
  ) async {
    final result = await showDialog<GherkinExamplesTable>(
      context: context,
      builder: (_) => _ExamplesTableEditorDialog(scenario: scenario),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    final freshFeature =
        freshProject.qaSpec.features
            .where((f) => f.id == feature.id)
            .firstOrNull ??
        feature;
    final freshScenario =
        freshFeature.scenarios.where((s) => s.id == scenario.id).firstOrNull ??
        scenario;
    final updatedScenario = freshScenario.copyWith(
      isOutline: true,
      examples: result,
    );
    final nextScenarios = [
      for (final sc in freshFeature.scenarios)
        if (sc.id == updatedScenario.id) updatedScenario else sc,
    ];
    await _saveFeature(
      freshProject,
      freshFeature.copyWith(scenarios: nextScenarios),
      focusScenarioId: updatedScenario.id,
    );
  }

  GherkinFeatureSpec? _resolveSelectedFeature(
    List<GherkinFeatureSpec> features,
    String? focusedFeatureId,
    String? focusedScenarioId,
  ) {
    if (features.isEmpty) return null;
    if (focusedFeatureId != null) {
      final direct = features
          .where((f) => f.id == focusedFeatureId)
          .firstOrNull;
      if (direct != null) return direct;
    }
    if (focusedScenarioId != null) {
      final owner = features
          .where((f) => f.scenarios.any((s) => s.id == focusedScenarioId))
          .firstOrNull;
      if (owner != null) return owner;
    }
    return features.first;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      key: const ValueKey('qa-gherkin-editor-view'),
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        if (project == null) return const SizedBox.shrink();

        final qaSpec = project.qaSpec;
        final features = qaSpec.features;
        final focusedFeatureId = widget.controller.focusedFeatureId;
        final focusedScenarioId = widget.controller.focusedScenarioId;
        final selectedFeature = _resolveSelectedFeature(
          features,
          focusedFeatureId,
          focusedScenarioId,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopHeader(context, project: project),
            const Divider(height: 1),
            Expanded(
              child: features.isEmpty
                  ? _buildEmptyState(context, project)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final masterPane = _buildMasterList(
                          context,
                          project: project,
                          features: features,
                          selectedFeatureId: selectedFeature?.id,
                          focusedScenarioId: focusedScenarioId,
                        );
                        final detailPane = selectedFeature == null
                            ? const SizedBox.shrink()
                            : _buildDetailWorkspace(
                                context,
                                project: project,
                                feature: selectedFeature,
                                focusedScenarioId: focusedScenarioId,
                              );

                        if (constraints.maxWidth >= 740) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 265, child: masterPane),
                              const VerticalDivider(width: 1),
                              Expanded(child: detailPane),
                            ],
                          );
                        }

                        final stackedMasterHeight =
                            (constraints.maxHeight * 0.32).clamp(108.0, 200.0);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: stackedMasterHeight,
                              child: masterPane,
                            ),
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
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final qaSpec = project.qaSpec;
    final lang = qaSpec.gherkinLanguage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 22,
                    color: colors.primary,
                  ),
                  Text(
                    'Features Gherkin BDD (.feature)',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                      '${qaSpec.features.length} feat. · ${qaSpec.totalScenarioCount} scén.',
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
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('qa-seed-gherkin-btn'),
                    onPressed: () => _seedFeatures(context),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                    label: const Text('Générer depuis UC & Parcours'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('qa-add-feature-btn'),
                    onPressed: () => _openFeatureDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('+ Nouvelle feature'),
                  ),
                ],
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
                'Syntaxe Gherkin :',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Wrap(
                key: const ValueKey('qa-gherkin-lang-toggle'),
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    key: const ValueKey('qa-gherkin-lang-fr'),
                    label: const Text('FR (# language: fr)'),
                    selected: lang == GherkinKeywordLanguage.fr,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => widget.controller.setGherkinLanguage(
                      GherkinKeywordLanguage.fr,
                    ),
                  ),
                  ChoiceChip(
                    key: const ValueKey('qa-gherkin-lang-en'),
                    label: const Text('EN (Feature/Given/When/Then)'),
                    selected: lang == GherkinKeywordLanguage.en,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => widget.controller.setGherkinLanguage(
                      GherkinKeywordLanguage.en,
                    ),
                  ),
                ],
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
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.fact_check_rounded,
                      size: 28,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune fonctionnalité Gherkin BDD définie',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Formalisez des spécifications exécutables (.feature) avec Contexte, Scénarios Given/When/Then et Plans de Scénario paramétrés par tables Exemples, ou générez un socle initial depuis vos cas d’usage et parcours UX.',
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
                      FilledButton.tonalIcon(
                        onPressed: () => _seedFeatures(context),
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        label: const Text('Générer depuis UC & Parcours'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openFeatureDialog(context, project),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('+ Nouvelle feature'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.controller.isSending
                            ? null
                            : () => widget.controller.kickoffQaStageIfEmpty(
                                QaForgeStage.gherkinFeatures,
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

  Widget _buildMasterList(
    BuildContext context, {
    required SpecForgeProject project,
    required List<GherkinFeatureSpec> features,
    required String? selectedFeatureId,
    required String? focusedScenarioId,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: features.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final feature = features[index];
        final isSelected = feature.id == selectedFeatureId;
        final module = _findModule(project, feature.moduleId);
        final persona = _findPersona(project, feature.personaId);
        final scenarioCount = feature.scenarios.length;

        return Material(
          key: ValueKey('qa-feature-tile-${feature.id}'),
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
            onTap: () {
              final keepScenario =
                  feature.scenarios.any((s) => s.id == focusedScenarioId)
                  ? focusedScenarioId
                  : feature.scenarios.firstOrNull?.id;
              _focusSelection(featureId: feature.id, scenarioId: keepScenario);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _CodeBadge(
                        text: feature.code,
                        backgroundColor: colors.primaryContainer,
                        foregroundColor: colors.onPrimaryContainer,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$scenarioCount scén.',
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
                    feature.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (module != null || persona != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (module != null) module.name,
                        if (persona != null) persona.name,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (feature.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final tag in feature.tags) _TagPill(tag: tag),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailWorkspace(
    BuildContext context, {
    required SpecForgeProject project,
    required GherkinFeatureSpec feature,
    required String? focusedScenarioId,
  }) {
    final colors = Theme.of(context).colorScheme;
    final lang = project.qaSpec.gherkinLanguage;
    final exportedContent = GherkinFeatureExporter.exportFeature(
      feature,
      language: lang,
    );
    final assignedFiles = GherkinFeatureExporter.assignFeatureFileNames(
      project.qaSpec.features,
    );
    var fileName = 'feature.feature';
    for (final entry in assignedFiles.entries) {
      if (entry.value.id == feature.id) {
        fileName = entry.key;
        break;
      }
    }

    return DefaultTabController(
      key: ValueKey('qa-feature-tabs-${feature.id}'),
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.surfaceContainerLow,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(
                  key: ValueKey('qa-feature-structured-tab'),
                  text: 'Éditeur Structuré',
                ),
                Tab(
                  key: ValueKey('qa-feature-code-preview-tab'),
                  text: 'Aperçu .feature',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildStructuredEditorTab(
                  context,
                  project: project,
                  feature: feature,
                  focusedScenarioId: focusedScenarioId,
                  lang: lang,
                ),
                _FeatureCodePreviewPane(
                  fileName: 'features/$fileName',
                  language: lang,
                  content: exportedContent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredEditorTab(
    BuildContext context, {
    required SpecForgeProject project,
    required GherkinFeatureSpec feature,
    required String? focusedScenarioId,
    required GherkinKeywordLanguage lang,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildFeatureHeaderCard(
          context,
          project: project,
          feature: feature,
          lang: lang,
        ),
        const SizedBox(height: 18),
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
                Icon(Icons.playlist_add_check_rounded, color: colors.primary),
                Text(
                  'Scénarios BDD (${feature.scenarios.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('qa-add-scenario-btn'),
              onPressed: () => _openScenarioDialog(context, project, feature),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('+ Nouveau scénario'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (feature.scenarios.isEmpty)
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
                  Icons.rule_folder_outlined,
                  size: 30,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  'Aucun scénario défini dans cette feature.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cliquez sur « + Nouveau scénario » pour ajouter un Scénario nominal, alternatif ou un Plan du Scénario paramétré.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < feature.scenarios.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildScenarioCard(
              context,
              project: project,
              feature: feature,
              scenario: feature.scenarios[i],
              isFocused: feature.scenarios[i].id == focusedScenarioId,
              lang: lang,
            ),
          ],
      ],
    );
  }

  Widget _buildFeatureHeaderCard(
    BuildContext context, {
    required SpecForgeProject project,
    required GherkinFeatureSpec feature,
    required GherkinKeywordLanguage lang,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final module = _findModule(project, feature.moduleId);
    final persona = _findPersona(project, feature.personaId);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    _CodeBadge(
                      text: feature.code,
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                    ),
                    _CodeBadge(
                      text: '${lang.featureKeyword}:',
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                    ),
                    if (module != null)
                      _MetaBadge(
                        icon: Icons.folder_outlined,
                        label: module.name,
                      )
                    else if (feature.moduleId.isNotEmpty)
                      _MetaBadge(
                        icon: Icons.folder_outlined,
                        label: feature.moduleId,
                      ),
                    if (persona != null)
                      _MetaBadge(
                        icon: Icons.person_outline_rounded,
                        label: persona.name,
                      )
                    else if (feature.personaId.isNotEmpty)
                      _MetaBadge(
                        icon: Icons.person_outline_rounded,
                        label: feature.personaId,
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('qa-edit-feature-btn'),
                      onPressed: () => _openFeatureDialog(
                        context,
                        project,
                        existing: feature,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Modifier'),
                    ),
                    IconButton(
                      key: const ValueKey('qa-delete-feature-btn'),
                      tooltip: 'Supprimer cette feature',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: colors.error,
                      ),
                      onPressed: () => _deleteFeature(project, feature),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              feature.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (feature.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final tag in feature.tags) _TagPill(tag: tag)],
              ),
            ],
            if (feature.narrative.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(color: colors.primary, width: 3),
                  ),
                ),
                child: Text(
                  feature.narrative,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
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
                    Icon(
                      Icons.layers_outlined,
                      size: 18,
                      color: colors.secondary,
                    ),
                    Text(
                      '${lang.backgroundKeyword} (${feature.backgroundSteps.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  key: const ValueKey('qa-add-bg-step-btn'),
                  onPressed: () =>
                      _openBackgroundStepDialog(context, project, feature),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('+ Étape de contexte'),
                ),
              ],
            ),
            if (feature.backgroundSteps.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Aucune précondition partagée (${lang.backgroundKeyword}). Optionnel.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              for (var i = 0; i < feature.backgroundSteps.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _GherkinStepTile(
                  step: feature.backgroundSteps[i],
                  language: lang,
                  upButtonKey: ValueKey(
                    'qa-bg-step-up-btn-${feature.backgroundSteps[i].id}',
                  ),
                  downButtonKey: ValueKey(
                    'qa-bg-step-down-btn-${feature.backgroundSteps[i].id}',
                  ),
                  editButtonKey: ValueKey(
                    'qa-bg-step-edit-btn-${feature.backgroundSteps[i].id}',
                  ),
                  deleteButtonKey: ValueKey(
                    'qa-bg-step-delete-btn-${feature.backgroundSteps[i].id}',
                  ),
                  onMoveUp: i > 0
                      ? () => _moveBackgroundStep(project, feature, i, -1)
                      : null,
                  onMoveDown: i < feature.backgroundSteps.length - 1
                      ? () => _moveBackgroundStep(project, feature, i, 1)
                      : null,
                  onEdit: () => _openBackgroundStepDialog(
                    context,
                    project,
                    feature,
                    existing: feature.backgroundSteps[i],
                  ),
                  onDelete: () => _deleteBackgroundStep(
                    project,
                    feature,
                    feature.backgroundSteps[i].id,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioCard(
    BuildContext context, {
    required SpecForgeProject project,
    required GherkinFeatureSpec feature,
    required GherkinScenarioSpec scenario,
    required bool isFocused,
    required GherkinKeywordLanguage lang,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final traceChips = _buildTraceabilityChips(project, scenario);
    final kindLabel = scenario.isOutline
        ? lang.scenarioOutlineKeyword
        : lang.scenarioKeyword;

    return Card(
      key: ValueKey('qa-scenario-card-${scenario.id}'),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isFocused
          ? colors.primaryContainer.withValues(alpha: 0.16)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isFocused ? colors.primary : colors.outlineVariant,
          width: isFocused ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _focusSelection(featureId: feature.id, scenarioId: scenario.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _CodeBadge(
                        text: scenario.code,
                        backgroundColor: colors.primaryContainer,
                        foregroundColor: colors.onPrimaryContainer,
                      ),
                      _CodeBadge(
                        text: kindLabel,
                        icon: scenario.isOutline
                            ? Icons.table_chart_outlined
                            : Icons.check_circle_outline_rounded,
                        backgroundColor: scenario.isOutline
                            ? colors.tertiaryContainer
                            : colors.secondaryContainer,
                        foregroundColor: scenario.isOutline
                            ? colors.onTertiaryContainer
                            : colors.onSecondaryContainer,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        key: ValueKey('qa-edit-scenario-btn-${scenario.id}'),
                        tooltip: 'Modifier le scénario',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _openScenarioDialog(
                          context,
                          project,
                          feature,
                          existing: scenario,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('qa-delete-scenario-btn-${scenario.id}'),
                        tooltip: 'Supprimer le scénario',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: colors.error,
                        ),
                        onPressed: () =>
                            _deleteScenario(project, feature, scenario),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                scenario.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (scenario.tags.isNotEmpty || traceChips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in scenario.tags) _TagPill(tag: tag),
                    ...traceChips,
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (scenario.steps.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text(
                    'Aucun pas Given / When / Then défini.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (var i = 0; i < scenario.steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _GherkinStepTile(
                    step: scenario.steps[i],
                    language: lang,
                    upButtonKey: ValueKey(
                      'qa-step-up-btn-${scenario.id}-${scenario.steps[i].id}',
                    ),
                    downButtonKey: ValueKey(
                      'qa-step-down-btn-${scenario.id}-${scenario.steps[i].id}',
                    ),
                    editButtonKey: ValueKey(
                      'qa-step-edit-btn-${scenario.id}-${scenario.steps[i].id}',
                    ),
                    deleteButtonKey: ValueKey(
                      'qa-step-delete-btn-${scenario.id}-${scenario.steps[i].id}',
                    ),
                    onMoveUp: i > 0
                        ? () => _moveScenarioStep(
                            project,
                            feature,
                            scenario,
                            i,
                            -1,
                          )
                        : null,
                    onMoveDown: i < scenario.steps.length - 1
                        ? () => _moveScenarioStep(
                            project,
                            feature,
                            scenario,
                            i,
                            1,
                          )
                        : null,
                    onEdit: () => _openScenarioStepDialog(
                      context,
                      project,
                      feature,
                      scenario,
                      existing: scenario.steps[i],
                    ),
                    onDelete: () => _deleteScenarioStep(
                      project,
                      feature,
                      scenario,
                      scenario.steps[i].id,
                    ),
                  ),
                ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    key: ValueKey('qa-add-step-btn-${scenario.id}'),
                    onPressed: () => _openScenarioStepDialog(
                      context,
                      project,
                      feature,
                      scenario,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('+ Ajouter un pas'),
                  ),
                ],
              ),
              if (scenario.isOutline) ...[
                const SizedBox(height: 10),
                _ScenarioExamplesSection(
                  scenario: scenario,
                  language: lang,
                  onEditExamples: () =>
                      _openExamplesDialog(context, project, feature, scenario),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTraceabilityChips(
    SpecForgeProject project,
    GherkinScenarioSpec scenario,
  ) {
    final chips = <Widget>[];
    for (final ref in scenario.requirementIds) {
      final req = _findRequirement(project, ref);
      chips.add(
        _TraceChip(
          prefix: 'EXF',
          label: req != null ? req.code : ref,
          tooltip: req?.title,
        ),
      );
    }
    for (final ref in scenario.useCaseIds) {
      final uc = _findUseCase(project, ref);
      chips.add(
        _TraceChip(
          prefix: 'UC',
          label: uc != null ? uc.title : ref,
          tooltip: uc?.id,
        ),
      );
    }
    for (final ref in scenario.businessRuleIds) {
      final rule = _findRule(project, ref);
      chips.add(
        _TraceChip(
          prefix: 'RG',
          label: rule != null ? rule.code : ref,
          tooltip: rule?.title,
        ),
      );
    }
    for (final ref in scenario.journeyIds) {
      final jrn = _findJourney(project, ref);
      chips.add(
        _TraceChip(
          prefix: 'JRN',
          label: jrn != null && jrn.code.isNotEmpty ? jrn.code : ref,
          tooltip: jrn?.name,
        ),
      );
    }
    for (final ref in scenario.screenIds) {
      final scr = _findScreen(project, ref);
      chips.add(
        _TraceChip(
          prefix: 'SCR',
          label: scr != null && scr.code.isNotEmpty ? scr.code : ref,
          tooltip: scr?.name,
        ),
      );
    }
    for (final ref in scenario.fixtureIds) {
      final fix = _findFixture(project, ref);
      chips.add(
        _TraceChip(
          prefix: 'FIX',
          label: fix != null && fix.code.isNotEmpty ? fix.code : ref,
          tooltip: fix?.name,
        ),
      );
    }
    return chips;
  }
}

class _CodeBadge extends StatelessWidget {
  const _CodeBadge({
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
    this.icon,
  });

  final String text;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Text(
          tag,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontFamily: 'Consolas',
            color: colors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TraceChip extends StatelessWidget {
  const _TraceChip({required this.prefix, required this.label, this.tooltip});

  final String prefix;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chip = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$prefix · $label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSecondaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.trim().isEmpty) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

class _GherkinStepTile extends StatelessWidget {
  const _GherkinStepTile({
    required this.step,
    required this.language,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
    this.upButtonKey,
    this.downButtonKey,
    this.editButtonKey,
    this.deleteButtonKey,
  });

  final GherkinStep step;
  final GherkinKeywordLanguage language;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Key? upButtonKey;
  final Key? downButtonKey;
  final Key? editButtonKey;
  final Key? deleteButtonKey;

  (Color bg, Color fg) _keywordColors(ColorScheme colors) {
    final isDark = colors.brightness == Brightness.dark;
    return switch (step.keyword) {
      GherkinStepKeyword.given => (
        isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE3F2FD),
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF0D47A1),
      ),
      GherkinStepKeyword.when => (
        isDark ? const Color(0xFF4E342E) : const Color(0xFFFFF3E0),
        isDark ? const Color(0xFFFFCC80) : const Color(0xFFE65100),
      ),
      GherkinStepKeyword.then => (
        isDark ? const Color(0xFF1B4332) : const Color(0xFFE8F5E9),
        isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20),
      ),
      GherkinStepKeyword.and => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      GherkinStepKeyword.but => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (kwBg, kwFg) = _keywordColors(colors);

    final keywordBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kwBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        step.keyword.keywordFor(language),
        style: theme.textTheme.labelSmall?.copyWith(
          color: kwFg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final actionButtons = Wrap(
      spacing: 2,
      children: [
        IconButton(
          key: upButtonKey,
          tooltip: 'Monter le pas',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: const EdgeInsets.all(4),
          icon: const Icon(Icons.arrow_upward_rounded, size: 15),
          onPressed: onMoveUp,
        ),
        IconButton(
          key: downButtonKey,
          tooltip: 'Descendre le pas',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: const EdgeInsets.all(4),
          icon: const Icon(Icons.arrow_downward_rounded, size: 15),
          onPressed: onMoveDown,
        ),
        IconButton(
          key: editButtonKey,
          tooltip: 'Modifier le pas',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: const EdgeInsets.all(4),
          icon: const Icon(Icons.edit_outlined, size: 15),
          onPressed: onEdit,
        ),
        IconButton(
          key: deleteButtonKey,
          tooltip: 'Supprimer le pas',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: const EdgeInsets.all(4),
          icon: Icon(
            Icons.delete_outline_rounded,
            size: 15,
            color: colors.error,
          ),
          onPressed: onDelete,
        ),
      ],
    );

    final textWidget = Text(
      step.text,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 460) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    keywordBadge,
                    const SizedBox(width: 8),
                    Expanded(child: textWidget),
                    const SizedBox(width: 6),
                    actionButtons,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [keywordBadge, actionButtons],
                  ),
                  const SizedBox(height: 4),
                  textWidget,
                ],
              );
            },
          ),
          if (step.docString.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(
                '"""\n${step.docString.trim()}\n"""',
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
              ),
            ),
          ],
          if (step.dataTable.isNotEmpty) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _PipeDataTablePreview(
                headers: const <String>[],
                rows: step.dataTable,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScenarioExamplesSection extends StatelessWidget {
  const _ScenarioExamplesSection({
    required this.scenario,
    required this.language,
    required this.onEditExamples,
  });

  final GherkinScenarioSpec scenario;
  final GherkinKeywordLanguage language;
  final VoidCallback onEditExamples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final outlineVars = scenario.referencedOutlineVariables;
    final headerLowerSet = <String>{
      for (final h in scenario.examples.headers) h.trim().toLowerCase(),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.table_rows_outlined,
                    size: 17,
                    color: colors.tertiary,
                  ),
                  Text(
                    '${language.examplesKeyword}:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.tertiaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${scenario.examples.rows.length} ligne(s)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                key: ValueKey('qa-edit-examples-btn-${scenario.id}'),
                onPressed: onEditExamples,
                icon: const Icon(Icons.table_chart_outlined, size: 16),
                label: const Text('Éditer les Exemples'),
              ),
            ],
          ),
          if (outlineVars.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Variables détectées :',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final v in outlineVars)
                  _OutlineVariableBadge(
                    variableName: v,
                    isCovered: headerLowerSet.contains(v.toLowerCase()),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (scenario.examples.headers.isEmpty)
            Text(
              outlineVars.isNotEmpty
                  ? 'Aucune table Exemples renseignée. Cliquez sur « Éditer les Exemples » pour alimenter ${outlineVars.map((v) => '<$v>').join(', ')}.'
                  : 'Aucune table Exemples renseignée. Cliquez sur « Éditer les Exemples » pour définir les colonnes et jeux de valeurs.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _PipeDataTablePreview(
                headers: scenario.examples.headers,
                rows: scenario.examples.rows,
              ),
            ),
        ],
      ),
    );
  }
}

class _OutlineVariableBadge extends StatelessWidget {
  const _OutlineVariableBadge({
    required this.variableName,
    required this.isCovered,
  });

  final String variableName;
  final bool isCovered;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = isCovered ? colors.secondaryContainer : colors.errorContainer;
    final fg = isCovered
        ? colors.onSecondaryContainer
        : colors.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '<$variableName>',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontFamily: 'Consolas',
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PipeDataTablePreview extends StatelessWidget {
  const _PipeDataTablePreview({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    var colCount = headers.length;
    for (final r in rows) {
      if (r.length > colCount) colCount = r.length;
    }
    if (colCount == 0) return const SizedBox.shrink();

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(
        color: colors.outlineVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      children: [
        if (headers.isNotEmpty)
          TableRow(
            decoration: BoxDecoration(color: colors.surfaceContainerHighest),
            children: [
              for (var c = 0; c < colCount; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    c < headers.length ? headers[c] : '',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'Consolas',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        for (final row in rows)
          TableRow(
            children: [
              for (var c = 0; c < colCount; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    c < row.length ? row[c] : '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Consolas',
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _FeatureCodePreviewPane extends StatelessWidget {
  const _FeatureCodePreviewPane({
    required this.fileName,
    required this.language,
    required this.content,
  });

  final String fileName;
  final GherkinKeywordLanguage language;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      key: const ValueKey('qa-feature-code-preview-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colors.surfaceContainerLow,
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: colors.primary,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _CodeBadge(
                    text: language.gherkinHeader,
                    backgroundColor: colors.secondaryContainer,
                    foregroundColor: colors.onSecondaryContainer,
                  ),
                ],
              ),
              OutlinedButton.icon(
                key: const ValueKey('qa-copy-single-feature-btn'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  await Clipboard.setData(ClipboardData(text: content));
                  messenger?.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Fichier .feature copié dans le presse-papiers',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copier'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: SelectableText(
                content,
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 13,
                  height: 1.48,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<String> _parseTagsInput(String raw) {
  final tokens = raw.split(RegExp(r'[,;\r\n\s]+'));
  final tags = <String>[];
  final seen = <String>{};
  for (final token in tokens) {
    final normalized = GherkinFeatureSpec.normalizeTag(token);
    if (normalized.isNotEmpty && seen.add(normalized.toLowerCase())) {
      tags.add(normalized);
    }
  }
  return tags;
}

List<List<String>> _parsePipeOrCsvMatrix(String raw) {
  final lines = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  if (lines.isEmpty) return const <List<String>>[];

  final matrix = <List<String>>[];
  for (final line in lines) {
    if (line.contains('|')) {
      var trimmed = line;
      if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
      if (trimmed.endsWith('|') && !trimmed.endsWith(r'\|')) {
        trimmed = trimmed.substring(0, trimmed.length - 1);
      }
      final cells = trimmed
          .split(RegExp(r'(?<!\\)\|'))
          .map((c) => c.replaceAll(r'\|', '|').replaceAll(r'\\', r'\').trim())
          .toList();
      matrix.add(cells);
    } else if (line.contains(';')) {
      matrix.add(line.split(';').map((c) => c.trim()).toList());
    } else {
      matrix.add(line.split(',').map((c) => c.trim()).toList());
    }
  }
  return matrix;
}

String _formatPipeMatrix(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  var colCount = 0;
  for (final r in rows) {
    if (r.length > colCount) colCount = r.length;
  }
  if (colCount == 0) return '';
  final widths = List<int>.filled(colCount, 0);
  for (final row in rows) {
    for (var c = 0; c < colCount; c++) {
      final cell = c < row.length ? row[c] : '';
      if (cell.length > widths[c]) widths[c] = cell.length;
    }
  }
  final buf = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final padded = [
      for (var c = 0; c < colCount; c++)
        (c < row.length ? row[c] : '').padRight(widths[c]),
    ];
    if (r > 0) buf.writeln();
    buf.write('| ${padded.join(' | ')} |');
  }
  return buf.toString();
}

class _FeatureFormDialog extends StatefulWidget {
  const _FeatureFormDialog({
    required this.project,
    required this.existing,
    required this.suggestedCode,
    required this.generatedId,
  });

  final SpecForgeProject project;
  final GherkinFeatureSpec? existing;
  final String suggestedCode;
  final String generatedId;

  @override
  State<_FeatureFormDialog> createState() => _FeatureFormDialogState();
}

class _FeatureFormDialogState extends State<_FeatureFormDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _narrativeCtrl;
  late final TextEditingController _tagsCtrl;
  late String _moduleId;
  late String _personaId;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeCtrl = TextEditingController(
      text: existing?.code ?? widget.suggestedCode,
    );
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _narrativeCtrl = TextEditingController(text: existing?.narrative ?? '');
    _tagsCtrl = TextEditingController(text: existing?.tags.join(' ') ?? '');
    final modules = widget.project.cahierDesCharges.modules;
    final rawModule = existing?.moduleId ?? '';
    _moduleId = modules.any((m) => m.id == rawModule) ? rawModule : '';

    final personas = widget.project.vision.personas;
    final rawPersona = existing?.personaId ?? '';
    _personaId = personas.any((p) => p.id == rawPersona) ? rawPersona : '';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _narrativeCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Le titre de la feature est requis.');
      return;
    }
    final code = _codeCtrl.text.trim().isEmpty
        ? widget.suggestedCode
        : _codeCtrl.text.trim();
    final built = GherkinFeatureSpec(
      id: widget.generatedId,
      code: code,
      title: title,
      moduleId: _moduleId,
      personaId: _personaId,
      narrative: _narrativeCtrl.text.trim(),
      tags: _parseTagsInput(_tagsCtrl.text),
      backgroundSteps:
          widget.existing?.backgroundSteps ?? const <GherkinStep>[],
      scenarios: widget.existing?.scenarios ?? const <GherkinScenarioSpec>[],
    );
    Navigator.of(context).pop(built);
  }

  @override
  Widget build(BuildContext context) {
    final modules = widget.project.cahierDesCharges.modules;
    final personas = widget.project.vision.personas;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      actionsOverflowButtonSpacing: 8,
      title: Text(
        widget.existing == null
            ? 'Nouvelle feature Gherkin'
            : 'Modifier la feature ${widget.existing!.code}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('qa-feature-code-input'),
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code (ex. FEAT-001)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('qa-feature-title-input'),
                controller: _titleCtrl,
                autofocus: widget.existing == null,
                decoration: InputDecoration(
                  labelText: 'Titre de la fonctionnalité *',
                  errorText: _titleError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('qa-feature-module-$_moduleId'),
                initialValue: _moduleId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Module fonctionnel',
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
                  for (final module in modules)
                    DropdownMenuItem(
                      value: module.id,
                      child: Text(module.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _moduleId = val);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('qa-feature-persona-$_personaId'),
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
                        persona.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _personaId = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('qa-feature-narrative-input'),
                controller: _narrativeCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Récit (En tant que... Je veux... Afin de...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('qa-feature-tags-input'),
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tags Gherkin (@smoke @commande)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('qa-feature-cancel-btn'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('qa-feature-save-btn'),
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }
}

class _ScenarioFormDialog extends StatefulWidget {
  const _ScenarioFormDialog({
    required this.project,
    required this.existing,
    required this.suggestedCode,
    required this.generatedId,
  });

  final SpecForgeProject project;
  final GherkinScenarioSpec? existing;
  final String suggestedCode;
  final String generatedId;

  @override
  State<_ScenarioFormDialog> createState() => _ScenarioFormDialogState();
}

class _ScenarioFormDialogState extends State<_ScenarioFormDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _tagsCtrl;
  late bool _isOutline;
  late final Set<String> _requirementRefs;
  late final Set<String> _useCaseRefs;
  late final Set<String> _ruleRefs;
  late final Set<String> _journeyRefs;
  late final Set<String> _screenRefs;
  late final Set<String> _fixtureRefs;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeCtrl = TextEditingController(
      text: existing?.code ?? widget.suggestedCode,
    );
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _tagsCtrl = TextEditingController(text: existing?.tags.join(' ') ?? '');
    _isOutline = existing?.isOutline ?? false;
    _requirementRefs = Set<String>.from(
      existing?.requirementIds ?? const <String>[],
    );
    _useCaseRefs = Set<String>.from(existing?.useCaseIds ?? const <String>[]);
    _ruleRefs = Set<String>.from(existing?.businessRuleIds ?? const <String>[]);
    _journeyRefs = Set<String>.from(existing?.journeyIds ?? const <String>[]);
    _screenRefs = Set<String>.from(existing?.screenIds ?? const <String>[]);
    _fixtureRefs = Set<String>.from(existing?.fixtureIds ?? const <String>[]);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  bool _containsRef(Set<String> target, List<String> aliases) {
    final lowerAliases = <String>{
      for (final a in aliases)
        if (a.trim().isNotEmpty) a.trim().toLowerCase(),
    };
    return target.any((r) => lowerAliases.contains(r.trim().toLowerCase()));
  }

  void _toggleRef(Set<String> target, String canonical, List<String> aliases) {
    final lowerAliases = <String>{
      for (final a in aliases)
        if (a.trim().isNotEmpty) a.trim().toLowerCase(),
    };
    setState(() {
      final hadMatch = target.any(
        (r) => lowerAliases.contains(r.trim().toLowerCase()),
      );
      target.removeWhere((r) => lowerAliases.contains(r.trim().toLowerCase()));
      if (!hadMatch) {
        target.add(canonical);
      }
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Le titre du scénario est requis.');
      return;
    }
    final code = _codeCtrl.text.trim().isEmpty
        ? widget.suggestedCode
        : _codeCtrl.text.trim();
    final built = GherkinScenarioSpec(
      id: widget.generatedId,
      code: code,
      title: title,
      isOutline: _isOutline,
      tags: _parseTagsInput(_tagsCtrl.text),
      steps: widget.existing?.steps ?? const <GherkinStep>[],
      examples: widget.existing?.examples ?? GherkinExamplesTable.empty,
      requirementIds: _requirementRefs.toList(),
      useCaseIds: _useCaseRefs.toList(),
      businessRuleIds: _ruleRefs.toList(),
      journeyIds: _journeyRefs.toList(),
      screenIds: _screenRefs.toList(),
      fixtureIds: _fixtureRefs.toList(),
    );
    Navigator.of(context).pop(built);
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final reqs = project.cahierDesCharges.functionalRequirements;
    final useCases = project.cahierDesCharges.useCases;
    final rules = project.businessRules;
    final journeys = project.uxSpec.journeys;
    final screens = project.uxSpec.screens;
    final fixtures = project.qaSpec.fixtures;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      actionsOverflowButtonSpacing: 8,
      title: Text(
        widget.existing == null
            ? 'Nouveau scénario Gherkin'
            : 'Modifier le scénario ${widget.existing!.code}',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('qa-scenario-code-input'),
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code (ex. SCN-001)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('qa-scenario-title-input'),
                controller: _titleCtrl,
                autofocus: widget.existing == null,
                decoration: InputDecoration(
                  labelText: 'Titre du scénario *',
                  errorText: _titleError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('qa-scenario-outline-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Plan du Scénario (Scenario Outline)'),
                subtitle: const Text(
                  'Paramètre les étapes avec des variables <colonne> et une table Exemples.',
                ),
                value: _isOutline,
                onChanged: (val) => setState(() => _isOutline = val),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('qa-scenario-tags-input'),
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tags (@nominal @rg-001)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (reqs.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildChipPickerSection(
                  context,
                  title: 'Exigences fonctionnelles (EXF)',
                  chips: [
                    for (final req in reqs)
                      FilterChip(
                        label: Text(
                          '${req.code} · ${req.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _containsRef(_requirementRefs, <String>[
                          req.id,
                          req.code,
                        ]),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _toggleRef(
                          _requirementRefs,
                          req.code.isNotEmpty ? req.code : req.id,
                          <String>[req.id, req.code],
                        ),
                      ),
                  ],
                ),
              ],
              if (useCases.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildChipPickerSection(
                  context,
                  title: 'Cas d’usage (UC)',
                  chips: [
                    for (final uc in useCases)
                      FilterChip(
                        label: Text(uc.title, overflow: TextOverflow.ellipsis),
                        selected: _containsRef(_useCaseRefs, <String>[
                          uc.id,
                          uc.title,
                        ]),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _toggleRef(
                          _useCaseRefs,
                          uc.id,
                          <String>[uc.id, uc.title],
                        ),
                      ),
                  ],
                ),
              ],
              if (rules.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildChipPickerSection(
                  context,
                  title: 'Règles de gestion (RG)',
                  chips: [
                    for (final rule in rules)
                      FilterChip(
                        label: Text(
                          '${rule.code} · ${rule.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _containsRef(_ruleRefs, <String>[
                          rule.id,
                          rule.code,
                        ]),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _toggleRef(
                          _ruleRefs,
                          rule.code.isNotEmpty ? rule.code : rule.id,
                          <String>[rule.id, rule.code],
                        ),
                      ),
                  ],
                ),
              ],
              if (journeys.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildChipPickerSection(
                  context,
                  title: 'Parcours UX (JRN)',
                  chips: [
                    for (final jrn in journeys)
                      FilterChip(
                        label: Text(
                          '${jrn.code} · ${jrn.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _containsRef(_journeyRefs, <String>[
                          jrn.id,
                          jrn.code,
                        ]),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _toggleRef(
                          _journeyRefs,
                          jrn.code.isNotEmpty && jrn.code != 'JRN'
                              ? jrn.code
                              : jrn.id,
                          <String>[jrn.id, jrn.code],
                        ),
                      ),
                  ],
                ),
              ],
              if (screens.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildChipPickerSection(
                  context,
                  title: 'Écrans UX (SCR)',
                  chips: [
                    for (final scr in screens)
                      FilterChip(
                        label: Text(
                          '${scr.code} · ${scr.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _containsRef(_screenRefs, <String>[
                          scr.id,
                          scr.code,
                        ]),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _toggleRef(
                          _screenRefs,
                          scr.code.isNotEmpty && scr.code != 'SCR'
                              ? scr.code
                              : scr.id,
                          <String>[scr.id, scr.code],
                        ),
                      ),
                  ],
                ),
              ],
              if (fixtures.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildChipPickerSection(
                  context,
                  title: 'Jeux d’essais (FIX)',
                  chips: [
                    for (final fix in fixtures)
                      FilterChip(
                        label: Text(
                          '${fix.code} · ${fix.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _containsRef(_fixtureRefs, <String>[
                          fix.id,
                          fix.code,
                        ]),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _toggleRef(
                          _fixtureRefs,
                          fix.code.isNotEmpty && fix.code != 'FIX'
                              ? fix.code
                              : fix.id,
                          <String>[fix.id, fix.code],
                        ),
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
          key: const ValueKey('qa-scenario-cancel-btn'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('qa-scenario-save-btn'),
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }

  Widget _buildChipPickerSection(
    BuildContext context, {
    required String title,
    required List<Widget> chips,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    );
  }
}

class _GherkinStepFormDialog extends StatefulWidget {
  const _GherkinStepFormDialog({
    required this.language,
    required this.existing,
    required this.defaultKeyword,
    required this.generatedId,
    required this.isOutlineContext,
    required this.dialogTitle,
  });

  final GherkinKeywordLanguage language;
  final GherkinStep? existing;
  final GherkinStepKeyword defaultKeyword;
  final String generatedId;
  final bool isOutlineContext;
  final String dialogTitle;

  @override
  State<_GherkinStepFormDialog> createState() => _GherkinStepFormDialogState();
}

class _GherkinStepFormDialogState extends State<_GherkinStepFormDialog> {
  late GherkinStepKeyword _keyword;
  late final TextEditingController _textCtrl;
  late final TextEditingController _docStringCtrl;
  late final TextEditingController _dataTableCtrl;
  String? _textError;

  @override
  void initState() {
    super.initState();
    _keyword = widget.existing?.keyword ?? widget.defaultKeyword;
    _textCtrl = TextEditingController(text: widget.existing?.text ?? '');
    _docStringCtrl = TextEditingController(
      text: widget.existing?.docString ?? '',
    );
    _dataTableCtrl = TextEditingController(
      text: widget.existing != null && widget.existing!.dataTable.isNotEmpty
          ? _formatPipeMatrix(widget.existing!.dataTable)
          : '',
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _docStringCtrl.dispose();
    _dataTableCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _textError = 'L’énoncé du pas Gherkin est requis.');
      return;
    }
    final parsedTable = _parsePipeOrCsvMatrix(_dataTableCtrl.text);
    final step = GherkinStep(
      id: widget.generatedId,
      keyword: _keyword,
      text: text,
      docString: _docStringCtrl.text.trim(),
      dataTable: parsedTable,
    );
    Navigator.of(context).pop(step);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      actionsOverflowButtonSpacing: 8,
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<GherkinStepKeyword>(
                key: ValueKey('qa-step-keyword-${_keyword.name}'),
                initialValue: _keyword,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mot-clé Gherkin',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final kw in GherkinStepKeyword.values)
                    DropdownMenuItem(
                      value: kw,
                      child: Text(
                        '${kw.keywordFor(widget.language)} (${kw.name.toUpperCase()})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _keyword = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('qa-step-text-input'),
                controller: _textCtrl,
                autofocus: widget.existing == null,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Énoncé du pas (sans mot-clé initial) *',
                  hintText: widget.isOutlineContext
                      ? 'Ex: l’utilisateur saisit le montant <montant>'
                      : 'Ex: la commande FIX-001 est enregistrée',
                  errorText: _textError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_textError != null) setState(() => _textError = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('qa-step-datatable-input'),
                controller: _dataTableCtrl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
                decoration: const InputDecoration(
                  labelText: 'Table de données optionnelle (pipe | ou CSV)',
                  hintText: '| champ | valeur |\n| statut | VALIDE |',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('qa-step-docstring-input'),
                controller: _docStringCtrl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
                decoration: const InputDecoration(
                  labelText: 'DocString optionnel (""" ... """)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('qa-step-cancel-btn'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('qa-step-save-btn'),
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

class _ExamplesTableEditorDialog extends StatefulWidget {
  const _ExamplesTableEditorDialog({required this.scenario});

  final GherkinScenarioSpec scenario;

  @override
  State<_ExamplesTableEditorDialog> createState() =>
      _ExamplesTableEditorDialogState();
}

class _ExamplesTableEditorDialogState
    extends State<_ExamplesTableEditorDialog> {
  late final TextEditingController _tableCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.scenario.examples;
    final outlineVars = widget.scenario.referencedOutlineVariables.toList();
    String initialText;
    if (existing.headers.isNotEmpty) {
      initialText = _formatPipeMatrix(<List<String>>[
        existing.headers,
        ...existing.rows,
      ]);
    } else if (outlineVars.isNotEmpty) {
      initialText = '| ${outlineVars.join(' | ')} |';
    } else {
      initialText = '';
    }
    _tableCtrl = TextEditingController(text: initialText);
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    super.dispose();
  }

  void _prefillDetectedVariables() {
    final vars = widget.scenario.referencedOutlineVariables.toList();
    if (vars.isEmpty) return;
    final matrix = _parsePipeOrCsvMatrix(_tableCtrl.text);
    final headers = matrix.isEmpty
        ? <String>[]
        : List<String>.from(matrix.first);
    final lowerExisting = <String>{
      for (final h in headers) h.trim().toLowerCase(),
    };
    for (final v in vars) {
      if (lowerExisting.add(v.toLowerCase())) {
        headers.add(v);
      }
    }
    final rows = [
      for (var i = 1; i < matrix.length; i++)
        [
          for (var c = 0; c < headers.length; c++)
            c < matrix[i].length ? matrix[i][c] : '',
        ],
    ];
    setState(() {
      _errorText = null;
      _tableCtrl.text = _formatPipeMatrix(<List<String>>[headers, ...rows]);
    });
  }

  (List<String> headers, List<List<String>> rows)? _tryBuildTable() {
    final matrix = _parsePipeOrCsvMatrix(_tableCtrl.text);
    if (matrix.isEmpty) {
      return (const <String>[], const <List<String>>[]);
    }
    final rawHeaders = matrix.first;
    final headers = <String>[];
    for (final cell in rawHeaders) {
      final trimmed = cell.trim();
      if (trimmed.isEmpty) return null;
      headers.add(trimmed);
    }
    if (headers.isEmpty) return null;
    final rows = <List<String>>[
      for (var r = 1; r < matrix.length; r++)
        <String>[
          for (var c = 0; c < headers.length; c++)
            c < matrix[r].length ? matrix[r][c].trim() : '',
        ],
    ];
    return (headers, rows);
  }

  void _submit() {
    final parsed = _tryBuildTable();
    if (parsed == null) {
      setState(
        () => _errorText = 'Chaque colonne de la première ligne d’en-tête doit avoir un nom non vide.',
      );
      return;
    }
    final (headers, rows) = parsed;
    final table = headers.isEmpty
        ? GherkinExamplesTable.empty
        : GherkinExamplesTable(headers: headers, rows: rows);
    table.validate();
    Navigator.of(context).pop(table);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final outlineVars = widget.scenario.referencedOutlineVariables;
    final parsed = _tryBuildTable();
    final currentHeadersLower = <String>{
      if (parsed != null)
        for (final h in parsed.$1) h.toLowerCase(),
    };

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      actionsOverflowButtonSpacing: 8,
      title: Text('Éditer les Exemples — ${widget.scenario.code}'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Saisissez la 1re ligne pour les en-têtes de colonnes, puis une ligne par jeu d’essai (syntaxe Gherkin `| col1 | col2 |` ou CSV `col1, col2`).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (outlineVars.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final v in outlineVars)
                      _OutlineVariableBadge(
                        variableName: v,
                        isCovered: currentHeadersLower.contains(
                          v.toLowerCase(),
                        ),
                      ),
                    TextButton.icon(
                      key: const ValueKey('qa-examples-prefill-vars-btn'),
                      onPressed: _prefillDetectedVariables,
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
                      label: const Text('Ajouter <variables> aux colonnes'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('qa-examples-table-input'),
                controller: _tableCtrl,
                autofocus: true,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Table Exemples (en-têtes + lignes)',
                  hintText: '| montant | plafond | resultat |\n| 120     | 500     | accepte  |\n| 650     | 500     | rejete   |',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _errorText = null),
              ),
              if (parsed != null && parsed.$1.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Aperçu : ${parsed.$1.length} colonne(s) · ${parsed.$2.length} ligne(s)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('qa-examples-cancel-btn'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('qa-examples-save-btn'),
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
