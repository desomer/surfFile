/// Modèles immuables d'un projet de domaine complet dans `super_backend_editor`
/// ([BackendDomainProject]) et de son résumé d'index ([BackendDomainProjectSummary]).
library;

import 'package:flutter/foundation.dart';

import 'backend_overlay_config.dart';
import 'domain_design_diff.dart';
import 'domain_design_spec.dart';
import 'json_value_utils.dart';

/// Résumé léger d'un projet de domaine persisté dans `workspace.json`.
@immutable
class BackendDomainProjectSummary {
  /// Crée un résumé de projet de domaine immuable.
  BackendDomainProjectSummary({
    required this.domainCode,
    required this.domainName,
    DateTime? lastImportedAt,
    this.modelsCount = 0,
    this.useCasesCount = 0,
    this.collectionsCount = 0,
  }) : lastImportedAt = (lastImportedAt ??
               DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc();

  /// Extrait le résumé d'un [BackendDomainProject] complet.
  factory BackendDomainProjectSummary.fromProject(
    BackendDomainProject project,
  ) {
    final latestImport = project.importHistory.isNotEmpty
        ? project.importHistory.last.importedAt
        : project.designSpec.exportedAt;
    return BackendDomainProjectSummary(
      domainCode: project.domainCode,
      domainName: project.domainName,
      lastImportedAt: latestImport,
      modelsCount: project.designSpec.models.length,
      useCasesCount: project.designSpec.useCases.length,
      collectionsCount: project.overlay.collections.length,
    );
  }

  /// Code canonique du domaine (`kebab-case`).
  final String domainCode;

  /// Nom lisible du domaine.
  final String domainName;

  /// Date UTC du dernier import Design.
  final DateTime lastImportedAt;

  /// Nombre de modèles persistants dans la spécification Design.
  final int modelsCount;

  /// Nombre de Use Cases CQRS dans la spécification Design.
  final int useCasesCount;

  /// Nombre de collections provisionnées dans l'overlay Backend.
  final int collectionsCount;

  /// Vérifie les invariants du résumé.
  void validate() {
    if (domainCode.trim().isEmpty) {
      throw const FormatException(
        'BackendDomainProjectSummary.domainCode requis.',
      );
    }
    if (domainName.trim().isEmpty) {
      throw const FormatException(
        'BackendDomainProjectSummary.domainName requis.',
      );
    }
    if (modelsCount < 0 || useCasesCount < 0 || collectionsCount < 0) {
      throw const FormatException(
        'Les compteurs de BackendDomainProjectSummary doivent être positifs.',
      );
    }
  }

  /// Retourne une copie modifiée.
  BackendDomainProjectSummary copyWith({
    String? domainCode,
    String? domainName,
    DateTime? lastImportedAt,
    int? modelsCount,
    int? useCasesCount,
    int? collectionsCount,
  }) => BackendDomainProjectSummary(
    domainCode: domainCode ?? this.domainCode,
    domainName: domainName ?? this.domainName,
    lastImportedAt: lastImportedAt ?? this.lastImportedAt,
    modelsCount: modelsCount ?? this.modelsCount,
    useCasesCount: useCasesCount ?? this.useCasesCount,
    collectionsCount: collectionsCount ?? this.collectionsCount,
  );

  /// Sérialise le résumé en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'domainCode': domainCode,
    'domainName': domainName,
    'lastImportedAt': lastImportedAt.toUtc().toIso8601String(),
    'modelsCount': modelsCount,
    'useCasesCount': useCasesCount,
    'collectionsCount': collectionsCount,
  };

  /// Désérialise un résumé depuis JSON.
  factory BackendDomainProjectSummary.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendDomainProjectSummary invalide.');
    }
    int parseCount(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s.trim()) ?? 0,
      _ => 0,
    };

    final code = (raw['domainCode'] as String?)?.trim() ?? '';
    final name = (raw['domainName'] as String?)?.trim() ?? '';
    final item = BackendDomainProjectSummary(
      domainCode: code,
      domainName: name.isEmpty ? code : name,
      lastImportedAt: parseUtcDateTimeOrEpoch(raw['lastImportedAt']),
      modelsCount: parseCount(raw['modelsCount']),
      useCasesCount: parseCount(raw['useCasesCount']),
      collectionsCount: parseCount(raw['collectionsCount']),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendDomainProjectSummary &&
          other.domainCode == domainCode &&
          other.domainName == domainName &&
          other.lastImportedAt == lastImportedAt &&
          other.modelsCount == modelsCount &&
          other.useCasesCount == useCasesCount &&
          other.collectionsCount == collectionsCount;

  @override
  int get hashCode => Object.hash(
    domainCode,
    domainName,
    lastImportedAt,
    modelsCount,
    useCasesCount,
    collectionsCount,
  );
}

/// Agrégat immuable réunissant la couche Design en lecture seule, la surcouche
/// d'implémentation Backend éditable, l'historique d'imports et les valeurs
/// locales de test des secrets d'un domaine métier.
@immutable
class BackendDomainProject {
  /// Crée un projet de domaine Backend immuable.
  BackendDomainProject({
    required this.designSpec,
    required this.overlay,
    List<DomainImportHistoryRecord> importHistory =
        const <DomainImportHistoryRecord>[],
    Map<String, Map<String, String>> localSecretValues =
        const <String, Map<String, String>>{},
  }) : importHistory = List<DomainImportHistoryRecord>.unmodifiable(
         importHistory,
       ),
       localSecretValues = freezeNestedStringMap(localSecretValues);

