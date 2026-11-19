/// Boîte de dialogue d'association, d'édition et de test en direct du
/// JSON Schema d'un repository JSON ([RepositorySchemaDialog]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:highlight/languages/json.dart' as highlight;
import 'package:material_ui/material_ui.dart';

import '../../../models/repository_json_schema.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../services/repositories/json_schema_validator.dart';
import '../../components/internal_widget/code_editor.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../overlay/editor_zoom.dart';

/// Boîte de dialogue permettant d'associer, modifier, tester et dissocier un
/// JSON Schema standard (Draft 7 / Draft 2020-12) sur un repository.
class RepositorySchemaDialog extends StatefulWidget {
  /// Crée le dialogue de schéma pour [repositoryId] dans [store].
  const RepositorySchemaDialog({
    required this.store,
    required this.repositoryId,
    this.repositoryName,
    super.key,
  });

  static const _preferredWidth = AlwaysStoppedAnimation<double>(860);

  /// Store porteur du repository et de son schéma persisté.
  final JsonRepositoryStore store;

  /// Identifiant technique du repository ciblé.
  final String repositoryId;

  /// Nom lisible optionnel affiché dans l'en-tête.
  final String? repositoryName;

  /// Ouvre la boîte de dialogue pour [repositoryId].
  static Future<void> show(
    BuildContext context, {
    required JsonRepositoryStore store,
    required String repositoryId,
    String? repositoryName,
  }) {
    final zoom = EditorZoomScope.controllerOf(context);
    return showEditorDialog<void>(
      context: context,
      target: zoom?.contentContext,
      preferredWidth: _preferredWidth,
      barrierDismissible: false,
      builder: (_) => JsonRepositoryScope(
        store: store,
        child: RepositorySchemaDialog(
          store: store,
          repositoryId: repositoryId,
          repositoryName: repositoryName,
        ),
      ),
    );
  }

  @override
  State<RepositorySchemaDialog> createState() => _RepositorySchemaDialogState();
}

class _RepositorySchemaDialogState extends State<RepositorySchemaDialog> {
  final _codeError = ValueNotifier<String>('');

  late final CodeEditorConfig _codeConfig = CodeEditorConfig(
    mode: highlight.json,
    getText: () => _schemaDraft,
    onChange: (String text, CodeEditorConfig _) {
      if (_schemaDraft == text) return;
      setState(() {
        _schemaDraft = text;
        _error = null;
        _notice = null;
        _validationResult = null;
      });
    },
    notifError: _codeError,
    useLargeTextViewer: false,
    type: 'json',
  );

  bool _loading = true;
  bool _saving = false;
  bool _hasPersistedSchema = false;
  bool _isCodeSchema = false;
  String _schemaDraft = _defaultTemplate;
  String _savedSchemaText = '';
  Object? _currentDocument;
  String? _error;
  String? _notice;
  JsonSchemaValidationResult? _validationResult;

  static const String _defaultTemplate = '''{
  "\$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {},
  "additionalProperties": true
}
''';

