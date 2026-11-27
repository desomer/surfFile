/// Modèles immuables du catalogue de domaines, environnements, microservices,
/// configurations et événements d'audit ([DomainCatalog]).
library;

import 'package:flutter/foundation.dart';

import 'build_tech_stack_profile.dart';
import 'domain_contracts.dart';
import 'spec_stage_chat.dart';
import 'usecase_orchestration_spec.dart';
import 'value_object_spec.dart';

/// Catégorie d'urbanisme d'un système ou service rattaché à un domaine.
enum DomainSystemKind {
  /// Application ou API externe / tierce (Stripe, SendGrid, SAP, etc.).
  externalApp('Application externe', 'App externe', 'Applications externes'),

  /// Outil open-source auto-hébergé ou déployé (Keycloak, Kafka, MinIO, Meilisearch…).
  openSourceTool('Tools openSource', 'Tools openSource', 'Tools openSource'),

  /// Application Front Web (SPA, portail client, back-office web).
  webFront('Front Web', 'Front Web', 'Fronts Web'),

  /// Application mobile native ou hybride (iOS / Android).
  mobileApp('App Mobile', 'App Mobile', 'Apps Mobiles'),

  /// Backend For Frontend dédié à un canal client.
  bff('BFF (Backend For Frontend)', 'BFF', 'BFF'),

  /// Service métier autonome ou microservice (valeur par défaut rétrocompatible).
  microservice('(Micro)Service', 'Service', '(Micro)Services'),

  /// Application monolithique ou cœur applicatif unifié.
  monolith('Application monolithique', 'Monolithe', 'Applications monolithiques');

  /// Construit une catégorie d'urbanisme.
  const DomainSystemKind(this.label, this.shortLabel, this.pluralLabel);

  /// Libellé complet affiché dans les formulaires et en-têtes.
  final String label;

  /// Libellé compact affiché dans les badges et filtres.
  final String shortLabel;

  /// Libellé pluriel utilisé dans les regroupements.
  final String pluralLabel;

  /// Indique s'il s'agit d'une application/API externe au SI ou au domaine.
  bool get isExternal => this == DomainSystemKind.externalApp;

  /// Indique s'il s'agit d'un outil open-source déployé / auto-hébergé.
  bool get isOpenSourceTool => this == DomainSystemKind.openSourceTool;

  /// Indique s'il s'agit d'un outil ou système tiers hors code interne (sans stack Build dédiée).
  bool get isOffTheShelf => isExternal || isOpenSourceTool;

  /// Indique s'il s'agit d'une application frontale (Web ou Mobile).
  bool get isFrontend =>
      this == DomainSystemKind.webFront || this == DomainSystemKind.mobileApp;

  /// Indique s'il s'agit d'un composant serveur interne (BFF, Service, Monolithe).
  bool get isBackend =>
      this == DomainSystemKind.bff ||
      this == DomainSystemKind.microservice ||
      this == DomainSystemKind.monolith;

  /// Désérialise une catégorie de système (`microservice` par défaut si absente).
  static DomainSystemKind fromJson(Object? raw) {
    if (raw == null) return DomainSystemKind.microservice;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return DomainSystemKind.microservice;
      for (final kind in values) {
        if (trimmed == kind.name) return kind;
      }
      final norm = trimmed.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
      switch (norm) {
        case 'externalapp':
        case 'external_app':
        case 'external':
        case 'external_system':
        case 'application_externe':
        case 'app_externe':
          return DomainSystemKind.externalApp;
        case 'opensourcetool':
        case 'open_source_tool':
        case 'open_source':
        case 'opensource':
        case 'tools_opensource':
        case 'tool_opensource':
        case 'tools_open_source':
        case 'tool_open_source':
        case 'oss':
        case 'oss_tool':
          return DomainSystemKind.openSourceTool;
        case 'webfront':
        case 'web_front':
        case 'front_web':
        case 'web':
        case 'spa':
          return DomainSystemKind.webFront;
        case 'mobileapp':
        case 'mobile_app':
        case 'app_mobile':
        case 'mobile':
          return DomainSystemKind.mobileApp;
        case 'bff':
        case 'backend_for_frontend':
          return DomainSystemKind.bff;
        case 'microservice':
        case 'micro_service':
        case 'service':
          return DomainSystemKind.microservice;
        case 'monolith':
        case 'monolithe':
        case 'monolithic':
        case 'application_monolithique':
        case 'app_monolithique':
          return DomainSystemKind.monolith;
      }
    }
    throw FormatException('Catégorie de système inconnue : $raw');
  }
}

/// Statut du cycle de vie d'un environnement logique.
enum LogicalEnvironmentStatus {
  /// Environnement opérationnel.
  active,

  /// Environnement en fin de cycle de vie.
  deprecated,

  /// Environnement figé et archivé.
  archived;

  /// Désérialise un statut d'environnement.
  static LogicalEnvironmentStatus fromJson(Object? raw) {
    for (final status in values) {
      if (raw == status.name) return status;
    }
    throw FormatException('Statut d’environnement inconnu : $raw');
  }
}

/// Classification d'une entrée de configuration.
enum ConfigurationEntryType {
  /// Valeur persistée en clair.
  plainVariable,

  /// Valeur chiffrée avant persistance.
  secret;

