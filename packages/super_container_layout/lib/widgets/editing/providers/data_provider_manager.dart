/// Gestionnaire des providers de données ([DataProviderManager]).
///
/// Boîte de dialogue de l'éditeur qui liste les providers du registre
/// (`store.providers`), crée, modifie, teste et supprime les providers HTTP
/// persistés dans `<dossier du store>/providers/`, affiche en lecture seule
/// ceux définis par le code de l'application et lance leur recherche.
library;

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/providers/data_provider.dart';
import '../../../services/providers/data_provider_registry.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../theme/appearance.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../overlay/editor_zoom.dart';
import 'http_provider_form.dart';

const _prettyJson = JsonEncoder.withIndent('  ');
const _maxPreviewLength = 600;

/// Boîte de dialogue de gestion des providers du [JsonRepositoryStore].
class DataProviderManager extends StatefulWidget {
  /// Crée le gestionnaire ; [createNew] ouvre directement un nouveau provider.
  const DataProviderManager({
    this.store,
    this.appearance,
    this.initialProviderId,
    this.createNew = false,
    super.key,
  });

  static const _preferredWidth = AlwaysStoppedAnimation<double>(900);

  /// Store dont le registre de providers est géré.
  final JsonRepositoryStore? store;

  /// Apparence consultée pour refuser la suppression d'un provider utilisé.
  final ValueNotifier<Appearance>? appearance;

  /// Provider sélectionné à l'ouverture.
  final String? initialProviderId;

  /// Vrai pour ouvrir le formulaire de création.
  final bool createNew;

  /// Ouvre le gestionnaire et retourne l'identifiant du dernier provider
  /// enregistré, ou `null` ; [store] remplace le store du [JsonRepositoryScope]
  /// (dossier ouvert dans le gestionnaire de repositories par exemple).
  static Future<String?> show(
    BuildContext context, {
    String? initialProviderId,
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
      builder: (_) => DataProviderManager(
        store: repositories,
        appearance: appearance,
        initialProviderId: initialProviderId,
        createNew: createNew,
      ),
    );
  }

  @override
  State<DataProviderManager> createState() => _DataProviderManagerState();
}

class _DataProviderManagerState extends State<DataProviderManager> {
  var _formKey = GlobalKey<HttpProviderFormState>();
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

  DataProviderRegistry? get _registry => widget.store?.providers;

  @override
  void initState() {
    super.initState();
    final registry = _registry;
    if (registry == null) return;
    registry.addListener(_registryChanged);
    unawaited(
      _run(() async {
        await registry.ensureLoaded();
        if (!mounted) return;
        final initial = widget.initialProviderId;
        _show(
          id: initial != null && registry.provider(initial) != null
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
        _formKey = GlobalKey<HttpProviderFormState>();
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
        content: const Text('Abandonner les modifications du provider ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            key: const ValueKey('provider-confirm-discard'),
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
      if (creating && registry.provider(config.id) != null) {
        throw FormatException('Un provider « ${config.id} » existe déjà.');
      }
      await registry.save(config);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _selectedId = config.id;
        _savedId = config.id;
        _touched = false;
        _notice = 'Provider enregistré.';
      });
    });
  }

  Future<void> _delete() async {
    final id = _selectedId;
    final registry = _registry;
    if (id == null || registry == null || _busy || _confirming) return;
    final appearance =
        (widget.appearance ?? AppearanceScope.controllerOf(context))?.value;
    if (appearance?.usesProvider(id) ?? false) {
      setState(() {
        _notice = null;
        _error =
            'Impossible de supprimer « $id » : '
            'ce provider est encore utilisé par un comportement.';
      });
      return;
    }
    _confirming = true;
    final label = registry.provider(id)?.label ?? id;
    final confirmed = await showEditorDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le provider ?'),
        content: Text(
          'Supprimer définitivement « $label » (providers/$id.json) ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('provider-confirm-delete'),
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
      _show(notice: 'Provider supprimé.');
    });
  }

