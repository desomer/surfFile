/// Modèles immuables d'Event Storming (Process Modeling DDD) :
/// [EventStormingSpec], [EventStormBoard], [EventStormNode],
/// [EventStormLink] et [EventStormBoundedContext].
library;

import 'package:flutter/foundation.dart';

/// Catégorie d'un post-it Event Storming (7 couleurs du Process Modeling).
enum EventStormNodeKind {
  /// Orange : fait métier immuable survenu dans le passé (ex. `CommandeValidee`).
  domainEvent(
    'Événement',
    'EVT',
    'Fait métier accompli formulé au passé (Orange)',
  ),

  /// Bleu : intention ou action déclenchée par un acteur ou une politique (ex. `ValiderCommande`).
  command(
    'Commande',
    'CMD',
    'Intention ou action métier déclenchée (Bleu)',
  ),

  /// Jaune (petit) : persona, rôle ou système externe initiant une commande.
  actor(
    'Acteur',
    'ACT',
    'Persona ou système externe initiateur (Jaune)',
  ),

  /// Ambre / Jaune (grand) : agrégat ou système recevant les commandes et émettant les événements.
  aggregate(
    'Agrégat',
    'AGG',
    'Agrégat, entité ou système portant les invariants (Ambre)',
  ),

  /// Lilas / Violet : règle réactive automatique (« Quand Événement, alors Commande »).
  policy(
    'Politique',
    'POL',
    'Réaction automatique « Quand…, alors… » (Lilas)',
  ),

  /// Vert : projection, vue ou modèle de lecture nécessaire à la prise de décision.
  readModel(
    'Read Model',
    'RMD',
    'Vue ou projection d’aide à la décision (Vert)',
  ),

  /// Rouge / Rose : zone d'ombre, goulot d'étranglement, risque ou question ouverte.
  hotspot(
    'Hotspot',
    'HOT',
    'Zone d’ombre, blocage ou question à lever (Rouge)',
  );

  /// Construit une catégorie de carte Event Storming.
  const EventStormNodeKind(this.label, this.shortCode, this.description);

  /// Libellé lisible en français.
  final String label;

  /// Trigamme compact (`EVT`, `CMD`, `ACT`, `AGG`, `POL`, `RMD`, `HOT`).
  final String shortCode;

  /// Description explicative de la sémantique Event Storming.
  final String description;

  /// Résout une catégorie depuis JSON ou un alias courant généré par un LLM.
  static EventStormNodeKind fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
      switch (norm) {
        case 'domainevent':
        case 'event':
        case 'evenement':
        case 'evt':
        case 'pivot':
        case 'pivotalevent':
          return EventStormNodeKind.domainEvent;
        case 'command':
        case 'cmd':
        case 'commande':
        case 'action':
          return EventStormNodeKind.command;
        case 'actor':
        case 'act':
        case 'acteur':
        case 'persona':
        case 'user':
        case 'utilisateur':
          return EventStormNodeKind.actor;
        case 'aggregate':
        case 'agg':
        case 'agregat':
        case 'system':
        case 'systeme':
        case 'entity':
        case 'entite':
          return EventStormNodeKind.aggregate;
        case 'policy':
        case 'pol':
        case 'politique':
        case 'reactor':
        case 'processmanager':
        case 'automation':
          return EventStormNodeKind.policy;
        case 'readmodel':
        case 'rmd':
        case 'view':
        case 'vue':
        case 'projection':
        case 'query':
          return EventStormNodeKind.readModel;
        case 'hotspot':
        case 'hot':
        case 'question':
        case 'risk':
        case 'risque':
        case 'issue':
        case 'blocker':
          return EventStormNodeKind.hotspot;
      }
    }
    return EventStormNodeKind.domainEvent;
  }
}

/// Nature d'une liaison orientée entre deux cartes d'un flux Event Storming.
enum EventStormLinkKind {
  /// Un acteur ou une politique déclenche une commande.
  triggers('Déclenche'),

  /// Une commande est traitée par un agrégat ou système.
  handles('Traite'),

