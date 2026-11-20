/// Parcours d'un document JSON (ou YAML décodé) en un arbre de [JsonNode].
library;

import 'dart:convert';
import 'dart:math';

import 'package:shortid/shortid.dart';
import 'package:yaml/yaml.dart';

/// Nœud d'un document JSON, identifié par un ID court unique.
class JsonNode {
  JsonNode({
    required this.id,
    required this.name,
    required this.type,
    this.value,
    this.parent,
    Map<String, Object?>? properties,
  }) : properties = properties ?? {};

  final String id;

  /// Clé dans l'objet parent, ou `[i]` pour un élément de liste.
  final String name;

  /// Pour un document JSON : `Object`, `Array`, `String`, `Number`,
  /// `Boolean` ou `Null` ; pour un schéma, le type du DSL (voir
  /// `Yaml2JsonSchemasParser`).
  final String type;

  /// Valeur d'origine : objet ou liste pour un conteneur, sinon scalaire.
  final Object? value;

  final JsonNode? parent;
  final List<JsonNode> children = [];

  /// Propriétés JSON Schema du nœud (`required`, `enum`…), complétables
  /// depuis une IHM ; conservées par [JsonModel.patch] tant que le nœud garde
  /// son ID.
  final Map<String, Object?> properties;

  bool get isContainer => value is Map || value is List;

  /// Chemin depuis la racine, par exemple `items[0].name`.
  String get path {
    final parentPath = parent?.path ?? '';
    if (name.startsWith('[') || parentPath.isEmpty) return '$parentPath$name';
    return '$parentPath.$name';
  }

  /// Représentation JSON compatible avec le `SuperTreeView`.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'typeIcon': isContainer || children.isNotEmpty ? 'container' : 'value',
    'description': isContainer ? '' : '${value ?? ''}',
    'isRequired' : true,
    'isSearchable' : true,
    if (properties.isNotEmpty) 'properties': properties,
    'propertiesText': properties.isEmpty ? '' : properties.toString(),
    if (isContainer || children.isNotEmpty)
      'children': [for (final child in children) child.toJson()],
  };
}

/// Structure JSON nommée, décrite par ses nœuds de premier niveau.
class JsonModel {
  JsonModel({
    required this.name,
    required Object? json,
    required List<JsonNode> nodes,
    String Function()? generateId,
    this.maxRemovedNodes = 50,
  }) : _document = json,
       _nodes = List.unmodifiable(nodes),
       _generateId = generateId ?? shortid.generate;

  final String name;
  final String Function() _generateId;
  Object? _document;
  List<JsonNode> _nodes;
  List<JsonNode> _removed = const [];

  /// Nombre maximal de sous-arbres supprimés conservés (les plus anciens
  /// sont oubliés en premier).
  final int maxRemovedNodes;

  /// Document JSON courant.
  Object? get json => _document;

  /// Nœuds de premier niveau (sans parent) ; vide pour un scalaire.
  List<JsonNode> get nodes => _nodes;

  /// Racines des sous-arbres supprimés par les patchs, du plus ancien au plus
  /// récent. Si l'un réapparaît (même ailleurs), [patch] lui rend son ID.
  List<JsonNode> get removedNodes => _removed;

  /// Oublie les nœuds supprimés : un retour recevra de nouveaux ID.
  void clearRemovedNodes() => _removed = const [];