  /// Désérialise une classification.
  static ConfigurationEntryType fromJson(Object? raw) {
    for (final type in values) {
      if (raw == type.name) return type;
    }
    throw FormatException('Type de configuration inconnu : $raw');
  }
}

/// Nature d'une opération consignée dans le journal d'audit.
enum DomainAuditAction {
  /// Création d'une entité.
  create,

  /// Modification d'une entité.
  update,

  /// Suppression d'une entité.
  delete,

  /// Clonage d'un environnement.
  clone;

  /// Désérialise un type d'action.
  static DomainAuditAction fromJson(Object? raw) {
    for (final action in values) {
      if (raw == action.name) return action;
    }
    throw FormatException('Action d’audit inconnue : $raw');
  }
}

final RegExp _domainCodePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final RegExp _configKeyPattern = RegExp(r'^[A-Z0-9]+(?:_[A-Z0-9]+)*$');

void _validateDomainCode(String code, String field) {
  if (code.length < 2 || code.length > 64 || !_domainCodePattern.hasMatch(code)) {
    throw FormatException(
      '$field doit être en kebab-case (2 à 64 caractères).',
    );
  }
}

/// Domaine fonctionnel autonome (Bounded Context).
@immutable
class FunctionalDomain {
  /// Crée un domaine fonctionnel.
  const FunctionalDomain({
    required this.id,
    required this.domainCode,
    required this.name,
    this.description = '',
    this.isActive = true,
    this.techStackId,
    this.contracts,
    this.useCaseOrchestration,
    this.systemsServicesChat = const <SpecChatMessage>[],
    this.valueObjects = const <ValueObjectSpec>[],
    this.valueObjectsChat = const <SpecChatMessage>[],
  });

  /// Identifiant technique.
  final String id;

  /// Identifiant canonique en kebab-case.
  final String domainCode;

  /// Nom affiché.
  final String name;

  /// Description métier.
  final String description;

  /// Indique si le domaine est actif.
  final bool isActive;

  /// Identifiant optionnel du profil de stack technique ([BuildTechStackProfile.id])
  /// associé à ce domaine pour la génération des prompts Build.
  final String? techStackId;

  /// Catalogue de modèles et contrats, absent pour un domaine encore vierge.
  final DomainContracts? contracts;

  /// Spécification « Cas d’usage & orchestration » du domaine, absente si vierge.
  final UseCaseOrchestrationSpec? useCaseOrchestration;

  /// Historique de conversation IA « Systèmes & Services » du domaine.
  final List<SpecChatMessage> systemsServicesChat;

  /// Catalogue des Value Objects (Architecture Hexagonale) propres à ce domaine.
  final List<ValueObjectSpec> valueObjects;

  /// Historique de conversation IA du catalogue de Value Objects de ce domaine.
  final List<SpecChatMessage> valueObjectsChat;

  /// Vérifie les invariants du domaine.
  void validate() {
    if (id.trim().isEmpty) throw const FormatException('Domaine.id requis.');
    _validateDomainCode(domainCode, 'Domaine.domainCode');
    if (name.trim().length < 2 || name.trim().length > 255) {
      throw const FormatException('Le nom du domaine doit contenir 2 à 255 caractères.');
    }
    if (description.length > 2000) {
      throw const FormatException('La description du domaine dépasse 2000 caractères.');
    }
    useCaseOrchestration?.validate();
    final voIds = <String>{};
    final voTechNames = <String>{};
    for (final vo in valueObjects) {
      vo.validate();
      if (!voIds.add(vo.id)) {
        throw FormatException(
          'Identifiant de Value Object dupliqué dans $domainCode : ${vo.id}',
        );
      }
      if (!voTechNames.add(vo.technicalName.toLowerCase())) {
        throw FormatException(
          'Nom technique de Value Object dupliqué dans $domainCode : ${vo.technicalName}',
        );
      }
    }
  }

  /// Copie modifiée.
  FunctionalDomain copyWith({
    String? id,
    String? domainCode,
    String? name,
    String? description,
    bool? isActive,
    String? techStackId,
    bool clearTechStackId = false,
    DomainContracts? contracts,
    UseCaseOrchestrationSpec? useCaseOrchestration,
    List<SpecChatMessage>? systemsServicesChat,
    List<ValueObjectSpec>? valueObjects,
    List<SpecChatMessage>? valueObjectsChat,
  }) => FunctionalDomain(
    id: id ?? this.id,
    domainCode: domainCode ?? this.domainCode,
    name: name ?? this.name,
    description: description ?? this.description,
    isActive: isActive ?? this.isActive,
    techStackId: clearTechStackId ? null : (techStackId ?? this.techStackId),
    contracts: contracts ?? this.contracts,
    useCaseOrchestration: useCaseOrchestration ?? this.useCaseOrchestration,
    systemsServicesChat: systemsServicesChat == null
        ? this.systemsServicesChat
        : List<SpecChatMessage>.unmodifiable(systemsServicesChat),
    valueObjects: valueObjects == null
        ? this.valueObjects
        : List<ValueObjectSpec>.unmodifiable(valueObjects),
    valueObjectsChat: valueObjectsChat == null
        ? this.valueObjectsChat
        : List<SpecChatMessage>.unmodifiable(valueObjectsChat),
  );

