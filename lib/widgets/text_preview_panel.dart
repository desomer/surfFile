import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:material_ui/material_ui.dart';

class TextPreviewPanel extends StatefulWidget {
  const TextPreviewPanel({
    required this.path,
    required this.onClose,
    required this.isExpanded,
    required this.onToggleExpanded,
    super.key,
  });

  final String? path;
  final VoidCallback onClose;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  static const _languagesByExtension = <String, MonacoLanguage>{
    '.bat': MonacoLanguage.bat,
    '.c': MonacoLanguage.c,
    '.cc': MonacoLanguage.cpp,
    '.cfg': MonacoLanguage.ini,
    '.conf': MonacoLanguage.ini,
    '.cpp': MonacoLanguage.cpp,
    '.cs': MonacoLanguage.csharp,
    '.css': MonacoLanguage.css,
    '.dart': MonacoLanguage.dart,
    '.env': MonacoLanguage.shell,
    '.go': MonacoLanguage.go,
    '.h': MonacoLanguage.c,
    '.hpp': MonacoLanguage.cpp,
    '.htm': MonacoLanguage.html,
    '.html': MonacoLanguage.html,
    '.ini': MonacoLanguage.ini,
    '.java': MonacoLanguage.java,
    '.js': MonacoLanguage.javascript,
    '.json': MonacoLanguage.json,
    '.jsx': MonacoLanguage.javascript,
    '.kt': MonacoLanguage.kotlin,
    '.kts': MonacoLanguage.kotlin,
    '.log': MonacoLanguage.plaintext,
    '.md': MonacoLanguage.markdown,
    '.markdown': MonacoLanguage.markdown,
    '.mjs': MonacoLanguage.javascript,
    '.php': MonacoLanguage.php,
    '.ps1': MonacoLanguage.powershell,
    '.py': MonacoLanguage.python,
    '.rb': MonacoLanguage.ruby,
    '.rs': MonacoLanguage.rust,
    '.sh': MonacoLanguage.shell,
    '.sql': MonacoLanguage.sql,
    '.swift': MonacoLanguage.swift,
    '.text': MonacoLanguage.plaintext,
    '.toml': MonacoLanguage.ini,
    '.ts': MonacoLanguage.typescript,
    '.tsx': MonacoLanguage.typescript,
    '.txt': MonacoLanguage.plaintext,
    '.xml': MonacoLanguage.xml,
    '.yaml': MonacoLanguage.yaml,
    '.yml': MonacoLanguage.yaml,
    '.csv': MonacoLanguage.plaintext,
    '.jsonc': MonacoLanguage.json,
  };

  static const _maximumPreviewBytes = 2 * 1024 * 1024;

  static bool supports(String path) => _extension(path) != null;

  static MonacoLanguage languageFor(String path) =>
      _languagesByExtension[_extension(path)] ?? MonacoLanguage.plaintext;

  static String? _extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final index = name.lastIndexOf('.');
    if (index == 0) {
      final dotFile = name.toLowerCase();
      return _languagesByExtension.containsKey(dotFile) ? dotFile : null;
    }
    if (index < 0) return null;
    final extension = name.substring(index).toLowerCase();
    return _languagesByExtension.containsKey(extension) ? extension : null;
  }

  @override
  State<TextPreviewPanel> createState() => _TextPreviewPanelState();
}

class _TextPreviewPanelState extends State<TextPreviewPanel> {
  String? _text;
  String? _editedText;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  int _loadGeneration = 0;
  int _saveGeneration = 0;
  MonacoController? _editorController;

  bool get _hasUnsavedChanges => _editedText != null && _editedText != _text;

  @override
  void initState() {
    super.initState();
    _loadText();
  }

  @override
  void didUpdateWidget(covariant TextPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _loadText();
  }

