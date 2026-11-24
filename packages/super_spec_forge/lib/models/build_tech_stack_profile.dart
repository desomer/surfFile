/// Profil immuable de stack technique et structure de dossiers injecté en fin
/// de chaque prompt IA généré par l'onglet Build ([BuildTechStackProfile]).
library;

import 'package:flutter/foundation.dart';

final RegExp _stackCodePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// Profil configurable d'une stack technique (langage, framework, outils,
/// arborescence cible en Architecture Hexagonale et extensions optionnelles
/// par rôle de prompt).
@immutable
class BuildTechStackProfile {
  /// Crée un profil de stack technique immuable.
  const BuildTechStackProfile({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
    this.technicalStack = '',
    this.folderStructure = '',
    this.implementationFolderStructure = '',
    this.unitTestFolderStructure = '',
    this.persistenceFolderStructure = '',
    this.implementationExtension = '',
    this.unitTestExtension = '',
    this.persistenceExtension = '',
  });

  /// Identifiant stable du profil par défaut TypeScript / NestJS.
  static const String defaultTsNestJsId = 'stack_ts_nestjs';

  /// Profil prédéfini TypeScript / NestJS en Architecture Hexagonale.
  static const BuildTechStackProfile tsNestJsPreset = BuildTechStackProfile(
    id: defaultTsNestJsId,
    code: 'ts-nestjs',
    name: 'TypeScript / NestJS',
    description:
        'Backend TypeScript 5 / Node.js LTS avec NestJS, persistance Prisma/TypeORM et tests Vitest/Jest.',
    technicalStack:
        '- Langage : TypeScript 5 (mode `strict: true`, `noUncheckedIndexedAccess: true`)\n'
        '- Runtime & Framework : Node.js 22 LTS · NestJS 10+ (injection de dépendances par tokens d’interface)\n'
        '- Persistance : Prisma ORM ou TypeORM côté `infrastructure/persistence/` (jamais importé dans `domain/`)\n'
        '- Validation & Typage : Value Objects stricts côté domaine, DTO/schémas dédiés aux bordures\n'
        '- Tests unitaires : Vitest ou Jest (fakes en mémoire sans base de données ni container NestJS)',
    implementationFolderStructure:
        'src/\n'
        '└── {{domain}}/\n'
        '    ├── domain/\n'
        '    │   ├── model/                 # Agrégats, Entités, Value Objects\n'
        '    │   ├── events/                # Événements du domaine\n'
        '    │   ├── errors/                # Exceptions métier typées\n'
        '    │   ├── services/              # Policy Services purs\n'
        '    │   └── ports/\n'
        '    │       └── outbound/          # Interfaces Driven Ports (Repositories, Bus)\n'
        '    └── application/\n'
        '        ├── ports/\n'
        '        │   └── inbound/           # Interfaces Driving Ports (Use Cases)\n'
        '        ├── use-cases/             # Commands / Queries & Handlers CQRS\n'
        '        └── sagas/                 # Coordinateurs / Handlers de Sagas',
    unitTestFolderStructure:
        'test/\n'
        '└── {{domain}}/\n'
        '    ├── domain/                    # Tests unitaires purs de la couche Domain (*.spec.ts)\n'
        '    └── application/               # Tests unitaires Use Cases & Sagas avec fakes (*.spec.ts)',
    persistenceFolderStructure:
        'src/\n'
        '└── {{domain}}/\n'
        '    ├── domain/\n'
        '    │   └── ports/\n'
        '    │       └── outbound/          # Interface Repository (Driven Port)\n'
        '    └── infrastructure/\n'
        '        ├── persistence/\n'
        '        │   ├── entities/          # Modèles ORM / Prisma\n'
        '        │   ├── mappers/           # Mappers Domain <-> Infrastructure\n'
        '        │   └── repositories/      # Adaptateurs implémentant les Driven Ports\n'
        '        └── nest/                  # Modules NestJS & bindings DI\n'
        'test/\n'
        '└── {{domain}}/\n'
        '    └── infrastructure/            # Tests mappers & contrats de persistance',
    implementationExtension:
        '- Utilise des classes/types TypeScript stricts (`readonly`, constructeurs privés + méthodes `static create(...)` / `reconstitute(...)`).\n'
        '- Aucun décorateur NestJS (`@Injectable`, `@Inject`) dans `domain/` ; réserve l’injection DI et les symboles/tokens aux adaptateurs et modules `infrastructure/nest/`.',
    unitTestExtension:
        '- Écris des specs `*.spec.ts` rapides exécutées en mémoire sans démarrer `Test.createTestingModule` pour la couche `domain/` ni pour les handlers `application/`.\n'
        '- Implémente des fakes en mémoire typés (ex. `InMemory<Aggregate>Repository`) plutôt que des mocks fragiles.',
    persistenceExtension:
        '- Sépare strictement le modèle ORM (`*.orm-entity.ts` ou modèle Prisma) de l’agrégat `domain/model/`, via un mapper statique `toDomain()` / `toPersistence()`.\n'
        '- Enregistre le binding `{ provide: REPOSITORY_TOKEN, useClass: ...RepositoryAdapter }` dans le module NestJS du domaine.',
  );