  Future<void> _runTest() async {
    final form = _formKey.currentState;
    final registry = _registry;
    if (form == null || registry == null || _testing) return;
    final draft = form.draft();
    final config = draft.config;
    if (config == null) {
      setState(
        () => _test = (ok: false, text: draft.error ?? 'Saisie invalide.'),
      );
      return;
    }
    setState(() {
      _testing = true;
      _test = null;
    });
    try {
      final rows = await registry.preview(config);
      if (mounted) setState(() => _test = (ok: true, text: _describe(rows)));
    } on DataProviderException catch (error) {
      if (mounted) setState(() => _test = (ok: false, text: error.message));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  static String _describe(List<Object?> rows) {
    final buffer = StringBuffer('${rows.length} ligne(s) reçue(s).');
    if (rows.isNotEmpty) {
      var first = _prettyJson.convert(rows.first);
      if (first.length > _maxPreviewLength) {
        first = '${first.substring(0, _maxPreviewLength)}…';
      }
      buffer
        ..write(' Première ligne :\n')
        ..write(first);
    }
    return buffer.toString();
  }

  Future<void> _search(String id) async {
    // L'état et l'éventuelle erreur s'affichent dans le gestionnaire.
    await _registry?.search(id, reportErrors: false);
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

  String _repositoryName(String? id) =>
      id == null ? '—' : _names[id] ?? 'Repository $id';

  String _bindingText(JsonTextBinding? binding) => binding == null
      ? '—'
      : '${_repositoryName(binding.repositoryId)} › ${binding.path}';

  Widget _statusIcon(DataProviderRegistry registry, String id) =>
      ValueListenableBuilder<DataProviderStatus>(
        valueListenable: registry.statusOf(id),
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

  Widget _providers(DataProviderRegistry registry) {
    final providers = registry.providers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('provider-create'),
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('Nouveau'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: providers.isEmpty && !_creating
              ? const Text('Aucun provider.')
              : ListView(
                  children: [
                    if (_creating)
                      const ListTile(
                        key: ValueKey('provider-entry-new'),
                        leading: Icon(Icons.add_circle_outline),
                        title: Text('Nouveau provider'),
                        selected: true,
                      ),
                    for (final provider in providers)
                      ListTile(
                        key: ValueKey('provider-entry-${provider.id}'),
                        leading: Icon(
                          registry.isEditable(provider.id)
                              ? Icons.cloud_outlined
                              : Icons.code,
                        ),
                        title: Text(
                          provider.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          registry.isEditable(provider.id)
                              ? provider.id
                              : '${provider.id} · code',
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: !_creating && provider.id == _selectedId,
                        enabled: !_busy,
                        onTap: () => _select(provider.id),
                        trailing: _statusIcon(registry, provider.id),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _searchButton(DataProviderRegistry registry, String id) =>
      ValueListenableBuilder<DataProviderStatus>(
        valueListenable: registry.statusOf(id),
        builder: (context, status, _) {
          final button = TextButton.icon(
            key: const ValueKey('provider-search'),
            onPressed: _busy || _touched || status.isLoading
                ? null
                : () => unawaited(_search(id)),
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

  Widget _status(DataProviderRegistry registry, String id) =>
      ValueListenableBuilder<DataProviderStatus>(
        valueListenable: registry.statusOf(id),
        builder: (context, status, _) {
          final theme = Theme.of(context);
          final (String text, Color? color) = switch (status.phase) {
            DataProviderPhase.idle => ('Aucune recherche lancée.', null),
            DataProviderPhase.loading => ('Recherche en cours…', null),
            DataProviderPhase.success => (
              '${status.rowCount ?? 0} ligne(s) écrite(s) lors de la '
                  'dernière recherche.',
              null,
            ),
            DataProviderPhase.error => (
              status.message ?? 'La recherche a échoué.',
              theme.colorScheme.error,
            ),
          };
          return Text(
            text,
            key: const ValueKey('provider-status'),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          );
        },
      );

  Widget _testResult(({bool ok, String text}) test) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 120),
        child: SingleChildScrollView(
          child: SelectableText(
            test.text,
            key: const ValueKey('provider-test-result'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: test.ok ? null : theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }

  Widget _readOnly(DataProvider provider) {
    final theme = Theme.of(context);
    final filter = provider.filterRepositoryId;
    final auto = provider.autoSearch;
    final rows = <(String, String)>[
      ('Identifiant', provider.id),
      ('Libellé', provider.label),
      ('Filtre', filter == null ? 'Aucun' : _repositoryName(filter)),
      ('Résultats', _bindingText(provider.target)),
      ('Chargement', _bindingText(provider.loading)),
      ('Erreur', _bindingText(provider.error)),
      (
        'Recherche automatique',
        auto == null
            ? 'Non'
            : 'Oui, ${auto.debounceMs} ms après une modification'
                  '${auto.onStart ? ' et au démarrage' : ''}',
      ),
    ];
    return ListView(
      children: [
        Text(
          'Défini par le code de l’application : lecture seule.',
          key: const ValueKey('provider-readonly'),
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

  Widget _details(DataProviderRegistry registry) {
    final id = _selectedId;
    if (!_creating && id == null) {
      return const Center(child: Text('Sélectionnez ou créez un provider.'));
    }
    final provider = id == null ? null : registry.provider(id);
    if (!_creating && provider == null) {
      return const Center(child: Text('Ce provider n’existe plus.'));
    }
    final editable = _creating || registry.isEditable(id!);
    final testing = _testing
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.play_arrow_outlined);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              '${_creating ? 'Nouveau provider' : provider!.label}'
              '${_touched ? ' *' : ''}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (editable)
              TextButton.icon(
                key: const ValueKey('provider-test'),
                onPressed: _busy || _testing ? null : _runTest,
                icon: testing,
                label: const Text('Tester'),
              ),
            if (!_creating) _searchButton(registry, id!),
            if (!_creating && editable)
              TextButton.icon(
                key: const ValueKey('provider-delete'),
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
          ],
        ),
        if (!_creating) _status(registry, id!),
        if (_test case final test?) _testResult(test),
        const SizedBox(height: 8),
        Expanded(
          child: editable
              ? HttpProviderForm(
                  key: _formKey,
                  initial: _creating ? null : registry.configOf(id!),
                  store: widget.store,
                  isNew: _creating,
                  onEdited: _edited,
                )
              : _readOnly(provider!),
        ),
      ],
    );
  }

  Widget _body(DataProviderRegistry registry) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 600
        ? Column(
            children: [
              SizedBox(
                height: math.min(130, constraints.maxHeight * .4),
                child: _providers(registry),
              ),
              const SizedBox(height: 8),
              Expanded(child: _details(registry)),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 220, child: _providers(registry)),
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
        title: const EditorDialogHeader(label: 'Providers'),
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
                        key: const ValueKey('provider-manager-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_notice != null)
                      Text(
                        _notice!,
                        key: const ValueKey('provider-manager-notice'),
                      ),
                    const SizedBox(height: 8),
                    Expanded(child: _body(registry)),
                  ],
                ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('provider-close'),
            onPressed: _busy ? null : _close,
            child: const Text('Fermer'),
          ),
          FilledButton(
            key: const ValueKey('provider-save'),
            onPressed: _busy || !_touched || registry == null ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