  /// Retrouve un nœud du modèle par son ID.
  JsonNode? nodeById(String id) {
    for (final node in _descendants(nodes)) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// Remplace le contenu par le document [yaml] en conservant au maximum les
  /// ID : un nœud modifié, renommé, déplacé ou réordonné garde le sien ; un
  /// nœud supprimé est mémorisé dans [removedNodes] et retrouve son ID s'il
  /// revient lors d'un patch ultérieur. Seuls les nœuds réellement nouveaux
  /// reçoivent un nouvel ID.
  ///
  /// Lève une [FormatException] si le YAML est invalide ; le modèle reste
  /// alors inchangé.
  void patch(String yaml) {
    final Object? document;
    try {
      document = _plainJson(loadYaml(yaml));
    } on YamlException catch (error) {
      throw FormatException(error.toString());
    }
    _apply(document, [
      for (final (name, value) in _entries(document))
        _Draft.fromValue(name, value, null),
    ], document is List);
  }

  /// Comme [patch], mais avec un arbre déjà construit (par exemple par
  /// `Yaml2JsonSchemasParser`) : les ID et propriétés de [nodes] sont
  /// ignorés au profit de ceux des nœuds retrouvés. [merge] calcule les
  /// propriétés d'un nœud retrouvé (par défaut, celles de l'ancien nœud
  /// complétées par les nouvelles).
  void patchNodes(
    Object? json,
    List<JsonNode> nodes, {
    Map<String, Object?> Function(JsonNode old, JsonNode fresh)? merge,
  }) => _apply(
    json,
    [for (final node in nodes) _Draft.fromNode(node, null)],
    _isListLike(nodes),
    merge: merge,
  );

  void _apply(
    Object? document,
    List<_Draft> roots,
    bool rootIsList, {
    Map<String, Object?> Function(JsonNode old, JsonNode fresh)? merge,
  }) {
    final matcher = _JsonMatcher(
      _nodes,
      roots,
      rootIsList,
      removedRoots: _removed,
    )..run();
    final removed = matcher.unmatchedRoots();
    final kept = removed.length > maxRemovedNodes
        ? removed.sublist(removed.length - maxRemovedNodes)
        : removed;
    final ids = {
      for (final old in matcher.used) old.id,
      for (final node in _descendants(kept)) node.id,
    };

    JsonNode build(_Draft draft, JsonNode? parent) {
      var id = draft.match?.id;
      if (id == null) {
        do {
          id = _generateId();
        } while (!ids.add(id));
      }
      final old = draft.match;
      final source = draft.source;
      final node = JsonNode(
        id: id,
        name: draft.name,
        type: draft.type,
        value: draft.value,
        parent: parent,
        properties: old == null
            ? {...draft.properties}
            : merge != null && source != null
            ? merge(old, source)
            : {...old.properties, ...draft.properties},
      );
      node.children.addAll([
        for (final child in draft.children) build(child, node),
      ]);
      return node;
    }

    _document = document;
    _nodes = List.unmodifiable([
      for (final root in matcher.roots) build(root, null),
    ]);
    _removed = List.unmodifiable(kept);
  }

  static Iterable<JsonNode> _descendants(List<JsonNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* _descendants(node.children);
    }
  }
}

/// Construit un [JsonNode] pour chaque nœud d'un document JSON.
class JsonBrowser {
  JsonBrowser({String Function()? generateId})
    : _generateId = generateId ?? shortid.generate;

  final String Function() _generateId;
  final Map<String, JsonNode> _nodesById = {};

  /// Nœuds du dernier parcours, indexés par ID.
  Map<String, JsonNode> get nodesById => Map.unmodifiable(_nodesById);

  /// Retourne les nœuds de premier niveau de [json] ; un scalaire n'en a pas.
  List<JsonNode> browse(Object? json) {
    _nodesById.clear();
    return _children(json, null);
  }

  /// Nomme [json] dans un [JsonModel] contenant ses nœuds de premier niveau.
  JsonModel model(String name, Object? json) => JsonModel(
    name: name,
    json: json,
    nodes: browse(json),
    generateId: _generateId,
  );

  List<JsonNode> _children(Object? value, JsonNode? parent) => [
    for (final (name, child) in _entries(value)) _node(name, child, parent),
  ];

  JsonNode _node(String name, Object? value, JsonNode? parent) {
    var id = _generateId();
    while (_nodesById.containsKey(id)) {
      id = _generateId();
    }
    final node = JsonNode(
      id: id,
      name: name,
      type: _typeOf(value),
      value: value,
      parent: parent,
    );
    _nodesById[id] = node;
    node.children.addAll(_children(value, node));
    return node;
  }
}

