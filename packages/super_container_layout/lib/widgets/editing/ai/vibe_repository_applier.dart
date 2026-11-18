/// Formatage de contexte, validation, réécriture d'alias et transaction d'application des repositories JSON pour Vibe IA.
///
/// Fournit :
/// - [VibeRepositoryPromptFormatter] pour résumer le catalogue et les données bornées d'un [JsonRepositoryStore] dans le prompt ;
/// - [VibeRepositoryPatchValidator] pour valider strictement les clés, modes et valeurs d'un patch `"repositories"` ;
/// - [VibeRepositoryApplier] et [rewriteVibePatchRepositoryAliases] pour réécrire les alias vers leurs identifiants 32 hex dans `"vibe"` ;
/// - [VibeRepositoryTurnTransaction] pour appliquer de manière idempotente les paliers SSE et le résultat final avec `rollback()` et callbacks Undo/Redo.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../models/calculated_attribute_definition.dart';
import '../../../services/appearance/appearance_codec.dart'
    show PatchRejectedEntry;
import '../../../services/repositories/json_repository_store.dart';

final RegExp _repoKeyOrIdPattern = RegExp(r'^[a-z0-9_]{1,32}$');
final RegExp _forbiddenJsonKeyChars = RegExp(r'[.\[\]?\s]');

/// Callbacks compagnons d'annulation et de rétablissement des mutations de repositories d'un tour Vibe.
typedef VibeRepositoryHistoryCallbacks = ({
  Future<void> Function() undo,
  Future<void> Function() redo,
});

/// Mode d'application d'une entrée du patch `"repositories"`.
enum VibeRepositoryPatchMode {
  /// Fusion profonde clé par clé sur l'objet JSON existant (comportement par défaut).
  merge,

  /// Remplacement intégral du document JSON racine du repository.
  replace,
}

/// Entrée validée et normalisée extraite d'un patch `"repositories"`.
@immutable
class VibeRepositoryPatchEntry {
  /// Crée une entrée validée pour la clé ou l'alias [key].
  VibeRepositoryPatchEntry({
    required this.key,
    this.name,
    this.mode = VibeRepositoryPatchMode.merge,
    required Map<String, Object?> data,
    this.hasData = true,
    List<CalculatedAttributeDefinition> calculatedAttributes = const [],
    this.hasCalculatedAttributes = false,
  }) : data = Map<String, Object?>.unmodifiable(data),
       calculatedAttributes = List<CalculatedAttributeDefinition>.unmodifiable(
         calculatedAttributes,
       );

  /// Identifiant ou alias `<idOrAlias>` déclaré dans `"repositories"`.
  final String key;

  /// Nom lisible optionnel du repository fichier (validé par [JsonRepositoryStore.validateName]).
  final String? name;

  /// Mode d'application (`merge` ou `replace`).
  final VibeRepositoryPatchMode mode;

  /// Document JSON objet validé à fusionner ou appliquer.
  final Map<String, Object?> data;

  /// Vrai lorsque le patch contient explicitement la clé `"data"`.
  final bool hasData;

  /// Définitions JavaScript des attributs calculés fournies dans le patch.
  final List<CalculatedAttributeDefinition> calculatedAttributes;

  /// Vrai lorsque le patch contient explicitement la clé `"calculatedAttributes"`.
  final bool hasCalculatedAttributes;
}

/// Formateur produisant le résumé borné des repositories d'un [JsonRepositoryStore] pour le prompt Vibe IA.
abstract final class VibeRepositoryPromptFormatter {
  /// En-tête standard de la section des repositories dans le prompt du tour.
  static const String sectionHeader = 'REPOSITORIES DISPONIBLES (JSON) :';

  /// Message renvoyé lorsque le store actif ne contient encore aucun repository.
  static const String emptyStoreMessage =
      '$sectionHeader\n'
      '[] (Aucun repository existant dans le store actif. Tu peux en créer via la clé racine "repositories" avec un alias snake_case.)';

  /// Formate la liste descriptive et les échantillons bornés des repositories de [store].
  ///
  /// Tronque tout tableau JSON de longueur strictement supérieure à [maxArrayItems] sans
  /// injecter de fausse clé dans les données, et expose les longueurs réelles dans
  /// `"truncatedArrays"`. Réduit automatiquement [maxArrayItems] à `2` puis `1` si le
  /// résultat dépasse [maxTotalChars].
  static Future<String> formatStoreContext(
    JsonRepositoryStore store, {
    int maxArrayItems = 5,
    int maxTotalChars = 12000,
  }) async {
    final entries = await store.catalog();
    if (entries.isEmpty) {
      return emptyStoreMessage;
    }

    final rawDocuments = <String, Object?>{};
    for (final entry in entries) {
      try {
        rawDocuments[entry.id] = await store.readDocument(entry.id);
      } on FormatException {
        rawDocuments[entry.id] = const <String, Object?>{};
      }
    }

    final initialLimit = maxArrayItems < 1 ? 1 : maxArrayItems;
    final candidateLimits = <int>[
      initialLimit,
      if (initialLimit > 2) 2,
      if (initialLimit > 1) 1,
    ];

    const prettyEncoder = JsonEncoder.withIndent('  ');
    String formatted = '';
    List<Map<String, Object?>> lastDescriptors = const [];

    for (final limit in candidateLimits) {
      final descriptors = <Map<String, Object?>>[
        for (final entry in entries)
          _buildRepositoryDescriptor(
            store: store,
            entry: entry,
            rawDocument: rawDocuments[entry.id],
            maxArrayItems: limit,
          ),
      ];
      lastDescriptors = descriptors;
      formatted = '$sectionHeader\n${prettyEncoder.convert(descriptors)}';
      if (formatted.length <= maxTotalChars) {
        return formatted;
      }
    }

    final compact = '$sectionHeader\n${jsonEncode(lastDescriptors)}';
    return compact.length < formatted.length ? compact : formatted;
  }

