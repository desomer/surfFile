/// Configuration d'une datasource ([DatasourceConfig]) : regroupement des
/// providers Search / Create / Read / Update / Delete d'une même notion
/// métier (« clients », « commandes »…).
///
/// Une datasource ne possède aucun repository : elle référence un provider
/// existant par opération ([DatasourceOperation]), chaque provider gardant
/// son filtre, sa cible et ses indicateurs. Elle ajoute :
///
/// * le tri ([DatasourceSort]) et la pagination (`DatasourcePagination`) de
///   la recherche, ainsi qu'un état observable écrit dans
///   [DatasourceSearchConfig.state] (`DatasourcePageState`) ;
/// * l'identité des entités ([DatasourceConfig.keyPath]) qui permet de
///   mettre à jour localement la liste et le détail après Create / Update /
///   Delete, sans relancer la recherche.
///
/// Persistée dans `<dossier du store>/datasources/<id>.json` ; les
/// comportements ne stockent que son identifiant et la commande
/// ([DatasourceCommand]) à lancer.
library;

import 'package:flutter/foundation.dart';

import '../json_text_binding.dart';
import '../providers/data_provider.dart';
import 'datasource_pagination.dart';

export 'datasource_pagination.dart';

final _datasourceIdPattern = RegExp(r'^[a-z0-9_]{1,32}$');

/// Longueur maximale du libellé d'une datasource.
const datasourceLabelMaxLength = 80;

/// Nombre maximal de champs triables déclarés.
const datasourceMaxSortFields = 50;

/// Vrai si [id] est un identifiant de datasource valide (minuscules,
/// chiffres et `_`, 1 à 32 caractères).
bool isValidDatasourceId(String id) => _datasourceIdPattern.hasMatch(id);

/// Opération d'une datasource, servie par un provider.
enum DatasourceOperation {
  /// Recherche paginée et triée d'une liste.
  search('Search', 'Rechercher'),

  /// Création d'une entité.
  create('Create', 'Créer'),

  /// Lecture d'une entité.
  read('Read', 'Lire'),

  /// Mise à jour d'une entité.
  update('Update', 'Mettre à jour'),

  /// Suppression d'une entité.
  delete('Delete', 'Supprimer');

  const DatasourceOperation(this.title, this.label);

  /// Nom court (« Search », « Create »…).
  final String title;

  /// Libellé d'action en français.
  final String label;

  /// Vrai si l'opération modifie les données distantes (Create, Update,
  /// Delete).
  bool get isMutation => this == create || this == update || this == delete;
}

/// Commande lancée par un comportement sur une datasource.
enum DatasourceCommand {
  /// Recherche depuis la première page (tri conservé).
  search(DatasourceOperation.search, 'Rechercher'),

  /// Relance la page courante.
  refresh(DatasourceOperation.search, 'Rafraîchir la page'),

  /// Première page.
  firstPage(DatasourceOperation.search, 'Première page'),

  /// Page précédente.
  previousPage(DatasourceOperation.search, 'Page précédente'),

  /// Page suivante.
  nextPage(DatasourceOperation.search, 'Page suivante'),

  /// Ajoute la page suivante à la liste (« Charger plus »).
  loadMore(DatasourceOperation.search, 'Charger plus'),

  /// Trie sur un champ (inverse la direction si le champ ne change pas).
  sort(DatasourceOperation.search, 'Trier'),

  /// Crée une entité depuis le filtre du provider Create.
  create(DatasourceOperation.create, 'Créer'),

  /// Lit l'entité courante.
  read(DatasourceOperation.read, 'Lire'),

  /// Met à jour l'entité courante.
  update(DatasourceOperation.update, 'Mettre à jour'),

  /// Supprime l'entité courante.
  delete(DatasourceOperation.delete, 'Supprimer');

  const DatasourceCommand(this.operation, this.label);

  /// Opération (provider) nécessaire.
  final DatasourceOperation operation;

  /// Libellé affiché dans l'éditeur.
  final String label;

  /// Vrai si la commande change de page (pagination requise).
  bool get isPaging =>
      this == nextPage ||
      this == previousPage ||
      this == firstPage ||
      this == loadMore;

  /// Vrai si la commande agit sur une entité (clé requise).
  bool get isEntity =>
      operation == DatasourceOperation.read ||
      operation == DatasourceOperation.update ||
      operation == DatasourceOperation.delete;
}

/// Sens d'un tri.
enum DatasourceSortDirection {
  /// Croissant.
  asc,

