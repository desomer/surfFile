/// Modèles immuables représentant la spécification Design importée en lecture
/// seule d'un domaine fonctionnel ([DomainDesignSpec] — contrat
/// `super_spec_forge.domain_design_spec` v1).
library;

import 'package:flutter/foundation.dart';

import 'json_value_utils.dart';

final RegExp _domainSlugPattern = RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$');

String _toPascalCase(String raw) {
  final parts = raw
      .trim()
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((p) => p.isNotEmpty);
  final buffer = StringBuffer();
  for (final part in parts) {
    buffer.write(part[0].toUpperCase());
    if (part.length > 1) buffer.write(part.substring(1));
  }
  final out = buffer.toString();
  return out.isEmpty ? 'Model' : out;
}

/// Origine de la spécification Design importée dans l'atelier Backend.
enum DesignSourceKind {
  /// État courant vivant du domaine fonctionnel.
  current('État courant'),

  /// Jalon d'itération figé (`DomainIterationSnapshot`).
  snapshot('Snapshot d’itération'),

  /// Lecture directe depuis `<workspace>/domains/catalog.json`.
  workspaceCatalog('Catalogue Workspace');

  const DesignSourceKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise l'origine de la spécification depuis JSON.
  static DesignSourceKind fromJson(Object? raw) {
    if (raw == null) return DesignSourceKind.current;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return DesignSourceKind.current;
      for (final kind in DesignSourceKind.values) {
        if (kind.name == trimmed) return kind;
      }
      final norm = trimmed.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
      switch (norm) {
        case 'current':
        case 'live':
        case 'active':
          return DesignSourceKind.current;
        case 'snapshot':
        case 'iteration':
        case 'baseline':
          return DesignSourceKind.snapshot;
        case 'workspacecatalog':
        case 'workspace_catalog':
        case 'catalog':
          return DesignSourceKind.workspaceCatalog;
      }
    }
    throw FormatException('Origine de spécification Design inconnue : $raw');
  }
}

/// Métadonnées d'un jalon figé (`snapshot`) associé à un import Design.
@immutable
class ImportedSnapshotMeta {
  /// Crée les métadonnées immuables d'un snapshot importé.
  ImportedSnapshotMeta({
    required this.id,
    this.iterationNumber = 1,
    required this.label,
    this.notes = '',
    DateTime? createdAt,
    this.techStackId,
  }) : createdAt = (createdAt ??
               DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc();

  /// Identifiant unique du snapshot.
  final String id;

  /// Numéro d'ordre séquentiel de l'itération (`>= 1`).
  final int iterationNumber;

  /// Libellé du jalon (ex. `Itération 1 — MVP`).
  final String label;

  /// Notes libres de livraison associées au jalon.
  final String notes;

  /// Date UTC de capture du jalon.
  final DateTime createdAt;

  /// Identifiant optionnel du profil de stack technique lors de la capture.
  final String? techStackId;

  /// Vérifie les invariants du jalon.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedSnapshotMeta.id requis.');
    }
    if (iterationNumber < 1) {
      throw const FormatException(
        'ImportedSnapshotMeta.iterationNumber doit être >= 1.',
      );
    }
    if (label.trim().isEmpty) {
      throw const FormatException('ImportedSnapshotMeta.label requis.');
    }
  }

  /// Retourne une copie modifiée.
  ImportedSnapshotMeta copyWith({
    String? id,
    int? iterationNumber,
    String? label,
    String? notes,
    DateTime? createdAt,
    String? techStackId,
    bool clearTechStackId = false,
  }) => ImportedSnapshotMeta(
    id: id ?? this.id,
    iterationNumber: iterationNumber ?? this.iterationNumber,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    techStackId: clearTechStackId ? null : (techStackId ?? this.techStackId),
  );

  /// Sérialise les métadonnées en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'iterationNumber': iterationNumber,
    'label': label,
    'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (techStackId != null && techStackId!.trim().isNotEmpty)
      'techStackId': techStackId,
  };

  /// Désérialise les métadonnées depuis JSON.
  factory ImportedSnapshotMeta.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedSnapshotMeta invalide.');
    }
    final rawIter = raw['iterationNumber'];
    final iter = switch (rawIter) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v.trim()) ?? 1,
      _ => 1,
    };
    final rawStackId = (raw['techStackId'] as String?)?.trim();
    final item = ImportedSnapshotMeta(
      id: (raw['id'] as String?)?.trim() ?? '',
      iterationNumber: iter,
      label: (raw['label'] as String?)?.trim() ?? '',
      notes: (raw['notes'] as String?) ?? '',
      createdAt: parseUtcDateTimeOrEpoch(raw['createdAt']),
      techStackId: (rawStackId == null || rawStackId.isEmpty)
          ? null
          : rawStackId,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedSnapshotMeta &&
          other.id == id &&
          other.iterationNumber == iterationNumber &&
          other.label == label &&
          other.notes == notes &&
          other.createdAt == createdAt &&
          other.techStackId == techStackId;

  @override
  int get hashCode =>
      Object.hash(id, iterationNumber, label, notes, createdAt, techStackId);
}

/// Résumé immuable du profil de stack technique associé au domaine importé.
@immutable
class ImportedTechStackSummary {
  /// Crée un résumé de stack technique.
  const ImportedTechStackSummary({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
  });

  /// Identifiant technique du profil de stack.
  final String id;

  /// Code court de la stack (ex. `ts-nestjs`).
  final String code;

  /// Nom affiché de la stack (ex. `TypeScript / NestJS`).
  final String name;

  /// Description synthétique de la stack.
  final String description;

  /// Vérifie les invariants du résumé de stack technique.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedTechStackSummary.id requis.');
    }
    if (code.trim().isEmpty) {
      throw const FormatException('ImportedTechStackSummary.code requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('ImportedTechStackSummary.name requis.');
    }
  }

  /// Retourne une copie modifiée.
  ImportedTechStackSummary copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
  }) => ImportedTechStackSummary(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
  );

  /// Sérialise le résumé en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'description': description,
  };

  /// Désérialise un résumé de stack technique depuis JSON.
  factory ImportedTechStackSummary.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedTechStackSummary invalide.');
    }
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final item = ImportedTechStackSummary(
      id: rawId.isNotEmpty ? rawId : rawCode,
      code: rawCode.isNotEmpty ? rawCode : rawId,
      name: rawName.isNotEmpty ? rawName : (rawCode.isNotEmpty ? rawCode : rawId),
      description: (raw['description'] as String?) ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedTechStackSummary &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.description == description;

  @override
  int get hashCode => Object.hash(id, code, name, description);
}

/// Identité fonctionnelle et technique du domaine importé.
@immutable
class ImportedDomainIdentity {
  /// Crée l'identité d'un domaine importé.
  const ImportedDomainIdentity({
    required this.id,
    required this.domainCode,
    required this.name,
    this.description = '',
    this.isActive = true,
    this.techStackId,
    this.techStack,
  });

  /// Identifiant technique du domaine dans `super_spec_forge`.
  final String id;

  /// Code canonique du domaine en `kebab-case` (ex. `billing-core`).
  final String domainCode;

  /// Libellé métier du domaine.
  final String name;

  /// Description fonctionnelle du domaine.
  final String description;

  /// Indique si le domaine est actif.
  final bool isActive;

  /// Identifiant optionnel du profil de stack technique associé.
  final String? techStackId;

  /// Résumé optionnel de la stack technique résolue.
  final ImportedTechStackSummary? techStack;

  /// Vérifie les invariants de l'identité du domaine.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedDomainIdentity.id requis.');
    }
    if (domainCode.trim().isEmpty ||
        !_domainSlugPattern.hasMatch(domainCode.trim())) {
      throw FormatException(
        'ImportedDomainIdentity.domainCode invalide : « $domainCode ».',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException('ImportedDomainIdentity.name requis.');
    }
    techStack?.validate();
  }

  /// Retourne une copie modifiée.
  ImportedDomainIdentity copyWith({
    String? id,
    String? domainCode,
    String? name,
    String? description,
    bool? isActive,
    String? techStackId,
    bool clearTechStackId = false,
    ImportedTechStackSummary? techStack,
    bool clearTechStack = false,
  }) => ImportedDomainIdentity(
    id: id ?? this.id,
    domainCode: domainCode ?? this.domainCode,
    name: name ?? this.name,
    description: description ?? this.description,
    isActive: isActive ?? this.isActive,
    techStackId: clearTechStackId ? null : (techStackId ?? this.techStackId),
    techStack: clearTechStack ? null : (techStack ?? this.techStack),
  );

  /// Sérialise l'identité du domaine en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainCode': domainCode,
    'name': name,
    'description': description,
    'isActive': isActive,
    if (techStackId != null && techStackId!.trim().isNotEmpty)
      'techStackId': techStackId,
    if (techStack != null) 'techStack': techStack!.toJson(),
  };

  /// Désérialise l'identité du domaine depuis JSON.
  factory ImportedDomainIdentity.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedDomainIdentity invalide.');
    }
    final parsedStack = raw['techStack'] is Map
        ? ImportedTechStackSummary.fromJson(raw['techStack'])
        : null;
    final rawStackId = (raw['techStackId'] as String?)?.trim();
    final effectiveStackId = (rawStackId != null && rawStackId.isNotEmpty)
        ? rawStackId
        : parsedStack?.id;
    final domainCode = (raw['domainCode'] as String?)?.trim() ?? '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = ImportedDomainIdentity(
      id: rawId.isNotEmpty ? rawId : domainCode,
      domainCode: domainCode,
      name: (raw['name'] as String?)?.trim() ?? domainCode,
      description: (raw['description'] as String?) ?? '',
      isActive: raw['isActive'] as bool? ?? true,
      techStackId: effectiveStackId,
      techStack: parsedStack,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedDomainIdentity &&
          other.id == id &&
          other.domainCode == domainCode &&
          other.name == name &&
          other.description == description &&
          other.isActive == isActive &&
          other.techStackId == techStackId &&
          other.techStack == techStack;

  @override
  int get hashCode => Object.hash(
    id,
    domainCode,
    name,
    description,
    isActive,
    techStackId,
    techStack,
  );
}