  static Map<String, Object?> _buildRepositoryDescriptor({
    required JsonRepositoryStore store,
    required JsonRepositoryEntry entry,
    required Object? rawDocument,
    required int maxArrayItems,
  }) {
    final kind = store.isPersistentRepository(entry.id)
        ? 'persistent'
        : (store.isMemoryOnlyRepository(entry.id) ? 'memory' : 'file');
    final calculated = [
      for (final descriptor in store.calculatedAttributeCatalog(entry.id))
        descriptor.path,
    ];
    final jsCalculated = [
      for (final def in store.jsCalculatedAttributesOf(entry.id))
        def.toCompactJson(),
    ];
    final truncatedArrays = <String, int>{};
    final sampledData = _sampleJsonValue(
      rawDocument,
      path: '',
      maxArrayItems: maxArrayItems,
      truncatedArrays: truncatedArrays,
    );
    return <String, Object?>{
      'id': entry.id,
      'name': entry.name,
      'kind': kind,
      if (calculated.isNotEmpty) 'calculatedAttributes': calculated,
      if (jsCalculated.isNotEmpty) 'jsCalculatedAttributes': jsCalculated,
      if (truncatedArrays.isNotEmpty) 'truncatedArrays': truncatedArrays,
      'data': sampledData,
    };
  }

  static Object? _sampleJsonValue(
    Object? value, {
    required String path,
    required int maxArrayItems,
    required Map<String, int> truncatedArrays,
  }) {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final childPath = path.isEmpty ? key : '$path.$key';
        result[key] = _sampleJsonValue(
          entry.value,
          path: childPath,
          maxArrayItems: maxArrayItems,
          truncatedArrays: truncatedArrays,
        );
      }
      return result;
    }
    if (value is List) {
      if (value.length > maxArrayItems) {
        truncatedArrays[path.isEmpty ? '[]' : path] = value.length;
      }
      final count = value.length > maxArrayItems ? maxArrayItems : value.length;
      return <Object?>[
        for (var i = 0; i < count; i++)
          _sampleJsonValue(
            value[i],
            path: '$path[$i]',
            maxArrayItems: maxArrayItems,
            truncatedArrays: truncatedArrays,
          ),
      ];
    }
    return value;
  }
}

/// Validateur syntaxique et structurel des patches `"repositories"` produits par l'IA.
abstract final class VibeRepositoryPatchValidator {
  static const Set<String> _envelopeKeys = <String>{
    'name',
    'mode',
    'data',
    'calculatedAttributes',
  };
  static const Set<String> _descriptorMetaKeys = <String>{
    'name',
    'mode',
    'data',
    'id',
    'kind',
    'calculatedAttributes',
    'jsCalculatedAttributes',
    'truncatedArrays',
  };