  /// Un agrégat ou une commande émet un événement domaine.
  emits('Émet'),

  /// Une politique réagit à un événement domaine.
  reactsTo('Réagit à'),

  /// Un événement alimente un Read Model ou un Read Model éclaire un acteur.
  informs('Alimente'),

  /// Lien vers ou depuis un Hotspot / zone d'ombre.
  flags('Signale');

  /// Construit un type de liaison.
  const EventStormLinkKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un type de liaison depuis JSON.
  static EventStormLinkKind fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
      switch (norm) {
        case 'triggers':
        case 'trigger':
        case 'declenche':
          return EventStormLinkKind.triggers;
        case 'handles':
        case 'handle':
        case 'traite':
          return EventStormLinkKind.handles;
        case 'emits':
        case 'emit':
        case 'emet':
        case 'produces':
          return EventStormLinkKind.emits;
        case 'reactsto':
        case 'reacts':
        case 'reagit':
        case 'listens':
          return EventStormLinkKind.reactsTo;
        case 'informs':
        case 'inform':
        case 'alimente':
        case 'updates':
        case 'projects':
          return EventStormLinkKind.informs;
        case 'flags':
        case 'flag':
        case 'signale':
        case 'question':
          return EventStormLinkKind.flags;
      }
    }
    return EventStormLinkKind.triggers;
  }
}

/// Bounded Context (contexte borné DDD) regroupant des cartes et flux cohérents.
@immutable
class EventStormBoundedContext {
  /// Construit un Bounded Context immuable.
  const EventStormBoundedContext({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
    this.notes = '',
  });

  /// Identifiant technique unique.
  final String id;

  /// Code court séquentiel (`BC-001`, `BC-002`...).
  final String code;

  /// Nom métier du contexte borné (ex. `Facturation`, `Logistique`).
  final String name;

  /// Responsabilité métier principale du contexte borné.
  final String description;

  /// Notes de frontières ou d'intégration avec d'autres contextes.
  final String notes;

  /// Vérifie les invariants du contexte borné.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'EventStormBoundedContext.id ne peut pas être vide.',
      );
    }
    if (code.trim().isEmpty) {
      throw const FormatException(
        'EventStormBoundedContext.code ne peut pas être vide.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'EventStormBoundedContext.name ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormBoundedContext copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? notes,
  }) => EventStormBoundedContext(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
    notes: notes ?? this.notes,
  );

  /// Sérialise le contexte borné en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    if (notes.isNotEmpty) 'notes': notes,
  };

  /// Désérialise un contexte borné depuis JSON.
  factory EventStormBoundedContext.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'EventStormBoundedContext doit être un objet JSON.',
      );
    }
    final name =
        ((raw['name'] ?? raw['title'] ?? raw['label']) as String?)?.trim() ??
        '';
    final effectiveName = name.isEmpty ? 'Contexte métier' : name;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final ctx = EventStormBoundedContext(
      id: rawId.isEmpty ? 'bc_${effectiveName.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'BC-001' : rawCode,
      name: effectiveName,
      description: (raw['description'] as String?)?.trim() ?? '',
      notes: (raw['notes'] as String?)?.trim() ?? '',
    );
    ctx.validate();
    return ctx;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormBoundedContext &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.description == description &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(id, code, name, description, notes);
}

/// Carte post-it unitaire sur la frise chronologique d'un flux Event Storming.
@immutable
class EventStormNode {
  /// Construit une carte Event Storming immuable.
  EventStormNode({
    required this.id,
    required this.kind,
    required this.title,
    this.code = '',
    this.description = '',
    this.sequenceOrder = 0,
    this.boundedContextId = '',
    this.isPivotal = false,
    this.actorId = '',
    this.targetObjectId = '',
    this.linkedRuleId = '',
    List<String> payloadFields = const <String>[],
    this.resolved = false,
    this.answer = '',
    this.notes = '',
  }) : payloadFields = List<String>.unmodifiable(payloadFields);

  /// Identifiant technique unique du nœud dans le flux.
  final String id;

