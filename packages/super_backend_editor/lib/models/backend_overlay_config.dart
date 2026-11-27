/// Modèles immuables de la surcouche d'implémentation Backend éditable
/// ([BackendOverlayConfig]) conservée séparément de [DomainDesignSpec] afin de
/// préserver tout travail local lors des ré-imports incrémentaux.
library;

import 'package:flutter/foundation.dart';

import 'domain_design_spec.dart';
import 'json_value_utils.dart';

final RegExp _collectionNamePattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

const Set<String> _allowedHttpMethods = <String>{
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
};

const Map<String, String> _accentFoldMap = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
};

String _toKebabSlug(String raw, {String fallback = 'item', int maxLen = 56}) {
  final splitCamel = raw
      .trim()
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (m) => '${m[1]}-${m[2]}',
      );
  final buf = StringBuffer();
  for (final rune in splitCamel.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_accentFoldMap[ch] ?? ch);
  }
  var slug = buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > maxLen) {
    slug = slug.substring(0, maxLen).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? fallback : slug;
}

String _pluralizeKebabSlug(String kebab) {
  if (kebab.isEmpty) return 'items';
  if (kebab.endsWith('s') || kebab.endsWith('x') || kebab.endsWith('z')) {
    return kebab;
  }
  if (kebab.endsWith('ch') || kebab.endsWith('sh')) {
    return '${kebab}es';
  }
  if (kebab.length >= 2 &&
      kebab.endsWith('y') &&
      !'aeiou'.contains(kebab[kebab.length - 2])) {
    return '${kebab.substring(0, kebab.length - 1)}ies';
  }
  return '${kebab}s';
}

void _validateRelativeScriptPath(String path, String field) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    throw FormatException('$field ne peut pas être vide.');
  }
  final normalized = trimmed.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.split('/').any((seg) => seg == '..' || seg.isEmpty)) {
    throw FormatException(
      '$field doit être un chemin relatif sûr sous scripts/ : $path.',
    );
  }
}

/// Politique d'exécution des suppressions SCRUD sur une collection `super_backend`.
enum BackendDeletionMode {
  /// Suppression physique immédiate de la ligne SQLite/mémoire.
  hardDelete('Suppression physique'),

  /// Suppression logique par horodatage d'un champ dédié (`deletedAt`).
  softDelete('Suppression logique (soft delete)'),

  /// Interdiction de toute suppression (archivage immuable).
  immutableArchive('Archivage immuable');

  const BackendDeletionMode(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise un mode de suppression depuis JSON.
  static BackendDeletionMode fromJson(Object? raw) {
    if (raw == null) return BackendDeletionMode.hardDelete;
    if (raw is String) {
      final norm = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
      switch (norm) {
        case 'harddelete':
        case 'hard':
        case 'physical':
          return BackendDeletionMode.hardDelete;
        case 'softdelete':
        case 'soft':
        case 'logical':
          return BackendDeletionMode.softDelete;
        case 'immutablearchive':
        case 'immutable':
        case 'archive':
        case 'appendonly':
          return BackendDeletionMode.immutableArchive;
      }
    }
    throw FormatException('Mode de suppression Backend inconnu : $raw');
  }
}

/// Politique de contrôle de concurrence sur les écritures d'une collection.
enum BackendConcurrencyMode {
  /// Aucun contrôle de version (dernier écrivain gagne).
  none('Aucun'),

  /// Verrouillage optimiste par incrémentation et vérification d'un champ entier (`version`).
  optimisticVersion('Version optimiste');

  const BackendConcurrencyMode(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise un mode de concurrence depuis JSON.
  static BackendConcurrencyMode fromJson(Object? raw) {
    if (raw == null) return BackendConcurrencyMode.none;
    if (raw is String) {
      final norm = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
      switch (norm) {
        case 'none':
        case 'standard':
        case 'pessimisticlock':
        case 'appendonly':
          return BackendConcurrencyMode.none;
        case 'optimisticversion':
        case 'optimistic':
        case 'version':
          return BackendConcurrencyMode.optimisticVersion;
      }
    }
    throw FormatException('Mode de concurrence Backend inconnu : $raw');
  }
}

/// Configuration d'une collection persistante provisionnée dans `super_backend`.
@immutable
class BackendCollectionConfig {
  /// Crée une configuration de collection Backend immuable.
  const BackendCollectionConfig({
    required this.id,
    this.contractEntryId,
    this.isOrphaned = false,
    required this.collectionName,
    required this.label,
    this.enabled = true,
    this.keyField = 'id',
    this.strictSchemaValidation = true,
    this.deletionMode = BackendDeletionMode.hardDelete,
    this.softDeleteField = 'deletedAt',
    this.concurrencyMode = BackendConcurrencyMode.none,
    this.versionField = 'version',
    this.invariantScriptPath,
  });

  /// Identifiant unique de la collection (aligné sur [contractEntryId] si lié).
  final String id;

  /// Identifiant de l'entrée `model` dans [DomainDesignSpec], ou `null` si collection personnalisée.
  final String? contractEntryId;

  /// Vrai lorsque le modèle Design lié a disparu lors d'un ré-import incrémental.
  final bool isOrphaned;

  /// Nom technique de la collection dans `super_backend` (ex. `invoices`).
  final String collectionName;

  /// Libellé affiché dans le studio Data & API.
  final String label;

