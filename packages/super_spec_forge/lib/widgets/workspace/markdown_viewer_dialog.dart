/// Visualisateur Markdown avancé intégré (`webview_flutter` / WebView2) avec support
/// Mermaid, Sommaire (TOC), Highlight.js, KaTeX, ouverture navigateur et export HTML/PDF
/// ([showSpecMarkdownViewerDialog]).
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as winwv;

import '../../services/exporters/spec_markdown_html_builder.dart';

/// Signature permettant d'ouvrir le fichier HTML généré dans un navigateur externe.
typedef SpecMarkdownBrowserLauncher = Future<void> Function(File htmlFile);

/// Signature optionnelle permettant d'injecter la surface de rendu WebView (utile en test).
typedef SpecMarkdownViewerSurfaceBuilder = Widget Function(
  BuildContext context,
  File htmlFile,
  void Function(Future<void> Function(String js) runner) registerJsRunner,
);

/// Ouvre [htmlFile] dans le navigateur système par défaut.
Future<void> openHtmlFileInSystemBrowser(File htmlFile) async {
  if (Platform.isWindows) {
    await Process.start('cmd', [
      '/c',
      'start',
      '',
      htmlFile.path,
    ], runInShell: false);
    return;
  }
  if (Platform.isMacOS) {
    await Process.start('open', [htmlFile.path]);
    return;
  }
  await Process.start('xdg-open', [htmlFile.path]);
}

/// Génère et écrit un fichier `.html` autonome (100 % hors-ligne) pour [markdown].
Future<File> writeStandaloneMarkdownHtmlFile({
  required String markdown,
  required String title,
  String filenameStem = 'cahier_des_charges',
  Directory? targetDirectory,
  bool darkMode = false,
  bool showToc = true,
}) async {
  final assets = await SpecMarkdownHtmlBuilder.loadAssets();
  final html = SpecMarkdownHtmlBuilder.buildHtml(
    markdown: markdown,
    title: title,
    assets: assets,
    darkMode: darkMode,
    showToc: showToc,
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
    '${dir.path}$sep${safeStem.isEmpty ? 'document' : safeStem}.html',
  );
  await file.writeAsString(html, flush: true);
  return file;
}

