/// Modèles immuables d'Event Storming conformes au **Event Storming DSL v1.0** :
/// [EventStormingSpec], [EventStormDocument] (1 document = 1 Bounded Context =
/// 1 fichier `<slug>.es.yaml`), [EventStormMeta], [EventStormCatalog],
/// [EventStormCatalogItem], [EventStormStep], [EventStormTrigger],
/// [EventStormPolicy], [EventStormReadModel], [EventStormCommand],
/// [EventStormDomainEvent], [EventStormOutcome], [EventStormHotspot] et
/// [EventStormBacklog].
library;

import 'package:flutter/foundation.dart';

/// Format d'atelier Event Storming (`meta.format`).
enum EventStormFormat {
  /// Vue d'ensemble macroscopique d'un domaine.
  bigPicture('big_picture', 'Big Picture'),

  /// Modélisation détaillée des processus métier (par défaut).
  processModeling('process_modeling', 'Process Modeling'),

  /// Modélisation fine au niveau conception logicielle / agrégats.
  designLevel('design_level', 'Design Level');

  /// Construit un format d'atelier.
  const EventStormFormat(this.yamlValue, this.label);

  /// Valeur exacte dans le schéma YAML/JSON DSL v1.0.
  final String yamlValue;

  /// Libellé lisible dans l'interface.
  final String label;

  /// Résout un format depuis JSON/YAML.
  static EventStormFormat fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
      for (final value in EventStormFormat.values) {
        if (value.yamlValue == norm || value.name.toLowerCase() == norm) {
          return value;
        }
      }
    }
    return EventStormFormat.processModeling;
  }
}

/// Nature d'un acteur du catalogue (`catalog.actors[].type`).
enum EventStormActorType {
  /// Acteur humain / persona.
  human('human', 'Humain'),

  /// Déclencheur temporel / planifié (CRON, échéance).
  timer('timer', 'Temporel'),

  /// Système interne ou automate.
  system('system', 'Système');

  /// Construit un type d'acteur.
  const EventStormActorType(this.yamlValue, this.label);

  /// Valeur exacte dans le schéma DSL v1.0.
  final String yamlValue;

  /// Libellé lisible en français.
  final String label;

  /// Résout un type d'acteur depuis JSON/YAML.
  static EventStormActorType fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in EventStormActorType.values) {
        if (value.yamlValue == norm) return value;
      }
      if (norm == 'utilisateur' || norm == 'user' || norm == 'persona') {
        return EventStormActorType.human;
      }
      if (norm == 'cron' || norm == 'schedule' || norm == 'temps') {
        return EventStormActorType.timer;
      }
      if (norm == 'systeme' || norm == 'bot' || norm == 'automate') {
        return EventStormActorType.system;
      }
    }
    return EventStormActorType.human;
  }
}

/// Sévérité d'un hotspot (`hotspots[].severity`).
enum EventStormHotspotSeverity {
  /// Risque ou question mineure.
  low('low', 'Faible'),

  /// Risque ou question modérée.
  medium('medium', 'Moyenne'),

  /// Risque ou question majeure.
  high('high', 'Élevée'),

  /// Blocage critique empêchant la suite.
  blocker('blocker', 'Bloquant');

  /// Construit une sévérité de hotspot.
  const EventStormHotspotSeverity(this.yamlValue, this.label);

  /// Valeur exacte dans le schéma DSL v1.0.
  final String yamlValue;

  /// Libellé lisible en français.
  final String label;

  /// Résout une sévérité depuis JSON/YAML.
  static EventStormHotspotSeverity fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in EventStormHotspotSeverity.values) {
        if (value.yamlValue == norm) return value;
      }
      if (norm == 'critical' || norm == 'critique' || norm == 'bloquant') {
        return EventStormHotspotSeverity.blocker;
      }
      if (norm == 'elevee' || norm == 'élevée' || norm == 'haute') {
        return EventStormHotspotSeverity.high;
      }
      if (norm == 'faible' || norm == 'basse') {
        return EventStormHotspotSeverity.low;
      }
    }
    return EventStormHotspotSeverity.medium;
  }
}

/// Statut d'un hotspot (`hotspots[].status`).
enum EventStormHotspotStatus {
  /// Question ouverte ou blocage actif.
  open('open', 'Ouvert'),

  /// Question tranchée / blocage levé.
  resolved('resolved', 'Résolu');

  /// Construit un statut de hotspot.
  const EventStormHotspotStatus(this.yamlValue, this.label);

  /// Valeur exacte dans le schéma DSL v1.0.
  final String yamlValue;

  /// Libellé lisible en français.
  final String label;

  /// Résout un statut depuis JSON/YAML.
  static EventStormHotspotStatus fromJson(Object? raw) {
    if (raw is bool) {
      return raw
          ? EventStormHotspotStatus.resolved
          : EventStormHotspotStatus.open;
    }
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      if (norm == 'resolved' ||
          norm == 'resolu' ||
          norm == 'résolu' ||
          norm == 'closed' ||
          norm == 'done') {
        return EventStormHotspotStatus.resolved;
      }
    }
    return EventStormHotspotStatus.open;
  }
}

/// Mode de déclenchement causal entrant (`triggered_by`).
enum EventStormTriggerMode {
  /// Déclenchement par un événement unique (`"EVT-01"` ou `"CMD:EVT-02A"`).
  single('single', 'Événement simple'),

  /// Synchronisation **ET** en entrée (`all_of: [...]`, min 2 événements).
  allOf('all_of', 'Synchronisation ET (all_of)'),

  /// Convergence **OU** en entrée (`any_of: [...]`, min 2 événements).
  anyOf('any_of', 'Convergence OU (any_of)');

  /// Construit un mode de déclenchement.
  const EventStormTriggerMode(this.yamlKey, this.label);

  /// Clé YAML correspondante.
  final String yamlKey;

  /// Libellé lisible en français.
  final String label;
}

/// Bloc `meta` d'un document Event Storming DSL v1.0 (cadre de l'atelier).
@immutable
class EventStormMeta {
  /// Construit le bloc de métadonnées d'atelier.
  const EventStormMeta({
    required this.domain,
    required this.boundedContext,
    this.format = EventStormFormat.processModeling,
    required this.date,
    this.facilitator = '',
  });

  /// Nom du domaine métier global (ex. `"E-Commerce"`).
  final String domain;

  /// Nom du Bounded Context couvert par ce fichier (ex. `"Gestion des commandes"`).
  final String boundedContext;

  /// Format de l'atelier (`big_picture`, `process_modeling`, `design_level`).
  final EventStormFormat format;

  /// Date de l'atelier au format ISO `YYYY-MM-DD`.
  final String date;

  /// Facilitateur optionnel (ex. `"Product Owner"`).
  final String facilitator;

  /// Vérifie les invariants du bloc `meta`.
  void validate() {
    if (domain.trim().isEmpty) {
      throw const FormatException('EventStormMeta.domain ne peut pas être vide.');
    }
    if (boundedContext.trim().isEmpty) {
      throw const FormatException(
        'EventStormMeta.boundedContext ne peut pas être vide.',
      );
    }
    if (date.trim().isEmpty) {
      throw const FormatException('EventStormMeta.date ne peut pas être vide.');
    }
  }

  /// Retourne une copie modifiée.
  EventStormMeta copyWith({
    String? domain,
    String? boundedContext,
    EventStormFormat? format,
    String? date,
    String? facilitator,
  }) => EventStormMeta(
    domain: domain ?? this.domain,
    boundedContext: boundedContext ?? this.boundedContext,
    format: format ?? this.format,
    date: date ?? this.date,
    facilitator: facilitator ?? this.facilitator,
  );