/// Environnement logique importé (ex. `dev`, `staging`, `prod`).
@immutable
class ImportedEnvironmentSpec {
  /// Crée une spécification d'environnement importée.
  const ImportedEnvironmentSpec({
    required this.id,
    this.domainId = '',
    required this.environmentCode,
    required this.name,
    this.description = '',
    this.status = 'active',
  });

  /// Identifiant technique de l'environnement.
  final String id;

  /// Identifiant du domaine propriétaire.
  final String domainId;

  /// Code canonique en `kebab-case` (ex. `local-dev`).
  final String environmentCode;

  /// Nom lisible de l'environnement.
  final String name;

  /// Description de l'usage de l'environnement.
  final String description;

  /// Statut du cycle de vie (`active`, `deprecated`, `archived`).
  final String status;

  /// Vérifie les invariants de l'environnement.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedEnvironmentSpec.id requis.');
    }
    if (environmentCode.trim().isEmpty) {
      throw const FormatException(
        'ImportedEnvironmentSpec.environmentCode requis.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException('ImportedEnvironmentSpec.name requis.');
    }
  }

  /// Retourne une copie modifiée.
  ImportedEnvironmentSpec copyWith({
    String? id,
    String? domainId,
    String? environmentCode,
    String? name,
    String? description,
    String? status,
  }) => ImportedEnvironmentSpec(
    id: id ?? this.id,
    domainId: domainId ?? this.domainId,
    environmentCode: environmentCode ?? this.environmentCode,
    name: name ?? this.name,
    description: description ?? this.description,
    status: status ?? this.status,
  );

  /// Sérialise l'environnement en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (domainId.isNotEmpty) 'domainId': domainId,
    'environmentCode': environmentCode,
    'name': name,
    'description': description,
    'status': status,
  };

  /// Désérialise un environnement depuis JSON.
  factory ImportedEnvironmentSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedEnvironmentSpec invalide.');
    }
    final envCode =
        ((raw['environmentCode'] ?? raw['code']) as String?)?.trim() ?? '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final rawStatus = (raw['status'] as String?)?.trim() ?? '';
    final item = ImportedEnvironmentSpec(
      id: rawId.isNotEmpty ? rawId : envCode,
      domainId: (raw['domainId'] as String?)?.trim() ?? '',
      environmentCode: envCode,
      name: rawName.isNotEmpty ? rawName : envCode,
      description: (raw['description'] as String?) ?? '',
      status: rawStatus.isEmpty ? 'active' : rawStatus,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedEnvironmentSpec &&
          other.id == id &&
          other.domainId == domainId &&
          other.environmentCode == environmentCode &&
          other.name == name &&
          other.description == description &&
          other.status == status;

  @override
  int get hashCode =>
      Object.hash(id, domainId, environmentCode, name, description, status);
}

/// Système, microservice ou application tierce rattaché au domaine importé.
@immutable
class ImportedSystemSpec {
  /// Crée une spécification de système/service importée.
  const ImportedSystemSpec({
    required this.id,
    this.domainId = '',
    required this.serviceCode,
    required this.name,
    this.kind = 'microservice',
    this.description = '',
    this.isActive = true,
    this.techStackId,
    this.vendor = '',
  });

  /// Identifiant technique du système/service.
  final String id;

  /// Identifiant du domaine propriétaire.
  final String domainId;

  /// Code canonique du service en `kebab-case`.
  final String serviceCode;

  /// Libellé du service ou système.
  final String name;

  /// Catégorie d'urbanisme (`microservice`, `externalApp`, `webFront`, etc.).
  final String kind;

  /// Responsabilité fonctionnelle ou technique.
  final String description;

  /// Indique si le système est actif.
  final bool isActive;

  /// Identifiant optionnel du profil de stack technique associé.
  final String? techStackId;

  /// Éditeur ou fournisseur tiers éventuel (ex. `Stripe`).
  final String vendor;

  /// Vérifie les invariants du système.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedSystemSpec.id requis.');
    }
    if (serviceCode.trim().isEmpty) {
      throw const FormatException('ImportedSystemSpec.serviceCode requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('ImportedSystemSpec.name requis.');
    }
  }

  /// Retourne une copie modifiée.
  ImportedSystemSpec copyWith({
    String? id,
    String? domainId,
    String? serviceCode,
    String? name,
    String? kind,
    String? description,
    bool? isActive,
    String? techStackId,
    bool clearTechStackId = false,
    String? vendor,
  }) => ImportedSystemSpec(
    id: id ?? this.id,
    domainId: domainId ?? this.domainId,
    serviceCode: serviceCode ?? this.serviceCode,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    description: description ?? this.description,
    isActive: isActive ?? this.isActive,
    techStackId: clearTechStackId ? null : (techStackId ?? this.techStackId),
    vendor: vendor ?? this.vendor,
  );

  /// Sérialise le système en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (domainId.isNotEmpty) 'domainId': domainId,
    'serviceCode': serviceCode,
    'name': name,
    'kind': kind,
    'description': description,
    'isActive': isActive,
    if (techStackId != null && techStackId!.trim().isNotEmpty)
      'techStackId': techStackId,
    if (vendor.trim().isNotEmpty) 'vendor': vendor,
  };

  /// Désérialise un système depuis JSON.
  factory ImportedSystemSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedSystemSpec invalide.');
    }
    final svcCode =
        ((raw['serviceCode'] ?? raw['systemCode'] ?? raw['code']) as String?)
            ?.trim() ??
        '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final rawKind = (raw['kind'] as String?)?.trim() ?? '';
    final rawStackId = (raw['techStackId'] as String?)?.trim();
    final item = ImportedSystemSpec(
      id: rawId.isNotEmpty ? rawId : svcCode,
      domainId: (raw['domainId'] as String?)?.trim() ?? '',
      serviceCode: svcCode,
      name: rawName.isNotEmpty ? rawName : svcCode,
      kind: rawKind.isEmpty ? 'microservice' : rawKind,
      description: (raw['description'] as String?) ?? '',
      isActive: raw['isActive'] as bool? ?? true,
      techStackId: (rawStackId == null || rawStackId.isEmpty)
          ? null
          : rawStackId,
      vendor: ((raw['vendor'] as String?) ?? '').trim(),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedSystemSpec &&
          other.id == id &&
          other.domainId == domainId &&
          other.serviceCode == serviceCode &&
          other.name == name &&
          other.kind == kind &&
          other.description == description &&
          other.isActive == isActive &&
          other.techStackId == techStackId &&
          other.vendor == vendor;

  @override
  int get hashCode => Object.hash(
    id,
    domainId,
    serviceCode,
    name,
    kind,
    description,
    isActive,
    techStackId,
    vendor,
  );
}

/// Entrée de configuration ou déclaration de secret importée pour un environnement.
///
/// Garantit par construction et validation qu'aucune valeur secrète (`plainValue`
/// ou `encryptedValue`) n'est conservée lorsque [entryType] vaut `'secret'`.
@immutable
class ImportedConfigurationSpec {
  /// Crée une entrée de configuration importée.
  const ImportedConfigurationSpec({
    required this.id,
    this.domainId = '',
    required this.environmentId,
    this.microserviceId,
    required this.configKey,
    String? entryType,
    bool? isSecret,
    this.plainValue,
    this.description = '',
    this.isInitialized = true,
  }) : entryType =
           entryType ?? (isSecret == true ? 'secret' : 'plainVariable');

  /// Identifiant technique de l'entrée.
  final String id;

  /// Identifiant du domaine propriétaire.
  final String domainId;

  /// Identifiant de l'environnement logique ciblé.
  final String environmentId;

  /// Identifiant optionnel du microservice ciblé (`null` = portée domaine).
  final String? microserviceId;

  /// Clé de configuration (typiquement en `UPPER_SNAKE_CASE`).
  final String configKey;

  /// Classification de l'entrée (`'plainVariable'` ou `'secret'`).
  final String entryType;

  /// Valeur en clair pour `'plainVariable'`, toujours `null` pour `'secret'`.
  final String? plainValue;

  /// Description fonctionnelle de la clé.
  final String description;

  /// Indique si la clé était initialisée dans la source Design.
  final bool isInitialized;

  /// Indique s'il s'agit d'une clé secrète (`entryType == 'secret'`).
  bool get isSecret => entryType == 'secret';

