/// Boîte de dialogue d'importation et d'exportation JSON de l'apparence ([AppearanceTransferDialog]).
///
/// Permet de copier/coller ou d'enregistrer/charger un document JSON
/// en filtrant les groupes ([TransferGroup] : Styles et Dispositions).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/appearance/appearance_codec.dart';
import '../../services/appearance/appearance_transfer.dart';
import '../../services/appearance/appearance_store.dart';
import '../../theme/appearance.dart';
import '../editing/dialogs/editor_dialog.dart';
import '../editing/dialogs/editor_dialog_header.dart';

/// Format de sortie de l'export dans [AppearanceTransferDialog].
enum ExportFormat {
  json('JSON'),
  dart('Code Dart');

  const ExportFormat(this.label);

  /// Libellé affiché dans le sélecteur de format.
  final String label;
}

/// Boîte d'export et d'import du style et de la disposition.
///
/// L'export produit un texte JSON ou du code Dart (à copier ou à enregistrer
/// dans un fichier). L'import lit ce texte JSON (collé ou lu depuis un fichier),
/// propose les groupes qu'il contient et applique ceux qui sont cochés.
class AppearanceTransferDialog extends StatefulWidget {
  const AppearanceTransferDialog({
    required this.controller,
    this.codec = const AppearanceCodec(),
    this.allowImport = true,
    this.allowExport = true,
    this.notice,
    this.dartExportBuilder,
    this.dartExportWithOptionsBuilder,
    this.initialDecomposeComponents = true,
    super.key,
  }) : assert(allowImport || allowExport);

  final ValueNotifier<Appearance> controller;
  final AppearanceCodec codec;

  /// Limite le dialogue a l'import ou a l'export selon son usage.
  final bool allowImport;
  final bool allowExport;

  /// Avertissement affiche au-dessus de l'export (contenu partiel, etc.).
  final String? notice;

  /// Générateur optionnel de code Dart pour « Exporter le contenu... ».
  final String Function(Appearance appearance)? dartExportBuilder;

  /// Générateur optionnel de code Dart recevant l'option [decomposeComponents].
  final String Function(Appearance appearance, {required bool decomposeComponents})?
  dartExportWithOptionsBuilder;

  /// État initial de l'option « Décomposer les composants composés » en mode Code Dart.
  final bool initialDecomposeComponents;

  static Future<void> show(
    BuildContext context,
    ValueNotifier<Appearance> controller, {
    AppearanceCodec? codec,
  }) => showEditorDialog<void>(
    context: context,
    builder: (_) => AppearanceTransferDialog(
      controller: controller,
      codec: codec ?? AppearanceServicesScope.codecOf(context),
    ),
  );

  @override
  State<AppearanceTransferDialog> createState() =>
      _AppearanceTransferDialogState();
}

class _AppearanceTransferDialogState extends State<AppearanceTransferDialog> {
  bool _importing = false;
  ExportFormat _exportFormat = ExportFormat.json;
  late bool _decomposeComponents = widget.initialDecomposeComponents;
  var _exportGroups = {...TransferGroup.values};
  var _importGroups = <TransferGroup>{};
  Set<TransferGroup> _available = const {};

  final _exportText = TextEditingController();
  final _importText = TextEditingController();
  late final _file = TextEditingController(text: _defaultPath());

  String? _importError;
  String? _status;

  bool get _hasDartExport =>
      widget.dartExportWithOptionsBuilder != null ||
      widget.dartExportBuilder != null;

  static String _defaultPath([ExportFormat format = ExportFormat.json]) {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final ext = format == ExportFormat.dart ? 'dart' : 'json';
    return '$home${Platform.pathSeparator}appearance.$ext';
  }

  @override
  void initState() {
    super.initState();
    _importing = !widget.allowExport;
    if (widget.allowExport) _refreshExport();
  }

  @override
  void dispose() {
    _exportText.dispose();
    _importText.dispose();
    _file.dispose();
    super.dispose();
  }