  /// Sérialise `meta` au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'domain': domain,
    'bounded_context': boundedContext,
    'format': format.yamlValue,
    'date': date,
    if (facilitator.isNotEmpty) 'facilitator': facilitator,
  };

  /// Désérialise `meta` depuis JSON/YAML.
  factory EventStormMeta.fromJson(
    Object? raw, {
    String fallbackDomain = 'Domaine métier',
    String fallbackContext = 'Contexte métier',
  }) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final domain = _str(map['domain']).isNotEmpty
        ? _str(map['domain'])
        : fallbackDomain;
    final boundedContext =
        _str(map['bounded_context'] ?? map['boundedContext'] ?? map['context'])
            .isNotEmpty
        ? _str(map['bounded_context'] ?? map['boundedContext'] ?? map['context'])
        : fallbackContext;
    final date = _str(map['date']).isNotEmpty
        ? _str(map['date'])
        : _todayIsoDate();
    final meta = EventStormMeta(
      domain: domain,
      boundedContext: boundedContext,
      format: EventStormFormat.fromJson(map['format']),
      date: date,
      facilitator: _str(map['facilitator']),
    );
    meta.validate();
    return meta;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormMeta &&
          other.domain == domain &&
          other.boundedContext == boundedContext &&
          other.format == format &&
          other.date == date &&
          other.facilitator == facilitator;

  @override
  int get hashCode =>
      Object.hash(domain, boundedContext, format, date, facilitator);
}

/// Entrée du référentiel `catalog` (`ACT-*`, `AGG-*` ou `EXT-*`).
@immutable
class EventStormCatalogItem {
  /// Construit une entrée de catalogue immuable.
  const EventStormCatalogItem({
    required this.id,
    required this.name,
    this.type,
  });

  /// Identifiant canonique (`ACT-*`, `AGG-*` ou `EXT-*`).
  final String id;

  /// Nom métier affiché.
  final String name;

  /// Type optionnel (utilisé pour les acteurs : `human`, `timer`, `system`).
  final EventStormActorType? type;

  /// Vérifie les invariants de l'entrée.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'EventStormCatalogItem.id ne peut pas être vide.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'EventStormCatalogItem.name ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormCatalogItem copyWith({
    String? id,
    String? name,
    EventStormActorType? type,
    bool clearType = false,
  }) => EventStormCatalogItem(
    id: id ?? this.id,
    name: name ?? this.name,
    type: clearType ? null : (type ?? this.type),
  );

  /// Sérialise l'entrée au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (type != null) 'type': type!.yamlValue,
  };

  /// Désérialise une entrée depuis JSON/YAML.
  factory EventStormCatalogItem.fromJson(
    Object? raw, {
    required String defaultPrefix,
    bool includeDefaultActorType = false,
  }) {
    if (raw is! Map) {
      throw const FormatException(
        'EventStormCatalogItem doit être un objet JSON/YAML.',
      );
    }
    final name = _str(raw['name'] ?? raw['title'] ?? raw['label']);
    final effectiveName = name.isEmpty ? 'Élément' : name;
    final rawId = _str(raw['id']);
    final effectiveId = rawId.isEmpty
        ? _makeCatalogId(defaultPrefix, effectiveName)
        : rawId;
    final hasType = raw['type'] != null && _str(raw['type']).isNotEmpty;
    final item = EventStormCatalogItem(
      id: effectiveId,
      name: effectiveName,
      type: hasType
          ? EventStormActorType.fromJson(raw['type'])
          : (includeDefaultActorType ? EventStormActorType.human : null),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormCatalogItem &&
          other.id == id &&
          other.name == name &&
          other.type == type;

  @override
  int get hashCode => Object.hash(id, name, type);
}

/// Bloc `catalog` (légende du mur) : référentiel unique des `actors`,
/// `aggregates` et `external_systems`.
@immutable
class EventStormCatalog {
  /// Construit un catalogue immuable.
  EventStormCatalog({
    List<EventStormCatalogItem> actors = const <EventStormCatalogItem>[],
    List<EventStormCatalogItem> aggregates = const <EventStormCatalogItem>[],
    List<EventStormCatalogItem> externalSystems =
        const <EventStormCatalogItem>[],
  }) : actors = List<EventStormCatalogItem>.unmodifiable(actors),
       aggregates = List<EventStormCatalogItem>.unmodifiable(aggregates),
       externalSystems = List<EventStormCatalogItem>.unmodifiable(
         externalSystems,
       );

  /// Catalogue vide.
  static final EventStormCatalog empty = EventStormCatalog();

  /// Acteurs humains, temporels ou systèmes (`ACT-*`).
  final List<EventStormCatalogItem> actors;

  /// Agrégats métier internes (`AGG-*`).
  final List<EventStormCatalogItem> aggregates;

  /// Services ou systèmes externes (`EXT-*`, post-it Rose pâle).
  final List<EventStormCatalogItem> externalSystems;

  /// Vrai si le catalogue ne contient aucune entrée.
  bool get isEmpty =>
      actors.isEmpty && aggregates.isEmpty && externalSystems.isEmpty;

  /// Vrai si au moins une entrée existe.
  bool get isNotEmpty => !isEmpty;

  /// Recherche un acteur par identifiant ou nom.
  EventStormCatalogItem? findActor(String idOrName) =>
      _findCatalogItem(actors, idOrName);

  /// Recherche un agrégat par identifiant ou nom.
  EventStormCatalogItem? findAggregate(String idOrName) =>
      _findCatalogItem(aggregates, idOrName);

  /// Recherche un système externe par identifiant ou nom.
  EventStormCatalogItem? findExternalSystem(String idOrName) =>
      _findCatalogItem(externalSystems, idOrName);

  /// Vérifie les invariants et l'unicité des identifiants du catalogue.
  void validate() {
    final seenIds = <String>{};
    for (final list in [actors, aggregates, externalSystems]) {
      for (final item in list) {
        item.validate();
        if (!seenIds.add(item.id)) {
          throw FormatException(
            'Identifiant dupliqué dans le catalogue Event Storming : ${item.id}',
          );
        }
      }
    }
  }

  /// Retourne une copie modifiée.
  EventStormCatalog copyWith({
    List<EventStormCatalogItem>? actors,
    List<EventStormCatalogItem>? aggregates,
    List<EventStormCatalogItem>? externalSystems,
  }) => EventStormCatalog(
    actors: actors ?? this.actors,
    aggregates: aggregates ?? this.aggregates,
    externalSystems: externalSystems ?? this.externalSystems,
  );

  /// Sérialise le catalogue au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    if (actors.isNotEmpty) 'actors': [for (final a in actors) a.toJson()],
    if (aggregates.isNotEmpty)
      'aggregates': [for (final a in aggregates) a.toJson()],
    if (externalSystems.isNotEmpty)
      'external_systems': [for (final e in externalSystems) e.toJson()],
  };

  /// Désérialise un catalogue depuis JSON/YAML.
  factory EventStormCatalog.fromJson(Object? raw) {
    if (raw is! Map) return EventStormCatalog.empty;
    final rawActors = raw['actors'];
    final rawAggregates = raw['aggregates'];
    final rawExternal = raw['external_systems'] ?? raw['externalSystems'];
    final catalog = EventStormCatalog(
      actors: [
        if (rawActors is List)
          for (final item in rawActors)
            EventStormCatalogItem.fromJson(
              item,
              defaultPrefix: 'ACT',
              includeDefaultActorType: true,
            ),
      ],
      aggregates: [
        if (rawAggregates is List)
          for (final item in rawAggregates)
            EventStormCatalogItem.fromJson(item, defaultPrefix: 'AGG'),
      ],
      externalSystems: [
        if (rawExternal is List)
          for (final item in rawExternal)
            EventStormCatalogItem.fromJson(item, defaultPrefix: 'EXT'),
      ],
    );
    catalog.validate();
    return catalog;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormCatalog &&
          listEquals(other.actors, actors) &&
          listEquals(other.aggregates, aggregates) &&
          listEquals(other.externalSystems, externalSystems);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(actors),
    Object.hashAll(aggregates),
    Object.hashAll(externalSystems),
  );
}

/// Rattachement backlog PO d'une étape (`step.backlog`).
@immutable
class EventStormBacklog {
  /// Construit un rattachement backlog immuable.
  const EventStormBacklog({this.epic = '', this.story = ''});

  /// Identifiant d'Epic (ex. `"EPIC-01"`).
  final String epic;

  /// Identifiant de User Story (ex. `"US-101"`).
  final String story;

