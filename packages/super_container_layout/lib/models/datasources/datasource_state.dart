/// État d'une datasource : position de pagination et de tri
/// ([DatasourcePageState], écrit dans l'objet `state` de la recherche) et
/// état observable de la dernière commande ([DatasourceStatus]).
///
/// L'objet `state` permet à des composants de s'y lier : numéro de page,
/// total, boutons « Précédent / Suivant » activés selon `hasPrevious` /
/// `hasNext`, en-têtes triables selon `sort`, invitation à actualiser selon
/// `needsRefresh`.
library;

import 'package:flutter/foundation.dart';

import '../providers/data_provider.dart';
import 'datasource_config.dart';

/// Position de pagination et de tri de la recherche d'une datasource.
@immutable
class DatasourcePageState {
  /// Crée un état ; [page] commence à 1.
  const DatasourcePageState({
    this.page = 1,
    this.pageSize,
    this.offset = 0,
    this.total,
    this.pageCount,
    this.hasNext = false,
    this.hasPrevious = false,
    this.cursor,
    this.nextCursor,
    this.sort,
    this.needsRefresh = false,
  });

  /// Lecture stricte de la forme écrite par [toJson] (clés facultatives).
  factory DatasourcePageState.fromJson(Object? json) {
    const keys = {
      'page',
      'pageSize',
      'offset',
      'total',
      'pageCount',
      'hasNext',
      'hasPrevious',
      'cursor',
      'nextCursor',
      'sort',
      'needsRefresh',
    };
    if (json is! Map || json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException(
        'État de datasource invalide : objet attendu, clés inconnues '
        'refusées.',
      );
    }
    final page = json['page'] ?? 1;
    final pageSize = json['pageSize'];
    final offset = json['offset'] ?? 0;
    final total = json['total'];
    final pageCount = json['pageCount'];
    final hasNext = json['hasNext'] ?? false;
    final hasPrevious = json['hasPrevious'] ?? false;
    final cursor = json['cursor'];
    final nextCursor = json['nextCursor'];
    final needsRefresh = json['needsRefresh'] ?? false;
    if (page is! int ||
        (pageSize != null && pageSize is! int) ||
        offset is! int ||
        (total != null && total is! int) ||
        (pageCount != null && pageCount is! int) ||
        hasNext is! bool ||
        hasPrevious is! bool ||
        (cursor != null && cursor is! String) ||
        (nextCursor != null && nextCursor is! String) ||
        needsRefresh is! bool) {
      throw const FormatException(
        'État de datasource invalide : types inattendus.',
      );
    }
    final result = DatasourcePageState(
      page: page,
      pageSize: pageSize as int?,
      offset: offset,
      total: total as int?,
      pageCount: pageCount as int?,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
      cursor: cursor as String?,
      nextCursor: nextCursor as String?,
      sort: json['sort'] == null
          ? null
          : DatasourceSortOrder.fromJson(json['sort']),
      needsRefresh: needsRefresh,
    );
    result.validate();
    return result;
  }

  /// État initial, avant toute recherche.
  static const initial = DatasourcePageState();

  /// Numéro de la dernière page chargée, à partir de 1.
  final int page;

  /// Taille de page, ou `null` sans pagination.
  final int? pageSize;

  /// Position de la première ligne de la page.
  final int offset;

  /// Nombre total de lignes lu dans la réponse, ou `null`.
  final int? total;

  /// Nombre de pages déduit de [total], ou `null`.
  final int? pageCount;

  /// Vrai si une page suivante existe.
  final bool hasNext;

  /// Vrai si une page précédente existe.
  final bool hasPrevious;

  /// Curseur de la page courante (mode `cursor`), ou `null`.
  final String? cursor;

  /// Curseur de la page suivante (mode `cursor`), ou `null`.
  final String? nextCursor;

  /// Tri courant, ou `null`.
  final DatasourceSortOrder? sort;

  /// Vrai après une modification locale de la liste (Create, Update,
  /// Delete) : l'ordre, les pages ou le filtrage du serveur peuvent différer
  /// jusqu'à la prochaine recherche, qui remet l'indicateur à `false`.
  final bool needsRefresh;

  /// Vérifie que les nombres sont positifs.
  void validate() {
    if (page < 1 ||
        offset < 0 ||
        (pageSize ?? 1) < 1 ||
        (total ?? 0) < 0 ||
        (pageCount ?? 0) < 0) {
      throw const FormatException(
        'État de datasource invalide : nombres négatifs ou nuls.',
      );
    }
    sort?.validate();
  }