  /// Vérifie les invariants et l'absence stricte de valeur sur un secret.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedConfigurationSpec.id requis.');
    }
    if (environmentId.trim().isEmpty) {
      throw const FormatException(
        'ImportedConfigurationSpec.environmentId requis.',
      );
    }
    if (configKey.trim().isEmpty) {
      throw const FormatException(
        'ImportedConfigurationSpec.configKey requis.',
      );
    }
    if (entryType != 'plainVariable' && entryType != 'secret') {
      throw FormatException(
        'ImportedConfigurationSpec.entryType invalide : $entryType '
        '(attendu : plainVariable ou secret).',
      );
    }
    if (entryType == 'secret' && plainValue != null) {
      throw const FormatException(
        'Une configuration secrète ne peut pas contenir de plainValue.',
      );
    }
  }

  /// Retourne une copie modifiée.
  ImportedConfigurationSpec copyWith({
    String? id,
    String? domainId,
    String? environmentId,
    String? microserviceId,
    bool clearMicroserviceId = false,
    String? configKey,
    String? entryType,
    String? plainValue,
    bool clearPlainValue = false,
    String? description,
    bool? isInitialized,
  }) {
    final nextType = entryType ?? this.entryType;
    final nextPlain = (clearPlainValue || nextType == 'secret')
        ? null
        : (plainValue ?? this.plainValue);
    return ImportedConfigurationSpec(
      id: id ?? this.id,
      domainId: domainId ?? this.domainId,
      environmentId: environmentId ?? this.environmentId,
      microserviceId: clearMicroserviceId
          ? null
          : (microserviceId ?? this.microserviceId),
      configKey: configKey ?? this.configKey,
      entryType: nextType,
      plainValue: nextPlain,
      description: description ?? this.description,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  /// Sérialise la configuration en JSON (sans jamais inclure `encryptedValue` ni secret).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (domainId.isNotEmpty) 'domainId': domainId,
    'environmentId': environmentId,
    if (microserviceId != null && microserviceId!.trim().isNotEmpty)
      'microserviceId': microserviceId,
    'configKey': configKey,
    'entryType': entryType,
    'isSecret': isSecret,
    if (!isSecret && plainValue != null) 'plainValue': plainValue,
    if (description.isNotEmpty) 'description': description,
    'isInitialized': isInitialized,
  };

  /// Désérialise une entrée de configuration en purgeant systématiquement
  /// toute `encryptedValue` et toute `plainValue` lorsque l'entrée est secrète.
  factory ImportedConfigurationSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedConfigurationSpec invalide.');
    }
    final rawType = (raw['entryType'] as String?)?.trim();
    final secretFlag = raw['isSecret'] == true;
    final String resolvedType;
    if (rawType == 'secret' || (rawType == null && secretFlag)) {
      resolvedType = 'secret';
    } else if (rawType == null || rawType.isEmpty || rawType == 'plainVariable') {
      resolvedType = 'plainVariable';
    } else {
      resolvedType = rawType;
    }

    final rawMic = (raw['microserviceId'] as String?)?.trim();
    // Tout champ `encryptedValue` entrant est volontairement ignoré, et
    // `plainValue` est forcé à `null` dès que `resolvedType == 'secret'`.
    final sanitizedPlainValue = resolvedType == 'secret'
        ? null
        : (raw['plainValue']?.toString() ?? '');

    final item = ImportedConfigurationSpec(
      id: (raw['id'] as String?)?.trim() ?? '',
      domainId: (raw['domainId'] as String?)?.trim() ?? '',
      environmentId: (raw['environmentId'] as String?)?.trim() ?? '',
      microserviceId: (rawMic == null || rawMic.isEmpty) ? null : rawMic,
      configKey: (raw['configKey'] as String?)?.trim() ?? '',
      entryType: resolvedType,
      plainValue: sanitizedPlainValue,
      description: (raw['description'] as String?) ?? '',
      isInitialized: raw['isInitialized'] as bool? ?? true,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedConfigurationSpec &&
          other.id == id &&
          other.domainId == domainId &&
          other.environmentId == environmentId &&
          other.microserviceId == microserviceId &&
          other.configKey == configKey &&
          other.entryType == entryType &&
          other.plainValue == plainValue &&
          other.description == description &&
          other.isInitialized == isInitialized;

  @override
  int get hashCode => Object.hash(
    id,
    domainId,
    environmentId,
    microserviceId,
    configKey,
    entryType,
    plainValue,
    description,
    isInitialized,
  );
}

/// Value Object DDD / Architecture Hexagonale importé (`domain` ou `shared`).
@immutable
class ImportedValueObjectSpec {
  /// Crée une spécification de Value Object importée.
  ImportedValueObjectSpec({
    required this.id,
    this.scope = 'domain',
    required this.name,
    required this.technicalName,
    this.kind = 'scalar',
    this.primitiveType,
    this.description = '',
    List<Map<String, Object?>> examples = const <Map<String, Object?>>[],
    Map<String, Object?> specJson = const <String, Object?>{},
    Map<String, Object?> jsonSchema = const <String, Object?>{},
  }) : examples = freezeJsonMapList(examples),
       specJson = freezeJsonMap(specJson),
       jsonSchema = freezeJsonMap(jsonSchema);

  /// Identifiant stable du Value Object.
  final String id;

  /// Portée du Value Object (`'domain'` ou `'shared'`).
  final String scope;

  /// Libellé métier du Value Object.
  final String name;

  /// Nom technique PascalCase ASCII (ex. `Money`, `EmailAddress`).
  final String technicalName;

  /// Forme structurelle (`'scalar'` ou `'composite'`).
  final String kind;

  /// Type primitif sous-jacent lorsque [kind] vaut `'scalar'`.
  final String? primitiveType;

  /// Description métier et règles d'égalité.
  final String description;

  /// Exemples valides et contre-exemples invalides extraits de la spécification.
  final List<Map<String, Object?>> examples;

  /// Spécification JSON complète d'origine du Value Object.
  final Map<String, Object?> specJson;

  /// JSON Schema Draft 2020-12 complet du Value Object.
  final Map<String, Object?> jsonSchema;

  /// Indique si le Value Object provient du Shared Kernel (`scope == 'shared'`).
  bool get isShared => scope == 'shared';

  /// Indique s'il s'agit d'un Value Object scalaire.
  bool get isScalar => kind == 'scalar';

  /// Indique s'il s'agit d'un Value Object composite.
  bool get isComposite => kind == 'composite';

  /// Version sémantique extraite de [specJson] (`1.0.0` par défaut).
  String get version {
    final raw = (specJson['version'] as String?)?.trim();
    return (raw != null && raw.isNotEmpty) ? raw : '1.0.0';
  }

  /// Champs imbriqués lorsque le Value Object est composite.
  List<Map<String, Object?>> get fields =>
      freezeJsonMapList(specJson['fields']);

  /// Vérifie les invariants du Value Object importé.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedValueObjectSpec.id requis.');
    }
    if (scope != 'domain' && scope != 'shared') {
      throw FormatException(
        'ImportedValueObjectSpec.scope invalide : $scope '
        '(attendu : domain ou shared).',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException('ImportedValueObjectSpec.name requis.');
    }
    if (technicalName.trim().isEmpty) {
      throw const FormatException(
        'ImportedValueObjectSpec.technicalName requis.',
      );
    }
    if (kind != 'scalar' && kind != 'composite') {
      throw FormatException(
        'ImportedValueObjectSpec.kind invalide : $kind '
        '(attendu : scalar ou composite).',
      );
    }
  }

  /// Retourne une copie modifiée.
  ImportedValueObjectSpec copyWith({
    String? id,
    String? scope,
    String? name,
    String? technicalName,
    String? kind,
    String? primitiveType,
    bool clearPrimitiveType = false,
    String? description,
    List<Map<String, Object?>>? examples,
    Map<String, Object?>? specJson,
    Map<String, Object?>? jsonSchema,
  }) => ImportedValueObjectSpec(
    id: id ?? this.id,
    scope: scope ?? this.scope,
    name: name ?? this.name,
    technicalName: technicalName ?? this.technicalName,
    kind: kind ?? this.kind,
    primitiveType: clearPrimitiveType
        ? null
        : (primitiveType ?? this.primitiveType),
    description: description ?? this.description,
    examples: examples ?? this.examples,
    specJson: specJson ?? this.specJson,
    jsonSchema: jsonSchema ?? this.jsonSchema,
  );

  /// Sérialise le Value Object importé en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'scope': scope,
    'name': name,
    'technicalName': technicalName,
    'kind': kind,
    if (primitiveType != null && primitiveType!.trim().isNotEmpty)
      'primitiveType': primitiveType,
    'description': description,
    if (examples.isNotEmpty) 'examples': examples,
    'specJson': specJson,
    'jsonSchema': jsonSchema,
  };

  /// Désérialise un Value Object importé depuis JSON (format plat ou bundle `{ id, scope, spec, jsonSchema }`).
  factory ImportedValueObjectSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedValueObjectSpec invalide.');
    }
    final specMap = raw['specJson'] is Map
        ? freezeJsonMap(raw['specJson'] as Map)
        : (raw['spec'] is Map
              ? freezeJsonMap(raw['spec'] as Map)
              : const <String, Object?>{});

    final rawId =
        ((raw['id'] ?? specMap['id']) as String?)?.trim() ?? '';
    final rawScope = (raw['scope'] as String?)?.trim().toLowerCase() ?? 'domain';
    final normalizedScope = rawScope.contains('shared') ? 'shared' : 'domain';

    final rawTech =
        ((raw['technicalName'] ?? specMap['technicalName']) as String?)
            ?.trim() ??
        '';
    final rawName =
        ((raw['name'] ?? specMap['name']) as String?)?.trim() ?? '';
    final effectiveTech = rawTech.isNotEmpty
        ? rawTech
        : _toPascalCase(rawName.isNotEmpty ? rawName : rawId);
    final effectiveName = rawName.isNotEmpty ? rawName : effectiveTech;

    final rawKind =
        ((raw['kind'] ?? specMap['kind']) as String?)?.trim().toLowerCase() ??
        'scalar';
    final normalizedKind =
        (rawKind == 'composite' ||
            rawKind == 'object' ||
            (raw['kind'] == null &&
                specMap['kind'] == null &&
                specMap['fields'] is List &&
                (specMap['fields'] as List).isNotEmpty))
        ? 'composite'
        : 'scalar';

    final rawPrimitive =
        ((raw['primitiveType'] ?? specMap['primitiveType']) as String?)?.trim();
    final effectivePrimitive = (rawPrimitive != null && rawPrimitive.isNotEmpty)
        ? rawPrimitive
        : (normalizedKind == 'scalar' ? 'string' : null);

    final rawDesc =
        (raw['description'] ?? specMap['description']) as String? ?? '';

    final rawExamplesSource = raw['examples'] ?? specMap['examples'];
    final parsedExamples = <Map<String, Object?>>[];
    if (rawExamplesSource is List) {
      for (var i = 0; i < rawExamplesSource.length; i++) {
        final ex = rawExamplesSource[i];
        if (ex is Map) {
          parsedExamples.add(freezeJsonMap(ex));
        } else if (ex != null) {
          parsedExamples.add(
            Map<String, Object?>.unmodifiable(<String, Object?>{
              'id': 'voex_$i',
              'value': '$ex',
              'isValid': true,
            }),
          );
        }
      }
    }

    final item = ImportedValueObjectSpec(
      id: rawId.isNotEmpty ? rawId : 'vo_${effectiveTech.toLowerCase()}',
      scope: normalizedScope,
      name: effectiveName,
      technicalName: effectiveTech,
      kind: normalizedKind,
      primitiveType: effectivePrimitive,
      description: rawDesc,
      examples: parsedExamples,
      specJson: specMap,
      jsonSchema: raw['jsonSchema'] is Map
          ? freezeJsonMap(raw['jsonSchema'] as Map)
          : const <String, Object?>{},
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedValueObjectSpec &&
          other.id == id &&
          other.scope == scope &&
          other.name == name &&
          other.technicalName == technicalName &&
          other.kind == kind &&
          other.primitiveType == primitiveType &&
          other.description == description &&
          deepJsonEquals(other.examples, examples) &&
          deepJsonEquals(other.specJson, specJson) &&
          deepJsonEquals(other.jsonSchema, jsonSchema);

  @override
  int get hashCode => Object.hash(
    id,
    scope,
    name,
    technicalName,
    kind,
    primitiveType,
    description,
    deepJsonHash(examples),
    deepJsonHash(specJson),
    deepJsonHash(jsonSchema),
  );
}

