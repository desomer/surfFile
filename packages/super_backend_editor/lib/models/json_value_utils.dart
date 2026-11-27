/// Utilitaires internes d'immuabilité profonde, d'égalité structurelle et de
/// hachage déterministe pour les structures JSON (`Map<String, Object?>` et `List`).
library;

/// Fige récursivement une carte JSON en `Map<String, Object?>` non modifiable.
Map<String, Object?> freezeJsonMap(Map<dynamic, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const <String, Object?>{};
  final copy = <String, Object?>{};
  for (final entry in raw.entries) {
    copy['${entry.key}'] = freezeJsonValue(entry.value);
  }
  return Map<String, Object?>.unmodifiable(copy);
}

/// Fige récursivement une liste d'objets JSON en `List<Map<String, Object?>>` non modifiable.
List<Map<String, Object?>> freezeJsonMapList(Object? raw) {
  if (raw is! List || raw.isEmpty) return const <Map<String, Object?>>[];
  return List<Map<String, Object?>>.unmodifiable(<Map<String, Object?>>[
    for (final item in raw)
      if (item is Map) freezeJsonMap(item),
  ]);
}

/// Fige récursivement une valeur JSON arbitraire (`Map`, `List` ou scalaire).
Object? freezeJsonValue(Object? value) {
  if (value is Map) {
    return freezeJsonMap(value);
  }
  if (value is List) {
    if (value.isEmpty) return const <Object?>[];
    return List<Object?>.unmodifiable(<Object?>[
      for (final item in value) freezeJsonValue(item),
    ]);
  }
  return value;
}

/// Fige une carte imbriquée `Map<String, Map<String, String>>` (ex. variables par environnement).
Map<String, Map<String, String>> freezeNestedStringMap(Object? raw) {
  if (raw is! Map || raw.isEmpty) {
    return const <String, Map<String, String>>{};
  }
  final outer = <String, Map<String, String>>{};
  for (final envEntry in raw.entries) {
    final envKey = '${envEntry.key}'.trim();
    if (envKey.isEmpty || envEntry.value is! Map) continue;
    final innerRaw = envEntry.value as Map;
    final inner = <String, String>{};
    for (final kv in innerRaw.entries) {
      final varKey = '${kv.key}'.trim();
      if (varKey.isEmpty || kv.value == null) continue;
      inner[varKey] = '${kv.value}';
    }
    outer[envKey] = Map<String, String>.unmodifiable(inner);
  }
  return Map<String, Map<String, String>>.unmodifiable(outer);
}

/// Compare récursivement deux valeurs JSON (`Map`, `List`, scalaires).
bool deepJsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!deepJsonEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepJsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Calcule un code de hachage profond et indépendant de l'ordre des clés pour une valeur JSON.
int deepJsonHash(Object? value) {
  if (value == null) return 0;
  if (value is Map) {
    return Object.hashAllUnordered(<int>[
      for (final entry in value.entries)
        Object.hash(entry.key, deepJsonHash(entry.value)),
    ]);
  }
  if (value is List) {
    return Object.hashAll(<int>[
      for (final item in value) deepJsonHash(item),
    ]);
  }
  return value.hashCode;
}

/// Extrait et nettoie une liste de chaînes non vides depuis une valeur JSON.
List<String> parseCleanStringList(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty
        ? const <String>[]
        : List<String>.unmodifiable(<String>[trimmed]);
  }
  if (raw is! List || raw.isEmpty) return const <String>[];
  final result = <String>[];
  for (final item in raw) {
    if (item == null) continue;
    final trimmed = '$item'.trim();
    if (trimmed.isNotEmpty) result.add(trimmed);
  }
  return List<String>.unmodifiable(result);
}

/// Analyse une date ISO-8601 en UTC avec repli sur l'époque Unix UTC si absente.
DateTime parseUtcDateTimeOrEpoch(Object? raw) {
  if (raw is DateTime) return raw.toUtc();
  if (raw is String && raw.trim().isNotEmpty) {
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed != null) return parsed.toUtc();
    throw FormatException('Horodatage ISO-8601 invalide : $raw');
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