  /// Décroissant.
  desc;

  /// Sens opposé.
  DatasourceSortDirection get reversed => this == asc ? desc : asc;

  /// Sens nommé [name], ou `null`.
  static DatasourceSortDirection? byName(Object? name) =>
      values.where((value) => value.name == name).firstOrNull;
}

/// Champ et sens d'un tri.
@immutable
class DatasourceSortOrder {
  /// Crée un tri sur [field].
  const DatasourceSortOrder(
    this.field, [
    this.direction = DatasourceSortDirection.asc,
  ]);

  /// Lecture stricte `{"field": "nom", "direction": "asc"}` (sens facultatif).
  factory DatasourceSortOrder.fromJson(Object? json) {
    if (json is! Map ||
        json.keys.any((key) => key != 'field' && key != 'direction')) {
      throw const FormatException('Tri invalide : {field, direction}.');
    }
    final field = json['field'];
    final direction = json.containsKey('direction')
        ? DatasourceSortDirection.byName(json['direction'])
        : DatasourceSortDirection.asc;
    if (field is! String || direction == null) {
      throw const FormatException(
        'Tri invalide : champ texte et sens « asc » ou « desc » attendus.',
      );
    }
    final result = DatasourceSortOrder(field, direction);
    result.validate();
    return result;
  }

  /// Champ trié.
  final String field;

  /// Sens du tri.
  final DatasourceSortDirection direction;

  /// Vérifie le nom du champ.
  void validate() {
    if (!isValidDatasourceParameter(field)) {
      throw FormatException(
        'Champ de tri « $field » invalide (lettres, chiffres, _, . et -).',
      );
    }
  }

  /// Forme JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {'field': field, 'direction': direction.name};
  }

  /// Forme compacte : le sens croissant est omis.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'field': field,
      if (direction != DatasourceSortDirection.asc) 'direction': direction.name,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatasourceSortOrder &&
      field == other.field &&
      direction == other.direction;

  @override
  int get hashCode => Object.hash(field, direction);
}

/// Tri de la recherche : paramètres ajoutés à la requête et champs permis.
@immutable
class DatasourceSort {
  /// Crée un tri ; sans [directionParam], le tri décroissant est encodé
  /// `-champ` dans [fieldParam].
  DatasourceSort({
    this.fieldParam = 'sort',
    this.directionParam,
    List<String> fields = const [],
    this.defaultOrder,
  }) : fields = List<String>.unmodifiable(fields);

  /// Lecture stricte : `fieldParam`, `directionParam`, `fields` et `default`
  /// facultatifs.
  factory DatasourceSort.fromJson(Object? json) {
    const keys = {'fieldParam', 'directionParam', 'fields', 'default'};
    if (json is! Map || json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException(
        'Tri invalide : objet attendu, clés inconnues refusées.',
      );
    }
    final fieldParam = json['fieldParam'] ?? 'sort';
    final directionParam = json['directionParam'];
    final fields = json['fields'] ?? const <Object?>[];
    if (fieldParam is! String ||
        (directionParam != null && directionParam is! String) ||
        fields is! List ||
        fields.any((field) => field is! String)) {
      throw const FormatException(
        'Tri invalide : paramètres textes et liste de champs attendus.',
      );
    }
    final result = DatasourceSort(
      fieldParam: fieldParam,
      directionParam: directionParam as String?,
      fields: fields.cast<String>(),
      defaultOrder: json['default'] == null
          ? null
          : DatasourceSortOrder.fromJson(json['default']),
    );
    result.validate();
    return result;
  }

  /// Paramètre qui reçoit le champ trié.
  final String fieldParam;

  /// Paramètre qui reçoit `asc` ou `desc`, ou `null` pour le préfixe `-`.
  final String? directionParam;

  /// Champs triables ; vide pour accepter tout champ.
  final List<String> fields;

  /// Tri appliqué par défaut, ou `null` (aucun paramètre de tri).
  final DatasourceSortOrder? defaultOrder;

  /// Noms des paramètres ajoutés à la requête.
  List<String> get parameterNames => [fieldParam, ?directionParam];

  /// Vrai si [field] peut être trié.
  bool allows(String field) =>
      isValidDatasourceParameter(field) &&
      (fields.isEmpty || fields.contains(field));