  /// Indique si la collection est active.
  final bool enabled;

  /// Champ JSON synchronisé avec la clé primaire d'entité (`id` par défaut).
  final String keyField;

  /// Active la validation stricte du payload par le JSON Schema Draft 2020-12.
  final bool strictSchemaValidation;

  /// Stratégie de suppression appliquée aux appels `DELETE` / `delete`.
  final BackendDeletionMode deletionMode;

  /// Champ horodaté lors d'un `softDelete` (`deletedAt` par défaut).
  final String softDeleteField;

  /// Stratégie de contrôle de concurrence optimiste.
  final BackendConcurrencyMode concurrencyMode;

  /// Champ entier de version contrôlé en mode `optimisticVersion` (`version` par défaut).
  final String versionField;

  /// Chemin relatif optionnel sous `scripts/` du script QuickJS validant les invariants.
  final String? invariantScriptPath;

  /// Vérifie les invariants de la configuration de collection.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BackendCollectionConfig.id requis.');
    }
    if (!_collectionNamePattern.hasMatch(collectionName)) {
      throw FormatException(
        'Nom de collection super_backend invalide : « $collectionName » '
        '(attendu : [a-zA-Z0-9_-]{1,64}).',
      );
    }
    if (label.trim().isEmpty) {
      throw const FormatException('BackendCollectionConfig.label requis.');
    }
    if (keyField.trim().isEmpty) {
      throw const FormatException('BackendCollectionConfig.keyField requis.');
    }
    if (deletionMode == BackendDeletionMode.softDelete &&
        softDeleteField.trim().isEmpty) {
      throw const FormatException(
        'BackendCollectionConfig.softDeleteField requis en mode softDelete.',
      );
    }
    if (concurrencyMode == BackendConcurrencyMode.optimisticVersion &&
        versionField.trim().isEmpty) {
      throw const FormatException(
        'BackendCollectionConfig.versionField requis en mode optimisticVersion.',
      );
    }
    if (invariantScriptPath != null) {
      _validateRelativeScriptPath(
        invariantScriptPath!,
        'BackendCollectionConfig.invariantScriptPath',
      );
    }
  }

  /// Retourne une copie modifiée.
  BackendCollectionConfig copyWith({
    String? id,
    String? contractEntryId,
    bool clearContractEntryId = false,
    bool? isOrphaned,
    String? collectionName,
    String? label,
    bool? enabled,
    String? keyField,
    bool? strictSchemaValidation,
    BackendDeletionMode? deletionMode,
    String? softDeleteField,
    BackendConcurrencyMode? concurrencyMode,
    String? versionField,
    String? invariantScriptPath,
    bool clearInvariantScriptPath = false,
  }) => BackendCollectionConfig(
    id: id ?? this.id,
    contractEntryId: clearContractEntryId
        ? null
        : (contractEntryId ?? this.contractEntryId),
    isOrphaned: isOrphaned ?? this.isOrphaned,
    collectionName: collectionName ?? this.collectionName,
    label: label ?? this.label,
    enabled: enabled ?? this.enabled,
    keyField: keyField ?? this.keyField,
    strictSchemaValidation:
        strictSchemaValidation ?? this.strictSchemaValidation,
    deletionMode: deletionMode ?? this.deletionMode,
    softDeleteField: softDeleteField ?? this.softDeleteField,
    concurrencyMode: concurrencyMode ?? this.concurrencyMode,
    versionField: versionField ?? this.versionField,
    invariantScriptPath: clearInvariantScriptPath
        ? null
        : (invariantScriptPath ?? this.invariantScriptPath),
  );

  /// Sérialise la configuration de collection en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (contractEntryId != null && contractEntryId!.trim().isNotEmpty)
      'contractEntryId': contractEntryId,
    'isOrphaned': isOrphaned,
    'collectionName': collectionName,
    'label': label,
    'enabled': enabled,
    'keyField': keyField,
    'strictSchemaValidation': strictSchemaValidation,
    'deletionMode': deletionMode.name,
    'softDeleteField': softDeleteField,
    'concurrencyMode': concurrencyMode.name,
    'versionField': versionField,
    if (invariantScriptPath != null && invariantScriptPath!.trim().isNotEmpty)
      'invariantScriptPath': invariantScriptPath,
  };

  /// Désérialise une configuration de collection depuis JSON.
  factory BackendCollectionConfig.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendCollectionConfig invalide.');
    }
    final rawContractId = (raw['contractEntryId'] as String?)?.trim();
    final rawScript = (raw['invariantScriptPath'] as String?)?.trim();
    final collectionName = (raw['collectionName'] as String?)?.trim() ?? '';
    final rawLabel = (raw['label'] as String?)?.trim() ?? '';
    final rawKeyField = (raw['keyField'] as String?)?.trim() ?? '';
    final rawSoftField = (raw['softDeleteField'] as String?)?.trim() ?? '';
    final rawVerField = (raw['versionField'] as String?)?.trim() ?? '';

    final item = BackendCollectionConfig(
      id: (raw['id'] as String?)?.trim() ?? '',
      contractEntryId: (rawContractId == null || rawContractId.isEmpty)
          ? null
          : rawContractId,
      isOrphaned: raw['isOrphaned'] as bool? ?? false,
      collectionName: collectionName,
      label: rawLabel.isNotEmpty ? rawLabel : collectionName,
      enabled: raw['enabled'] as bool? ?? true,
      keyField: rawKeyField.isEmpty ? 'id' : rawKeyField,
      strictSchemaValidation: raw['strictSchemaValidation'] as bool? ?? true,
      deletionMode: BackendDeletionMode.fromJson(raw['deletionMode']),
      softDeleteField: rawSoftField.isEmpty ? 'deletedAt' : rawSoftField,
      concurrencyMode: BackendConcurrencyMode.fromJson(raw['concurrencyMode']),
      versionField: rawVerField.isEmpty ? 'version' : rawVerField,
      invariantScriptPath: (rawScript == null || rawScript.isEmpty)
          ? null
          : rawScript.replaceAll('\\', '/'),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendCollectionConfig &&
          other.id == id &&
          other.contractEntryId == contractEntryId &&
          other.isOrphaned == isOrphaned &&
          other.collectionName == collectionName &&
          other.label == label &&
          other.enabled == enabled &&
          other.keyField == keyField &&
          other.strictSchemaValidation == strictSchemaValidation &&
          other.deletionMode == deletionMode &&
          other.softDeleteField == softDeleteField &&
          other.concurrencyMode == concurrencyMode &&
          other.versionField == versionField &&
          other.invariantScriptPath == invariantScriptPath;

  @override
  int get hashCode => Object.hash(
    id,
    contractEntryId,
    isOrphaned,
    collectionName,
    label,
    enabled,
    keyField,
    strictSchemaValidation,
    deletionMode,
    softDeleteField,
    concurrencyMode,
    versionField,
    invariantScriptPath,
  );
}

