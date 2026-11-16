/// Gestionnaire des datasources ([DatasourceManager]).
///
/// Boîte de dialogue de l'éditeur qui liste les datasources du registre
/// (`store.datasources`), crée, modifie et supprime celles persistées dans
/// `<dossier du store>/datasources/`, affiche en lecture seule celles définies
/// par le code de l'application, teste leur recherche sans rien écrire et la
/// lance. Une datasource regroupe les providers Search, Create, Read, Update
/// et Delete d'une même notion.
library;

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/datasources/datasource_config.dart';
import '../../../models/datasources/datasource_state.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/providers/data_provider.dart';
import '../../../services/datasources/datasource_registry.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../theme/appearance.dart';
import '../../appearance/appearance_scope.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../overlay/editor_zoom.dart';
import '../providers/data_provider_manager.dart';
import 'datasource_form.dart';
import 'super_backend_datasource_wizard.dart';

const _prettyJson = JsonEncoder.withIndent('  ');
const _maxPreviewLength = 600;

/// Boîte de dialogue de gestion des datasources du [JsonRepositoryStore].
class DatasourceManager extends StatefulWidget {
  /// Crée le gestionnaire ; [createNew] ouvre directement une nouvelle
  /// datasource.
  const DatasourceManager({
    this.store,
    this.appearance,
    this.initialDatasourceId,
    this.createNew = false,
    super.key,
  });

  static const _preferredWidth = AlwaysStoppedAnimation<double>(900);

  /// Store dont le registre de datasources est géré.
  final JsonRepositoryStore? store;

  /// Apparence consultée pour refuser la suppression d'une datasource
  /// utilisée.
  final ValueNotifier<Appearance>? appearance;

  /// Datasource sélectionnée à l'ouverture.
  final String? initialDatasourceId;

  /// Vrai pour ouvrir le formulaire de création.
  final bool createNew;

  /// Ouvre le gestionnaire et retourne l'identifiant de la dernière
  /// datasource enregistrée, ou `null` ; [store] remplace le store du
  /// [JsonRepositoryScope].
  static Future<String?> show(
    BuildContext context, {
    String? initialDatasourceId,
    bool createNew = false,
    JsonRepositoryStore? store,
  }) {
    final repositories = store ?? JsonRepositoryScope.maybeOf(context);
    final appearance = AppearanceScope.controllerOf(context);
    final zoom = EditorZoomScope.controllerOf(context);
    return showEditorDialog<String>(
      context: context,
      target: zoom?.contentContext,
      preferredWidth: _preferredWidth,
      barrierDismissible: false,
      builder: (_) => DatasourceManager(
        store: repositories,
        appearance: appearance,
        initialDatasourceId: initialDatasourceId,
        createNew: createNew,
      ),
    );
  }

  @override
  State<DatasourceManager> createState() => _DatasourceManagerState();
}

class _DatasourceManagerState extends State<DatasourceManager> {
  var _formKey = GlobalKey<DatasourceFormState>();
  Map<String, String> _names = const {};
  String? _selectedId;
  String? _savedId;
  String? _error;
  String? _notice;
  ({bool ok, String text})? _test;
  bool _creating = false;
  bool _touched = false;
  bool _busy = false;
  bool _testing = false;
  bool _confirming = false;
  bool _closing = false;

  DatasourceRegistry? get _registry => widget.store?.datasources;

  @override
  void initState() {
    super.initState();
    final registry = _registry;
    if (registry == null) return;
    registry.addListener(_registryChanged);
    widget.store?.providers.addListener(_registryChanged);
    unawaited(
      _run(() async {
        await widget.store!.providers.ensureLoaded();
        await registry.ensureLoaded();
        if (!mounted) return;
        final initial = widget.initialDatasourceId;
        _show(
          id: initial != null && registry.datasource(initial) != null
              ? initial
              : null,
          creating: widget.createNew,
        );
        await _loadNames();
      }),
    );
  }

  @override
  void dispose() {
    _registry?.removeListener(_registryChanged);
    widget.store?.providers.removeListener(_registryChanged);
    super.dispose();
  }

  void _registryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadNames() async {
    final entries = await widget.store!.catalog();
    if (!mounted) return;
    setState(
      () => _names = {for (final entry in entries) entry.id: entry.name},
    );
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await operation();
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _error = 'Erreur de fichier : ${error.message}');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Affiche [id] (ou le formulaire de création) avec un formulaire neuf.
  void _show({String? id, bool creating = false, String? notice}) =>
      setState(() {
        _selectedId = creating ? null : id;
        _creating = creating;
        _touched = false;
        _test = null;
        _error = null;
        _notice = notice;
        _formKey = GlobalKey<DatasourceFormState>();
      });

  void _edited() => setState(() {
    _touched = true;
    _error = null;
    _notice = null;
  });