  /// Sérialise le domaine.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainCode': domainCode,
    'name': name,
    'description': description,
    'isActive': isActive,
    if (techStackId != null && techStackId!.trim().isNotEmpty)
      'techStackId': techStackId,
    if (contracts != null) 'contracts': contracts!.toJson(),
    if (useCaseOrchestration != null && !useCaseOrchestration!.isEmpty)
      'useCaseOrchestration': useCaseOrchestration!.toJson(),
    if (systemsServicesChat.isNotEmpty)
      'systemsServicesChat': [
        for (final msg in systemsServicesChat) msg.toJson(),
      ],
    if (valueObjects.isNotEmpty)
      'valueObjects': [for (final vo in valueObjects) vo.toJson()],
    if (valueObjectsChat.isNotEmpty)
      'valueObjectsChat': [
        for (final msg in valueObjectsChat) msg.toJson(),
      ],
  };

  /// Désérialise un domaine.
  factory FunctionalDomain.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Domaine invalide.');
    final rawStackId = (raw['techStackId'] as String?)?.trim();
    final rawChat = raw['systemsServicesChat'];
    final rawVos = raw['valueObjects'];
    final rawVoChat = raw['valueObjectsChat'];
    final item = FunctionalDomain(
      id: raw['id'] as String? ?? '',
      domainCode: raw['domainCode'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      description: raw['description'] as String? ?? '',
      isActive: raw['isActive'] as bool? ?? true,
      techStackId: (rawStackId == null || rawStackId.isEmpty)
          ? null
          : rawStackId,
      contracts: raw.containsKey('contracts') ? DomainContracts.fromJson(raw['contracts']) : null,
      useCaseOrchestration: raw['useCaseOrchestration'] != null
          ? UseCaseOrchestrationSpec.fromJson(raw['useCaseOrchestration'])
          : null,
      systemsServicesChat: rawChat is List
          ? List<SpecChatMessage>.unmodifiable(<SpecChatMessage>[
              for (final msg in rawChat)
                if (msg is Map)
                  SpecChatMessage.fromJson(Map<String, Object?>.from(msg)),
            ])
          : const <SpecChatMessage>[],
      valueObjects: rawVos is List
          ? List<ValueObjectSpec>.unmodifiable(<ValueObjectSpec>[
              for (final vo in rawVos) ValueObjectSpec.fromJson(vo),
            ])
          : const <ValueObjectSpec>[],
      valueObjectsChat: rawVoChat is List
          ? List<SpecChatMessage>.unmodifiable(<SpecChatMessage>[
              for (final msg in rawVoChat)
                if (msg is Map)
                  SpecChatMessage.fromJson(Map<String, Object?>.from(msg)),
            ])
          : const <SpecChatMessage>[],
    );
    item.validate();
    return item;
  }
}

/// Environnement logique, librement nommé, rattaché à un domaine.
@immutable
class LogicalEnvironment {
  /// Crée un environnement logique.
  const LogicalEnvironment({
    required this.id,
    required this.domainId,
    required this.environmentCode,
    required this.name,
    this.description = '',
    this.status = LogicalEnvironmentStatus.active,
    this.isCloned = false,
    this.sourceEnvironmentId,
  });

  /// Identifiant technique.
  final String id;

  /// Identifiant du domaine parent.
  final String domainId;

  /// Code canonique en kebab-case, unique dans le domaine.
  final String environmentCode;

  /// Nom affiché.
  final String name;

  /// Description de l'usage de l'environnement.
  final String description;

  /// Statut de cycle de vie.
  final LogicalEnvironmentStatus status;

  /// Indique si l'environnement a été cloné.
  final bool isCloned;

  /// Identifiant de l'environnement source, le cas échéant.
  final String? sourceEnvironmentId;

  /// Vérifie les invariants de l'environnement.
  void validate() {
    if (id.trim().isEmpty || domainId.trim().isEmpty) {
      throw const FormatException('Identifiants d’environnement requis.');
    }
    _validateDomainCode(environmentCode, 'LogicalEnvironment.environmentCode');
    if (name.trim().length < 2 || name.trim().length > 255) {
      throw const FormatException('Le nom d’environnement doit contenir 2 à 255 caractères.');
    }
    if (description.length > 2000) {
      throw const FormatException('La description d’environnement dépasse 2000 caractères.');
    }
  }

  /// Copie modifiée.
  LogicalEnvironment copyWith({
    String? id,
    String? domainId,
    String? environmentCode,
    String? name,
    String? description,
    LogicalEnvironmentStatus? status,
    bool? isCloned,
    String? sourceEnvironmentId,
    bool clearSourceEnvironmentId = false,
  }) => LogicalEnvironment(
    id: id ?? this.id,
    domainId: domainId ?? this.domainId,
    environmentCode: environmentCode ?? this.environmentCode,
    name: name ?? this.name,
    description: description ?? this.description,
    status: status ?? this.status,
    isCloned: isCloned ?? this.isCloned,
    sourceEnvironmentId: clearSourceEnvironmentId
        ? null
        : sourceEnvironmentId ?? this.sourceEnvironmentId,
  );