/// Nature d'un endpoint HTTP exposé par le serveur local du domaine.
enum BackendEndpointKind {
  /// Exposition REST SCRUD complète d'une collection (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`).
  scrudCollection('SCRUD Collection'),

  /// Commande applicative CQRS (`POST /api/commands/...`).
  cqrsCommand('Commande CQRS'),

  /// Requête applicative CQRS (`GET /api/queries/...`).
  cqrsQuery('Requête CQRS'),

  /// Route HTTP personnalisée pilotée par un script QuickJS.
  custom('Route personnalisée');

  const BackendEndpointKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une catégorie d'endpoint depuis JSON.
  static BackendEndpointKind fromJson(Object? raw) {
    if (raw is String) {
      for (final kind in BackendEndpointKind.values) {
        if (kind.name == raw.trim()) return kind;
      }
      final norm = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
      switch (norm) {
        case 'scrudcollection':
        case 'scrud':
        case 'collection':
          return BackendEndpointKind.scrudCollection;
        case 'cqrscommand':
        case 'command':
          return BackendEndpointKind.cqrsCommand;
        case 'cqrsquery':
        case 'query':
          return BackendEndpointKind.cqrsQuery;
        case 'custom':
          return BackendEndpointKind.custom;
      }
    }
    throw FormatException('Catégorie d’endpoint Backend inconnue : $raw');
  }
}

/// Configuration d'un endpoint REST / CQRS exposé par le routeur local.
@immutable
class BackendEndpointConfig {
  /// Crée une configuration d'endpoint immuable.
  BackendEndpointConfig({
    required this.id,
    required this.kind,
    required String method,
    required this.path,
    this.summary = '',
    this.enabled = true,
    this.isOrphaned = false,
    this.collectionId,
    this.useCaseId,
    this.inputContractEntryId,
    this.outputContractEntryId,
    this.handlerScriptPath,
  }) : method = method.trim().toUpperCase();

  /// Identifiant unique de l'endpoint.
  final String id;

  /// Catégorie d'endpoint (`scrudCollection`, `cqrsCommand`, `cqrsQuery`, `custom`).
  final BackendEndpointKind kind;

  /// Méthode HTTP principale (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`).
  final String method;

  /// Chemin HTTP absolu commençant par `/` (ex. `/api/invoices`, `/api/commands/create-invoice`).
  final String path;

  /// Résumé fonctionnel affiché dans l'API Playground et OpenAPI.
  final String summary;

  /// Indique si l'endpoint est exposé par le serveur local.
  final bool enabled;

  /// Vrai lorsque le Use Case ou la collection Design cible a été supprimé au ré-import.
  final bool isOrphaned;

  /// Identifiant optionnel de la [BackendCollectionConfig] associée.
  final String? collectionId;

  /// Identifiant optionnel du [ImportedUseCaseSpec] associé.
  final String? useCaseId;

  /// Identifiant optionnel du contrat DTO/modèle d'entrée.
  final String? inputContractEntryId;

  /// Identifiant optionnel du contrat DTO/modèle de sortie.
  final String? outputContractEntryId;

  /// Chemin relatif optionnel sous `scripts/` du handler QuickJS exécuté sur cet endpoint.
  final String? handlerScriptPath;

