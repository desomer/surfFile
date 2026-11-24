/// Atelier de l'étape QA 4 : Audit de couverture 360° Métier+UX↔Tests et exports BDD/Gherkin & TDD ([QaReviewExportView]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/business_rule_spec.dart';
import '../../models/qa/qa_coherence_issue.dart';
import '../../models/qa/qa_forge_stage.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../../models/ux/ux_journey_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import '../../services/exporters/gherkin_feature_exporter.dart';
import '../../services/exporters/qa_markdown_exporter.dart';
import '../../services/exporters/qa_tdd_prompt_exporter.dart';
import '../../services/qa_coherence_analyzer.dart';
import '../../services/spec_forge_controller.dart';
import '../workspace/markdown_viewer_dialog.dart';

/// Vue d'audit de couverture 360° Métier+UX↔QA, de prévisualisation des livrables Gherkin/TDD et d'export sur disque.
class QaReviewExportView extends StatelessWidget {
  /// Crée la vue d'audit et d'export QA connectée au [controller].
  const QaReviewExportView({
    required this.controller,
    this.onContinueToCostWizard,
    this.markdownViewerSurfaceBuilder,
    this.markdownBrowserLauncher,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Callback optionnel permettant d'enchaîner directement vers l'Estimation de coût IT.
  final VoidCallback? onContinueToCostWizard;

  /// Constructeur optionnel pour remplacer la WebView dans le visualisateur Markdown (tests).
  final SpecMarkdownViewerSurfaceBuilder? markdownViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour l'ouverture du visualisateur Markdown (tests).
  final SpecMarkdownBrowserLauncher? markdownBrowserLauncher;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    if (project == null) return const SizedBox.shrink();

    final localIssues = QaCoherenceAnalyzer.analyze(
      project,
      companyGlossary: controller.companyGlossary,
    );
    final localIds = <String>{for (final issue in localIssues) issue.id};
    final aiIssues = project.qaSpec.coherenceIssues
        .where((i) => i.source == 'ai' && !localIds.contains(i.id))
        .toList();
    final allIssues = <QaCoherenceIssue>[...localIssues, ...aiIssues];

    final tddPrompt = QaTddPromptExporter.export(project);
    final featuresPreview = GherkinFeatureExporter.exportCombinedPreview(
      project,
    );
    final fixturesBundlePreview = const JsonEncoder.withIndent('  ')
        .convert(<String, Object?>{
          'fixtures': [for (final f in project.qaSpec.fixtures) f.toJson()],
        });
    final qaMarkdown = QaMarkdownExporter.export(project);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sep = Platform.pathSeparator;
    final exportDirPath =
        '${controller.store.rootDirectory.path}${sep}exports$sep${_safeName(project.id)}${sep}qa';

    return DefaultTabController(
      key: const ValueKey('qa-review-export-view'),
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Couverture 360° & Export BDD / TDD',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (onContinueToCostWizard != null)
                      OutlinedButton.icon(
                        key: const ValueKey('qa-continue-to-cost-wizard-btn'),
                        onPressed: onContinueToCostWizard,
                        icon: const Icon(Icons.calculate_outlined, size: 16),
                        label: const Text('Estimation de coût IT'),
                      ),
                    FilledButton.icon(
                      key: const ValueKey('qa-export-all-btn'),
                      onPressed: () => _exportAllDialog(
                        context,
                        project: project,
                        defaultExportDir: exportDirPath,
                      ),
                      icon: const Icon(Icons.save_alt_rounded, size: 16),
                      label: const Text(
                        'Exporter BDD / Gherkin & TDD',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Couverture & Audit (${allIssues.length})'),
              const Tab(text: 'Prompt Agent TDD'),
              Tab(
                text: 'Features .feature (${project.qaSpec.features.length})',
              ),
              Tab(text: 'Fixtures JSON (${project.qaSpec.fixtures.length})'),
              const Tab(text: 'Cahier BDD/TDD (.md)'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _QaCoverageAndAuditTab(
                  project: project,
                  issues: allIssues,
                  onJumpToStage: (stage) => controller.goToQaStage(stage),
                ),
                _QaExportCodeTab(
                  content: tddPrompt,
                  filename: 'prompt_tdd_agent.md',
                  copyButtonKey: const ValueKey('qa-review-copy-tdd-prompt'),
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('qa-review-open-tdd-prompt-viewer'),
                      onPressed: () => showSpecMarkdownViewerDialog(
                        context,
                        markdown: tddPrompt,
                        title: 'Prompt Agent TDD — ${project.name}',
                        filenameStem:
                            '${_safeName(project.name)}_prompt_tdd_agent',
                        exportDirectory: Directory(exportDirPath),
                        openInBrowser: markdownBrowserLauncher,
                        surfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.preview_rounded, size: 16),
                      label: const Text(
                        'Ouvrir le visualisateur',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                _QaExportCodeTab(
                  content: featuresPreview,
                  filename: 'features/*.feature',
                  copyButtonKey: const ValueKey('qa-review-copy-features'),
                  colors: colors,
                ),
                _QaExportCodeTab(
                  content: fixturesBundlePreview,
                  filename: 'fixtures_bundle.json',
                  copyButtonKey: const ValueKey('qa-review-copy-fixtures'),
                  colors: colors,
                ),
                _QaExportCodeTab(
                  content: qaMarkdown,
                  filename: 'specification_bdd_tdd.md',
                  copyButtonKey: const ValueKey('qa-review-copy-qa-md'),
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('qa-review-open-qa-md-viewer'),
                      onPressed: () => showSpecMarkdownViewerDialog(
                        context,
                        markdown: qaMarkdown,
                        title: 'Cahier BDD / TDD — ${project.name}',
                        filenameStem:
                            '${_safeName(project.name)}_specification_bdd_tdd',
                        exportDirectory: Directory(exportDirPath),
                        openInBrowser: markdownBrowserLauncher,
                        surfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.preview_rounded, size: 16),
                      label: const Text(
                        'Ouvrir le visualisateur',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  Future<void> _exportAllDialog(
    BuildContext context, {
    required SpecForgeProject project,
    required String defaultExportDir,
  }) async {
    final targetPath = await showDialog<String>(
      context: context,
      builder: (_) => _QaExportDialog(defaultDir: defaultExportDir),
    );

    if (targetPath == null || targetPath.trim().isEmpty) return;

    final dir = Directory(targetPath.trim());
    await QaDirectoryExporter.exportQaDirectory(project, dir);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exports BDD / TDD enregistrés dans ${dir.path}'),
        ),
      );
    }
  }

  static String _safeName(String input) {
    final clean = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return clean.isEmpty ? 'spec' : clean;
  }
}

class _QaExportDialog extends StatefulWidget {
  const _QaExportDialog({required this.defaultDir});

  final String defaultDir;

  @override
  State<_QaExportDialog> createState() => _QaExportDialogState();
}

class _QaExportDialogState extends State<_QaExportDialog> {
  late final TextEditingController _pathCtrl = TextEditingController(
    text: widget.defaultDir,
  );

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AlertDialog(
      title: const Text('Exporter les livrables BDD / Gherkin & TDD'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('qa-export-dir-field'),
                controller: _pathCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dossier de destination',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Fichiers générés : features/*.feature, fixtures/*.json, fixtures_bundle.json, specification_bdd_tdd.md, specification_qa.json et prompt_tdd_agent.md.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('qa-export-cancel-btn'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('qa-export-confirm-btn'),
          onPressed: () => Navigator.pop(context, _pathCtrl.text),
          child: const Text('Exporter'),
        ),
      ],
    );
  }
}

class _QaCoverageAndAuditTab extends StatelessWidget {
  const _QaCoverageAndAuditTab({
    required this.project,
    required this.issues,
    required this.onJumpToStage,
  });

  final SpecForgeProject project;
  final List<QaCoherenceIssue> issues;
  final ValueChanged<QaForgeStage> onJumpToStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final qa = project.qaSpec;
    final ux = project.uxSpec;

    final mustReqs = project.cahierDesCharges.functionalRequirements
        .where((r) => r.priority == RequirementPriority.must)
        .toList();
    final mustCovered = mustReqs
        .where((req) => _isRequirementCovered(project, req))
        .length;

    final activeRules = project.businessRules.where((r) => r.active).toList();
    final rulesCovered = activeRules
        .where((rule) => _isRuleCovered(project, rule))
        .length;

    final showUxMetrics = ux.hasContent;
    final journeysCovered = showUxMetrics
        ? ux.journeys.where((j) => _isJourneyCovered(project, j)).length
        : 0;
    final screensCovered = showUxMetrics
        ? ux.screens.where((s) => _isScreenCovered(project, s)).length
        : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: const ValueKey('qa-coverage-summary-card'),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Synthèse de couverture 360° (Métier + UX ↔ Tests)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        qa.gherkinLanguage.gherkinHeader,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _QaCoverageMetricBadge(
                      icon: Icons.dataset_outlined,
                      label: 'Fixtures (FIX)',
                      value: '${qa.fixtures.length}',
                      colors: colors,
                    ),
                    _QaCoverageMetricBadge(
                      icon: Icons.fact_check_outlined,
                      label: 'Features / Scénarios',
                      value: '${qa.features.length} / ${qa.totalScenarioCount}',
                      colors: colors,
                    ),
                    _QaCoverageMetricBadge(
                      icon: Icons.science_outlined,
                      label: 'Suites / Cas TDD',
                      value: '${qa.tddSuites.length} / ${qa.totalTddCaseCount}',
                      colors: colors,
                    ),
                    _QaCoverageMetricBadge(
                      icon: Icons.checklist_rtl_rounded,
                      label: 'EXF Must couvertes',
                      value: '$mustCovered / ${mustReqs.length}',
                      colors: colors,
                    ),
                    _QaCoverageMetricBadge(
                      icon: Icons.gavel_rounded,
                      label: 'RG-xxx couvertes',
                      value: '$rulesCovered / ${activeRules.length}',
                      colors: colors,
                    ),
                    if (showUxMetrics) ...[
                      _QaCoverageMetricBadge(
                        icon: Icons.route_outlined,
                        label: 'Parcours UX couverts',
                        value: '$journeysCovered / ${ux.journeys.length}',
                        colors: colors,
                      ),
                      _QaCoverageMetricBadge(
                        icon: Icons.dashboard_customize_outlined,
                        label: 'Écrans UX couverts',
                        value: '$screensCovered / ${ux.screens.length}',
                        colors: colors,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (issues.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 44, color: colors.primary),
                  const SizedBox(height: 10),
                  Text(
                    'Aucune anomalie QA détectée',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Jeux d’essais, scénarios Gherkin, suites TDD et couverture 360° Métier+UX↔Tests sont cohérents.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final issue in issues)
            _QaCoherenceIssueCard(issue: issue, onJumpToStage: onJumpToStage),
      ],
    );
  }

  static bool _isRequirementCovered(
    SpecForgeProject project,
    FunctionalRequirement req,
  ) {
    final qa = project.qaSpec;
    final inGherkin = qa.features.any(
      (f) => f.scenarios.any(
        (sc) => sc.requirementIds.any((ref) => _matchesRequirement(req, ref)),
      ),
    );
    if (inGherkin) return true;
    return qa.tddSuites.any(
      (s) => s.cases.any(
        (tc) => tc.requirementIds.any((ref) => _matchesRequirement(req, ref)),
      ),
    );
  }

  static bool _isRuleCovered(SpecForgeProject project, BusinessRuleSpec rule) {
    final qa = project.qaSpec;
    final inGherkin = qa.features.any(
      (f) => f.scenarios.any(
        (sc) => sc.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
      ),
    );
    if (inGherkin) return true;
    return qa.tddSuites.any(
      (s) => s.cases.any(
        (tc) => tc.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
      ),
    );
  }

  static bool _isJourneyCovered(
    SpecForgeProject project,
    UxJourneySpec journey,
  ) => project.qaSpec.features.any(
    (f) => f.scenarios.any(
      (sc) => sc.journeyIds.any((ref) => _matchesJourney(journey, ref)),
    ),
  );

  static bool _isScreenCovered(SpecForgeProject project, UxScreenSpec screen) {
    final qa = project.qaSpec;
    final inGherkin = qa.features.any(
      (f) => f.scenarios.any(
        (sc) => sc.screenIds.any((ref) => _matchesScreen(screen, ref)),
      ),
    );
    if (inGherkin) return true;
    return qa.tddSuites.any(
      (s) => s.cases.any(
        (tc) => tc.screenIds.any((ref) => _matchesScreen(screen, ref)),
      ),
    );
  }

  static bool _matchesRequirement(FunctionalRequirement req, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return req.id.toLowerCase() == needle ||
        (req.code.trim().isNotEmpty && req.code.trim().toLowerCase() == needle);
  }

  static bool _matchesRule(BusinessRuleSpec rule, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return rule.id.toLowerCase() == needle ||
        (rule.code.trim().isNotEmpty &&
            rule.code.trim().toLowerCase() == needle);
  }

  static bool _matchesJourney(UxJourneySpec journey, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return journey.id.toLowerCase() == needle ||
        (journey.code.trim().isNotEmpty &&
            journey.code.trim().toLowerCase() == needle) ||
        journey.name.toLowerCase() == needle;
  }

  static bool _matchesScreen(UxScreenSpec screen, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return screen.id.toLowerCase() == needle ||
        (screen.code.trim().isNotEmpty &&
            screen.code.trim().toLowerCase() == needle) ||
        (screen.routeId.trim().isNotEmpty &&
            screen.routeId.trim().toLowerCase() == needle) ||
        screen.name.toLowerCase() == needle;
  }
}

class _QaCoverageMetricBadge extends StatelessWidget {
  const _QaCoverageMetricBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: colors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QaCoherenceIssueCard extends StatelessWidget {
  const _QaCoherenceIssueCard({
    required this.issue,
    required this.onJumpToStage,
  });

  final QaCoherenceIssue issue;
  final ValueChanged<QaForgeStage> onJumpToStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, tint) = switch (issue.severity) {
      CoherenceSeverity.error => (Icons.error_outline_rounded, colors.error),
      CoherenceSeverity.warning => (
        Icons.warning_amber_rounded,
        colors.tertiary,
      ),
      CoherenceSeverity.info => (Icons.info_outline_rounded, colors.primary),
    };

    return Card(
      key: ValueKey('qa-coherence-issue-${issue.id}'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: tint, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${issue.code} · ${issue.title}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  key: ValueKey('qa-coherence-jump-${issue.id}'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => onJumpToStage(issue.stage),
                  child: Text(
                    'Voir ${issue.stage.shortLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (issue.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(issue.description, style: theme.textTheme.bodyMedium),
            ],
            if (issue.suggestion.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Suggestion : ${issue.suggestion}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QaExportCodeTab extends StatelessWidget {
  const _QaExportCodeTab({
    required this.content,
    required this.filename,
    required this.colors,
    this.copyButtonKey,
    this.extraActions = const <Widget>[],
  });

  final String content;
  final String filename;
  final ColorScheme colors;
  final Key? copyButtonKey;
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: colors.surfaceContainerLow,
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                filename,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...extraActions,
                  OutlinedButton.icon(
                    key: copyButtonKey,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copié dans le presse-papiers'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copier'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