/// Entrée de modèle ou contrat DSL importée avec son objet métier, son JSON
/// Schema Draft 2020-12 et sa couche Domain en Architecture Hexagonale.
@immutable
class ImportedContractEntry {
  /// Crée une entrée de contrat importée.
  ImportedContractEntry({
    required this.entryId,
    required this.name,
    required this.technicalName,
    this.groupName = 'models',
    this.dslType = 'model',
    this.title = '',
    this.version = '0.0.1',
    Map<String, String> states = const <String, String>{},
    Map<String, Object?> objectSpecJson = const <String, Object?>{},
    Map<String, Object?> jsonSchema = const <String, Object?>{},
    Map<String, Object?> domainLayerJson = const <String, Object?>{},
  }) : states = Map<String, String>.unmodifiable(<String, String>{
         for (final e in states.entries) e.key: e.value,
       }),
       objectSpecJson = freezeJsonMap(objectSpecJson),
       jsonSchema = freezeJsonMap(jsonSchema),
       domainLayerJson = freezeJsonMap(domainLayerJson);

  /// Identifiant stable du nœud dans le catalogue DSL.
  final String entryId;

  /// Nom du nœud dans l'arbre DSL.
  final String name;

  /// Nom technique PascalCase de l'entrée (ex. `Invoice`).
  final String technicalName;

  /// Rubrique parente dans le DSL (`models`, `components`, `dto`, `message`).
  final String groupName;

  /// Type DSL de l'entrée (`model`, `component`, `createxdto`, etc.).
  final String dslType;

  /// Titre métier lisible.
  final String title;

  /// Version sémantique (`x.y.z`).
  final String version;

  /// États d'avancement par étape (`conception`, `validation`, `code`, `livraison`).
  final Map<String, String> states;

  /// Spécification JSON complète de l'objet métier (`attributes`, `relations`, cycle de vie).
  final Map<String, Object?> objectSpecJson;

  /// JSON Schema Draft 2020-12 généré pour cette entrée.
  final Map<String, Object?> jsonSchema;

  /// Spécification JSON de la couche Domain hexagonale (7 onglets).
  final Map<String, Object?> domainLayerJson;

  /// Indique s'il s'agit d'un modèle métier persistant (`dslType == 'model'`).
  bool get isPersistentModel => dslType == 'model';

  /// Indique si la couche Domain hexagonale contient des spécifications.
  bool get hasDomainLayer => domainLayerJson.isNotEmpty;

  /// Libellé effectif (retombe sur [technicalName] ou [name] si [title] est vide).
  String get effectiveLabel => title.trim().isNotEmpty
      ? title.trim()
      : (name.trim().isNotEmpty ? name.trim() : technicalName);

  /// Description fonctionnelle extraite de [objectSpecJson].
  String get description => (objectSpecJson['description'] as String?) ?? '';

  /// Indique si le modèle est racine d'agrégat DDD (`true` par défaut).
  bool get isAggregateRoot => objectSpecJson['aggregateRoot'] as bool? ?? true;

  /// Attributs typés extraits de [objectSpecJson].
  List<Map<String, Object?>> get attributes =>
      freezeJsonMapList(objectSpecJson['attributes']);

  /// Relations inter-objets extraites de [objectSpecJson].
  List<Map<String, Object?>> get relations =>
      freezeJsonMapList(objectSpecJson['relations']);

  /// États du cycle de vie extraits de [objectSpecJson].
  List<Map<String, Object?>> get lifecycleStates =>
      freezeJsonMapList(objectSpecJson['lifecycleStates']);

  /// Transitions du cycle de vie extraites de [objectSpecJson].
  List<Map<String, Object?>> get lifecycleTransitions =>
      freezeJsonMapList(objectSpecJson['lifecycleTransitions']);

  /// Onglet 1 de la couche Domain : invariants métier permanents.
  List<Map<String, Object?>> get invariants => freezeJsonMapList(
    domainLayerJson['invariants'] ?? domainLayerJson['invariant_behaviors'],
  );

  /// Onglet 2 de la couche Domain : méthodes et commandes modifiant l'état (`State changing`).
  List<Map<String, Object?>> get stateChangingMethods => freezeJsonMapList(
    domainLayerJson['stateChangingMethods'] ??
        domainLayerJson['stateChanges'] ??
        domainLayerJson['state_changing_behaviors'],
  );

  /// Onglet 3 de la couche Domain : méthodes pures et calculs sans effet de bord (`Query`).
  List<Map<String, Object?>> get queryMethods => freezeJsonMapList(
    domainLayerJson['queryMethods'] ??
        domainLayerJson['queries'] ??
        domainLayerJson['query_behaviors'],
  );

  /// Onglet 4 de la couche Domain : services et politiques métier sans état (`Policy Services`).
  List<Map<String, Object?>> get policyServices => freezeJsonMapList(
    domainLayerJson['policyServices'] ??
        domainLayerJson['policy_service_behaviors'],
  );

  /// Onglet 5 de la couche Domain : fabriques et constructeurs métier (`Factory`).
  List<Map<String, Object?>> get factories => freezeJsonMapList(
    domainLayerJson['factories'] ?? domainLayerJson['factory_behaviors'],
  );

  /// Onglet 6 de la couche Domain : événements du domaine publiés (`Domain events`).
  List<Map<String, Object?>> get domainEvents => freezeJsonMapList(
    domainLayerJson['domainEvents'] ??
        domainLayerJson['domain_event_behaviors'],
  );