  /// Catalogue initial des stacks prédéfinies fournies par défaut.
  static const List<BuildTechStackProfile> defaults = <BuildTechStackProfile>[
    tsNestJsPreset,
  ];

  /// Identifiant technique unique.
  final String id;

  /// Code canonique en `kebab-case` (injecté dans l'en-tête YAML `generation.stack` et `tags`).
  final String code;

  /// Nom lisible de la stack (ex. `TypeScript / NestJS`).
  final String name;

  /// Résumé court de la stack.
  final String description;

  /// Description détaillée de la stack technique (langage, frameworks, libs, conventions).
  final String technicalStack;

  /// Arborescence cible commune (utilisée en repli si celle d'un rôle est vide).
  final String folderStructure;

  /// Arborescence cible dédiée aux prompts de rôle *Implémentation* (`{{domain}}`).
  final String implementationFolderStructure;

  /// Arborescence cible dédiée aux prompts de rôle *Tests unitaires* (`{{domain}}`).
  final String unitTestFolderStructure;

  /// Arborescence cible dédiée aux prompts de rôle *Persistance* (`{{domain}}`).
  final String persistenceFolderStructure;

  /// Extension optionnelle ajoutée uniquement aux prompts de rôle *Implémentation*.
  final String implementationExtension;

  /// Extension optionnelle ajoutée uniquement aux prompts de rôle *Tests unitaires*.
  final String unitTestExtension;

  /// Extension optionnelle ajoutée uniquement aux prompts de rôle *Persistance*.
  final String persistenceExtension;

  /// Indique si ce profil contient au moins un bloc textuel d'extension à injecter.
  bool hasExtensionContentForRole(String roleName) =>
      technicalStack.trim().isNotEmpty ||
      rawFolderStructureForRole(roleName).isNotEmpty ||
      roleExtensionForName(roleName).isNotEmpty;

  /// Retourne l'arborescence brute dédiée à [roleName], ou [folderStructure] en repli.
  String rawFolderStructureForRole(String roleName) {
    final roleFolders = switch (roleName) {
      'implementation' => implementationFolderStructure.trim(),
      'unitTest' => unitTestFolderStructure.trim(),
      'persistence' => persistenceFolderStructure.trim(),
      _ => '',
    };
    return roleFolders.isNotEmpty ? roleFolders : folderStructure.trim();
  }

  /// Retourne l'extension spécifique au nom de rôle (`implementation`, `unitTest`, `persistence`).
  String roleExtensionForName(String roleName) => switch (roleName) {
    'implementation' => implementationExtension.trim(),
    'unitTest' => unitTestExtension.trim(),
    'persistence' => persistenceExtension.trim(),
    _ => '',
  };

  /// Résout l'arborescence cible en remplaçant `{{domain}}` par [domainCode].
  ///
  /// Lorsque [roleName] est fourni, utilise la structure dédiée à ce rôle
  /// (ou [folderStructure] en repli).
  String resolveFolderStructure(String domainCode, {String? roleName}) {
    final cleanCode = domainCode.trim().isEmpty ? 'domain' : domainCode.trim();
    final raw = roleName != null
        ? rawFolderStructureForRole(roleName)
        : (folderStructure.trim().isNotEmpty
              ? folderStructure.trim()
              : implementationFolderStructure.trim());
    return raw.replaceAll('{{domain}}', cleanCode);
  }