  /// Copie modifiée ; les `clear...` retirent la valeur facultative.
  DatasourcePageState copyWith({
    int? page,
    int? pageSize,
    int? offset,
    int? total,
    bool clearTotal = false,
    int? pageCount,
    bool clearPageCount = false,
    bool? hasNext,
    bool? hasPrevious,
    String? cursor,
    bool clearCursor = false,
    String? nextCursor,
    bool clearNextCursor = false,
    DatasourceSortOrder? sort,
    bool clearSort = false,
    bool? needsRefresh,
  }) => DatasourcePageState(
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
    offset: offset ?? this.offset,
    total: clearTotal ? null : (total ?? this.total),
    pageCount: clearPageCount ? null : (pageCount ?? this.pageCount),
    hasNext: hasNext ?? this.hasNext,
    hasPrevious: hasPrevious ?? this.hasPrevious,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    sort: clearSort ? null : (sort ?? this.sort),
    needsRefresh: needsRefresh ?? this.needsRefresh,
  );

  /// Forme écrite dans l'objet `state` : toutes les clés sont présentes
  /// (`null` si inconnues) pour que les composants liés se vident.
  Map<String, Object?> toJson() {
    validate();
    return {
      'page': page,
      'pageSize': pageSize,
      'offset': offset,
      'total': total,
      'pageCount': pageCount,
      'hasNext': hasNext,
      'hasPrevious': hasPrevious,
      'cursor': cursor,
      'nextCursor': nextCursor,
      'sort': sort?.toJson(),
      'needsRefresh': needsRefresh,
    };
  }

  /// Forme compacte : les valeurs inconnues et par défaut sont omises.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      if (page != 1) 'page': page,
      'pageSize': ?pageSize,
      if (offset != 0) 'offset': offset,
      'total': ?total,
      'pageCount': ?pageCount,
      if (hasNext) 'hasNext': true,
      if (hasPrevious) 'hasPrevious': true,
      'cursor': ?cursor,
      'nextCursor': ?nextCursor,
      'sort': ?sort?.toCompactJson(),
      if (needsRefresh) 'needsRefresh': true,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatasourcePageState &&
      page == other.page &&
      pageSize == other.pageSize &&
      offset == other.offset &&
      total == other.total &&
      pageCount == other.pageCount &&
      hasNext == other.hasNext &&
      hasPrevious == other.hasPrevious &&
      cursor == other.cursor &&
      nextCursor == other.nextCursor &&
      sort == other.sort &&
      needsRefresh == other.needsRefresh;

  @override
  int get hashCode => Object.hash(
    page,
    pageSize,
    offset,
    total,
    pageCount,
    hasNext,
    hasPrevious,
    cursor,
    nextCursor,
    sort,
    needsRefresh,
  );
}

/// État observable de la dernière commande d'une datasource.
@immutable
class DatasourceStatus {
  /// Crée un état.
  const DatasourceStatus({
    this.phase = DataProviderPhase.idle,
    this.command,
    this.run = 0,
    this.message,
    this.page = DatasourcePageState.initial,
  });

  /// Datasource qui n'a encore rien exécuté.
  static const idle = DatasourceStatus();

  /// Phase de la dernière commande.
  final DataProviderPhase phase;

  /// Dernière commande lancée, ou `null`.
  final DatasourceCommand? command;

  /// Numéro croissant de la commande.
  final int run;

  /// Message d'erreur (phase `error`) ou avertissement (synchronisation
  /// locale incomplète), sinon `null`.
  final String? message;

  /// Position de pagination et de tri courante.
  final DatasourcePageState page;

  /// Vrai pendant une commande.
  bool get isLoading => phase == DataProviderPhase.loading;

  /// Copie modifiée ; [clearMessage] retire le message.
  DatasourceStatus copyWith({
    DataProviderPhase? phase,
    DatasourceCommand? command,
    int? run,
    String? message,
    bool clearMessage = false,
    DatasourcePageState? page,
  }) => DatasourceStatus(
    phase: phase ?? this.phase,
    command: command ?? this.command,
    run: run ?? this.run,
    message: clearMessage ? null : (message ?? this.message),
    page: page ?? this.page,
  );

  @override
  bool operator ==(Object other) =>
      other is DatasourceStatus &&
      phase == other.phase &&
      command == other.command &&
      run == other.run &&
      message == other.message &&
      page == other.page;

  @override
  int get hashCode => Object.hash(phase, command, run, message, page);
}