  /// Vérifie les invariants de l'endpoint.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BackendEndpointConfig.id requis.');
    }
    if (!_allowedHttpMethods.contains(method)) {
      throw FormatException(
        'Méthode HTTP invalide sur BackendEndpointConfig ($id) : $method.',
      );
    }
    if (path.trim().isEmpty || !path.startsWith('/')) {
      throw FormatException(
        'BackendEndpointConfig.path doit commencer par "/" : $path.',
      );
    }
    if (handlerScriptPath != null) {
      _validateRelativeScriptPath(
        handlerScriptPath!,
        'BackendEndpointConfig.handlerScriptPath',
      );
    }
  }

  /// Retourne une copie modifiée.
  BackendEndpointConfig copyWith({
    String? id,
    BackendEndpointKind? kind,
    String? method,
    String? path,
    String? summary,
    bool? enabled,
    bool? isOrphaned,
    String? collectionId,
    bool clearCollectionId = false,
    String? useCaseId,
    bool clearUseCaseId = false,
    String? inputContractEntryId,
    bool clearInputContractEntryId = false,
    String? outputContractEntryId,
    bool clearOutputContractEntryId = false,
    String? handlerScriptPath,
    bool clearHandlerScriptPath = false,
  }) => BackendEndpointConfig(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    method: method ?? this.method,
    path: path ?? this.path,
    summary: summary ?? this.summary,
    enabled: enabled ?? this.enabled,
    isOrphaned: isOrphaned ?? this.isOrphaned,
    collectionId: clearCollectionId
        ? null
        : (collectionId ?? this.collectionId),
    useCaseId: clearUseCaseId ? null : (useCaseId ?? this.useCaseId),
    inputContractEntryId: clearInputContractEntryId
        ? null
        : (inputContractEntryId ?? this.inputContractEntryId),
    outputContractEntryId: clearOutputContractEntryId
        ? null
        : (outputContractEntryId ?? this.outputContractEntryId),
    handlerScriptPath: clearHandlerScriptPath
        ? null
        : (handlerScriptPath ?? this.handlerScriptPath),
  );

  /// Sérialise la configuration d'endpoint en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'method': method,
    'path': path,
    'summary': summary,
    'enabled': enabled,
    'isOrphaned': isOrphaned,
    if (collectionId != null && collectionId!.trim().isNotEmpty)
      'collectionId': collectionId,
    if (useCaseId != null && useCaseId!.trim().isNotEmpty)
      'useCaseId': useCaseId,
    if (inputContractEntryId != null && inputContractEntryId!.trim().isNotEmpty)
      'inputContractEntryId': inputContractEntryId,
    if (outputContractEntryId != null &&
        outputContractEntryId!.trim().isNotEmpty)
      'outputContractEntryId': outputContractEntryId,
    if (handlerScriptPath != null && handlerScriptPath!.trim().isNotEmpty)
      'handlerScriptPath': handlerScriptPath,
  };

  /// Désérialise une configuration d'endpoint depuis JSON.
  factory BackendEndpointConfig.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendEndpointConfig invalide.');
    }
    String? optStr(String key) {
      final v = (raw[key] as String?)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final rawScript = optStr('handlerScriptPath');
    final item = BackendEndpointConfig(
      id: (raw['id'] as String?)?.trim() ?? '',
      kind: BackendEndpointKind.fromJson(raw['kind']),
      method: (raw['method'] as String?) ?? 'GET',
      path: (raw['path'] as String?)?.trim() ?? '',
      summary: (raw['summary'] as String?) ?? '',
      enabled: raw['enabled'] as bool? ?? true,
      isOrphaned: raw['isOrphaned'] as bool? ?? false,
      collectionId: optStr('collectionId'),
      useCaseId: optStr('useCaseId'),
      inputContractEntryId: optStr('inputContractEntryId'),
      outputContractEntryId: optStr('outputContractEntryId'),
      handlerScriptPath: rawScript?.replaceAll('\\', '/'),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendEndpointConfig &&
          other.id == id &&
          other.kind == kind &&
          other.method == method &&
          other.path == path &&
          other.summary == summary &&
          other.enabled == enabled &&
          other.isOrphaned == isOrphaned &&
          other.collectionId == collectionId &&
          other.useCaseId == useCaseId &&
          other.inputContractEntryId == inputContractEntryId &&
          other.outputContractEntryId == outputContractEntryId &&
          other.handlerScriptPath == handlerScriptPath;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    method,
    path,
    summary,
    enabled,
    isOrphaned,
    collectionId,
    useCaseId,
    inputContractEntryId,
    outputContractEntryId,
    handlerScriptPath,
  );
}

/// Cible fonctionnelle d'un script QuickJS rattaché au domaine.
enum BackendScriptTargetKind {
  /// Validation des invariants d'un modèle métier avant persistance.
  modelInvariant('Invariant de modèle'),

  /// Exécution d'une méthode `stateChanging` sur un agrégat.
  aggregateCommand('Commande d’agrégat'),

  /// Implémentation d'un Use Case CQRS (`Command` ou `Query`).
  useCase('Use Case CQRS'),

  /// Orchestration ou compensation d'une Saga.
  saga('Saga'),

  /// Handler d'un endpoint HTTP personnalisé.
  customEndpoint('Endpoint personnalisé');

  const BackendScriptTargetKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une cible de script depuis JSON.
  static BackendScriptTargetKind fromJson(Object? raw) {
    if (raw is String) {
      for (final kind in BackendScriptTargetKind.values) {
        if (kind.name == raw.trim()) return kind;
      }
    }
    throw FormatException('Cible de script QuickJS inconnue : $raw');
  }
}