  /// Sérialise l'environnement.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainId': domainId,
    'environmentCode': environmentCode,
    'name': name,
    'description': description,
    'status': status.name,
    'isCloned': isCloned,
    if (sourceEnvironmentId != null) 'sourceEnvironmentId': sourceEnvironmentId,
  };

  /// Désérialise un environnement.
  factory LogicalEnvironment.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Environnement invalide.');
    final item = LogicalEnvironment(
      id: raw['id'] as String? ?? '',
      domainId: raw['domainId'] as String? ?? '',
      environmentCode: raw['environmentCode'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      description: raw['description'] as String? ?? '',
      status: LogicalEnvironmentStatus.fromJson(raw['status'] ?? 'active'),
      isCloned: raw['isCloned'] as bool? ?? false,
      sourceEnvironmentId: raw['sourceEnvironmentId'] as String?,
    );
    item.validate();
    return item;
  }
}

/// Système ou service (application externe, front Web/Mobile, BFF, microservice
/// ou monolithe) rattaché à un unique domaine fonctionnel.
@immutable
class Microservice {
  /// Crée un système ou service rattaché à un domaine.
  const Microservice({
    required this.id,
    required this.domainId,
    required this.serviceCode,
    required this.name,
    this.kind = DomainSystemKind.microservice,
    this.description = '',
    this.isActive = true,
    this.techStackId,
    this.vendor = '',
  });

  /// Identifiant technique.
  final String id;

  /// Identifiant du domaine parent.
  final String domainId;

  /// Code technique en kebab-case.
  final String serviceCode;

  /// Nom affiché.
  final String name;

  /// Catégorie d'urbanisme ([DomainSystemKind.microservice] par défaut).
  final DomainSystemKind kind;

  /// Description de la responsabilité du système ou service.
  final String description;

  /// Indique si le système ou service est actif.
  final bool isActive;

  /// Identifiant optionnel du profil de stack technique ([BuildTechStackProfile.id]).
  final String? techStackId;

  /// Fournisseur, éditeur ou propriétaire tiers optionnel (ex. `Stripe`, `SendGrid`).
  final String vendor;

  /// Vérifie les invariants du système ou service.
  void validate() {
    if (id.trim().isEmpty || domainId.trim().isEmpty) {
      throw const FormatException('Identifiants de microservice requis.');
    }
    _validateDomainCode(serviceCode, 'Microservice.serviceCode');
    if (name.trim().length < 2 || name.trim().length > 255) {
      throw const FormatException('Le nom du microservice doit contenir 2 à 255 caractères.');
    }
    if (description.length > 2000) {
      throw const FormatException('La description du microservice dépasse 2000 caractères.');
    }
    if (vendor.length > 255) {
      throw const FormatException('Le fournisseur dépasse 255 caractères.');
    }
  }

  /// Copie modifiée.
  Microservice copyWith({
    String? id,
    String? domainId,
    String? serviceCode,
    String? name,
    DomainSystemKind? kind,
    String? description,
    bool? isActive,
    String? techStackId,
    bool clearTechStackId = false,
    String? vendor,
  }) => Microservice(
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

  /// Sérialise le système ou service.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainId': domainId,
    'serviceCode': serviceCode,
    'name': name,
    'kind': kind.name,
    'description': description,
    'isActive': isActive,
    if (techStackId != null && techStackId!.trim().isNotEmpty)
      'techStackId': techStackId,
    if (vendor.trim().isNotEmpty) 'vendor': vendor,
  };