  /// Valide et décode un objet `"repositories"` complet en entrées [VibeRepositoryPatchEntry] typées.
  static Map<String, VibeRepositoryPatchEntry> validateAndParse(
    Object? rawRepositoriesPatch,
  ) {
    if (rawRepositoriesPatch is! Map) {
      throw const FormatException(
        'Le champ "repositories" doit être un objet JSON.',
      );
    }
    final result = <String, VibeRepositoryPatchEntry>{};
    for (final entry in rawRepositoriesPatch.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'Les clés de "repositories" doivent être des chaînes JSON.',
        );
      }
      final key = entry.key as String;
      result[key] = parseEntry(key, entry.value);
    }
    return result;
  }

  /// Valide et décode une entrée individuelle `(repoKey, rawValue)` du patch `"repositories"`.
  static VibeRepositoryPatchEntry parseEntry(String repoKey, Object? rawValue) {
    if (!_repoKeyOrIdPattern.hasMatch(repoKey)) {
      throw FormatException(
        'Identifiant ou alias de repository invalide "$repoKey" '
        '(attendu : 1 à 32 caractères parmi a-z, 0-9 et "_").',
      );
    }
    if (rawValue is! Map) {
      throw FormatException(
        'L’entrée de repository "$repoKey" doit être un objet JSON.',
      );
    }
    for (final k in rawValue.keys) {
      if (k is! String) {
        throw FormatException(
          'L’entrée de repository "$repoKey" contient une clé non textuelle.',
        );
      }
    }
    final map = Map<String, Object?>.from(rawValue);

    if ((map.containsKey('data') || map.containsKey('calculatedAttributes')) &&
        map.keys.every(_envelopeKeys.contains)) {
      return _parseEnvelope(repoKey, map);
    }

    if (_looksLikeMalformedEnvelope(map)) {
      return _parseEnvelope(repoKey, map);
    }

    final normalizedData = validateDataObject(repoKey, map);
    return VibeRepositoryPatchEntry(
      key: repoKey,
      mode: VibeRepositoryPatchMode.merge,
      data: normalizedData,
    );
  }

  static bool _looksLikeMalformedEnvelope(Map<String, Object?> map) {
    if (map.isEmpty) return false;
    if (map.containsKey('data')) {
      if (map.keys.every(_descriptorMetaKeys.contains)) {
        return true;
      }
      if (map.containsKey('mode') &&
          (map['data'] is! Map || !_isValidModeValue(map['mode']))) {
        return true;
      }
      if (map.containsKey('name') && map['data'] is! Map) {
        return true;
      }
      return false;
    }
    if (map.containsKey('mode') &&
        map.keys.every(_descriptorMetaKeys.contains)) {
      return true;
    }
    if (map.containsKey('calculatedAttributes') &&
        map.keys.every(_descriptorMetaKeys.contains)) {
      return true;
    }
    return false;
  }

  static bool _isValidModeValue(Object? rawMode) =>
      rawMode == 'merge' || rawMode == 'replace';

  static VibeRepositoryPatchEntry _parseEnvelope(
    String repoKey,
    Map<String, Object?> map,
  ) {
    final extraKeys = map.keys.where((k) => !_envelopeKeys.contains(k)).toList();
    String? validatedName;
    if (map.containsKey('name') && map['name'] != null) {
      final rawName = map['name'];
      if (rawName is! String) {
        throw FormatException(
          'Le champ "name" du repository "$repoKey" doit être une chaîne de caractères.',
        );
      }
      validatedName = JsonRepositoryStore.validateName(rawName);
    }

    var mode = VibeRepositoryPatchMode.merge;
    if (map.containsKey('mode')) {
      final rawMode = map['mode'];
      if (rawMode == 'merge') {
        mode = VibeRepositoryPatchMode.merge;
      } else if (rawMode == 'replace') {
        mode = VibeRepositoryPatchMode.replace;
      } else {
        throw FormatException(
          'Mode de repository invalide "$rawMode" pour "$repoKey" '
          '(attendu: "merge" ou "replace").',
        );
      }
    }

    final hasData = map.containsKey('data');
    final hasCalculated = map.containsKey('calculatedAttributes');

    if (!hasData && !hasCalculated) {
      throw FormatException(
        'Enveloppe du repository "$repoKey" incomplète : clé "data" manquante.',
      );
    }
    if (mode == VibeRepositoryPatchMode.replace && !hasData) {
      throw FormatException(
        'Enveloppe du repository "$repoKey" incomplète : clé "data" requise en mode "replace".',
      );
    }

    Map<String, Object?> normalizedData = const <String, Object?>{};
    if (hasData) {
      final rawData = map['data'];
      if (rawData is! Map) {
        throw FormatException(
          'Le champ "data" du repository "$repoKey" doit être un objet JSON {...}, '
          'jamais un tableau ni un scalaire.',
        );
      }
      normalizedData = validateDataObject(repoKey, rawData);
    }

    final parsedCalculated = <CalculatedAttributeDefinition>[];
    if (hasCalculated) {
      final rawCalculated = map['calculatedAttributes'];
      if (rawCalculated is! List) {
        throw FormatException(
          'Le champ "calculatedAttributes" du repository "$repoKey" doit être un tableau JSON.',
        );
      }
      final seenPaths = <String>{};
      for (final item in rawCalculated) {
        final def = CalculatedAttributeDefinition.fromJson(item);
        if (!seenPaths.add(def.path)) {
          throw FormatException(
            'Attribut calculé en double "${def.path}" dans le repository "$repoKey".',
          );
        }
        parsedCalculated.add(def);
      }
    }

    if (extraKeys.isNotEmpty) {
      throw FormatException(
        'Clé(s) non autorisée(s) ${extraKeys.map((k) => '"$k"').join(', ')} '
        'dans l’enveloppe du repository "$repoKey" '
        '(attendu uniquement : "name", "mode", "data", "calculatedAttributes").',
      );
    }

    return VibeRepositoryPatchEntry(
      key: repoKey,
      name: validatedName,
      mode: mode,
      data: normalizedData,
      hasData: hasData,
      calculatedAttributes: parsedCalculated,
      hasCalculatedAttributes: hasCalculated,
    );
  }

  /// Valide récursivement toutes les clés et valeurs d'un objet JSON `data` pour [repoKey].
  ///
  /// Interdit le préfixe `@` (attributs calculés), les caractères `.`, `[`, `]`, `?` et les
  /// espaces dans toutes les clés d'objets, ainsi que les nombres non finis (`NaN`, `Infinity`).
  static Map<String, Object?> validateDataObject(
    String repoKey,
    Map<Object?, Object?> rawData,
  ) {
    final result = <String, Object?>{};
    for (final entry in rawData.entries) {
      final rawKey = entry.key;
      if (rawKey is! String || rawKey.isEmpty) {
        throw FormatException(
          'Clé JSON vide ou invalide dans le repository "$repoKey".',
        );
      }
      if (rawKey.startsWith('@')) {
        throw FormatException(
          'Clé JSON invalide "$rawKey" dans le repository "$repoKey" : '
          'le préfixe "@" est réservé aux attributs calculés en lecture seule.',
        );
      }
      if (_forbiddenJsonKeyChars.hasMatch(rawKey)) {
        throw FormatException(
          'Clé JSON invalide "$rawKey" dans le repository "$repoKey" : '
          'les caractères ".", "[", "]", "?" et les espaces sont interdits par JsonAttributePath.',
        );
      }
      result[rawKey] = _validateValue(repoKey, entry.value);
    }
    return result;
  }

  static Object? _validateValue(String repoKey, Object? value) {
    if (value == null || value is bool || value is String) {
      return value;
    }
    if (value is num) {
      if (!value.isFinite) {
        throw FormatException(
          'Nombre JSON non fini interdit dans le repository "$repoKey".',
        );
      }
      return value;
    }
    if (value is List) {
      return <Object?>[
        for (final item in value) _validateValue(repoKey, item),
      ];
    }
    if (value is Map) {
      return validateDataObject(repoKey, value);
    }
    throw FormatException(
      'Valeur JSON non supportée dans le repository "$repoKey".',
    );
  }
}

