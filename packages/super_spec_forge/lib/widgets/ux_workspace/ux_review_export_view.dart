/// Atelier de l'étape UX 4 : Audit de cohérence Métier↔UX, traçabilité et export vers SuperDesigner ([UxReviewExportView]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../../models/ux/ux_coherence_issue.dart';
import '../../models/ux/ux_forge_stage.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';
import '../../services/exporters/ux_design_md_exporter.dart';
import '../../services/exporters/ux_markdown_exporter.dart';
import '../../services/spec_forge_controller.dart';
import '../../services/ux_coherence_analyzer.dart';
import '../workspace/json_schema_viewer_dialog.dart';
import '../workspace/markdown_viewer_dialog.dart';

/// Vue d'audit de cohérence Métier↔UX, de prévisualisation des livrables UX et d'export SuperDesigner.
class UxReviewExportView extends StatelessWidget {
  /// Crée la vue connectée au [controller].
  const UxReviewExportView({
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

    final localIssues = UxCoherenceAnalyzer.analyze(
      project,
      companyGlossary: controller.companyGlossary,
    );
    final localIds = <String>{for (final issue in localIssues) issue.id};
    final aiIssues = project.uxSpec.coherenceIssues
        .where((i) => i.source == 'ai' && !localIds.contains(i.id))
        .toList();
    final allIssues = <UxCoherenceIssue>[...localIssues, ...aiIssues];

    final bundle = SpecSuperDesignerExporter.toBundle(
      project,
      modelPreferencesOverride: controller.modelPreferences,
    );
    final uxMarkdown = UxMarkdownExporter.export(project);
    final designMd =
        bundle.designMarkdown ?? UxDesignMdExporter.export(project);
    final sdPrompt =
        bundle.superDesignerChatPrompt ??
        SpecSuperDesignerExporter.toSuperDesignerChatPrompt(project);
    final bundlePreview = const JsonEncoder.withIndent('  ').convert({
      'repositoriesJsonSchemas': bundle.repositoriesJsonSchemas,
      'repositoriesSeedData': bundle.repositoriesSeedData,
    });
    final uxJson = const JsonEncoder.withIndent('  ')
        .convert(project.uxSpec.toJson());
    final initialAppearance =
        bundle.initialAppearance ??
        SpecSuperDesignerExporter.buildInitialAppearance(project);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sep = Platform.pathSeparator;
    final exportDirPath =
        '${controller.store.rootDirectory.path}${sep}exports$sep${_safeName(project.id)}';

    return DefaultTabController(
      key: const ValueKey('ux-review-export-view'),
      length: 6,
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
                  'Audit UX, Traçabilité & Export SuperDesigner',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('ux-export-all-btn'),
                  onPressed: () => _exportAllDialog(
                    context,
                    project: project,
                    defaultExportDir: exportDirPath,
                  ),
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: const Text('Exporter UX & SuperDesigner'),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Cohérence UX (${allIssues.length})'),
              const Tab(text: 'Prompt SuperDesigner'),
              Tab(
                text:
                    'JSON Schema & Repositories (${bundle.repositoriesSeedData.length})',
              ),
              const Tab(text: 'Spécification UX (.md)'),
              const Tab(text: 'Charte DESIGN.md'),
              const Tab(text: 'Aperçu SuperDesigner'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _UxCoherenceTab(
                  issues: allIssues,
                  onJumpToStage: (stage) => controller.goToUxStage(stage),
                ),
                _UxExportCodeTab(
                  content: sdPrompt,
                  filename: 'prompt_super_designer.md',
                  copyButtonKey: const ValueKey('ux-review-copy-sd-prompt'),
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('ux-review-open-sd-prompt-viewer'),
                      onPressed: () => showSpecMarkdownViewerDialog(
                        context,
                        markdown: sdPrompt,
                        title: 'Prompt Chat SuperDesigner — ${project.name}',
                        filenameStem:
                            '${_safeName(project.name)}_prompt_super_designer',
                        exportDirectory: Directory(exportDirPath),
                        openInBrowser: markdownBrowserLauncher,
                        surfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.preview_rounded, size: 16),
                      label: const Text('Ouvrir le visualisateur'),
                    ),
                  ],
                ),
                _UxExportCodeTab(
                  content: bundlePreview,
                  filename: 'json_schemas/*.schema.json + repositories/*.json',
                  copyButtonKey: const ValueKey('ux-review-copy-repos-bundle'),
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('ux-review-open-repos-schema-viewer'),
                      onPressed: () => showSpecJsonSchemaViewerDialog(
                        context,
                        bundle: bundle,
                        title: 'JSON Schema & Repositories — ${project.name}',
                        filenameStem:
                            '${_safeName(project.name)}_repositories_schema',
                        exportDirectory: Directory(exportDirPath),
                        openInBrowser: markdownBrowserLauncher,
                        htmlSurfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.schema_outlined, size: 16),
                      label: const Text('Ouvrir le visualisateur'),
                    ),
                  ],
                ),
                _UxExportCodeTab(
                  content: uxMarkdown,
                  filename: 'specification_ux.md',
                  copyButtonKey: const ValueKey('ux-review-copy-ux-md'),
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('ux-review-open-ux-md-viewer'),
                      onPressed: () => showSpecMarkdownViewerDialog(
                        context,
                        markdown: uxMarkdown,
                        title: 'Spécification UX — ${project.name}',
                        filenameStem:
                            '${_safeName(project.name)}_specification_ux',
                        exportDirectory: Directory(exportDirPath),
                        openInBrowser: markdownBrowserLauncher,
                        surfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.preview_rounded, size: 16),
                      label: const Text('Ouvrir le visualisateur'),
                    ),
                  ],
                ),
                _UxExportCodeTab(
                  content: designMd,
                  filename: 'DESIGN.md',
                  copyButtonKey: const ValueKey('ux-review-copy-design-md'),
                  colors: colors,
                  extraActions: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('ux-review-open-design-md-viewer'),
                      onPressed: () => showSpecMarkdownViewerDialog(
                        context,
                        markdown: designMd,
                        title: 'DESIGN.md — ${project.name}',
                        filenameStem: '${_safeName(project.name)}_design',
                        exportDirectory: Directory(exportDirPath),
                        openInBrowser: markdownBrowserLauncher,
                        surfaceBuilder: markdownViewerSurfaceBuilder,
                      ),
                      icon: const Icon(Icons.preview_rounded, size: 16),
                      label: const Text('Ouvrir le visualisateur'),
                    ),
                  ],
                ),
                _SuperDesignerPreviewTab(
                  project: project,
                  appearance: initialAppearance,
                  uxJson: uxJson,
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
    final result = await showDialog<({String path, bool includeSandboxedApp})>(
      context: context,
      builder: (_) => _UxExportOptionsDialog(defaultDir: defaultExportDir),
    );

    if (result == null || result.path.trim().isEmpty) return;

    final dir = Directory(result.path.trim());
    await SpecSuperDesignerExporter.exportUxAndSuperDesignerDirectory(
      project,
      dir,
      includeSandboxedApp: result.includeSandboxedApp,
      modelPreferencesOverride: controller.modelPreferences,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exports UX enregistrés dans ${dir.path}')),
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

class _UxExportOptionsDialog extends StatefulWidget {
  const _UxExportOptionsDialog({required this.defaultDir});

  final String defaultDir;

  @override
  State<_UxExportOptionsDialog> createState() => _UxExportOptionsDialogState();
}

class _UxExportOptionsDialogState extends State<_UxExportOptionsDialog> {
  late final TextEditingController _pathCtrl = TextEditingController(
    text: widget.defaultDir,
  );
  bool _includeSandboxedApp = true;

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exporter les livrables UX & SuperDesigner'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('ux-export-dir-field'),
              controller: _pathCtrl,
              decoration: const InputDecoration(
                labelText: 'Dossier de destination',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Fichiers générés : prompt_super_designer.md, json_schemas/*.schema.json, repositories/*.json, repositories_bundle.json, schema_light.yaml, DESIGN.md, specification_ux.md et specification_ux.json.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('ux-export-sandbox-checkbox'),
              contentPadding: EdgeInsets.zero,
              value: _includeSandboxedApp,
              onChanged: (v) =>
                  setState(() => _includeSandboxedApp = v ?? true),
              title: const Text(
                'Générer / mettre à jour l’application sandboxée super_designer (pages + DESIGN.md + repositories)',
              ),
              subtitle: const Text(
                'Crée ou synchronise super_designer_app/ avec le catalogue de pages, la charte DESIGN.md et les repositories JSON.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('ux-export-cancel-btn'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ux-export-confirm-btn'),
          onPressed: () => Navigator.pop(context, (
            path: _pathCtrl.text,
            includeSandboxedApp: _includeSandboxedApp,
          )),
          child: const Text('Exporter'),
        ),
      ],
    );
  }
}

class _UxCoherenceTab extends StatelessWidget {
  const _UxCoherenceTab({required this.issues, required this.onJumpToStage});

  final List<UxCoherenceIssue> issues;
  final ValueChanged<UxForgeStage> onJumpToStage;

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
              'Aucune anomalie UX détectée',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Parcours, navigation, écrans et traçabilité Métier↔UX sont cohérents.',
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
          key: ValueKey('ux-coherence-issue-${issue.id}'),
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
              key: ValueKey('ux-coherence-jump-${issue.id}'),
              onPressed: () => onJumpToStage(issue.stage),
              child: Text('Voir ${issue.stage.shortLabel}'),
            ),
          ),
        );
      },
    );
  }
}

class _UxExportCodeTab extends StatelessWidget {
  const _UxExportCodeTab({
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

class _SuperDesignerPreviewTab extends StatefulWidget {
  const _SuperDesignerPreviewTab({
    required this.project,
    required this.appearance,
    required this.uxJson,
  });

  final SpecForgeProject project;
  final Appearance appearance;
  final String uxJson;

  @override
  State<_SuperDesignerPreviewTab> createState() =>
      _SuperDesignerPreviewTabState();
}

class _SuperDesignerPreviewTabState extends State<_SuperDesignerPreviewTab> {
  bool _jsonExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final catalog = widget.appearance.pageCatalog;
    final pages = catalog.pages;
    final partition = EditorPageGraph.partitionForPages(
      appearance: widget.appearance,
      loadedPageIds: <String>{for (final page in pages) page.id},
    );
    final routePaths = <String>[for (final page in pages) page.path];
    final declaredRouteCount = widget.project.uxSpec.navigation.routes.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: const ValueKey('ux-super-designer-summary-card'),
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
                Text(
                  'Synthèse de l’apparence initiale SuperDesigner',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _SummaryMetricBadge(
                      icon: Icons.layers_outlined,
                      label: 'Pages du catalogue',
                      value: '${pages.length}',
                      colors: colors,
                    ),
                    _SummaryMetricBadge(
                      icon: Icons.alt_route_rounded,
                      label: 'Routes UX',
                      value: '$declaredRouteCount',
                      colors: colors,
                    ),
                    _SummaryMetricBadge(
                      icon: Icons.widgets_outlined,
                      label: 'Composants',
                      value: '${widget.appearance.components.length}',
                      colors: colors,
                    ),
                    _SummaryMetricBadge(
                      icon: Icons.palette_outlined,
                      label: 'Styles',
                      value: '${widget.appearance.styles.length}',
                      colors: colors,
                    ),
                  ],
                ),
                if (routePaths.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Routes générées : ${routePaths.join(' · ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Catalogue de pages (${pages.length})',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (pages.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Aucune page générée dans EditorPageCatalog pour l’instant. Définissez des routes (étape 2) ou des écrans (étape 3) pour pré-générer les squelettes SuperDesigner.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final page in pages)
            _SuperDesignerPageCard(
              page: page,
              isHome: catalog.homePageId == page.id,
              slice: partition.pages[page.id],
              hasRootComponent: widget.appearance.components.containsKey(
                page.id,
              ),
            ),
        const SizedBox(height: 16),
        Card(
          key: const ValueKey('ux-super-designer-json-card'),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                color: colors.surfaceContainerLow,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InkWell(
                      key: const ValueKey('ux-toggle-ux-json-btn'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          setState(() => _jsonExpanded = !_jsonExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _jsonExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'specification_ux.json',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('ux-review-copy-ux-json'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: widget.uxJson),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copié dans le presse-papiers'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text('Copier'),
                    ),
                  ],
                ),
              ),
              if (_jsonExpanded)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        widget.uxJson,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryMetricBadge extends StatelessWidget {
  const _SummaryMetricBadge({
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

class _SuperDesignerPageCard extends StatelessWidget {
  const _SuperDesignerPageCard({
    required this.page,
    required this.isHome,
    required this.slice,
    required this.hasRootComponent,
  });

  final EditorPageConfig page;
  final bool isHome;
  final EditorPageAppearanceSlice? slice;
  final bool hasRootComponent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final componentCount =
        slice?.components.length ?? (hasRootComponent ? 1 : 0);
    final styleCount = slice?.styles.length ?? 0;

    return Card(
      key: ValueKey('ux-super-designer-page-card-${page.id}'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colors.primaryContainer,
              child: Icon(
                page.pageType.icon,
                size: 18,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
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
                        page.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isHome)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Accueil',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        page.path,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '• ${page.pageType.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '• $componentCount composants'
                        '${styleCount > 0 ? ' ($styleCount styles)' : ''}',
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