  /// Vérifie les paramètres, les champs (uniques) et le tri par défaut.
  void validate() {
    for (final name in parameterNames) {
      if (!isValidDatasourceParameter(name)) {
        throw FormatException('Tri : paramètre « $name » invalide.');
      }
    }
    if (fieldParam == directionParam) {
      throw const FormatException(
        'Tri : le champ et le sens doivent utiliser des paramètres distincts.',
      );
    }
    if (fields.length > datasourceMaxSortFields ||
        fields.toSet().length != fields.length) {
      throw const FormatException(
        'Tri : $datasourceMaxSortFields champs distincts au plus.',
      );
    }
    for (final field in fields) {
      DatasourceSortOrder(field).validate();
    }
    final order = defaultOrder;
    if (order != null) {
      order.validate();
      if (!allows(order.field)) {
        throw FormatException(
          'Tri : le champ par défaut « ${order.field} » n’est pas triable.',
        );
      }
    }
  }

  /// Paramètres de requête du tri [order].
  Map<String, Object?> parametersFor(DatasourceSortOrder order) {
    final descending = order.direction == DatasourceSortDirection.desc;
    final direction = directionParam;
    if (direction == null) {
      return {fieldParam: descending ? '-${order.field}' : order.field};
    }
    return {fieldParam: order.field, direction: order.direction.name};
  }

  /// Copie modifiée ; les `clear...` retirent la valeur facultative.
  DatasourceSort copyWith({
    String? fieldParam,
    String? directionParam,
    bool clearDirectionParam = false,
    List<String>? fields,
    DatasourceSortOrder? defaultOrder,
    bool clearDefaultOrder = false,
  }) => DatasourceSort(
    fieldParam: fieldParam ?? this.fieldParam,
    directionParam: clearDirectionParam
        ? null
        : (directionParam ?? this.directionParam),
    fields: fields ?? this.fields,
    defaultOrder: clearDefaultOrder
        ? null
        : (defaultOrder ?? this.defaultOrder),
  );

  /// Forme JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {
      'fieldParam': fieldParam,
      'directionParam': ?directionParam,
      'fields': fields,
      'default': ?defaultOrder?.toJson(),
    };
  }

  /// Forme compacte : les valeurs par défaut sont omises.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      if (fieldParam != 'sort') 'fieldParam': fieldParam,
      'directionParam': ?directionParam,
      if (fields.isNotEmpty) 'fields': fields,
      'default': ?defaultOrder?.toCompactJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatasourceSort &&
      fieldParam == other.fieldParam &&
      directionParam == other.directionParam &&
      listEquals(fields, other.fields) &&
      defaultOrder == other.defaultOrder;

  @override
  int get hashCode => Object.hash(
    fieldParam,
    directionParam,
    Object.hashAll(fields),
    defaultOrder,
  );
}

void _validateProvider(DatasourceOperation operation, String provider) {
  if (!isValidDataProviderId(provider)) {
    throw FormatException(
      '${operation.title} : identifiant de provider « $provider » invalide.',
    );
  }
}

String _readProvider(
  DatasourceOperation operation,
  Object? json,
  Set<String> keys,
) {
  if (json is! Map || json.keys.any((key) => !keys.contains(key))) {
    throw FormatException(
      '${operation.title} invalide : objet attendu, clés inconnues refusées.',
    );
  }
  final provider = json['provider'];
  if (provider is! String) {
    throw FormatException('${operation.title} : provider obligatoire.');
  }
  return provider;
}

/// Opération Search : provider, état, tri et pagination.
@immutable
class DatasourceSearchConfig {
  /// Crée la recherche servie par [provider].
  const DatasourceSearchConfig({
    required this.provider,
    this.state,
    this.sort,
    this.pagination,
  });

  /// Lecture stricte `{provider, state?, sort?, pagination?}`.
  factory DatasourceSearchConfig.fromJson(Object? json) {
    final provider = _readProvider(DatasourceOperation.search, json, const {
      'provider',
      'state',
      'sort',
      'pagination',
    });
    final map = json as Map;
    final result = DatasourceSearchConfig(
      provider: provider,
      state: map['state'] == null
          ? null
          : JsonTextBinding.fromJson(map['state']),
      sort: map['sort'] == null ? null : DatasourceSort.fromJson(map['sort']),
      pagination: map['pagination'] == null
          ? null
          : DatasourcePagination.fromJson(map['pagination']),
    );
    result.validate();
    return result;
  }

  /// Provider de recherche ; sa cible reçoit la page de lignes.
  final String provider;