  /// Vérifie les invariants du profil de stack.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BuildTechStackProfile.id requis.');
    }
    if (code.length < 2 || code.length > 64 || !_stackCodePattern.hasMatch(code)) {
      throw const FormatException(
        'Le code de stack doit être en kebab-case (2 à 64 caractères).',
      );
    }
    if (name.trim().length < 2 || name.trim().length > 120) {
      throw const FormatException(
        'Le nom de la stack doit contenir 2 à 120 caractères.',
      );
    }
    if (description.length > 1000) {
      throw const FormatException(
        'La description de la stack dépasse 1000 caractères.',
      );
    }
    if (technicalStack.length > 8000 ||
        folderStructure.length > 8000 ||
        implementationFolderStructure.length > 8000 ||
        unitTestFolderStructure.length > 8000 ||
        persistenceFolderStructure.length > 8000 ||
        implementationExtension.length > 8000 ||
        unitTestExtension.length > 8000 ||
        persistenceExtension.length > 8000) {
      throw const FormatException(
        'Une section d’extension de stack dépasse 8000 caractères.',
      );
    }
  }

  /// Copie modifiée.
  BuildTechStackProfile copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? technicalStack,
    String? folderStructure,
    String? implementationFolderStructure,
    String? unitTestFolderStructure,
    String? persistenceFolderStructure,
    String? implementationExtension,
    String? unitTestExtension,
    String? persistenceExtension,
  }) => BuildTechStackProfile(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
    technicalStack: technicalStack ?? this.technicalStack,
    folderStructure: folderStructure ?? this.folderStructure,
    implementationFolderStructure:
        implementationFolderStructure ?? this.implementationFolderStructure,
    unitTestFolderStructure:
        unitTestFolderStructure ?? this.unitTestFolderStructure,
    persistenceFolderStructure:
        persistenceFolderStructure ?? this.persistenceFolderStructure,
    implementationExtension:
        implementationExtension ?? this.implementationExtension,
    unitTestExtension: unitTestExtension ?? this.unitTestExtension,
    persistenceExtension: persistenceExtension ?? this.persistenceExtension,
  );

  /// Sérialise le profil en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    if (technicalStack.isNotEmpty) 'technicalStack': technicalStack,
    if (folderStructure.isNotEmpty) 'folderStructure': folderStructure,
    if (implementationFolderStructure.isNotEmpty)
      'implementationFolderStructure': implementationFolderStructure,
    if (unitTestFolderStructure.isNotEmpty)
      'unitTestFolderStructure': unitTestFolderStructure,
    if (persistenceFolderStructure.isNotEmpty)
      'persistenceFolderStructure': persistenceFolderStructure,
    if (implementationExtension.isNotEmpty)
      'implementationExtension': implementationExtension,
    if (unitTestExtension.isNotEmpty) 'unitTestExtension': unitTestExtension,
    if (persistenceExtension.isNotEmpty)
      'persistenceExtension': persistenceExtension,
  };

  /// Désérialise un profil depuis JSON.
  factory BuildTechStackProfile.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Profil de stack technique invalide.');
    }
    final profile = BuildTechStackProfile(
      id: (raw['id'] as String?)?.trim() ?? '',
      code: (raw['code'] as String?)?.trim() ?? '',
      name: (raw['name'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      technicalStack: (raw['technicalStack'] as String?) ?? '',
      folderStructure: (raw['folderStructure'] as String?) ?? '',
      implementationFolderStructure:
          (raw['implementationFolderStructure'] as String?) ?? '',
      unitTestFolderStructure:
          (raw['unitTestFolderStructure'] as String?) ?? '',
      persistenceFolderStructure:
          (raw['persistenceFolderStructure'] as String?) ?? '',
      implementationExtension:
          (raw['implementationExtension'] as String?) ?? '',
      unitTestExtension: (raw['unitTestExtension'] as String?) ?? '',
      persistenceExtension: (raw['persistenceExtension'] as String?) ?? '',
    );
    profile.validate();
    return profile;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildTechStackProfile &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.description == description &&
          other.technicalStack == technicalStack &&
          other.folderStructure == folderStructure &&
          other.implementationFolderStructure ==
              implementationFolderStructure &&
          other.unitTestFolderStructure == unitTestFolderStructure &&
          other.persistenceFolderStructure == persistenceFolderStructure &&
          other.implementationExtension == implementationExtension &&
          other.unitTestExtension == unitTestExtension &&
          other.persistenceExtension == persistenceExtension;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    description,
    technicalStack,
    folderStructure,
    implementationFolderStructure,
    unitTestFolderStructure,
    persistenceFolderStructure,
    implementationExtension,
    unitTestExtension,
    persistenceExtension,
  );
}