  /// Vrai si ni epic ni story ne sont renseignés.
  bool get isEmpty => epic.trim().isEmpty && story.trim().isEmpty;

  /// Vrai si au moins epic ou story est renseigné.
  bool get isNotEmpty => !isEmpty;

  /// Retourne une copie modifiée.
  EventStormBacklog copyWith({String? epic, String? story}) =>
      EventStormBacklog(epic: epic ?? this.epic, story: story ?? this.story);

  /// Sérialise au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    if (epic.isNotEmpty) 'epic': epic,
    if (story.isNotEmpty) 'story': story,
  };

  /// Désérialise depuis JSON/YAML.
  static EventStormBacklog? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final b = EventStormBacklog(
      epic: _str(raw['epic']),
      story: _str(raw['story']),
    );
    return b.isEmpty ? null : b;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormBacklog && other.epic == epic && other.story == story;

  @override
  int get hashCode => Object.hash(epic, story);
}

/// Lien causal entrant (`triggered_by`) : événement simple, `all_of` (ET) ou `any_of` (OU).
@immutable
class EventStormTrigger {
  /// Construit un déclencheur simple sur un événement unique (local ou `CTX:EVT-*`).
  EventStormTrigger.single(String eventId)
    : mode = EventStormTriggerMode.single,
      eventIds = List<String>.unmodifiable(<String>[eventId.trim()]);

  /// Construit une synchronisation **ET** (`all_of: [...]`, min 2 événements).
  EventStormTrigger.allOf(List<String> eventIds)
    : mode = EventStormTriggerMode.allOf,
      eventIds = List<String>.unmodifiable([
        for (final id in eventIds)
          if (id.trim().isNotEmpty) id.trim(),
      ]);

  /// Construit une convergence **OU** (`any_of: [...]`, min 2 événements).
  EventStormTrigger.anyOf(List<String> eventIds)
    : mode = EventStormTriggerMode.anyOf,
      eventIds = List<String>.unmodifiable([
        for (final id in eventIds)
          if (id.trim().isNotEmpty) id.trim(),
      ]);

  /// Mode du déclencheur (`single`, `allOf`, `anyOf`).
  final EventStormTriggerMode mode;

  /// Liste des identifiants d'événements déclencheurs (1 pour `single`, >= 2 pour `allOf`/`anyOf`).
  final List<String> eventIds;

  /// Identifiant unique si [mode] est [EventStormTriggerMode.single].
  String? get singleEventId =>
      mode == EventStormTriggerMode.single && eventIds.isNotEmpty
      ? eventIds.first
      : null;

  /// Résumé lisible (ex. `"EVT-01"`, `"ET (EVT-03A, EVT-04)"`, `"OU (EVT-02B, EVT-03B)"`).
  String get summaryLabel => switch (mode) {
    EventStormTriggerMode.single => eventIds.isEmpty ? '' : eventIds.first,
    EventStormTriggerMode.allOf => 'ET (${eventIds.join(' + ')})',
    EventStormTriggerMode.anyOf => 'OU (${eventIds.join(' | ')})',
  };

  /// Vérifie les invariants du déclencheur.
  void validate() {
    if (mode == EventStormTriggerMode.single) {
      if (eventIds.length != 1 || eventIds.first.isEmpty) {
        throw const FormatException(
          'EventStormTrigger.single requiert exactement 1 identifiant d’événement.',
        );
      }
    } else if (eventIds.length < 2) {
      throw FormatException(
        'EventStormTrigger.${mode.yamlKey} requiert au moins 2 identifiants d’événements.',
      );
    }
  }

  /// Sérialise au format exact du DSL v1.0 (`String` ou `{"all_of": [...]}` ou `{"any_of": [...]}`).
  Object toJson() => switch (mode) {
    EventStormTriggerMode.single => eventIds.first,
    EventStormTriggerMode.allOf => <String, Object?>{'all_of': eventIds},
    EventStormTriggerMode.anyOf => <String, Object?>{'any_of': eventIds},
  };

  /// Désérialise depuis JSON/YAML (`String` ou `Map` `all_of` / `any_of`).
  static EventStormTrigger? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return EventStormTrigger.single(trimmed);
    }
    if (raw is Map) {
      final allOf = _stringList(raw['all_of'] ?? raw['allOf']);
      if (allOf.isNotEmpty) {
        final trigger = EventStormTrigger.allOf(allOf);
        trigger.validate();
        return trigger;
      }
      final anyOf = _stringList(raw['any_of'] ?? raw['anyOf']);
      if (anyOf.isNotEmpty) {
        final trigger = EventStormTrigger.anyOf(anyOf);
        trigger.validate();
        return trigger;
      }
    }
    throw const FormatException(
      'triggered_by doit être un identifiant EVT-* ou un objet all_of / any_of.',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormTrigger &&
          other.mode == mode &&
          listEquals(other.eventIds, eventIds);

  @override
  int get hashCode => Object.hash(mode, Object.hashAll(eventIds));
}

/// Politique réactive automatique (`step.policy`, post-it Violet).
@immutable
class EventStormPolicy {
  /// Construit une politique réactive immuable.
  const EventStormPolicy({required this.name, required this.rule});

  /// Nom court de la politique (ex. `"Déclencher l'encaissement"`).
  final String name;

  /// Règle métier formulée `Quand [événement], alors [commande]`.
  final String rule;

  /// Vérifie les invariants de la politique.
  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException('EventStormPolicy.name ne peut pas être vide.');
    }
    if (rule.trim().isEmpty) {
      throw const FormatException('EventStormPolicy.rule ne peut pas être vide.');
    }
  }

  /// Retourne une copie modifiée.
  EventStormPolicy copyWith({String? name, String? rule}) =>
      EventStormPolicy(name: name ?? this.name, rule: rule ?? this.rule);

  /// Sérialise au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'rule': rule,
  };

  /// Désérialise depuis JSON/YAML.
  static EventStormPolicy? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is String && raw.trim().isNotEmpty) {
      return EventStormPolicy(name: raw.trim(), rule: raw.trim());
    }
    if (raw is! Map) return null;
    final name = _str(raw['name'] ?? raw['title']);
    final rule = _str(raw['rule'] ?? raw['description']);
    if (name.isEmpty && rule.isEmpty) return null;
    final p = EventStormPolicy(
      name: name.isNotEmpty ? name : rule,
      rule: rule.isNotEmpty ? rule : name,
    );
    p.validate();
    return p;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormPolicy && other.name == name && other.rule == rule;

  @override
  int get hashCode => Object.hash(name, rule);
}

/// Modèle de lecture / écran (`step.read_model`, post-it Vert).
@immutable
class EventStormReadModel {
  /// Construit un Read Model immuable.
  EventStormReadModel({
    required this.name,
    List<String> sourceEvents = const <String>[],
    List<String> fields = const <String>[],
  }) : sourceEvents = List<String>.unmodifiable(sourceEvents),
       fields = List<String>.unmodifiable(fields);

  /// Nom de l'écran ou de la projection (ex. `"Écran récapitulatif panier"`).
  final String name;

  /// Identifiants d'événements sources alimentant cette vue (ex. `["EVT-00"]`).
  final List<String> sourceEvents;

  /// Champs affichés à l'acteur (ex. `["lignes_panier", "montant_ttc"]`).
  final List<String> fields;

  /// Vérifie les invariants du Read Model.
  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException(
        'EventStormReadModel.name ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormReadModel copyWith({
    String? name,
    List<String>? sourceEvents,
    List<String>? fields,
  }) => EventStormReadModel(
    name: name ?? this.name,
    sourceEvents: sourceEvents ?? this.sourceEvents,
    fields: fields ?? this.fields,
  );

  /// Sérialise au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (sourceEvents.isNotEmpty) 'source_events': sourceEvents,
    if (fields.isNotEmpty) 'fields': fields,
  };

  /// Désérialise depuis JSON/YAML.
  static EventStormReadModel? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is String && raw.trim().isNotEmpty) {
      return EventStormReadModel(name: raw.trim());
    }
    if (raw is! Map) return null;
    final name = _str(raw['name'] ?? raw['title']);
    if (name.isEmpty) return null;
    final rm = EventStormReadModel(
      name: name,
      sourceEvents: _stringList(raw['source_events'] ?? raw['sourceEvents']),
      fields: _stringList(raw['fields'] ?? raw['payloadFields']),
    );
    rm.validate();
    return rm;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormReadModel &&
          other.name == name &&
          listEquals(other.sourceEvents, sourceEvents) &&
          listEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(
    name,
    Object.hashAll(sourceEvents),
    Object.hashAll(fields),
  );
}

