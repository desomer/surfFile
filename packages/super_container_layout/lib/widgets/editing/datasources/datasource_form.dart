/// Formulaire d'édition d'une datasource ([DatasourceForm]).
///
/// Saisie guidée d'une [DatasourceConfig] : identité, clé des entités, un
/// provider existant par opération (Search, Create, Read, Update, Delete),
/// position d'insertion des créations, et pour la recherche : état, tri et
/// pagination. Le formulaire ne connaît pas le registre des datasources : le
/// gestionnaire lit la saisie courante avec [DatasourceFormState.draft], puis
/// l'enregistre ou la teste.
library;

import 'dart:async' show unawaited;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/datasources/datasource_config.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/providers/data_provider.dart';
import '../../../services/datasources/super_backend_datasource_bridge.dart';
import '../../../services/providers/data_provider_registry.dart';
import '../../../services/providers/http_data_provider.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../repositories/repository_binding_fields.dart';
import 'super_backend_datasource_wizard.dart';

/// Saisie courante d'un [DatasourceForm] : une configuration valide ou le
/// message d'erreur affichable qui l'en sépare.
typedef DatasourceDraft = ({DatasourceConfig? config, String? error});

final _listSeparator = RegExp(r'[,;\s]+');

/// Formulaire de saisie d'une [DatasourceConfig].
class DatasourceForm extends StatefulWidget {
  /// Crée le formulaire ; [initial] est `null` pour une nouvelle datasource.
  const DatasourceForm({
    required this.onEdited,
    this.initial,
    this.store,
    this.isNew = true,
    this.onCreateProvider,
    super.key,
  });

  /// Datasource à modifier, ou `null` pour en créer une.
  final DatasourceConfig? initial;

  /// Store dont les providers et les repositories sont proposés.
  final JsonRepositoryStore? store;

  /// Vrai tant que l'identifiant (nom du fichier) peut être choisi.
  final bool isNew;

  /// Appelé après chaque modification de l'utilisateur.
  final VoidCallback onEdited;

  /// Ouvre la création d'un provider et retourne son identifiant, ou `null`.
  final Future<String?> Function()? onCreateProvider;

  @override
  State<DatasourceForm> createState() => DatasourceFormState();
}

/// État de [DatasourceForm] ; [draft] expose la saisie courante.
class DatasourceFormState extends State<DatasourceForm> {
  late final TextEditingController _id;
  late final TextEditingController _label;
  late final TextEditingController _keyPath;
  late final TextEditingController _sortParam;
  late final TextEditingController _directionParam;
  late final TextEditingController _sortFields;
  late final TextEditingController _defaultSort;
  late final TextEditingController _pageSize;
  late final TextEditingController _pageParam;
  late final TextEditingController _sizeParam;
  late final TextEditingController _offsetParam;
  late final TextEditingController _limitParam;
  late final TextEditingController _cursorParam;
  late final TextEditingController _nextCursorPath;
  late final TextEditingController _totalPath;
  final _providers = <DatasourceOperation, String>{};
  JsonTextBinding? _state;
  late bool _sortEnabled;
  late DatasourceSortDirection _defaultDirection;
  late bool _paginationEnabled;
  late DatasourcePaginationMode _mode;
  late int _firstPage;
  late DatasourceInsert _insert;
  bool _touched = false;

