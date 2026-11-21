/// Atelier de l'étape 5 : Audit de cohérence et prévisualisation/export des livrables ([ReviewExportView]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../../services/exporters/spec_json_exporter.dart';
import '../../services/exporters/spec_json_schema_html_builder.dart';
import '../../services/exporters/spec_markdown_exporter.dart';
import '../../services/exporters/spec_markdown_html_builder.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';
import '../../services/spec_coherence_analyzer.dart';
import '../../services/spec_forge_controller.dart';
import 'json_schema_viewer_dialog.dart';
import 'markdown_viewer_dialog.dart';

/// Vue de revue globale, audit de cohérence et export multi-formats.
class ReviewExportView extends StatelessWidget {
  /// Crée la vue connectée au [controller].
  const ReviewExportView({
    required this.controller,
    this.markdownViewerSurfaceBuilder,
    this.markdownBrowserLauncher,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Constructeur optionnel pour remplacer la WebView dans le visualisateur Markdown (tests).
  final SpecMarkdownViewerSurfaceBuilder? markdownViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour l'ouverture du `.html` généré (tests).
  final SpecMarkdownBrowserLauncher? markdownBrowserLauncher;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    if (project == null) return const SizedBox.shrink();

    final localIssues = SpecCoherenceAnalyzer.analyze(
      project,
      companyGlossary: controller.companyGlossary,
      modelPreferences: controller.modelPreferences,
    );
    final aiIssues = project.coherenceIssues
        .where((i) => i.source == 'ai')
        .toList();
    final allIssues = [...localIssues, ...aiIssues];

    final markdown = SpecMarkdownExporter.export(project);
    final yamlSchema = SpecSuperDesignerExporter.toYamlLightSchema(project);
    final bundle = SpecSuperDesignerExporter.toBundle(
      project,
      modelPreferencesOverride: controller.modelPreferences,
    );
    final bundlePreview = const JsonEncoder.withIndent('  ').convert({
      'repositoriesJsonSchemas': bundle.repositoriesJsonSchemas,
      'repositoriesSeedData': bundle.repositoriesSeedData,
    });
    final fullJson = SpecJsonExporter.export(project);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Revue, Cohérence & Export',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _exportAllDialog(
                    context,
                    project: project,
                    markdown: markdown,
                    yamlSchema: yamlSchema,
                    fullJson: fullJson,
                  ),
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: const Text('Exporter sur disque'),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Cohérence (${allIssues.length})'),
              const Tab(text: 'Cahier des charges (.md)'),
              const Tab(text: 'YAML super_designer'),
              const Tab(text: 'JSON Schema & Seed'),
              const Tab(text: 'JSON Complet'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CoherenceTab(
                  issues: allIssues,
                  onJumpToStage: (stage) => controller.goToStage(stage),
                ),
                _ExportCodeTab(
                  content: markdown,
                  filename: '${_safeName(project.name)}_cdc.md',
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('spec-review-open-md-viewer'),
                      onPressed: () => showSpecMarkdownViewerDialog(
                        context,
                        markdown: markdown,
                        title: 'Cahier des charges — ${project.name}',
                        filenameStem: '${_safeName(project.name)}_cdc',
                        exportDirectory: Directory(
                          '${controller.store.rootDirectory.path}${Platform.pathSeparator}exports${Platform.pathSeparator}${_safeName(project.id)}',
                        ),
                        openInBrowser: markdownBrowserLauncher,
                        surfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.preview_rounded, size: 16),
                      label: const Text('Ouvrir le visualisateur'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('spec-review-open-md-browser'),
                      onPressed: () async {
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        final file = await writeStandaloneMarkdownHtmlFile(
                          markdown: markdown,
                          title: 'Cahier des charges — ${project.name}',
                          filenameStem: '${_safeName(project.name)}_cdc',
                          darkMode: isDark,
                        );
                        final launcher =
                            markdownBrowserLauncher ??
                            openHtmlFileInSystemBrowser;
                        await launcher(file);
                      },
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: const Text('Navigateur'),
                    ),
                  ],
                ),
                _ExportCodeTab(
                  content: yamlSchema,
                  filename: '${_safeName(project.name)}_schema.yaml',
                  colors: colors,
                ),
                _ExportCodeTab(
                  content: bundlePreview,
                  filename: '${_safeName(project.name)}_repositories.json',
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('spec-review-open-schema-viewer'),
                      onPressed: () => showSpecJsonSchemaViewerDialog(
                        context,
                        bundle: bundle,
                        title: 'JSON Schema & Seed — ${project.name}',
                        filenameStem: '${_safeName(project.name)}_repositories_schema',
                        exportDirectory: Directory(
                          '${controller.store.rootDirectory.path}${Platform.pathSeparator}exports${Platform.pathSeparator}${_safeName(project.id)}',
                        ),
                        openInBrowser: markdownBrowserLauncher,
                        htmlSurfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.schema_outlined, size: 16),
                      label: const Text('Ouvrir le visualisateur'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('spec-review-open-schema-browser'),
                      onPressed: () async {
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        final file = await writeStandaloneJsonSchemaHtmlFile(
                          bundle: bundle,
                          title: 'JSON Schema & Seed — ${project.name}',
                          filenameStem:
                              '${_safeName(project.name)}_repositories_schema',
                          darkMode: isDark,
                        );
                        final launcher =
                            markdownBrowserLauncher ??
                            openHtmlFileInSystemBrowser;
                        await launcher(file);
                      },
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: const Text('Navigateur'),
                    ),
                  ],
                ),
                _ExportCodeTab(
                  content: fullJson,
                  filename: '${_safeName(project.name)}_spec.json',
                  colors: colors,
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
    required String markdown,
    required String yamlSchema,
    required String fullJson,
  }) async {
    final defaultDir =
        '${controller.store.rootDirectory.path}${Platform.pathSeparator}exports${Platform.pathSeparator}${_safeName(project.id)}';
    final pathCtrl = TextEditingController(text: defaultDir);
    var includeSandboxedApp = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Exporter les livrables'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: pathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dossier de destination',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeSandboxedApp,
                  onChanged: (v) =>
                      setDialogState(() => includeSandboxedApp = v ?? true),
                  title: const Text(
                    'Créer aussi un dossier d’application super_designer',
                  ),
                  subtitle: const Text(
                    'Génère app.json + repositories/ avec JSON Schemas et données de seed prêts à ouvrir.',
                  ),
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
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Exporter'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && pathCtrl.text.trim().isNotEmpty) {
      final dir = Directory(pathCtrl.text.trim());
      await dir.create(recursive: true);
      final sep = Platform.pathSeparator;
      await File('$dir${sep}cahier_des_charges.md')
          .writeAsString(markdown, flush: true);
      final htmlAssets = await SpecMarkdownHtmlBuilder.loadAssets();
      final html = SpecMarkdownHtmlBuilder.buildHtml(
        markdown: markdown,
        title: 'Cahier des charges — ${project.name}',
        assets: htmlAssets,
      );
      await File('$dir${sep}cahier_des_charges.html')
          .writeAsString(html, flush: true);
      final schemaDocHtml = SpecJsonSchemaHtmlBuilder.buildHtml(
        bundle: SpecSuperDesignerExporter.toBundle(project),
        title: 'JSON Schema & Seed — ${project.name}',
        assets: htmlAssets,
      );
      await File('$dir${sep}repositories_schema_doc.html')
          .writeAsString(schemaDocHtml, flush: true);
      await File('$dir${sep}schema_light.yaml')
          .writeAsString(yamlSchema, flush: true);
      await File('$dir${sep}specification_complete.json')
          .writeAsString(fullJson, flush: true);

      if (includeSandboxedApp) {
        final appDir = Directory('${dir.path}${sep}super_designer_app');
        await SpecSuperDesignerExporter.exportToSandboxedApplication(
          project,
          appDir,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exports enregistrés dans ${dir.path}')),
        );
      }
    }
    pathCtrl.dispose();
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