/// Commande métier (`step.command`, post-it Bleu) formulée à l'infinitif.
@immutable
class EventStormCommand {
  /// Construit une commande immuable.
  EventStormCommand({
    required this.name,
    List<String> payload = const <String>[],
  }) : payload = List<String>.unmodifiable(payload);

  /// Intention d'action formulée à l'infinitif (ex. `"Valider le panier"`).
  final String name;

  /// Paramètres d'entrée de la commande.
  final List<String> payload;

  /// Vérifie les invariants de la commande.
  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException(
        'EventStormCommand.name ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormCommand copyWith({String? name, List<String>? payload}) =>
      EventStormCommand(
        name: name ?? this.name,
        payload: payload ?? this.payload,
      );

  /// Sérialise au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (payload.isNotEmpty) 'payload': payload,
  };

  /// Désérialise depuis JSON/YAML.
  factory EventStormCommand.fromJson(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return EventStormCommand(name: raw.trim());
    }
    if (raw is! Map) {
      throw const FormatException(
        'EventStormCommand doit être un objet JSON/YAML.',
      );
    }
    final name = _str(raw['name'] ?? raw['title']);
    final cmd = EventStormCommand(
      name: name.isEmpty ? 'Exécuter la commande' : name,
      payload: _stringList(raw['payload'] ?? raw['payloadFields']),
    );
    cmd.validate();
    return cmd;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormCommand &&
          other.name == name &&
          listEquals(other.payload, payload);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(payload));
}

/// Événement domaine (`domain_event`, post-it Orange) formulé au passé composé.
@immutable
class EventStormDomainEvent {
  /// Construit un événement domaine immuable.
  EventStormDomainEvent({
    required this.id,
    required this.name,
    List<String> data = const <String>[],
  }) : data = List<String>.unmodifiable(data);

  /// Identifiant canonique de l'événement (`EVT-01`, `EVT-02A`, ...).
  final String id;

  /// Fait accompli formulé au passé composé (ex. `"Panier validé"`).
  final String name;

  /// Données émises par l'événement.
  final List<String> data;

  /// Vérifie les invariants de l'événement domaine.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'EventStormDomainEvent.id ne peut pas être vide.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'EventStormDomainEvent.name ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormDomainEvent copyWith({
    String? id,
    String? name,
    List<String>? data,
  }) => EventStormDomainEvent(
    id: id ?? this.id,
    name: name ?? this.name,
    data: data ?? this.data,
  );

  /// Sérialise au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (data.isNotEmpty) 'data': data,
  };

  /// Désérialise depuis JSON/YAML.
  factory EventStormDomainEvent.fromJson(
    Object? raw, {
    String fallbackId = 'EVT-01',
  }) {
    if (raw is! Map) {
      throw const FormatException(
        'EventStormDomainEvent doit être un objet JSON/YAML.',
      );
    }
    final id = _str(raw['id']);
    final name = _str(raw['name'] ?? raw['title']);
    final evt = EventStormDomainEvent(
      id: id.isEmpty ? fallbackId : id,
      name: name.isEmpty ? 'Événement émis' : name,
      data: _stringList(raw['data'] ?? raw['payloadFields']),
    );
    evt.validate();
    return evt;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormDomainEvent &&
          other.id == id &&
          other.name == name &&
          listEquals(other.data, data);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(data));
}

/// Branche d'alternative exclusive en sortie (`step.outcomes[]`, OU exclusif).
@immutable
class EventStormOutcome {
  /// Construit une branche d'issue immuable.
  const EventStormOutcome({
    required this.condition,
    this.isError = false,
    required this.domainEvent,
  });

  /// Condition métier déclenchant cette issue.
  final String condition;

  /// Indique si cette branche correspond à un cas d'erreur / échec métier.
  final bool isError;

  /// Événement domaine émis sur cette branche.
  final EventStormDomainEvent domainEvent;

  /// Vérifie les invariants de l'issue.
  void validate() {
    if (condition.trim().isEmpty) {
      throw const FormatException(
        'EventStormOutcome.condition ne peut pas être vide.',
      );
    }
    domainEvent.validate();
  }

  /// Retourne une copie modifiée.
  EventStormOutcome copyWith({
    String? condition,
    bool? isError,
    EventStormDomainEvent? domainEvent,
  }) => EventStormOutcome(
    condition: condition ?? this.condition,
    isError: isError ?? this.isError,
    domainEvent: domainEvent ?? this.domainEvent,
  );

  /// Sérialise au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'condition': condition,
    'is_error': isError,
    'domain_event': domainEvent.toJson(),
  };

  /// Désérialise depuis JSON/YAML.
  factory EventStormOutcome.fromJson(
    Object? raw, {
    String fallbackEventId = 'EVT-01A',
  }) {
    if (raw is! Map) {
      throw const FormatException(
        'EventStormOutcome doit être un objet JSON/YAML.',
      );
    }
    final condition = _str(raw['condition']);
    final isError = raw['is_error'] == true || raw['isError'] == true;
    final evt = EventStormDomainEvent.fromJson(
      raw['domain_event'] ?? raw['domainEvent'],
      fallbackId: fallbackEventId,
    );
    final outcome = EventStormOutcome(
      condition: condition.isEmpty ? 'Condition métier' : condition,
      isError: isError,
      domainEvent: evt,
    );
    outcome.validate();
    return outcome;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormOutcome &&
          other.condition == condition &&
          other.isError == isError &&
          other.domainEvent == domainEvent;

  @override
  int get hashCode => Object.hash(condition, isError, domainEvent);
}

/// Question ouverte, blocage ou risque (`step.hotspots[]`, post-it Rose vif).
@immutable
class EventStormHotspot {
  /// Construit un hotspot immuable.
  const EventStormHotspot({
    required this.id,
    required this.question,
    this.severity = EventStormHotspotSeverity.medium,
    this.owner = '',
    this.status = EventStormHotspotStatus.open,
  });

  /// Identifiant canonique (`HS-01`, `HS-02`, ...).
  final String id;

  /// Question ouverte ou risque identifié.
  final String question;

  /// Niveau de sévérité (`low`, `medium`, `high`, `blocker`).
  final EventStormHotspotSeverity severity;

  /// Responsable de la résolution (ex. `"PO + Métier Pricing"`).
  final String owner;

  /// Statut (`open` ou `resolved`).
  final EventStormHotspotStatus status;

  /// Raccourci vrai si le hotspot est résolu.
  bool get isResolved => status == EventStormHotspotStatus.resolved;

  /// Raccourci vrai si le hotspot est ouvert.
  bool get isOpen => status == EventStormHotspotStatus.open;

  /// Vérifie les invariants du hotspot.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('EventStormHotspot.id ne peut pas être vide.');
    }
    if (question.trim().isEmpty) {
      throw const FormatException(
        'EventStormHotspot.question ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormHotspot copyWith({
    String? id,
    String? question,
    EventStormHotspotSeverity? severity,
    String? owner,
    EventStormHotspotStatus? status,
  }) => EventStormHotspot(
    id: id ?? this.id,
    question: question ?? this.question,
    severity: severity ?? this.severity,
    owner: owner ?? this.owner,
    status: status ?? this.status,
  );

  /// Sérialise au format DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'question': question,
    'severity': severity.yamlValue,
    if (owner.isNotEmpty) 'owner': owner,
    'status': status.yamlValue,
  };

  /// Désérialise depuis JSON/YAML.
  factory EventStormHotspot.fromJson(
    Object? raw, {
    String fallbackId = 'HS-01',
  }) {
    if (raw is! Map) {
      throw const FormatException(
        'EventStormHotspot doit être un objet JSON/YAML.',
      );
    }
    final id = _str(raw['id']);
    final question = _str(raw['question'] ?? raw['title']);
    final hotspot = EventStormHotspot(
      id: id.isEmpty ? fallbackId : id,
      question: question.isEmpty ? 'Question ouverte à clarifier' : question,
      severity: EventStormHotspotSeverity.fromJson(raw['severity']),
      owner: _str(raw['owner']),
      status: EventStormHotspotStatus.fromJson(
        raw['status'] ?? raw['resolved'],
      ),
    );
    hotspot.validate();
    return hotspot;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormHotspot &&
          other.id == id &&
          other.question == question &&
          other.severity == severity &&
          other.owner == owner &&
          other.status == status;

  @override
  int get hashCode => Object.hash(id, question, severity, owner, status);
}

