/// Persistance locale du dictionnaire technique et des préférences globales de modélisation ([ModelDictionaryStore]).
///
/// Stocke le référentiel global dans `<rootDirectory>/model_dictionary.json`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/business_object_model_preferences.dart';
import 'spec_project_store.dart';

/// Magasin disque persistant les [BusinessObjectModelPreferences] et le dictionnaire
/// de règles techniques à l'échelle globale de l'application.
class ModelDictionaryStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  ModelDictionaryStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? SpecProjectStore.defaultRootDirectory();

  /// Identifiant de format du fichier JSON.
  static const String fileFormat = 'super_spec_forge.model_dictionary';

  /// Version du format persisté.
  static const int storageVersion = 1;

  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  /// Dossier racine du magasin.
  final Directory rootDirectory;

  Future<void> _opQueue = Future<void>.value();
  int _tmpCounter = 0;

  /// Fichier JSON persisté sur disque.
  File get dictionaryFile =>
      File('${rootDirectory.path}${Platform.pathSeparator}model_dictionary.json');

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
    if (!await dictionaryFile.exists()) {
      return BusinessObjectModelPreferences.defaults;
    }
    final raw = jsonDecode(await dictionaryFile.readAsString());
    if (raw is! Map) {
      throw const FormatException(
        'model_dictionary.json doit être un objet JSON.',
      );
    }
    final payload = raw['data'] is Map ? raw['data'] : raw;
    return BusinessObjectModelPreferences.fromJson(payload);
  });

  /// Sauvegarde atomiquement [preferences] sur disque.
  Future<void> save(BusinessObjectModelPreferences preferences) {
    preferences.validate();
    return _enqueue(() async {
      await dictionaryFile.parent.create(recursive: true);
      final tmp = File('${dictionaryFile.path}.tmp.${_tmpCounter++}');
      final encoded = _prettyEncoder.convert(<String, Object?>{
        'format': fileFormat,
        'version': storageVersion,
        'data': preferences.toJson(),
      });
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(dictionaryFile.path);
    });
  }
}