  /// Code optionnel (ex. `EVT-01`, `CMD-01`).
  final String code;

  /// Couleur / type de post-it Event Storming.
  final EventStormNodeKind kind;

  /// Libellé principal du post-it (au passé pour un événement, à l'impératif pour une commande).
  final String title;

  /// Détail métier, précondition ou description de la carte.
  final String description;

  /// Position chronologique sur la frise (de gauche à droite).
  final int sequenceOrder;

  /// Identifiant éventuel du [EventStormBoundedContext] auquel appartient cette carte.
  final String boundedContextId;

  /// Indique un événement pivot structurant (frontière de phase ou de contexte).
  final bool isPivotal;

  /// Identifiant éventuel du persona (`SpecPersona.id`) lié à un acteur ou une commande.
  final String actorId;

  /// Identifiant ou nom technique éventuel de l'objet métier (`BusinessObjectSpec`) cible.
  final String targetObjectId;

  /// Identifiant ou code éventuel de la règle de gestion `RG-xxx` issue d'une politique.
  final String linkedRuleId;

  /// Attributs ou données clés transportés (pour Événement, Commande ou Read Model).
  final List<String> payloadFields;

  /// Pour un `hotspot` : indique si la zone d'ombre est résolue.
  final bool resolved;

  /// Pour un `hotspot` : décision ou réponse retenue.
  final String answer;

  /// Notes complémentaires.
  final String notes;

  /// Vérifie les invariants de la carte.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('EventStormNode.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'EventStormNode.title ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormNode copyWith({
    String? id,
    String? code,
    EventStormNodeKind? kind,
    String? title,
    String? description,
    int? sequenceOrder,
    String? boundedContextId,
    bool? isPivotal,
    String? actorId,
    String? targetObjectId,
    String? linkedRuleId,
    List<String>? payloadFields,
    bool? resolved,
    String? answer,
    String? notes,
  }) => EventStormNode(
    id: id ?? this.id,
    code: code ?? this.code,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    description: description ?? this.description,
    sequenceOrder: sequenceOrder ?? this.sequenceOrder,
    boundedContextId: boundedContextId ?? this.boundedContextId,
    isPivotal: isPivotal ?? this.isPivotal,
    actorId: actorId ?? this.actorId,
    targetObjectId: targetObjectId ?? this.targetObjectId,
    linkedRuleId: linkedRuleId ?? this.linkedRuleId,
    payloadFields: payloadFields ?? this.payloadFields,
    resolved: resolved ?? this.resolved,
    answer: answer ?? this.answer,
    notes: notes ?? this.notes,
  );

  /// Sérialise la carte en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (code.isNotEmpty) 'code': code,
    'kind': kind.name,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    'sequenceOrder': sequenceOrder,
    if (boundedContextId.isNotEmpty) 'boundedContextId': boundedContextId,
    if (isPivotal) 'isPivotal': isPivotal,
    if (actorId.isNotEmpty) 'actorId': actorId,
    if (targetObjectId.isNotEmpty) 'targetObjectId': targetObjectId,
    if (linkedRuleId.isNotEmpty) 'linkedRuleId': linkedRuleId,
    if (payloadFields.isNotEmpty) 'payloadFields': payloadFields,
    if (resolved) 'resolved': resolved,
    if (answer.isNotEmpty) 'answer': answer,
    if (notes.isNotEmpty) 'notes': notes,
  };

  /// Désérialise une carte depuis JSON.
  factory EventStormNode.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('EventStormNode doit être un objet JSON.');
    }
    final kind = EventStormNodeKind.fromJson(raw['kind'] ?? raw['type']);
    final title =
        ((raw['title'] ?? raw['name'] ?? raw['label'] ?? raw['question'])
                as String?)
            ?.trim() ??
        '';
    final effectiveTitle = title.isEmpty ? kind.label : title;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final answer = (raw['answer'] as String?)?.trim() ?? '';
    final rawResolved = raw['resolved'];
    final resolved = rawResolved is bool ? rawResolved : answer.isNotEmpty;
    final rawSeq = raw['sequenceOrder'] ?? raw['order'] ?? raw['step'];
    final sequenceOrder = rawSeq is int
        ? rawSeq
        : (rawSeq is num ? rawSeq.toInt() : 0);

    final node = EventStormNode(
      id: rawId.isEmpty
          ? 'esn_${kind.shortCode.toLowerCase()}_${effectiveTitle.hashCode.abs()}'
          : rawId,
      code: (raw['code'] as String?)?.trim() ?? '',
      kind: kind,
      title: effectiveTitle,
      description: (raw['description'] as String?)?.trim() ?? '',
      sequenceOrder: sequenceOrder < 0 ? 0 : sequenceOrder,
      boundedContextId:
          (raw['boundedContextId'] as String?)?.trim() ??
          (raw['contextId'] as String?)?.trim() ??
          '',
      isPivotal: raw['isPivotal'] == true || raw['pivotal'] == true,
      actorId: (raw['actorId'] as String?)?.trim() ?? '',
      targetObjectId: (raw['targetObjectId'] as String?)?.trim() ?? '',
      linkedRuleId: (raw['linkedRuleId'] as String?)?.trim() ?? '',
      payloadFields: _stringList(raw['payloadFields'] ?? raw['fields']),
      resolved: resolved,
      answer: answer,
      notes: (raw['notes'] as String?)?.trim() ?? '',
    );
    node.validate();
    return node;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormNode &&
          other.id == id &&
          other.code == code &&
          other.kind == kind &&
          other.title == title &&
          other.description == description &&
          other.sequenceOrder == sequenceOrder &&
          other.boundedContextId == boundedContextId &&
          other.isPivotal == isPivotal &&
          other.actorId == actorId &&
          other.targetObjectId == targetObjectId &&
          other.linkedRuleId == linkedRuleId &&
          listEquals(other.payloadFields, payloadFields) &&
          other.resolved == resolved &&
          other.answer == answer &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    kind,
    title,
    description,
    sequenceOrder,
    boundedContextId,
    isPivotal,
    actorId,
    targetObjectId,
    linkedRuleId,
    Object.hashAll(payloadFields),
    resolved,
    answer,
    notes,
  );
}

