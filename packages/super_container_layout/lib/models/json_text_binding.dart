import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class JsonTextBinding {
  const JsonTextBinding({required this.repositoryId, required this.path});

  final String repositoryId;
  final String path;

  void validate() {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(repositoryId)) {
      throw const FormatException('ID de repository invalide.');
    }
    JsonAttributePath(path);
  }

  Map<String, Object?> toJson() {
    validate();
    return {'repositoryId': repositoryId, 'path': path};
  }

  factory JsonTextBinding.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json.length != 2 ||
        json['repositoryId'] is! String ||
        json['path'] is! String) {
      throw const FormatException('Liaison de repository invalide.');
    }
    final result = JsonTextBinding(
      repositoryId: json['repositoryId'] as String,
      path: json['path'] as String,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is JsonTextBinding &&
      repositoryId == other.repositoryId &&
      path == other.path;

  @override
  int get hashCode => Object.hash(repositoryId, path);
}

/// Strict dotted object keys and existing array indices; not JSONPath.
class JsonAttributePath {
  JsonAttributePath(String path) : _segments = _parse(path);

  final List<Object> _segments;

  static List<Object> _parse(String path) {
    final matches = RegExp(r'(^|\.)([^.\[\]\s]+)|\[([0-9]+)\]')
        .allMatches(path);
    final segments = <Object>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start != offset ||
          (offset == 0 && match.group(1) == '.') ||
          (offset > 0 && match.group(1) == '')) {
        throw const FormatException('Chemin JSON invalide.');
      }
      final index = match.group(3);
      final parsedIndex = index == null ? null : int.tryParse(index);
      if (index != null && parsedIndex == null) {
        throw const FormatException('Indice JSON invalide.');
      }
      segments.add(index == null ? match.group(2)! : parsedIndex!);
      offset = match.end;
    }
    if (segments.isEmpty || offset != path.length) {
      throw const FormatException(
        'Chemin JSON invalide. Exemple : client.nom ou clients[0].nom.',
      );
    }
    return segments;
  }

  Object? read(Object? root) {
    Object? value = root;
    for (final segment in _segments) {
      if (segment is String) {
        if (value == null) continue;
        if (value is! Map<String, dynamic>) _incompatible();
        value = value[segment];
      } else {
        final index = segment as int;
        if (value is! List || index >= value.length) {
          throw const FormatException('Indice de tableau JSON inexistant.');
        }
        value = value[index];
      }
    }
    if ((value != null &&
            value is! String &&
            value is! num &&
            value is! bool) ||
        (value is num && !value.isFinite)) {
      throw const FormatException('L’attribut doit être une valeur simple.');
    }
    return value;
  }

  static Never _incompatible() => throw const FormatException(
    'Structure JSON incompatible avec le chemin.',
  );

  /// Returns a new JSON tree; the input is never changed on validation failure.
  Object? write(Object? root, String text, Object? previous) {
    if (previous != null &&
        previous is! String &&
        previous is! num &&
        previous is! bool) {
      throw const FormatException('L’attribut doit être une valeur simple.');
    }
    final Object? replacement;
    if (previous == null || previous is String) {
      replacement = text;
    } else {
      Object? parsed;
      try {
        parsed = jsonDecode(text);
      } on FormatException {
        throw const FormatException('Valeur incompatible avec le type JSON.');
      }
      if ((previous is bool && parsed is! bool) ||
          (previous is num && (parsed is! num || !parsed.isFinite))) {
        throw const FormatException('Valeur incompatible avec le type JSON.');
      }
      replacement = parsed;
    }

    Object? update(Object? value, int depth) {
      if (depth == _segments.length) return replacement;
      final segment = _segments[depth];
      if (segment is String) {
        if (value != null && value is! Map<String, dynamic>) _incompatible();
        final map = value == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.of(value as Map<String, dynamic>);
        map[segment] = update(map[segment], depth + 1);
        return map;
      }
      final index = segment as int;
      if (value is! List || index >= value.length) {
        throw const FormatException('Indice de tableau JSON inexistant.');
      }
      final list = List<Object?>.of(value);
      list[index] = update(list[index], depth + 1);
      return list;
    }

    return update(root, 0);
  }
}