/// Fusionne récursivement les clés de [patch] sur une copie profonde de [base].
///
/// Deux objets JSON (`Map`) sont fusionnés récursivement clé par clé ; les tableaux
/// (`List`), les scalaires et `null` remplacent la valeur correspondante de [base].
Map<String, Object?> deepMergeJsonObjects(
  Map<String, Object?> base,
  Map<String, Object?> patch,
) {
  final merged = _deepCopyJsonMap(base);
  for (final entry in patch.entries) {
    final existing = merged[entry.key];
    final incoming = entry.value;
    if (existing is Map && incoming is Map) {
      merged[entry.key] = deepMergeJsonObjects(
        Map<String, Object?>.from(existing),
        Map<String, Object?>.from(incoming),
      );
    } else {
      merged[entry.key] = _deepCopyJsonValue(incoming);
    }
  }
  return merged;
}

/// Réécrit récursivement les alias de repositories dans les liaisons d'un patch `"vibe"`.
Map<String, dynamic> rewriteVibePatchRepositoryAliases(
  Map<String, dynamic> vibePatch,
  Map<String, String> aliasToActualId,
) => VibeRepositoryApplier.rewriteVibePatchBindings(vibePatch, aliasToActualId);

/// Utilitaires statiques de réécriture des liaisons `"vibe"` et de fusion JSON des repositories.
abstract final class VibeRepositoryApplier {
  static const Set<String> _protectedPrefixes = <String>{
    'theme',
    'registry',
    'case',
    'http',
    'https',
    'data',
    'file',
    'asset',
    'scaffold',
    'content',
  };

  static const Set<String> _directBindingKeys = <String>{
    'binding',
    'optionsBinding',
    'imageBinding',
    'errorBinding',
  };

  static const Set<String> _dynamicTabBindingKeys = <String>{
    'label',
    'icon',
    'binding',
  };

  /// Réécrit dans [vibePatch] les références d'alias de repositories selon [aliasToActualId].
  ///
  /// Remplace :
  /// - `'repositoryId'` dans tout objet de liaison (`{'repositoryId': '<alias>', 'path': '...'}`) ;
  /// - le préfixe `'<alias>:<chemin>'` dans les contextes de liaison (`'binding'`,
  ///   `'optionsBinding'`, `'imageBinding'`, `'errorBinding'`, `'label'`/`'icon'` dans
  ///   `'dynamicTab'`, et toute entrée d'un objet `'propertyBindings'`), sans jamais
  ///   altérer les préfixes système (`theme:`, `registry:`, `case:`, `http:`, `https:`,
  ///   `data:`, `file:`, `asset:`).
  static Map<String, dynamic> rewriteVibePatchBindings(
    Map<String, dynamic> vibePatch,
    Map<String, String> aliasToActualId,
  ) {
    if (aliasToActualId.isEmpty) return vibePatch;
    return _rewriteMap(vibePatch, aliasToActualId, parentKey: null);
  }

  static Map<String, dynamic> _rewriteMap(
    Map<Object?, Object?> source,
    Map<String, String> aliasToActualId, {
    required String? parentKey,
  }) {
    final result = <String, dynamic>{};
    final hasPath = source['path'] is String;
    final inPropertyBindings = parentKey == 'propertyBindings';
    final inDynamicTab = parentKey == 'dynamicTab';

    for (final entry in source.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      if (key == 'repositoryId' && hasPath && value is String) {
        final trimmed = value.trim();
        if (!_protectedPrefixes.contains(trimmed.toLowerCase()) &&
            aliasToActualId.containsKey(trimmed)) {
          result[key] = aliasToActualId[trimmed]!;
          continue;
        }
      }

      if (value is String &&
          (inPropertyBindings ||
              _directBindingKeys.contains(key) ||
              (inDynamicTab && _dynamicTabBindingKeys.contains(key)))) {
        result[key] = _rewriteBindingString(value, aliasToActualId);
        continue;
      }

      result[key] = _rewriteValue(value, aliasToActualId, parentKey: key);
    }
    return result;
  }

  static Object? _rewriteValue(
    Object? value,
    Map<String, String> aliasToActualId, {
    required String? parentKey,
  }) {
    if (value is Map) {
      return _rewriteMap(value, aliasToActualId, parentKey: parentKey);
    }
    if (value is List) {
      return <Object?>[
        for (final item in value)
          _rewriteValue(item, aliasToActualId, parentKey: parentKey),
      ];
    }
    return value;
  }

  static String _rewriteBindingString(
    String rawValue,
    Map<String, String> aliasToActualId,
  ) {
    final trimmed = rawValue.trim();
    final colonIndex = trimmed.indexOf(':');
    if (colonIndex <= 0 || colonIndex >= trimmed.length - 1) {
      return rawValue;
    }
    final prefix = trimmed.substring(0, colonIndex);
    if (_protectedPrefixes.contains(prefix.toLowerCase())) {
      return rawValue;
    }
    final actualId = aliasToActualId[prefix];
    if (actualId == null) {
      return rawValue;
    }
    final rest = trimmed.substring(colonIndex + 1);
    return '$actualId:$rest';
  }
}