/// Entrées nommées d'un conteneur : clés d'objet ou `[i]` pour une liste.
List<(String, Object?)> _entries(Object? value) => switch (value) {
  Map() => [for (final entry in value.entries) ('${entry.key}', entry.value)],
  List() => [for (var i = 0; i < value.length; i++) ('[$i]', value[i])],
  _ => const [],
};

String _typeOf(Object? value) => switch (value) {
  Map() => 'Object',
  List() => 'Array',
  String() => 'String',
  num() => 'Number',
  bool() => 'Boolean',
  null => 'Null',
  _ => value.runtimeType.toString(),
};

/// Convertit les `YamlMap` / `YamlList` en objets JSON simples.
Object? _plainJson(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final entry in value.entries) '${entry.key}': _plainJson(entry.value),
  },
  List() => [for (final item in value) _plainJson(item)],
  _ => value,
};

/// Empreinte du contenu d'une valeur, indépendante de l'ordre des clés.
String _signature(Object? value) {
  Object? canonical(Object? value) => switch (value) {
    Map() => {
      for (final key in value.keys.map((key) => '$key').toList()..sort())
        key: canonical(value[key]),
    },
    List() => [for (final item in value) canonical(item)],
    _ => value,
  };
  return jsonEncode(canonical(value), toEncodable: (value) => '$value');
}

bool _isListLike(List<JsonNode> nodes) =>
    nodes.isNotEmpty && nodes.every((node) => _isIndex(node.name));

bool _isIndex(String name) => RegExp(r'^\[\d+\]$').hasMatch(name);

int _indexOf(String name) =>
    name.startsWith('[') ? int.parse(name.substring(1, name.length - 1)) : 0;

/// Nœud du nouveau document, avant attribution de son ID.
class _Draft {
  _Draft.fromValue(this.name, this.value, this.parent)
    : type = _typeOf(value),
      properties = const {},
      source = null,
      isList = value is List,
      signature = _signature(value) {
    children.addAll([
      for (final (name, child) in _entries(value))
        _Draft.fromValue(name, child, this),
    ]);
  }

  _Draft.fromNode(JsonNode node, this.parent)
    : name = node.name,
      value = node.value,
      type = node.type,
      properties = node.properties,
      source = node,
      isList = _isListLike(node.children),
      signature = _signature(node.value) {
    children.addAll([
      for (final child in node.children) _Draft.fromNode(child, this),
    ]);
  }

  final String name;
  final Object? value;
  final String type;
  final Map<String, Object?> properties;

  /// Nœud fourni à [JsonModel.patchNodes], sinon `null`.
  final JsonNode? source;
  final bool isList;
  final _Draft? parent;
  final String signature;
  final List<_Draft> children = [];
  JsonNode? match;

  String get path {
    final parentPath = parent?.path ?? '';
    if (name.startsWith('[') || parentPath.isEmpty) return '$parentPath$name';
    return '$parentPath.$name';
  }
}

/// Associe chaque nœud du nouveau document à au plus un ancien nœud, des
/// indices les plus sûrs (sous-arbre identique) aux plus faibles (chemin).
///
/// Les nœuds courants sont essayés d'abord ; les nœuds supprimés lors de
/// patchs précédents ne servent qu'ensuite, pour les nœuds encore sans ID.
class _JsonMatcher {
  _JsonMatcher(
    this.oldRoots,
    this.roots,
    this._rootIsList, {
    List<JsonNode> removedRoots = const [],
  }) {
    void addDraft(_Draft draft) {
      _drafts.add(draft);
      draft.children.forEach(addDraft);
    }

    roots.forEach(addDraft);
    final seen = <String>{};
    void addOld(JsonNode old) {
      final signature = _signature(old.value);
      _oldSignatures[old] = signature;
      (_oldBySignature[signature] ??= []).add(old);
    }

    for (final old in JsonModel._descendants(oldRoots)) {
      seen.add(old.id);
      addOld(old);
      _oldNodes.add(old);
    }
    // Most recent removals first; an ID still present (moved out of a
    // removed subtree) or already seen is skipped with its stale subtree.
    void addRemoved(JsonNode old) {
      if (!seen.add(old.id)) return;
      addOld(old);
      _removedNodes.add(old);
      old.children.forEach(addRemoved);
    }

    removedRoots.reversed.forEach(addRemoved);
    _removedOrder = [
      for (final root in removedRoots)
        ...JsonModel._descendants([root]).where(_removedNodes.contains),
    ];
  }

