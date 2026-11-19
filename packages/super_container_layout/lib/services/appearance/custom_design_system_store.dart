/// Persistance sur disque des systèmes de design `DESIGN.md` personnalisés ([CustomDesignSystemStore]).
///
/// Sauvegarde et recharge les [DesignSystemPreset] générés par Vibe IA ou importés dans
/// la galerie sous forme de fichiers `<slug>.md` autonomes avec frontmatter YAML, en
/// s'appuyant sur [DesignMdParser] pour garantir une sérialisation sans perte.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../ai/design_md_parser.dart';
import '../../ai/design_system_catalog.dart';
import '../repositories/json_repository_store.dart';

/// Taille maximale autorisée pour un fichier `DESIGN.md` personnalisé sur disque (1 Mo).
const int customDesignSystemMaxFileBytes = 1024 * 1024;

/// Magasin de fichiers `.md` pour les [DesignSystemPreset] personnalisés.
class CustomDesignSystemStore {
  /// Crée un magasin lisant et écrivant les fichiers `DESIGN.md` dans [directory].
  CustomDesignSystemStore(this.directory);

  /// Crée un magasin stockant les fichiers sous `<store.directory>/design_systems`.
  factory CustomDesignSystemStore.forRepositoryStore(
    JsonRepositoryStore store,
  ) => CustomDesignSystemStore(
    Directory(
      '${store.directory.path}${Platform.pathSeparator}design_systems',
    ),
  );

  /// Crée le magasin utilisateur par défaut sous `~/.super_container_layout/design_systems`.
  factory CustomDesignSystemStore.defaultStore() {
    final store = tryDefaultStore();
    if (store == null) {
      throw const FileSystemException('Dossier utilisateur introuvable.');
    }
    return store;
  }

  /// Tente de résoudre le magasin utilisateur par défaut, ou retourne `null` si indisponible.
  static CustomDesignSystemStore? tryDefaultStore() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) return null;
    return CustomDesignSystemStore(
      Directory(
        '$home${Platform.pathSeparator}.super_container_layout'
        '${Platform.pathSeparator}design_systems',
      ),
    );
  }

  /// Dossier racine contenant les fichiers `<slug>.md`.
  final Directory directory;

  Future<void> _queue = Future<void>.value();

  Future<R> _serial<R>(Future<R> Function() action) {
    final completer = Completer<R>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Calcule le nom de fichier `.md` déterministe associé à l'identifiant [id].
  static String fileNameForId(String id) {
    var raw = id.trim();
    if (raw.toLowerCase().startsWith('custom:')) {
      raw = raw.substring('custom:'.length);
    }
    final slug = DesignMdParser.slugify(raw);
    return '$slug.md';
  }

  /// Retourne le fichier cible associé à [preset].
  File fileForPreset(DesignSystemPreset preset) => File(
    '${directory.path}${Platform.pathSeparator}${fileNameForId(preset.id)}',
  );

  /// Charge tous les systèmes de design `.md` valides présents dans [directory].
  ///
  /// Les fichiers illisibles, vides ou liens symboliques sont ignorés sans interrompre
  /// le chargement des autres chartes.
  Future<List<DesignSystemPreset>> loadAll() => _serial(() async {
    final dirType = FileSystemEntity.typeSync(
      directory.path,
      followLinks: false,
    );
    if (dirType != FileSystemEntityType.directory) {
      return const <DesignSystemPreset>[];
    }

    final entries = <({DateTime modified, DesignSystemPreset preset})>[];
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final lowerPath = entity.path.toLowerCase();
      if (!lowerPath.endsWith('.md') && !lowerPath.endsWith('.markdown')) {
        continue;
      }
      try {
        final type = FileSystemEntity.typeSync(
          entity.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file) continue;
        final stat = entity.statSync();
        if (stat.size <= 0 || stat.size > customDesignSystemMaxFileBytes) {
          continue;
        }
        final content = entity.readAsStringSync(encoding: utf8);
        if (content.trim().isEmpty) continue;
        final fileName = entity.uri.pathSegments.last;
        final parsed = DesignMdParser.parseExternal(
          content,
          fileName: fileName,
        );
        entries.add((modified: stat.modified, preset: parsed));
      } on Object {
        // Ignore un fichier corrompu ou non conforme pour préserver les autres.
      }
    }

    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return List<DesignSystemPreset>.unmodifiable(
      entries.map((entry) => entry.preset),
    );
  });

  /// Enregistre [preset] sur disque au format `DESIGN.md` complet et retourne son [File].
  Future<File> save(DesignSystemPreset preset) => _serial(() async {
    final parentType = FileSystemEntity.typeSync(
      directory.path,
      followLinks: false,
    );
    if (parentType == FileSystemEntityType.link) {
      throw FileSystemException(
        'Le dossier design_systems ne peut pas être un lien symbolique.',
        directory.path,
      );
    }
    if (parentType == FileSystemEntityType.notFound) {
      directory.createSync(recursive: true);
    }

    final target = fileForPreset(preset);
    final targetType = FileSystemEntity.typeSync(
      target.path,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.link) {
      throw FileSystemException(
        'Le fichier cible ne peut pas être un lien symbolique.',
        target.path,
      );
    }

    final content = DesignMdParser.toMarkdownWithFrontmatter(preset);
    final temp = File(
      '${target.path}.tmp.$pid.${Random().nextInt(1 << 30)}',
    );
    try {
      temp.writeAsStringSync(content, encoding: utf8, flush: true);
      temp.renameSync(target.path);
    } catch (_) {
      if (temp.existsSync()) {
        temp.deleteSync();
      }
      rethrow;
    }
    return target;
  });

  /// Supprime le fichier correspondant à [id] s'il existe ; retourne `true` s'il a été supprimé.
  Future<bool> delete(String id) => _serial(() async {
    final target = File(
      '${directory.path}${Platform.pathSeparator}${fileNameForId(id)}',
    );
    final targetType = FileSystemEntity.typeSync(
      target.path,
      followLinks: false,
    );
    if (targetType != FileSystemEntityType.file) {
      return false;
    }
    target.deleteSync();
    return true;
  });
}
