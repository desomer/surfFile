/// Catalogue DSL d'un domaine et métadonnées des entrées éditées dans l'arbre.
library;

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;
import 'package:super_schema_dsl/super_schema_dsl.dart';
import 'package:yaml/yaml.dart';

import 'business_object_spec.dart';
import 'domain_layer_spec.dart';
import 'spec_stage_chat.dart';

/// Avancement d'une étape du contrat.
enum ContractStatus { pending, inProgress, done }

/// Étapes représentées par les quatre indicateurs dans l'arbre.
enum ContractStage { design, validation, code, delivery }

/// Propriétés qui ne font pas partie de la syntaxe compacte `nom: type`.
@immutable
class ContractDetails {
  ContractDetails({
    this.title = '',
    this.version = '0.0.1',
    Map<ContractStage, ContractStatus> states = const {},
  }) : states = Map.unmodifiable(states) {
    if (!versionPattern.hasMatch(version)) {
      throw const FormatException('La version doit être au format x.y.z.');
    }
  }

  static final versionPattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  );
  static final defaults = ContractDetails();
  final String title;
  final String version;
  final Map<ContractStage, ContractStatus> states;

  Map<String, Object?> toJson() => {
    'title': title,
    'version': version,
    'states': {for (final e in states.entries) e.key.name: e.value.name},
  };

  factory ContractDetails.fromJson(Object? raw) {
    if (raw case {
      'title': String title,
      'version': String version,
      'states': Map states,
    }) {
      final parsed = <ContractStage, ContractStatus>{};
      for (final e in states.entries) {
        final stage = ContractStage.values
            .where((s) => s.name == e.key)
            .firstOrNull;
        final status = ContractStatus.values
            .where((s) => s.name == e.value)
            .firstOrNull;
        if (stage == null || status == null) {
          throw const FormatException('État de contrat invalide.');
        }
        parsed[stage] = status;
      }
      return ContractDetails(title: title, version: version, states: parsed);
    }
    throw const FormatException('Métadonnées du contrat invalides.');
  }
}

/// Source YAML, arbre aux ID stables et métadonnées indexées par ID d'entrée.
@immutable
class DomainContracts {
  const DomainContracts._(
    this.source,
    this.groups,
    this.removed,
    this.details, {
    this.objects = const {},
    this.chats = const {},
    this.domainLayers = const {},
    this.domainLayerChats = const {},
  });

  static const types = {
    'model',
    'part',
    'component',
    'createxdto',
    'updatexdto',
    'xresponsedto',
    'xlistitemdto',
    'xquerydto',
    'eventxpayloaddto',
    'eventxenvelopedto',
    'flatfile',
  };
  static final empty = parse('models:\n\ncomponents:\n\ndto:\n\nmessage:\n');
  final String source;

  /// Rubriques du DSL ; [patch] conserve l'ID des entrées déplacées.
  final List<JsonNode> groups;

  /// Sous-arbres supprimés ([JsonModel.removedNodes]) : un bloc coupé puis
  /// recollé retrouve son ID, donc ses métadonnées.
  final List<JsonNode> removed;

  /// Titre, version et états indexés par [JsonNode.id].
  final Map<String, ContractDetails> details;

  /// Détail (attributs) de chaque modèle, indexé par [JsonNode.id] : il suit
  /// l'entrée déplacée, renommée ou recollée comme [details].
  final Map<String, BusinessObjectSpec> objects;

  /// Historique du chat IA de chaque modèle, indexé par [JsonNode.id].
  final Map<String, List<SpecChatMessage>> chats;

  /// Spécification de la couche Domain (Architecture Hexagonale) de chaque entrée,
  /// indexée par [JsonNode.id].
  final Map<String, HexagonalDomainLayerSpec> domainLayers;

  /// Historique du chat IA de la couche Domain de chaque entrée, indexé par [JsonNode.id].
  final Map<String, List<SpecChatMessage>> domainLayerChats;

  static Yaml2JsonSchemasParser get _parser =>
      Yaml2JsonSchemasParser(externalTypes: types);

  /// Nouveau catalogue sans métadonnées : chaque entrée reçoit un nouvel ID.
  static DomainContracts parse(String source) {
    final model = _parser.model('contracts', source);
    return _publish(source, model.nodes, model.removedNodes, const {});
  }