/// Transaction gérant la création, la fusion idempotente, le rollback et l'Undo/Redo
/// des repositories JSON au cours d'un tour de génération Vibe IA.
class VibeRepositoryTurnTransaction {
  /// Crée une nouvelle transaction rattachée à [store].
  VibeRepositoryTurnTransaction(this.store, {Random? random})
    : _random = random ?? Random.secure();

  /// Store de repositories JSON manipulé par cette transaction.
  final JsonRepositoryStore store;

  final Random _random;
  final Map<String, String> _assignedIdsByAlias = <String, String>{};
  final Map<String, String> _aliasToActualId = <String, String>{};
  final Map<String, String> _resolvedTargetByKey = <String, String>{};
  final Map<String, Map<String, Object?>> _baselineDocuments =
      <String, Map<String, Object?>>{};
  final Map<String, ({String name, String id})> _createdRepositories =
      <String, ({String name, String id})>{};
  final Map<String, Map<String, Object?>> _finalDocuments =
      <String, Map<String, Object?>>{};
  final Map<String, List<CalculatedAttributeDefinition>>
  _baselineCalculatedAttributes =
      <String, List<CalculatedAttributeDefinition>>{};
  final Map<String, List<CalculatedAttributeDefinition>>
  _finalCalculatedAttributes = <String, List<CalculatedAttributeDefinition>>{};

  /// Table de correspondance immuable des alias résolus ou créés vers leur `repositoryId` réel.
  Map<String, String> get aliasToActualId => Map.unmodifiable(_aliasToActualId);

  /// Indique si au moins un repository a été créé ou effectivement modifié durant ce tour.
  bool get hasChanges {
    if (_createdRepositories.isNotEmpty) return true;
    for (final entry in _baselineDocuments.entries) {
      final finalDoc = _finalDocuments[entry.key];
      if (finalDoc != null &&
          !JsonRepositoryStore.jsonEquals(entry.value, finalDoc)) {
        return true;
      }
    }
    for (final entry in _baselineCalculatedAttributes.entries) {
      final finalCalc = _finalCalculatedAttributes[entry.key];
      if (finalCalc != null && !listEquals(entry.value, finalCalc)) {
        return true;
      }
    }
    return false;
  }

  /// Réécrit les alias de [vibePatch] à l'aide de la table [aliasToActualId] courante.
  Map<String, dynamic> rewriteVibePatchBindings(
    Map<String, dynamic> vibePatch,
  ) => VibeRepositoryApplier.rewriteVibePatchBindings(
    vibePatch,
    _aliasToActualId,
  );

