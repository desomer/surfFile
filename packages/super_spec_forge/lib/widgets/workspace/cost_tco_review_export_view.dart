/// Atelier de l'étape Coûts 4 : Synthèse TCO 1/3/5 ans, Risques EMV, Cohérence et Exports MD/HTML/CSV/JSON ([CostTcoReviewExportView]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/cost/cost_coherence_issue.dart';
import '../../models/cost/cost_forge_spec.dart';
import '../../models/cost/cost_risk_item_spec.dart';
import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../../services/cost_calculator.dart';
import '../../services/cost_coherence_analyzer.dart';
import '../../services/exporters/cost_csv_exporter.dart';
import '../../services/exporters/cost_markdown_exporter.dart';
import '../../services/spec_forge_controller.dart';
import 'markdown_viewer_dialog.dart';

/// Vue exécutive de l'étape 4 du wizard d'estimation de coût IT : TCO 1/3/5 ans,
/// comparatif MVP/V1/Cible & gain IA, registre des risques EMV, audit de cohérence et exports.
class CostTcoReviewExportView extends StatefulWidget {
  /// Crée la vue de synthèse TCO et d'export connectée au [controller].
  const CostTcoReviewExportView({
    required this.controller,
    this.markdownViewerSurfaceBuilder,
    this.markdownBrowserLauncher,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Constructeur optionnel pour remplacer la WebView dans le visualisateur Markdown (tests).
  final SpecMarkdownViewerSurfaceBuilder? markdownViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour l'ouverture du visualisateur Markdown (tests).
  final SpecMarkdownBrowserLauncher? markdownBrowserLauncher;

  @override
  State<CostTcoReviewExportView> createState() =>
      _CostTcoReviewExportViewState();
}

class _CostTcoReviewExportViewState extends State<CostTcoReviewExportView> {
  String _selectedCsvOrJsonKey = 'cost_summary_tco.csv';

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final spec = project.costSpec;
    final summary = CostCalculator.compute(spec);
    final localIssues = CostCoherenceAnalyzer.analyze(project);
    final localIds = <String>{for (final i in localIssues) i.id};
    final aiIssues = spec.coherenceIssues
        .where((i) => i.source == 'ai' && !localIds.contains(i.id))
        .toList();
    final allIssues = <CostCoherenceIssue>[...localIssues, ...aiIssues];

    final markdown = CostMarkdownExporter.export(project);
    final csvFiles = CostCsvExporter.exportAllFiles(project);
    final jsonPreview = const JsonEncoder.withIndent(
      '  ',
    ).convert(spec.toJson());

    final sep = Platform.pathSeparator;
    final safeId = project.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final exportDirPath =
        '${widget.controller.store.rootDirectory.path}${sep}exports$sep$safeId${sep}cost';

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DefaultTabController(
      key: const ValueKey('cost-tco-review-export-view'),
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
                  'Synthèse TCO, Risques & Export FinOps',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('cost-export-all-btn'),
                  onPressed: () => _exportAllToDisk(
                    context,
                    project: project,
                    markdown: markdown,
                    csvFiles: csvFiles,
                    jsonContent: jsonPreview,
                    exportDirPath: exportDirPath,
                  ),
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: const Text('Exporter Dossier Coûts IT'),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Synthèse TCO & KPI'),
              Tab(text: 'Risques EMV (${spec.riskItems.length})'),
              Tab(text: 'Audit & Cohérence (${allIssues.length})'),
              const Tab(text: 'Rapport Markdown / HTML'),
              const Tab(text: 'Exports CSV & JSON'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildExecutiveSummaryTab(spec, summary, theme, colors),
                _buildRisksTab(context, spec, summary, theme, colors),
                _buildAuditTab(allIssues, theme, colors),
                _buildMarkdownTab(
                  context,
                  project,
                  markdown,
                  exportDirPath,
                  theme,
                ),
                _buildCsvAndJsonTab(context, csvFiles, jsonPreview, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveSummaryTab(
    CostForgeSpec spec,
    CostProjectSummary summary,
    ThemeData theme,
    ColorScheme colors,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ExecCard(
                title: 'Lot MVP (Must)',
                primary: CostCalculator.formatAmount(
                  summary.mvpLot.effectiveTotalCost,
                  spec.currency,
                ),
                secondary:
                    '${CostCalculator.formatDays(summary.mvpLot.effectiveTotalDays)} (${summary.mvpLot.itemCount} lots)',
                colors: colors,
              ),
              _ExecCard(
                title: 'Lot V1 (Must + Should)',
                primary: CostCalculator.formatAmount(
                  summary.v1Lot.effectiveTotalCost,
                  spec.currency,
                ),
                secondary:
                    '${CostCalculator.formatDays(summary.v1Lot.effectiveTotalDays)} (${summary.v1Lot.itemCount} lots)',
                colors: colors,
              ),
              _ExecCard(
                title: 'Build Cible Complet',
                primary: CostCalculator.formatAmount(
                  summary.fullLot.effectiveTotalCost,
                  spec.currency,
                ),
                secondary:
                    '${CostCalculator.formatDays(summary.fullLot.effectiveTotalDays)} · P80 ${CostCalculator.formatAmount(summary.fullLot.effectiveP80Cost, spec.currency, compact: true)}',
                colors: colors,
                highlight: true,
              ),
              _ExecCard(
                title: 'Impact Accélération IA',
                primary: spec.aiProductivity.enabled
                    ? '-${CostCalculator.formatAmount(summary.fullLot.aiSavedCost, spec.currency)}'
                    : 'Non activé',
                secondary: spec.aiProductivity.enabled
                    ? 'Classique : ${CostCalculator.formatDays(summary.fullLot.classicTotalDays)} vs IA : ${CostCalculator.formatDays(summary.fullLot.aiTotalDays)}'
                    : 'Activez l’IA à l’étape 1 pour simuler',
                colors: colors,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Projection TCO Pluriannuelle (Build + Provisions Risques EMV + Run OPEX cumulé)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TcoRow(
                    horizon: 'TCO 1 an',
                    amount: summary.tco1Year,
                    maxAmount: summary.tco5Years,
                    detail:
                        'Build ${CostCalculator.formatAmount(summary.fullLot.effectiveTotalCost, spec.currency, compact: true)} + Risques ${CostCalculator.formatAmount(summary.riskEmvCost, spec.currency, compact: true)} + Run An 1 ${CostCalculator.formatAmount(summary.yearlyRunYear1, spec.currency, compact: true)}',
                    currency: spec.currency,
                    colors: colors,
                  ),
                  const SizedBox(height: 10),
                  _TcoRow(
                    horizon: 'TCO 3 ans',
                    amount: summary.tco3Years,
                    maxAmount: summary.tco5Years,
                    detail:
                        'Incl. Run cumulé 3 ans : ${CostCalculator.formatAmount(summary.cumulativeRun3Years, spec.currency)}',
                    currency: spec.currency,
                    colors: colors,
                  ),
                  const SizedBox(height: 10),
                  _TcoRow(
                    horizon: 'TCO 5 ans',
                    amount: summary.tco5Years,
                    maxAmount: summary.tco5Years,
                    detail:
                        'Incl. Run cumulé 5 ans : ${CostCalculator.formatAmount(summary.cumulativeRun5Years, spec.currency)}',
                    currency: spec.currency,
                    colors: colors,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Répartition directe Build par discipline',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final b in summary.fullLot.byDiscipline.values)
                    if (b.itemCount > 0)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${b.discipline.label} (${b.itemCount} lot(s))',
                        ),
                        subtitle: Text(
                          'Classique : ${CostCalculator.formatDays(b.classicExpectedDays)} · Assisté IA : ${CostCalculator.formatDays(b.aiExpectedDays)}',
                        ),
                        trailing: Text(
                          CostCalculator.formatAmount(
                            spec.aiProductivity.enabled
                                ? b.aiCost
                                : b.classicCost,
                            spec.currency,
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRisksTab(
    BuildContext context,
    CostForgeSpec spec,
    CostProjectSummary summary,
    ThemeData theme,
    ColorScheme colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Provision pondérée (EMV) : ${CostCalculator.formatDays(summary.riskEmvDays)} · ${CostCalculator.formatAmount(summary.riskEmvCost, spec.currency)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => widget.controller.seedCostFromProject(),
                    icon: const Icon(Icons.warning_amber_rounded, size: 16),
                    label: const Text('Importer Hotspots Event Storming'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('cost-add-risk-btn'),
                    onPressed: () => _openRiskDialog(context, spec),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Ajouter un risque'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: spec.riskItems.isEmpty
              ? const Center(child: Text('Aucun risque budgétaire enregistré.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: spec.riskItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final r = spec.riskItems[i];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(
                          '${r.code} — ${r.title} (${r.probabilityPct.toStringAsFixed(0)} %)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Impact : ${CostCalculator.formatDays(r.impactDays)}'
                          '${r.fixedCostImpact > 0 ? ' + ${CostCalculator.formatAmount(r.fixedCostImpact, spec.currency)}' : ''}'
                          ' → EMV ${CostCalculator.formatDays(r.expectedDays)}'
                          '${r.mitigation.isNotEmpty ? '\nMitigation : ${r.mitigation}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () =>
                                  _openRiskDialog(context, spec, existing: r),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              onPressed: () {
                                final next = spec.riskItems
                                    .where((x) => x.id != r.id)
                                    .toList();
                                widget.controller.updateCostSpec(
                                  spec.copyWith(riskItems: next),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAuditTab(
    List<CostCoherenceIssue> issues,
    ThemeData theme,
    ColorScheme colors,
  ) {
    if (issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 42, color: colors.primary),
            const SizedBox(height: 8),
            const Text('Aucune anomalie de cohérence financière détectée.'),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: issues.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final issue = issues[index];
        final icon = switch (issue.severity) {
          CoherenceSeverity.error => Icons.error_outline_rounded,
          CoherenceSeverity.warning => Icons.warning_amber_rounded,
          CoherenceSeverity.info => Icons.info_outline_rounded,
        };
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(icon, color: colors.primary),
            title: Text(
              '[${issue.code}] ${issue.title}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${issue.description}'
              '${issue.suggestion.isNotEmpty ? '\nAction : ${issue.suggestion}' : ''}',
            ),
            trailing: TextButton(
              onPressed: () => widget.controller.goToCostStage(issue.stage),
              child: Text(issue.stage.shortLabel),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarkdownTab(
    BuildContext context,
    SpecForgeProject project,
    String markdown,
    String exportDirPath,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showSpecMarkdownViewerDialog(
                  context,
                  markdown: markdown,
                  title: 'Estimation de coût IT — ${project.name}',
                  filenameStem: 'estimation_couts_it',
                  exportDirectory: Directory(exportDirPath),
                  openInBrowser: widget.markdownBrowserLauncher,
                  surfaceBuilder: widget.markdownViewerSurfaceBuilder,
                ),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Aperçu HTML / PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: markdown));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text('Rapport Markdown copié.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copier Markdown'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              markdown,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCsvAndJsonTab(
    BuildContext context,
    Map<String, String> csvFiles,
    String jsonPreview,
    ThemeData theme,
  ) {
    final allEntries = <String, String>{
      ...csvFiles,
      'cost_estimation.json': jsonPreview,
    };
    final activeContent =
        allEntries[_selectedCsvOrJsonKey] ?? allEntries.values.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final key in allEntries.keys)
                ChoiceChip(
                  label: Text(key),
                  selected: _selectedCsvOrJsonKey == key,
                  onSelected: (_) =>
                      setState(() => _selectedCsvOrJsonKey = key),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: activeContent));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text('$_selectedCsvOrJsonKey copié.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copier'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              activeContent,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openRiskDialog(
    BuildContext context,
    CostForgeSpec spec, {
    CostRiskItemSpec? existing,
  }) async {
    final idx = spec.riskItems.length + 1;
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'RSK-${idx.toString().padLeft(3, '0')}',
    );
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final probCtrl = TextEditingController(
      text: (existing?.probabilityPct ?? 30.0).toStringAsFixed(0),
    );
    final daysCtrl = TextEditingController(
      text: (existing?.impactDays ?? 4.0).toString(),
    );
    final fixedCtrl = TextEditingController(
      text: (existing?.fixedCostImpact ?? 0.0).toStringAsFixed(0),
    );
    final mitCtrl = TextEditingController(text: existing?.mitigation ?? '');

    final saved = await showDialog<CostRiskItemSpec>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null ? 'Nouveau risque financier' : 'Modifier ${existing.code}',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Intitulé du risque *',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: probCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Probabilité (%)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: daysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Impact (j/h)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: fixedCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Coût fixe (${spec.currency.symbol})',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mitCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Plan de mitigation',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final t = titleCtrl.text.trim();
              if (t.isEmpty) return;
              Navigator.of(ctx).pop(
                CostRiskItemSpec(
                  id: existing?.id ?? 'rsk_${shortid.generate()}',
                  code: codeCtrl.text.trim().isEmpty
                      ? 'RSK-001'
                      : codeCtrl.text.trim(),
                  title: t,
                  probabilityPct:
                      (double.tryParse(probCtrl.text.replaceAll(',', '.')) ??
                              30.0)
                          .clamp(0.0, 100.0),
                  impactDays:
                      (double.tryParse(daysCtrl.text.replaceAll(',', '.')) ??
                              0.0)
                          .clamp(0.0, 10000.0),
                  fixedCostImpact:
                      (double.tryParse(fixedCtrl.text.replaceAll(',', '.')) ??
                              0.0)
                          .clamp(0.0, 1e9),
                  profileId: existing?.profileId ?? spec.profiles.first.id,
                  mitigation: mitCtrl.text.trim(),
                  linkedHotspotId: existing?.linkedHotspotId ?? '',
                  linkedRequirementIds:
                      existing?.linkedRequirementIds ?? const [],
                ),
              );
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (saved == null) return;
    final next = List<CostRiskItemSpec>.from(spec.riskItems);
    final i = next.indexWhere((x) => x.id == saved.id);
    if (i >= 0) {
      next[i] = saved;
    } else {
      next.add(saved);
    }
    await widget.controller.updateCostSpec(spec.copyWith(riskItems: next));
  }

  Future<void> _exportAllToDisk(
    BuildContext context, {
    required SpecForgeProject project,
    required String markdown,
    required Map<String, String> csvFiles,
    required String jsonContent,
    required String exportDirPath,
  }) async {
    final sep = Platform.pathSeparator;
    final dir = Directory(exportDirPath);
    await dir.create(recursive: true);

    await File('${dir.path}${sep}cost_estimation.md').writeAsString(markdown);
    await writeStandaloneMarkdownHtmlFile(
      markdown: markdown,
      title: 'Estimation de coût IT — ${project.name}',
      filenameStem: 'cost_estimation',
      targetDirectory: dir,
    );
    for (final entry in csvFiles.entries) {
      await File('${dir.path}$sep${entry.key}').writeAsString(entry.value);
    }
    await File('${dir.path}${sep}cost_estimation.json').writeAsString(
      jsonContent,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Dossier Coûts IT exporté dans $exportDirPath'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ExecCard extends StatelessWidget {
  const _ExecCard({
    required this.title,
    required this.primary,
    required this.secondary,
    required this.colors,
    this.highlight = false,
  });

  final String title;
  final String primary;
  final String secondary;
  final ColorScheme colors;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            primary,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            secondary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TcoRow extends StatelessWidget {
  const _TcoRow({
    required this.horizon,
    required this.amount,
    required this.maxAmount,
    required this.detail,
    required this.currency,
    required this.colors,
  });

  final String horizon;
  final double amount;
  final double maxAmount;
  final String detail;
  final dynamic currency;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final ratio = maxAmount > 0 ? (amount / maxAmount).clamp(0.05, 1.0) : 0.05;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              horizon,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              CostCalculator.formatAmount(amount, currency),
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: ratio, minHeight: 8),
        const SizedBox(height: 2),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
