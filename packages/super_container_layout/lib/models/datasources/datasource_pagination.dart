/// Pagination de la recherche d'une datasource ([DatasourcePagination]).
///
/// Trois modes ([DatasourcePaginationMode]) nomment les paramètres ajoutés
/// automatiquement à la requête du provider Search :
///
/// * `page` : numéro de page ([DatasourcePagination.pageParam], à partir de
///   [DatasourcePagination.firstPage]) et taille
///   ([DatasourcePagination.sizeParam]) ;
/// * `offset` : position de la première ligne
///   ([DatasourcePagination.offsetParam]) et nombre de lignes
///   ([DatasourcePagination.limitParam]) ;
/// * `cursor` : curseur opaque ([DatasourcePagination.cursorParam]) lu dans
///   la réponse précédente ([DatasourcePagination.nextCursorPath]) et nombre
///   de lignes.
///
/// [DatasourcePagination.totalPath] lit facultativement le nombre total de
/// lignes dans la réponse brute.
library;

import 'package:flutter/foundation.dart';

import '../json_text_binding.dart';

final _parameterPattern = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');

/// Vrai si [name] est un nom de paramètre de requête accepté (lettres,
/// chiffres, `_`, `.` et `-`, 1 à 64 caractères).
bool isValidDatasourceParameter(String name) =>
    _parameterPattern.hasMatch(name);

/// Vérifie qu'un chemin lu dans une ligne ou dans la réponse brute est
/// concret, non vide et non calculé ; [name] préfixe le message d'erreur.
void validateDatasourcePath(String name, String path) {
  try {
    if (path.trim().isEmpty) throw const FormatException('chemin vide.');
    final parsed = JsonAttributePath(path)..requireResolved();
    if (parsed.calculated != null) {
      throw const FormatException('un attribut calculé (@) est interdit.');
    }
  } on FormatException catch (error) {
    throw FormatException('$name : ${error.message}');
  }
}

/// Mode de pagination d'une recherche.
enum DatasourcePaginationMode {
  /// Numéro de page et taille.
  page,

  /// Position (offset) et nombre de lignes (limit).
  offset,

  /// Curseur opaque retourné par la page précédente.
  cursor,
}

/// Paramètres de pagination de la recherche d'une datasource.
@immutable
class DatasourcePagination {
  /// Crée une pagination ; seuls les paramètres du [mode] choisi sont
  /// utilisés et sérialisés.
  const DatasourcePagination({
    this.mode = DatasourcePaginationMode.page,
    this.pageSize = defaultPageSize,
    this.pageParam = 'page',
    this.sizeParam = 'size',
    this.firstPage = 1,
    this.offsetParam = 'offset',
    this.limitParam = 'limit',
    this.cursorParam = 'cursor',
    this.nextCursorPath,
    this.totalPath,
  });