class _CoherenceTab extends StatelessWidget {
  const _CoherenceTab({required this.issues, required this.onJumpToStage});

  final List<SpecCoherenceIssue> issues;
  final ValueChanged onJumpToStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 48, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              'Aucune anomalie détectée',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cadrage, cahier des charges, objets métiers et règles de gestion sont cohérents.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: issues.length,
      itemBuilder: (context, index) {
        final issue = issues[index];
        final (icon, tint) = switch (issue.severity) {
          CoherenceSeverity.error => (
            Icons.error_outline_rounded,
            colors.error,
          ),
          CoherenceSeverity.warning => (
            Icons.warning_amber_rounded,
            colors.tertiary,
          ),
          CoherenceSeverity.info => (
            Icons.info_outline_rounded,
            colors.primary,
          ),
        };
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: ListTile(
            leading: Icon(icon, color: tint),
            title: Text(
              '${issue.code} · ${issue.title}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.description),
                if (issue.suggestion.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Suggestion : ${issue.suggestion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: TextButton(
              onPressed: () => onJumpToStage(issue.stage),
              child: Text('Voir ${issue.stage.shortLabel}'),
            ),
          ),
        );
      },
    );
  }
}

class _ExportCodeTab extends StatelessWidget {
  const _ExportCodeTab({
    required this.content,
    required this.filename,
    required this.colors,
    this.extraActions = const <Widget>[],
  });

  final String content;
  final String filename;
  final ColorScheme colors;
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