  /// Onglet 7 de la couche Domain : politique de persistance normalisée
  /// (`repositoryPortName`, `concurrencyStrategy`, `deletionStrategy`, `transactionalBoundary`).
  Map<String, Object?> get persistencePolicy {
    final raw =
        domainLayerJson['persistencePolicy'] ??
        domainLayerJson['persistence_policy_behaviors'];
    if (raw is! Map) return const <String, Object?>{};
    final base = freezeJsonMap(raw);
    final boundary =
        ((base['transactionalBoundary'] ?? base['aggregateBoundary'])
                as String?)
            ?.trim() ??
        '';
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      ...base,
      'repositoryPortName':
          (base['repositoryPortName'] as String?)?.trim() ?? '',
      'concurrencyStrategy':
          (base['concurrencyStrategy'] as String?)?.trim() ??
          'optimisticVersion',
      'deletionStrategy':
          (base['deletionStrategy'] as String?)?.trim() ?? 'softDelete',
      'transactionalBoundary': boundary,
    });
  }

  /// Méthodes et règles du port Repository extraites de [persistencePolicy].
  List<Map<String, Object?>> get repositoryPortMethods => freezeJsonMapList(
    persistencePolicy['portMethods'] ?? persistencePolicy['behaviors'],
  );

  /// Vérifie les invariants de l'entrée de contrat.
  void validate() {
    if (entryId.trim().isEmpty) {
      throw const FormatException('ImportedContractEntry.entryId requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('ImportedContractEntry.name requis.');
    }
    if (technicalName.trim().isEmpty) {
      throw const FormatException(
        'ImportedContractEntry.technicalName requis.',
      );
    }
    if (groupName.trim().isEmpty) {
      throw const FormatException('ImportedContractEntry.groupName requis.');
    }
    if (dslType.trim().isEmpty) {
      throw const FormatException('ImportedContractEntry.dslType requis.');
    }
  }

  /// Retourne une copie modifiée.
  ImportedContractEntry copyWith({
    String? entryId,
    String? name,
    String? technicalName,
    String? groupName,
    String? dslType,
    String? title,
    String? version,
    Map<String, String>? states,
    Map<String, Object?>? objectSpecJson,
    Map<String, Object?>? jsonSchema,
    Map<String, Object?>? domainLayerJson,
  }) => ImportedContractEntry(
    entryId: entryId ?? this.entryId,
    name: name ?? this.name,
    technicalName: technicalName ?? this.technicalName,
    groupName: groupName ?? this.groupName,
    dslType: dslType ?? this.dslType,
    title: title ?? this.title,
    version: version ?? this.version,
    states: states ?? this.states,
    objectSpecJson: objectSpecJson ?? this.objectSpecJson,
    jsonSchema: jsonSchema ?? this.jsonSchema,
    domainLayerJson: domainLayerJson ?? this.domainLayerJson,
  );

  /// Sérialise l'entrée de contrat en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'entryId': entryId,
    'name': name,
    'technicalName': technicalName,
    'groupName': groupName,
    'dslType': dslType,
    'title': title,
    'version': version,
    if (states.isNotEmpty) 'states': states,
    'objectSpecJson': objectSpecJson,
    'jsonSchema': jsonSchema,
    if (domainLayerJson.isNotEmpty) 'domainLayerJson': domainLayerJson,
  };

  /// Désérialise une entrée de contrat depuis JSON.
  factory ImportedContractEntry.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedContractEntry invalide.');
    }
    final objMap = raw['objectSpecJson'] is Map
        ? freezeJsonMap(raw['objectSpecJson'] as Map)
        : (raw['objectSpec'] is Map
              ? freezeJsonMap(raw['objectSpec'] as Map)
              : const <String, Object?>{});
    final domMap = raw['domainLayerJson'] is Map
        ? freezeJsonMap(raw['domainLayerJson'] as Map)
        : (raw['domainLayer'] is Map
              ? freezeJsonMap(raw['domainLayer'] as Map)
              : (raw['domainLayerSpec'] is Map
                    ? freezeJsonMap(raw['domainLayerSpec'] as Map)
                    : const <String, Object?>{}));
    final schemaMap = raw['jsonSchema'] is Map
        ? freezeJsonMap(raw['jsonSchema'] as Map)
        : (raw['schema'] is Map
              ? freezeJsonMap(raw['schema'] as Map)
              : const <String, Object?>{});

    final entryId = ((raw['entryId'] ?? raw['id']) as String?)?.trim() ?? '';
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final rawTech =
        ((raw['technicalName'] ?? objMap['technicalName']) as String?)
            ?.trim() ??
        '';
    final effectiveName = rawName.isNotEmpty ? rawName : rawTech;
    final effectiveTech = rawTech.isNotEmpty
        ? rawTech
        : _toPascalCase(effectiveName);

    final parsedStates = <String, String>{};
    if (raw['states'] case final Map statesMap) {
      for (final e in statesMap.entries) {
        if (e.value != null) {
          parsedStates['${e.key}'] = '${e.value}';
        }
      }
    }

    final rawGroup =
        ((raw['groupName'] ?? raw['group']) as String?)?.trim() ?? '';
    final rawDslType =
        ((raw['dslType'] ?? raw['type']) as String?)?.trim() ?? '';
    final rawVersion = (raw['version'] as String?)?.trim() ?? '';

    final item = ImportedContractEntry(
      entryId: entryId,
      name: effectiveName,
      technicalName: effectiveTech,
      groupName: rawGroup.isEmpty ? 'models' : rawGroup,
      dslType: rawDslType.isEmpty ? 'model' : rawDslType,
      title: (raw['title'] as String?) ?? '',
      version: rawVersion.isEmpty ? '0.0.1' : rawVersion,
      states: parsedStates,
      objectSpecJson: objMap,
      jsonSchema: schemaMap,
      domainLayerJson: domMap,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedContractEntry &&
          other.entryId == entryId &&
          other.name == name &&
          other.technicalName == technicalName &&
          other.groupName == groupName &&
          other.dslType == dslType &&
          other.title == title &&
          other.version == version &&
          mapEquals(other.states, states) &&
          deepJsonEquals(other.objectSpecJson, objectSpecJson) &&
          deepJsonEquals(other.jsonSchema, jsonSchema) &&
          deepJsonEquals(other.domainLayerJson, domainLayerJson);

  @override
  int get hashCode => Object.hash(
    entryId,
    name,
    technicalName,
    groupName,
    dslType,
    title,
    version,
    Object.hashAllUnordered(<int>[
      for (final e in states.entries) Object.hash(e.key, e.value),
    ]),
    deepJsonHash(objectSpecJson),
    deepJsonHash(jsonSchema),
    deepJsonHash(domainLayerJson),
  );
}

/// Use Case applicatif CQRS (`command` ou `query`) importé depuis le Design.
@immutable
class ImportedUseCaseSpec {
  /// Crée une spécification de Use Case importée.
  ImportedUseCaseSpec({
    required this.id,
    required this.code,
    required this.name,
    this.title = '',
    this.version = '0.0.1',
    this.boundedContext = '',
    this.cqrsType = 'command',
    this.targetAggregate = '',
    this.businessGoal = '',
    this.inboundPort = '',
    List<String> outboundPorts = const <String>[],
    List<String> emittedEvents = const <String>[],
    List<String> businessRules = const <String>[],
    List<String> detailedProcess = const <String>[],
    List<String> possibleErrors = const <String>[],
    List<Map<String, Object?>> scenarios = const <Map<String, Object?>>[],
    Map<String, Object?> specJson = const <String, Object?>{},
    Map<String, Object?> inputJsonSchema = const <String, Object?>{},
    Map<String, Object?> outputJsonSchema = const <String, Object?>{},
  }) : outboundPorts = List<String>.unmodifiable(outboundPorts),
       emittedEvents = List<String>.unmodifiable(emittedEvents),
       businessRules = List<String>.unmodifiable(businessRules),
       detailedProcess = List<String>.unmodifiable(detailedProcess),
       possibleErrors = List<String>.unmodifiable(possibleErrors),
       scenarios = freezeJsonMapList(scenarios),
       specJson = freezeJsonMap(specJson),
       inputJsonSchema = freezeJsonMap(inputJsonSchema),
       outputJsonSchema = freezeJsonMap(outputJsonSchema);

  /// Identifiant technique stable du Use Case.
  final String id;

  /// Code fonctionnel court (ex. `UC-001`).
  final String code;

  /// Nom technique PascalCase en anglais (ex. `CreateInvoice`).
  final String name;

  /// Titre fonctionnel en français.
  final String title;

  /// Version sémantique (`x.y.z`).
  final String version;

  /// Bounded Context propriétaire.
  final String boundedContext;

  /// Nature CQRS (`'command'` ou `'query'`).
  final String cqrsType;

  /// Agrégat ou Read Model principalement ciblé.
  final String targetAggregate;

  /// Objectif métier du Use Case.
  final String businessGoal;

  /// Port entrant (Driving Port).
  final String inboundPort;

  /// Ports sortants sollicités (Repositories, bus, services).
  final List<String> outboundPorts;

  /// Événements métier ou d'intégration publiés.
  final List<String> emittedEvents;

  /// Règles métier appliquées.
  final List<String> businessRules;

  /// Étapes détaillées d'orchestration.
  final List<String> detailedProcess;

  /// Erreurs métier possibles.
  final List<String> possibleErrors;

  /// Scénarios Given / When / Then.
  final List<Map<String, Object?>> scenarios;

  /// Spécification JSON complète d'origine du Use Case.
  final Map<String, Object?> specJson;

  /// JSON Schema Draft 2020-12 de la charge utile d'entrée.
  final Map<String, Object?> inputJsonSchema;

  /// JSON Schema Draft 2020-12 de la charge utile de sortie.
  final Map<String, Object?> outputJsonSchema;

  /// Indique s'il s'agit d'une commande CQRS (`cqrsType == 'command'`).
  bool get isCommand => cqrsType == 'command';

  /// Indique s'il s'agit d'une requête CQRS (`cqrsType == 'query'`).
  bool get isQuery => cqrsType == 'query';

  /// Libellé effectif du Use Case.
  String get effectiveTitle => title.trim().isNotEmpty ? title.trim() : name;