/// Étape chronologique (`flow[]`) d'un document Event Storming DSL v1.0.
@immutable
class EventStormStep {
  /// Construit une étape immuable.
  EventStormStep({
    required this.step,
    this.backlog,
    this.triggeredBy,
    this.policy,
    this.readModel,
    this.actor = '',
    required this.command,
    this.aggregate = '',
    this.externalSystem = '',
    this.domainEvent,
    List<EventStormOutcome> outcomes = const <EventStormOutcome>[],
    List<EventStormHotspot> hotspots = const <EventStormHotspot>[],
  }) : outcomes = List<EventStormOutcome>.unmodifiable(outcomes),
       hotspots = List<EventStormHotspot>.unmodifiable(hotspots);

  /// Numéro d'ordre chronologique (>= 1).
  final int step;

  /// Rattachement backlog optionnel (`epic`, `story`).
  final EventStormBacklog? backlog;

  /// Lien causal entrant (`EVT-*`, `all_of`, `any_of` ou `CTX:EVT-*`).
  final EventStormTrigger? triggeredBy;

  /// Politique réactive automatique (post-it Violet).
  final EventStormPolicy? policy;

  /// Écran / données consultées (post-it Vert).
  final EventStormReadModel? readModel;

  /// Identifiant catalogue de l'acteur déclencheur (`ACT-*`, Petit Jaune).
  final String actor;

  /// Commande métier (post-it Bleu, obligatoire).
  final EventStormCommand command;

  /// Identifiant catalogue de l'agrégat cible (`AGG-*`, Grand Jaune).
  final String aggregate;

  /// Identifiant catalogue du système externe cible (`EXT-*`, Rose pâle).
  final String externalSystem;

  /// Événement domaine unique (mutuellement exclusif avec [outcomes]).
  final EventStormDomainEvent? domainEvent;

  /// Alternative exclusive en sortie (min 2 items, mutuellement exclusif avec [domainEvent]).
  final List<EventStormOutcome> outcomes;

  /// Hotspots rattachés à cette étape (Rose vif).
  final List<EventStormHotspot> hotspots;

  /// Vrai si cette étape utilise un embranchement exclusif `outcomes[]`.
  bool get hasOutcomes => outcomes.isNotEmpty;

  /// Liste de tous les événements émis par cette étape (1 ou plusieurs via `outcomes`).
  List<EventStormDomainEvent> get emittedEvents => [
    ?domainEvent,
    for (final o in outcomes) o.domainEvent,
  ];

  /// Nombre de hotspots ouverts sur cette étape.
  int get openHotspotCount => hotspots.where((h) => h.isOpen).length;

  /// Vérifie les invariants structurels de l'étape conformes au schéma DSL v1.0.
  void validate() {
    if (step < 1) {
      throw const FormatException('EventStormStep.step doit être >= 1.');
    }
    triggeredBy?.validate();
    policy?.validate();
    readModel?.validate();
    command.validate();

    final hasEvent = domainEvent != null;
    final hasOut = outcomes.isNotEmpty;
    if (hasEvent == hasOut) {
      throw FormatException(
        'L’étape $step doit définir exactement l’un de `domain_event` ou `outcomes` (mutuellement exclusifs).',
      );
    }
    if (hasEvent) {
      domainEvent!.validate();
    } else {
      if (outcomes.length < 2) {
        throw FormatException(
          'L’étape $step : `outcomes` doit contenir au moins 2 branches exclusives.',
        );
      }
      for (final outcome in outcomes) {
        outcome.validate();
      }
    }
    for (final hotspot in hotspots) {
      hotspot.validate();
    }
  }

  /// Retourne une copie modifiée.
  EventStormStep copyWith({
    int? step,
    EventStormBacklog? backlog,
    bool clearBacklog = false,
    EventStormTrigger? triggeredBy,
    bool clearTriggeredBy = false,
    EventStormPolicy? policy,
    bool clearPolicy = false,
    EventStormReadModel? readModel,
    bool clearReadModel = false,
    String? actor,
    EventStormCommand? command,
    String? aggregate,
    String? externalSystem,
    EventStormDomainEvent? domainEvent,
    bool clearDomainEvent = false,
    List<EventStormOutcome>? outcomes,
    List<EventStormHotspot>? hotspots,
  }) => EventStormStep(
    step: step ?? this.step,
    backlog: clearBacklog ? null : (backlog ?? this.backlog),
    triggeredBy: clearTriggeredBy ? null : (triggeredBy ?? this.triggeredBy),
    policy: clearPolicy ? null : (policy ?? this.policy),
    readModel: clearReadModel ? null : (readModel ?? this.readModel),
    actor: actor ?? this.actor,
    command: command ?? this.command,
    aggregate: aggregate ?? this.aggregate,
    externalSystem: externalSystem ?? this.externalSystem,
    domainEvent: clearDomainEvent ? null : (domainEvent ?? this.domainEvent),
    outcomes: outcomes ?? this.outcomes,
    hotspots: hotspots ?? this.hotspots,
  );

  /// Sérialise l'étape au format exact du DSL v1.0.
  Map<String, Object?> toJson() => <String, Object?>{
    'step': step,
    if (backlog != null && backlog!.isNotEmpty) 'backlog': backlog!.toJson(),
    if (triggeredBy != null) 'triggered_by': triggeredBy!.toJson(),
    if (policy != null) 'policy': policy!.toJson(),
    if (readModel != null) 'read_model': readModel!.toJson(),
    if (actor.isNotEmpty) 'actor': actor,
    'command': command.toJson(),
    if (aggregate.isNotEmpty) 'aggregate': aggregate,
    if (externalSystem.isNotEmpty) 'external_system': externalSystem,
    if (domainEvent != null) 'domain_event': domainEvent!.toJson(),
    if (outcomes.isNotEmpty)
      'outcomes': [for (final o in outcomes) o.toJson()],
    if (hotspots.isNotEmpty)
      'hotspots': [for (final h in hotspots) h.toJson()],
  };