  final List<JsonNode> oldRoots;
  final List<_Draft> roots;
  final bool _rootIsList;

  /// Nouveaux nœuds en ordre préfixe (parents avant enfants).
  final List<_Draft> _drafts = [];
  final List<JsonNode> _oldNodes = [];
  final Set<JsonNode> _removedNodes = Set.identity();
  late final List<JsonNode> _removedOrder;
  final Map<JsonNode, String> _oldSignatures = Map.identity();
  final Map<String, List<JsonNode>> _oldBySignature = {};
  final Set<JsonNode> used = Set.identity();
  bool _restoring = false;

  /// Candidats de la phase en cours.
  Iterable<JsonNode> get _candidates =>
      _restoring ? [..._oldNodes, ..._removedOrder] : _oldNodes;

  bool _available(JsonNode old) =>
      _oldSignatures.containsKey(old) &&
      !used.contains(old) &&
      (_restoring || !_removedNodes.contains(old));

  void run() {
    _matchAll();
    if (_removedNodes.isEmpty) return;
    _restoring = true;
    _matchAll();
  }

  void _matchAll() {
    _matchIdenticalSubtrees();
    var changed = true;
    while (changed) {
      changed = _matchSiblings() | _matchMovedContainers();
      if (!changed) changed = _matchMovedLeaves();
    }
  }

  /// Racines des sous-arbres sans correspondance (anciens supprimés encore
  /// absents, puis nouvellement supprimés), du plus ancien au plus récent.
  List<JsonNode> unmatchedRoots() {
    bool isRoot(JsonNode node) {
      final parent = node.parent;
      return parent == null || !_oldSignatures.containsKey(parent);
    }

    return [
      for (final node in [..._removedOrder, ..._oldNodes])
        if (!used.contains(node) && isRoot(node)) node,
    ];
  }

  void _link(_Draft draft, JsonNode old) {
    draft.match = old;
    used.add(old);
  }

  void _linkSubtree(_Draft draft, JsonNode old) {
    _link(draft, old);
    for (final child in draft.children) {
      final oldChild = old.children
          .where((node) => node.name == child.name && _available(node))
          .firstOrNull;
      if (oldChild != null && _oldSignatures[oldChild] == child.signature) {
        _linkSubtree(child, oldChild);
      }
    }
  }

  /// Proximité de position : même chemin, même nom, même parent.
  int _placeScore(_Draft draft, JsonNode old) =>
      (old.path == draft.path ? 4 : 0) +
      (old.name == draft.name ? 2 : 0) +
      (identical(old.parent, draft.parent?.match) ? 1 : 0);

  /// Nombre d'enfants identiques (même nom pour un objet, même contenu).
  int _similarity(_Draft draft, JsonNode old) {
    if (draft.children.isEmpty || old.children.isEmpty) return 0;
    final isList = draft.isList;
    String key(String name, String signature) =>
        isList ? signature : '$name\u0000$signature';
    final remaining = <String, int>{};
    for (final child in old.children) {
      final signature = _oldSignatures[child];
      if (signature == null) continue;
      final k = key(child.name, signature);
      remaining[k] = (remaining[k] ?? 0) + 1;
    }
    var count = 0;
    for (final child in draft.children) {
      final k = key(child.name, child.signature);
      final left = remaining[k] ?? 0;
      if (left > 0) {
        remaining[k] = left - 1;
        count++;
      }
    }
    return count;
  }