  /// Nom technique DSL d'une entrée (son nom s'il est déjà un identifiant valide).
  static String technicalNameOf(JsonNode entry) =>
      BusinessAttribute.isValidDslIdentifier(entry.name)
      ? entry.name
      : BusinessAttribute.toPascalCaseDslIdentifier(entry.name);

  /// Autres entrées du domaine que [entry] peut référencer, indexées par ID,
  /// avec un nom technique unique (préfixé par la rubrique en cas d'homonyme).
  Map<String, String> referenceTargetsOf(JsonNode entry) {
    final used = {technicalNameOf(entry)};
    final targets = <String, String>{};
    for (final group in groups) {
      for (final other in group.children) {
        if (other.id == entry.id) continue;
        var name = technicalNameOf(other);
        if (!used.add(name)) {
          final base = BusinessAttribute.normalizeDslIdentifier(
            '${group.name}_$name',
          );
          name = base;
          for (var i = 2; !used.add(name); i++) {
            name = '$base$i';
          }
        }
        targets[other.id] = name;
      }
    }
    return targets;
  }

  /// Détail de [entry] : l'objet stocké, ou un objet vide de même ID. Le nom
  /// technique suit le nom DSL et le nom métier le titre de l'entrée.
  BusinessObjectSpec objectFor(JsonNode entry) {
    final title = details[entry.id]?.title.trim() ?? '';
    final name = title.isEmpty ? entry.name : title;
    final technicalName = technicalNameOf(entry);
    return objects[entry.id]?.copyWith(
          name: name,
          technicalName: technicalName,
        ) ??
        BusinessObjectSpec(
          id: entry.id,
          name: name,
          technicalName: technicalName,
        );
  }

  /// Couche Domain (Architecture Hexagonale) de [entry], ou [HexagonalDomainLayerSpec.empty].
  HexagonalDomainLayerSpec domainLayerFor(JsonNode entry) =>
      domainLayers[entry.id] ?? HexagonalDomainLayerSpec.empty;

  /// Remplace le détail et/ou l'historique du chat de l'entrée [id].
  DomainContracts withModel(
    String id, {
    BusinessObjectSpec? object,
    List<SpecChatMessage>? chat,
  }) {
    if (entryById(id) == null) {
      throw FormatException('Entrée introuvable : $id.');
    }
    if (object != null) {
      if (object.id != id) {
        throw FormatException('Le détail ${object.id} n’appartient pas à $id.');
      }
      object.validate();
    }
    return DomainContracts._(
      source,
      groups,
      removed,
      details,
      objects: Map.unmodifiable({...objects, id: ?(object ?? objects[id])}),
      chats: Map.unmodifiable({
        ...chats,
        id: ?(chat == null
            ? chats[id]
            : List<SpecChatMessage>.unmodifiable(chat)),
      }),
      domainLayers: domainLayers,
      domainLayerChats: domainLayerChats,
    );
  }

  /// Remplace la couche Domain et/ou son historique de chat IA pour l'entrée [id].
  DomainContracts withDomainLayer(
    String id, {
    HexagonalDomainLayerSpec? layer,
    List<SpecChatMessage>? chat,
  }) {
    if (entryById(id) == null) {
      throw FormatException('Entrée introuvable : $id.');
    }
    layer?.validate();
    final nextLayers = <String, HexagonalDomainLayerSpec>{...domainLayers};
    if (layer != null) {
      if (layer.isEmpty) {
        nextLayers.remove(id);
      } else {
        nextLayers[id] = layer;
      }
    }
    return DomainContracts._(
      source,
      groups,
      removed,
      details,
      objects: objects,
      chats: chats,
      domainLayers: Map.unmodifiable(nextLayers),
      domainLayerChats: Map.unmodifiable({
        ...domainLayerChats,
        id: ?(chat == null
            ? domainLayerChats[id]
            : List<SpecChatMessage>.unmodifiable(chat)),
      }),
    );
  }

  /// Applique [next] avec l'algorithme de [JsonModel] : une entrée déplacée
  /// dans une autre rubrique, renommée, retypée ou recollée garde son ID et
  /// ses métadonnées. Parse entièrement avant de publier : une saisie
  /// invalide lève une [FormatException] sans modifier ce document.
  DomainContracts patch(String next, [Map<String, ContractDetails>? details]) {
    final model = JsonModel(
      name: 'contracts',
      json: null,
      nodes: groups,
      removedNodes: removed,
    );
    _parser.patch(model, next);
    return _publish(
      next,
      model.nodes,
      model.removedNodes,
      details ?? this.details,
      objects,
      chats,
      domainLayers,
      domainLayerChats,
    );
  }