  /// Désérialise une étape depuis JSON/YAML.
  factory EventStormStep.fromJson(Object? raw, {int fallbackStep = 1}) {
    if (raw is! Map) {
      throw const FormatException('EventStormStep doit être un objet JSON/YAML.');
    }
    final rawStep = raw['step'];
    final stepNum = rawStep is int
        ? rawStep
        : (rawStep is num ? rawStep.toInt() : fallbackStep);
    final rawOutcomes = raw['outcomes'];
    final outcomes = <EventStormOutcome>[
      if (rawOutcomes is List)
        for (var i = 0; i < rawOutcomes.length; i++)
          EventStormOutcome.fromJson(
            rawOutcomes[i],
            fallbackEventId:
                'EVT-${stepNum.toString().padLeft(2, '0')}${String.fromCharCode(65 + (i % 26))}',
          ),
    ];
    final rawEvent = raw['domain_event'] ?? raw['domainEvent'];
    final domainEvent = outcomes.isEmpty && rawEvent != null
        ? EventStormDomainEvent.fromJson(
            rawEvent,
            fallbackId: 'EVT-${stepNum.toString().padLeft(2, '0')}',
          )
        : null;
    final rawHotspots = raw['hotspots'];
    final hotspots = <EventStormHotspot>[
      if (rawHotspots is List)
        for (var i = 0; i < rawHotspots.length; i++)
          EventStormHotspot.fromJson(
            rawHotspots[i],
            fallbackId: 'HS-${(i + 1).toString().padLeft(2, '0')}',
          ),
    ];

    final stepObj = EventStormStep(
      step: stepNum < 1 ? fallbackStep : stepNum,
      backlog: EventStormBacklog.fromJson(raw['backlog']),
      triggeredBy: EventStormTrigger.fromJson(
        raw['triggered_by'] ?? raw['triggeredBy'],
      ),
      policy: EventStormPolicy.fromJson(raw['policy']),
      readModel: EventStormReadModel.fromJson(
        raw['read_model'] ?? raw['readModel'],
      ),
      actor: _str(raw['actor']),
      command: EventStormCommand.fromJson(raw['command']),
      aggregate: _str(raw['aggregate']),
      externalSystem: _str(raw['external_system'] ?? raw['externalSystem']),
      domainEvent: domainEvent,
      outcomes: outcomes,
      hotspots: hotspots,
    );
    stepObj.validate();
    return stepObj;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormStep &&
          other.step == step &&
          other.backlog == backlog &&
          other.triggeredBy == triggeredBy &&
          other.policy == policy &&
          other.readModel == readModel &&
          other.actor == actor &&
          other.command == command &&
          other.aggregate == aggregate &&
          other.externalSystem == externalSystem &&
          other.domainEvent == domainEvent &&
          listEquals(other.outcomes, outcomes) &&
          listEquals(other.hotspots, hotspots);

  @override
  int get hashCode => Object.hash(
    step,
    backlog,
    triggeredBy,
    policy,
    readModel,
    actor,
    command,
    aggregate,
    externalSystem,
    domainEvent,
    Object.hashAll(outcomes),
    Object.hashAll(hotspots),
  );
}

/// Document Event Storming DSL v1.0 correspondant à **un Bounded Context**
/// (persisté en 1 fichier `<id>.es.yaml`).
@immutable
class EventStormDocument {
  /// Construit un document Event Storming immuable.
  EventStormDocument({
    required this.id,
    this.dslVersion = currentDslVersion,
    required this.meta,
    EventStormCatalog? catalog,
    List<EventStormStep> flow = const <EventStormStep>[],
  }) : catalog = catalog ?? EventStormCatalog.empty,
       flow = List<EventStormStep>.unmodifiable(flow);

  /// Version de la grammaire Event Storming DSL supportée.
  static const String currentDslVersion = '1.0';

  /// Identifiant / slug de fichier du Bounded Context (ex. `"gestion-commandes"`).
  final String id;

  /// Version de la grammaire (`"1.0"`).
  final String dslVersion;

  /// Cadre de l'atelier (`meta`).
  final EventStormMeta meta;

  /// Légende du mur (`catalog` : `actors`, `aggregates`, `external_systems`).
  final EventStormCatalog catalog;

  /// Colonne chronologique ordonnée des étapes (`flow[]`).
  final List<EventStormStep> flow;

  /// Nom de fichier YAML canonique (ex. `gestion-commandes.es.yaml`).
  String get fileName => '${_slugify(id)}.es.yaml';

  /// Étapes triées par numéro `step` croissant.
  List<EventStormStep> get sortedSteps {
    final copy = List<EventStormStep>.from(flow)
      ..sort((a, b) => a.step.compareTo(b.step));
    return copy;
  }

  /// Tous les événements domaine émis dans ce Bounded Context (directs + `outcomes`).
  List<EventStormDomainEvent> get allDomainEvents => [
    for (final s in sortedSteps) ...s.emittedEvents,
  ];

  /// Tous les hotspots de ce document avec leur numéro d'étape associé.
  List<({int stepNumber, EventStormHotspot hotspot})> get allHotspots => [
    for (final s in sortedSteps)
      for (final h in s.hotspots) (stepNumber: s.step, hotspot: h),
  ];

  /// Nombre total d'événements domaine émis.
  int get domainEventCount => allDomainEvents.length;

  /// Nombre total de commandes (= nombre d'étapes).
  int get commandCount => flow.length;

  /// Nombre total de politiques réactives.
  int get policyCount => flow.where((s) => s.policy != null).length;

  /// Nombre total de hotspots encore ouverts.
  int get openHotspotCount =>
      flow.fold<int>(0, (sum, s) => sum + s.openHotspotCount);

  /// Recherche une étape par son numéro `step`.
  EventStormStep? findStep(int stepNumber) {
    for (final s in flow) {
      if (s.step == stepNumber) return s;
    }
    return null;
  }