  /// Désérialise un système ou service (rétrocompatible si `kind` est absent).
  factory Microservice.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Microservice invalide.');
    final rawStackId = (raw['techStackId'] as String?)?.trim();
    final item = Microservice(
      id: raw['id'] as String? ?? '',
      domainId: raw['domainId'] as String? ?? '',
      serviceCode: raw['serviceCode'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      kind: DomainSystemKind.fromJson(raw['kind']),
      description: raw['description'] as String? ?? '',
      isActive: raw['isActive'] as bool? ?? true,
      techStackId: (rawStackId == null || rawStackId.isEmpty)
          ? null
          : rawStackId,
      vendor: (raw['vendor'] as String? ?? '').trim(),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Microservice &&
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

/// Variable en clair ou secret chiffré, ciblé optionnellement sur un microservice.
@immutable
class ConfigurationEntry {
  /// Crée une entrée de configuration.
  const ConfigurationEntry({
    required this.id,
    required this.domainId,
    required this.environmentId,
    required this.configKey,
    required this.entryType,
    this.microserviceId,
    this.plainValue,
    this.encryptedValue,
    this.isInitialized = true,
    this.description = '',
  });

  /// Identifiant technique.
  final String id;

  /// Identifiant du domaine.
  final String domainId;

  /// Identifiant de l'environnement.
  final String environmentId;

  /// Identifiant du microservice ciblé, ou `null` pour la portée du domaine.
  final String? microserviceId;

  /// Clé au format UPPER_SNAKE_CASE.
  final String configKey;

  /// Classification en clair ou secrète.
  final ConfigurationEntryType entryType;

  /// Valeur en clair ; uniquement pour [ConfigurationEntryType.plainVariable].
  final String? plainValue;

  /// Ciphertext ; uniquement pour [ConfigurationEntryType.secret].
  final String? encryptedValue;

  /// Indique si la valeur a été initialisée.
  final bool isInitialized;

  /// Description facultative.
  final String description;

  /// Vérifie les invariants et l'étanchéité des valeurs.
  void validate() {
    if (id.trim().isEmpty ||
        domainId.trim().isEmpty ||
        environmentId.trim().isEmpty) {
      throw const FormatException('Identifiants de configuration requis.');
    }
    if (configKey.length < 2 ||
        configKey.length > 128 ||
        !_configKeyPattern.hasMatch(configKey)) {
      throw const FormatException(
        'La clé doit respecter UPPER_SNAKE_CASE (2 à 128 caractères).',
      );
    }
    if (description.length > 2000) {
      throw const FormatException('La description dépasse 2000 caractères.');
    }
    switch (entryType) {
      case ConfigurationEntryType.plainVariable:
        if (plainValue == null || encryptedValue != null || !isInitialized) {
          throw const FormatException(
            'Une variable en clair doit avoir plainValue uniquement et être initialisée.',
          );
        }
        if (plainValue!.length > 2000) {
          throw const FormatException('La valeur de configuration dépasse 2000 caractères.');
        }
      case ConfigurationEntryType.secret:
        if (plainValue != null ||
            (isInitialized && (encryptedValue == null || encryptedValue!.isEmpty)) ||
            (!isInitialized && encryptedValue != null)) {
          throw const FormatException(
            'Un secret doit être chiffré, ou non initialisé sans valeur.',
          );
        }
    }
  }

  /// Copie modifiée.
  ConfigurationEntry copyWith({
    String? id,
    String? domainId,
    String? environmentId,
    String? microserviceId,
    bool clearMicroserviceId = false,
    String? configKey,
    ConfigurationEntryType? entryType,
    String? plainValue,
    bool clearPlainValue = false,
    String? encryptedValue,
    bool clearEncryptedValue = false,
    bool? isInitialized,
    String? description,
  }) => ConfigurationEntry(
    id: id ?? this.id,
    domainId: domainId ?? this.domainId,
    environmentId: environmentId ?? this.environmentId,
    microserviceId: clearMicroserviceId
        ? null
        : microserviceId ?? this.microserviceId,
    configKey: configKey ?? this.configKey,
    entryType: entryType ?? this.entryType,
    plainValue: clearPlainValue ? null : plainValue ?? this.plainValue,
    encryptedValue: clearEncryptedValue
        ? null
        : encryptedValue ?? this.encryptedValue,
    isInitialized: isInitialized ?? this.isInitialized,
    description: description ?? this.description,
  );

  /// Sérialise l'entrée sans jamais inclure une valeur secrète en clair.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainId': domainId,
    'environmentId': environmentId,
    if (microserviceId != null) 'microserviceId': microserviceId,
    'configKey': configKey,
    'entryType': entryType.name,
    if (plainValue != null) 'plainValue': plainValue,
    if (encryptedValue != null) 'encryptedValue': encryptedValue,
    'isInitialized': isInitialized,
    'description': description,
  };

  /// Désérialise une entrée et vérifie son stockage.
  factory ConfigurationEntry.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Configuration invalide.');
    final item = ConfigurationEntry(
      id: raw['id'] as String? ?? '',
      domainId: raw['domainId'] as String? ?? '',
      environmentId: raw['environmentId'] as String? ?? '',
      microserviceId: raw['microserviceId'] as String?,
      configKey: raw['configKey'] as String? ?? '',
      entryType: ConfigurationEntryType.fromJson(raw['entryType']),
      plainValue: raw['plainValue'] as String?,
      encryptedValue: raw['encryptedValue'] as String?,
      isInitialized: raw['isInitialized'] as bool? ?? true,
      description: raw['description'] as String? ?? '',
    );
    item.validate();
    return item;
  }
}

/// Événement d'audit sans valeurs de configuration ni de secrets.
@immutable
class AuditLogEntry {
  /// Crée un événement d'audit.
  AuditLogEntry({
    required this.id,
    required DateTime recordedAt,
    required this.actorUsername,
    required this.domainId,
    required this.actionType,
    this.environmentId,
    this.clientIpAddress,
    this.userAgent,
    this.targetKey,
    this.isSecret = false,
    this.details = '',
  }) : recordedAt = recordedAt.toUtc();

  /// Identifiant technique.
  final String id;

  /// Horodatage UTC.
  final DateTime recordedAt;

  /// Acteur local déclaré par l'application.
  final String actorUsername;

  /// Adresse IP cliente si connue.
  final String? clientIpAddress;

  /// User-Agent si connu.
  final String? userAgent;

  /// Domaine concerné.
  final String domainId;

  /// Environnement concerné.
  final String? environmentId;

  /// Opération effectuée.
  final DomainAuditAction actionType;

  /// Clé de configuration concernée.
  final String? targetKey;

  /// Indique si l'opération portait sur un secret.
  final bool isSecret;

  /// Détails non sensibles.
  final String details;

  /// Vérifie les invariants et rejette les tentatives de journaliser une valeur.
  void validate() {
    if (id.trim().isEmpty ||
        actorUsername.trim().isEmpty ||
        domainId.trim().isEmpty) {
      throw const FormatException('Identifiants d’audit requis.');
    }
    if (details.length > 2000 ||
        (clientIpAddress?.length ?? 0) > 45 ||
        (userAgent?.length ?? 0) > 512) {
      throw const FormatException('Métadonnées d’audit trop longues.');
    }
  }