  /// Valide puis applique de manière atomique et idempotente [rawRepositoriesPatch] sur [store].
  ///
  /// Peut être invoquée plusieurs fois au fil des paliers du streaming SSE puis lors
  /// de la validation finale : un même alias conserve toujours le même identifiant 32 hex
  /// et les fusions `'merge'` sur un repository préexistant repartent de son document initial.
  Future<Map<String, String>> applyRepositoriesPatch(
    Map<String, dynamic> rawRepositoriesPatch,
  ) async {
    final parsedEntries = VibeRepositoryPatchValidator.validateAndParse(
      rawRepositoriesPatch,
    );
    if (parsedEntries.isEmpty) {
      return aliasToActualId;
    }

    var catalog = await store.catalog();
    final inPatchDocuments = <String, Map<String, Object?>>{};
    final inPatchCalculated =
        <String, List<CalculatedAttributeDefinition>>{};

    for (final entry in parsedEntries.entries) {
      final repoKey = entry.key;
      final parsed = entry.value;

      var actualId = _aliasToActualId[repoKey] ?? _resolvedTargetByKey[repoKey];
      if (actualId == null) {
        final byId = catalog.where((c) => c.id == repoKey).firstOrNull;
        if (byId != null) {
          actualId = byId.id;
          _resolvedTargetByKey[repoKey] = actualId;
        } else {
          final lowerRepoKey = repoKey.toLowerCase();
          final lowerExplicitName = parsed.name?.toLowerCase();
          final byName = catalog.where((c) {
            final candidateName = c.name.toLowerCase();
            return candidateName == lowerRepoKey ||
                (lowerExplicitName != null &&
                    candidateName == lowerExplicitName);
          }).firstOrNull;

          if (byName != null) {
            actualId = byName.id;
            _resolvedTargetByKey[repoKey] = actualId;
            if (repoKey != actualId) {
              _aliasToActualId[repoKey] = actualId;
            }
          } else {
            actualId = _allocateUniqueHexId(repoKey, catalog);
            final chosenName = _chooseAvailableFileName(
              parsed.name ?? repoKey,
              catalog,
            );
            final initialDoc = _deepCopyJsonMap(parsed.data);
            await store.createWithId(
              chosenName,
              id: actualId,
              initialDocument: initialDoc,
            );
            if (parsed.hasCalculatedAttributes) {
              await store.saveCalculatedAttributes(
                actualId,
                parsed.calculatedAttributes,
              );
              _finalCalculatedAttributes[actualId] =
                  List<CalculatedAttributeDefinition>.of(
                    parsed.calculatedAttributes,
                  );
              inPatchCalculated[actualId] = _finalCalculatedAttributes[actualId]!;
            }
            _createdRepositories[actualId] = (name: chosenName, id: actualId);
            _aliasToActualId[repoKey] = actualId;
            _resolvedTargetByKey[repoKey] = actualId;
            _finalDocuments[actualId] = initialDoc;
            inPatchDocuments[actualId] = initialDoc;
            catalog = [...catalog, (name: chosenName, id: actualId)];
            continue;
          }
        }
      }

      final isCreatedInTurn = _createdRepositories.containsKey(actualId);
      if (!isCreatedInTurn && !_baselineDocuments.containsKey(actualId)) {
        final rawBaseline = await store.readDocument(actualId);
        _baselineDocuments[actualId] = rawBaseline is Map
            ? _deepCopyJsonMap(rawBaseline)
            : <String, Object?>{};
      }
      if (!isCreatedInTurn &&
          !_baselineCalculatedAttributes.containsKey(actualId)) {
        _baselineCalculatedAttributes[actualId] =
            List<CalculatedAttributeDefinition>.of(
              await store.readCalculatedAttributes(actualId),
            );
      }

      if (parsed.hasData) {
        final Map<String, Object?> targetDoc;
        if (inPatchDocuments.containsKey(actualId)) {
          targetDoc = parsed.mode == VibeRepositoryPatchMode.merge
              ? deepMergeJsonObjects(inPatchDocuments[actualId]!, parsed.data)
              : _deepCopyJsonMap(parsed.data);
        } else if (!isCreatedInTurn) {
          targetDoc = parsed.mode == VibeRepositoryPatchMode.merge
              ? deepMergeJsonObjects(_baselineDocuments[actualId]!, parsed.data)
              : _deepCopyJsonMap(parsed.data);
        } else {
          targetDoc = parsed.mode == VibeRepositoryPatchMode.merge
              ? deepMergeJsonObjects(
                  _finalDocuments[actualId] ?? const <String, Object?>{},
                  parsed.data,
                )
              : _deepCopyJsonMap(parsed.data);
        }

        await store.replaceDocumentById(actualId, targetDoc);
        inPatchDocuments[actualId] = targetDoc;
        _finalDocuments[actualId] = targetDoc;
      }

      if (parsed.hasCalculatedAttributes) {
        final List<CalculatedAttributeDefinition> targetCalc;
        if (inPatchCalculated.containsKey(actualId)) {
          targetCalc = parsed.mode == VibeRepositoryPatchMode.merge
              ? _mergeCalculatedAttributes(
                  inPatchCalculated[actualId]!,
                  parsed.calculatedAttributes,
                )
              : List<CalculatedAttributeDefinition>.of(
                  parsed.calculatedAttributes,
                );
        } else if (!isCreatedInTurn) {
          targetCalc = parsed.mode == VibeRepositoryPatchMode.merge
              ? _mergeCalculatedAttributes(
                  _baselineCalculatedAttributes[actualId]!,
                  parsed.calculatedAttributes,
                )
              : List<CalculatedAttributeDefinition>.of(
                  parsed.calculatedAttributes,
                );
        } else {
          targetCalc = parsed.mode == VibeRepositoryPatchMode.merge
              ? _mergeCalculatedAttributes(
                  _finalCalculatedAttributes[actualId] ?? const [],
                  parsed.calculatedAttributes,
                )
              : List<CalculatedAttributeDefinition>.of(
                  parsed.calculatedAttributes,
                );
        }
        await store.saveCalculatedAttributes(actualId, targetCalc);
        inPatchCalculated[actualId] = targetCalc;
        _finalCalculatedAttributes[actualId] = targetCalc;
      }
    }

    return aliasToActualId;
  }

  /// Valide chaque entrée de [rawRepositoriesPatch] individuellement, applique les entrées
  /// valides de manière idempotente et retourne les entrées rejetées sans bloquer les autres.
  Future<
    ({
      Map<String, String> aliasToActualId,
      Map<String, dynamic> appliedEntries,
      List<PatchRejectedEntry> rejectedEntries,
    })
  >
  applyRepositoriesPatchPartial(
    Map<String, dynamic> rawRepositoriesPatch,
  ) async {
    final validMap = <String, dynamic>{};
    final rejected = <PatchRejectedEntry>[];

    for (final entry in rawRepositoriesPatch.entries) {
      final key = entry.key;
      try {
        VibeRepositoryPatchValidator.parseEntry(key, entry.value);
        validMap[key] = entry.value;
      } on FormatException catch (error) {
        rejected.add(
          PatchRejectedEntry(
            section: 'repositories',
            key: key,
            message: error.message,
            rawValue: entry.value,
          ),
        );
      }
    }

    if (validMap.isNotEmpty) {
      await applyRepositoriesPatch(validMap);
    }
    return (
      aliasToActualId: aliasToActualId,
      appliedEntries: validMap,
      rejectedEntries: List<PatchRejectedEntry>.unmodifiable(rejected),
    );
  }

  /// Capture un point de sauvegarde immuable de l'état courant de la transaction.
  VibeRepositorySavepoint createSavepoint() => VibeRepositorySavepoint._(
    Map<String, String>.of(_assignedIdsByAlias),
    Map<String, String>.of(_aliasToActualId),
    Map<String, String>.of(_resolvedTargetByKey),
    {
      for (final entry in _baselineDocuments.entries)
        entry.key: _deepCopyJsonMap(entry.value),
    },
    Map<String, ({String name, String id})>.of(_createdRepositories),
    {
      for (final entry in _finalDocuments.entries)
        entry.key: _deepCopyJsonMap(entry.value),
    },
    {
      for (final entry in _baselineCalculatedAttributes.entries)
        entry.key: List<CalculatedAttributeDefinition>.of(entry.value),
    },
    {
      for (final entry in _finalCalculatedAttributes.entries)
        entry.key: List<CalculatedAttributeDefinition>.of(entry.value),
    },
  );

