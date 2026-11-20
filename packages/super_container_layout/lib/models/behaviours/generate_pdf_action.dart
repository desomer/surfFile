/// Action de comportement générant un PDF ([GeneratePdfAction]) depuis une page A4.
///
/// Déclenche [A4PdfGenerator] sur la page A4 courante ou sur une page A4
/// explicitement ciblée du catalogue, puis ouvre la boîte d'export PDF
/// (ou enregistre directement le fichier `.pdf` sur disque).
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../models/editor_page_config.dart';
import '../../services/pdf/a4_pdf_generator.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../../widgets/components/a4_document_page.dart';
import '../component_behavior.dart';

/// Mode de restitution du document PDF généré.
enum PdfOutputMode {
  /// Ouvre une boîte de dialogue permettant de choisir le nom, le dossier et d'exporter le `.pdf`.
  exportDialog('Boîte d’export PDF'),

  /// Enregistre directement le fichier `.pdf` dans le dossier par défaut (Téléchargements).
  saveFile('Enregistrement direct (.pdf)');

  const PdfOutputMode(this.label);

  /// Libellé affiché dans l'assistant de configuration.
  final String label;

  /// Décode un [PdfOutputMode] depuis son nom JSON.
  static PdfOutputMode fromJson(Object? value) => switch (value) {
    null || 'exportDialog' || 'previewAndPrint' => PdfOutputMode.exportDialog,
    'saveFile' => PdfOutputMode.saveFile,
    _ => throw FormatException('Mode de sortie PDF invalide : $value.'),
  };
}

/// Action générant un PDF à partir d'une page de type [EditorPageType.a4Document].
@immutable
class GeneratePdfAction extends BehaviorAction {
  /// Crée une action de génération PDF.
  const GeneratePdfAction({
    this.pageId,
    this.pageName,
    this.fileName,
    this.outputMode = PdfOutputMode.exportDialog,
  });

  /// Identifiant de la page A4 cible (`null` utilise la page A4 courante).
  final String? pageId;

  /// Nom lisible de la page cible pour le récapitulatif.
  final String? pageName;

  /// Surcharge optionnelle du nom de fichier PDF produit.
  final String? fileName;

  /// Mode de restitution (`exportDialog` ou `saveFile`).
  final PdfOutputMode outputMode;

  @override
  String get type => 'generatePdf';

  @override
  String get label => 'Exporter en PDF (A4)';

  @override
  String get description {
    final target = (pageName != null && pageName!.trim().isNotEmpty)
        ? pageName!.trim()
        : (pageId != null && pageId!.trim().isNotEmpty)
        ? pageId!.trim()
        : 'Page A4 courante';
    return '$target — ${outputMode.label}';
  }

  @override
  IconData get icon => Icons.picture_as_pdf_outlined;

  /// Vérifie les paramètres de l'action.
  void validate() {
    if (pageId != null && pageId!.trim().isEmpty) {
      throw const FormatException(
        'pageId ne doit pas être vide lorsqu’il est fourni.',
      );
    }
    if (fileName != null && fileName!.trim().isEmpty) {
      throw const FormatException(
        'fileName ne doit pas être vide lorsqu’il est fourni.',
      );
    }
  }

  String? _resolveTargetPageId(BuildContext context) {
    final explicit = pageId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final ancestorA4 = context
        .findAncestorWidgetOfExactType<A4DocumentPage>()
        ?.id;
    if (ancestorA4 != null) return ancestorA4;

    final appearance = AppearanceScope.of(context);
    final a4Pages = appearance.pageCatalog.pages
        .where((p) => p.pageType == EditorPageType.a4Document)
        .toList();
    if (a4Pages.length == 1) return a4Pages.single.id;
    return null;
  }