  Future<bool> _discard() async {
    if (!_touched) return true;
    if (_confirming) return false;
    _confirming = true;
    final result = await showEditorDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Abandonner les modifications de la datasource ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            key: const ValueKey('datasource-confirm-discard'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    _confirming = false;
    return result == true && mounted;
  }

  Future<void> _select(String id) async {
    if (_busy || (!_creating && id == _selectedId)) return;
    if (!await _discard() || !mounted) return;
    _show(id: id);
  }

  Future<void> _create() async {
    if (_busy) return;
    if (!await _discard() || !mounted) return;
    _show(creating: true);
  }

  Future<void> _createSuperBackend() async {
    final store = widget.store;
    if (_busy || store == null) return;
    if (!await _discard() || !mounted) return;
    final config = await SuperBackendDatasourceWizardDialog.show(
      context,
      store: store,
      saveDatasource: true,
    );
    if (config == null || !mounted) return;
    _savedId = config.id;
    _show(
      id: config.id,
      notice: 'Datasource SuperBackend « ${config.id} » créée.',
    );
  }

  Future<String?> _createProvider() =>
      DataProviderManager.show(context, createNew: true, store: widget.store);

  Future<void> _save() async {
    final form = _formKey.currentState;
    final registry = _registry;
    if (form == null || registry == null || _busy) return;
    final draft = form.draft();
    final config = draft.config;
    if (config == null) {
      setState(() {
        _error = draft.error;
        _notice = null;
      });
      return;
    }
    final creating = _creating;
    await _run(() async {
      if (creating && registry.datasource(config.id) != null) {
        throw FormatException('Une datasource « ${config.id} » existe déjà.');
      }
      await registry.save(config);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _selectedId = config.id;
        _savedId = config.id;
        _touched = false;
        _test = null;
        _notice = 'Datasource enregistrée.';
      });
    });
  }

  Future<void> _delete() async {
    final id = _selectedId;
    final registry = _registry;
    if (id == null || registry == null || _busy || _confirming) return;
    final appearance =
        (widget.appearance ?? AppearanceScope.controllerOf(context))?.value;
    if (appearance?.usesDatasource(id) ?? false) {
      setState(() {
        _notice = null;
        _error =
            'Impossible de supprimer « $id » : '
            'cette datasource est encore utilisée par un comportement.';
      });
      return;
    }
    _confirming = true;
    final label = registry.datasource(id)?.label ?? id;
    final confirmed = await showEditorDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la datasource ?'),
        content: Text(
          'Supprimer définitivement « $label » (datasources/$id.json) ? '
          'Ses providers sont conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('datasource-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (confirmed != true || !mounted) return;
    final current =
        (widget.appearance ?? AppearanceScope.controllerOf(context))?.value;
    await _run(() async {
      await registry.delete(id, appearance: current);
      if (!mounted) return;
      if (_savedId == id) _savedId = null;
      _show(notice: 'Datasource supprimée.');
    });
  }

  DatasourceConfig? _currentConfig(DatasourceRegistry registry) {
    if (_touched || _creating) return _formKey.currentState?.draft().config;
    final id = _selectedId;
    return id == null ? null : registry.datasource(id);
  }

  Future<void> _runTest() async {
    final registry = _registry;
    if (registry == null || _testing) return;
    final form = _formKey.currentState;
    final draft = form?.draft();
    final config = draft == null ? _currentConfig(registry) : draft.config;
    if (config == null) {
      setState(
        () => _test = (ok: false, text: draft?.error ?? 'Saisie invalide.'),
      );
      return;
    }
    setState(() {
      _testing = true;
      _test = null;
    });
    try {
      final result = await registry.previewSearch(config);
      if (mounted) {
        setState(
          () => _test = (
            ok: true,
            text: _describe(result.rows, result.total, result.nextCursor),
          ),
        );
      }
    } on DataProviderException catch (error) {
      if (mounted) setState(() => _test = (ok: false, text: error.message));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  static String _describe(List<Object?> rows, int? total, String? cursor) {
    final buffer = StringBuffer('${rows.length} ligne(s) reçue(s)');
    if (total != null) buffer.write(' sur $total');
    buffer.write('.');
    if (cursor != null) buffer.write(' Curseur suivant : $cursor.');
    if (rows.isNotEmpty) {
      final text = _prettyJson.convert(rows.first);
      buffer
        ..write(' Première ligne :\n')
        ..write(
          text.length > _maxPreviewLength
              ? '${text.substring(0, _maxPreviewLength)}…'
              : text,
        );
    }
    return buffer.toString();
  }

  Future<void> _search(String id) async {
    // L'état et l'éventuelle erreur s'affichent dans le gestionnaire.
    await _registry?.run(id, DatasourceCommand.search, reportErrors: false);
  }

  Future<void> _close() async {
    if (_busy || !await _discard() || !mounted) return;
    setState(() {
      _touched = false;
      _closing = true;
    });
    // Let PopScope observe the clean state before popping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, _savedId);
    });
  }

  String _bindingText(JsonTextBinding? binding) => binding == null
      ? '—'
      : '${_names[binding.repositoryId] ?? 'Repository ${binding.repositoryId}'}'
            ' › ${binding.path}';

  Widget _statusIcon(DatasourceRegistry registry, String id) =>
      ValueListenableBuilder<DatasourceStatus>(
        valueListenable: registry.stateOf(id),
        builder: (context, status, _) {
          final scheme = Theme.of(context).colorScheme;
          return switch (status.phase) {
            DataProviderPhase.idle => const SizedBox.shrink(),
            DataProviderPhase.loading => const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            DataProviderPhase.success => Icon(
              Icons.check_circle_outline,
              size: 18,
              color: scheme.primary,
            ),
            DataProviderPhase.error => Icon(
              Icons.error_outline,
              size: 18,
              color: scheme.error,
            ),
          };
        },
      );

  Widget _datasources(DatasourceRegistry registry) {
    final datasources = registry.datasources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('datasource-create'),
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('Nouvelle'),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: const ValueKey('datasource-create-super-backend'),
          onPressed: _busy || widget.store == null ? null : _createSuperBackend,
          icon: const Icon(Icons.storage_outlined, size: 18),
          label: const Text('SuperBackend…'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: datasources.isEmpty && !_creating
              ? const Text('Aucune datasource.')
              : ListView(
                  children: [
                    if (_creating)
                      const ListTile(
                        key: ValueKey('datasource-entry-new'),
                        leading: Icon(Icons.add_circle_outline),
                        title: Text('Nouvelle datasource'),
                        selected: true,
                      ),
                    for (final datasource in datasources)
                      ListTile(
                        key: ValueKey('datasource-entry-${datasource.id}'),
                        leading: Icon(
                          registry.isEditable(datasource.id)
                              ? Icons.dataset_outlined
                              : Icons.code,
                        ),
                        title: Text(
                          datasource.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${datasource.id} · '
                          '${datasource.operations.map((op) => op.title[0]).join()}'
                          '${registry.isEditable(datasource.id) ? '' : ' · code'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: !_creating && datasource.id == _selectedId,
                        enabled: !_busy,
                        onTap: () => _select(datasource.id),
                        trailing: _statusIcon(registry, datasource.id),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _searchButton(DatasourceRegistry registry, DatasourceConfig config) =>
      ValueListenableBuilder<DatasourceStatus>(
        valueListenable: registry.stateOf(config.id),
        builder: (context, status, _) {
          final button = TextButton.icon(
            key: const ValueKey('datasource-search'),
            onPressed: _busy || _touched || status.isLoading
                ? null
                : () => unawaited(_search(config.id)),
            icon: const Icon(Icons.search),
            label: const Text('Rechercher'),
          );
          return _touched
              ? Tooltip(
                  message:
                      'Enregistrez les modifications avant de lancer la '
                      'recherche.',
                  child: button,
                )
              : button;
        },
      );

  static String _pageText(DatasourcePageState page) {
    final parts = <String>[
      'page ${page.page}',
      if (page.pageCount case final count?) 'sur $count',
      if (page.total case final total?) '($total ligne(s) au total)',
      if (page.hasNext) '· page suivante disponible',
    ];
    return parts.join(' ');
  }

  Widget _status(DatasourceRegistry registry, String id) =>
      ValueListenableBuilder<DatasourceStatus>(
        valueListenable: registry.stateOf(id),
        builder: (context, status, _) {
          final theme = Theme.of(context);
          final command = switch (status.command) {
            final command? => 'Commande « ${command.label} »',
            null => 'Commande',
          };
          final (String text, Color? color) = switch (status.phase) {
            DataProviderPhase.idle => ('Aucune commande lancée.', null),
            DataProviderPhase.loading => ('$command en cours…', null),
            DataProviderPhase.success => (
              status.command?.operation == DatasourceOperation.search
                  ? '$command terminée : ${_pageText(status.page)}.'
                  : status.message ?? '$command terminée.',
              null,
            ),
            DataProviderPhase.error => (
              status.message ?? '$command en échec.',
              theme.colorScheme.error,
            ),
          };
          return Text(
            text,
            key: const ValueKey('datasource-status'),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          );
        },
      );

  Widget _problems(DatasourceRegistry registry) {
    final config = _currentConfig(registry);
    final problems = config == null
        ? const <String>[]
        : registry.problemsOf(config);
    if (problems.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        problems.join('\n'),
        key: const ValueKey('datasource-problems'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }

  Widget _testResult(({bool ok, String text}) test) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 120),
        child: SingleChildScrollView(
          child: SelectableText(
            test.text,
            key: const ValueKey('datasource-test-result'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: test.ok ? null : theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }

  Widget _readOnly(DatasourceConfig config) {
    final theme = Theme.of(context);
    final search = config.search;
    final pagination = search?.pagination;
    final sort = search?.sort;
    final rows = <(String, String)>[
      ('Identifiant', config.id),
      ('Libellé', config.label),
      ('Clé des entités', config.keyPath ?? '—'),
      for (final operation in DatasourceOperation.values)
        (operation.title, config.providerOf(operation) ?? '—'),
      if (config.create case final create?)
        (
          'Insertion',
          create.insert == DatasourceInsert.start ? 'Au début' : 'À la fin',
        ),
      if (search != null) ...[
        ('État de la recherche', _bindingText(search.state)),
        (
          'Tri',
          sort == null
              ? 'Non'
              : '${sort.fieldParam}'
                    '${sort.directionParam == null ? '' : ' + ${sort.directionParam}'}'
                    '${sort.fields.isEmpty ? '' : ' (${sort.fields.join(', ')})'}',
        ),
        (
          'Pagination',
          pagination == null
              ? 'Non'
              : '${pagination.mode.name}, ${pagination.pageSize} ligne(s) '
                    '(${pagination.parameterNames.join(', ')})',
        ),
      ],
    ];
    return ListView(
      children: [
        Text(
          'Définie par le code de l’application : lecture seule.',
          key: const ValueKey('datasource-readonly'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  child: Text(label, style: theme.textTheme.labelMedium),
                ),
                Expanded(child: SelectableText(value)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _details(DatasourceRegistry registry) {
    final id = _selectedId;
    if (!_creating && id == null) {
      return const Center(child: Text('Sélectionnez ou créez une datasource.'));
    }
    final config = id == null ? null : registry.datasource(id);
    if (!_creating && config == null) {
      return const Center(child: Text('Cette datasource n’existe plus.'));
    }
    final editable = _creating || registry.isEditable(id!);
    final testing = _testing
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.play_arrow_outlined);
    final canSearch = !_creating && config!.supports(DatasourceCommand.search);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              '${_creating ? 'Nouvelle datasource' : config!.label}'
              '${_touched ? ' *' : ''}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Tooltip(
              message:
                  'Exécute la recherche (page 1) sans rien écrire ; les '
                  'opérations Create, Read, Update et Delete ne sont jamais '
                  'testées ici.',
              child: TextButton.icon(
                key: const ValueKey('datasource-test'),
                onPressed: _busy || _testing ? null : _runTest,
                icon: testing,
                label: const Text('Tester la recherche'),
              ),
            ),
            if (canSearch) _searchButton(registry, config),
            if (!_creating && editable)
              TextButton.icon(
                key: const ValueKey('datasource-delete'),
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
          ],
        ),
        if (!_creating) _status(registry, id!),
        _problems(registry),
        if (_test case final test?) _testResult(test),
        const SizedBox(height: 8),
        Expanded(
          child: editable
              ? DatasourceForm(
                  key: _formKey,
                  initial: _creating ? null : registry.configOf(id!),
                  store: widget.store,
                  isNew: _creating,
                  onEdited: _edited,
                  onCreateProvider: _createProvider,
                )
              : _readOnly(config!),
        ),
      ],
    );
  }

  Widget _body(DatasourceRegistry registry) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 600
        ? Column(
            children: [
              SizedBox(
                height: math.min(130, constraints.maxHeight * .4),
                child: _datasources(registry),
              ),
              const SizedBox(height: 8),
              Expanded(child: _details(registry)),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 220, child: _datasources(registry)),
              const SizedBox(width: 16),
              Expanded(child: _details(registry)),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) {
    final registry = _registry;
    return PopScope(
      canPop: _closing || (!_busy && !_touched && _savedId == null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) unawaited(_close());
      },
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        title: const EditorDialogHeader(label: 'Datasources'),
        content: SizedBox(
          width: 900,
          height: 560,
          child: registry == null
              ? const Center(
                  child: Text('Service de repositories indisponible.'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(
                        _error!,
                        key: const ValueKey('datasource-manager-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_notice != null)
                      Text(
                        _notice!,
                        key: const ValueKey('datasource-manager-notice'),
                      ),
                    const SizedBox(height: 8),
                    Expanded(child: _body(registry)),
                  ],
                ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('datasource-close'),
            onPressed: _busy ? null : _close,
            child: const Text('Fermer'),
          ),
          FilledButton(
            key: const ValueKey('datasource-save'),
            onPressed: _busy || !_touched || registry == null ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
