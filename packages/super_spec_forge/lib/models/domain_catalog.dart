/// Modèles immuables du catalogue de domaines, environnements, microservices,
/// configurations et événements d'audit ([DomainCatalog]).
library;

import 'package:flutter/foundation.dart';

import 'domain_contracts.dart';

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
    this.contracts,
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

  /// Catalogue de modèles et contrats, absent pour un domaine encore vierge.
  final DomainContracts? contracts;

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
  }

  /// Copie modifiée.
  FunctionalDomain copyWith({
    String? id,
    String? domainCode,
    String? name,
    String? description,
    bool? isActive,
    DomainContracts? contracts,
  }) => FunctionalDomain(
    id: id ?? this.id,
    domainCode: domainCode ?? this.domainCode,
    name: name ?? this.name,
    description: description ?? this.description,
    isActive: isActive ?? this.isActive,
    contracts: contracts ?? this.contracts,
  );

  /// Sérialise le domaine.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainCode': domainCode,
    'name': name,
    'description': description,
    'isActive': isActive,
    if (contracts != null) 'contracts': contracts!.toJson(),
  };

  /// Désérialise un domaine.
  factory FunctionalDomain.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Domaine invalide.');
    final item = FunctionalDomain(
      id: raw['id'] as String? ?? '',
      domainCode: raw['domainCode'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      description: raw['description'] as String? ?? '',
      isActive: raw['isActive'] as bool? ?? true,
      contracts: raw.containsKey('contracts') ? DomainContracts.fromJson(raw['contracts']) : null,
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

/// Microservice rattaché à un unique domaine fonctionnel.
@immutable
class Microservice {
  /// Crée un microservice.
  const Microservice({
    required this.id,
    required this.domainId,
    required this.serviceCode,
    required this.name,
    this.description = '',
    this.isActive = true,
  });

  /// Identifiant technique.
  final String id;

  /// Identifiant du domaine parent.
  final String domainId;

  /// Code technique en kebab-case.
  final String serviceCode;

  /// Nom affiché.
  final String name;

  /// Description de la responsabilité du service.
  final String description;

  /// Indique si le service est actif.
  final bool isActive;

  /// Vérifie les invariants du microservice.
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
  }

  /// Copie modifiée.
  Microservice copyWith({
    String? id,
    String? domainId,
    String? serviceCode,
    String? name,
    String? description,
    bool? isActive,
  }) => Microservice(
    id: id ?? this.id,
    domainId: domainId ?? this.domainId,
    serviceCode: serviceCode ?? this.serviceCode,
    name: name ?? this.name,
    description: description ?? this.description,
    isActive: isActive ?? this.isActive,
  );

  /// Sérialise le microservice.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainId': domainId,
    'serviceCode': serviceCode,
    'name': name,
    'description': description,
    'isActive': isActive,
  };

  /// Désérialise un microservice.
  factory Microservice.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Microservice invalide.');
    final item = Microservice(
      id: raw['id'] as String? ?? '',
      domainId: raw['domainId'] as String? ?? '',
      serviceCode: raw['serviceCode'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      description: raw['description'] as String? ?? '',
      isActive: raw['isActive'] as bool? ?? true,
    );
    item.validate();
    return item;
  }
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
    DateTime? updatedAt,
  }) : domains = List<FunctionalDomain>.unmodifiable(domains),
       environments = List<LogicalEnvironment>.unmodifiable(environments),
       microservices = List<Microservice>.unmodifiable(microservices),
       configurationEntries = List<ConfigurationEntry>.unmodifiable(
         configurationEntries,
       ),
       auditLog = List<AuditLogEntry>.unmodifiable(auditLog),
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

  /// Horodatage UTC de la dernière modification.
  final DateTime? updatedAt;

  /// Valide l'intégrité référentielle et l'unicité de toutes les entités.
  void validate() {
    _validateUniqueIds(domains.map((e) => e.id), 'domaine');
    _validateUniqueIds(environments.map((e) => e.id), 'environnement');
    _validateUniqueIds(microservices.map((e) => e.id), 'microservice');
    _validateUniqueIds(configurationEntries.map((e) => e.id), 'configuration');
    _validateUniqueIds(auditLog.map((e) => e.id), 'audit');

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
    DateTime? updatedAt,
  }) => DomainCatalog(
    domains: domains ?? this.domains,
    environments: environments ?? this.environments,
    microservices: microservices ?? this.microservices,
    configurationEntries: configurationEntries ?? this.configurationEntries,
    auditLog: auditLog ?? this.auditLog,
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
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Désérialise et valide le catalogue.
  factory DomainCatalog.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Catalogue de domaines invalide.');
    final date = raw['updatedAt'] is String
        ? DateTime.tryParse(raw['updatedAt'] as String)
        : null;
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
      updatedAt: date,
    );
    catalog.validate();
    return catalog;
  }
}
