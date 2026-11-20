/// Persistance locale multi-projets sur disque pour `super_spec_forge` ([SpecProjectStore]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';

/// Métadonnées légères d'un projet sauvegardé sur disque.
@immutable
class SpecProjectSummary {
  /// Construit un résumé de projet.
  const SpecProjectSummary({
    required this.id,
    required this.name,
    required this.initialIdea,
    required this.currentStage,
    required this.updatedAt,
    required this.objectCount,
    required this.ruleCount,
  });

  /// Identifiant unique du projet.
  final String id;

  /// Nom du projet.
  final String name;

  /// Idée initiale.
  final String initialIdea;

  /// Étape active lors de la dernière sauvegarde.
  final SpecForgeStage currentStage;

  /// Date de dernière modification.
  final DateTime updatedAt;

  /// Nombre d'objets métiers modélisés.
  final int objectCount;

  /// Nombre de règles de gestion formalisées.
  final int ruleCount;
}

/// Magasin disque persistant les projets `SpecForgeProject` en JSON.
class SpecProjectStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  SpecProjectStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? defaultRootDirectory();

  /// Dossier racine du magasin.
  final Directory rootDirectory;

  /// Dossier par défaut sous le répertoire utilisateur (`~/.super_spec_forge`).
  static Directory defaultRootDirectory() {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final sep = Platform.pathSeparator;
    final cleanHome = home.endsWith(sep) && home.length > 1
        ? home.substring(0, home.length - 1)
        : home;
    return Directory('$cleanHome$sep.super_spec_forge');
  }

  Directory get _projectsDir =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}projects');

  File get _indexFile =>
      File('${rootDirectory.path}${Platform.pathSeparator}index.json');

  File _projectFile(String projectId) {
    final safeId = projectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(
      '${_projectsDir.path}${Platform.pathSeparator}$safeId${Platform.pathSeparator}project.json',
    );
  }

  /// Sauvegarde atomiquement [project] sur disque et le marque comme dernier projet actif.
  Future<void> saveProject(SpecForgeProject project) async {
    project.validate();
    final file = _projectFile(project.id);
    await file.parent.create(recursive: true);
    final encoded = const JsonEncoder.withIndent('  ').convert(project.toJson());
    await file.writeAsString(encoded, flush: true);
    await setLastActiveProjectId(project.id);
  }

  /// Charge un projet depuis son [projectId], ou retourne `null` s'il est introuvable.
  Future<SpecForgeProject?> loadProject(String projectId) async {
    final file = _projectFile(projectId);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    return SpecForgeProject.fromJson(decoded);
  }

  /// Supprime définitivement un projet du disque.
  Future<void> deleteProject(String projectId) async {
    final dir = _projectFile(projectId).parent;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final activeId = await getLastActiveProjectId();
    if (activeId == projectId) {
      await setLastActiveProjectId(null);
    }
  }

  /// Liste tous les projets valides présents sur disque, triés du plus récent au plus ancien.
  Future<List<SpecProjectSummary>> listProjects() async {
    if (!await _projectsDir.exists()) return const <SpecProjectSummary>[];
    final summaries = <SpecProjectSummary>[];
    await for (final entity in _projectsDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final file = File(
        '${entity.path}${Platform.pathSeparator}project.json',
      );
      if (!await file.exists()) continue;
      try {
        final project = SpecForgeProject.fromJson(
          jsonDecode(await file.readAsString()),
        );
        summaries.add(
          SpecProjectSummary(
            id: project.id,
            name: project.name,
            initialIdea: project.initialIdea,
            currentStage: project.currentStage,
            updatedAt: project.updatedAt,
            objectCount: project.businessObjects.length,
            ruleCount: project.businessRules.length,
          ),
        );
      } catch (_) {
        // Ignore un dossier corrompu sans bloquer les autres projets.
      }
    }
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<SpecProjectSummary>.unmodifiable(summaries);
  }

  /// Lit l'identifiant du dernier projet ouvert, ou `null`.
  Future<String?> getLastActiveProjectId() async {
    if (!await _indexFile.exists()) return null;
    try {
      final decoded = jsonDecode(await _indexFile.readAsString());
      if (decoded is Map && decoded['lastActiveProjectId'] is String) {
        final id = (decoded['lastActiveProjectId'] as String).trim();
        return id.isEmpty ? null : id;
      }
    } catch (_) {}
    return null;
  }

  /// Mémorise l'identifiant du dernier projet actif dans `index.json`.
  Future<void> setLastActiveProjectId(String? projectId) async {
    await rootDirectory.create(recursive: true);
    final payload = <String, Object?>{'lastActiveProjectId': projectId};
    await _indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }
}
