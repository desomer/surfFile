/// Restaure les nœuds du repository et conserve leurs données lors des patchs YAML.
library;

import 'json_browser.dart';
import 'yaml2jsonschemas_parser.dart';

/// Synchronise le modèle du schéma avec les nœuds éditables du repository.
class RepositorySchemaModel {
  RepositorySchemaModel(this._parser) : _model = _parser.model('source', '');

  final Yaml2JsonSchemasParser _parser;
  JsonModel _model;
  final _storedNodes = <String, Map<String, Object?>>{};

  static const _derivedFields = {
    'id',
    'name',
    'type',
    'typeIcon',
    'description',
    'properties',
    'propertiesText',
    'children',
  };

  /// Reconstruit le modèle depuis les nœuds chargés, sans modifier ceux-ci.
  void restore(List<Object?> nodes) {
    final indexed = _index(nodes);
    JsonNode build(Object? raw, JsonNode? parent) {
      final data = _nodeMap(raw);
      final id = data['id'] as String;
      final description = data['description'];
      final children = _children(data);
      final previous = _model.nodeById(id);
      final value =
          previous?.value ??
          ((description == null || description == '') &&
                  (data['typeIcon'] == 'container' || children.isNotEmpty)
              ? <String, Object?>{}
              : description);
      final node = JsonNode(
        id: id,
        name: data['name'] as String,
        type: data['type'] as String,
        value: value,
        parent: parent,
        properties: _properties(data),
      );
      node.children.addAll([for (final child in children) build(child, node)]);
      return node;
    }

    final restored = [for (final node in nodes) build(node, null)];
    _model = JsonModel(name: 'source', json: null, nodes: restored);
    _storedNodes
      ..clear()
      ..addAll(indexed);
  }

  /// Patche le YAML et préserve les ID et les champs saisis dans les nœuds.
  List<Object?> patch(String source, List<Object?> nodes) {
    final indexed = _index(nodes);
    for (final entry in indexed.entries) {
      final node = _model.nodeById(entry.key);
      if (node == null) continue;
      final properties = _properties(entry.value);
      node.properties
        ..clear()
        ..addAll(properties);
    }
    _storedNodes.addAll(indexed);
    _parser.patch(_model, source);

    Map<String, Object?> serialize(JsonNode node) {
      final result = node.toJson();
      final previous = _storedNodes[node.id];
      if (previous != null) {
        for (final entry in previous.entries) {
          if (!_derivedFields.contains(entry.key)) {
            result[entry.key] = entry.value;
          }
        }
      }
      if (result.containsKey('children')) {
        result['children'] = [
          for (final child in node.children) serialize(child),
        ];
      }
      return result;
    }

    final result = [for (final node in _model.nodes) serialize(node)];
    final retained = <String>{};
    void retain(JsonNode node) {
      retained.add(node.id);
      for (final child in node.children) {
        retain(child);
      }
    }

    for (final node in [..._model.nodes, ..._model.removedNodes]) {
      retain(node);
    }
    _storedNodes.removeWhere((id, _) => !retained.contains(id));
    return result;
  }

  static Map<String, Map<String, Object?>> _index(List<Object?> nodes) {
    final indexed = <String, Map<String, Object?>>{};
    void visit(Object? raw) {
      final node = _nodeMap(raw);
      final id = node['id'] as String;
      if (indexed.containsKey(id)) {
        throw const FormatException('Les ID des nœuds doivent être uniques.');
      }
      _properties(node);
      indexed[id] = node;
      for (final child in _children(node)) {
        visit(child);
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return indexed;
  }

  static Map<String, Object?> _nodeMap(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw const FormatException('Un nœud du repository doit être un objet.');
    }
    final node = Map<String, Object?>.from(raw);
    for (final key in ['id', 'name', 'type']) {
      final value = node[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Le nœud doit posséder un $key valide.');
      }
    }
    if (node['description'] != null && node['description'] is! String) {
      throw const FormatException('La description du nœud doit être du texte.');
    }
    return node;
  }

  static List<Object?> _children(Map<String, Object?> node) {
    final children = node['children'];
    if (children == null) return const [];
    if (children is! List) {
      throw const FormatException(
        'Les enfants d’un nœud doivent être une liste.',
      );
    }
    return List<Object?>.from(children);
  }

  static Map<String, Object?> _properties(Map<String, Object?> node) {
    final properties = node['properties'];
    if (properties == null) return {};
    if (properties is! Map || properties.keys.any((key) => key is! String)) {
      throw const FormatException(
        'Les propriétés d’un nœud doivent être un objet.',
      );
    }
    return Map<String, Object?>.from(properties);
  }
}