/// Liaison orientée entre deux cartes [EventStormNode] d'un flux.
@immutable
class EventStormLink {
  /// Construit une liaison immuable.
  const EventStormLink({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    this.kind = EventStormLinkKind.triggers,
    this.label = '',
  });

  /// Identifiant unique de la liaison.
  final String id;

  /// Identifiant du nœud source.
  final String fromNodeId;

  /// Identifiant du nœud cible.
  final String toNodeId;

  /// Nature sémantique de la liaison.
  final EventStormLinkKind kind;

  /// Libellé optionnel affiché sur le diagramme Mermaid.
  final String label;

  /// Vérifie les invariants de la liaison.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('EventStormLink.id ne peut pas être vide.');
    }
    if (fromNodeId.trim().isEmpty || toNodeId.trim().isEmpty) {
      throw const FormatException(
        'EventStormLink.fromNodeId et toNodeId ne peuvent pas être vides.',
      );
    }
  }

  /// Retourne une copie modifiée.
  EventStormLink copyWith({
    String? id,
    String? fromNodeId,
    String? toNodeId,
    EventStormLinkKind? kind,
    String? label,
  }) => EventStormLink(
    id: id ?? this.id,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    kind: kind ?? this.kind,
    label: label ?? this.label,
  );

  /// Sérialise la liaison en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fromNodeId': fromNodeId,
    'toNodeId': toNodeId,
    'kind': kind.name,
    if (label.isNotEmpty) 'label': label,
  };

  /// Désérialise une liaison depuis JSON.
  factory EventStormLink.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('EventStormLink doit être un objet JSON.');
    }
    final fromId =
        ((raw['fromNodeId'] ?? raw['from'] ?? raw['source']) as String?)
            ?.trim() ??
        '';
    final toId =
        ((raw['toNodeId'] ?? raw['to'] ?? raw['target']) as String?)?.trim() ??
        '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final link = EventStormLink(
      id: rawId.isEmpty ? 'esl_${fromId}_$toId'.hashCode.abs().toString() : rawId,
      fromNodeId: fromId,
      toNodeId: toId,
      kind: EventStormLinkKind.fromJson(raw['kind']),
      label: (raw['label'] as String?)?.trim() ?? '',
    );
    link.validate();
    return link;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormLink &&
          other.id == id &&
          other.fromNodeId == fromNodeId &&
          other.toNodeId == toNodeId &&
          other.kind == kind &&
          other.label == label;

  @override
  int get hashCode => Object.hash(id, fromNodeId, toNodeId, kind, label);
}