  void _refreshExport() {
    if (_exportFormat == ExportFormat.dart && _hasDartExport) {
      if (widget.dartExportWithOptionsBuilder != null) {
        _exportText.text = widget.dartExportWithOptionsBuilder!(
          widget.controller.value,
          decomposeComponents: _decomposeComponents,
        );
      } else {
        _exportText.text = widget.dartExportBuilder!(widget.controller.value);
      }
      return;
    }
    _exportText.text = _exportGroups.isEmpty
        ? ''
        : AppearanceTransfer.export(
            widget.controller.value,
            _exportGroups,
            codec: widget.codec,
          );
  }

  void _setExportFormat(ExportFormat next) {
    if (_exportFormat == next) return;
    final previousDefault = _defaultPath(_exportFormat);
    setState(() {
      _exportFormat = next;
      _status = null;
      if (_file.text.trim() == previousDefault) {
        _file.text = _defaultPath(next);
      }
      _refreshExport();
    });
  }

  /// Relit le texte à importer : groupes présents, ou erreur à afficher.
  void _refreshImport() {
    final text = _importText.text;
    setState(() {
      _status = null;
      if (text.trim().isEmpty) {
        _available = const {};
        _importGroups = {};
        _importError = null;
        return;
      }
      try {
        _available = AppearanceTransfer.groupsIn(text, codec: widget.codec);
        _importGroups = {..._available};
        _importError = null;
      } on FormatException catch (error) {
        _available = const {};
        _importGroups = {};
        _importError = error.message;
      }
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _exportText.text));
    if (mounted) setState(() => _status = 'Copié dans le presse-papiers.');
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    _importText.text = data?.text ?? '';
    _refreshImport();
  }