  @override
  Future<void> execute(BuildContext context) async {
    final targetId = _resolveTargetPageId(context);
    if (targetId == null) {
      _showMessage(
        context,
        'Aucune page Document A4 cible n’a été trouvée pour exporter le PDF.',
      );
      return;
    }

    try {
      final result = await A4PdfGenerator.generateFromContext(
        context,
        pageId: targetId,
        fileNameOverride: fileName,
      );
      if (!context.mounted) return;
      switch (outputMode) {
        case PdfOutputMode.exportDialog:
          final savedPath = await showDialog<String>(
            context: context,
            builder: (_) => _PdfExportDialog(result: result),
          );
          if (savedPath != null && context.mounted) {
            _showMessage(context, 'PDF exporté : $savedPath');
          }
        case PdfOutputMode.saveFile:
          final file = await _savePdfToDirectory(
            result: result,
            directory: defaultExportDirectory(),
            fileName: result.fileName,
          );
          if (context.mounted) {
            _showMessage(context, 'PDF exporté : ${file.path}');
          }
      }
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'Échec de l’export PDF : $error');
    }
  }

  void _showMessage(BuildContext context, String message) {
    if (Scaffold.maybeOf(context) == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Retourne le dossier d'export par défaut (`Downloads`, `Documents` ou dossier temporaire).
  static Directory defaultExportDirectory() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      for (final folder in ['Downloads', 'Documents']) {
        final candidate = Directory('$home${Platform.pathSeparator}$folder');
        if (candidate.existsSync()) return candidate;
      }
    }
    return Directory.systemTemp;
  }

  static Future<File> _savePdfToDirectory({
    required A4PdfResult result,
    required Directory directory,
    required String fileName,
  }) async {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    var cleanName = fileName.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (cleanName.isEmpty) cleanName = 'document.pdf';
    if (!cleanName.toLowerCase().endsWith('.pdf')) {
      cleanName = '$cleanName.pdf';
    }
    var file = File('${directory.path}${Platform.pathSeparator}$cleanName');
    if (file.existsSync()) {
      final dot = cleanName.lastIndexOf('.');
      final stem = dot > 0 ? cleanName.substring(0, dot) : cleanName;
      final ext = dot > 0 ? cleanName.substring(dot) : '.pdf';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      file = File(
        '${directory.path}${Platform.pathSeparator}$stem-$stamp$ext',
      );
    }
    return file.writeAsBytes(result.bytes, flush: true);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (pageId != null) 'pageId': pageId,
    if (pageName != null) 'pageName': pageName,
    if (fileName != null) 'fileName': fileName,
    if (outputMode != PdfOutputMode.exportDialog) 'outputMode': outputMode.name,
  };

  /// Décode une [GeneratePdfAction] depuis JSON.
  factory GeneratePdfAction.fromJson(Map<String, dynamic> json) {
    final action = GeneratePdfAction(
      pageId: json['pageId'] as String?,
      pageName: json['pageName'] as String?,
      fileName: json['fileName'] as String?,
      outputMode: PdfOutputMode.fromJson(json['outputMode']),
    );
    action.validate();
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratePdfAction &&
          other.pageId == pageId &&
          other.pageName == pageName &&
          other.fileName == fileName &&
          other.outputMode == outputMode;

  @override
  int get hashCode => Object.hash(pageId, pageName, fileName, outputMode);
}

class _PdfExportDialog extends StatefulWidget {
  const _PdfExportDialog({required this.result});

  final A4PdfResult result;

  @override
  State<_PdfExportDialog> createState() => _PdfExportDialogState();
}

class _PdfExportDialogState extends State<_PdfExportDialog> {
  late final TextEditingController _fileName = TextEditingController(
    text: widget.result.fileName,
  );
  late final TextEditingController _directory = TextEditingController(
    text: GeneratePdfAction.defaultExportDirectory().path,
  );
  bool _saving = false;
  bool _browsing = false;
  String? _error;

  @override
  void dispose() {
    _fileName.dispose();
    _directory.dispose();
    super.dispose();
  }

  List<({String label, String path})> get _quickFolders {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final folders = <({String label, String path})>[];
    if (home != null && home.trim().isNotEmpty) {
      for (final entry in [
        ('Téléchargements', 'Downloads'),
        ('Documents', 'Documents'),
        ('Bureau', 'Desktop'),
      ]) {
        final dir = Directory('$home${Platform.pathSeparator}${entry.$2}');
        if (dir.existsSync()) {
          folders.add((label: entry.$1, path: dir.path));
        }
      }
    }
    return folders;
  }

