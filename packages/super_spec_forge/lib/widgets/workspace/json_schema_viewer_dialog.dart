/// Visualisateur hybride « JSON Schema & Seed » combinant :
/// 1. Un inspecteur natif Flutter (liste des repositories, arbre hiérarchique du schéma,
///    aperçu tabulaire & bac à sable Seed [CodeEditor] validé en direct par [JsonSchemaValidator],
///    et source JSON Schema colorisée) ;
/// 2. Une vue documentation interactive HTML5 hors-ligne (WebView2 / navigateur).
/// ([showSpecJsonSchemaViewerDialog])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:highlight/languages/json.dart' as json_lang;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as winwv;

import '../../services/exporters/spec_json_schema_html_builder.dart';
import '../../services/exporters/spec_markdown_html_builder.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';
import '../spec_split_handle.dart';
import 'markdown_viewer_dialog.dart';

/// Mode d'affichage actif dans le visualisateur JSON Schema & Seed.
enum SpecJsonSchemaViewerMode {
  /// Inspecteur natif Flutter + validateur JSON Schema en direct.
  nativeInspector,

  /// Documentation HTML5 interactive rendue dans WebView2.
  htmlDoc,
}

/// Génère et écrit un fichier `.html` autonome pour un [SuperDesignerExportBundle].
Future<File> writeStandaloneJsonSchemaHtmlFile({
  required SuperDesignerExportBundle bundle,
  required String title,
  String filenameStem = 'repositories_schema_doc',
  Directory? targetDirectory,
  bool darkMode = false,
}) async {
  final assets = await SpecMarkdownHtmlBuilder.loadAssets();
  final html = SpecJsonSchemaHtmlBuilder.buildHtml(
    bundle: bundle,
    title: title,
    assets: assets,
    darkMode: darkMode,
  );
  final sep = Platform.pathSeparator;
  final dir =
      targetDirectory ??
      Directory('${Directory.systemTemp.path}${sep}super_spec_forge_md');
  await dir.create(recursive: true);
  final safeStem = filenameStem
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final file = File(
    '${dir.path}$sep${safeStem.isEmpty ? 'repositories_schema' : safeStem}.html',
  );
  await file.writeAsString(html, flush: true);
  return file;
}