  Future<void> _save() async {
    final path = _file.text.trim();
    if (path.isEmpty || _exportText.text.isEmpty) return;
    try {
      await File(path).writeAsString(_exportText.text);
      if (mounted) setState(() => _status = 'Enregistré : $path');
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _status = 'Enregistrement impossible : ${error.message}',
        );
      }
    }
  }

  Future<void> _read() async {
    final path = _file.text.trim();
    if (path.isEmpty) return;
    try {
      final text = await File(path).readAsString();
      if (!mounted) return;
      _importText.text = text;
      _refreshImport();
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _status = 'Lecture impossible : ${error.message}');
      }
    }
  }

  void _apply() {
    try {
      widget.controller.value = AppearanceTransfer.import(
        widget.controller.value,
        _importText.text,
        _importGroups,
        codec: widget.codec,
      );
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      setState(() => _importError = error.message);
    }
  }

  Widget _groupChips(
    Set<TransferGroup> selected,
    ValueChanged<TransferGroup> onToggle, {
    Set<TransferGroup>? enabled,
    required String keyPrefix,
  }) => Wrap(
    spacing: 8,
    children: [
      for (final group in TransferGroup.values)
        FilterChip(
          key: ValueKey('$keyPrefix-${group.name}'),
          label: Text(group.label),
          selected: selected.contains(group),
          onSelected: enabled != null && !enabled.contains(group)
              ? null
              : (_) => onToggle(group),
        ),
    ],
  );

  Widget _fileRow(List<Widget> actions) => Row(
    children: [
      Expanded(
        child: TextField(
          key: const ValueKey('transfer-file'),
          controller: _file,
          decoration: const InputDecoration(
            labelText: 'Fichier',
            isDense: true,
          ),
        ),
      ),
      const SizedBox(width: 8),
      ...actions,
    ],
  );

  Widget _exportTab() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.notice case final notice?) ...[
        Text(
          notice,
          key: const ValueKey('transfer-export-notice'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 8),
      ],
      if (_hasDartExport) ...[
        const Text('Format de l’export'),
        const SizedBox(height: 6),
        SegmentedButton<ExportFormat>(
          key: const ValueKey('transfer-export-format'),
          segments: const [
            ButtonSegment<ExportFormat>(
              value: ExportFormat.json,
              icon: Icon(Icons.data_object),
              label: Text('JSON'),
            ),
            ButtonSegment<ExportFormat>(
              value: ExportFormat.dart,
              icon: Icon(Icons.code),
              label: Text('Code Dart'),
            ),
          ],
          selected: {_exportFormat},
          onSelectionChanged: (selection) => _setExportFormat(selection.first),
        ),
        const SizedBox(height: 12),
      ],
      if (_exportFormat == ExportFormat.dart &&
          widget.dartExportWithOptionsBuilder != null) ...[
        FilterChip(
          key: const ValueKey('transfer-export-decompose'),
          label: const Text('Décomposer les composants composés'),
          selected: _decomposeComponents,
          onSelected: (selected) {
            setState(() {
              _decomposeComponents = selected;
              _status = null;
              _refreshExport();
            });
          },
        ),
        const SizedBox(height: 12),
      ],
      if (_exportFormat == ExportFormat.json) ...[
        const Text('Contenu de l’export'),
        const SizedBox(height: 6),
        _groupChips(_exportGroups, (group) {
          final next = {..._exportGroups};
          // Au moins un groupe reste coché.
          if (!next.remove(group)) {
            next.add(group);
          } else if (next.isEmpty) {
            return;
          }
          setState(() {
            _exportGroups = next;
            _status = null;
            _refreshExport();
          });
        }, keyPrefix: 'transfer-export'),
        const SizedBox(height: 12),
      ],
      TextField(
        key: const ValueKey('transfer-export-text'),
        controller: _exportText,
        readOnly: true,
        minLines: 6,
        maxLines: 10,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      _fileRow([
        OutlinedButton(
          key: const ValueKey('transfer-copy'),
          onPressed: _copy,
          child: const Text('Copier'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('transfer-save'),
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ]),
    ],
  );

  Widget _importTab() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const ValueKey('transfer-import-text'),
        controller: _importText,
        onChanged: (_) => _refreshImport(),
        minLines: 6,
        maxLines: 10,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: 'Collez ici un export d’apparence',
          errorText: _importError,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: 12),
      _fileRow([
        OutlinedButton(
          key: const ValueKey('transfer-paste'),
          onPressed: _paste,
          child: const Text('Coller'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const ValueKey('transfer-read'),
          onPressed: _read,
          child: const Text('Lire'),
        ),
      ]),
      const SizedBox(height: 12),
      const Text('À importer'),
      const SizedBox(height: 6),
      _groupChips(
        _importGroups,
        (group) => setState(() {
          _importGroups = _importGroups.contains(group)
              ? ({..._importGroups}..remove(group))
              : {..._importGroups, group};
        }),
        enabled: _available,
        keyPrefix: 'transfer-import',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('appearance-transfer'),
    title: EditorDialogHeader(
      label: !widget.allowImport
          ? 'Exporter le contenu'
          : !widget.allowExport
          ? 'Importer une apparence'
          : 'Importer / exporter',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.allowImport && widget.allowExport)
              SegmentedButton<bool>(
                key: const ValueKey('transfer-mode'),
                segments: const [
                  ButtonSegment(
                    value: false,
                    tooltip: 'Exporter',
                    icon: Icon(Icons.upload),
                    label: Text('Exporter'),
                  ),
                  ButtonSegment(
                    value: true,
                    tooltip: 'Importer',
                    icon: Icon(Icons.download),
                    label: Text('Importer'),
                  ),
                ],
                selected: {_importing},
                onSelectionChanged: (value) => setState(() {
                  _importing = value.first;
                  _status = null;
                }),
              ),
            const SizedBox(height: 16),
            _importing ? _importTab() : _exportTab(),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                key: const ValueKey('transfer-status'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fermer'),
      ),
      if (_importing)
        FilledButton(
          key: const ValueKey('transfer-apply'),
          onPressed: _importGroups.isEmpty ? null : _apply,
          child: const Text('Importer'),
        ),
    ],
  );
}
