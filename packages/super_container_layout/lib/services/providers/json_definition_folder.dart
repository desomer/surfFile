/// Persistance partagée des définitions JSON de l'éditeur
/// ([JsonDefinitionFolder]).
///
/// Les providers (`<store>/providers/<id>.json`) et les datasources
/// (`<store>/datasources/<id>.json`) sont stockés un fichier par définition.
/// Ce dossier sérialise les opérations de fichier, borne le nombre et la
/// taille des fichiers lus, refuse les liens symboliques et écrit chaque
/// fichier de manière atomique (fichier temporaire puis renommage).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Taille maximale d'un fichier de définition.
const jsonDefinitionMaxFileBytes = 256 * 1024;

/// Dossier de définitions JSON `<id>.json` de type [T].
class JsonDefinitionFolder<T> {
  /// Crée l'accès au dossier retourné par [directory] (relu à chaque
  /// opération).
  ///
  /// [ofOne] et [plural] nomment les définitions dans les messages
  /// (« du provider », « providers ») ; [decode] lit et valide un fichier,
  /// [encode] produit sa forme JSON et [idOf] son identifiant ; [isValidId]
  /// filtre les noms de fichier acceptés.
  JsonDefinitionFolder({
    required this._directory,
    required this.ofOne,
    required this.plural,
    required this.maxFiles,
    required this.decode,
    required this.encode,
    required this.idOf,
    required this.isValidId,
  });

  final Directory Function() _directory;

  /// Complément du nom d'une définition dans les messages (« du provider »,
  /// « de la datasource »).
  final String ofOne;

  /// Nom de plusieurs définitions dans les messages.
  final String plural;

  /// Nombre maximal de fichiers chargés.
  final int maxFiles;

  /// Lit une définition depuis son JSON décodé (lève une [FormatException]).
  final T Function(Object? json) decode;

  /// Forme JSON écrite dans le fichier.
  final Map<String, Object?> Function(T value) encode;

  /// Identifiant (nom du fichier sans `.json`) d'une définition.
  final String Function(T value) idOf;

  /// Vrai si [id] est un identifiant de fichier accepté.
  final bool Function(String id) isValidId;

  Future<void> _queue = Future.value();

  /// Dossier courant.
  Directory get folder => _directory();

  File _fileOf(String id) =>
      File('${folder.path}${Platform.pathSeparator}$id.json');

  /// Exécute [action] après les opérations de fichier précédentes.
  Future<R> serial<R>(Future<R> Function() action) {
    final result = Completer<R>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  /// Lit toutes les définitions du dossier ; les fichiers invalides sont
  /// ignorés et décrits dans `problems` (via [describe]).
  Future<({Map<String, T> loaded, List<String> problems})> readAll({
    required String Function(Object error) describe,
  }) async {
    final loaded = <String, T>{};
    final problems = <String>[];
    final directory = folder;
    try {
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File || !entity.path.endsWith('.json')) continue;
          final name = entity.uri.pathSegments.last;
          final id = name.substring(0, name.length - '.json'.length);
          if (loaded.length >= maxFiles) {
            problems.add('au plus $maxFiles $plural sont chargés');
            break;
          }
          try {
            loaded[id] = await _read(entity, id);
          } on Object catch (error) {
            problems.add('« $id » : ${describe(error)}');
          }
        }
      }
    } on FileSystemException catch (error) {
      problems.add('dossier illisible : ${error.message}');
    }
    return (loaded: loaded, problems: problems);
  }

  Future<T> _read(File file, String id) async {
    if (!isValidId(id)) {
      throw const FormatException(
        'le nom du fichier doit utiliser a-z, 0-9 et _ (32 caractères au plus).',
      );
    }
    if (await file.length() > jsonDefinitionMaxFileBytes) {
      throw const FormatException('fichier trop volumineux.');
    }
    final Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const FormatException('JSON invalide.');
    }
    final value = decode(json);
    if (idOf(value) != id) {
      throw const FormatException('l’identifiant doit être celui du fichier.');
    }
    return value;
  }

  /// Écrit [value] de manière atomique dans `<id>.json` (dossier créé si
  /// besoin) ; refuse un dossier ou un fichier qui n'est pas ordinaire.
  Future<void> write(T value) async {
    final directory = folder;
    final folderType = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (folderType == FileSystemEntityType.notFound) {
      await directory.create(recursive: true);
    } else if (folderType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Dossier des $plural invalide ou lien refusé.',
        directory.path,
      );
    }
    final file = _fileOf(idOf(value));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Fichier $ofOne invalide ou lien refusé.',
        file.path,
      );
    }
    final text =
        '${const JsonEncoder.withIndent('  ').convert(encode(value))}\n';
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = File('${file.path}.$suffix.tmp');
    await temporary.create(exclusive: true);
    try {
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temporary.delete();
      }
    }
  }

  /// Supprime `<id>.json` s'il existe ; refuse un lien ou un dossier.
  Future<void> delete(String id) async {
    final file = _fileOf(id);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await file.delete();
    } else if (type != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Fichier $ofOne invalide ou lien refusé.',
        file.path,
      );
    }
  }
}