/// Liaison entre un artefact métier/technique et un fichier JavaScript QuickJS sous `scripts/`.
@immutable
class BackendScriptBinding {
  /// Crée une liaison de script QuickJS immuable.
  const BackendScriptBinding({
    required this.id,
    required this.targetKind,
    required this.targetId,
    this.targetSubName,
    required this.label,
    required this.scriptPath,
    this.enabled = true,
    this.isOrphaned = false,
  });

  /// Identifiant unique de la liaison.
  final String id;

  /// Type d'artefact ciblé.
  final BackendScriptTargetKind targetKind;

  /// Identifiant de l'artefact ciblé (`entryId`, `useCaseId`, `sagaId`, `endpointId`).
  final String targetId;

  /// Sous-élément optionnel (ex. nom de la méthode `stateChanging`).
  final String? targetSubName;

  /// Libellé affiché dans le Logic Studio.
  final String label;

  /// Chemin relatif sous `scripts/` (ex. `usecases/uc_create_invoice.js`).
  final String scriptPath;

  /// Indique si l'exécution du script est activée.
  final bool enabled;

  /// Vrai lorsque la cible Design a disparu lors d'un ré-import.
  final bool isOrphaned;

  /// Vérifie les invariants de la liaison de script.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BackendScriptBinding.id requis.');
    }
    if (targetId.trim().isEmpty) {
      throw const FormatException('BackendScriptBinding.targetId requis.');
    }
    if (label.trim().isEmpty) {
      throw const FormatException('BackendScriptBinding.label requis.');
    }
    _validateRelativeScriptPath(scriptPath, 'BackendScriptBinding.scriptPath');
  }

  /// Retourne une copie modifiée.
  BackendScriptBinding copyWith({
    String? id,
    BackendScriptTargetKind? targetKind,
    String? targetId,
    String? targetSubName,
    bool clearTargetSubName = false,
    String? label,
    String? scriptPath,
    bool? enabled,
    bool? isOrphaned,
  }) => BackendScriptBinding(
    id: id ?? this.id,
    targetKind: targetKind ?? this.targetKind,
    targetId: targetId ?? this.targetId,
    targetSubName: clearTargetSubName
        ? null
        : (targetSubName ?? this.targetSubName),
    label: label ?? this.label,
    scriptPath: scriptPath ?? this.scriptPath,
    enabled: enabled ?? this.enabled,
    isOrphaned: isOrphaned ?? this.isOrphaned,
  );

  /// Sérialise la liaison en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'targetKind': targetKind.name,
    'targetId': targetId,
    if (targetSubName != null && targetSubName!.trim().isNotEmpty)
      'targetSubName': targetSubName,
    'label': label,
    'scriptPath': scriptPath,
    'enabled': enabled,
    'isOrphaned': isOrphaned,
  };

  /// Désérialise une liaison depuis JSON.
  factory BackendScriptBinding.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendScriptBinding invalide.');
    }
    final rawSub = (raw['targetSubName'] as String?)?.trim();
    final item = BackendScriptBinding(
      id: (raw['id'] as String?)?.trim() ?? '',
      targetKind: BackendScriptTargetKind.fromJson(raw['targetKind']),
      targetId: (raw['targetId'] as String?)?.trim() ?? '',
      targetSubName: (rawSub == null || rawSub.isEmpty) ? null : rawSub,
      label: (raw['label'] as String?)?.trim() ?? '',
      scriptPath: ((raw['scriptPath'] as String?)?.trim() ?? '').replaceAll(
        '\\',
        '/',
      ),
      enabled: raw['enabled'] as bool? ?? true,
      isOrphaned: raw['isOrphaned'] as bool? ?? false,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendScriptBinding &&
          other.id == id &&
          other.targetKind == targetKind &&
          other.targetId == targetId &&
          other.targetSubName == targetSubName &&
          other.label == label &&
          other.scriptPath == scriptPath &&
          other.enabled == enabled &&
          other.isOrphaned == isOrphaned;

  @override
  int get hashCode => Object.hash(
    id,
    targetKind,
    targetId,
    targetSubName,
    label,
    scriptPath,
    enabled,
    isOrphaned,
  );
}

/// Configuration réseau du serveur HTTP local exposant les APIs du domaine.
@immutable
class BackendServerConfig {
  /// Crée une configuration serveur immuable.
  const BackendServerConfig({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.apiPrefix = '/api',
    this.enableCors = true,
    this.autoStart = false,
  });

  /// Adresse d'écoute locale (`127.0.0.1` par défaut).
  final String host;

  /// Port TCP d'écoute (`0..65535`, `8080` par défaut ; `0` = port éphémère).
  final int port;

  /// Préfixe d'API HTTP (`/api` par défaut).
  final String apiPrefix;

  /// Active l'émission des en-têtes CORS permissifs pour les clients locaux.
  final bool enableCors;

  /// Démarre automatiquement le serveur à l'ouverture du domaine.
  final bool autoStart;

  /// URL de base complète du serveur (sans slash final).
  String get baseUrl {
    final cleanPrefix = apiPrefix == '/'
        ? ''
        : apiPrefix.replaceAll(RegExp(r'/+$'), '');
    return 'http://$host:$port$cleanPrefix';
  }