  /// Sérialise l'événement d'audit.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'actorUsername': actorUsername,
    if (clientIpAddress != null) 'clientIpAddress': clientIpAddress,
    if (userAgent != null) 'userAgent': userAgent,
    'domainId': domainId,
    if (environmentId != null) 'environmentId': environmentId,
    'actionType': actionType.name,
    if (targetKey != null) 'targetKey': targetKey,
    'isSecret': isSecret,
    'details': details,
  };

  /// Désérialise un événement d'audit.
  factory AuditLogEntry.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Événement d’audit invalide.');
    final date = DateTime.tryParse(raw['recordedAt'] as String? ?? '');
    if (date == null) throw const FormatException('Date d’audit invalide.');
    final item = AuditLogEntry(
      id: raw['id'] as String? ?? '',
      recordedAt: date,
      actorUsername: raw['actorUsername'] as String? ?? '',
      clientIpAddress: raw['clientIpAddress'] as String?,
      userAgent: raw['userAgent'] as String?,
      domainId: raw['domainId'] as String? ?? '',
      environmentId: raw['environmentId'] as String?,
      actionType: DomainAuditAction.fromJson(raw['actionType']),
      targetKey: raw['targetKey'] as String?,
      isSecret: raw['isSecret'] as bool? ?? false,
      details: raw['details'] as String? ?? '',
    );
    item.validate();
    return item;
  }
}

/// Référentiel complet et cohérent des domaines fonctionnels du workspace.
@immutable
class DomainCatalog {
  /// Crée un catalogue immuable.
  DomainCatalog({
    List<FunctionalDomain> domains = const <FunctionalDomain>[],
    List<LogicalEnvironment> environments = const <LogicalEnvironment>[],
    List<Microservice> microservices = const <Microservice>[],
    List<ConfigurationEntry> configurationEntries =
        const <ConfigurationEntry>[],
    List<AuditLogEntry> auditLog = const <AuditLogEntry>[],
    List<BuildTechStackProfile>? techStacks,
    List<ValueObjectSpec> sharedValueObjects = const <ValueObjectSpec>[],
    List<SpecChatMessage> sharedValueObjectsChat = const <SpecChatMessage>[],
    DateTime? updatedAt,
  }) : domains = List<FunctionalDomain>.unmodifiable(domains),
       environments = List<LogicalEnvironment>.unmodifiable(environments),
       microservices = List<Microservice>.unmodifiable(microservices),
       configurationEntries = List<ConfigurationEntry>.unmodifiable(
         configurationEntries,
       ),
       auditLog = List<AuditLogEntry>.unmodifiable(auditLog),
       techStacks = List<BuildTechStackProfile>.unmodifiable(
         techStacks ?? BuildTechStackProfile.defaults,
       ),
       sharedValueObjects = List<ValueObjectSpec>.unmodifiable(
         sharedValueObjects,
       ),
       sharedValueObjectsChat = List<SpecChatMessage>.unmodifiable(
         sharedValueObjectsChat,
       ),
       updatedAt = updatedAt?.toUtc();

  /// Catalogue vide.
  static final DomainCatalog empty = DomainCatalog();

  /// Domaines fonctionnels.
  final List<FunctionalDomain> domains;

  /// Environnements logiques.
  final List<LogicalEnvironment> environments;

  /// Microservices inventoriés.
  final List<Microservice> microservices;

  /// Variables et secrets.
  final List<ConfigurationEntry> configurationEntries;

  /// Journal append-only de l'application.
  final List<AuditLogEntry> auditLog;

  /// Profils de stacks techniques configurés dans le workspace pour les prompts Build.
  final List<BuildTechStackProfile> techStacks;

  /// Catalogue Shared Kernel des Value Objects partagés entre tous les domaines du workspace.
  final List<ValueObjectSpec> sharedValueObjects;

  /// Historique de conversation IA du Shared Kernel de Value Objects.
  final List<SpecChatMessage> sharedValueObjectsChat;

  /// Horodatage UTC de la dernière modification.
  final DateTime? updatedAt;

  /// Retourne tous les Value Objects visibles pour [domainId] avec leur portée
  /// effective : les VOs du domaine priment sur le Shared Kernel en cas d'homonyme
  /// de `technicalName`.
  List<ResolvedValueObject> resolvedValueObjectsForDomain(String? domainId) {
    final domain = domainId == null
        ? null
        : domains.where((d) => d.id == domainId).firstOrNull;
    final resolved = <ResolvedValueObject>[];
    final seenTechNames = <String>{};
    if (domain != null) {
      for (final vo in domain.valueObjects) {
        seenTechNames.add(vo.technicalName.toLowerCase());
        resolved.add(
          ResolvedValueObject(
            spec: vo,
            scope: ValueObjectScope.domain,
            domainId: domain.id,
          ),
        );
      }
    }
    for (final vo in sharedValueObjects) {
      if (seenTechNames.add(vo.technicalName.toLowerCase())) {
        resolved.add(
          ResolvedValueObject(spec: vo, scope: ValueObjectScope.shared),
        );
      }
    }
    return List<ResolvedValueObject>.unmodifiable(resolved);
  }