  /// Lecture stricte : `mode` (défaut `page`), `pageSize`, `totalPath` et les
  /// clés propres au mode ; les autres clés sont refusées.
  factory DatasourcePagination.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Pagination invalide : objet attendu.');
    }
    final modeName = json['mode'] ?? DatasourcePaginationMode.page.name;
    final mode = DatasourcePaginationMode.values
        .where((value) => value.name == modeName)
        .firstOrNull;
    if (mode == null) {
      throw const FormatException(
        'Pagination : mode « page », « offset » ou « cursor » attendu.',
      );
    }
    final allowed = {'mode', 'pageSize', 'totalPath', ..._keysOf(mode)};
    final unknown = json.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Pagination « ${mode.name} » : clé inconnue « ${unknown.first} ».',
      );
    }
    const defaults = DatasourcePagination();
    T read<T>(String key, T fallback) {
      final value = json[key] ?? fallback;
      if (value is! T) {
        throw FormatException('Pagination : « $key » a un type invalide.');
      }
      return value;
    }

    final result = DatasourcePagination(
      mode: mode,
      pageSize: read('pageSize', defaults.pageSize),
      pageParam: read('pageParam', defaults.pageParam),
      sizeParam: read('sizeParam', defaults.sizeParam),
      firstPage: read('firstPage', defaults.firstPage),
      offsetParam: read('offsetParam', defaults.offsetParam),
      limitParam: read('limitParam', defaults.limitParam),
      cursorParam: read('cursorParam', defaults.cursorParam),
      nextCursorPath: read<String?>('nextCursorPath', null),
      totalPath: read<String?>('totalPath', null),
    );
    result.validate();
    return result;
  }

  static Set<String> _keysOf(DatasourcePaginationMode mode) => switch (mode) {
    DatasourcePaginationMode.page => {'pageParam', 'sizeParam', 'firstPage'},
    DatasourcePaginationMode.offset => {'offsetParam', 'limitParam'},
    DatasourcePaginationMode.cursor => {
      'cursorParam',
      'limitParam',
      'nextCursorPath',
    },
  };

  /// Taille de page par défaut.
  static const int defaultPageSize = 20;

  /// Taille de page maximale.
  static const int maxPageSize = 1000;

  /// Mode de pagination.
  final DatasourcePaginationMode mode;

  /// Nombre de lignes par page (1 à [maxPageSize]).
  final int pageSize;

  /// Paramètre du numéro de page (mode `page`).
  final String pageParam;

  /// Paramètre de la taille de page (mode `page`).
  final String sizeParam;

  /// Numéro de la première page : 0 ou 1 (mode `page`).
  final int firstPage;

  /// Paramètre de la position de la première ligne (mode `offset`).
  final String offsetParam;

  /// Paramètre du nombre de lignes (modes `offset` et `cursor`).
  final String limitParam;

  /// Paramètre du curseur (mode `cursor`) ; absent pour la première page.
  final String cursorParam;

  /// Chemin du curseur suivant dans la réponse brute (obligatoire en mode
  /// `cursor`) ; vide ou absent sur la dernière page.
  final String? nextCursorPath;

  /// Chemin du nombre total de lignes dans la réponse brute, ou `null`.
  final String? totalPath;

  /// Noms des paramètres ajoutés à la requête dans le [mode] courant.
  List<String> get parameterNames => switch (mode) {
    DatasourcePaginationMode.page => [pageParam, sizeParam],
    DatasourcePaginationMode.offset => [offsetParam, limitParam],
    DatasourcePaginationMode.cursor => [cursorParam, limitParam],
  };

  /// Vérifie la taille de page, les noms de paramètres (distincts), la
  /// première page et les chemins de la réponse.
  ///
  /// Lève une [FormatException] avec un message affichable sinon.
  void validate() {
    if (pageSize < 1 || pageSize > maxPageSize) {
      throw const FormatException(
        'Pagination : la taille de page doit être comprise entre 1 et '
        '$maxPageSize.',
      );
    }
    final names = parameterNames;
    for (final name in names) {
      if (!isValidDatasourceParameter(name)) {
        throw FormatException(
          'Pagination : paramètre « $name » invalide (lettres, chiffres, _, . '
          'et -, 64 caractères au plus).',
        );
      }
    }
    if (names.toSet().length != names.length) {
      throw const FormatException(
        'Pagination : les paramètres doivent porter des noms distincts.',
      );
    }
    if (mode == DatasourcePaginationMode.page &&
        firstPage != 0 &&
        firstPage != 1) {
      throw const FormatException(
        'Pagination : la première page doit valoir 0 ou 1.',
      );
    }
    final cursorPath = nextCursorPath;
    if (mode == DatasourcePaginationMode.cursor) {
      if (cursorPath == null) {
        throw const FormatException(
          'Pagination par curseur : le chemin du curseur suivant est '
          'obligatoire.',
        );
      }
      validateDatasourcePath('Curseur suivant', cursorPath);
    }
    final total = totalPath;
    if (total != null) validateDatasourcePath('Total', total);
  }

  /// Valeur du paramètre de page pour la page d'indice [pageIndex] (0 pour
  /// la première) : numéro à partir de [firstPage] en mode `page`, numéro à
  /// partir de 1 sinon.
  int pageNumber(int pageIndex) => mode == DatasourcePaginationMode.page
      ? firstPage + pageIndex
      : pageIndex + 1;

  /// Paramètres de la page d'indice [pageIndex] (0 pour la première) ;
  /// [cursor] est le curseur de cette page en mode `cursor` (`null` pour la
  /// première).
  Map<String, Object?> parametersFor(int pageIndex, {String? cursor}) =>
      switch (mode) {
        DatasourcePaginationMode.page => {
          pageParam: firstPage + pageIndex,
          sizeParam: pageSize,
        },
        DatasourcePaginationMode.offset => {
          offsetParam: pageIndex * pageSize,
          limitParam: pageSize,
        },
        DatasourcePaginationMode.cursor => {
          cursorParam: ?cursor,
          limitParam: pageSize,
        },
      };

  /// Copie modifiée ; les `clear...` retirent le chemin facultatif.
  DatasourcePagination copyWith({
    DatasourcePaginationMode? mode,
    int? pageSize,
    String? pageParam,
    String? sizeParam,
    int? firstPage,
    String? offsetParam,
    String? limitParam,
    String? cursorParam,
    String? nextCursorPath,
    bool clearNextCursorPath = false,
    String? totalPath,
    bool clearTotalPath = false,
  }) => DatasourcePagination(
    mode: mode ?? this.mode,
    pageSize: pageSize ?? this.pageSize,
    pageParam: pageParam ?? this.pageParam,
    sizeParam: sizeParam ?? this.sizeParam,
    firstPage: firstPage ?? this.firstPage,
    offsetParam: offsetParam ?? this.offsetParam,
    limitParam: limitParam ?? this.limitParam,
    cursorParam: cursorParam ?? this.cursorParam,
    nextCursorPath: clearNextCursorPath
        ? null
        : (nextCursorPath ?? this.nextCursorPath),
    totalPath: clearTotalPath ? null : (totalPath ?? this.totalPath),
  );

  /// Forme JSON complète : `mode`, `pageSize`, les paramètres du mode et les
  /// chemins définis.
  Map<String, Object?> toJson() {
    validate();
    return {
      'mode': mode.name,
      'pageSize': pageSize,
      ...switch (mode) {
        DatasourcePaginationMode.page => {
          'pageParam': pageParam,
          'sizeParam': sizeParam,
          'firstPage': firstPage,
        },
        DatasourcePaginationMode.offset => {
          'offsetParam': offsetParam,
          'limitParam': limitParam,
        },
        DatasourcePaginationMode.cursor => {
          'cursorParam': cursorParam,
          'limitParam': limitParam,
          'nextCursorPath': nextCursorPath,
        },
      },
      'totalPath': ?totalPath,
    };
  }

  /// Forme compacte : les valeurs par défaut sont omises.
  Map<String, Object?> toCompactJson() {
    const defaults = DatasourcePagination();
    return {
      for (final entry in toJson().entries)
        if (switch (entry.key) {
          'mode' => mode != defaults.mode,
          'pageSize' => pageSize != defaults.pageSize,
          'pageParam' => pageParam != defaults.pageParam,
          'sizeParam' => sizeParam != defaults.sizeParam,
          'firstPage' => firstPage != defaults.firstPage,
          'offsetParam' => offsetParam != defaults.offsetParam,
          'limitParam' => limitParam != defaults.limitParam,
          'cursorParam' => cursorParam != defaults.cursorParam,
          _ => true,
        })
          entry.key: entry.value,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatasourcePagination &&
      mode == other.mode &&
      pageSize == other.pageSize &&
      pageParam == other.pageParam &&
      sizeParam == other.sizeParam &&
      firstPage == other.firstPage &&
      offsetParam == other.offsetParam &&
      limitParam == other.limitParam &&
      cursorParam == other.cursorParam &&
      nextCursorPath == other.nextCursorPath &&
      totalPath == other.totalPath;

  @override
  int get hashCode => Object.hash(
    mode,
    pageSize,
    pageParam,
    sizeParam,
    firstPage,
    offsetParam,
    limitParam,
    cursorParam,
    nextCursorPath,
    totalPath,
  );
}
