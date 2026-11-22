/// Boîte de dialogue de gestion, d'édition JavaScript et de test en direct
/// des attributs calculés d'un repository JSON ([CalculatedAttributesDialog]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:highlight/languages/javascript.dart' as js_lang;
import 'package:material_ui/material_ui.dart';

import '../../../models/calculated_attribute_definition.dart';
import '../../../models/json_text_binding.dart';
import '../../../services/diagnostics/debug_entry.dart';
import '../../../services/inspection/vibe_debug_capture.dart';
import '../../../services/repositories/calculated_attribute.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../components/internal_widget/code_editor.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../overlay/editor_zoom.dart';
import 'js_calculated_examples.dart';

/// Boîte de dialogue de gestion des attributs calculés JavaScript d'un repository.
class CalculatedAttributesDialog extends StatefulWidget {
  /// Crée la boîte de dialogue pour [repositoryId] dans [store].
  const CalculatedAttributesDialog({
    required this.store,
    required this.repositoryId,
    this.repositoryName,
    super.key,
  });

  static const _preferredWidth = AlwaysStoppedAnimation<double>(900);

  /// Store porteur du repository et de ses formules persistées.
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
        child: CalculatedAttributesDialog(
          store: store,
          repositoryId: repositoryId,
          repositoryName: repositoryName,
        ),
      ),
    );
  }

  @override
  State<CalculatedAttributesDialog> createState() =>
      _CalculatedAttributesDialogState();
}