  Future<void> _browseWindowsSaveTarget() async {
    if (!Platform.isWindows || _browsing) return;
    setState(() {
      _browsing = true;
      _error = null;
    });
    try {
      final initialDir = _directory.text.trim().replaceAll("'", "''");
      var initialName = _fileName.text.trim();
      if (!initialName.toLowerCase().endsWith('.pdf')) {
        initialName = '$initialName.pdf';
      }
      initialName = initialName.replaceAll("'", "''");
      final script =
          "Add-Type -AssemblyName System.Windows.Forms; "
          "\$d = New-Object System.Windows.Forms.SaveFileDialog; "
          "\$d.Filter = 'Fichiers PDF (*.pdf)|*.pdf'; "
          "\$d.DefaultExt = 'pdf'; "
          "\$d.InitialDirectory = '$initialDir'; "
          "\$d.FileName = '$initialName'; "
          "if (\$d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { "
          "Write-Output \$d.FileName }";
      final proc = await Process.run('powershell', [
        '-NoProfile',
        '-STA',
        '-Command',
        script,
      ]);
      final chosen = (proc.stdout as String).trim();
      if (chosen.isNotEmpty && mounted) {
        final file = File(chosen);
        setState(() {
          _directory.text = file.parent.path;
          _fileName.text = file.uri.pathSegments.last;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Sélecteur indisponible : $error');
    } finally {
      if (mounted) setState(() => _browsing = false);
    }
  }

  Future<void> _export({required bool openAfterSave}) async {
    final dirPath = _directory.text.trim();
    final name = _fileName.text.trim();
    if (dirPath.isEmpty) {
      setState(() => _error = 'Indiquez un dossier de destination.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Indiquez un nom de fichier PDF.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final file = await GeneratePdfAction._savePdfToDirectory(
        result: widget.result,
        directory: Directory(dirPath),
        fileName: name,
      );
      if (openAfterSave && Platform.isWindows) {
        unawaited(Process.run('cmd', ['/c', 'start', '', file.path]));
      }
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Impossible d’enregistrer le fichier : $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final kb = (result.bytes.length / 1024).toStringAsFixed(1);
    final quick = _quickFolders;

    return AlertDialog(
      key: const ValueKey('pdf-export-dialog'),
      title: const Row(
        children: [
          Icon(Icons.picture_as_pdf_outlined, size: 22),
          SizedBox(width: 10),
          Expanded(child: Text('Exporter en PDF')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${result.pageCount} page${result.pageCount > 1 ? 's' : ''} A4 · $kb Ko'
                '${result.rasterFallbackCount > 0 ? ' · ${result.rasterFallbackCount} élément${result.rasterFallbackCount > 1 ? 's' : ''} graphique${result.rasterFallbackCount > 1 ? 's' : ''}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('pdf-export-filename'),
                controller: _fileName,
                decoration: const InputDecoration(
                  labelText: 'Nom du fichier',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('pdf-export-directory'),
                      controller: _directory,
                      decoration: const InputDecoration(
                        labelText: 'Dossier de destination',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (Platform.isWindows) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('pdf-export-browse'),
                      onPressed: _browsing || _saving
                          ? null
                          : _browseWindowsSaveTarget,
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: const Text('Parcourir…'),
                    ),
                  ],
                ],
              ),
              if (quick.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final folder in quick)
                      ActionChip(
                        label: Text(folder.label),
                        avatar: const Icon(Icons.folder_outlined, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setState(() => _directory.text = folder.path),
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('pdf-export-save-only'),
          onPressed: _saving ? null : () => _export(openAfterSave: false),
          icon: const Icon(Icons.save_alt_outlined, size: 18),
          label: const Text('Enregistrer'),
        ),
        FilledButton.icon(
          key: const ValueKey('pdf-export-save-open'),
          onPressed: _saving ? null : () => _export(openAfterSave: true),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Enregistrer et ouvrir'),
        ),
      ],
    );
  }
}