/// Tableau / flux chronologique d'Event Storming (`ES-001`, `ES-002`...).
@immutable
class EventStormBoard {
  /// Construit un flux chronologique immuable.
  EventStormBoard({
    required this.id,
    required this.code,
    required this.title,
    this.description = '',
    List<String> boundedContextIds = const <String>[],
    List<String> requirementIds = const <String>[],
    List<String> useCaseIds = const <String>[],
    List<EventStormNode> nodes = const <EventStormNode>[],
    List<EventStormLink> links = const <EventStormLink>[],
    List<String> refinementNotes = const <String>[],
  }) : boundedContextIds = List<String>.unmodifiable(boundedContextIds),
       requirementIds = List<String>.unmodifiable(requirementIds),
       useCaseIds = List<String>.unmodifiable(useCaseIds),
       nodes = List<EventStormNode>.unmodifiable(nodes),
       links = List<EventStormLink>.unmodifiable(links),
       refinementNotes = List<String>.unmodifiable(refinementNotes);

  /// Identifiant unique du flux.
  final String id;

  /// Code séquentiel (`ES-001`, `ES-002`...).
  final String code;

  /// Nom du processus métier ou scénario exploré.
  final String title;

  /// Contexte ou objectif du flux.
  final String description;

  /// Bounded Contexts traversés par ce flux.
  final List<String> boundedContextIds;

  /// Codes ou identifiants des exigences (`EXF-xxx`) couvertes.
  final List<String> requirementIds;

  /// Identifiants ou titres des cas d'usage (`SpecUseCase`) associés.
  final List<String> useCaseIds;

  /// Cartes post-its composant la frise chronologique.
  final List<EventStormNode> nodes;

  /// Liaisons orientées entre les cartes du flux.
  final List<EventStormLink> links;

  /// Notes de synthèse ou découvertes issues de l'atelier.
  final List<String> refinementNotes;