  /// Restaure le store et les tables internes exactement à l'état de [savepoint].
  Future<void> restoreSavepoint(VibeRepositorySavepoint savepoint) async {
    final extraCreated = [
      for (final entry in _createdRepositories.entries)
        if (!savepoint._createdRepositories.containsKey(entry.key)) entry.value,
    ];
    final restoreToBaseline = [
      for (final entry in _baselineDocuments.entries)
        if (!savepoint._finalDocuments.containsKey(entry.key)) entry,
    ];
    final restoreCalcToBaseline = [
      for (final entry in _baselineCalculatedAttributes.entries)
        if (!savepoint._finalCalculatedAttributes.containsKey(entry.key)) entry,
    ];

    _assignedIdsByAlias
      ..clear()
      ..addAll(savepoint._assignedIdsByAlias);
    _aliasToActualId
      ..clear()
      ..addAll(savepoint._aliasToActualId);
    _resolvedTargetByKey
      ..clear()
      ..addAll(savepoint._resolvedTargetByKey);
    _baselineDocuments
      ..clear()
      ..addAll({
        for (final entry in savepoint._baselineDocuments.entries)
          entry.key: _deepCopyJsonMap(entry.value),
      });
    _createdRepositories
      ..clear()
      ..addAll(savepoint._createdRepositories);
    _finalDocuments
      ..clear()
      ..addAll({
        for (final entry in savepoint._finalDocuments.entries)
          entry.key: _deepCopyJsonMap(entry.value),
      });
    _baselineCalculatedAttributes
      ..clear()
      ..addAll({
        for (final entry in savepoint._baselineCalculatedAttributes.entries)
          entry.key: List<CalculatedAttributeDefinition>.of(entry.value),
      });
    _finalCalculatedAttributes
      ..clear()
      ..addAll({
        for (final entry in savepoint._finalCalculatedAttributes.entries)
          entry.key: List<CalculatedAttributeDefinition>.of(entry.value),
      });

    for (final entry in restoreToBaseline) {
      await store.replaceDocumentById(entry.key, entry.value);
    }
    for (final entry in savepoint._finalDocuments.entries) {
      await store.replaceDocumentById(entry.key, entry.value);
    }
    for (final entry in restoreCalcToBaseline) {
      await store.saveCalculatedAttributes(entry.key, entry.value);
    }
    for (final entry in savepoint._finalCalculatedAttributes.entries) {
      await store.saveCalculatedAttributes(entry.key, entry.value);
    }
    for (final repo in extraCreated) {
      await store.deleteCreatedFileRepositoryById(repo.id);
    }
  }

  /// Annule intégralement toutes les créations et modifications de repositories de la tentative courante.
  Future<void> rollback() async {
    final baselines = List<MapEntry<String, Map<String, Object?>>>.of(
      _baselineDocuments.entries,
    );
    final calcBaselines =
        List<MapEntry<String, List<CalculatedAttributeDefinition>>>.of(
          _baselineCalculatedAttributes.entries,
        );
    final created = List<({String name, String id})>.of(
      _createdRepositories.values,
    );

    _baselineDocuments.clear();
    _createdRepositories.clear();
    _finalDocuments.clear();
    _baselineCalculatedAttributes.clear();
    _finalCalculatedAttributes.clear();
    _aliasToActualId.clear();
    _resolvedTargetByKey.clear();
    _assignedIdsByAlias.clear();

    for (final entry in baselines) {
      await store.replaceDocumentById(entry.key, entry.value);
    }
    for (final entry in calcBaselines) {
      await store.saveCalculatedAttributes(entry.key, entry.value);
    }
    for (final repo in created) {
      await store.deleteCreatedFileRepositoryById(repo.id);
    }
  }

