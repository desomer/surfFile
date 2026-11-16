/// Action de comportement qui lance une commande de datasource ([DatasourceAction]).
///
/// Au déclenchement, appelle `JsonRepositoryStore.datasources.run` avec la
/// ligne courante du composant (`JsonListScope`) : recherche, pagination, tri,
/// ou opération Create / Read / Update / Delete sur l'entité courante.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../component_behavior.dart';
import '../datasources/datasource_config.dart';

const _keys = {'type', 'datasourceId', 'command', 'field', 'direction'};

/// Lance la commande [command] de la datasource [datasourceId].
///
/// Seul l'identifiant est stocké dans l'apparence : la datasource elle-même
/// est déclarée dans le code hôte ou créée dans l'éditeur de datasources.
/// [field] et [direction] ne concernent que [DatasourceCommand.sort] : sans
/// [direction], un nouveau clic sur le même champ inverse le sens.
@immutable
class DatasourceAction extends BehaviorAction {
  /// Crée une action sur la datasource [datasourceId].
  const DatasourceAction({
    required this.datasourceId,
    this.command = DatasourceCommand.search,
    this.field,
    this.direction,
  });

  /// Identifiant de la datasource (`store.datasources`).
  final String datasourceId;

  /// Commande lancée.
  final DatasourceCommand command;

  /// Champ trié par [DatasourceCommand.sort].
  final String? field;

  /// Sens imposé par [DatasourceCommand.sort] ; `null` pour alterner.
  final DatasourceSortDirection? direction;

  /// Vérifie l'identifiant et les paramètres de tri.
  void validate() {
    if (!isValidDatasourceId(datasourceId)) {
      throw const FormatException(
        'L’identifiant de la datasource doit utiliser a-z, 0-9 et _ '
        '(32 caractères au plus).',
      );
    }
    if (command == DatasourceCommand.sort) {
      final field = this.field;
      if (field == null) {
        throw const FormatException('Le tri exige un champ (« field »).');
      }
      DatasourceSortOrder(field).validate();
    } else if (field != null || direction != null) {
      throw const FormatException(
        '« field » et « direction » ne concernent que la commande sort.',
      );
    }
  }

  @override
  String get type => 'datasource';

  @override
  String get label => command.label;

  @override
  String get description => switch (command) {
    DatasourceCommand.sort =>
      'Datasource $datasourceId — tri sur $field'
          '${direction == null ? '' : ' (${direction!.name})'}',
    _ => 'Datasource $datasourceId',
  };

  @override
  IconData get icon => switch (command.operation) {
    DatasourceOperation.search => switch (command) {
      DatasourceCommand.sort => Icons.sort,
      DatasourceCommand.refresh => Icons.refresh,
      DatasourceCommand.firstPage => Icons.first_page,
      DatasourceCommand.previousPage => Icons.chevron_left,
      DatasourceCommand.nextPage => Icons.chevron_right,
      DatasourceCommand.loadMore => Icons.expand_more,
      _ => Icons.manage_search_outlined,
    },
    DatasourceOperation.create => Icons.add_circle_outline,
    DatasourceOperation.read => Icons.file_open_outlined,
    DatasourceOperation.update => Icons.save_outlined,
    DatasourceOperation.delete => Icons.delete_outline,
  };

  /// Lance la commande sans l'attendre ; son échec est signalé par le store
  /// et l'état de la datasource, jamais par une exception.
  @override
  Future<void> execute(BuildContext context) async {
    final store = JsonRepositoryScope.maybeOf(context);
    if (store == null) return;
    unawaited(
      store.datasources.run(
        datasourceId,
        command,
        scope: JsonListScope.maybeOf(context),
        field: field,
        direction: direction,
      ),
    );
  }

  /// Copie immuable de l'action ; [clearSort] retire [field] et [direction],
  /// [clearDirection] seulement le sens.
  DatasourceAction copyWith({
    String? datasourceId,
    DatasourceCommand? command,
    String? field,
    DatasourceSortDirection? direction,
    bool clearSort = false,
    bool clearDirection = false,
  }) => DatasourceAction(
    datasourceId: datasourceId ?? this.datasourceId,
    command: command ?? this.command,
    field: clearSort ? null : field ?? this.field,
    direction: clearSort || clearDirection ? null : direction ?? this.direction,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'datasourceId': datasourceId,
      'command': command.name,
      'field': ?field,
      'direction': ?direction?.name,
    };
  }

  /// Forme compacte (identique : l'action ne contient aucune liaison).
  Map<String, Object?> toCompactJson() => toJson();

  /// Décode et valide une [DatasourceAction] persistée (`command` vaut
  /// `search` par défaut).
  factory DatasourceAction.fromJson(Map<String, dynamic> json) {
    for (final key in json.keys) {
      if (!_keys.contains(key)) {
        throw FormatException('Clé inconnue pour datasource : "$key".');
      }
    }
    final datasourceId = json['datasourceId'];
    if (datasourceId is! String) {
      throw const FormatException('L’identifiant de la datasource est requis.');
    }
    final rawCommand = json['command'] ?? DatasourceCommand.search.name;
    final command = DatasourceCommand.values
        .where((value) => value.name == rawCommand)
        .firstOrNull;
    if (command == null) {
      throw FormatException(
        'Commande de datasource inconnue : "$rawCommand" (attendu : '
        '${DatasourceCommand.values.map((value) => value.name).join(', ')}).',
      );
    }
    final field = json['field'];
    if (field != null && field is! String) {
      throw const FormatException('Le champ de tri doit être un texte.');
    }
    final rawDirection = json['direction'];
    final direction = rawDirection == null
        ? null
        : DatasourceSortDirection.byName(rawDirection);
    if (rawDirection != null && direction == null) {
      throw const FormatException(
        'Le sens du tri doit valoir « asc » ou « desc ».',
      );
    }
    final result = DatasourceAction(
      datasourceId: datasourceId,
      command: command,
      field: field as String?,
      direction: direction,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatasourceAction &&
          other.datasourceId == datasourceId &&
          other.command == command &&
          other.field == field &&
          other.direction == direction;

  @override
  int get hashCode => Object.hash(datasourceId, command, field, direction);
}