/// Ouvre la fenêtre modale de visualisation Markdown avancée (Mermaid, TOC, KaTeX, Highlight.js).
Future<void> showSpecMarkdownViewerDialog(
  BuildContext context, {
  required String markdown,
  required String title,
  String filenameStem = 'cahier_des_charges',
  Directory? exportDirectory,
  SpecMarkdownBrowserLauncher? openInBrowser,
  SpecMarkdownViewerSurfaceBuilder? surfaceBuilder,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SpecMarkdownViewerDialog(
    markdown: markdown,
    title: title,
    filenameStem: filenameStem,
    exportDirectory: exportDirectory,
    openInBrowser: openInBrowser,
    surfaceBuilder: surfaceBuilder,
  ),
);

class _SpecMarkdownViewerDialog extends StatefulWidget {
  const _SpecMarkdownViewerDialog({
    required this.markdown,
    required this.title,
    required this.filenameStem,
    this.exportDirectory,
    this.openInBrowser,
    this.surfaceBuilder,
  });

  final String markdown;
  final String title;
  final String filenameStem;
  final Directory? exportDirectory;
  final SpecMarkdownBrowserLauncher? openInBrowser;
  final SpecMarkdownViewerSurfaceBuilder? surfaceBuilder;

  @override
  State<_SpecMarkdownViewerDialog> createState() =>
      _SpecMarkdownViewerDialogState();
}

class _SpecMarkdownViewerDialogState extends State<_SpecMarkdownViewerDialog> {
  bool _initializedTheme = false;
  bool _darkMode = false;
  bool _showToc = true;
  bool _loading = true;
  String? _error;
  File? _htmlFile;
  winwv.WebviewController? _winWebViewController;
  wf.WebViewController? _webViewController;
  Future<void> Function(String js)? _jsRunner;

  @override
  void dispose() {
    final winCtrl = _winWebViewController;
    _winWebViewController = null;
    if (winCtrl != null) {
      unawaited(winCtrl.dispose());
      unawaited(winwv.WebviewController.releaseFocus());
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedTheme) {
      _initializedTheme = true;
      _darkMode = Theme.of(context).brightness == Brightness.dark;
      unawaited(_prepareViewer());
    }
  }

  Future<void> _prepareViewer() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await writeStandaloneMarkdownHtmlFile(
        markdown: widget.markdown,
        title: widget.title,
        filenameStem: widget.filenameStem,
        darkMode: _darkMode,
        showToc: _showToc,
      );
      if (!mounted) return;

      if (widget.surfaceBuilder == null) {
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
            _jsRunner = (js) => controller.executeScript(js);
          } catch (err) {
            _winWebViewController = null;
            _jsRunner = null;
            _error =
                'WebView2 indisponible sur cet environnement ($err). '
                'Utilisez « Ouvrir dans le navigateur ».';
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
            _error =
                'WebView intégrée indisponible sur cet environnement ($err). '
                'Utilisez « Ouvrir dans le navigateur ».';
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _htmlFile = file;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de générer l’aperçu HTML : $err';
        _loading = false;
      });
    }
  }

  void _registerJsRunner(Future<void> Function(String js) runner) {
    _jsRunner = runner;
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
      "window.ssfViewer && window.ssfViewer.setTheme('${_darkMode ? 'dark' : 'light'}');",
    );
  }

  Future<void> _toggleToc() async {
    setState(() => _showToc = !_showToc);
    await _runJs(
      'window.ssfViewer && window.ssfViewer.setTocVisible($_showToc);',
    );
  }

  Future<void> _openExternalBrowser() async {
    final file = await writeStandaloneMarkdownHtmlFile(
      markdown: widget.markdown,
      title: widget.title,
      filenameStem: widget.filenameStem,
      darkMode: _darkMode,
      showToc: _showToc,
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
        title: const Text('Exporter le document HTML autonome'),
        content: SizedBox(
          width: 480,
          child: TextField(
            key: const ValueKey('spec-md-export-html-path'),
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
            key: const ValueKey('spec-md-export-html-confirm'),
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
    final html = SpecMarkdownHtmlBuilder.buildHtml(
      markdown: widget.markdown,
      title: widget.title,
      assets: assets,
      darkMode: _darkMode,
      showToc: _showToc,
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
    if (_jsRunner != null) {
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
        width: (screen.width * 0.92).clamp(640.0, 1400.0),
        height: (screen.height * 0.92).clamp(480.0, 960.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 20,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Mermaid · TOC · Code · KaTeX',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
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
                      FilterChip(
                        key: const ValueKey('spec-md-viewer-toggle-toc'),
                        selected: _showToc,
                        onSelected: (_) => _toggleToc(),
                        avatar: const Icon(Icons.toc_rounded, size: 16),
                        label: const Text('Sommaire'),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        key: const ValueKey('spec-md-viewer-toggle-theme'),
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
                        key: const ValueKey('spec-md-viewer-open-browser'),
                        onPressed: _openExternalBrowser,
                        icon: const Icon(
                          Icons.open_in_browser_rounded,
                          size: 16,
                        ),
                        label: const Text('Navigateur'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('spec-md-viewer-export-html'),
                        onPressed: _exportHtml,
                        icon: const Icon(Icons.html_rounded, size: 18),
                        label: const Text('Exporter .html'),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('spec-md-viewer-print'),
                        onPressed: _printOrPdf,
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text('Imprimer / PDF'),
                      ),
                      IconButton(
                        key: const ValueKey('spec-md-viewer-close'),
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(theme, colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
                      _error!,
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
                          onPressed: _prepareViewer,
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

    if (widget.surfaceBuilder != null) {
      return widget.surfaceBuilder!(context, file, _registerJsRunner);
    }

    final winController = _winWebViewController;
    if (winController != null) {
      return winwv.Webview(winController);
    }

    final controller = _webViewController;
    if (controller == null) return const SizedBox.shrink();
    return wf.WebViewWidget(controller: controller);
  }
}