class _CalculatedAttributesDialogState
    extends State<CalculatedAttributesDialog> {
  final _nameController = TextEditingController();
  final _scopeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _indicesController = TextEditingController(text: '0');
  final _codeError = ValueNotifier<String>('');

  late final CodeEditorConfig _codeConfig = CodeEditorConfig(
    mode: js_lang.javascript,
    getText: () => _codeDraft,
    onChange: (String text, CodeEditorConfig _) {
      if (_codeDraft == text) return;
      setState(() {
        _codeDraft = text;
        _testResult = null;
        _testError = null;
      });
    },
    notifError: _codeError,
    useLargeTextViewer: false,
    type: 'javascript',
  );

  List<CalculatedAttributeDefinition> _jsDefinitions = const [];
  List<CalculatedAttributeDescriptor> _dartDescriptors = const [];
  List<String> _scopeSuggestions = const [];
  List<String> _otherRepositoryIds = const [];
  Object? _document;

  int? _selectedJsIndex;
  int? _selectedDartIndex;
  bool _creatingNew = false;
  String _codeDraft = 'row.prix * row.quantite';
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _error;
  String? _notice;
  String? _testResult;
  String? _testError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scopeController.dispose();
    _descriptionController.dispose();
    _indicesController.dispose();
    _codeError.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jsDefs = await widget.store.readCalculatedAttributes(
        widget.repositoryId,
      );
      final dartDefs = widget.store
          .calculatedAttributeCatalog(widget.repositoryId)
          .where((d) => !d.isJs)
          .toList(growable: false);
      final doc = await widget.store.readDocument(widget.repositoryId);
      final suggestions = _collectArrayScopes(doc);
      if (!mounted) return;
      setState(() {
        _jsDefinitions = List<CalculatedAttributeDefinition>.of(jsDefs);
        _dartDescriptors = dartDefs;
        _document = doc;
        _scopeSuggestions = suggestions;
        _loading = false;
        if (_jsDefinitions.isNotEmpty) {
          _selectJs(0);
        } else if (_dartDescriptors.isNotEmpty) {
          _selectDart(0);
        } else {
          _startNew();
        }
      });
      _loadOtherRepositories();
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

  Future<void> _loadOtherRepositories() async {
    try {
      final catalog = await widget.store.catalog();
      final otherRepoIds = catalog
          .where((entry) => entry.id != widget.repositoryId)
          .map((entry) => entry.id)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _otherRepositoryIds = otherRepoIds;
      });
    } catch (_) {
      // Information optionnelle pour les badges inter-repositories.
    }
  }

  static List<String> _collectArrayScopes(Object? document) {
    final scopes = <String>{};
    void visit(Object? node, String prefix) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = entry.key.toString();
          if (key.startsWith('@')) continue;
          final next = prefix.isEmpty ? key : '$prefix.$key';
          visit(entry.value, next);
        }
      } else if (node is List) {
        if (prefix.isNotEmpty) {
          final scope = '$prefix[?]';
          scopes.add(scope);
          for (final item in node) {
            visit(item, scope);
          }
        }
      }
    }

    visit(document, '');
    final sorted = scopes.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List<String>.unmodifiable(sorted);
  }

  void _selectJs(int index) {
    final def = _jsDefinitions[index];
    setState(() {
      _creatingNew = false;
      _selectedJsIndex = index;
      _selectedDartIndex = null;
      _nameController.text = def.name;
      _scopeController.text = def.scope ?? '';
      _descriptionController.text = def.description ?? '';
      _codeDraft = def.code;
      _error = null;
      _notice = null;
      _testResult = null;
      _testError = null;
      _codeConfig.repaintCode();
    });
  }

  void _selectDart(int index) {
    setState(() {
      _creatingNew = false;
      _selectedDartIndex = index;
      _selectedJsIndex = null;
      _error = null;
      _notice = null;
      _testResult = null;
      _testError = null;
    });
  }

  void _startNew() {
    setState(() {
      _creatingNew = true;
      _selectedJsIndex = null;
      _selectedDartIndex = null;
      _nameController.clear();
      _scopeController.clear();
      _descriptionController.clear();
      _codeDraft = 'return row;';
      _error = null;
      _notice = null;
      _testResult = null;
      _testError = null;
      _codeConfig.repaintCode();
    });
  }

  void _applyCodeExample(String code) {
    setState(() {
      _codeDraft = code;
      _testResult = null;
      _testError = null;
      _codeConfig.repaintCode();
    });
  }

  List<JsCalculatedExample> _buildCurrentExamples() {
    final currentScope = _scopeController.text.trim();
    final sameScopeNames = <String>[
      for (final def in _jsDefinitions)
        if ((def.scope ?? '') == currentScope) def.name,
    ];
    final rootNames = <String>[
      for (final def in _jsDefinitions)
        if (def.scope == null) def.name,
    ];
    final scopedPaths = <String>[
      for (final def in _jsDefinitions)
        if (def.scope != null) def.path,
    ];

    for (final descriptor in _dartDescriptors) {
      final path = descriptor.path;
      final atIndex = path.lastIndexOf('@');
      if (atIndex < 0) continue;
      final name = path.substring(atIndex + 1);
      final descriptorScope = atIndex == 0
          ? ''
          : path.substring(0, atIndex - 1);
      if (descriptorScope == currentScope) {
        sameScopeNames.add(name);
      }
      if (descriptorScope.isEmpty) {
        rootNames.add(name);
      } else {
        scopedPaths.add(path);
      }
    }

    final currentName = _nameController.text.trim();
    return buildJsCalculatedExamples(
      document: _document,
      scope: currentScope,
      sameScopeCalculatedNames: sameScopeNames,
      rootCalculatedNames: rootNames,
      scopedCalculatedPaths: scopedPaths,
      otherRepositoryIds: _otherRepositoryIds,
      currentAttributeName: currentName.isEmpty ? null : currentName,
    );
  }

  CalculatedAttributeDefinition _buildDraftDefinition() {
    final rawScope = _scopeController.text.trim();
    return CalculatedAttributeDefinition(
      name: _nameController.text,
      scope: rawScope.isEmpty ? null : rawScope,
      code: _codeDraft,
      description: _descriptionController.text,
    );
  }

  List<int> _parseIndices(String? scope) {
    if (scope == null || scope.isEmpty) return const [];
    final expected = JsonAttributePath(scope).wildcardCount;
    if (expected == 0) return const [];
    final raw = _indicesController.text.trim();
    final parts = raw.isEmpty
        ? const <String>[]
        : raw.split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty).toList();
    final indices = <int>[];
    for (var i = 0; i < expected; i++) {
      final token = i < parts.length ? parts[i] : '0';
      final parsed = int.tryParse(token);
      if (parsed == null || parsed < 0) {
        throw FormatException('Indice de ligne invalide : « $token ».');
      }
      indices.add(parsed);
    }
    return indices;
  }

  Future<void> _saveCurrent() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final draft = _buildDraftDefinition();
      final next = List<CalculatedAttributeDefinition>.of(_jsDefinitions);
      final existingIdx = _selectedJsIndex;
      if (_creatingNew || existingIdx == null) {
        if (next.any((d) => d.path == draft.path)) {
          throw FormatException(
            'Un attribut calculé « ${draft.path} » existe déjà.',
          );
        }
        next.add(draft);
      } else {
        for (var i = 0; i < next.length; i++) {
          if (i != existingIdx && next[i].path == draft.path) {
            throw FormatException(
              'Un autre attribut calculé porte déjà le chemin « ${draft.path} ».',
            );
          }
        }
        next[existingIdx] = draft;
      }
      await widget.store.saveCalculatedAttributes(widget.repositoryId, next);
      final targetIndex = _creatingNew || existingIdx == null
          ? next.length - 1
          : existingIdx;
      if (!mounted) return;
      setState(() {
        _jsDefinitions = next;
        _creatingNew = false;
        _selectedJsIndex = targetIndex;
        _selectedDartIndex = null;
        _notice = 'Attribut calculé « ${draft.path} » enregistré.';
      });
    } on FormatException catch (error, stack) {
      VibeDebugCapture.recordTypedError(
        message: '[JS ERROR] ${error.message}',
        category: DebugErrorCategory.javascript,
        severity: DebugSeverity.error,
        stackTrace: stack,
        source: 'CalculatedAttributesDialog(${widget.repositoryId})',
        visibleInUi: true,
      );
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException catch (error, stack) {
      final msg = 'Erreur de fichier : ${error.message}';
      VibeDebugCapture.recordTypedError(
        message: msg,
        category: DebugErrorCategory.binding,
        severity: DebugSeverity.error,
        stackTrace: stack,
        source: 'CalculatedAttributesDialog(${widget.repositoryId})',
        visibleInUi: true,
      );
      if (mounted) {
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteJs(int index) async {
    if (_saving) return;
    final removed = _jsDefinitions[index];
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final next = List<CalculatedAttributeDefinition>.of(_jsDefinitions)
        ..removeAt(index);
      await widget.store.saveCalculatedAttributes(widget.repositoryId, next);
      if (!mounted) return;
      setState(() {
        _jsDefinitions = next;
        _notice = 'Attribut calculé « ${removed.path} » supprimé.';
        if (_jsDefinitions.isNotEmpty) {
          _selectJs(index.clamp(0, _jsDefinitions.length - 1));
        } else if (_dartDescriptors.isNotEmpty) {
          _selectDart(0);
        } else {
          _startNew();
        }
      });
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

  Future<void> _runTest() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _testError = null;
    });
    try {
      final draft = _buildDraftDefinition();
      final indices = _parseIndices(draft.scope);
      final value = await widget.store.testCalculatedAttribute(
        widget.repositoryId,
        draft,
        indices: indices,
      );
      if (!mounted) return;
      final formatted = value == null
          ? 'null'
          : (value is String || value is num || value is bool)
          ? jsonEncode(value)
          : const JsonEncoder.withIndent('  ').convert(value);
      setState(() => _testResult = formatted);
    } on FormatException catch (error, stack) {
      VibeDebugCapture.recordTypedError(
        message: '[JS ERROR] Test attribut calculé : ${error.message}',
        category: DebugErrorCategory.javascript,
        severity: DebugSeverity.critical,
        stackTrace: stack,
        source: 'CalculatedAttributesDialog.test(${widget.repositoryId})',
        visibleInUi: true,
      );
      if (mounted) setState(() => _testError = error.message);
    } on FileSystemException catch (error, stack) {
      final msg = 'Erreur de fichier : ${error.message}';
      VibeDebugCapture.recordTypedError(
        message: msg,
        category: DebugErrorCategory.binding,
        severity: DebugSeverity.error,
        stackTrace: stack,
        source: 'CalculatedAttributesDialog.test(${widget.repositoryId})',
        visibleInUi: true,
      );
      if (mounted) {
        setState(() => _testError = msg);
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String get _previewPath {
    final name = _nameController.text.trim();
    final scope = _scopeController.text.trim();
    if (name.isEmpty) return scope.isEmpty ? '@…' : '$scope.@…';
    return scope.isEmpty ? '@$name' : '$scope.@$name';
  }

  Widget _buildListPane(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('calculated-attr-add'),
          onPressed: _saving ? null : _startNew,
          icon: const Icon(Icons.add),
          label: const Text('Nouveau calcul JS'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: (_jsDefinitions.isEmpty && _dartDescriptors.isEmpty)
              ? Text(
                  'Aucun champ calculé défini.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : ListView(
                  children: [
                    for (var i = 0; i < _jsDefinitions.length; i++)
                      ListTile(
                        key: ValueKey('calculated-attr-js-$i'),
                        dense: true,
                        selected: !_creatingNew && _selectedJsIndex == i,
                        title: Text(
                          _jsDefinitions[i].path,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'JavaScript',
                          style: TextStyle(color: colors.primary, fontSize: 11),
                        ),
                        onTap: _saving ? null : () => _selectJs(i),
                        trailing: IconButton(
                          key: ValueKey('calculated-attr-delete-$i'),
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: _saving ? null : () => _deleteJs(i),
                        ),
                      ),
                    for (var i = 0; i < _dartDescriptors.length; i++)
                      ListTile(
                        key: ValueKey('calculated-attr-dart-$i'),
                        dense: true,
                        selected: !_creatingNew && _selectedDartIndex == i,
                        title: Text(
                          _dartDescriptors[i].path,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Dart (lecture seule)',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                        onTap: () => _selectDart(i),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!_creatingNew && _selectedDartIndex != null) {
      final descriptor = _dartDescriptors[_selectedDartIndex!];
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Text(
              descriptor.path,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Cet attribut calculé est déclaré côté code Dart via '
              'RepositoryImpl.addCalculatedAttribute. Il est utilisable dans '
              'les liaisons en lecture seule, mais ne peut pas être modifié ici.',
            ),
          ],
        ),
      );
    }

    final hasWildcard = _scopeController.text.contains('[?]');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('calculated-attr-name'),
                controller: _nameController,
                enabled: !_saving,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Nom du champ calculé',
                  prefixText: '@',
                  helperText: 'Liaison : $_previewPath',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: TextFormField(
                key: const ValueKey('calculated-attr-scope'),
                controller: _scopeController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Portée (scope, optionnel)',
                  hintText: 'ex. articles[?]',
                  helperText: 'Vide = calcul racine du repository',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (_scopeSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ActionChip(
                label: const Text('Racine'),
                onPressed: _saving
                    ? null
                    : () => setState(() => _scopeController.clear()),
              ),
              for (final scope in _scopeSuggestions)
                ActionChip(
                  label: Text(scope),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _scopeController.text = scope),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('calculated-attr-description'),
          controller: _descriptionController,
          enabled: !_saving,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Description (optionnel)',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Exemples JS (clic pour préremplir)',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            Text(
              'Paramètres : row, ctx (ctx.get(chemin, repoId?, defaut?)), doc',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 108),
          child: SingleChildScrollView(
            child: Wrap(
              key: const ValueKey('calculated-attr-examples'),
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final example in _buildCurrentExamples())
                  Tooltip(
                    message: '${example.description}\n\n${example.code}',
                    child: ActionChip(
                      key: ValueKey('calculated-attr-example-${example.id}'),
                      avatar: example.isSchemaAdapted
                          ? Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: colors.primary,
                            )
                          : null,
                      backgroundColor: example.isSchemaAdapted
                          ? colors.secondaryContainer.withValues(alpha: 0.65)
                          : null,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      label: Text(
                        example.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _saving
                          ? null
                          : () => _applyCodeExample(example.code),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: CodeEditor(
              key: const ValueKey('calculated-attr-code'),
              config: _codeConfig,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (hasWildcard)
                  SizedBox(
                    width: 140,
                    child: TextFormField(
                      key: const ValueKey('calculated-attr-test-indices'),
                      controller: _indicesController,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Indices [?]',
                        hintText: '0 ou 0,1',
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('calculated-attr-test'),
                  onPressed: _testing || _saving ? null : _runTest,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(_testing ? 'Test…' : 'Tester'),
                ),
              ],
            ),
            FilledButton.icon(
              key: const ValueKey('calculated-attr-save'),
              onPressed: _saving ? null : _saveCurrent,
              icon: const Icon(Icons.save, size: 18),
              label: Text(
                _creatingNew ? 'Ajouter le calcul' : 'Enregistrer le calcul',
              ),
            ),
          ],
        ),
        if (_testResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText(
              'Résultat : $_testResult',
              key: const ValueKey('calculated-attr-test-result'),
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                color: colors.primary,
              ),
            ),
          ),
        if (_testError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText(
              _testError!,
              key: const ValueKey('calculated-attr-test-error'),
              style: TextStyle(fontSize: 12, color: colors.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleSuffix = widget.repositoryName ?? widget.repositoryId;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: EditorDialogHeader(label: 'Champs calculés (JS) — $titleSuffix'),
      content: SizedBox(
        width: 900,
        height: 580,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saving) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        key: const ValueKey('calculated-attr-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _notice!,
                        key: const ValueKey('calculated-attr-notice'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 240, child: _buildListPane(context)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildDetailPane(context)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('calculated-attr-close'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