  Future<void> _loadText() async {
    final generation = ++_loadGeneration;
    _saveGeneration++;
    final path = widget.path;
    setState(() {
      _text = null;
      _editedText = null;
      _error = null;
      _loading = path != null;
      _saving = false;
      _editorController = null;
    });
    if (path == null) return;

    try {
      final file = File(path);
      final size = await file.length();
      if (size > TextPreviewPanel._maximumPreviewBytes) {
        throw const _PreviewTooLargeException();
      }
      final text = await file.readAsString();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _text = text;
        _editedText = text;
        _loading = false;
      });
    } on _PreviewTooLargeException {
      _setError(
        generation,
        'Les fichiers de plus de 2 Mo ne peuvent pas être prévisualisés.',
      );
    } on FileSystemException catch (error) {
      _setError(generation, 'Impossible de lire le fichier : ${error.message}');
    } on FormatException {
      _setError(
        generation,
        'Ce fichier ne contient pas du texte UTF-8 valide.',
      );
    }
  }

  void _setError(int generation, String message) {
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _saveText() async {
    final path = widget.path;
    final controller = _editorController;
    if (path == null || controller == null || !_hasUnsavedChanges || _saving) {
      return;
    }

    final generation = ++_saveGeneration;
    setState(() => _saving = true);
    try {
      final text = await controller.document.getText();
      await File(path).writeAsString(text, flush: true);
      if (!mounted || generation != _saveGeneration) return;
      setState(() {
        _text = text;
        _editedText ??= text;
        _saving = false;
      });
    } on FileSystemException catch (error) {
      _showSaveError(
        generation,
        'Impossible d’enregistrer le fichier : '
        '${error.message}',
      );
    } on MonacoException catch (error) {
      _showSaveError(
        generation,
        'Impossible de récupérer le texte de Monaco : '
        '$error',
      );
    } on PlatformException catch (error) {
      _showSaveError(
        generation,
        'Impossible d’enregistrer le fichier : '
        '${error.message ?? error.code}',
      );
    }
  }

  void _showSaveError(int generation, String message) {
    if (!mounted || generation != _saveGeneration) return;
    setState(() => _saving = false);
    debugPrint(message);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _loadGeneration++;
    _saveGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              children: [
                Icon(Icons.code_rounded, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.path == null
                        ? 'Prévisualisation texte'
                        : '${File(widget.path!).uri.pathSegments.last}'
                              '${_hasUnsavedChanges ? ' •' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: _saving
                      ? 'Enregistrement…'
                      : 'Enregistrer le fichier',
                  onPressed: _saving || !_hasUnsavedChanges ? null : _saveText,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: widget.isExpanded
                      ? 'Réduire la prévisualisation'
                      : 'Agrandir la prévisualisation',
                  onPressed: widget.onToggleExpanded,
                  icon: Icon(
                    widget.isExpanded
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Fermer la prévisualisation',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(child: _buildEditor(colors)),
        ],
      ),
    );
  }

  Widget _buildEditor(ColorScheme colors) {
    final text = _text;
    final path = widget.path;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (path == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Sélectionnez un fichier texte ou code pris en charge.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    if (_loading || text == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return MonacoEditor(
      key: ValueKey(path),
      initialText: text,
      options: EditorOptions(
        language: TextPreviewPanel.languageFor(path),
        theme: colors.brightness == Brightness.dark
            ? MonacoTheme.vsDark
            : MonacoTheme.vs,
        readOnly: false,
        minimap: const MonacoMinimapOptions(enabled: false),
        wordWrap: MonacoWordWrap.on,
        fontSize: 13,
        automaticLayout: true,
      ),
      onReady: (controller) {
        if (mounted) setState(() => _editorController = controller);
      },
      onContentChanged: (text) {
        if (mounted) {
          setState(() {
            _editedText = text;
          });
        }
      },
      backgroundColor: colors.surfaceContainerLow,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Impossible d’initialiser Monaco / WebView2 : $error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _PreviewTooLargeException implements Exception {
  const _PreviewTooLargeException();
}