  static DomainContracts _publish(
    String source,
    List<JsonNode> groups,
    List<JsonNode> removed,
    Map<String, ContractDetails> details, [
    Map<String, BusinessObjectSpec> objects = const {},
    Map<String, List<SpecChatMessage>> chats = const {},
    Map<String, HexagonalDomainLayerSpec> domainLayers = const {},
    Map<String, List<SpecChatMessage>> domainLayerChats = const {},
  ]) {
    for (final group in groups) {
      if ((group.type != 'object' && group.type != 'null') ||
          group.properties.isNotEmpty) {
        throw FormatException('${group.name} : rubrique attendue.');
      }
      for (final node in group.children) {
        if (!types.contains(node.type) ||
            node.properties.isNotEmpty ||
            node.children.isNotEmpty) {
          throw FormatException(
            '${node.path} : type attendu parmi ${types.join(', ')}.',
          );
        }
      }
    }
    final ids = {
      for (final node in _walk([...groups, ...removed])) node.id,
    };
    Map<String, V> alive<V>(Map<String, V> byId) => Map.unmodifiable({
      for (final entry in byId.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    });
    return DomainContracts._(
      source,
      List.unmodifiable(groups),
      List.unmodifiable(removed),
      alive(details),
      objects: alive(objects),
      chats: alive(chats),
      domainLayers: alive(domainLayers),
      domainLayerChats: alive(domainLayerChats),
    );
  }

  static Iterable<JsonNode> _walk(List<JsonNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* _walk(node.children);
    }
  }

  /// Entrée courante d'ID [id], ou `null` si elle n'existe plus.
  JsonNode? entryById(String? id) => groups
      .expand((group) => group.children)
      .where((node) => node.id == id)
      .firstOrNull;

  /// Ne remplace que le scalaire concerné, sans reformater commentaires ou rubriques.
  DomainContracts edit(JsonNode node, String type, ContractDetails detail) {
    if (entryById(node.id) == null) {
      throw FormatException('Entrée introuvable : ${node.path}.');
    }
    var next = source;
    if (type != node.type) {
      final yaml = loadYamlNode(source);
      final group = yaml is YamlMap ? yaml.nodes[node.parent?.name] : null;
      final value = group is YamlMap ? group.nodes[node.name] : null;
      if (value is! YamlScalar || value.value != node.type) {
        throw FormatException('Modifiez le type de ${node.path} dans le DSL.');
      }
      final span = value.span;
      next = source.replaceRange(span.start.offset, span.end.offset, type);
    }
    return patch(next, {...details, node.id: detail});
  }

  Map<String, Object?> toJson() => {
    'source': source,
    'nodes': [for (final node in groups) _nodeToJson(node)],
    if (removed.isNotEmpty)
      'removed': [for (final node in removed) _nodeToJson(node)],
    'details': {for (final e in details.entries) e.key: e.value.toJson()},
    if (objects.isNotEmpty)
      'objects': {for (final e in objects.entries) e.key: e.value.toJson()},
    if (chats.isNotEmpty)
      'chats': {
        for (final e in chats.entries)
          e.key: [for (final message in e.value) _messageToJson(message)],
      },
    if (domainLayers.isNotEmpty)
      'domainLayers': {
        for (final e in domainLayers.entries)
          if (e.value.isNotEmpty) e.key: e.value.toJson(),
      },
    if (domainLayerChats.isNotEmpty)
      'domainLayerChats': {
        for (final e in domainLayerChats.entries)
          if (e.value.isNotEmpty)
            e.key: [for (final message in e.value) _messageToJson(message)],
      },
  };

  /// Le catalogue est réécrit à chaque saisie : seuls le nom et le type des
  /// pièces jointes sont conservés, pas leur contenu.
  static Map<String, Object?> _messageToJson(SpecChatMessage message) => message
      .copyWith(
        attachments: [
          for (final a in message.attachments)
            VibeChatAttachment(
              name: a.name,
              mimeType: a.mimeType,
              bytes: Uint8List(0),
            ),
        ],
      )
      .toJson();

  static Map<String, Object?> _nodeToJson(JsonNode node) => {
    'id': node.id,
    'name': node.name,
    'type': node.type,
    'value': node.value,
    if (node.children.isNotEmpty)
      'children': [for (final child in node.children) _nodeToJson(child)],
  };