  /// Vérifie les invariants de la configuration serveur.
  void validate() {
    if (host.trim().isEmpty) {
      throw const FormatException('BackendServerConfig.host requis.');
    }
    if (port < 0 || port > 65535) {
      throw FormatException(
        'BackendServerConfig.port hors plage 0..65535 : $port.',
      );
    }
    if (apiPrefix.trim().isEmpty || !apiPrefix.startsWith('/')) {
      throw FormatException(
        'BackendServerConfig.apiPrefix doit commencer par "/" : $apiPrefix.',
      );
    }
  }

  /// Retourne une copie modifiée.
  BackendServerConfig copyWith({
    String? host,
    int? port,
    String? apiPrefix,
    bool? enableCors,
    bool? autoStart,
  }) => BackendServerConfig(
    host: host ?? this.host,
    port: port ?? this.port,
    apiPrefix: apiPrefix ?? this.apiPrefix,
    enableCors: enableCors ?? this.enableCors,
    autoStart: autoStart ?? this.autoStart,
  );

  /// Sérialise la configuration serveur en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'apiPrefix': apiPrefix,
    'enableCors': enableCors,
    'autoStart': autoStart,
  };

  /// Désérialise une configuration serveur depuis JSON.
  factory BackendServerConfig.fromJson(Object? raw) {
    if (raw == null) return const BackendServerConfig();
    if (raw is! Map) {
      throw const FormatException('BackendServerConfig invalide.');
    }
    final rawPort = raw['port'];
    final parsedPort = switch (rawPort) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v.trim()) ?? 8080,
      _ => 8080,
    };
    final rawHost = (raw['host'] as String?)?.trim() ?? '';
    final rawPrefix = (raw['apiPrefix'] as String?)?.trim() ?? '';
    final item = BackendServerConfig(
      host: rawHost.isEmpty ? '127.0.0.1' : rawHost,
      port: parsedPort,
      apiPrefix: rawPrefix.isEmpty ? '/api' : rawPrefix,
      enableCors: raw['enableCors'] as bool? ?? true,
      autoStart: raw['autoStart'] as bool? ?? false,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendServerConfig &&
          other.host == host &&
          other.port == port &&
          other.apiPrefix == apiPrefix &&
          other.enableCors == enableCors &&
          other.autoStart == autoStart;

  @override
  int get hashCode =>
      Object.hash(host, port, apiPrefix, enableCors, autoStart);
}

/// Surcouche complète et éditable d'implémentation Backend pour un domaine métier.
@immutable
class BackendOverlayConfig {
  /// Crée une configuration d'overlay Backend immuable.
  BackendOverlayConfig({
    required this.domainCode,
    this.activeEnvironmentId,
    this.server = const BackendServerConfig(),
    List<BackendCollectionConfig> collections =
        const <BackendCollectionConfig>[],
    List<BackendEndpointConfig> endpoints = const <BackendEndpointConfig>[],
    List<BackendScriptBinding> scripts = const <BackendScriptBinding>[],
    Map<String, Map<String, String>> environmentVariableOverrides =
        const <String, Map<String, String>>{},
    this.superDesignerExportPath,
    DateTime? updatedAt,
  }) : collections = List<BackendCollectionConfig>.unmodifiable(collections),
       endpoints = List<BackendEndpointConfig>.unmodifiable(endpoints),
       scripts = List<BackendScriptBinding>.unmodifiable(scripts),
       environmentVariableOverrides = freezeNestedStringMap(
         environmentVariableOverrides,
       ),
       updatedAt = updatedAt?.toUtc();