  /// Cartes triées par [EventStormNode.sequenceOrder] croissant en préservant l'ordre d'insertion.
  List<EventStormNode> get sortedNodes {
    final indexed = nodes.indexed.toList()
      ..sort((a, b) {
        final cmp = a.$2.sequenceOrder.compareTo(b.$2.sequenceOrder);
        return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  /// Nombre d'événements domaine du flux.
  int get domainEventCount =>
      nodes.where((n) => n.kind == EventStormNodeKind.domainEvent).length;

  /// Nombre de commandes du flux.
  int get commandCount =>
      nodes.where((n) => n.kind == EventStormNodeKind.command).length;

  /// Nombre de politiques réactives du flux.
  int get policyCount =>
      nodes.where((n) => n.kind == EventStormNodeKind.policy).length;

  /// Nombre de hotspots encore ouverts.
  int get openHotspotCount => nodes
      .where((n) => n.kind == EventStormNodeKind.hotspot && !n.resolved)
      .length;

  /// Vérifie les invariants du flux et de ses cartes/liaisons.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('EventStormBoard.id ne peut pas être vide.');
    }
    if (code.trim().isEmpty) {
      throw const FormatException(
        'EventStormBoard.code ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'EventStormBoard.title ne peut pas être vide.',
      );
    }
    final nodeIds = <String>{};
    for (final node in nodes) {
      node.validate();
      if (!nodeIds.add(node.id)) {
        throw FormatException('Carte Event Storming dupliquée : ${node.id}');
      }
    }
    final linkIds = <String>{};
    for (final link in links) {
      link.validate();
      if (!linkIds.add(link.id)) {
        throw FormatException('Liaison Event Storming dupliquée : ${link.id}');
      }
    }
  }

  /// Retourne une copie modifiée.
  EventStormBoard copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    List<String>? boundedContextIds,
    List<String>? requirementIds,
    List<String>? useCaseIds,
    List<EventStormNode>? nodes,
    List<EventStormLink>? links,
    List<String>? refinementNotes,
  }) => EventStormBoard(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    description: description ?? this.description,
    boundedContextIds: boundedContextIds ?? this.boundedContextIds,
    requirementIds: requirementIds ?? this.requirementIds,
    useCaseIds: useCaseIds ?? this.useCaseIds,
    nodes: nodes ?? this.nodes,
    links: links ?? this.links,
    refinementNotes: refinementNotes ?? this.refinementNotes,
  );

  /// Sérialise le flux en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    if (boundedContextIds.isNotEmpty) 'boundedContextIds': boundedContextIds,
    if (requirementIds.isNotEmpty) 'requirementIds': requirementIds,
    if (useCaseIds.isNotEmpty) 'useCaseIds': useCaseIds,
    if (nodes.isNotEmpty) 'nodes': [for (final n in nodes) n.toJson()],
    if (links.isNotEmpty) 'links': [for (final l in links) l.toJson()],
    if (refinementNotes.isNotEmpty) 'refinementNotes': refinementNotes,
  };

  /// Désérialise un flux depuis JSON.
  factory EventStormBoard.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('EventStormBoard doit être un objet JSON.');
    }
    final title =
        ((raw['title'] ?? raw['name'] ?? raw['flow']) as String?)?.trim() ?? '';
    final effectiveTitle = title.isEmpty ? 'Flux Event Storming' : title;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final board = EventStormBoard(
      id: rawId.isEmpty ? 'es_${effectiveTitle.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'ES-001' : rawCode,
      title: effectiveTitle,
      description: (raw['description'] as String?)?.trim() ?? '',
      boundedContextIds: _stringList(raw['boundedContextIds']),
      requirementIds: _stringList(raw['requirementIds']),
      useCaseIds: _stringList(raw['useCaseIds']),
      nodes: [
        if (raw['nodes'] is List)
          for (final item in raw['nodes'] as List) EventStormNode.fromJson(item),
      ],
      links: [
        if (raw['links'] is List)
          for (final item in raw['links'] as List) EventStormLink.fromJson(item),
      ],
      refinementNotes: _stringList(raw['refinementNotes']),
    );
    board.validate();
    return board;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormBoard &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.description == description &&
          listEquals(other.boundedContextIds, boundedContextIds) &&
          listEquals(other.requirementIds, requirementIds) &&
          listEquals(other.useCaseIds, useCaseIds) &&
          listEquals(other.nodes, nodes) &&
          listEquals(other.links, links) &&
          listEquals(other.refinementNotes, refinementNotes);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    description,
    Object.hashAll(boundedContextIds),
    Object.hashAll(requirementIds),
    Object.hashAll(useCaseIds),
    Object.hashAll(nodes),
    Object.hashAll(links),
    Object.hashAll(refinementNotes),
  );
}

/// Conteneur racine immuable de l'étape Event Storming d'un [SpecForgeProject].
@immutable
class EventStormingSpec {
  /// Construit un modèle complet d'Event Storming.
  EventStormingSpec({
    List<EventStormBoundedContext> boundedContexts =
        const <EventStormBoundedContext>[],
    List<EventStormBoard> flows = const <EventStormBoard>[],
  }) : boundedContexts = List<EventStormBoundedContext>.unmodifiable(
         boundedContexts,
       ),
       flows = List<EventStormBoard>.unmodifiable(flows);

