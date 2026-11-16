/// Assistant IHM de création et préconfiguration d'une datasource reliée à
/// `SuperBackend` ([SuperBackendDatasourceWizardDialog]).
///
/// Permet de configurer en un seul écran une datasource pointant sur une
/// collection SQLite locale (`nom_collection`, `id_entity`, `data_json`) de
/// `SuperBackend` :
/// * génère automatiquement les 5 `HttpProviderConfig` (`<id>_search`,
///   `<id>_create`, `<id>_read`, `<id>_update`, `<id>_delete`) pointant sur
///   `https://super.backend/api/<collection>` ;
/// * génère ou pré-remplit la [DatasourceConfig] correspondante (`keyPath`,
///   pagination, tri, liaisons cibles).
library;

import 'dart:async' show unawaited;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/datasources/datasource_config.dart';
import '../../../models/json_text_binding.dart';
import '../../../services/datasources/super_backend_datasource_bridge.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../overlay/editor_zoom.dart';
import '../repositories/repository_binding_fields.dart';

final _fieldSeparator = RegExp(r'[,;\s]+');

/// Dialogue d'assistant permettant de relier une datasource à une collection
/// SQLite locale de [SuperBackend].
class SuperBackendDatasourceWizardDialog extends StatefulWidget {
  /// Crée l'assistant ; si [saveDatasource] vaut `true`, enregistre à la fois
  /// les 5 providers et la [DatasourceConfig] sur disque, sinon enregistre
  /// uniquement les 5 providers et retourne la [DatasourceConfig] générée pour
  /// pré-remplir `DatasourceForm`.
  const SuperBackendDatasourceWizardDialog({
    required this.store,
    this.initialDatasourceId = '',
    this.initialLabel = '',
    this.initialKeyPath = 'id',
    this.saveDatasource = true,
    super.key,
  });

  static const _preferredWidth = AlwaysStoppedAnimation<double>(560);

  /// Store cible contenant les repositories, providers, datasources et
  /// `superBackendBridge`.
  final JsonRepositoryStore store;

  /// Identifiant initial proposé pour la datasource.
  final String initialDatasourceId;

  /// Libellé initial proposé.
  final String initialLabel;

  /// Chemin de clé initial (par défaut `'id'`).
  final String initialKeyPath;

  /// Si vrai, enregistre aussi la [DatasourceConfig] dans `store.datasources`.
  final bool saveDatasource;

  /// Ouvre le dialogue et retourne la [DatasourceConfig] générée (et
  /// éventuellement enregistrée), ou `null` si annulé.
  static Future<DatasourceConfig?> show(
    BuildContext context, {
    JsonRepositoryStore? store,
    String initialDatasourceId = '',
    String initialLabel = '',
    String initialKeyPath = 'id',
    bool saveDatasource = true,
  }) {
    final repositories = store ?? JsonRepositoryScope.maybeOf(context);
    if (repositories == null) return Future.value(null);
    final zoom = EditorZoomScope.controllerOf(context);
    return showEditorDialog<DatasourceConfig>(
      context: context,
      target: zoom?.contentContext,
      preferredWidth: _preferredWidth,
      barrierDismissible: false,
      builder: (_) => SuperBackendDatasourceWizardDialog(
        store: repositories,
        initialDatasourceId: initialDatasourceId,
        initialLabel: initialLabel,
        initialKeyPath: initialKeyPath,
        saveDatasource: saveDatasource,
      ),
    );
  }

  @override
  State<SuperBackendDatasourceWizardDialog> createState() =>
      _SuperBackendDatasourceWizardDialogState();
}