  /// Objet qui reçoit l'état de pagination et de tri, ou `null`.
  final JsonTextBinding? state;

  /// Tri, ou `null` (aucun paramètre de tri).
  final DatasourceSort? sort;

  /// Pagination, ou `null` (une seule page).
  final DatasourcePagination? pagination;

  /// Vérifie le provider, l'état (liaison concrète, non calculée) et les
  /// paramètres de tri et de pagination (noms distincts).
  void validate() {
    _validateProvider(DatasourceOperation.search, provider);
    final binding = state;
    if (binding != null) {
      try {
        binding.validateResolved();
        if (JsonAttributePath(binding.path).calculated != null) {
          throw const FormatException('un attribut calculé est interdit.');
        }
      } on FormatException catch (error) {
        throw FormatException('État de la recherche : ${error.message}');
      }
    }
    sort?.validate();
    pagination?.validate();
    final names = [...?sort?.parameterNames, ...?pagination?.parameterNames];
    if (names.toSet().length != names.length) {
      throw const FormatException(
        'Search : le tri et la pagination doivent utiliser des paramètres '
        'distincts.',
      );
    }
  }

  /// Copie modifiée ; les `clear...` retirent la valeur facultative.
  DatasourceSearchConfig copyWith({
    String? provider,
    JsonTextBinding? state,
    bool clearState = false,
    DatasourceSort? sort,
    bool clearSort = false,
    DatasourcePagination? pagination,
    bool clearPagination = false,
  }) => DatasourceSearchConfig(
    provider: provider ?? this.provider,
    state: clearState ? null : (state ?? this.state),
    sort: clearSort ? null : (sort ?? this.sort),
    pagination: clearPagination ? null : (pagination ?? this.pagination),
  );

  /// Forme JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {
      'provider': provider,
      'state': ?state?.toJson(),
      'sort': ?sort?.toJson(),
      'pagination': ?pagination?.toJson(),
    };
  }

  /// Forme compacte.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'provider': provider,
      'state': ?state?.toCompactJson(),
      'sort': ?sort?.toCompactJson(),
      'pagination': ?pagination?.toCompactJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatasourceSearchConfig &&
      provider == other.provider &&
      state == other.state &&
      sort == other.sort &&
      pagination == other.pagination;

  @override
  int get hashCode => Object.hash(provider, state, sort, pagination);
}

/// Position d'insertion d'une entité créée dans la liste.
enum DatasourceInsert {
  /// En tête de liste.
  start,

  /// En fin de liste.
  end,
}

/// Opération Create : provider et position d'insertion.
@immutable
class DatasourceCreateConfig {
  /// Crée l'opération servie par [provider].
  const DatasourceCreateConfig({
    required this.provider,
    this.insert = DatasourceInsert.end,
  });

  /// Lecture stricte `{provider, insert?}`.
  factory DatasourceCreateConfig.fromJson(Object? json) {
    final provider = _readProvider(DatasourceOperation.create, json, const {
      'provider',
      'insert',
    });
    final insertName = (json as Map)['insert'] ?? DatasourceInsert.end.name;
    final insert = DatasourceInsert.values
        .where((value) => value.name == insertName)
        .firstOrNull;
    if (insert == null) {
      throw const FormatException('Create : insert vaut « start » ou « end ».');
    }
    final result = DatasourceCreateConfig(provider: provider, insert: insert);
    result.validate();
    return result;
  }

  /// Provider de création ; son filtre porte le formulaire de saisie.
  final String provider;

  /// Position de l'entité créée dans la liste.
  final DatasourceInsert insert;

  /// Vérifie le provider.
  void validate() => _validateProvider(DatasourceOperation.create, provider);

  /// Copie modifiée.
  DatasourceCreateConfig copyWith({
    String? provider,
    DatasourceInsert? insert,
  }) => DatasourceCreateConfig(
    provider: provider ?? this.provider,
    insert: insert ?? this.insert,
  );

  /// Forme JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {'provider': provider, 'insert': insert.name};
  }

  /// Forme compacte : l'insertion en fin est omise.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'provider': provider,
      if (insert != DatasourceInsert.end) 'insert': insert.name,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatasourceCreateConfig &&
      provider == other.provider &&
      insert == other.insert;

  @override
  int get hashCode => Object.hash(provider, insert);
}

/// Opération Read, Update ou Delete : provider qui agit sur l'entité
/// courante (contexte `{{ds.key}}` et `{{ds.entity}}`).
@immutable
class DatasourceEntityConfig {
  /// Crée l'opération servie par [provider].
  const DatasourceEntityConfig({required this.provider});