  /// Construit une paire immuable de callbacks `undo` / `redo` si [hasChanges] est vrai, ou `null` sinon.
  VibeRepositoryHistoryCallbacks? buildHistoryCallbacks() {
    if (!hasChanges) return null;

    final createdSnapshot = List<({String name, String id})>.unmodifiable(
      _createdRepositories.values.toList(),
    );
    final baselineSnapshot = <String, Map<String, Object?>>{
      for (final entry in _baselineDocuments.entries)
        if (_finalDocuments.containsKey(entry.key) &&
            !JsonRepositoryStore.jsonEquals(
              entry.value,
              _finalDocuments[entry.key],
            ))
          entry.key: _deepCopyJsonMap(entry.value),
    };
    final finalSnapshot = <String, Map<String, Object?>>{
      for (final created in createdSnapshot)
        created.id: _deepCopyJsonMap(
          _finalDocuments[created.id] ?? const <String, Object?>{},
        ),
      for (final id in baselineSnapshot.keys)
        id: _deepCopyJsonMap(_finalDocuments[id] ?? const <String, Object?>{}),
    };
    final calcBaselineSnapshot =
        <String, List<CalculatedAttributeDefinition>>{
          for (final entry in _baselineCalculatedAttributes.entries)
            if (_finalCalculatedAttributes.containsKey(entry.key) &&
                !listEquals(
                  entry.value,
                  _finalCalculatedAttributes[entry.key],
                ))
              entry.key: List<CalculatedAttributeDefinition>.unmodifiable(
                entry.value,
              ),
        };
    final calcFinalSnapshot = <String, List<CalculatedAttributeDefinition>>{
      for (final created in createdSnapshot)
        if (_finalCalculatedAttributes.containsKey(created.id))
          created.id: List<CalculatedAttributeDefinition>.unmodifiable(
            _finalCalculatedAttributes[created.id]!,
          ),
      for (final id in calcBaselineSnapshot.keys)
        id: List<CalculatedAttributeDefinition>.unmodifiable(
          _finalCalculatedAttributes[id] ?? const [],
        ),
    };

    return (
      undo: () async {
        for (final entry in baselineSnapshot.entries) {
          await store.replaceDocumentById(
            entry.key,
            _deepCopyJsonMap(entry.value),
          );
        }
        for (final entry in calcBaselineSnapshot.entries) {
          await store.saveCalculatedAttributes(entry.key, entry.value);
        }
        for (final created in createdSnapshot) {
          await store.deleteCreatedFileRepositoryById(created.id);
        }
      },
      redo: () async {
        final existingCatalog = await store.catalog();
        final existingIds = <String>{
          for (final entry in existingCatalog) entry.id,
        };
        var currentCatalog = List<JsonRepositoryEntry>.of(existingCatalog);

        for (final created in createdSnapshot) {
          final doc = _deepCopyJsonMap(
            finalSnapshot[created.id] ?? const <String, Object?>{},
          );
          if (existingIds.contains(created.id)) {
            await store.replaceDocumentById(created.id, doc);
          } else {
            final chosenName = _chooseAvailableFileName(
              created.name,
              currentCatalog,
            );
            await store.createWithId(
              chosenName,
              id: created.id,
              initialDocument: doc,
            );
            existingIds.add(created.id);
            currentCatalog.add((name: chosenName, id: created.id));
          }
          final calcDefs = calcFinalSnapshot[created.id];
          if (calcDefs != null) {
            await store.saveCalculatedAttributes(created.id, calcDefs);
          }
        }
        for (final id in baselineSnapshot.keys) {
          final doc = finalSnapshot[id];
          if (doc != null) {
            await store.replaceDocumentById(id, _deepCopyJsonMap(doc));
          }
        }
        for (final id in calcBaselineSnapshot.keys) {
          final calcDefs = calcFinalSnapshot[id];
          if (calcDefs != null) {
            await store.saveCalculatedAttributes(id, calcDefs);
          }
        }
      },
    );
  }

  static List<CalculatedAttributeDefinition> _mergeCalculatedAttributes(
    List<CalculatedAttributeDefinition> base,
    List<CalculatedAttributeDefinition> patch,
  ) {
    final result = List<CalculatedAttributeDefinition>.of(base);
    for (final incoming in patch) {
      final idx = result.indexWhere((d) => d.path == incoming.path);
      if (idx >= 0) {
        result[idx] = incoming;
      } else {
        result.add(incoming);
      }
    }
    return result;
  }

  String _allocateUniqueHexId(
    String alias,
    List<JsonRepositoryEntry> catalog,
  ) {
    final existingIds = <String>{
      for (final entry in catalog) entry.id,
      ..._createdRepositories.keys,
    };
    final previous = _assignedIdsByAlias[alias];
    if (previous != null && !existingIds.contains(previous)) {
      return previous;
    }
    while (true) {
      final candidate = List<String>.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      if (!existingIds.contains(candidate) &&
          !_assignedIdsByAlias.containsValue(candidate)) {
        _assignedIdsByAlias[alias] = candidate;
        return candidate;
      }
    }
  }

  static String _chooseAvailableFileName(
    String rawDesiredName,
    List<JsonRepositoryEntry> catalog,
  ) {
    final baseName = JsonRepositoryStore.validateName(rawDesiredName);
    final usedNames = <String>{
      for (final entry in catalog) entry.name.toLowerCase(),
    };
    if (!usedNames.contains(baseName.toLowerCase())) {
      return baseName;
    }
    var suffix = 2;
    while (true) {
      final candidate = JsonRepositoryStore.validateName('${baseName}_$suffix');
      if (!usedNames.contains(candidate.toLowerCase())) {
        return candidate;
      }
      suffix++;
    }
  }
}

/// Point de sauvegarde immuable d'une [VibeRepositoryTurnTransaction] entre deux tentatives.
@immutable
class VibeRepositorySavepoint {
  const VibeRepositorySavepoint._(
    this._assignedIdsByAlias,
    this._aliasToActualId,
    this._resolvedTargetByKey,
    this._baselineDocuments,
    this._createdRepositories,
    this._finalDocuments,
    this._baselineCalculatedAttributes,
    this._finalCalculatedAttributes,
  );

  final Map<String, String> _assignedIdsByAlias;
  final Map<String, String> _aliasToActualId;
  final Map<String, String> _resolvedTargetByKey;
  final Map<String, Map<String, Object?>> _baselineDocuments;
  final Map<String, ({String name, String id})> _createdRepositories;
  final Map<String, Map<String, Object?>> _finalDocuments;
  final Map<String, List<CalculatedAttributeDefinition>>
  _baselineCalculatedAttributes;
  final Map<String, List<CalculatedAttributeDefinition>>
  _finalCalculatedAttributes;
}

Map<String, Object?> _deepCopyJsonMap(Map<Object?, Object?> map) =>
    <String, Object?>{
      for (final entry in map.entries)
        entry.key.toString(): _deepCopyJsonValue(entry.value),
    };

Object? _deepCopyJsonValue(Object? value) => switch (value) {
  Map() => _deepCopyJsonMap(value),
  List() => <Object?>[for (final item in value) _deepCopyJsonValue(item)],
  _ => value,
};