  DataProviderRegistry? get _registry => widget.store?.providers;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final search = initial?.search;
    final sort = search?.sort;
    final pagination = search?.pagination ?? const DatasourcePagination();
    _id = TextEditingController(text: initial?.id ?? '');
    _label = TextEditingController(text: initial?.label ?? '');
    _keyPath = TextEditingController(text: initial?.keyPath ?? '');
    _sortParam = TextEditingController(text: sort?.fieldParam ?? 'sort');
    _directionParam = TextEditingController(text: sort?.directionParam ?? '');
    _sortFields = TextEditingController(text: sort?.fields.join(', ') ?? '');
    _defaultSort = TextEditingController(text: sort?.defaultOrder?.field ?? '');
    _pageSize = TextEditingController(text: '${pagination.pageSize}');
    _pageParam = TextEditingController(text: pagination.pageParam);
    _sizeParam = TextEditingController(text: pagination.sizeParam);
    _offsetParam = TextEditingController(text: pagination.offsetParam);
    _limitParam = TextEditingController(text: pagination.limitParam);
    _cursorParam = TextEditingController(text: pagination.cursorParam);
    _nextCursorPath = TextEditingController(
      text: pagination.nextCursorPath ?? '',
    );
    _totalPath = TextEditingController(text: pagination.totalPath ?? '');
    for (final operation in DatasourceOperation.values) {
      _providers[operation] = initial?.providerOf(operation) ?? '';
    }
    _state = search?.state;
    _sortEnabled = sort != null;
    _defaultDirection =
        sort?.defaultOrder?.direction ?? DatasourceSortDirection.asc;
    _paginationEnabled = search?.pagination != null;
    _mode = pagination.mode;
    _firstPage = pagination.firstPage;
    _insert = initial?.create?.insert ?? DatasourceInsert.end;
    _registry?.addListener(_providersChanged);
  }

  @override
  void dispose() {
    _registry?.removeListener(_providersChanged);
    for (final controller in [
      _id,
      _label,
      _keyPath,
      _sortParam,
      _directionParam,
      _sortFields,
      _defaultSort,
      _pageSize,
      _pageParam,
      _sizeParam,
      _offsetParam,
      _limitParam,
      _cursorParam,
      _nextCursorPath,
      _totalPath,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _providersChanged() {
    if (mounted) setState(() {});
  }

  /// Applique [mutate] puis signale au gestionnaire que la saisie a changé.
  void _change(VoidCallback mutate) {
    setState(() {
      mutate();
      _touched = true;
    });
    widget.onEdited();
  }

  String? _providerOf(DatasourceOperation operation) {
    final id = _providers[operation] ?? '';
    return id.isEmpty ? null : id;
  }

  static String? _optional(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  DatasourceSort _sort() {
    final defaultField = _optional(_defaultSort);
    return DatasourceSort(
      fieldParam: _optional(_sortParam) ?? 'sort',
      directionParam: _optional(_directionParam),
      fields: [
        for (final field in _sortFields.text.split(_listSeparator))
          if (field.isNotEmpty) field,
      ],
      defaultOrder: defaultField == null
          ? null
          : DatasourceSortOrder(defaultField, _defaultDirection),
    );
  }

  DatasourcePagination _pagination() {
    final pageSize = int.tryParse(_pageSize.text.trim());
    if (pageSize == null) {
      throw const FormatException(
        'Pagination : la taille de page doit être un nombre entier.',
      );
    }
    const defaults = DatasourcePagination();
    return DatasourcePagination(
      mode: _mode,
      pageSize: pageSize,
      pageParam: _optional(_pageParam) ?? defaults.pageParam,
      sizeParam: _optional(_sizeParam) ?? defaults.sizeParam,
      firstPage: _firstPage,
      offsetParam: _optional(_offsetParam) ?? defaults.offsetParam,
      limitParam: _optional(_limitParam) ?? defaults.limitParam,
      cursorParam: _optional(_cursorParam) ?? defaults.cursorParam,
      nextCursorPath: _mode == DatasourcePaginationMode.cursor
          ? _optional(_nextCursorPath)
          : null,
      totalPath: _optional(_totalPath),
    );
  }

  /// Saisie courante : la configuration complète et valide, ou le message
  /// d'erreur affichable de la première erreur rencontrée.
  DatasourceDraft draft() {
    try {
      final id = _id.text.trim();
      final label = _label.text.trim();
      final search = _providerOf(DatasourceOperation.search);
      final create = _providerOf(DatasourceOperation.create);
      DatasourceEntityConfig? entity(DatasourceOperation operation) =>
          switch (_providerOf(operation)) {
            final provider? => DatasourceEntityConfig(provider: provider),
            null => null,
          };
      final config = DatasourceConfig(
        id: id,
        label: label.isEmpty ? id : label,
        keyPath: _optional(_keyPath),
        search: search == null
            ? null
            : DatasourceSearchConfig(
                provider: search,
                state: _state,
                sort: _sortEnabled ? _sort() : null,
                pagination: _paginationEnabled ? _pagination() : null,
              ),
        create: create == null
            ? null
            : DatasourceCreateConfig(provider: create, insert: _insert),
        read: entity(DatasourceOperation.read),
        update: entity(DatasourceOperation.update),
        delete: entity(DatasourceOperation.delete),
      );
      config.validate();
      return (config: config, error: null);
    } on FormatException catch (error) {
      return (config: null, error: error.message);
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Widget _caption(String text, {Key? key, Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      key: key,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    ),
  );

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    bool enabled = true,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      enabled: enabled,
      keyboardType: number ? TextInputType.number : null,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
      ),
      onChanged: (_) => _change(() {}),
    ),
  );

  Widget _switch(
    String key,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    key: ValueKey(key),
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: (value) => _change(() => onChanged(value)),
  );

  Widget _segments<T extends Object>(
    String key,
    Map<T, String> labels,
    T selected,
    ValueChanged<T> onSelected,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SegmentedButton<T>(
      key: ValueKey(key),
      showSelectedIcon: false,
      segments: [
        for (final MapEntry(:key, :value) in labels.entries)
          ButtonSegment(value: key, label: Text(value)),
      ],
      selected: {selected},
      onSelectionChanged: (selection) =>
          _change(() => onSelected(selection.first)),
    ),
  );

  Future<void> _createProvider(DatasourceOperation operation) async {
    final create = widget.onCreateProvider;
    if (create == null) return;
    final id = await create();
    if (id == null || !mounted) return;
    _change(() => _providers[operation] = id);
  }

  /// Remplit tous les champs du formulaire à partir de [config] (par exemple
  /// après génération via [SuperBackendDatasourceWizardDialog]).
  void applyConfig(DatasourceConfig config) {
    _change(() {
      if (widget.isNew) {
        _id.text = config.id;
      }
      _label.text = config.label;
      _keyPath.text = config.keyPath ?? '';
      for (final operation in DatasourceOperation.values) {
        _providers[operation] = config.providerOf(operation) ?? '';
      }
      _insert = config.create?.insert ?? DatasourceInsert.end;
      final search = config.search;
      _state = search?.state;
      final sort = search?.sort;
      _sortEnabled = sort != null;
      if (sort != null) {
        _sortParam.text = sort.fieldParam;
        _directionParam.text = sort.directionParam ?? '';
        _sortFields.text = sort.fields.join(', ');
        _defaultSort.text = sort.defaultOrder?.field ?? '';
        _defaultDirection =
            sort.defaultOrder?.direction ?? DatasourceSortDirection.asc;
      }
      final pagination = search?.pagination;
      _paginationEnabled = pagination != null;
      if (pagination != null) {
        _mode = pagination.mode;
        _pageSize.text = '${pagination.pageSize}';
        _pageParam.text = pagination.pageParam;
        _sizeParam.text = pagination.sizeParam;
        _firstPage = pagination.firstPage;
        _offsetParam.text = pagination.offsetParam;
        _limitParam.text = pagination.limitParam;
        _cursorParam.text = pagination.cursorParam;
        _nextCursorPath.text = pagination.nextCursorPath ?? '';
        _totalPath.text = pagination.totalPath ?? '';
      }
    });
  }

  Future<void> _openSuperBackendWizard() async {
    final store = widget.store;
    if (store == null) return;
    final config = await SuperBackendDatasourceWizardDialog.show(
      context,
      store: store,
      initialDatasourceId: _id.text.trim(),
      initialLabel: _label.text.trim(),
      initialKeyPath: _keyPath.text.trim().isEmpty ? 'id' : _keyPath.text.trim(),
      saveDatasource: false,
    );
    if (config == null || !mounted) return;
    applyConfig(config);
  }

  String _targetText(DataProvider provider) {
    final target = provider.target;
    final base = target == null
        ? 'Aucun repository de résultats.'
        : 'Résultats : ${target.path}.';
    if (provider is HttpDataProvider) {
      final collection = SuperBackendDatasourceBridge.collectionFromUrl(
        provider.config.request.url,
      );
      if (collection != null) {
        return '$base SuperBackend SQLite : collection « $collection ».';
      }
    }
    return base;
  }

  Widget _providerPicker(DatasourceOperation operation) {
    final providers = _registry?.providers ?? const <DataProvider>[];
    final selected = _providers[operation] ?? '';
    final provider = selected.isEmpty ? null : _registry?.provider(selected);
    final scheme = Theme.of(context).colorScheme;
    final String? note;
    Color? noteColor;
    if (selected.isEmpty) {
      note = null;
    } else if (provider == null) {
      note = 'Provider « $selected » introuvable.';
      noteColor = scheme.error;
    } else if (operation == DatasourceOperation.search &&
        provider.target == null) {
      note =
          'Ce provider n’a pas de repository de résultats : la recherche ne '
          'peut pas écrire ses lignes.';
      noteColor = scheme.error;
    } else {
      note = _targetText(provider);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  key: ValueKey('datasource-provider-${operation.name}'),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '${operation.title} — ${operation.label}',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selected,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Aucun')),
                        for (final candidate in providers)
                          DropdownMenuItem(
                            value: candidate.id,
                            child: Text(
                              '${candidate.label} (${candidate.id})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (provider == null && selected.isNotEmpty)
                          DropdownMenuItem(
                            value: selected,
                            child: Text('$selected (introuvable)'),
                          ),
                      ],
                      onChanged: (value) =>
                          _change(() => _providers[operation] = value ?? ''),
                    ),
                  ),
                ),
              ),
              if (widget.onCreateProvider != null)
                IconButton(
                  key: ValueKey('datasource-new-provider-${operation.name}'),
                  tooltip: 'Nouveau provider…',
                  onPressed: () => unawaited(_createProvider(operation)),
                  icon: const Icon(Icons.add_link),
                ),
            ],
          ),
          if (note != null) _caption(note, color: noteColor),
        ],
      ),
    );
  }

  List<Widget> _sortFieldsSection() => [
    _field(
      'datasource-sort-param',
      _sortParam,
      'Paramètre du champ trié',
      hint: 'sort',
    ),
    _field(
      'datasource-direction-param',
      _directionParam,
      'Paramètre du sens (facultatif)',
      hint: 'order',
      helper: 'Vide : le tri décroissant est envoyé sous la forme -champ.',
    ),
    _field(
      'datasource-sort-fields',
      _sortFields,
      'Champs triables (facultatif)',
      hint: 'nom, ville, creation',
      helper: 'Séparés par des virgules ; vide : tout champ est accepté.',
    ),
    _field(
      'datasource-default-sort',
      _defaultSort,
      'Tri par défaut (facultatif)',
      hint: 'nom',
    ),
    if (_optional(_defaultSort) != null)
      _segments(
        'datasource-default-direction',
        const {
          DatasourceSortDirection.asc: 'Croissant',
          DatasourceSortDirection.desc: 'Décroissant',
        },
        _defaultDirection,
        (value) => _defaultDirection = value,
      ),
  ];

  List<Widget> _paginationSection() => [
    _segments(
      'datasource-pagination-mode',
      const {
        DatasourcePaginationMode.page: 'Page',
        DatasourcePaginationMode.offset: 'Offset',
        DatasourcePaginationMode.cursor: 'Curseur',
      },
      _mode,
      (value) => _mode = value,
    ),
    _field(
      'datasource-page-size',
      _pageSize,
      'Lignes par page',
      helper: '1 à ${DatasourcePagination.maxPageSize}.',
      number: true,
    ),
    ...switch (_mode) {
      DatasourcePaginationMode.page => [
        _field('datasource-page-param', _pageParam, 'Paramètre de la page'),
        _field('datasource-size-param', _sizeParam, 'Paramètre de la taille'),
        _segments(
          'datasource-first-page',
          const {0: 'Première page : 0', 1: 'Première page : 1'},
          _firstPage,
          (value) => _firstPage = value,
        ),
      ],
      DatasourcePaginationMode.offset => [
        _field(
          'datasource-offset-param',
          _offsetParam,
          'Paramètre de la position',
        ),
        _field('datasource-limit-param', _limitParam, 'Paramètre du nombre'),
      ],
      DatasourcePaginationMode.cursor => [
        _field('datasource-cursor-param', _cursorParam, 'Paramètre du curseur'),
        _field('datasource-limit-param', _limitParam, 'Paramètre du nombre'),
        _field(
          'datasource-next-cursor',
          _nextCursorPath,
          'Chemin du curseur suivant dans la réponse',
          hint: 'meta.next',
          helper: 'Vide ou absent sur la dernière page.',
        ),
      ],
    },
    _field(
      'datasource-total-path',
      _totalPath,
      'Chemin du total dans la réponse (facultatif)',
      hint: 'meta.total',
      helper:
          'Sans total, une page complète laisse supposer une page suivante.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final error = _touched ? draft().error : null;
    final hasSearch = _providerOf(DatasourceOperation.search) != null;
    final hasCreate = _providerOf(DatasourceOperation.create) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  'datasource-id',
                  _id,
                  'Identifiant',
                  hint: 'clients',
                  helper:
                      'a-z, 0-9 et _ (32 caractères au plus) ; nom du fichier '
                      'et valeur des actions « Commande de datasource ».',
                  enabled: widget.isNew,
                ),
                _field(
                  'datasource-label',
                  _label,
                  'Libellé',
                  helper: 'Facultatif : l’identifiant par défaut.',
                ),
                _field(
                  'datasource-key-path',
                  _keyPath,
                  'Chemin de la clé des entités',
                  hint: 'id',
                  helper:
                      'Obligatoire avec Create, Read, Update ou Delete : les '
                      'lignes sont retrouvées par cette clé (texte ou entier).',
                ),
                _heading('Opérations'),
                if (widget.store != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('datasource-preconfigure-super-backend'),
                        onPressed: () => unawaited(_openSuperBackendWizard()),
                        icon: const Icon(Icons.storage_outlined, size: 18),
                        label: const Text(
                          'Préconfigurer avec SuperBackend (SQLite local)…',
                        ),
                      ),
                    ),
                  ),
                _caption(
                  'Un provider existant par opération ; au moins une. Read, '
                  'Update et Delete reçoivent l’entité courante : {{ds.key}} '
                  'et {{ds.entity.champ}}.',
                ),
                for (final operation in DatasourceOperation.values)
                  _providerPicker(operation),
                if (hasCreate)
                  _segments(
                    'datasource-insert',
                    const {
                      DatasourceInsert.start: 'Création insérée au début',
                      DatasourceInsert.end: 'Création ajoutée à la fin',
                    },
                    _insert,
                    (value) => _insert = value,
                  ),
                if (hasSearch) ...[
                  _heading('Recherche'),
                  _caption(
                    'Le provider peut lire {{ds.page}}, {{ds.pageSize}}, '
                    '{{ds.offset}}, {{ds.limit}}, {{ds.cursor}}, {{ds.sort}} '
                    'et {{ds.direction}} ; avec « Ajouter automatiquement les '
                    'champs du filtre », le tri et la pagination sont ajoutés '
                    'à la requête.',
                  ),
                  _caption('État de la recherche (facultatif)'),
                  RepositoryBindingFields(
                    keyPrefix: 'datasource-binding-state',
                    binding: _state,
                    store: widget.store,
                    pathHint: 'recherche.page',
                    helper:
                        'Objet qui reçoit page, total, hasNext, hasPrevious, '
                        'sort… pour afficher la pagination.',
                    onChanged: (value) => _change(() => _state = value),
                  ),
                  _switch(
                    'datasource-sort',
                    'Tri',
                    'Ajoute le champ et le sens du tri à la requête.',
                    _sortEnabled,
                    (value) => _sortEnabled = value,
                  ),
                  if (_sortEnabled) ..._sortFieldsSection(),
                  _switch(
                    'datasource-pagination',
                    'Pagination',
                    'Page, offset ou curseur ; sinon une seule page.',
                    _paginationEnabled,
                    (value) => _paginationEnabled = value,
                  ),
                  if (_paginationEnabled) ..._paginationSection(),
                ],
                if (widget.store != null &&
                    (_registry?.providers.isEmpty ?? true))
                  _caption(
                    'Créez d’abord les providers dans le gestionnaire de '
                    'providers.',
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              key: const ValueKey('datasource-form-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
