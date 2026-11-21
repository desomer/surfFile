/// Persistance atomique du catalogue des domaines fonctionnels ([DomainCatalogStore]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/domain_catalog.dart';
import 'spec_project_store.dart';
import 'spec_storage_slug.dart';

/// Stocke le catalogue dans `<workspace>/domains/catalog.json`.
class DomainCatalogStore {
  /// Crée un store ancré sur [rootDirectory].
  DomainCatalogStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? SpecProjectStore.defaultRootDirectory();

  /// Identifiant de format du catalogue.
  static const String fileFormat = 'super_spec_forge.domain_catalog';

  /// Version du format persisté.
  static const int storageVersion = 1;

  /// Dossier racine du workspace.
  final Directory rootDirectory;
  Future<void> _opQueue = Future<void>.value();
  int _tmpCounter = 0;

  /// Dossier `domains/`.
  Directory get domainsDirectory =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}domains');

  /// Fichier contenant le catalogue.
  File get catalogFile =>
      File('${domainsDirectory.path}${Platform.pathSeparator}catalog.json');

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final previous = _opQueue;
    final completer = Completer<void>();
    final next = previous.catchError((_) {}).then((_) => action());
    _opQueue = completer.future;
    return next.whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
  }

  /// Charge le catalogue ou renvoie [DomainCatalog.empty] si absent.
  Future<DomainCatalog> load() => _enqueue(() async {
    if (!await catalogFile.exists()) return DomainCatalog.empty;
    final raw = jsonDecode(await catalogFile.readAsString());
    if (raw is! Map) {
      throw const FormatException('domains/catalog.json doit être un objet JSON.');
    }
    final format = raw['format'];
    if (format != null && format != fileFormat) {
      throw const FormatException('Format de catalogue de domaines inconnu.');
    }
    return DomainCatalog.fromJson(raw['data'] ?? raw);
  });

  /// Valide et sauvegarde atomiquement le catalogue, sans permettre de réécrire
  /// ou de supprimer les événements déjà consignés.
  Future<void> save(DomainCatalog catalog) => _enqueue(() async {
    catalog.validate();
    if (await catalogFile.exists()) {
      final raw = jsonDecode(await catalogFile.readAsString());
      if (raw is! Map) {
        throw const FormatException(
          'domains/catalog.json doit être un objet JSON.',
        );
      }
      final previous = DomainCatalog.fromJson(raw['data'] ?? raw);
      if (catalog.auditLog.length < previous.auditLog.length) {
        throw StateError('Le journal d’audit ne peut pas être raccourci.');
      }
      for (var index = 0; index < previous.auditLog.length; index++) {
        if (jsonEncode(catalog.auditLog[index].toJson()) !=
            jsonEncode(previous.auditLog[index].toJson())) {
          throw StateError('Les événements d’audit existants sont immuables.');
        }
      }
    }
    await SpecStorageIo.writeJsonAtomicallyIfChanged(
      catalogFile,
      <String, Object?>{
        'format': fileFormat,
        'version': storageVersion,
        'data': catalog.toJson(),
      },
      nextTmpId: () => _tmpCounter++,
    );
  });
}