  /// Dérive la configuration Backend initiale à partir d'une [DomainDesignSpec] :
  /// - provisionne une collection par modèle persistant (`model`) en inférant
  ///   `deletionMode` et `concurrencyMode` depuis `persistencePolicy` ;
  /// - expose un endpoint `scrudCollection` (`/api/<collection>`) par modèle ;
  /// - expose un endpoint CQRS (`POST /api/commands/<kebab>` ou
  ///   `GET /api/queries/<kebab>`) par [ImportedUseCaseSpec].
  factory BackendOverlayConfig.bootstrapFromDesign(
    DomainDesignSpec spec, {
    BackendServerConfig server = const BackendServerConfig(),
    DateTime? updatedAt,
  }) {
    final cleanPrefix = server.apiPrefix == '/'
        ? ''
        : server.apiPrefix.replaceAll(RegExp(r'/+$'), '');
    final activeEnv =
        spec.environments
            .where((e) => e.status == 'active')
            .firstOrNull
            ?.id ??
        spec.environments.firstOrNull?.id;

    final collections = <BackendCollectionConfig>[];
    final endpoints = <BackendEndpointConfig>[];
    final usedCollectionNames = <String>{};
    final collectionIdByTechLower = <String, String>{};

    for (final model in spec.models) {
      final baseSlug = _pluralizeKebabSlug(
        _toKebabSlug(model.technicalName, fallback: 'entities'),
      );
      var collectionName = baseSlug;
      var suffix = 2;
      while (!usedCollectionNames.add(collectionName.toLowerCase())) {
        collectionName = '$baseSlug-$suffix';
        suffix++;
      }

      final hasExplicitPolicy =
          model.domainLayerJson['persistencePolicy'] is Map ||
          model.domainLayerJson['persistence_policy_behaviors'] is Map;
      final policy = model.persistencePolicy;
      final deletionMode = hasExplicitPolicy
          ? BackendDeletionMode.fromJson(policy['deletionStrategy'])
          : BackendDeletionMode.hardDelete;
      final concurrencyMode = hasExplicitPolicy
          ? BackendConcurrencyMode.fromJson(policy['concurrencyStrategy'])
          : BackendConcurrencyMode.none;

      final collection = BackendCollectionConfig(
        id: model.entryId,
        contractEntryId: model.entryId,
        collectionName: collectionName,
        label: model.effectiveLabel,
        deletionMode: deletionMode,
        concurrencyMode: concurrencyMode,
      );
      collections.add(collection);
      collectionIdByTechLower[model.technicalName.toLowerCase()] =
          collection.id;
      collectionIdByTechLower[model.name.toLowerCase()] = collection.id;

      endpoints.add(
        BackendEndpointConfig(
          id: 'ep_scrud_${model.entryId}',
          kind: BackendEndpointKind.scrudCollection,
          method: 'GET',
          path: '$cleanPrefix/$collectionName',
          summary: 'SCRUD ${model.effectiveLabel}',
          collectionId: collection.id,
          inputContractEntryId: model.entryId,
          outputContractEntryId: model.entryId,
        ),
      );
    }

    final usedCqrsPaths = <String>{};
    for (final uc in spec.useCases) {
      final isQuery = uc.isQuery;
      final baseSlug = _toKebabSlug(
        uc.name.trim().isNotEmpty ? uc.name : uc.code,
        fallback: isQuery ? 'query' : 'command',
      );
      final segment = isQuery ? 'queries' : 'commands';
      var routePath = '$cleanPrefix/$segment/$baseSlug';
      var suffix = 2;
      while (!usedCqrsPaths.add('${isQuery ? 'GET' : 'POST'}:$routePath')) {
        routePath = '$cleanPrefix/$segment/$baseSlug-$suffix';
        suffix++;
      }

      final targetAggLower = uc.targetAggregate.trim().toLowerCase();
      final matchedCollectionId = targetAggLower.isEmpty
          ? null
          : collectionIdByTechLower[targetAggLower];

      endpoints.add(
        BackendEndpointConfig(
          id: 'ep_uc_${uc.id}',
          kind: isQuery
              ? BackendEndpointKind.cqrsQuery
              : BackendEndpointKind.cqrsCommand,
          method: isQuery ? 'GET' : 'POST',
          path: routePath,
          summary: uc.effectiveTitle,
          collectionId: matchedCollectionId,
          useCaseId: uc.id,
        ),
      );
    }

    final overlay = BackendOverlayConfig(
      domainCode: spec.domain.domainCode,
      activeEnvironmentId: activeEnv,
      server: server,
      collections: collections,
      endpoints: endpoints,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    overlay.validate();
    return overlay;
  }

  /// Identifiant de format du fichier `backend_overlay.json`.
  static const String formatId = 'super_backend_editor.backend_overlay';

  /// Version courante du schéma JSON d'overlay.
  static const int currentVersion = 1;

  /// Code canonique du domaine auquel s'applique cet overlay.
  final String domainCode;

  /// Identifiant de l'environnement actif sélectionné dans l'atelier.
  final String? activeEnvironmentId;

  /// Configuration du serveur HTTP local.
  final BackendServerConfig server;

  /// Collections persistantes configurées au-dessus de `super_backend`.
  final List<BackendCollectionConfig> collections;

  /// Endpoints HTTP SCRUD, CQRS et personnalisés.
  final List<BackendEndpointConfig> endpoints;

  /// Liaisons de scripts QuickJS rattachées aux modèles, Use Cases, Sagas ou routes.
  final List<BackendScriptBinding> scripts;

  /// Surcharges locales des variables en clair par environnement (`envId -> {KEY: valeur}`).
  final Map<String, Map<String, String>> environmentVariableOverrides;

  /// Dernier chemin d'export ou de synchronisation vers `super_designer`.
  final String? superDesignerExportPath;

  /// Date UTC de dernière modification de l'overlay.
  final DateTime? updatedAt;

  /// Recherche une collection par son [id].
  BackendCollectionConfig? findCollectionById(String id) =>
      collections.where((c) => c.id == id).firstOrNull;

  /// Recherche une collection par son [collectionName] (insensible à la casse).
  BackendCollectionConfig? findCollectionByName(String collectionName) {
    final lower = collectionName.trim().toLowerCase();
    return collections
        .where((c) => c.collectionName.toLowerCase() == lower)
        .firstOrNull;
  }

  /// Recherche la collection rattachée à l'entrée de contrat [contractEntryId].
  BackendCollectionConfig? findCollectionForContract(String contractEntryId) =>
      collections
          .where((c) => c.contractEntryId == contractEntryId)
          .firstOrNull;

  /// Recherche un endpoint par son [id].
  BackendEndpointConfig? findEndpointById(String id) =>
      endpoints.where((e) => e.id == id).firstOrNull;

  /// Retourne les liaisons de scripts rattachées à [targetId].
  List<BackendScriptBinding> findScriptsForTarget(String targetId) =>
      scripts.where((s) => s.targetId == targetId).toList(growable: false);

  /// Vérifie les invariants de l'overlay Backend.
  void validate() {
    if (domainCode.trim().isEmpty) {
      throw const FormatException('BackendOverlayConfig.domainCode requis.');
    }
    server.validate();

    final colIds = <String>{};
    final colNames = <String>{};
    for (final col in collections) {
      col.validate();
      if (!colIds.add(col.id)) {
        throw FormatException(
          'Identifiant de collection dupliqué : ${col.id}.',
        );
      }
      if (!colNames.add(col.collectionName.toLowerCase())) {
        throw FormatException(
          'Nom de collection dupliqué : ${col.collectionName}.',
        );
      }
    }

    final epIds = <String>{};
    for (final ep in endpoints) {
      ep.validate();
      if (!epIds.add(ep.id)) {
        throw FormatException('Identifiant d’endpoint dupliqué : ${ep.id}.');
      }
    }

    final scriptIds = <String>{};
    for (final script in scripts) {
      script.validate();
      if (!scriptIds.add(script.id)) {
        throw FormatException('Identifiant de script dupliqué : ${script.id}.');
      }
    }
  }

  /// Retourne une copie modifiée.
  BackendOverlayConfig copyWith({
    String? domainCode,
    String? activeEnvironmentId,
    bool clearActiveEnvironmentId = false,
    BackendServerConfig? server,
    List<BackendCollectionConfig>? collections,
    List<BackendEndpointConfig>? endpoints,
    List<BackendScriptBinding>? scripts,
    Map<String, Map<String, String>>? environmentVariableOverrides,
    String? superDesignerExportPath,
    bool clearSuperDesignerExportPath = false,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) => BackendOverlayConfig(
    domainCode: domainCode ?? this.domainCode,
    activeEnvironmentId: clearActiveEnvironmentId
        ? null
        : (activeEnvironmentId ?? this.activeEnvironmentId),
    server: server ?? this.server,
    collections: collections ?? this.collections,
    endpoints: endpoints ?? this.endpoints,
    scripts: scripts ?? this.scripts,
    environmentVariableOverrides:
        environmentVariableOverrides ?? this.environmentVariableOverrides,
    superDesignerExportPath: clearSuperDesignerExportPath
        ? null
        : (superDesignerExportPath ?? this.superDesignerExportPath),
    updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
  );

  /// Sérialise l'overlay en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': formatId,
    'version': currentVersion,
    'domainCode': domainCode,
    if (activeEnvironmentId != null && activeEnvironmentId!.trim().isNotEmpty)
      'activeEnvironmentId': activeEnvironmentId,
    'server': server.toJson(),
    'collections': <Map<String, Object?>>[
      for (final col in collections) col.toJson(),
    ],
    'endpoints': <Map<String, Object?>>[
      for (final ep in endpoints) ep.toJson(),
    ],
    'scripts': <Map<String, Object?>>[
      for (final s in scripts) s.toJson(),
    ],
    if (environmentVariableOverrides.isNotEmpty)
      'environmentVariableOverrides': environmentVariableOverrides,
    if (superDesignerExportPath != null &&
        superDesignerExportPath!.trim().isNotEmpty)
      'superDesignerExportPath': superDesignerExportPath,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  /// Désérialise une configuration d'overlay depuis JSON.
  factory BackendOverlayConfig.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendOverlayConfig invalide.');
    }
    final rawActiveEnv = (raw['activeEnvironmentId'] as String?)?.trim();
    final rawExportPath = (raw['superDesignerExportPath'] as String?)?.trim();
    final rawUpdated = (raw['updatedAt'] as String?)?.trim();
    final parsedUpdated = (rawUpdated != null && rawUpdated.isNotEmpty)
        ? DateTime.parse(rawUpdated).toUtc()
        : null;

    final overlay = BackendOverlayConfig(
      domainCode: (raw['domainCode'] as String?)?.trim() ?? '',
      activeEnvironmentId: (rawActiveEnv == null || rawActiveEnv.isEmpty)
          ? null
          : rawActiveEnv,
      server: BackendServerConfig.fromJson(raw['server']),
      collections: <BackendCollectionConfig>[
        if (raw['collections'] case final List list)
          for (final item in list) BackendCollectionConfig.fromJson(item),
      ],
      endpoints: <BackendEndpointConfig>[
        if (raw['endpoints'] case final List list)
          for (final item in list) BackendEndpointConfig.fromJson(item),
      ],
      scripts: <BackendScriptBinding>[
        if (raw['scripts'] case final List list)
          for (final item in list) BackendScriptBinding.fromJson(item),
      ],
      environmentVariableOverrides: freezeNestedStringMap(
        raw['environmentVariableOverrides'],
      ),
      superDesignerExportPath: (rawExportPath == null || rawExportPath.isEmpty)
          ? null
          : rawExportPath,
      updatedAt: parsedUpdated,
    );
    overlay.validate();
    return overlay;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendOverlayConfig &&
          other.domainCode == domainCode &&
          other.activeEnvironmentId == activeEnvironmentId &&
          other.server == server &&
          listEquals(other.collections, collections) &&
          listEquals(other.endpoints, endpoints) &&
          listEquals(other.scripts, scripts) &&
          deepJsonEquals(
            other.environmentVariableOverrides,
            environmentVariableOverrides,
          ) &&
          other.superDesignerExportPath == superDesignerExportPath &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    domainCode,
    activeEnvironmentId,
    server,
    Object.hashAll(collections),
    Object.hashAll(endpoints),
    Object.hashAll(scripts),
    deepJsonHash(environmentVariableOverrides),
    superDesignerExportPath,
    updatedAt,
  );
}