  /// Lecture stricte `{provider}` pour [operation].
  factory DatasourceEntityConfig.fromJson(
    DatasourceOperation operation,
    Object? json,
  ) {
    final provider = _readProvider(operation, json, const {'provider'});
    _validateProvider(operation, provider);
    return DatasourceEntityConfig(provider: provider);
  }

  /// Provider de l'opération.
  final String provider;

  /// Vérifie le provider pour [operation].
  void validate(DatasourceOperation operation) =>
      _validateProvider(operation, provider);

  /// Copie modifiée.
  DatasourceEntityConfig copyWith({String? provider}) =>
      DatasourceEntityConfig(provider: provider ?? this.provider);

  /// Forme JSON complète.
  Map<String, Object?> toJson() => {'provider': provider};

  /// Forme compacte (identique).
  Map<String, Object?> toCompactJson() => toJson();

  @override
  bool operator ==(Object other) =>
      other is DatasourceEntityConfig && provider == other.provider;

  @override
  int get hashCode => provider.hashCode;
}

/// Datasource : providers des opérations d'une notion métier, identité des
/// entités, tri et pagination de la recherche.
@immutable
class DatasourceConfig {
  /// Crée une datasource ; au moins une opération est requise (voir
  /// [validate]).
  const DatasourceConfig({
    required this.id,
    required this.label,
    this.keyPath,
    this.search,
    this.create,
    this.read,
    this.update,
    this.delete,
  });

  /// Lecture stricte d'un fichier de datasource. Lève une
  /// [FormatException] si la structure ou une valeur est invalide.
  factory DatasourceConfig.fromJson(Object? json) {
    const keys = {
      'id',
      'label',
      'keyPath',
      'search',
      'create',
      'read',
      'update',
      'delete',
    };
    if (json is! Map || json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException(
        'Datasource invalide : objet attendu, clés inconnues refusées.',
      );
    }
    final id = json['id'];
    final label = json['label'] ?? id;
    final keyPath = json['keyPath'];
    if (id is! String ||
        label is! String ||
        (keyPath != null && keyPath is! String)) {
      throw const FormatException(
        'Datasource invalide : id obligatoire, textes attendus.',
      );
    }
    DatasourceEntityConfig? entity(DatasourceOperation operation) =>
        json[operation.name] == null
        ? null
        : DatasourceEntityConfig.fromJson(operation, json[operation.name]);
    final result = DatasourceConfig(
      id: id,
      label: label,
      keyPath: keyPath as String?,
      search: json['search'] == null
          ? null
          : DatasourceSearchConfig.fromJson(json['search']),
      create: json['create'] == null
          ? null
          : DatasourceCreateConfig.fromJson(json['create']),
      read: entity(DatasourceOperation.read),
      update: entity(DatasourceOperation.update),
      delete: entity(DatasourceOperation.delete),
    );
    result.validate();
    return result;
  }

  /// Identifiant unique, identique au nom du fichier.
  final String id;

  /// Libellé affiché dans l'éditeur.
  final String label;

  /// Chemin de l'identifiant dans une ligne (`id`, `meta.uuid`), ou `null`
  /// si seule la recherche est configurée.
  final String? keyPath;

  /// Recherche, ou `null`.
  final DatasourceSearchConfig? search;

  /// Création, ou `null`.
  final DatasourceCreateConfig? create;

  /// Lecture, ou `null`.
  final DatasourceEntityConfig? read;

  /// Mise à jour, ou `null`.
  final DatasourceEntityConfig? update;

  /// Suppression, ou `null`.
  final DatasourceEntityConfig? delete;

  /// Provider de [operation], ou `null` si elle n'est pas configurée.
  String? providerOf(DatasourceOperation operation) => switch (operation) {
    DatasourceOperation.search => search?.provider,
    DatasourceOperation.create => create?.provider,
    DatasourceOperation.read => read?.provider,
    DatasourceOperation.update => update?.provider,
    DatasourceOperation.delete => delete?.provider,
  };

  /// Opérations configurées, dans l'ordre Search, Create, Read, Update,
  /// Delete.
  List<DatasourceOperation> get operations => [
    for (final operation in DatasourceOperation.values)
      if (providerOf(operation) != null) operation,
  ];

  /// Providers référencés (sans doublon).
  Set<String> get providerIds => {
    for (final operation in DatasourceOperation.values) ?providerOf(operation),
  };