  /// Vérifie les invariants du Use Case importé.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedUseCaseSpec.id requis.');
    }
    if (name.trim().isEmpty && title.trim().isEmpty) {
      throw const FormatException('ImportedUseCaseSpec.name ou title requis.');
    }
    if (cqrsType != 'command' && cqrsType != 'query') {
      throw FormatException(
        'ImportedUseCaseSpec.cqrsType invalide : $cqrsType '
        '(attendu : command ou query).',
      );
    }
  }

  /// Retourne une copie modifiée.
  ImportedUseCaseSpec copyWith({
    String? id,
    String? code,
    String? name,
    String? title,
    String? version,
    String? boundedContext,
    String? cqrsType,
    String? targetAggregate,
    String? businessGoal,
    String? inboundPort,
    List<String>? outboundPorts,
    List<String>? emittedEvents,
    List<String>? businessRules,
    List<String>? detailedProcess,
    List<String>? possibleErrors,
    List<Map<String, Object?>>? scenarios,
    Map<String, Object?>? specJson,
    Map<String, Object?>? inputJsonSchema,
    Map<String, Object?>? outputJsonSchema,
  }) => ImportedUseCaseSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    title: title ?? this.title,
    version: version ?? this.version,
    boundedContext: boundedContext ?? this.boundedContext,
    cqrsType: cqrsType ?? this.cqrsType,
    targetAggregate: targetAggregate ?? this.targetAggregate,
    businessGoal: businessGoal ?? this.businessGoal,
    inboundPort: inboundPort ?? this.inboundPort,
    outboundPorts: outboundPorts ?? this.outboundPorts,
    emittedEvents: emittedEvents ?? this.emittedEvents,
    businessRules: businessRules ?? this.businessRules,
    detailedProcess: detailedProcess ?? this.detailedProcess,
    possibleErrors: possibleErrors ?? this.possibleErrors,
    scenarios: scenarios ?? this.scenarios,
    specJson: specJson ?? this.specJson,
    inputJsonSchema: inputJsonSchema ?? this.inputJsonSchema,
    outputJsonSchema: outputJsonSchema ?? this.outputJsonSchema,
  );

  /// Sérialise le Use Case importé en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'title': title,
    'version': version,
    'boundedContext': boundedContext,
    'cqrsType': cqrsType,
    'targetAggregate': targetAggregate,
    'businessGoal': businessGoal,
    'inboundPort': inboundPort,
    'outboundPorts': outboundPorts,
    'emittedEvents': emittedEvents,
    'businessRules': businessRules,
    'detailedProcess': detailedProcess,
    'possibleErrors': possibleErrors,
    'scenarios': scenarios,
    'specJson': specJson,
    'inputJsonSchema': inputJsonSchema,
    'outputJsonSchema': outputJsonSchema,
  };

  /// Désérialise un Use Case importé depuis JSON (format plat ou `{ spec, inputJsonSchema, outputJsonSchema }`).
  factory ImportedUseCaseSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedUseCaseSpec invalide.');
    }
    final specMap = raw['specJson'] is Map
        ? freezeJsonMap(raw['specJson'] as Map)
        : (raw['spec'] is Map
              ? freezeJsonMap(raw['spec'] as Map)
              : const <String, Object?>{});

    String pickStr(String key, [String fallback = '']) {
      final v = (raw[key] ?? specMap[key]) as String?;
      return v?.trim() ?? fallback;
    }

    final rawName = pickStr('name');
    final rawTitle = pickStr('title');
    final effectiveName = rawName.isNotEmpty ? rawName : rawTitle;
    final rawId = pickStr('id');
    final rawCode = pickStr('code');
    final rawVersion = pickStr('version', '0.0.1');
    final rawCqrs =
        ((raw['cqrsType'] ?? specMap['cqrsType'] ?? raw['type']) as String?)
            ?.trim()
            .toLowerCase() ??
        'command';
    final normalizedCqrs =
        (rawCqrs == 'query' || rawCqrs == 'q' || rawCqrs.contains('lecture'))
        ? 'query'
        : 'command';

    final item = ImportedUseCaseSpec(
      id: rawId,
      code: rawCode.isEmpty ? 'UC-001' : rawCode,
      name: effectiveName,
      title: rawTitle.isNotEmpty ? rawTitle : effectiveName,
      version: rawVersion.isEmpty ? '0.0.1' : rawVersion,
      boundedContext: pickStr('boundedContext'),
      cqrsType: normalizedCqrs,
      targetAggregate: pickStr('targetAggregate'),
      businessGoal: pickStr('businessGoal'),
      inboundPort: pickStr('inboundPort'),
      outboundPorts: parseCleanStringList(
        raw['outboundPorts'] ?? specMap['outboundPorts'],
      ),
      emittedEvents: parseCleanStringList(
        raw['emittedEvents'] ?? specMap['emittedEvents'],
      ),
      businessRules: parseCleanStringList(
        raw['businessRules'] ?? specMap['businessRules'],
      ),
      detailedProcess: parseCleanStringList(
        raw['detailedProcess'] ?? specMap['detailedProcess'],
      ),
      possibleErrors: parseCleanStringList(
        raw['possibleErrors'] ?? specMap['possibleErrors'],
      ),
      scenarios: freezeJsonMapList(raw['scenarios'] ?? specMap['scenarios']),
      specJson: specMap,
      inputJsonSchema: raw['inputJsonSchema'] is Map
          ? freezeJsonMap(raw['inputJsonSchema'] as Map)
          : (raw['inputSchema'] is Map
                ? freezeJsonMap(raw['inputSchema'] as Map)
                : const <String, Object?>{}),
      outputJsonSchema: raw['outputJsonSchema'] is Map
          ? freezeJsonMap(raw['outputJsonSchema'] as Map)
          : (raw['outputSchema'] is Map
                ? freezeJsonMap(raw['outputSchema'] as Map)
                : const <String, Object?>{}),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedUseCaseSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.title == title &&
          other.version == version &&
          other.boundedContext == boundedContext &&
          other.cqrsType == cqrsType &&
          other.targetAggregate == targetAggregate &&
          other.businessGoal == businessGoal &&
          other.inboundPort == inboundPort &&
          listEquals(other.outboundPorts, outboundPorts) &&
          listEquals(other.emittedEvents, emittedEvents) &&
          listEquals(other.businessRules, businessRules) &&
          listEquals(other.detailedProcess, detailedProcess) &&
          listEquals(other.possibleErrors, possibleErrors) &&
          deepJsonEquals(other.scenarios, scenarios) &&
          deepJsonEquals(other.specJson, specJson) &&
          deepJsonEquals(other.inputJsonSchema, inputJsonSchema) &&
          deepJsonEquals(other.outputJsonSchema, outputJsonSchema);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    code,
    name,
    title,
    version,
    boundedContext,
    cqrsType,
    targetAggregate,
    businessGoal,
    inboundPort,
    Object.hashAll(outboundPorts),
    Object.hashAll(emittedEvents),
    Object.hashAll(businessRules),
    Object.hashAll(detailedProcess),
    Object.hashAll(possibleErrors),
    deepJsonHash(scenarios),
    deepJsonHash(specJson),
    deepJsonHash(inputJsonSchema),
    deepJsonHash(outputJsonSchema),
  ]);
}

/// Saga distribuée (orchestrée ou chorégraphiée) importée avec son diagramme
/// Mermaid et ses étapes / compensations.
@immutable
class ImportedSagaSpec {
  /// Crée une spécification de Saga importée.
  ImportedSagaSpec({
    required this.id,
    required this.code,
    required this.name,
    this.title = '',
    this.version = '0.0.1',
    this.boundedContext = '',
    this.coordinationMode = 'orchestration',
    this.triggerEvent = '',
    this.mermaidDiagram = '',
    List<Map<String, Object?>> steps = const <Map<String, Object?>>[],
    List<Map<String, Object?>> compensations = const <Map<String, Object?>>[],
    Map<String, Object?> specJson = const <String, Object?>{},
  }) : steps = freezeJsonMapList(steps),
       compensations = freezeJsonMapList(compensations),
       specJson = freezeJsonMap(specJson);

  /// Identifiant technique stable de la Saga.
  final String id;

  /// Code court de la Saga (ex. `SAGA-001`).
  final String code;

  /// Nom technique PascalCase de la Saga.
  final String name;

  /// Titre fonctionnel en français.
  final String title;

  /// Version sémantique (`x.y.z`).
  final String version;

  /// Bounded Context(s) impliqué(s).
  final String boundedContext;

  /// Mode de coordination (`orchestration` ou `choreography`).
  final String coordinationMode;

  /// Événement ou commande déclenchant la Saga.
  final String triggerEvent;

  /// Diagramme de séquence ou d'états en syntaxe Mermaid.
  final String mermaidDiagram;

  /// Étapes structurées de la Saga.
  final List<Map<String, Object?>> steps;

  /// Matrice des compensations / rollbacks de la Saga.
  final List<Map<String, Object?>> compensations;

  /// Spécification JSON brute complète d'origine de la Saga.
  final Map<String, Object?> specJson;