/// Ouvre la fenêtre modale de visualisation « JSON Schema & Seed ».
Future<void> showSpecJsonSchemaViewerDialog(
  BuildContext context, {
  required SuperDesignerExportBundle bundle,
  required String title,
  String filenameStem = 'repositories_schema_doc',
  Directory? exportDirectory,
  SpecMarkdownBrowserLauncher? openInBrowser,
  SpecMarkdownViewerSurfaceBuilder? htmlSurfaceBuilder,
  SpecJsonSchemaViewerMode initialMode =
      SpecJsonSchemaViewerMode.nativeInspector,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SpecJsonSchemaViewerDialog(
    bundle: bundle,
    title: title,
    filenameStem: filenameStem,
    exportDirectory: exportDirectory,
    openInBrowser: openInBrowser,
    htmlSurfaceBuilder: htmlSurfaceBuilder,
    initialMode: initialMode,
  ),
);

class _SpecJsonSchemaViewerDialog extends StatefulWidget {
  const _SpecJsonSchemaViewerDialog({
    required this.bundle,
    required this.title,
    required this.filenameStem,
    required this.initialMode,
    this.exportDirectory,
    this.openInBrowser,
    this.htmlSurfaceBuilder,
  });

  final SuperDesignerExportBundle bundle;
  final String title;
  final String filenameStem;
  final SpecJsonSchemaViewerMode initialMode;
  final Directory? exportDirectory;
  final SpecMarkdownBrowserLauncher? openInBrowser;
  final SpecMarkdownViewerSurfaceBuilder? htmlSurfaceBuilder;

  @override
  State<_SpecJsonSchemaViewerDialog> createState() =>
      _SpecJsonSchemaViewerDialogState();
}

class _SpecJsonSchemaViewerDialogState
    extends State<_SpecJsonSchemaViewerDialog> {
  late SpecJsonSchemaViewerMode _mode;
  late final List<String> _aliases;
  String? _selectedAlias;

  final GlobalKey _splitRowKey = GlobalKey();
  double _repoPaneFraction = 0.27;
  double _dragOffset = SpecSplitHandle.width / 2;

  String _schemaSearch = '';

  // État des éditeurs JSON Seed et Schéma
  final Map<String, String> _seedDraftsByAlias = {};
  final Map<String, JsonSchemaValidationResult?> _validationByAlias = {};
  final Map<String, String?> _syntaxErrorByAlias = {};

  final ValueNotifier<String> _seedErrorNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> _schemaErrorNotifier = ValueNotifier<String>('');
  late final CodeEditorConfig _seedEditorConfig;
  late final CodeEditorConfig _schemaEditorConfig;

  // État de la vue HTML (WebView2)
  bool _initializedTheme = false;
  bool _darkMode = false;
  bool _htmlLoading = false;
  String? _htmlError;
  File? _htmlFile;
  winwv.WebviewController? _winWebViewController;
  wf.WebViewController? _webViewController;
  Future<void> Function(String js)? _jsRunner;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _aliases = <String>{
      ...widget.bundle.repositoriesJsonSchemas.keys,
      ...widget.bundle.repositoriesSeedData.keys,
    }.toList()..sort();
    _selectedAlias = _aliases.isNotEmpty ? _aliases.first : null;

    for (final alias in _aliases) {
      final seed =
          widget.bundle.repositoriesSeedData[alias] ??
          const <String, Object?>{};
      final encoded = '${const JsonEncoder.withIndent('  ').convert(seed)}\n';
      _seedDraftsByAlias[alias] = encoded;
      _validateAliasSeed(alias, encoded, notify: false);
    }

    _seedEditorConfig = CodeEditorConfig(
      mode: json_lang.json,
      type: 'json',
      getText: () => _selectedAlias == null
          ? '{}'
          : (_seedDraftsByAlias[_selectedAlias!] ?? '{}'),
      onChange: (String value, CodeEditorConfig _) {
        final alias = _selectedAlias;
        if (alias == null) return;
        _seedDraftsByAlias[alias] = value;
        _validateAliasSeed(alias, value, notify: true);
      },
      notifError: _seedErrorNotifier,
      useLargeTextViewer: false,
    );

    _schemaEditorConfig = CodeEditorConfig(
      mode: json_lang.json,
      type: 'json',
      readOnly: true,
      getText: () {
        final alias = _selectedAlias;
        if (alias == null) return '{}';
        final schema =
            widget.bundle.repositoriesJsonSchemas[alias] ??
            const <String, Object?>{};
        return '${const JsonEncoder.withIndent('  ').convert(schema)}\n';
      },
      onChange: (_, _) {},
      notifError: _schemaErrorNotifier,
      useLargeTextViewer: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedTheme) {
      _initializedTheme = true;
      _darkMode = Theme.of(context).brightness == Brightness.dark;
      if (_mode == SpecJsonSchemaViewerMode.htmlDoc) {
        unawaited(_prepareHtmlViewer());
      }
    }
  }

  @override
  void dispose() {
    _seedErrorNotifier.dispose();
    _schemaErrorNotifier.dispose();
    final winCtrl = _winWebViewController;
    _winWebViewController = null;
    if (winCtrl != null) {
      unawaited(winCtrl.dispose());
      unawaited(winwv.WebviewController.releaseFocus());
    }
    super.dispose();
  }

  void _selectAlias(String alias) {
    if (_selectedAlias == alias) return;
    setState(() {
      _selectedAlias = alias;
    });
    _seedEditorConfig.repaintCode();
    _schemaEditorConfig.repaintCode();
  }

  void _validateAliasSeed(
    String alias,
    String rawJson, {
    required bool notify,
  }) {
    final schema = widget.bundle.repositoriesJsonSchemas[alias];
    JsonSchemaValidationResult? result;
    String? syntaxError;
    try {
      final decoded = jsonDecode(rawJson);
      if (schema != null) {
        result = JsonSchemaValidator.validate(decoded, schema);
      }
      _seedErrorNotifier.value = '';
    } on FormatException catch (e) {
      syntaxError = e.message;
      _seedErrorNotifier.value = e.message;
    }

    void apply() {
      _validationByAlias[alias] = result;
      _syntaxErrorByAlias[alias] = syntaxError;
    }

    if (notify && mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _resetSelectedSeed() {
    final alias = _selectedAlias;
    if (alias == null) return;
    final seed =
        widget.bundle.repositoriesSeedData[alias] ?? const <String, Object?>{};
    final encoded = '${const JsonEncoder.withIndent('  ').convert(seed)}\n';
    _seedDraftsByAlias[alias] = encoded;
    _validateAliasSeed(alias, encoded, notify: true);
    _seedEditorConfig.repaintCode();
  }

  Future<void> _prepareHtmlViewer() async {
    setState(() {
      _htmlLoading = true;
      _htmlError = null;
    });
    try {
      final file = await writeStandaloneJsonSchemaHtmlFile(
        bundle: widget.bundle,
        title: widget.title,
        filenameStem: widget.filenameStem,
        darkMode: _darkMode,
      );
      if (!mounted) return;

      if (widget.htmlSurfaceBuilder == null) {
        if (Platform.isWindows) {
          try {
            final prev = _winWebViewController;
            if (prev != null) {
              _winWebViewController = null;
              await prev.dispose();
            }
            final controller = winwv.WebviewController();
            await controller.initialize();
            await controller.setBackgroundColor(
              _darkMode ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
            );
            await controller.loadUrl(Uri.file(file.path).toString());
            if (!mounted) {
              await controller.dispose();
              return;
            }
            _winWebViewController = controller;
            _jsRunner = controller.executeScript;
          } catch (err) {
            _winWebViewController = null;
            _jsRunner = null;
            _htmlError =
                'WebView2 indisponible sur cet environnement ($err). '
                'Utilisez « Navigateur ».';
          }
        } else {
          try {
            final controller = wf.WebViewController()
              ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
              ..setBackgroundColor(
                _darkMode ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
              );
            await controller.loadFile(file.path);
            _webViewController = controller;
            _jsRunner = controller.runJavaScript;
          } catch (err) {
            _webViewController = null;
            _jsRunner = null;
            _htmlError =
                'WebView intégrée indisponible sur cet environnement ($err). '
                'Utilisez « Navigateur ».';
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _htmlFile = file;
        _htmlLoading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _htmlError = 'Impossible de générer la documentation HTML : $err';
        _htmlLoading = false;
      });
    }
  }

  Future<void> _switchMode(SpecJsonSchemaViewerMode next) async {
    if (_mode == next) return;
    setState(() => _mode = next);
    if (next == SpecJsonSchemaViewerMode.htmlDoc && _htmlFile == null) {
      await _prepareHtmlViewer();
    }
  }

  Future<void> _runJs(String js) async {
    final runner = _jsRunner;
    if (runner == null) return;
    try {
      await runner(js);
    } catch (_) {}
  }

  Future<void> _toggleTheme() async {
    setState(() => _darkMode = !_darkMode);
    if (_winWebViewController != null) {
      unawaited(
        _winWebViewController!.setBackgroundColor(
          _darkMode ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
        ),
      );
    }
    await _runJs(
      "window.ssfSchemaViewer && window.ssfSchemaViewer.setTheme('${_darkMode ? 'dark' : 'light'}');",
    );
  }

  Future<void> _openExternalBrowser() async {
    final file = await writeStandaloneJsonSchemaHtmlFile(
      bundle: widget.bundle,
      title: widget.title,
      filenameStem: widget.filenameStem,
      darkMode: _darkMode,
    );
    _htmlFile = file;
    final launcher = widget.openInBrowser ?? openHtmlFileInSystemBrowser;
    await launcher(file);
  }

  Future<void> _exportHtml() async {
    final sep = Platform.pathSeparator;
    final baseDir =
        widget.exportDirectory?.path ??
        '${Directory.systemTemp.path}${sep}super_spec_forge_exports';
    final pathCtrl = TextEditingController(
      text: '$baseDir$sep${widget.filenameStem}.html',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exporter la documentation HTML'),
        content: SizedBox(
          width: 480,
          child: TextField(
            key: const ValueKey('spec-schema-export-html-path'),
            controller: pathCtrl,
            decoration: const InputDecoration(
              labelText: 'Chemin du fichier .html',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('spec-schema-export-html-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final outPath = pathCtrl.text.trim();
    pathCtrl.dispose();
    if (confirmed != true || outPath.isEmpty) return;

    final assets = await SpecMarkdownHtmlBuilder.loadAssets();
    final html = SpecJsonSchemaHtmlBuilder.buildHtml(
      bundle: widget.bundle,
      title: widget.title,
      assets: assets,
      darkMode: _darkMode,
    );
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsString(html, flush: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('HTML exporté vers ${outFile.path}')),
      );
    }
  }

  Future<void> _printOrPdf() async {
    if (_mode == SpecJsonSchemaViewerMode.htmlDoc && _jsRunner != null) {
      await _runJs('window.print();');
      return;
    }
    await _openExternalBrowser();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final screen = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: (screen.width * 0.92).clamp(680.0, 1420.0),
        height: (screen.height * 0.92).clamp(500.0, 960.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(theme, colors),
            Expanded(
              child: _mode == SpecJsonSchemaViewerMode.nativeInspector
                  ? _buildNativeInspector(theme, colors)
                  : _buildHtmlBody(theme, colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.data_object_rounded, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<SpecJsonSchemaViewerMode>(
                key: const ValueKey('spec-schema-viewer-mode-switch'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: SpecJsonSchemaViewerMode.nativeInspector,
                    icon: Icon(Icons.account_tree_outlined, size: 16),
                    label: Text('Inspecteur natif'),
                  ),
                  ButtonSegment(
                    value: SpecJsonSchemaViewerMode.htmlDoc,
                    icon: Icon(Icons.web_outlined, size: 16),
                    label: Text('Doc HTML'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (sel) => _switchMode(sel.first),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_mode == SpecJsonSchemaViewerMode.htmlDoc)
                IconButton(
                  key: const ValueKey('spec-schema-viewer-toggle-theme'),
                  tooltip: _darkMode
                      ? 'Passer en thème clair'
                      : 'Passer en thème sombre',
                  onPressed: _toggleTheme,
                  icon: Icon(
                    _darkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                ),
              OutlinedButton.icon(
                key: const ValueKey('spec-schema-viewer-open-browser'),
                onPressed: _openExternalBrowser,
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: const Text('Navigateur'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('spec-schema-viewer-export-html'),
                onPressed: _exportHtml,
                icon: const Icon(Icons.html_rounded, size: 18),
                label: const Text('Exporter .html'),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('spec-schema-viewer-print'),
                onPressed: _printOrPdf,
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Imprimer / PDF'),
              ),
              IconButton(
                key: const ValueKey('spec-schema-viewer-close'),
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNativeInspector(ThemeData theme, ColorScheme colors) {
    if (_aliases.isEmpty) {
      return const Center(
        child: Text(
          'Aucun repository JSON Schema ou Seed généré.\nModélisez d’abord au moins un objet métier.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final activeAlias = _selectedAlias ?? _aliases.first;
    final activeSchema =
        widget.bundle.repositoriesJsonSchemas[activeAlias] ??
        const <String, Object?>{};
    final activeValidation = _validationByAlias[activeAlias];
    final activeSyntaxError = _syntaxErrorByAlias[activeAlias];

    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = SpecSplitHandle.width;
        const minRepoWidth = 210.0;
        const minDetailWidth = 360.0;
        final totalWidth = constraints.maxWidth;
        final availableWidth = (totalWidth - dividerWidth).clamp(
          0.0,
          double.infinity,
        );
        final repoWidth = availableWidth <= minRepoWidth + minDetailWidth
            ? availableWidth * _repoPaneFraction
            : (availableWidth * _repoPaneFraction).clamp(
                minRepoWidth,
                availableWidth - minDetailWidth,
              );

        return Row(
          key: _splitRowKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('spec-schema-repo-list-pane'),
              width: repoWidth,
              child: Container(
                color: colors.surfaceContainerLowest,
                child: ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                      child: Text(
                        'Repositories (${_aliases.length})',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final alias in _aliases)
                      _buildRepoTile(alias, activeAlias, theme, colors),
                  ],
                ),
              ),
            ),
            SpecSplitHandle(
              key: const ValueKey('spec-schema-split-handle'),
              onDoubleTap: () => setState(() => _repoPaneFraction = 0.27),
              onHorizontalDragDown: (details) {
                final box =
                    _splitRowKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (box != null) {
                  final localX = box.globalToLocal(details.globalPosition).dx;
                  _dragOffset = (localX - repoWidth).clamp(
                    0.0,
                    SpecSplitHandle.width,
                  );
                } else {
                  _dragOffset = SpecSplitHandle.width / 2;
                }
              },
              onHorizontalDragUpdate: (details) {
                final box =
                    _splitRowKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (box == null || availableWidth <= 0) return;
                final localX = box.globalToLocal(details.globalPosition).dx;
                final nextWidth = localX - _dragOffset;
                final minFrac = availableWidth > minRepoWidth + minDetailWidth
                    ? (minRepoWidth / availableWidth)
                    : 0.18;
                final maxFrac = availableWidth > minRepoWidth + minDetailWidth
                    ? ((availableWidth - minDetailWidth) / availableWidth)
                    : 0.55;
                setState(() {
                  _repoPaneFraction = (nextWidth / availableWidth).clamp(
                    minFrac,
                    maxFrac,
                  );
                });
              },
            ),
            Expanded(
              key: const ValueKey('spec-schema-detail-pane'),
              child: DefaultTabController(
                length: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Arbre du Schéma'),
                        Tab(text: 'Seed & Validateur live'),
                        Tab(text: 'Source JSON Schema'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildSchemaTreeTab(
                            activeAlias,
                            activeSchema,
                            theme,
                            colors,
                          ),
                          _buildSeedValidatorTab(
                            activeAlias,
                            activeValidation,
                            activeSyntaxError,
                            theme,
                            colors,
                          ),
                          _buildRawSchemaTab(
                            activeAlias,
                            activeSchema,
                            theme,
                            colors,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRepoTile(
    String alias,
    String activeAlias,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final isSelected = alias == activeAlias;
    final schema = widget.bundle.repositoriesJsonSchemas[alias];
    final title = (schema?['title'] as String?)?.trim().isNotEmpty == true
        ? schema!['title'] as String
        : alias;
    final syntaxError = _syntaxErrorByAlias[alias];
    final validation = _validationByAlias[alias];
    final isValid = syntaxError == null && (validation?.isValid ?? true);
    final issueCount = validation?.issues.length ?? 0;

    return Card(
      key: ValueKey('spec-schema-repo-tile-$alias'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: isSelected
          ? colors.primaryContainer.withValues(alpha: 0.6)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectAlias(alias),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isValid
                      ? colors.secondaryContainer
                      : colors.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isValid
                      ? 'Valide'
                      : (syntaxError != null ? 'JSON' : '$issueCount err.'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isValid
                        ? colors.onSecondaryContainer
                        : colors.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchemaTreeTab(
    String alias,
    Map<String, Object?> schema,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final description = (schema['description'] as String?) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('spec-schema-tree-search'),
                  onChanged: (v) =>
                      setState(() => _schemaSearch = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText:
                        'Filtrer une propriété, un format ou une contrainte…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (schema[r'$schema'] != null) ...[
                const SizedBox(width: 10),
                Chip(
                  label: const Text('Draft 2020-12'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              _SchemaTreeNodeCard(
                name: alias,
                schema: schema,
                isRequired: true,
                depth: 0,
                searchQuery: _schemaSearch,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeedValidatorTab(
    String alias,
    JsonSchemaValidationResult? validation,
    String? syntaxError,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    _seedEditorConfig.style = SuperCodeStyle(
      theme: isDark ? SuperCodeTheme.atomOneDark : SuperCodeTheme.atomOneLight,
      fontSize: 13,
      lineHeight: 1.45,
      showLineNumbers: true,
      showFoldingHandles: true,
    );

    final rawSeedText = _seedDraftsByAlias[alias] ?? '{}';
    Object? decodedSeed;
    try {
      decodedSeed = jsonDecode(rawSeedText);
    } catch (_) {}

    final isValid = syntaxError == null && (validation?.isValid ?? true);
    final issues = validation?.issues ?? const <JsonSchemaValidationIssue>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final minEditorHeight = (constraints.maxHeight - 240).clamp(
          180.0,
          560.0,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('spec-schema-live-validation-banner'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isValid
                      ? colors.secondaryContainer.withValues(alpha: 0.55)
                      : colors.errorContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isValid
                        ? colors.secondary.withValues(alpha: 0.45)
                        : colors.error.withValues(alpha: 0.55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isValid
                                  ? Icons.verified_rounded
                                  : Icons.error_outline_rounded,
                              size: 18,
                              color: isValid ? colors.secondary : colors.error,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                isValid
                                    ? 'Document Seed conforme au JSON Schema (JsonSchemaValidator)'
                                    : (syntaxError != null
                                          ? 'JSON invalide : $syntaxError'
                                          : '${issues.length} erreur(s) de validation JSON Schema'),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isValid
                                      ? colors.onSecondaryContainer
                                      : colors.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            OutlinedButton.icon(
                              key: const ValueKey('spec-schema-reset-seed'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: _resetSelectedSeed,
                              icon: const Icon(Icons.refresh_rounded, size: 15),
                              label: const Text('Réinitialiser Seed'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: rawSeedText),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: const Text('Copier'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (issues.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 72),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final issue in issues.take(6))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '• ${issue.instancePath} (${issue.keyword}) : ${issue.message}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onErrorContainer,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (decodedSeed is Map) ...[
                const SizedBox(height: 8),
                _SeedQuickTablePreview(seedDocument: decodedSeed),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: minEditorHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CodeEditor(
                      key: ValueKey('spec-schema-seed-editor-$alias'),
                      config: _seedEditorConfig,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRawSchemaTab(
    String alias,
    Map<String, Object?> schema,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    _schemaEditorConfig.style = SuperCodeStyle(
      theme: isDark ? SuperCodeTheme.atomOneDark : SuperCodeTheme.atomOneLight,
      fontSize: 13,
      lineHeight: 1.45,
      showLineNumbers: true,
      showFoldingHandles: true,
    );
    final pretty = '${const JsonEncoder.withIndent('  ').convert(schema)}\n';

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$alias.schema.json (Draft 2020-12)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: pretty));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'JSON Schema copié dans le presse-papiers',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Copier Schéma'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CodeEditor(
                  key: ValueKey('spec-schema-raw-editor-$alias'),
                  config: _schemaEditorConfig,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHtmlBody(ThemeData theme, ColorScheme colors) {
    if (_htmlLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_htmlError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 0,
              color: colors.errorContainer.withValues(alpha: 0.45),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.web_asset_off_rounded,
                      color: colors.error,
                      size: 36,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _htmlError!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _openExternalBrowser,
                          icon: const Icon(
                            Icons.open_in_browser_rounded,
                            size: 16,
                          ),
                          label: const Text('Ouvrir dans le navigateur'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _prepareHtmlViewer,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Réessayer'),
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

    final file = _htmlFile;
    if (file == null) return const SizedBox.shrink();

    if (widget.htmlSurfaceBuilder != null) {
      return widget.htmlSurfaceBuilder!(context, file, (runner) {
        _jsRunner = runner;
      });
    }

    final winCtrl = _winWebViewController;
    if (winCtrl != null) {
      return winwv.Webview(winCtrl);
    }

    final ctrl = _webViewController;
    if (ctrl == null) return const SizedBox.shrink();
    return wf.WebViewWidget(controller: ctrl);
  }
}

class _SchemaTreeNodeCard extends StatefulWidget {
  const _SchemaTreeNodeCard({
    required this.name,
    required this.schema,
    required this.isRequired,
    required this.depth,
    required this.searchQuery,
  });

  final String name;
  final Map<String, Object?> schema;
  final bool isRequired;
  final int depth;
  final String searchQuery;

  @override
  State<_SchemaTreeNodeCard> createState() => _SchemaTreeNodeCardState();
}

class _SchemaTreeNodeCardState extends State<_SchemaTreeNodeCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.searchQuery.isNotEmpty &&
        !_matches(widget.name, widget.schema, widget.searchQuery)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final schema = widget.schema;
    final typeText = _formatType(schema);
    final description = (schema['description'] as String?) ?? '';
    final badges = _collectConstraintBadges(schema);
    final childrenWidgets = _buildChildren(schema);
    final hasChildren = childrenWidgets.isNotEmpty || description.isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: widget.depth.isEven
          ? colors.surfaceContainerLow
          : colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: hasChildren
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (hasChildren)
                    Icon(
                      _expanded
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  Text(
                    widget.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _SchemaBadge(
                    label: typeText,
                    bg: colors.primaryContainer,
                    fg: colors.onPrimaryContainer,
                  ),
                  if (widget.isRequired)
                    _SchemaBadge(
                      label: 'required',
                      bg: colors.errorContainer,
                      fg: colors.onErrorContainer,
                    ),
                  for (final badge in badges)
                    _SchemaBadge(
                      label: badge,
                      bg: colors.surfaceContainerHighest,
                      fg: colors.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          if (hasChildren && _expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ...childrenWidgets,
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildChildren(Map<String, Object?> schema) {
    final result = <Widget>[];
    final reqList = schema['required'] is List
        ? {for (final r in schema['required'] as List) '$r'}
        : const <String>{};

    final props = schema['properties'];
    if (props is Map) {
      for (final entry in props.entries) {
        if (entry.value is Map) {
          result.add(
            _SchemaTreeNodeCard(
              name: '${entry.key}',
              schema: Map<String, Object?>.from(entry.value as Map),
              isRequired: reqList.contains('${entry.key}'),
              depth: widget.depth + 1,
              searchQuery: widget.searchQuery,
            ),
          );
        }
      }
    }

    final items = schema['items'];
    if (items is Map) {
      result.add(
        _SchemaTreeNodeCard(
          name: '[items]',
          schema: Map<String, Object?>.from(items),
          isRequired: false,
          depth: widget.depth + 1,
          searchQuery: widget.searchQuery,
        ),
      );
    }

    final addProps = schema['additionalProperties'];
    if (addProps is Map) {
      result.add(
        _SchemaTreeNodeCard(
          name: '[additionalProperties]',
          schema: Map<String, Object?>.from(addProps),
          isRequired: false,
          depth: widget.depth + 1,
          searchQuery: widget.searchQuery,
        ),
      );
    }

    for (final combiner in const ['allOf', 'anyOf', 'oneOf', 'prefixItems']) {
      final branches = schema[combiner];
      if (branches is List) {
        for (var i = 0; i < branches.length; i++) {
          final b = branches[i];
          if (b is Map) {
            result.add(
              _SchemaTreeNodeCard(
                name: '$combiner[$i]',
                schema: Map<String, Object?>.from(b),
                isRequired: false,
                depth: widget.depth + 1,
                searchQuery: widget.searchQuery,
              ),
            );
          }
        }
      }
    }

    for (final kw in const ['not', 'if', 'then', 'else', 'contains']) {
      final sub = schema[kw];
      if (sub is Map) {
        result.add(
          _SchemaTreeNodeCard(
            name: kw,
            schema: Map<String, Object?>.from(sub),
            isRequired: false,
            depth: widget.depth + 1,
            searchQuery: widget.searchQuery,
          ),
        );
      }
    }

    return result;
  }

  static bool _matches(String name, Map<String, Object?> schema, String query) {
    final hay = '$name ${jsonEncode(schema)}'.toLowerCase();
    return hay.contains(query);
  }

  static String _formatType(Map<String, Object?> schema) {
    final rawType = schema['type'];
    if (rawType is List) {
      return rawType.join(' | ');
    }
    if (rawType is String && rawType.isNotEmpty) {
      return rawType;
    }
    if (schema['properties'] is Map) return 'object';
    return 'any';
  }

  static List<String> _collectConstraintBadges(Map<String, Object?> schema) {
    const keys = [
      'format',
      'minimum',
      'maximum',
      'exclusiveMinimum',
      'exclusiveMaximum',
      'multipleOf',
      'minLength',
      'maxLength',
      'pattern',
      'minItems',
      'maxItems',
      'uniqueItems',
      'minContains',
      'maxContains',
      'minProperties',
      'maxProperties',
      'additionalProperties',
      'readOnly',
      'writeOnly',
      'deprecated',
      'contentMediaType',
      'contentEncoding',
      r'$comment',
    ];
    final badges = <String>[];
    if (schema.containsKey('const')) {
      badges.add('const=${jsonEncode(schema['const'])}');
    }
    if (schema['enum'] is List) {
      badges.add('enum(${(schema['enum'] as List).join(', ')})');
    }
    for (final k in keys) {
      if (schema.containsKey(k)) {
        badges.add('$k: ${jsonEncode(schema[k])}');
      }
    }
    if (schema['examples'] is List) {
      badges.add('examples(${(schema['examples'] as List).length})');
    }
    return badges;
  }
}

class _SchemaBadge extends StatelessWidget {
  const _SchemaBadge({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: fg,
        ),
      ),
    );
  }
}

class _SeedQuickTablePreview extends StatelessWidget {
  const _SeedQuickTablePreview({required this.seedDocument});

  final Map<dynamic, dynamic> seedDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    String? collectionKey;
    List<Map<dynamic, dynamic>> rows = const [];
    for (final entry in seedDocument.entries) {
      if (entry.value is List) {
        final maps = (entry.value as List).whereType<Map>().toList();
        if (maps.isNotEmpty) {
          collectionKey = '${entry.key}';
          rows = maps;
          break;
        }
      }
    }

    if (collectionKey == null || rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final columns = <String>{
      for (final row in rows)
        for (final k in row.keys) '$k',
    }.take(8).toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 110),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: 34,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 40,
            columns: [
              for (final col in columns)
                DataColumn(
                  label: Text(
                    col,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
            rows: [
              for (final row in rows.take(10))
                DataRow(
                  cells: [
                    for (final col in columns)
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            _formatCell(row[col]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatCell(Object? value) {
    if (value == null) return 'null';
    if (value is Map || value is List) return jsonEncode(value);
    return '$value';
  }
}