class _SuperBackendDatasourceWizardDialogState
    extends State<SuperBackendDatasourceWizardDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _collectionController;
  late final TextEditingController _labelController;
  late final TextEditingController _keyPathController;
  late final TextEditingController _pageSizeController;
  late final TextEditingController _sortFieldsController;

  List<JsonRepositoryEntry> _repositories = const [];
  JsonTextBinding? _listTarget;
  JsonTextBinding? _detailTarget;
  JsonTextBinding? _stateTarget;
  String _searchFilterRepoId = '';
  String _formRepoId = '';
  bool _mergeUpdates = true;
  bool _loadingRepos = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController(text: widget.initialDatasourceId);
    _collectionController = TextEditingController(
      text: widget.initialDatasourceId,
    );
    _labelController = TextEditingController(text: widget.initialLabel);
    _keyPathController = TextEditingController(
      text: widget.initialKeyPath.trim().isEmpty
          ? 'id'
          : widget.initialKeyPath.trim(),
    );
    _pageSizeController = TextEditingController(text: '20');
    _sortFieldsController = TextEditingController();
    unawaited(_loadRepositories());
  }

  @override
  void dispose() {
    for (final c in [
      _idController,
      _collectionController,
      _labelController,
      _keyPathController,
      _pageSizeController,
      _sortFieldsController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRepositories() async {
    try {
      final entries = await widget.store.catalog();
      if (!mounted) return;
      setState(() => _repositories = entries);
    } on Object {
      // Ignore catalog errors here; binding fields handle repository listing.
    } finally {
      if (mounted) setState(() => _loadingRepos = false);
    }
  }

  ScrudDatasourceBlueprint _buildBlueprint() {
    final id = _idController.text.trim();
    if (!isValidDatasourceId(id)) {
      throw const FormatException(
        'Identifiant de datasource invalide (a-z, 0-9 et _, 1 à 32 caractères).',
      );
    }
    final collection = _collectionController.text.trim().isEmpty
        ? id
        : _collectionController.text.trim();
    final label = _labelController.text.trim().isEmpty
        ? id
        : _labelController.text.trim();
    final keyPath = _keyPathController.text.trim().isEmpty
        ? 'id'
        : _keyPathController.text.trim();
    final pageSize = int.tryParse(_pageSizeController.text.trim());
    if (pageSize == null ||
        pageSize < 1 ||
        pageSize > DatasourcePagination.maxPageSize) {
      throw const FormatException(
        'La taille de page doit être comprise entre 1 et '
        '${DatasourcePagination.maxPageSize}.',
      );
    }
    final listTarget = _listTarget;
    if (listTarget == null ||
        listTarget.repositoryId == null ||
        listTarget.repositoryId!.isEmpty ||
        listTarget.path.trim().isEmpty) {
      throw const FormatException(
        'Sélectionnez le repository et le chemin de la liste de résultats (Search).',
      );
    }
    listTarget.validateResolved();

    final detailTarget = _detailTarget;
    if (detailTarget != null) {
      detailTarget.validateResolved();
    }
    final stateTarget = _stateTarget;
    if (stateTarget != null) {
      stateTarget.validateResolved();
    }

    final sortFields = [
      for (final item in _sortFieldsController.text.split(_fieldSeparator))
        if (item.trim().isNotEmpty) item.trim(),
    ];

    return ScrudDatasourceBlueprint(
      datasourceId: id,
      collection: collection,
      label: label,
      keyPath: keyPath,
      listTarget: (
        repositoryId: listTarget.repositoryId!,
        path: listTarget.path,
      ),
      detailTarget: detailTarget == null
          ? null
          : (repositoryId: detailTarget.repositoryId!, path: detailTarget.path),
      stateTarget: stateTarget == null
          ? null
          : (repositoryId: stateTarget.repositoryId!, path: stateTarget.path),
      searchFilterRepositoryId: _searchFilterRepoId.isEmpty
          ? null
          : _searchFilterRepoId,
      formRepositoryId: _formRepoId.isEmpty ? null : _formRepoId,
      pageSize: pageSize,
      sortFields: sortFields,
      mergeUpdates: _mergeUpdates,
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final blueprint = _buildBlueprint();
      final bridge = widget.store.superBackendBridge;
      if (widget.saveDatasource &&
          widget.store.datasources.datasource(blueprint.datasourceId) != null) {
        throw FormatException(
          'Une datasource « ${blueprint.datasourceId} » existe déjà.',
        );
      }
      final config = widget.saveDatasource
          ? await bridge.saveEditorDatasource(blueprint)
          : await bridge.saveEditorProviders(blueprint);
      if (!mounted) return;
      Navigator.pop(context, config);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on SuperBackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _repositoryDropdown({
    required String key,
    required String label,
    required String helper,
    required String value,
    required ValueChanged<String> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: InputDecorator(
      key: ValueKey(key),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            const DropdownMenuItem(value: '', child: Text('Aucun')),
            for (final repo in _repositories)
              DropdownMenuItem(
                value: repo.id,
                child: Text(
                  repo.name == repo.id
                      ? repo.name
                      : '${repo.name} (${repo.id})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (next) => setState(() => onChanged(next ?? '')),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const EditorDialogHeader(
        label: 'Connecter une datasource à SuperBackend',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingRepos || _busy) const LinearProgressIndicator(),
              Text(
                'Génère automatiquement les 5 opérations SCRUD '
                '(Search, Create, Read, Update, Delete) reliées à une '
                'collection SQLite locale (nom_collection, id_entity, data_json).',
                style: theme.textTheme.bodySmall,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('super-backend-wizard-error'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('super-backend-wizard-id'),
                controller: _idController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Identifiant de la datasource',
                  hintText: 'clients',
                  helperText: 'a-z, 0-9 et _ (ex. clients).',
                ),
                onChanged: (value) {
                  if (_collectionController.text.trim().isEmpty ||
                      _collectionController.text ==
                          value.substring(
                            0,
                            value.isEmpty ? 0 : value.length - 1,
                          )) {
                    _collectionController.text = value;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('super-backend-wizard-collection'),
                controller: _collectionController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Collection SQLite (nom_collection)',
                  hintText: 'clients',
                  helperText:
                      'Nom de la collection dans la table SQLite locale.',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('super-backend-wizard-label'),
                      controller: _labelController,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Libellé (facultatif)',
                        hintText: 'Clients',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('super-backend-wizard-key-path'),
                      controller: _keyPathController,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Clé des entités',
                        hintText: 'id',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Cible de la liste (Search — obligatoire)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              RepositoryBindingFields(
                keyPrefix: 'super-backend-wizard-list',
                binding: _listTarget,
                store: widget.store,
                pathHint: 'rows',
                helper: 'Tableau JSON qui reçoit les lignes de la collection.',
                onChanged: (value) => setState(() => _listTarget = value),
              ),
              const SizedBox(height: 12),
              Text(
                'Cible du détail (Read — facultatif)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              RepositoryBindingFields(
                keyPrefix: 'super-backend-wizard-detail',
                binding: _detailTarget,
                store: widget.store,
                pathHint: 'detail',
                helper: 'Objet JSON qui reçoit l’entité lue ou sélectionnée.',
                onChanged: (value) => setState(() => _detailTarget = value),
              ),
              const SizedBox(height: 12),
              Text(
                'État de pagination (Search — facultatif)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              RepositoryBindingFields(
                keyPrefix: 'super-backend-wizard-state',
                binding: _stateTarget,
                store: widget.store,
                pathHint: 'state',
                helper: 'Objet JSON qui reçoit page, total, hasNext…',
                onChanged: (value) => setState(() => _stateTarget = value),
              ),
              _repositoryDropdown(
                key: 'super-backend-wizard-filter-repo',
                label: 'Repository de filtre (Search — facultatif)',
                helper:
                    'Repository contenant les critères de recherche (q, champs…).',
                value: _searchFilterRepoId,
                onChanged: (value) => _searchFilterRepoId = value,
              ),
              _repositoryDropdown(
                key: 'super-backend-wizard-form-repo',
                label: 'Repository de formulaire (Create / Update — facultatif)',
                helper:
                    'Repository contenant les champs saisis pour créer ou modifier une entité.',
                value: _formRepoId,
                onChanged: (value) => _formRepoId = value,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      key: const ValueKey('super-backend-wizard-page-size'),
                      controller: _pageSizeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Lignes par page',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('super-backend-wizard-sort-fields'),
                      controller: _sortFieldsController,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Champs triables (facultatif)',
                        hintText: 'name, city, createdAt',
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('super-backend-wizard-merge'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Mise à jour partielle (PATCH / merge)'),
                subtitle: const Text(
                  'Fusionne les champs modifiés avec l’entité existante.',
                ),
                value: _mergeUpdates,
                onChanged: (value) => setState(() => _mergeUpdates = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('super-backend-wizard-cancel'),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const ValueKey('super-backend-wizard-submit'),
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.storage_outlined),
          label: Text(
            widget.saveDatasource
                ? 'Créer la datasource SuperBackend'
                : 'Générer et pré-remplir',
          ),
        ),
      ],
    );
  }
}