  /// Vérifie les invariants du document Event Storming.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'EventStormDocument.id ne peut pas être vide.',
      );
    }
    if (dslVersion.trim() != currentDslVersion) {
      throw FormatException(
        'Version DSL Event Storming non supportée : "$dslVersion" (attendu "$currentDslVersion").',
      );
    }
    meta.validate();
    catalog.validate();
    final stepNumbers = <int>{};
    for (final s in flow) {
      s.validate();
      if (!stepNumbers.add(s.step)) {
        throw FormatException(
          'Numéro d’étape dupliqué (${s.step}) dans le Bounded Context "${meta.boundedContext}".',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  EventStormDocument copyWith({
    String? id,
    String? dslVersion,
    EventStormMeta? meta,
    EventStormCatalog? catalog,
    List<EventStormStep>? flow,
  }) => EventStormDocument(
    id: id ?? this.id,
    dslVersion: dslVersion ?? this.dslVersion,
    meta: meta ?? this.meta,
    catalog: catalog ?? this.catalog,
    flow: flow ?? this.flow,
  );

  /// Sérialise le document au format **strict** du schéma `es-dsl.schema.json`
  /// (`{"event_storming": {...}}`, sans aucune propriété supplémentaire).
  Map<String, Object?> toDslJson() => <String, Object?>{
    'event_storming': <String, Object?>{
      'dsl_version': dslVersion,
      'meta': meta.toJson(),
      if (catalog.isNotEmpty) 'catalog': catalog.toJson(),
      'flow': [for (final s in sortedSteps) s.toJson()],
    },
  };

  /// Sérialise le document pour le stockage JSON interne / contexte IA.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    ...toDslJson(),
  };

  /// Désérialise un document depuis JSON/YAML (accepte `{id?, event_storming: {...}}`
  /// ou la forme aplatie `{id?, dsl_version, meta, catalog, flow}`).
  factory EventStormDocument.fromJson(
    Object? raw, {
    String? idHint,
    String fallbackDomain = 'Domaine métier',
  }) {
    if (raw is! Map) {
      throw const FormatException(
        'EventStormDocument doit être un objet JSON/YAML.',
      );
    }
    final inner = raw['event_storming'] is Map
        ? raw['event_storming'] as Map
        : (raw['eventStorming'] is Map ? raw['eventStorming'] as Map : raw);
    final dslVersion = _str(inner['dsl_version'] ?? inner['dslVersion']);
    final meta = EventStormMeta.fromJson(
      inner['meta'],
      fallbackDomain: fallbackDomain,
      fallbackContext:
          _str(raw['bounded_context'] ?? raw['title'] ?? raw['name']).isNotEmpty
          ? _str(raw['bounded_context'] ?? raw['title'] ?? raw['name'])
          : (idHint ?? 'Contexte métier'),
    );
    final rawId = _str(raw['id']).isNotEmpty
        ? _str(raw['id'])
        : ((idHint != null && idHint.trim().isNotEmpty)
              ? idHint.trim()
              : _slugify(meta.boundedContext));
    final catalog = EventStormCatalog.fromJson(inner['catalog']);
    final rawFlow = inner['flow'];
    final steps = <EventStormStep>[
      if (rawFlow is List)
        for (var i = 0; i < rawFlow.length; i++)
          EventStormStep.fromJson(rawFlow[i], fallbackStep: i + 1),
    ];
    final doc = EventStormDocument(
      id: rawId.isEmpty ? 'contexte-metier' : rawId,
      dslVersion: dslVersion.isEmpty
          ? EventStormDocument.currentDslVersion
          : dslVersion,
      meta: meta,
      catalog: catalog,
      flow: steps,
    );
    doc.validate();
    return doc;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormDocument &&
          other.id == id &&
          other.dslVersion == dslVersion &&
          other.meta == meta &&
          other.catalog == catalog &&
          listEquals(other.flow, flow);

  @override
  int get hashCode =>
      Object.hash(id, dslVersion, meta, catalog, Object.hashAll(flow));
}

/// Conteneur racine immuable de l'étape Event Storming d'un [SpecForgeProject] :
/// regroupe 1 [EventStormDocument] (`.es.yaml`) par Bounded Context.
@immutable
class EventStormingSpec {
  /// Construit un conteneur d'Event Storming multi-Bounded-Contexts.
  EventStormingSpec({
    List<EventStormDocument> documents = const <EventStormDocument>[],
  }) : documents = List<EventStormDocument>.unmodifiable(documents);

  /// Instance vide par défaut.
  static final EventStormingSpec empty = EventStormingSpec();

  /// Documents Event Storming DSL v1.0 (1 document par Bounded Context).
  final List<EventStormDocument> documents;

  /// Vrai si au moins un Bounded Context est modélisé.
  bool get hasContent => documents.isNotEmpty;

  /// Nombre total d'étapes sur l'ensemble des Bounded Contexts.
  int get totalStepCount =>
      documents.fold<int>(0, (sum, d) => sum + d.flow.length);

  /// Nombre total d'événements domaine émis.
  int get totalEventCount =>
      documents.fold<int>(0, (sum, d) => sum + d.domainEventCount);

  /// Nombre total de commandes (= nombre d'étapes).
  int get totalCommandCount => totalStepCount;

  /// Nombre total de politiques réactives.
  int get totalPolicyCount =>
      documents.fold<int>(0, (sum, d) => sum + d.policyCount);

  /// Nombre total de hotspots (ouverts + résolus).
  int get totalHotspotCount =>
      documents.fold<int>(0, (sum, d) => sum + d.allHotspots.length);

  /// Nombre total de hotspots encore ouverts.
  int get openHotspotCount =>
      documents.fold<int>(0, (sum, d) => sum + d.openHotspotCount);

  /// Tous les hotspots de tous les documents avec contexte et étape.
  List<
    ({
      EventStormDocument document,
      int stepNumber,
      EventStormHotspot hotspot,
    })
  >
  get allHotspots => [
    for (final doc in documents)
      for (final entry in doc.allHotspots)
        (
          document: doc,
          stepNumber: entry.stepNumber,
          hotspot: entry.hotspot,
        ),
  ];

  /// Recherche un document par identifiant, nom de fichier ou nom de Bounded Context.
  EventStormDocument? findDocument(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final doc in documents) {
      if (doc.id.toLowerCase() == needle ||
          doc.fileName.toLowerCase() == needle ||
          doc.meta.boundedContext.toLowerCase() == needle) {
        return doc;
      }
    }
    return null;
  }

  /// Vérifie les invariants de l'ensemble des documents Event Storming.
  void validate() {
    final ids = <String>{};
    for (final doc in documents) {
      doc.validate();
      if (!ids.add(doc.id)) {
        throw FormatException(
          'Document Event Storming dupliqué (id: ${doc.id}).',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  EventStormingSpec copyWith({List<EventStormDocument>? documents}) =>
      EventStormingSpec(documents: documents ?? this.documents);

  /// Sérialise l'Event Storming en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (documents.isNotEmpty)
      'documents': [for (final doc in documents) doc.toJson()],
  };

  /// Désérialise un [EventStormingSpec] depuis JSON (`null` -> [empty]).
  ///
  /// Supporte :
  /// 1. Le format natif DSL v1.0 (`{"documents": [...]}` ou `{"event_storming": {...}}`) ;
  /// 2. La migration transparente de l'ancien format (`{"boundedContexts": [...], "flows": [...]}`).
  factory EventStormingSpec.fromJson(Object? raw) {
    if (raw == null) return EventStormingSpec.empty;
    if (raw is List) {
      final docs = [
        for (final item in raw)
          if (item is Map &&
              (item.containsKey('event_storming') ||
                  item.containsKey('dsl_version') ||
                  item.containsKey('flow')))
            EventStormDocument.fromJson(item)
          else
            _migrateLegacyBoardToDocument(item, const <String, String>{}),
      ];
      final spec = EventStormingSpec(documents: docs);
      spec.validate();
      return spec;
    }
    if (raw is! Map) {
      throw const FormatException('EventStormingSpec doit être un objet JSON.');
    }

    // Cas 1 : document DSL v1.0 unique à la racine (`{"event_storming": {...}}`).
    if (raw.containsKey('event_storming') ||
        raw.containsKey('dsl_version') ||
        raw.containsKey('flow')) {
      final doc = EventStormDocument.fromJson(raw);
      final spec = EventStormingSpec(documents: [doc]);
      spec.validate();
      return spec;
    }

    // Cas 2 : conteneur natif multi-documents (`{"documents": [...]}`).
    if (raw['documents'] is List) {
      final docs = <EventStormDocument>[];
      final usedIds = <String>{};
      for (final item in raw['documents'] as List) {
        var doc = EventStormDocument.fromJson(item);
        if (!usedIds.add(doc.id)) {
          var suffix = 2;
          while (!usedIds.add('${doc.id}-$suffix')) {
            suffix++;
          }
          doc = doc.copyWith(id: '${doc.id}-$suffix');
        }
        docs.add(doc);
      }
      final spec = EventStormingSpec(documents: docs);
      spec.validate();
      return spec;
    }

    // Cas 3 : migration transparente de l'ancien format (`boundedContexts` + `flows`).
    if (raw['boundedContexts'] is List ||
        raw['flows'] is List ||
        raw['boards'] is List) {
      return _migrateLegacySpec(raw);
    }

    return EventStormingSpec.empty;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormingSpec && listEquals(other.documents, documents);

  @override
  int get hashCode => Object.hashAll(documents);
}

// ---------------------------------------------------------------------------
// Migration rétrocompatible de l'ancien modèle graphe (nodes/links) -> DSL v1.0
// ---------------------------------------------------------------------------

EventStormingSpec _migrateLegacySpec(Map<Object?, Object?> raw) {
  final bcNamesById = <String, String>{};
  final rawBcs = raw['boundedContexts'];
  if (rawBcs is List) {
    for (final item in rawBcs) {
      if (item is Map) {
        final id = _str(item['id']);
        final name = _str(item['name'] ?? item['title']);
        if (id.isNotEmpty && name.isNotEmpty) {
          bcNamesById[id] = name;
        }
      }
    }
  }

  final rawFlows = raw['flows'] ?? raw['boards'];
  final docs = <EventStormDocument>[];
  final usedIds = <String>{};

  if (rawFlows is List && rawFlows.isNotEmpty) {
    for (final item in rawFlows) {
      var doc = _migrateLegacyBoardToDocument(item, bcNamesById);
      if (!usedIds.add(doc.id)) {
        var suffix = 2;
        while (!usedIds.add('${doc.id}-$suffix')) {
          suffix++;
        }
        doc = doc.copyWith(id: '${doc.id}-$suffix');
      }
      docs.add(doc);
    }
  } else if (bcNamesById.isNotEmpty) {
    for (final entry in bcNamesById.entries) {
      final slug = _slugify(entry.value);
      final id = usedIds.add(slug) ? slug : _slugify(entry.key);
      docs.add(
        EventStormDocument(
          id: id.isEmpty ? 'contexte-metier' : id,
          meta: EventStormMeta(
            domain: 'Domaine métier',
            boundedContext: entry.value,
            date: _todayIsoDate(),
          ),
        ),
      );
    }
  }

  final spec = EventStormingSpec(documents: docs);
  spec.validate();
  return spec;
}

EventStormDocument _migrateLegacyBoardToDocument(
  Object? rawBoard,
  Map<String, String> bcNamesById,
) {
  final map = rawBoard is Map ? rawBoard : const <Object?, Object?>{};
  final title = _str(map['title'] ?? map['name']).isNotEmpty
      ? _str(map['title'] ?? map['name'])
      : 'Contexte métier';
  final bcIds = _stringList(map['boundedContextIds']);
  final bcName = bcIds.isNotEmpty && bcNamesById.containsKey(bcIds.first)
      ? bcNamesById[bcIds.first]!
      : title;
  final rawNodes = map['nodes'] is List ? map['nodes'] as List : const [];

  final sortedNodes = <Map<Object?, Object?>>[
    for (final n in rawNodes)
      if (n is Map) n,
  ]..sort((a, b) {
      final sa = (a['sequenceOrder'] as num?)?.toInt() ?? 0;
      final sb = (b['sequenceOrder'] as num?)?.toInt() ?? 0;
      return sa.compareTo(sb);
    });

  final actors = <EventStormCatalogItem>[];
  final aggregates = <EventStormCatalogItem>[];
  final actorIdByTitle = <String, String>{};
  final aggIdByTitle = <String, String>{};

  String registerActor(String name) {
    final key = name.trim().toLowerCase();
    return actorIdByTitle.putIfAbsent(key, () {
      final id = _uniqueCatalogId(
        'ACT',
        name,
        {for (final a in actors) a.id},
      );
      actors.add(
        EventStormCatalogItem(
          id: id,
          name: name.trim(),
          type: EventStormActorType.human,
        ),
      );
      return id;
    });
  }

  String registerAggregate(String name) {
    final key = name.trim().toLowerCase();
    return aggIdByTitle.putIfAbsent(key, () {
      final id = _uniqueCatalogId(
        'AGG',
        name,
        {for (final a in aggregates) a.id},
      );
      aggregates.add(EventStormCatalogItem(id: id, name: name.trim()));
      return id;
    });
  }

  final reqs = _stringList(map['requirementIds']);
  final storyRef = reqs.isNotEmpty ? reqs.first : '';
  final epicRef = _str(map['code']);

  String pendingActor = '';
  EventStormReadModel? pendingReadModel;
  EventStormPolicy? pendingPolicy;
  EventStormCommand? pendingCommand;
  String pendingAggregate = '';
  final pendingHotspots = <EventStormHotspot>[];
  final steps = <EventStormStep>[];
  String? lastEventId;
  var evtCounter = 0;
  var hsCounter = 0;

  void flushStep({EventStormDomainEvent? explicitEvent}) {
    evtCounter++;
    final stepNum = steps.length + 1;
    final evt =
        explicitEvent ??
        EventStormDomainEvent(
          id: 'EVT-${evtCounter.toString().padLeft(2, '0')}',
          name: pendingCommand != null
              ? '${pendingCommand!.name} (effectué)'
              : 'Événement métier produit',
        );
    final cmd =
        pendingCommand ??
        EventStormCommand(name: 'Exécuter ${evt.name}');
    steps.add(
      EventStormStep(
        step: stepNum,
        backlog: (epicRef.isNotEmpty || storyRef.isNotEmpty) && stepNum == 1
            ? EventStormBacklog(epic: epicRef, story: storyRef)
            : null,
        triggeredBy: lastEventId != null && pendingPolicy != null
            ? EventStormTrigger.single(lastEventId!)
            : null,
        policy: pendingPolicy,
        readModel: pendingReadModel,
        actor: pendingActor,
        command: cmd,
        aggregate: pendingAggregate,
        domainEvent: evt,
        hotspots: List<EventStormHotspot>.from(pendingHotspots),
      ),
    );
    lastEventId = evt.id;
    pendingActor = '';
    pendingReadModel = null;
    pendingPolicy = null;
    pendingCommand = null;
    pendingAggregate = '';
    pendingHotspots.clear();
  }

  for (final n in sortedNodes) {
    final kind = _str(n['kind'] ?? n['type']).toLowerCase();
    final nodeTitle = _str(n['title'] ?? n['name']);
    if (nodeTitle.isEmpty) continue;
    final fields = _stringList(n['payloadFields'] ?? n['fields']);

    if (kind == 'actor') {
      pendingActor = registerActor(nodeTitle);
    } else if (kind == 'readmodel' || kind == 'read_model') {
      pendingReadModel = EventStormReadModel(name: nodeTitle, fields: fields);
    } else if (kind == 'policy') {
      if (pendingCommand != null) flushStep();
      final desc = _str(n['description']);
      pendingPolicy = EventStormPolicy(
        name: nodeTitle,
        rule: desc.isNotEmpty ? desc : nodeTitle,
      );
    } else if (kind == 'command') {
      if (pendingCommand != null) flushStep();
      pendingCommand = EventStormCommand(name: nodeTitle, payload: fields);
    } else if (kind == 'aggregate') {
      pendingAggregate = registerAggregate(nodeTitle);
    } else if (kind == 'domainevent' || kind == 'domain_event') {
      evtCounter++;
      final code = _str(n['code']);
      final validEvtId = RegExp(r'^EVT-[0-9]+[A-Z]?$').hasMatch(code)
          ? code
          : 'EVT-${evtCounter.toString().padLeft(2, '0')}';
      flushStep(
        explicitEvent: EventStormDomainEvent(
          id: validEvtId,
          name: nodeTitle,
          data: fields,
        ),
      );
    } else if (kind == 'hotspot') {
      hsCounter++;
      final code = _str(n['code']);
      final validHsId = RegExp(r'^HS-[0-9]+$').hasMatch(code)
          ? code
          : 'HS-${hsCounter.toString().padLeft(2, '0')}';
      final hs = EventStormHotspot(
        id: validHsId,
        question: nodeTitle,
        severity: EventStormHotspotSeverity.medium,
        status: n['resolved'] == true
            ? EventStormHotspotStatus.resolved
            : EventStormHotspotStatus.open,
      );
      if (steps.isNotEmpty && pendingCommand == null) {
        final last = steps.removeLast();
        steps.add(last.copyWith(hotspots: [...last.hotspots, hs]));
      } else {
        pendingHotspots.add(hs);
      }
    }
  }

  if (pendingCommand != null ||
      pendingPolicy != null ||
      pendingHotspots.isNotEmpty) {
    flushStep();
  }

  final rawId = _str(map['id']);
  final docId = _slugify(bcName).isNotEmpty
      ? _slugify(bcName)
      : (rawId.isNotEmpty ? _slugify(rawId) : 'contexte-metier');

  return EventStormDocument(
    id: docId,
    meta: EventStormMeta(
      domain: title,
      boundedContext: bcName,
      format: EventStormFormat.processModeling,
      date: _todayIsoDate(),
    ),
    catalog: EventStormCatalog(actors: actors, aggregates: aggregates),
    flow: steps,
  );
}

// ---------------------------------------------------------------------------
// Helpers internes
// ---------------------------------------------------------------------------

EventStormCatalogItem? _findCatalogItem(
  List<EventStormCatalogItem> items,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final item in items) {
    if (item.id.toLowerCase() == needle || item.name.toLowerCase() == needle) {
      return item;
    }
  }
  return null;
}

String _str(Object? raw) => raw == null ? '' : '$raw'.trim();

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}

String _todayIsoDate() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _foldAccents(String input) {
  const map = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ç': 'c',
    'À': 'A',
    'Â': 'A',
    'Ä': 'A',
    'É': 'E',
    'È': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Î': 'I',
    'Ï': 'I',
    'Ô': 'O',
    'Ö': 'O',
    'Ù': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ç': 'C',
  };
  final buf = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

String _slugify(String raw) {
  final folded = _foldAccents(raw).toLowerCase();
  final cleaned = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'contexte-metier' : cleaned;
}

String _makeCatalogId(String prefix, String name) {
  final token = _foldAccents(name)
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '$prefix-${token.isEmpty ? 'ITEM' : token}';
}

String _uniqueCatalogId(String prefix, String name, Set<String> usedIds) {
  final base = _makeCatalogId(prefix, name);
  if (!usedIds.contains(base)) return base;
  var idx = 2;
  while (usedIds.contains('${base}_$idx')) {
    idx++;
  }
  return '${base}_$idx';
}