  /// Crée un nouveau projet initialisé à partir d'une [DomainDesignSpec].
  factory BackendDomainProject.bootstrap(
    DomainDesignSpec designSpec, {
    List<DomainImportHistoryRecord> importHistory =
        const <DomainImportHistoryRecord>[],
    Map<String, Map<String, String>> localSecretValues =
        const <String, Map<String, String>>{},
  }) {
    final project = BackendDomainProject(
      designSpec: designSpec,
      overlay: BackendOverlayConfig.bootstrapFromDesign(designSpec),
      importHistory: importHistory,
      localSecretValues: localSecretValues,
    );
    project.validate();
    return project;
  }

  /// Spécification Design importée (couche strictement en lecture seule).
  final DomainDesignSpec designSpec;

  /// Configuration Backend locale (couche éditable préservée au ré-import).
  final BackendOverlayConfig overlay;

  /// Historique chronologique des imports et ré-imports Design.
  final List<DomainImportHistoryRecord> importHistory;

  /// Valeurs de test locales des clés secrètes par environnement (`envId -> {SECRET_KEY: valeur}`).
  ///
  /// Persistées exclusivement sous `.local/secrets_<domainCode>.json` et jamais exportées.
  final Map<String, Map<String, String>> localSecretValues;

  /// Code canonique du domaine (`designSpec.domain.domainCode`).
  String get domainCode => designSpec.domain.domainCode;

  /// Nom affiché du domaine (`designSpec.domain.name`).
  String get domainName => designSpec.domain.name;

  /// Construit le résumé d'index de ce projet.
  BackendDomainProjectSummary toSummary() =>
      BackendDomainProjectSummary.fromProject(this);

  /// Résout la carte effective des variables d'environnement pour [environmentId]
  /// (ou `overlay.activeEnvironmentId` si omis), en fusionnant variables Design
  /// en clair, surcharges locales et valeurs de test locales des secrets.
  Map<String, String> resolveEnvironmentVariables([String? environmentId]) {
    final targetEnvId =
        environmentId ??
        overlay.activeEnvironmentId ??
        designSpec.environments.firstOrNull?.id;
    if (targetEnvId == null || targetEnvId.isEmpty) {
      return const <String, String>{};
    }
    final resolved = <String, String>{};
    for (final cfg in designSpec.configurations) {
      if (cfg.environmentId != targetEnvId) continue;
      if (!cfg.isSecret && cfg.plainValue != null) {
        resolved[cfg.configKey] = cfg.plainValue!;
      }
    }
    final plainOverrides = overlay.environmentVariableOverrides[targetEnvId];
    if (plainOverrides != null) {
      resolved.addAll(plainOverrides);
    }
    final secretOverrides = localSecretValues[targetEnvId];
    if (secretOverrides != null) {
      resolved.addAll(secretOverrides);
    }
    return Map<String, String>.unmodifiable(resolved);
  }

  /// Vérifie la cohérence structurelle du projet et de ses sous-modèles.
  void validate() {
    designSpec.validate();
    overlay.validate();
    if (designSpec.domain.domainCode != overlay.domainCode) {
      throw FormatException(
        'Incohérence de domainCode entre Design (${designSpec.domain.domainCode}) '
        'et BackendOverlayConfig (${overlay.domainCode}).',
      );
    }
    final historyIds = <String>{};
    for (final record in importHistory) {
      record.validate();
      if (!historyIds.add(record.id)) {
        throw FormatException(
          'Identifiant d’historique d’import dupliqué : ${record.id}.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  BackendDomainProject copyWith({
    DomainDesignSpec? designSpec,
    BackendOverlayConfig? overlay,
    List<DomainImportHistoryRecord>? importHistory,
    Map<String, Map<String, String>>? localSecretValues,
  }) => BackendDomainProject(
    designSpec: designSpec ?? this.designSpec,
    overlay: overlay ?? this.overlay,
    importHistory: importHistory ?? this.importHistory,
    localSecretValues: localSecretValues ?? this.localSecretValues,
  );

  /// Sérialise le projet en JSON (omet [localSecretValues] lorsque
  /// [includeLocalSecrets] vaut `false`, par exemple lors d'un partage externe).
  Map<String, Object?> toJson({bool includeLocalSecrets = true}) =>
      <String, Object?>{
        'designSpec': designSpec.toJson(),
        'overlay': overlay.toJson(),
        'importHistory': <Map<String, Object?>>[
          for (final record in importHistory) record.toJson(),
        ],
        if (includeLocalSecrets && localSecretValues.isNotEmpty)
          'localSecretValues': localSecretValues,
      };

  /// Désérialise un projet complet depuis JSON.
  factory BackendDomainProject.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendDomainProject invalide.');
    }
    final spec = DomainDesignSpec.fromJson(raw['designSpec']);
    final overlay = raw['overlay'] != null
        ? BackendOverlayConfig.fromJson(raw['overlay'])
        : BackendOverlayConfig.bootstrapFromDesign(spec);
    final project = BackendDomainProject(
      designSpec: spec,
      overlay: overlay,
      importHistory: <DomainImportHistoryRecord>[
        if (raw['importHistory'] case final List list)
          for (final item in list) DomainImportHistoryRecord.fromJson(item),
      ],
      localSecretValues: freezeNestedStringMap(raw['localSecretValues']),
    );
    project.validate();
    return project;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendDomainProject &&
          other.designSpec == designSpec &&
          other.overlay == overlay &&
          listEquals(other.importHistory, importHistory) &&
          deepJsonEquals(other.localSecretValues, localSecretValues);

  @override
  int get hashCode => Object.hash(
    designSpec,
    overlay,
    Object.hashAll(importHistory),
    deepJsonHash(localSecretValues),
  );
}