  /// Retourne la liste fusionnée des [ValueObjectSpec] utilisables dans [domainId].
  List<ValueObjectSpec> valueObjectsForDomain(String? domainId) => [
    for (final item in resolvedValueObjectsForDomain(domainId)) item.spec,
  ];

  /// Recherche un Value Object par [idOrTechnicalName] dans [domainId] (prioritaire)
  /// puis dans le Shared Kernel.
  ResolvedValueObject? findValueObject(
    String idOrTechnicalName, {
    String? domainId,
  }) {
    final needle = idOrTechnicalName.trim();
    if (needle.isEmpty) return null;
    final lower = needle.toLowerCase();
    final visible = resolvedValueObjectsForDomain(domainId);
    for (final item in visible) {
      if (item.spec.id == needle) return item;
    }
    for (final item in visible) {
      if (item.spec.technicalName.toLowerCase() == lower) return item;
    }
    // Repli : un VO du Shared Kernel masqué par un homonyme de domaine reste
    // résoluble par son ID exact.
    for (final vo in sharedValueObjects) {
      if (vo.id == needle) {
        return ResolvedValueObject(spec: vo, scope: ValueObjectScope.shared);
      }
    }
    return null;
  }

  /// Retourne le profil de stack technique associé à [domain], ou `null` si aucun.
  BuildTechStackProfile? techStackForDomain(FunctionalDomain domain) {
    final stackId = domain.techStackId;
    if (stackId == null || stackId.isEmpty) return null;
    return techStacks.where((stack) => stack.id == stackId).firstOrNull;
  }

  /// Retourne le profil de stack technique associé à [service], ou `null` si aucun.
  BuildTechStackProfile? techStackForService(Microservice service) {
    final stackId = service.techStackId;
    if (stackId == null || stackId.isEmpty) return null;
    return techStacks.where((stack) => stack.id == stackId).firstOrNull;
  }

  /// Valide l'intégrité référentielle et l'unicité de toutes les entités.
  void validate() {
    _validateUniqueIds(domains.map((e) => e.id), 'domaine');
    _validateUniqueIds(environments.map((e) => e.id), 'environnement');
    _validateUniqueIds(microservices.map((e) => e.id), 'microservice');
    _validateUniqueIds(configurationEntries.map((e) => e.id), 'configuration');
    _validateUniqueIds(auditLog.map((e) => e.id), 'audit');
    _validateUniqueIds(techStacks.map((e) => e.id), 'stack technique');
    _validateUniqueIds(
      sharedValueObjects.map((e) => e.id),
      'Value Object partagé',
    );
    _validateUniqueBy(
      sharedValueObjects,
      (v) => v.technicalName.toLowerCase(),
      'Nom technique de Value Object partagé dupliqué',
    );
    for (final vo in sharedValueObjects) {
      vo.validate();
    }
    ValueObjectSpec.validateNoCycles(sharedValueObjects);

    _validateUniqueBy(
      techStacks,
      (s) => s.code,
      'Code de stack technique dupliqué',
    );
    for (final stack in techStacks) {
      stack.validate();
    }
    final techStackIds = techStacks.map((s) => s.id).toSet();

    final domainIds = domains.map((e) => e.id).toSet();
    final environmentById = {for (final e in environments) e.id: e};
    final serviceById = {for (final service in microservices) service.id: service};
    _validateUniqueBy(
      domains,
      (d) => d.domainCode,
      'Code de domaine dupliqué',
    );
    for (final domain in domains) {
      domain.validate();
      if (domain.valueObjects.isNotEmpty) {
        ValueObjectSpec.validateNoCycles([
          ...domain.valueObjects,
          ...sharedValueObjects,
        ]);
      }
      if (domain.techStackId != null &&
          !techStackIds.contains(domain.techStackId)) {
        throw FormatException(
          'Stack technique introuvable pour le domaine ${domain.domainCode} : ${domain.techStackId}',
        );
      }
    }

    final environmentCodes = <String>{};
    for (final environment in environments) {
      environment.validate();
      if (!domainIds.contains(environment.domainId)) {
        throw FormatException('Domaine introuvable pour ${environment.environmentCode}.');
      }
      if (!environmentCodes.add('${environment.domainId}\u0000${environment.environmentCode}')) {
        throw FormatException('Code d’environnement dupliqué : ${environment.environmentCode}');
      }
      if (environment.sourceEnvironmentId != null &&
          !environmentById.containsKey(environment.sourceEnvironmentId)) {
        throw FormatException('Environnement source introuvable : ${environment.sourceEnvironmentId}');
      }
    }

    final serviceCodes = <String>{};
    for (final service in microservices) {
      service.validate();
      if (!domainIds.contains(service.domainId)) {
        throw FormatException('Domaine introuvable pour ${service.serviceCode}.');
      }
      if (!serviceCodes.add('${service.domainId}\u0000${service.serviceCode}')) {
        throw FormatException('Code de microservice dupliqué : ${service.serviceCode}');
      }
      if (service.techStackId != null &&
          !techStackIds.contains(service.techStackId)) {
        throw FormatException(
          'Stack technique introuvable pour le système ${service.serviceCode} : ${service.techStackId}',
        );
      }
    }

    final configKeys = <String>{};
    for (final entry in configurationEntries) {
      entry.validate();
      final environment = environmentById[entry.environmentId];
      if (environment == null ||
          environment.domainId != entry.domainId ||
          !domainIds.contains(entry.domainId)) {
        throw FormatException('Domaine ou environnement incohérent pour ${entry.configKey}.');
      }
      if (entry.microserviceId != null &&
          serviceById[entry.microserviceId]?.domainId != entry.domainId) {
        throw FormatException('Microservice invalide pour ${entry.configKey}.');
      }
      final key = '${entry.domainId}\u0000${entry.environmentId}\u0000${entry.microserviceId ?? ''}\u0000${entry.configKey}';
      if (!configKeys.add(key)) {
        throw FormatException('Clé de configuration dupliquée : ${entry.configKey}');
      }
    }

    for (final event in auditLog) {
      event.validate();
    }
  }