  /// [ids] impose l'unicité ; les sous-arbres supprimés peuvent partager l'ID
  /// d'un nœud sorti avant leur suppression, comme dans [JsonModel].
  static List<JsonNode> _restore(
    Object? raw,
    JsonNode? parent,
    Set<String>? ids,
  ) {
    if (raw is! List) {
      throw const FormatException('Arbre de contrats invalide.');
    }
    final nodes = <JsonNode>[];
    for (final item in raw) {
      if (item case {'id': String id, 'name': String name, 'type': String type}
          when ids?.add(id) ?? true) {
        final node = JsonNode(
          id: id,
          name: name,
          type: type,
          value: item['value'],
          parent: parent,
        );
        node.children.addAll(_restore(item['children'] ?? const [], node, ids));
        nodes.add(node);
      } else {
        throw const FormatException('Nœud de contrat invalide.');
      }
    }
    return nodes;
  }

  // Seuls les scalaires de type des anciens catalogues changent de casse.
  static String _upgradeStoredSource(String source) {
    const legacy = {'XResponseDto', 'eventXEnvelopeDto'};
    if (!legacy.any(source.contains)) return source;
    final YamlNode root;
    try {
      root = loadYamlNode(source);
    } on YamlException catch (error) {
      throw FormatException(error.toString());
    }
    if (root is! YamlMap) return source;
    final edits = <int, YamlScalar>{};
    for (final group in root.nodes.values.whereType<YamlMap>()) {
      for (final scalar in group.nodes.values.whereType<YamlScalar>()) {
        if (legacy.contains(scalar.value)) {
          edits[scalar.span.start.offset] = scalar;
        }
      }
    }
    for (final start in edits.keys.toList()..sort((a, b) => b.compareTo(a))) {
      final scalar = edits[start]!;
      source = source.replaceRange(
        start,
        scalar.span.end.offset,
        (scalar.value as String).toLowerCase(),
      );
    }
    return source;
  }

  factory DomainContracts.fromJson(Object? raw) {
    if (raw case {
      'source': String stored,
      'details': Map<String, dynamic> rawDetails,
    }) {
      final source = _upgradeStoredSource(stored);
      final details = rawDetails.map(
        (key, value) => MapEntry(key, ContractDetails.fromJson(value)),
      );
      final nodes = raw['nodes'];
      if (nodes == null) {
        // Ancien format : métadonnées indexées par chemin `rubrique.nom`.
        final fresh = parse(source);
        return _publish(source, fresh.groups, fresh.removed, {
          for (final node in _walk(fresh.groups)) node.id: ?details[node.path],
        });
      }
      final rawObjects = raw['objects'] ?? const <String, Object?>{};
      final rawChats = raw['chats'] ?? const <String, Object?>{};
      final rawDomainLayers = raw['domainLayers'] ?? const <String, Object?>{};
      final rawDomainLayerChats =
          raw['domainLayerChats'] ?? const <String, Object?>{};
      if (rawObjects is! Map ||
          rawChats is! Map ||
          rawDomainLayers is! Map ||
          rawDomainLayerChats is! Map) {
        throw const FormatException('Détails des modèles invalides.');
      }
      return DomainContracts._(
        source,
        _restore(nodes, null, {}),
        _restore(raw['removed'] ?? const [], null, null),
        details,
        objects: {
          for (final MapEntry(:key, :value) in rawObjects.entries)
            '$key': BusinessObjectSpec.fromJson(value),
        },
        chats: {
          for (final MapEntry(:key, :value) in rawChats.entries)
            '$key': switch (value) {
              List messages => List<SpecChatMessage>.unmodifiable([
                for (final message in messages)
                  SpecChatMessage.fromJson(message),
              ]),
              _ => throw const FormatException(
                'Historique de modèle invalide.',
              ),
            },
        },
        domainLayers: {
          for (final MapEntry(:key, :value) in rawDomainLayers.entries)
            '$key': HexagonalDomainLayerSpec.fromJson(value),
        },
        domainLayerChats: {
          for (final MapEntry(:key, :value) in rawDomainLayerChats.entries)
            '$key': switch (value) {
              List messages => List<SpecChatMessage>.unmodifiable([
                for (final message in messages)
                  SpecChatMessage.fromJson(message),
              ]),
              _ => throw const FormatException(
                'Historique de couche Domain invalide.',
              ),
            },
        },
      ).patch(source);
    }
    throw const FormatException('Catalogue de contrats invalide.');
  }
}