  /// Vérifie les invariants de la Saga importée.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ImportedSagaSpec.id requis.');
    }
    if (name.trim().isEmpty && title.trim().isEmpty) {
      throw const FormatException('ImportedSagaSpec.name ou title requis.');
    }
  }

  /// Retourne une copie modifiée.
  ImportedSagaSpec copyWith({
    String? id,
    String? code,
    String? name,
    String? title,
    String? version,
    String? boundedContext,
    String? coordinationMode,
    String? triggerEvent,
    String? mermaidDiagram,
    List<Map<String, Object?>>? steps,
    List<Map<String, Object?>>? compensations,
    Map<String, Object?>? specJson,
  }) => ImportedSagaSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    title: title ?? this.title,
    version: version ?? this.version,
    boundedContext: boundedContext ?? this.boundedContext,
    coordinationMode: coordinationMode ?? this.coordinationMode,
    triggerEvent: triggerEvent ?? this.triggerEvent,
    mermaidDiagram: mermaidDiagram ?? this.mermaidDiagram,
    steps: steps ?? this.steps,
    compensations: compensations ?? this.compensations,
    specJson: specJson ?? this.specJson,
  );

  /// Sérialise la Saga importée en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'title': title,
    'version': version,
    'boundedContext': boundedContext,
    'coordinationMode': coordinationMode,
    'triggerEvent': triggerEvent,
    'mermaidDiagram': mermaidDiagram,
    'steps': steps,
    'compensations': compensations,
    'specJson': specJson,
  };

  /// Désérialise une Saga importée depuis JSON.
  factory ImportedSagaSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ImportedSagaSpec invalide.');
    }
    final hasExplicitSpecJson =
        raw.containsKey('specJson') || raw.containsKey('spec');
    final specMap = raw['specJson'] is Map
        ? freezeJsonMap(raw['specJson'] as Map)
        : (raw['spec'] is Map
              ? freezeJsonMap(raw['spec'] as Map)
              : (hasExplicitSpecJson
                    ? const <String, Object?>{}
                    : freezeJsonMap(raw)));

    String pickStr(String key, [String fallback = '']) {
      final v = (raw[key] ?? specMap[key]) as String?;
      return v?.trim() ?? fallback;
    }

    final rawName = pickStr('name');
    final rawTitle = pickStr('title');
    final effectiveName = rawName.isNotEmpty ? rawName : rawTitle;
    final rawBc = pickStr('boundedContext');
    final bcList = parseCleanStringList(
      raw['boundedContexts'] ?? specMap['boundedContexts'],
    );
    final effectiveBc = rawBc.isNotEmpty ? rawBc : bcList.join(', ');

    final rawTrigger = pickStr('triggerEvent');
    final effectiveTrigger = rawTrigger.isNotEmpty
        ? rawTrigger
        : pickStr('triggerEventOrCommand');

    final rawVersion = pickStr('version', '0.0.1');
    final rawCode = pickStr('code', 'SAGA-001');
    final rawMode = pickStr('coordinationMode', 'orchestration');

    final item = ImportedSagaSpec(
      id: pickStr('id'),
      code: rawCode.isEmpty ? 'SAGA-001' : rawCode,
      name: effectiveName,
      title: rawTitle.isNotEmpty ? rawTitle : effectiveName,
      version: rawVersion.isEmpty ? '0.0.1' : rawVersion,
      boundedContext: effectiveBc,
      coordinationMode: rawMode.isEmpty ? 'orchestration' : rawMode,
      triggerEvent: effectiveTrigger,
      mermaidDiagram:
          (raw['mermaidDiagram'] ?? specMap['mermaidDiagram']) as String? ?? '',
      steps: freezeJsonMapList(raw['steps'] ?? specMap['steps']),
      compensations: freezeJsonMapList(
        raw['compensations'] ??
            raw['compensationMatrix'] ??
            specMap['compensationMatrix'],
      ),
      specJson: specMap,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedSagaSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.title == title &&
          other.version == version &&
          other.boundedContext == boundedContext &&
          other.coordinationMode == coordinationMode &&
          other.triggerEvent == triggerEvent &&
          other.mermaidDiagram == mermaidDiagram &&
          deepJsonEquals(other.steps, steps) &&
          deepJsonEquals(other.compensations, compensations) &&
          deepJsonEquals(other.specJson, specJson);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    title,
    version,
    boundedContext,
    coordinationMode,
    triggerEvent,
    mermaidDiagram,
    deepJsonHash(steps),
    deepJsonHash(compensations),
    deepJsonHash(specJson),
  );
}

/// Agrégat racine immuable représentant la spécification Design complète d'un
/// domaine fonctionnel importé en lecture seule (`super_spec_forge.domain_design_spec` v1).
@immutable
class DomainDesignSpec {
  /// Crée une spécification Design complète de domaine.
  DomainDesignSpec({
    this.format = formatId,
    this.version = currentVersion,
    DateTime? exportedAt,
    this.sourceKind = DesignSourceKind.current,
    this.snapshotMeta,
    required this.domain,
    List<ImportedEnvironmentSpec> environments =
        const <ImportedEnvironmentSpec>[],
    List<ImportedSystemSpec> systems = const <ImportedSystemSpec>[],
    List<ImportedConfigurationSpec> configurations =
        const <ImportedConfigurationSpec>[],
    List<ImportedValueObjectSpec> valueObjects =
        const <ImportedValueObjectSpec>[],
    this.dslSource = '',
    List<ImportedContractEntry> contractEntries =
        const <ImportedContractEntry>[],
    List<Map<String, Object?>> cartography = const <Map<String, Object?>>[],
    List<ImportedUseCaseSpec> useCases = const <ImportedUseCaseSpec>[],
    List<ImportedSagaSpec> sagas = const <ImportedSagaSpec>[],
  }) : exportedAt = (exportedAt ??
               DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc(),
       environments = List<ImportedEnvironmentSpec>.unmodifiable(environments),
       systems = List<ImportedSystemSpec>.unmodifiable(systems),
       configurations = List<ImportedConfigurationSpec>.unmodifiable(
         configurations,
       ),
       valueObjects = List<ImportedValueObjectSpec>.unmodifiable(valueObjects),
       contractEntries = List<ImportedContractEntry>.unmodifiable(
         contractEntries,
       ),
       cartography = freezeJsonMapList(cartography),
       useCases = List<ImportedUseCaseSpec>.unmodifiable(useCases),
       sagas = List<ImportedSagaSpec>.unmodifiable(sagas);

  /// Identifiant canonique du format JSON d'export Design.
  static const String formatId = 'super_spec_forge.domain_design_spec';

  /// Version courante du format JSON supporté.
  static const int currentVersion = 1;

  /// Identifiant de format du document (`super_spec_forge.domain_design_spec`).
  final String format;

  /// Version du format (`1`).
  final int version;

  /// Horodatage UTC de l'export ou de la lecture.
  final DateTime exportedAt;

  /// Origine de la spécification (`current`, `snapshot`, `workspaceCatalog`).
  final DesignSourceKind sourceKind;

  /// Métadonnées du jalon lorsque [sourceKind] vaut [DesignSourceKind.snapshot].
  final ImportedSnapshotMeta? snapshotMeta;

  /// Identité et stack technique du domaine fonctionnel.
  final ImportedDomainIdentity domain;

  /// Environnements logiques rattachés au domaine.
  final List<ImportedEnvironmentSpec> environments;

  /// Systèmes, microservices et applications tierces du domaine.
  final List<ImportedSystemSpec> systems;

  /// Variables de configuration et déclarations de secrets (sans valeurs secrètes).
  final List<ImportedConfigurationSpec> configurations;

  /// Catalogue des Value Objects résolus (`domain` et `shared`).
  final List<ImportedValueObjectSpec> valueObjects;

  /// Source YAML du catalogue DSL des modèles et contrats.
  final String dslSource;

  /// Entrées du catalogue de modèles et contrats.
  final List<ImportedContractEntry> contractEntries;

  /// Cartographie des Use Cases et Sagas par Bounded Context.
  final List<Map<String, Object?>> cartography;

  /// Use Cases applicatifs CQRS du domaine.
  final List<ImportedUseCaseSpec> useCases;

  /// Sagas distribuées du domaine.
  final List<ImportedSagaSpec> sagas;

  /// Modèles persistants du domaine (`dslType == 'model'`).
  List<ImportedContractEntry> get models => contractEntries
      .where((e) => e.isPersistentModel)
      .toList(growable: false);

  /// Contrats DTO d'API (`groupName == 'dto'` ou types `*dto` hors messages).
  List<ImportedContractEntry> get dtos => contractEntries
      .where(
        (e) =>
            e.groupName == 'dto' ||
            (e.groupName != 'message' &&
                (e.dslType == 'createxdto' ||
                    e.dslType == 'updatexdto' ||
                    e.dslType == 'xresponsedto' ||
                    e.dslType == 'xlistitemdto' ||
                    e.dslType == 'xquerydto')),
      )
      .toList(growable: false);

  /// Contrats de messages et d'événements (`groupName == 'message'` ou `eventx*`).
  List<ImportedContractEntry> get messages => contractEntries
      .where(
        (e) =>
            e.groupName == 'message' ||
            e.dslType == 'eventxpayloaddto' ||
            e.dslType == 'eventxenvelopedto',
      )
      .toList(growable: false);

  /// Sous-composants réutilisables (`groupName == 'components'`, `component` ou `part`).
  List<ImportedContractEntry> get components => contractEntries
      .where(
        (e) =>
            e.groupName == 'components' ||
            e.dslType == 'component' ||
            e.dslType == 'part',
      )
      .toList(growable: false);

  /// Recherche une entrée de contrat par son [entryId] exact.
  ImportedContractEntry? findContractById(String entryId) {
    final target = entryId.trim();
    if (target.isEmpty) return null;
    for (final entry in contractEntries) {
      if (entry.entryId == target) return entry;
    }
    return null;
  }

  /// Recherche une entrée de contrat par son [technicalName] (ou son `name`).
  ImportedContractEntry? findContractByTechnicalName(String technicalName) {
    final target = technicalName.trim();
    if (target.isEmpty) return null;
    for (final entry in contractEntries) {
      if (entry.technicalName == target || entry.name == target) return entry;
    }
    final lower = target.toLowerCase();
    for (final entry in contractEntries) {
      if (entry.technicalName.toLowerCase() == lower ||
          entry.name.toLowerCase() == lower) {
        return entry;
      }
    }
    return null;
  }

  /// Recherche un Use Case par son [id] (ou son `code`).
  ImportedUseCaseSpec? findUseCaseById(String id) {
    final target = id.trim();
    if (target.isEmpty) return null;
    for (final uc in useCases) {
      if (uc.id == target) return uc;
    }
    return null;
  }

  /// Recherche une Saga par son [id].
  ImportedSagaSpec? findSagaById(String id) {
    final target = id.trim();
    if (target.isEmpty) return null;
    for (final saga in sagas) {
      if (saga.id == target) return saga;
    }
    return null;
  }

  /// Recherche un Value Object par son `technicalName`, son `name` ou son `id`.
  ImportedValueObjectSpec? findValueObjectByName(String name) {
    final target = name.trim();
    if (target.isEmpty) return null;
    for (final vo in valueObjects) {
      if (vo.technicalName == target || vo.name == target || vo.id == target) {
        return vo;
      }
    }
    final lower = target.toLowerCase();
    for (final vo in valueObjects) {
      if (vo.technicalName.toLowerCase() == lower ||
          vo.name.toLowerCase() == lower ||
          vo.id.toLowerCase() == lower) {
        return vo;
      }
    }
    return null;
  }

  /// Vérifie les invariants de l'ensemble de la spécification Design.
  void validate() {
    if (format != formatId) {
      throw FormatException(
        'Format DomainDesignSpec non supporté : $format (attendu : $formatId).',
      );
    }
    if (version < 1) {
      throw FormatException('Version DomainDesignSpec invalide : $version.');
    }
    domain.validate();
    snapshotMeta?.validate();

    final envIds = <String>{};
    for (final env in environments) {
      env.validate();
      if (!envIds.add(env.id)) {
        throw FormatException('Environnement dupliqué : ${env.id}.');
      }
    }

    final sysIds = <String>{};
    for (final sys in systems) {
      sys.validate();
      if (!sysIds.add(sys.id)) {
        throw FormatException('Système dupliqué : ${sys.id}.');
      }
    }

    final cfgIds = <String>{};
    for (final cfg in configurations) {
      cfg.validate();
      if (!cfgIds.add(cfg.id)) {
        throw FormatException('Configuration dupliquée : ${cfg.id}.');
      }
    }

    final voIds = <String>{};
    for (final vo in valueObjects) {
      vo.validate();
      if (!voIds.add(vo.id)) {
        throw FormatException('Value Object dupliqué : ${vo.id}.');
      }
    }

    final entryIds = <String>{};
    for (final entry in contractEntries) {
      entry.validate();
      if (!entryIds.add(entry.entryId)) {
        throw FormatException(
          'Entrée de contrat dupliquée : ${entry.entryId}.',
        );
      }
    }

    final ucIds = <String>{};
    for (final uc in useCases) {
      uc.validate();
      if (!ucIds.add(uc.id)) {
        throw FormatException('Use Case dupliqué : ${uc.id}.');
      }
    }

    final sagaIds = <String>{};
    for (final saga in sagas) {
      saga.validate();
      if (!sagaIds.add(saga.id)) {
        throw FormatException('Saga dupliquée : ${saga.id}.');
      }
    }
  }

  /// Retourne une copie modifiée.
  DomainDesignSpec copyWith({
    String? format,
    int? version,
    DateTime? exportedAt,
    DesignSourceKind? sourceKind,
    ImportedSnapshotMeta? snapshotMeta,
    bool clearSnapshotMeta = false,
    ImportedDomainIdentity? domain,
    List<ImportedEnvironmentSpec>? environments,
    List<ImportedSystemSpec>? systems,
    List<ImportedConfigurationSpec>? configurations,
    List<ImportedValueObjectSpec>? valueObjects,
    String? dslSource,
    List<ImportedContractEntry>? contractEntries,
    List<Map<String, Object?>>? cartography,
    List<ImportedUseCaseSpec>? useCases,
    List<ImportedSagaSpec>? sagas,
  }) => DomainDesignSpec(
    format: format ?? this.format,
    version: version ?? this.version,
    exportedAt: exportedAt ?? this.exportedAt,
    sourceKind: sourceKind ?? this.sourceKind,
    snapshotMeta: clearSnapshotMeta
        ? null
        : (snapshotMeta ?? this.snapshotMeta),
    domain: domain ?? this.domain,
    environments: environments ?? this.environments,
    systems: systems ?? this.systems,
    configurations: configurations ?? this.configurations,
    valueObjects: valueObjects ?? this.valueObjects,
    dslSource: dslSource ?? this.dslSource,
    contractEntries: contractEntries ?? this.contractEntries,
    cartography: cartography ?? this.cartography,
    useCases: useCases ?? this.useCases,
    sagas: sagas ?? this.sagas,
  );

  /// Sérialise la spécification Design en JSON canonique.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'version': version,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'sourceKind': sourceKind.name,
    if (snapshotMeta != null) 'snapshotMeta': snapshotMeta!.toJson(),
    'domain': domain.toJson(),
    'environments': <Map<String, Object?>>[
      for (final env in environments) env.toJson(),
    ],
    'systems': <Map<String, Object?>>[
      for (final sys in systems) sys.toJson(),
    ],
    'configurations': <Map<String, Object?>>[
      for (final cfg in configurations) cfg.toJson(),
    ],
    'valueObjects': <Map<String, Object?>>[
      for (final vo in valueObjects) vo.toJson(),
    ],
    'dslSource': dslSource,
    'contractEntries': <Map<String, Object?>>[
      for (final entry in contractEntries) entry.toJson(),
    ],
    'cartography': cartography,
    'useCases': <Map<String, Object?>>[
      for (final uc in useCases) uc.toJson(),
    ],
    'sagas': <Map<String, Object?>>[
      for (final saga in sagas) saga.toJson(),
    ],
  };

