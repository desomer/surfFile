/// Persistance locale du dictionnaire technique et des préférences globales de modélisation ([ModelDictionaryStore]).
///
/// Stocke le référentiel global dans un découpage adapté à Git :
/// - `<rootDirectory>/dictionary/preferences.json` (conventions et préférences) ;
/// - `<rootDirectory>/dictionary/rules/<slug>.json` (1 fichier par règle technique + `_order.json`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/business_object_model_preferences.dart';
import '../models/technical_modeling_rule.dart';
import 'spec_project_store.dart';
import 'spec_storage_slug.dart';

/// Magasin disque persistant les [BusinessObjectModelPreferences] et le dictionnaire
/// de règles techniques à l'échelle globale de l'application.
class ModelDictionaryStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  ModelDictionaryStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? SpecProjectStore.defaultRootDirectory();

  /// Identifiant de format du fichier JSON des préférences globales.
  static const String fileFormat = 'super_spec_forge.model_dictionary';

  /// Identifiant de format d'un fichier règle technique unitaire.
  static const String ruleFormat = 'super_spec_forge.technical_rule';

  /// Identifiant de format d'un fichier d'ordre `_order.json`.
  static const String orderFormat = 'super_spec_forge.order';

  /// Version courante du format persisté.
  static const int storageVersion = 3;

  /// Dossier racine du workspace.
  final Directory rootDirectory;

  Future<void> _opQueue = Future<void>.value();
  int _tmpCounter = 0;

  /// Sous-dossier `dictionary/`.
  Directory get dictionaryDirectory =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}dictionary');

  /// Sous-dossier `dictionary/rules/`.
  Directory get rulesDirectory =>
      Directory('${dictionaryDirectory.path}${Platform.pathSeparator}rules');

  /// Fichier JSON des préférences globales (`dictionary/preferences.json`).
  File get dictionaryFile => File(
    '${dictionaryDirectory.path}${Platform.pathSeparator}preferences.json',
  );

  /// Fichier d'ordre `dictionary/rules/_order.json`.
  File get rulesOrderFile =>
      File('${rulesDirectory.path}${Platform.pathSeparator}_order.json');

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final prev = _opQueue;
    final completer = Completer<void>();
    final next = prev.catchError((_) {}).then((_) => action());
    _opQueue = completer.future;
    return next.whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }

  /// Charge le dictionnaire global (retourne [BusinessObjectModelPreferences.defaults] si absent).
  Future<BusinessObjectModelPreferences> load() => _enqueue(() async {
    final hasPrefs = await dictionaryFile.exists();
    final hasRulesDir = await rulesDirectory.exists();
    if (!hasPrefs && !hasRulesDir) {
      return BusinessObjectModelPreferences.defaults;
    }

    var basePrefs = BusinessObjectModelPreferences.defaults;
    if (hasPrefs) {
      final raw = jsonDecode(await dictionaryFile.readAsString());
      if (raw is! Map) {
        throw const FormatException(
          'dictionary/preferences.json doit être un objet JSON.',
        );
      }
      final payload = raw['data'] is Map ? raw['data'] : raw;
      basePrefs = BusinessObjectModelPreferences.fromJson(payload);
    }

    if (!hasRulesDir) {
      return basePrefs;
    }

    final rules = await _loadRules();
    return basePrefs.copyWith(technicalRules: rules);
  });

  Future<List<TechnicalModelingRule>> _loadRules() async {
    final files = <File>[];
    await for (final entity in rulesDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name.contains('.tmp.') ||
          name == '_order.json' ||
          !name.toLowerCase().endsWith('.json')) {
        continue;
      }
      files.add(entity);
    }
    files.sort(
      (a, b) => SpecStorageIo.fileNameOf(a.path)
          .toLowerCase()
          .compareTo(SpecStorageIo.fileNameOf(b.path).toLowerCase()),
    );

    final parsed = await Future.wait<TechnicalModelingRule>(
      files.map((file) async {
        final decoded = jsonDecode(await file.readAsString());
        final payload = (decoded is Map && decoded['data'] is Map)
            ? decoded['data']
            : decoded;
        return TechnicalModelingRule.fromJson(payload);
      }),
    );

    if (!await rulesOrderFile.exists()) return parsed;
    try {
      final rawOrder = jsonDecode(await rulesOrderFile.readAsString());
      final ids = rawOrder is Map ? rawOrder['ids'] : null;
      if (ids is! List) return parsed;
      final byId = <String, TechnicalModelingRule>{
        for (final rule in parsed) rule.id: rule,
      };
      final ordered = <TechnicalModelingRule>[];
      final placed = <String>{};
      for (final rawId in ids) {
        if (rawId is! String) continue;
        final item = byId[rawId];
        if (item != null && placed.add(rawId)) {
          ordered.add(item);
        }
      }
      for (final rule in parsed) {
        if (placed.add(rule.id)) {
          ordered.add(rule);
        }
      }
      return ordered;
    } catch (_) {
      return parsed;
    }
  }

  /// Sauvegarde incrémentalement et atomiquement [preferences] sur disque.
  Future<void> save(BusinessObjectModelPreferences preferences) {
    preferences.validate();
    return _enqueue(() async {
      final prefsData = Map<String, Object?>.from(preferences.toJson())
        ..remove('technicalRules');
      await SpecStorageIo.writeJsonAtomicallyIfChanged(
        dictionaryFile,
        <String, Object?>{
          'format': fileFormat,
          'version': storageVersion,
          'data': prefsData,
        },
        nextTmpId: () => _tmpCounter++,
      );

      final fileMap = SpecStorageSlug.assignUniqueJsonFiles<TechnicalModelingRule>(
        preferences.technicalRules,
        labelFor: (r) =>
            r.name.trim().isNotEmpty ? r.name : r.suffixOrPattern,
        idFor: (r) => r.id,
        fallback: 'rule',
        separator: '-',
      );

      final keepFiles = <String>{...fileMap.keys};
      final writes = <Future<bool>>[];
      if (preferences.technicalRules.isNotEmpty) {
        keepFiles.add('_order.json');
        writes.add(
          SpecStorageIo.writeJsonAtomicallyIfChanged(
            rulesOrderFile,
            <String, Object?>{
              'format': orderFormat,
              'version': storageVersion,
              'ids': [for (final r in preferences.technicalRules) r.id],
            },
            nextTmpId: () => _tmpCounter++,
          ),
        );
      }

      for (final entry in fileMap.entries) {
        writes.add(
          SpecStorageIo.writeJsonAtomicallyIfChanged(
            File('${rulesDirectory.path}${Platform.pathSeparator}${entry.key}'),
            <String, Object?>{
              'format': ruleFormat,
              'version': storageVersion,
              'data': entry.value.toJson(),
            },
            nextTmpId: () => _tmpCounter++,
          ),
        );
      }

      if (writes.isNotEmpty) {
        await Future.wait(writes);
      }
      await SpecStorageIo.pruneUnexpectedFiles(rulesDirectory, keepFiles);
    });
  }
}