  bool _similarEnough(_Draft draft, JsonNode old) {
    final similarity = _similarity(draft, old);
    return similarity > 0 &&
        similarity * 2 >= max(draft.children.length, old.children.length);
  }

  /// Sous-arbres non vides strictement identiques, éventuellement déplacés
  /// ou renommés ; le plus proche en position l'emporte.
  void _matchIdenticalSubtrees() {
    for (final draft in _drafts) {
      if (draft.match != null || draft.children.isEmpty) continue;
      JsonNode? best;
      var bestScore = -1;
      for (final old in _oldBySignature[draft.signature] ?? const []) {
        if (!_available(old) || old.children.isEmpty) continue;
        final score = _placeScore(draft, old);
        if (score > bestScore) {
          best = old;
          bestScore = score;
        }
      }
      if (best != null) _linkSubtree(draft, best);
    }
  }

  /// Enfants de parents déjà associés : par nom dans un objet, par contenu
  /// puis par position dans une liste ; gère renommages et réordonnancements.
  bool _matchSiblings() {
    var changed = false;
    void group(List<_Draft> drafts, List<JsonNode> olds, bool isList) {
      final pairs = <(int, int, _Draft, JsonNode)>[];
      for (final draft in drafts) {
        if (draft.match != null) continue;
        for (final old in olds) {
          if (!_available(old)) continue;
          final sameSignature = _oldSignatures[old] == draft.signature;
          final similar = _similarEnough(draft, old);
          final int score;
          if (isList) {
            score = sameSignature
                ? 3000
                : similar
                ? 1000 + _similarity(draft, old)
                : old.type == draft.type
                ? 1
                : 0;
          } else {
            score = old.name == draft.name
                ? 4000
                : sameSignature
                ? 3000
                : similar
                ? 1000 + _similarity(draft, old)
                : 0;
          }
          if (score > 0) {
            final distance = (_indexOf(draft.name) - _indexOf(old.name)).abs();
            pairs.add((score, distance, draft, old));
          }
        }
      }
      pairs.sort(
        (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2),
      );
      for (final (_, _, draft, old) in pairs) {
        if (draft.match == null && !used.contains(old)) {
          _link(draft, old);
          changed = true;
        }
      }
    }

    group(roots, oldRoots, _rootIsList);
    for (final draft in _drafts) {
      final old = draft.match;
      if (old != null) group(draft.children, old.children, draft.isList);
    }
    return changed;
  }

  /// Conteneurs déplacés (et éventuellement modifiés) vers un autre parent.
  bool _matchMovedContainers() {
    var changed = false;
    for (final draft in _drafts) {
      if (draft.match != null || draft.children.isEmpty) continue;
      JsonNode? best;
      var bestScore = (0, 0);
      for (final old in _candidates) {
        if (!_available(old) || !_similarEnough(draft, old)) continue;
        final score = (_similarity(draft, old), _placeScore(draft, old));
        if (score.$1 > bestScore.$1 ||
            (score.$1 == bestScore.$1 && score.$2 > bestScore.$2)) {
          best = old;
          bestScore = score;
        }
      }
      if (best != null) {
        _link(draft, best);
        changed = true;
      }
    }
    return changed;
  }

  /// Derniers recours : même chemin, ou valeur simple déplacée (ou revenue)
  /// avec son nom.
  bool _matchMovedLeaves() {
    var changed = false;
    for (final draft in _drafts) {
      if (draft.match != null) continue;
      JsonNode? best;
      var bestScore = -1;
      for (final old in _candidates) {
        if (!_available(old)) continue;
        // A removed node's path is stale: it only comes back by content.
        final samePath = !_removedNodes.contains(old) && old.path == draft.path;
        final moved =
            old.name == draft.name && _oldSignatures[old] == draft.signature;
        if (!samePath && !moved) continue;
        final score = _placeScore(draft, old);
        if (score > bestScore) {
          best = old;
          bestScore = score;
        }
      }
      if (best != null) {
        _link(draft, best);
        changed = true;
      }
    }
    return changed;
  }
}