  bool get _dirty =>
      !_isCodeSchema && _schemaDraft.trim() != _savedSchemaText.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeError.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schema = await widget.store.readJsonSchema(widget.repositoryId);
      final doc = await widget.store.readDocument(widget.repositoryId);
      final isCode = widget.store.isCodeJsonSchema(widget.repositoryId);
      final encoded = schema == null
          ? _defaultTemplate
          : '${const JsonEncoder.withIndent('  ').convert(schema)}\n';
      if (!mounted) return;
      _codeConfig.readOnly = isCode;
      setState(() {
        _loading = false;
        _isCodeSchema = isCode;
        _hasPersistedSchema = schema != null;
        _schemaDraft = encoded;
        _savedSchemaText = schema == null ? '' : encoded;
        _currentDocument = doc;
      });
      _codeConfig.repaintCode();
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Erreur de fichier : ${error.message}';
        });
      }
    }
  }

  void _inferFromDocument() {
    if (_isCodeSchema || _saving) return;
    final inferred = JsonSchemaValidator.inferSchema(
      _currentDocument,
      title: widget.repositoryName,
    );
    final formatted =
        '${const JsonEncoder.withIndent('  ').convert(inferred)}\n';
    setState(() {
      _schemaDraft = formatted;
      _error = null;
      _notice = 'Schéma initial généré depuis le document courant.';
      _validationResult = JsonSchemaValidator.validate(
        _currentDocument,
        inferred,
      );
    });
    _codeConfig.repaintCode();
  }

  void _format() {
    try {
      final parsed = JsonSchemaValidator.parseSchemaText(_schemaDraft);
      final formatted =
          '${const JsonEncoder.withIndent('  ').convert(parsed)}\n';
      setState(() {
        _schemaDraft = formatted;
        _error = null;
      });
      _codeConfig.repaintCode();
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _testAgainstDocument() async {
    setState(() {
      _error = null;
      _notice = null;
      _validationResult = null;
    });
    try {
      final parsed = JsonSchemaValidator.parseSchemaText(_schemaDraft);
      final doc = await widget.store.readDocument(widget.repositoryId);
      final result = JsonSchemaValidator.validate(doc, parsed);
      if (!mounted) return;
      setState(() {
        _currentDocument = doc;
        _validationResult = result;
        if (result.isValid) {
          _notice = 'Document conforme au JSON Schema.';
        }
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _save() async {
    if (_saving || _isCodeSchema) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
      _validationResult = null;
    });
    try {
      final parsed = JsonSchemaValidator.parseSchemaText(_schemaDraft);
      await widget.store.saveJsonSchema(widget.repositoryId, parsed);
      final formatted =
          '${const JsonEncoder.withIndent('  ').convert(parsed)}\n';
      if (!mounted) return;
      setState(() {
        _schemaDraft = formatted;
        _savedSchemaText = formatted;
        _hasPersistedSchema = true;
        _validationResult = JsonSchemaValidationResult.valid;
        _notice = 'JSON Schema associé et enregistré.';
      });
      _codeConfig.repaintCode();
    } on JsonSchemaValidationException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _validationResult = JsonSchemaValidationResult(issues: error.issues);
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _error = 'Erreur de fichier : ${error.message}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeSchema() async {
    if (_saving || _isCodeSchema || !_hasPersistedSchema) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
      _validationResult = null;
    });
    try {
      await widget.store.saveJsonSchema(widget.repositoryId, null);
      if (!mounted) return;
      setState(() {
        _hasPersistedSchema = false;
        _savedSchemaText = '';
        _schemaDraft = _defaultTemplate;
        _notice = 'JSON Schema dissocié du repository.';
      });
      _codeConfig.repaintCode();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _error = 'Erreur de fichier : ${error.message}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titleSuffix = widget.repositoryName == null
        ? widget.repositoryId
        : '${widget.repositoryName} (${widget.repositoryId})';

    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: EditorDialogHeader(
        label: 'JSON Schema — $titleSuffix',
      ),
      content: SizedBox(
        width: 820,
        height: 540,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isCodeSchema)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: const Text(
                        'Ce JSON Schema est déclaré par l’application via '
                        'RepositoryImpl.jsonSchema (lecture seule).',
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: Icon(
                          _hasPersistedSchema
                              ? Icons.verified_outlined
                              : Icons.schema_outlined,
                          size: 16,
                        ),
                        label: Text(
                          _hasPersistedSchema
                              ? 'Schéma associé'
                              : 'Aucun schéma associé',
                        ),
                      ),
                      if (!_isCodeSchema)
                        OutlinedButton.icon(
                          key: const ValueKey('repository-schema-infer'),
                          onPressed: _saving ? null : _inferFromDocument,
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: const Text('Générer depuis le document'),
                        ),
                      if (!_isCodeSchema)
                        TextButton(
                          key: const ValueKey('repository-schema-format'),
                          onPressed: _saving ? null : _format,
                          child: const Text('Formater'),
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('repository-schema-test'),
                        onPressed: _saving ? null : _testAgainstDocument,
                        icon: const Icon(Icons.play_arrow_outlined, size: 18),
                        label: const Text('Tester sur le document'),
                      ),
                      if (_hasPersistedSchema && !_isCodeSchema)
                        TextButton.icon(
                          key: const ValueKey('repository-schema-remove'),
                          onPressed: _saving ? null : _removeSchema,
                          icon: const Icon(Icons.link_off, size: 18),
                          label: const Text('Dissocier'),
                        ),
                    ],
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 6),
                    const LinearProgressIndicator(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _error!,
                        key: const ValueKey('repository-schema-error'),
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _notice!,
                      key: const ValueKey('repository-schema-notice'),
                      style: TextStyle(color: colors.primary),
                    ),
                  ],
                  if (_validationResult != null &&
                      !_validationResult!.isValid &&
                      _error == null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _validationResult!.formatSummary(maxIssues: 8),
                        key: const ValueKey('repository-schema-issues'),
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CodeEditor(
                          key: const ValueKey('repository-schema-editor'),
                          config: _codeConfig,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('repository-schema-close'),
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        if (!_isCodeSchema)
          FilledButton(
            key: const ValueKey('repository-schema-save'),
            onPressed: _saving || (!_dirty && _hasPersistedSchema)
                ? null
                : _save,
            child: const Text('Enregistrer et associer'),
          ),
      ],
    );
  }
}