  /// Instance vide par défaut (projets sans Event Storming).
  static final EventStormingSpec empty = EventStormingSpec();

  /// Contextes bornés (Bounded Contexts DDD) identifiés pour le projet.
  final List<EventStormBoundedContext> boundedContexts;

  /// Flux chronologiques Event Storming (`ES-001`, `ES-002`...).
  final List<EventStormBoard> flows;

  /// Vrai si au moins un contexte borné ou un flux est renseigné.
  bool get hasContent => boundedContexts.isNotEmpty || flows.isNotEmpty;

  /// Nombre total de cartes across tous les flux.
  int get totalNodeCount =>
      flows.fold<int>(0, (sum, flow) => sum + flow.nodes.length);

  /// Nombre total d'événements domaine.
  int get totalEventCount =>
      flows.fold<int>(0, (sum, flow) => sum + flow.domainEventCount);

  /// Nombre total de commandes.
  int get totalCommandCount =>
      flows.fold<int>(0, (sum, flow) => sum + flow.commandCount);

  /// Nombre total de politiques réactives.
  int get totalPolicyCount =>
      flows.fold<int>(0, (sum, flow) => sum + flow.policyCount);

  /// Nombre total de hotspots encore ouverts.
  int get openHotspotCount =>
      flows.fold<int>(0, (sum, flow) => sum + flow.openHotspotCount);

  /// Recherche un contexte borné par id, code ou nom (insensible à la casse).
  EventStormBoundedContext? findBoundedContext(String idOrCodeOrName) {
    final needle = idOrCodeOrName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final bc in boundedContexts) {
      if (bc.id.toLowerCase() == needle ||
          bc.code.toLowerCase() == needle ||
          bc.name.toLowerCase() == needle) {
        return bc;
      }
    }
    return null;
  }

  /// Vérifie les invariants de l'ensemble de l'Event Storming.
  void validate() {
    final bcIds = <String>{};
    for (final bc in boundedContexts) {
      bc.validate();
      if (!bcIds.add(bc.id)) {
        throw FormatException('Bounded Context dupliqué : ${bc.id}');
      }
    }
    final flowIds = <String>{};
    for (final flow in flows) {
      flow.validate();
      if (!flowIds.add(flow.id)) {
        throw FormatException('Flux Event Storming dupliqué : ${flow.id}');
      }
    }
  }

  /// Retourne une copie modifiée.
  EventStormingSpec copyWith({
    List<EventStormBoundedContext>? boundedContexts,
    List<EventStormBoard>? flows,
  }) => EventStormingSpec(
    boundedContexts: boundedContexts ?? this.boundedContexts,
    flows: flows ?? this.flows,
  );

  /// Sérialise l'Event Storming en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (boundedContexts.isNotEmpty)
      'boundedContexts': [for (final bc in boundedContexts) bc.toJson()],
    if (flows.isNotEmpty) 'flows': [for (final f in flows) f.toJson()],
  };

  /// Désérialise un [EventStormingSpec] depuis JSON (`null` -> [empty]).
  factory EventStormingSpec.fromJson(Object? raw) {
    if (raw == null) return EventStormingSpec.empty;
    if (raw is List) {
      return EventStormingSpec(
        flows: [for (final item in raw) EventStormBoard.fromJson(item)],
      );
    }
    if (raw is! Map) {
      throw const FormatException(
        'EventStormingSpec doit être un objet JSON.',
      );
    }
    final rawFlows = raw['flows'] ?? raw['boards'];
    final spec = EventStormingSpec(
      boundedContexts: [
        if (raw['boundedContexts'] is List)
          for (final item in raw['boundedContexts'] as List)
            EventStormBoundedContext.fromJson(item),
      ],
      flows: [
        if (rawFlows is List)
          for (final item in rawFlows) EventStormBoard.fromJson(item),
      ],
    );
    spec.validate();
    return spec;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventStormingSpec &&
          listEquals(other.boundedContexts, boundedContexts) &&
          listEquals(other.flows, flows);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(boundedContexts), Object.hashAll(flows));
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}