  /// Vrai si la datasource référence le provider [providerId].
  bool usesProvider(String providerId) => providerIds.contains(providerId);

  /// Vrai si l'état de la recherche est écrit dans [repositoryId].
  bool usesRepository(String repositoryId) =>
      search?.state?.repositoryId == repositoryId;

  /// Vrai si [command] peut être lancée : opération configurée, pagination
  /// pour changer de page et tri pour trier.
  bool supports(DatasourceCommand command) {
    if (providerOf(command.operation) == null) return false;
    if (command.isPaging) return search?.pagination != null;
    if (command == DatasourceCommand.sort) return search?.sort != null;
    return true;
  }

  /// Commandes disponibles (voir [supports]).
  List<DatasourceCommand> get commands => [
    for (final command in DatasourceCommand.values)
      if (supports(command)) command,
  ];

  /// Vérifie l'identifiant, le libellé, les opérations (au moins une) et le
  /// chemin de la clé (obligatoire hors recherche seule).
  ///
  /// Lève une [FormatException] avec un message affichable sinon.
  void validate() {
    if (!isValidDatasourceId(id)) {
      throw FormatException(
        'Identifiant de datasource invalide « $id » : minuscules, chiffres et '
        '_ (1 à 32 caractères).',
      );
    }
    if (label.trim().isEmpty || label.length > datasourceLabelMaxLength) {
      throw const FormatException(
        'Le libellé de la datasource doit contenir de 1 à '
        '$datasourceLabelMaxLength caractères.',
      );
    }
    if (operations.isEmpty) {
      throw const FormatException(
        'Une datasource doit configurer au moins une opération.',
      );
    }
    search?.validate();
    create?.validate();
    read?.validate(DatasourceOperation.read);
    update?.validate(DatasourceOperation.update);
    delete?.validate(DatasourceOperation.delete);
    final key = keyPath;
    if (key == null) {
      if (operations.any(
        (operation) => operation != DatasourceOperation.search,
      )) {
        throw const FormatException(
          'Le chemin de la clé est obligatoire dès qu’une opération autre que '
          'Search est configurée.',
        );
      }
    } else {
      validateDatasourcePath('Chemin de la clé', key);
    }
  }

  /// Copie modifiée ; les `clear...` retirent la valeur facultative.
  DatasourceConfig copyWith({
    String? id,
    String? label,
    String? keyPath,
    bool clearKeyPath = false,
    DatasourceSearchConfig? search,
    bool clearSearch = false,
    DatasourceCreateConfig? create,
    bool clearCreate = false,
    DatasourceEntityConfig? read,
    bool clearRead = false,
    DatasourceEntityConfig? update,
    bool clearUpdate = false,
    DatasourceEntityConfig? delete,
    bool clearDelete = false,
  }) => DatasourceConfig(
    id: id ?? this.id,
    label: label ?? this.label,
    keyPath: clearKeyPath ? null : (keyPath ?? this.keyPath),
    search: clearSearch ? null : (search ?? this.search),
    create: clearCreate ? null : (create ?? this.create),
    read: clearRead ? null : (read ?? this.read),
    update: clearUpdate ? null : (update ?? this.update),
    delete: clearDelete ? null : (delete ?? this.delete),
  );

  /// Forme JSON complète, écrite dans `datasources/<id>.json`.
  Map<String, Object?> toJson() {
    validate();
    return {
      'id': id,
      'label': label,
      'keyPath': ?keyPath,
      'search': ?search?.toJson(),
      'create': ?create?.toJson(),
      'read': ?read?.toJson(),
      'update': ?update?.toJson(),
      'delete': ?delete?.toJson(),
    };
  }

  /// Forme compacte : le libellé égal à l'identifiant et les valeurs par
  /// défaut sont omis.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'id': id,
      if (label != id) 'label': label,
      'keyPath': ?keyPath,
      'search': ?search?.toCompactJson(),
      'create': ?create?.toCompactJson(),
      'read': ?read?.toCompactJson(),
      'update': ?update?.toCompactJson(),
      'delete': ?delete?.toCompactJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatasourceConfig &&
      id == other.id &&
      label == other.label &&
      keyPath == other.keyPath &&
      search == other.search &&
      create == other.create &&
      read == other.read &&
      update == other.update &&
      delete == other.delete;

  @override
  int get hashCode =>
      Object.hash(id, label, keyPath, search, create, read, update, delete);
}