  /// Désérialise une spécification Design depuis un bundle `.domain-design.json`
  /// (format imbriqué `contracts` / `useCaseOrchestration` de `super_spec_forge`
  /// ou format plat `contractEntries` / `useCases` / `sagas`).
  factory DomainDesignSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainDesignSpec doit être un objet JSON.');
    }
    final rawFormat = (raw['format'] as String?)?.trim();
    final effectiveFormat = (rawFormat == null || rawFormat.isEmpty)
        ? formatId
        : rawFormat;
    final rawVersion = raw['version'];
    final effectiveVersion = switch (rawVersion) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v.trim()) ?? currentVersion,
      _ => currentVersion,
    };

    final rawContracts = raw['contracts'];
    final String resolvedDslSource;
    final Object? rawEntriesList;
    if (raw['contractEntries'] is List) {
      resolvedDslSource = (raw['dslSource'] as String?) ?? '';
      rawEntriesList = raw['contractEntries'];
    } else if (rawContracts is Map) {
      resolvedDslSource =
          (raw['dslSource'] as String?) ??
          (rawContracts['dslSource'] as String?) ??
          (rawContracts['source'] as String?) ??
          '';
      rawEntriesList = rawContracts['entries'] ?? rawContracts['items'];
    } else if (rawContracts is List) {
      resolvedDslSource = (raw['dslSource'] as String?) ?? '';
      rawEntriesList = rawContracts;
    } else {
      resolvedDslSource = (raw['dslSource'] as String?) ?? '';
      rawEntriesList = null;
    }

    final rawOrch =
        raw['useCaseOrchestration'] ?? raw['orchestration'];
    final orchMap = rawOrch is Map ? rawOrch : const <String, Object?>{};
    final rawCartography = raw['cartography'] ?? orchMap['cartography'];
    final rawUseCases = raw['useCases'] ?? orchMap['useCases'];
    final rawSagas = raw['sagas'] ?? orchMap['sagas'];
    final rawSystems = raw['systems'] ?? raw['microservices'];
    final rawSnapshot = raw['snapshotMeta'] ?? raw['snapshot'];

    final spec = DomainDesignSpec(
      format: effectiveFormat,
      version: effectiveVersion,
      exportedAt: parseUtcDateTimeOrEpoch(raw['exportedAt']),
      sourceKind: DesignSourceKind.fromJson(raw['sourceKind']),
      snapshotMeta: rawSnapshot is Map
          ? ImportedSnapshotMeta.fromJson(rawSnapshot)
          : null,
      domain: ImportedDomainIdentity.fromJson(raw['domain']),
      environments: <ImportedEnvironmentSpec>[
        if (raw['environments'] case final List list)
          for (final item in list) ImportedEnvironmentSpec.fromJson(item),
      ],
      systems: <ImportedSystemSpec>[
        if (rawSystems case final List list)
          for (final item in list) ImportedSystemSpec.fromJson(item),
      ],
      configurations: <ImportedConfigurationSpec>[
        if (raw['configurations'] case final List list)
          for (final item in list) ImportedConfigurationSpec.fromJson(item),
      ],
      valueObjects: <ImportedValueObjectSpec>[
        if (raw['valueObjects'] case final List list)
          for (final item in list) ImportedValueObjectSpec.fromJson(item),
      ],
      dslSource: resolvedDslSource,
      contractEntries: <ImportedContractEntry>[
        if (rawEntriesList case final List list)
          for (final item in list) ImportedContractEntry.fromJson(item),
      ],
      cartography: freezeJsonMapList(rawCartography),
      useCases: <ImportedUseCaseSpec>[
        if (rawUseCases case final List list)
          for (final item in list) ImportedUseCaseSpec.fromJson(item),
      ],
      sagas: <ImportedSagaSpec>[
        if (rawSagas case final List list)
          for (final item in list) ImportedSagaSpec.fromJson(item),
      ],
    );
    spec.validate();
    return spec;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainDesignSpec &&
          other.format == format &&
          other.version == version &&
          other.exportedAt == exportedAt &&
          other.sourceKind == sourceKind &&
          other.snapshotMeta == snapshotMeta &&
          other.domain == domain &&
          listEquals(other.environments, environments) &&
          listEquals(other.systems, systems) &&
          listEquals(other.configurations, configurations) &&
          listEquals(other.valueObjects, valueObjects) &&
          other.dslSource == dslSource &&
          listEquals(other.contractEntries, contractEntries) &&
          deepJsonEquals(other.cartography, cartography) &&
          listEquals(other.useCases, useCases) &&
          listEquals(other.sagas, sagas);

  @override
  int get hashCode => Object.hash(
    format,
    version,
    exportedAt,
    sourceKind,
    snapshotMeta,
    domain,
    Object.hashAll(environments),
    Object.hashAll(systems),
    Object.hashAll(configurations),
    Object.hashAll(valueObjects),
    dslSource,
    Object.hashAll(contractEntries),
    deepJsonHash(cartography),
    Object.hashAll(useCases),
    Object.hashAll(sagas),
  );
}