  static void _validateUniqueIds(Iterable<String> ids, String entity) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.trim().isEmpty || !seen.add(id)) {
        throw FormatException('Identifiant $entity vide ou dupliqué : $id');
      }
    }
  }

  static void _validateUniqueBy<T>(
    Iterable<T> items,
    String Function(T) keyOf,
    String message,
  ) {
    final seen = <String>{};
    for (final item in items) {
      if (!seen.add(keyOf(item))) throw FormatException(message);
    }
  }

  /// Copie modifiée.
  DomainCatalog copyWith({
    List<FunctionalDomain>? domains,
    List<LogicalEnvironment>? environments,
    List<Microservice>? microservices,
    List<ConfigurationEntry>? configurationEntries,
    List<AuditLogEntry>? auditLog,
    List<BuildTechStackProfile>? techStacks,
    List<ValueObjectSpec>? sharedValueObjects,
    List<SpecChatMessage>? sharedValueObjectsChat,
    DateTime? updatedAt,
  }) => DomainCatalog(
    domains: domains ?? this.domains,
    environments: environments ?? this.environments,
    microservices: microservices ?? this.microservices,
    configurationEntries: configurationEntries ?? this.configurationEntries,
    auditLog: auditLog ?? this.auditLog,
    techStacks: techStacks ?? this.techStacks,
    sharedValueObjects: sharedValueObjects ?? this.sharedValueObjects,
    sharedValueObjectsChat:
        sharedValueObjectsChat ?? this.sharedValueObjectsChat,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Sérialise le catalogue complet.
  Map<String, Object?> toJson() => <String, Object?>{
    'domains': [for (final item in domains) item.toJson()],
    'environments': [for (final item in environments) item.toJson()],
    'microservices': [for (final item in microservices) item.toJson()],
    'configurationEntries': [
      for (final item in configurationEntries) item.toJson(),
    ],
    'auditLog': [for (final item in auditLog) item.toJson()],
    'techStacks': [for (final item in techStacks) item.toJson()],
    if (sharedValueObjects.isNotEmpty)
      'sharedValueObjects': [
        for (final item in sharedValueObjects) item.toJson(),
      ],
    if (sharedValueObjectsChat.isNotEmpty)
      'sharedValueObjectsChat': [
        for (final msg in sharedValueObjectsChat) msg.toJson(),
      ],
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Désérialise et valide le catalogue.
  factory DomainCatalog.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Catalogue de domaines invalide.');
    final date = raw['updatedAt'] is String
        ? DateTime.tryParse(raw['updatedAt'] as String)
        : null;
    final parsedTechStacks = raw.containsKey('techStacks') && raw['techStacks'] is List
        ? <BuildTechStackProfile>[
            for (final item in raw['techStacks'] as List)
              BuildTechStackProfile.fromJson(item),
          ]
        : null;
    final rawSharedVos = raw['sharedValueObjects'];
    final rawSharedVoChat = raw['sharedValueObjectsChat'];
    final catalog = DomainCatalog(
      domains: [
        if (raw['domains'] is List)
          for (final item in raw['domains'] as List)
            FunctionalDomain.fromJson(item),
      ],
      environments: [
        if (raw['environments'] is List)
          for (final item in raw['environments'] as List)
            LogicalEnvironment.fromJson(item),
      ],
      microservices: [
        if (raw['microservices'] is List)
          for (final item in raw['microservices'] as List)
            Microservice.fromJson(item),
      ],
      configurationEntries: [
        if (raw['configurationEntries'] is List)
          for (final item in raw['configurationEntries'] as List)
            ConfigurationEntry.fromJson(item),
      ],
      auditLog: [
        if (raw['auditLog'] is List)
          for (final item in raw['auditLog'] as List) AuditLogEntry.fromJson(item),
      ],
      techStacks: parsedTechStacks,
      sharedValueObjects: rawSharedVos is List
          ? <ValueObjectSpec>[
              for (final item in rawSharedVos) ValueObjectSpec.fromJson(item),
            ]
          : const <ValueObjectSpec>[],
      sharedValueObjectsChat: rawSharedVoChat is List
          ? <SpecChatMessage>[
              for (final msg in rawSharedVoChat)
                if (msg is Map)
                  SpecChatMessage.fromJson(Map<String, Object?>.from(msg)),
            ]
          : const <SpecChatMessage>[],
      updatedAt: date,
    );
    catalog.validate();
    return catalog;
  }
}
