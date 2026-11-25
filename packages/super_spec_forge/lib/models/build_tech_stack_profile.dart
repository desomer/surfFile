/// Profil immuable de stack technique et structure de dossiers injecté en fin
/// de chaque prompt IA généré par l'onglet Build ([BuildTechStackProfile]).
library;

import 'package:flutter/foundation.dart';

final RegExp _stackCodePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// Partie architecturale configurable dans un profil de stack technique.
enum BuildTechStackSection {
  /// Couche Domain pure (agrégats, entités, value objects, services métier, ports).
  domain(label: 'Domain', slug: 'domain'),

  /// Couche Application (Use Cases CQRS et Sagas).
  useCaseSaga(label: 'UseCase / Saga', slug: 'usecase-saga'),

  /// Adaptateurs sortants hors persistance (messaging, clients externes, logging).
  outbound(label: 'Outbound', slug: 'outbound'),

  /// Points d'entrée entrants (contrôleurs REST/GraphQL, CLI, consumers).
  inbound(label: 'Inbound', slug: 'inbound'),

  /// Persistance (schémas, mappers, repositories et read-models).
  persistence(label: 'Persistance', slug: 'persistence');

  const BuildTechStackSection({required this.label, required this.slug});

  /// Libellé affiché dans les onglets, filtres et titres de prompts.
  final String label;

  /// Segment `kebab-case` utilisé dans les métadonnées YAML.
  final String slug;
}

/// Sous-rôle de chaque partie architecturale dans un profil de stack technique.
enum BuildTechStackSubRole {
  /// Implémentation du code de production de la partie ciblée.
  implementation(label: 'Implémentation', slug: 'implementation'),

  /// Suite de tests unitaires associée à la partie ciblée.
  unitTest(label: 'Test unitaire', slug: 'unit-test');

  const BuildTechStackSubRole({required this.label, required this.slug});

  /// Libellé affiché dans les sous-onglets et badges.
  final String label;

  /// Segment `kebab-case` utilisé dans les métadonnées YAML.
  final String slug;
}

/// Profil configurable d'une stack technique (langage, framework, outils,
/// arborescences cibles en Architecture Hexagonale, extensions par partie et
/// sous-rôle, et consignes globales de documentation IA).
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
    this.aiDocumentation = '',
    this.domainImplementationFolderStructure = '',
    this.domainUnitTestFolderStructure = '',
    this.useCaseSagaImplementationFolderStructure = '',
    this.useCaseSagaUnitTestFolderStructure = '',
    this.outboundImplementationFolderStructure = '',
    this.outboundUnitTestFolderStructure = '',
    this.inboundImplementationFolderStructure = '',
    this.inboundUnitTestFolderStructure = '',
    this.persistenceImplementationFolderStructure = '',
    this.persistenceUnitTestFolderStructure = '',
    this.domainImplementationExtension = '',
    this.domainUnitTestExtension = '',
    this.useCaseSagaImplementationExtension = '',
    this.useCaseSagaUnitTestExtension = '',
    this.outboundImplementationExtension = '',
    this.outboundUnitTestExtension = '',
    this.inboundImplementationExtension = '',
    this.inboundUnitTestExtension = '',
    this.persistenceImplementationExtension = '',
    this.persistenceUnitTestExtension = '',
  });

  /// Identifiant stable du profil par défaut TypeScript / NestJS.
  static const String defaultTsNestJsId = 'stack_ts_nestjs';

  /// Profil prédéfini TypeScript / NestJS en Architecture Hexagonale.
  static const BuildTechStackProfile tsNestJsPreset = BuildTechStackProfile(
    id: defaultTsNestJsId,
    code: 'ts-nestjs',
    name: 'TypeScript / NestJS',
    description: 'Backend TypeScript 5 / Node.js LTS avec NestJS, domaine pur DDD (Neverthrow), persistance MongoDB/Mongoose et tests Vitest/Jest.',
    technicalStack:
        '- Langage : TypeScript 5 (mode `strict: true`, `noUncheckedIndexedAccess: true`)\n'
        '- Runtime & Framework : Node.js 22 LTS · NestJS 10+ (uniquement en infrastructure, aucun décorateur dans `core/`)\n'
        '- Erreurs & Logs domaine : Neverthrow (`Result` / `ok` / `err`) pour les erreurs métier · port Logger (Pino)\n'
        '- Persistance : MongoDB via Mongoose côté `infrastructure/{{domain}}/outbound/persistence/` (jamais importé dans `core/`)\n'
        '- Validation & Typage : Value Objects stricts côté domaine, DTO/schémas dédiés aux bordures\n'
        '- Tests unitaires : Vitest ou Jest (fakes en mémoire sans base de données ni container NestJS)',
    aiDocumentation:
        '## Mise à jour obligatoire de la documentation IA du projet\n'
        'À chaque génération ou modification, tu DOIS créer (s’ils n’existent pas) ou mettre à jour à la racine du projet :\n'
        '```text\n'
        '├── README.md\n'
        '├── CLAUDE.md\n'
        '├── AGENTS.md\n'
        '└── docs/\n'
        '    ├── architecture.md\n'
        '    ├── conventions.md\n'
        '    └── business-rules.md\n'
        '```\n'
        '- `README.md` : Vue d’ensemble du projet, des modules disponibles, prérequis et commandes de lancement/test.\n'
        '- `CLAUDE.md` & `AGENTS.md` : Instructions de contexte et garde-fous pour les agents IA (isolation stricte du Domaine en TypeScript pur, interdiction d’importer NestJS/Mongoose dans `core/`, commandes de build/test, pièges à éviter, pointeurs vers `docs/`).\n'
        '- `docs/architecture.md` : Cartographie des couches et du module `{{domain}}` (Aggregates, Entities, Value Objects, Domain Services, Domain Events, Use Cases, Ports Inbound/Outbound, Schémas MongoDB, Index, Repositories et Tokens).\n'
        '- `docs/conventions.md` : Conventions techniques appliquées (factories `create()` / `reconstitute()`, `Neverthrow`, immutabilité, Mongoose `.lean()`, verrouillage optimiste `__v`, traduction des codes d’erreur Mongo `11000`/`112`/`121`/`50`, en-têtes JSDoc IA en français).\n'
        '- `docs/business-rules.md` : Catalogue exhaustif des règles et invariants métier, transitions d’état, contraintes d’unicité et erreurs domaine du module `{{domain}}`.',
    domainImplementationFolderStructure:
        'src/\n'
        '└── core/                # Domaine pur (DDD)\n'
        '    └── {{domain}}/\n'
        '        ├── ports/\n'
        '        │   ├── logging/        # logging ports\n'
        '        │   ├── repositories/   # repository ports for aggregates\n'
        '        │   ├── read-model/     # lecture complexe multi aggregates optimisée (uniquement si nécessaire)\n'
        '        │   └── messaging/      # messaging ports (e.g., event bus, message queue)\n'
        '        └── domain/\n'
        '            ├── models/\n'
        '            │   ├── aggregates/      # root objects of the domain model, encapsulating entities and value objects\n'
        '            │   ├── entities/        # object single domain entities (representing a single concept in the domain)\n'
        '            │   ├── composites/      # object composed of multiple entities or value objects\n'
        '            │   └── value-objects/   # objets atomiques de valeur immuables représentant des concepts métier\n'
        '            ├── services/          # services métier stateless\n'
        '            ├── events/            # domain events\n'
        '            └── errors/            # domain errors',
    domainUnitTestFolderStructure: 'identique au domaine principal\n',
    useCaseSagaImplementationFolderStructure:
        'src/\n'
        '└── core/\n'
        '    └── {{domain}}/\n'
        '        ├── ports/\n'
        '        │   ├── gateways/            # role: services externes\n'
        '        │   ├── messaging/           # role: publication/consommation de messages\n'
        '        │   ├── storage/             # role: stockage objet (bucket, file)\n'
        '        │   ├── logging/             # role: journalisation\n'
        '        │   ├── repositories/\n'
        '        │   └── read-model/          # lecture complexe multi aggregates optimisée (uniquement si nécessaire)\n'
        '        └── application/             # role: orchestration des cas d’usage\n'
        '            ├── commands/            # role: intentions d’écriture\n'
        '            ├── queries/             # role: intentions de lecture\n'
        '            ├── sagas/               # role: processus longs ou distribués\n'
        '            ├── services/            # role: orchestration applicative\n'
        '            ├── events/              # role: événements applicatifs\n'
        '            └── errors/              # gestion des erreurs applicatives',
    useCaseSagaUnitTestFolderStructure: 'identique au domaine principal\n',
    outboundImplementationFolderStructure:
        'src/\n'
        '└── infrastructure/\n'
        '    └── {{domain}}/\n'
        '        ├── {{domain}}.module.ts\n'
        '        └── outbound/\n'
        '            ├── messaging/         # Adaptateurs Event Bus / Message Queue\n'
        '            ├── logging/           # Adaptateur Logger (Pino)\n'
        '            └── clients/           # Adaptateurs HTTP / APIs externes',
    outboundUnitTestFolderStructure: 'identique au domaine principal\n',
    inboundImplementationFolderStructure:
        'src/\n'
        '└── infrastructure/\n'
        '    └── {{domain}}/\n'
        '        └── inbound/\n'
        '            ├── http/              # Contrôleurs NestJS, DTOs & mapping Result -> HTTP\n'
        '            ├── messaging/         # Consumers / Listeners d’événements\n'
        '            └── guards/            # Guards & pipes d’entrée',
    inboundUnitTestFolderStructure:
        'test/\n'
        '└── {{domain}}/\n'
        '    └── infrastructure/\n'
        '        └── inbound/               # Tests unitaires des contrôleurs, DTOs & consumers (*.spec.ts)',
    persistenceImplementationFolderStructure:
        'src/\n'
        '└── infrastructure/\n'
        '    └── {{domain}}/\n'
        '        ├── {{domain}}.module.ts\n'
        '        └── outbound/\n'
        '            └── persistence/\n'
        '                ├── repositories/   # Implémentations MongoDB des ports du domaine\n'
        '                ├── read-model/     # Lecture complexe multi-agrégats optimisée (si port existe)\n'
        '                ├── schemas/        # Schémas Mongoose (@Schema())\n'
        '                └── mappers/        # Mappers purs Domain <-> Persistence',
    persistenceUnitTestFolderStructure: 'identique au domaine principal\n',
    domainImplementationExtension:
        '# Contraintes techniques :\n'
        '- Aucun décorateur NestJS.\n'
        '- Aucun import lié à un framework (sauf Neverthrow si nécessaire).\n'
        '- Code 100% TypeScript pur (`readonly`, constructeurs privés + méthodes `static create(...)` / `reconstitute(...)`).\n'
        '- Génère ou réutilise les classes suivantes :\n'
        '  - Aggregates (racines d’agrégats)\n'
        '  - Entities (immutables si possible)\n'
        '  - Value Objects (avec validations internes) uniquement si isVO = Val.Obj\n'
        '  - Domain Services (logique métier pure)\n'
        '  - Interfaces de repositories (ports côté domaine)\n'
        '- Respect strict des invariants métier.\n'
        '- Pas de DTO, pas de mapping, pas de persistence.\n'
        '- Pas de logique technique (HTTP, DB, queues…).\n'
        '- Un port Logger (pour pino) pour log métier.\n'
        '- Utilise Neverthrow pour les erreurs métier.\n'
        '- Mettre des commentaires en français dans le code (JSDoc et explications des règles/invariants métier).\n'
        '\n'
        '# Rappel :\n'
        '1. Un agrégat :\n'
        '  - ne peut pas appeler une méthode d’un autre agrégat\n'
        '  - ne peut pas charger un autre agrégat\n'
        '  - ne peut pas vérifier une règle qui dépend d’un autre agrégat\n'
        '  - ne peut pas accéder à un repository d’un autre agrégat\n'
        '  - ne peut pas modifier un autre agrégat\n'
        '  - il peut référencer l’ID d’un autre agrégat\n'
        '  - publier un événement que d’autres agrégats écouteront\n'
        '  - laisser un Use Case orchestrer la collaboration\n'
        '  - laisser un Domain Service appliquer une règle inter-agrégats\n'
        '\n'
        '2. Le dossier read-model :\n'
        '  - Lecture optimisée pour les cas d’usage\n'
        '  - Contient des projections de données pour les cas d’usage\n'
        '\n'
        '3. Le dossier services :\n'
        '  - Logique métier qui ne rentre pas dans un Aggregate (calculs complexes, règles métier transverses, validation métier multi-aggregates, politiques métier pricing/eligibility/scoring)\n'
        '  - Services métier stateless (ex. `PasswordPolicyService`, `PricingService`, `EligibilityService`, `UserDomainService`)\n'
        '  - Règles métier réutilisables (calcul de TVA, calcul de réduction, règles de sécurité/validation métier)\n'
        '  - Opérations métier qui ne doivent pas être dans un handler (un handler = orchestration, pas logique métier)\n'
        '\n'
        '# MODE STRICT - CONTRAINTES BLOQUANTES\n'
        '\n'
        'Tu dois appliquer ces règles AVANT de coder.\n'
        'Si une seule règle ne peut pas être respectée, STOP, n’écris aucun fichier, et demande validation.\n'
        '\n'
        '## 1) Arborescence obligatoire (hard requirement)\n'
        'Tous les fichiers créés/modifiés DOIVENT être uniquement sous `src/core/{{domain}}/` (ports `logging/`, `repositories/`, `read-model/`, `messaging/` et `domain/` : `models/aggregates/`, `models/entities/`, `models/composites/`, `models/value-objects/`, `services/`, `events/`, `errors/`), ainsi que la documentation IA (`README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/architecture.md`, `docs/conventions.md`, `docs/business-rules.md`).\n'
        'Interdiction absolue de créer/modifier en dehors de cette arborescence.\n'
        '\n'
        '## 2) Politique d’exécution\n'
        '- Étape 1 : proposer le plan + liste exacte des fichiers ciblés.\n'
        '- Étape 2 : attendre ma validation explicite « GO ».\n'
        '- Étape 3 : coder.\n'
        '- Étape 4 : vérifier build/tests.\n'
        '- Étape 5 : afficher checklist de conformité.\n'
        '- Étape 6 : archiver les prompts UNIQUEMENT si checklist = 100%.\n'
        '\n'
        '## 3) Checklist de conformité obligatoire\n'
        '- [ ] Aucun fichier hors arborescence imposée.\n'
        '- [ ] Domaine en TypeScript pur (pas de décorateurs NestJS, pas de framework).\n'
        '- [ ] Ports/domain/services/events/errors présents selon besoin.\n'
        '- [ ] Invariants métier implémentés.\n'
        '- [ ] Build OK.\n'
        '- [ ] Diff final listé fichier par fichier.\n'
        '\n'
        '## 4) Règle d’ambiguïté\n'
        'Si une contrainte est ambiguë ou contradictoire avec le code existant :\n'
        '- STOP\n'
        '- Pose 1 question précise\n'
        '- N’écris rien tant que je n’ai pas répondu.\n'
        '\n'
        '## 5) Règle d’archivage\n'
        'Ne déplace les prompts en archive qu’après :\n'
        '- build OK\n'
        '- checklist complète validée\n'
        '- mon message « ARCHIVE OK ».\n'
        '\n'
        '## 6) En-têtes de fichiers obligatoires (JSDoc IA en français par dossier autorisé)\n'
        'Chaque fichier généré DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@folder`, `@role`, `@boundaries`, `@invariants` et `@ai-modification-guide`, adapté à son dossier :\n'
        '- `domain/models/aggregates/` : `@layer` Domain (Aggregate Root) · `@role` Racine d’agrégat garantissant la cohérence transactionnelle, le cycle de vie et les invariants métier · `@boundaries` TypeScript pur + Neverthrow, interdiction d’appeler un autre agrégat, un repository ou tout framework (NestJS, Mongoose) · `@invariants` lister explicitement tous les invariants métier garantis · `@ai-modification-guide` aucune mutation par setter public, passer par des méthodes métier retournant `Result`, mettre à jour `create()`, `reconstitute()`, le schéma/mapper de persistance et les tests `.spec.ts` si un attribut est ajouté.\n'
        '- `domain/models/entities/` et `domain/models/composites/` : `@layer` Domain (Entity | Composite) · `@role` Entité ou objet composite interne à un agrégat, identifié par son ID ou sa structure métier · `@boundaries` TypeScript pur, manipulé uniquement via sa racine d’agrégat · `@ai-modification-guide` toute modification d’état doit préserver les invariants de l’agrégat parent.\n'
        '- `domain/models/value-objects/` : `@layer` Domain (Value Object) · `@role` Objet de valeur immuable défini par ses attributs, auto-validé à la construction via `create()` · `@boundaries` TypeScript pur + Neverthrow, immuable (`Object.freeze` / `readonly`), égalité structurelle (`equals`) · `@invariants` lister les règles de format/bornes validées dans `create()` · `@ai-modification-guide` ne jamais contourner la factory `create()`.\n'
        '- `domain/services/` : `@layer` Domain (Domain Service) · `@role` Service métier stateless portant une règle métier transverse ou un calcul impliquant plusieurs agrégats/entités · `@boundaries` TypeScript pur, stateless, ne remplace pas un Handler applicatif · `@ai-modification-guide` garder les méthodes pures et déterministes ; toute orchestration va dans `application/`.\n'
        '- `domain/events/` : `@layer` Domain (Domain Event) · `@role` Fait métier immuable survenu dans un agrégat (nommé au passé, ex. `PriceUpdatedDomainEvent`) · `@boundaries` TypeScript pur, uniquement primitives/IDs métier et date d’occurrence · `@ai-modification-guide` vérifier les handlers et mappers consommateurs en cas d’évolution du payload.\n'
        '- `domain/errors/` : `@layer` Domain (Domain Error) · `@role` Violation explicite d’une règle ou d’un invariant métier avec code unique et message clair · `@boundaries` TypeScript pur, aucun statut HTTP · `@ai-modification-guide` référencer toute nouvelle erreur dans les types de retour `Result<..., DomainError>`.\n'
        '- `ports/repositories/`, `ports/read-model/`, `ports/messaging/`, `ports/logging/` : `@layer` Domain Port (Driven Port) · `@role` Contrat d’interface abstrait exprimant un besoin du domaine envers l’infrastructure · `@boundaries` Interfaces TypeScript pures + types du domaine + `Neverthrow`, aucun type technique externe · `@ai-modification-guide` tout changement de contrat impose de mettre à jour l’implémentation dans `infrastructure/{{domain}}/outbound/` et les mocks de test.',
    domainUnitTestExtension:
        '- Écris des specs `*.spec.ts` rapides exécutées en mémoire sans démarrer `Test.createTestingModule` ni aucune base de données.\n'
        '- Vérifie les invariants métier, les factories `create()` / `reconstitute()`, les résultats `Neverthrow` (`isOk()` / `isErr()`) et les événements émis par l’agrégat.',
    useCaseSagaImplementationExtension:
        '# MODE STRICT - CONTRAINTES BLOQUANTES\n'
        '\n'
        'Tu dois appliquer ces règles AVANT de coder.\n'
        'Si une seule règle ne peut pas être respectée, STOP, n’écris aucun fichier, et demande validation.\n'
        '\n'
        '## 1) Arborescence obligatoire (hard requirement)\n'
        'Tous les fichiers créés/modifiés DOIVENT être uniquement sous :\n'
        '- `src/core/{{domain}}/ports/` (`gateways/`, `messaging/`, `storage/`, `logging/`, `repositories/`, `read-model/`)\n'
        '- `src/core/{{domain}}/application/` (`commands/`, `queries/`, `sagas/`, `services/`, `events/`, `errors/`)\n'
        'Ainsi que la documentation IA (`README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/architecture.md`, `docs/conventions.md`, `docs/business-rules.md`).\n'
        'Interdiction absolue de créer/modifier en dehors de cette arborescence.\n'
        '\n'
        'Détails attendus pour chaque dossier :\n'
        '1. `commands/` : Générer une classe par action métier qui modifie l’état (simple, immuable, sans logique — ex. `CreateUser.command.ts`, `PlaceOrder.command.ts`).\n'
        '2. `queries/` : Générer une classe par action de lecture (simple, immuable, sans logique — ex. `GetUserById.query.ts`, `ListOrders.query.ts`).\n'
        '3. Handlers (`<command>.handler.ts`, `<query>.handler.ts`) : Générer un handler par command et par query ; injecter les ports (repositories, services externes), orchestrer le domaine, garantir les invariants applicatifs sans logique technique ; méthode obligatoire : `execute()`.\n'
        '4. `services/` (Application Services — rôle : orchestration applicative) :\n'
        '   - Factoriser une orchestration applicative synchrone complexe ou partagée entre plusieurs Command Handlers et coordonner plusieurs Aggregates, Domain Services et Ports au sein d’une **seule transaction atomique** via `UnitOfWorkPort.runInTransaction()`.\n'
        '   - ≠ **Domain Service** (`domain/services/`) : logique/calcul métier pur en mémoire sans I/O ; l’**Application Service** (`application/services/`) fait de l’orchestration I/O.\n'
        '   - ≠ **Command Handler** (`application/commands/*.handler.ts`) : 1 Command = 1 Handler, délègue à l’Application Service lorsqu’un workflow synchrone coordonne plusieurs agrégats en transaction ou est réutilisé.\n'
        '   - ≠ **Saga** (`application/sagas/`) : l’Application Service est court, synchrone et transactionnel (ACID via `UnitOfWork`) ; la Saga est longue, asynchrone, pilotée par événements avec compensations.\n'
        '   - Exemple de signature/flux (`OrderCheckoutApplicationService`) : lecture via ports I/O → appel `DomainService` / `Aggregate` en mémoire → persistance multi-agrégats dans `this.unitOfWork.runInTransaction(async () => ...)` → publication de l’événement applicatif et log après commit.\n'
        '5. `sagas/` : Orchestration longue, asynchrone, multi-étapes, multi-événements, multi-agrégats, avec écoute d’événements, déclenchement de plusieurs commands, gestion des échecs et compensations (rembourser, annuler, rollback métier).\n'
        '6. `events/` : Événements applicatifs déclenchés après un use case (ex. `UserRegisteredEvent`, `OrderPlacedEvent`), distincts des Domain Events.\n'
        '7. `ports/` : Interfaces nécessaires à l’infrastructure (gateways externes, read models, et services techniques `ApplicationEventPublisherPort.publish()`, `CommandDispatcherPort.dispatch()`, `UnitOfWorkPort.runInTransaction()`), utilisées par les handlers et services applicatifs.\n'
        '8. `errors/` : Exceptions applicatives spécifiques à chaque workflow/use case (ex. `UserAlreadyExistsException`, `OrderNotFoundException`).\n'
        '\n'
        '## 2) Politique d’exécution\n'
        '- Étape 1 : proposer le plan + liste exacte des fichiers ciblés.\n'
        '- Étape 2 : attendre ma validation explicite « GO ».\n'
        '- Étape 3 : coder.\n'
        '- Étape 4 : vérifier build/tests.\n'
        '- Étape 5 : afficher checklist de conformité.\n'
        '- Étape 6 : archiver les prompts UNIQUEMENT si checklist = 100%.\n'
        '\n'
        '## 3) Checklist de conformité obligatoire\n'
        '- [ ] Aucun fichier hors arborescence imposée.\n'
        '- [ ] Domaine en TypeScript pur (pas de décorateurs NestJS, pas de framework).\n'
        '- [ ] Ports/domain/services/events/errors présents selon besoin.\n'
        '- [ ] Invariants métier implémentés.\n'
        '- [ ] Build OK.\n'
        '- [ ] Diff final listé fichier par fichier.\n'
        '\n'
        '## 4) Règle d’ambiguïté\n'
        'Si une contrainte est ambiguë ou contradictoire avec le code existant :\n'
        '- STOP\n'
        '- Pose 1 question précise\n'
        '- N’écris rien tant que je n’ai pas répondu.\n'
        '\n'
        '## 5) Règle d’archivage\n'
        'Ne déplace les prompts en archive qu’après :\n'
        '- build OK\n'
        '- checklist complète validée\n'
        '- mon message « ARCHIVE OK ».\n'
        '\n'
        '## 6) Contexte de code source :\n'
        '- Le domaine est déjà défini.\n'
        '\n'
        '## 7) Contraintes techniques :\n'
        '- Aucun décorateur NestJS.\n'
        '- Aucun import NestJS.\n'
        '- Aucun accès direct à la base de données.\n'
        '- Aucun DTO NestJS.\n'
        '- Aucun mapping technique.\n'
        '- Code 100% TypeScript pur.\n'
        '- Respect strict des invariants métier du domaine.\n'
        '- Gère les erreurs avec `Neverthrow`.\n'
        '- Les handlers doivent être testables sans framework (sauf `Neverthrow`).\n'
        '- Mettre des commentaires en français dans le code (JSDoc et explications des étapes/règles métier).\n'
        '\n'
        '## 8) En-têtes de fichiers obligatoires (JSDoc IA en français par dossier autorisé)\n'
        'Chaque fichier généré DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@folder`, `@role`, `@boundaries`, `@collaborators` et `@ai-modification-guide`, adapté à son dossier :\n'
        '- `application/commands/` et `application/queries/` (`.command.ts` / `.query.ts`) : `@layer` Application (CQRS - Command | Query) · `@role` Porte l’intention métier immuable (écriture pour Command, lecture pour Query) et ses données primitives d’entrée · `@boundaries` Pur TypeScript, immuable (`readonly`), aucune logique métier, aucun décorateur, aucune dépendance technique · `@ai-modification-guide` si un attribut est ajouté/modifié, mettre à jour le Handler associé, le Mapper de la couche Interface (`inbound/rest/v1/mappers/`) et les tests unitaires.\n'
        '- `application/commands/` et `application/queries/` (`.handler.ts`) : `@layer` Application (CQRS - Command Handler | Query Handler) · `@role` Orchestre le cas d’usage (charge les agrégats/read-models via les ports, exécute la logique du domaine, persiste et publie les événements applicatifs) · `@boundaries` Dépend uniquement du Domaine (`core/{{domain}}/domain/*`), des Ports (`core/{{domain}}/ports/*`) et de `Neverthrow` ; interdiction d’importer NestJS, Mongoose, Zod ou des DTOs HTTP · `@collaborators` lister la Command/Query traitée, les Ports injectés et les Events/Errors produits · `@ai-modification-guide` ne jamais ajouter de règle métier pure ici (la déléguer à l’Aggregate ou à un Domain Service), toujours retourner un `Result` / `ResultAsync` (`Neverthrow`).\n'
        '- `application/services/` : `@layer` Application (Application Service) · `@role` Orchestration synchrone complexe coordonnant plusieurs agrégats ou cas d’usage dans une même transaction (`UnitOfWorkPort`) · `@boundaries` Pur TypeScript + Ports + Domaine + `Neverthrow`, zéro logique métier pure, zéro dépendance framework/DB · `@ai-modification-guide` vérifier la cohérence transactionnelle via `UnitOfWorkPort` lors de l’ajout d’appels à de nouveaux ports.\n'
        '- `application/sagas/` : `@layer` Application (Saga / Process Manager) · `@role` Orchestration longue et asynchrone multi-étapes/multi-événements avec gestion explicite des compensations (rollback métier) · `@boundaries` Pur TypeScript + Ports (`CommandDispatcherPort`, `ApplicationEventPublisherPort`) · `@ai-modification-guide` toute nouvelle étape ajoutée à la Saga DOIT définir son action de compensation, son idempotence et sa gestion d’erreur.\n'
        '- `application/events/` : `@layer` Application (Application Event) · `@role` Notifie les autres modules/adaptateurs qu’un cas d’usage s’est terminé avec succès (distinct des Domain Events internes) · `@boundaries` Structure de données immuable en TypeScript pur · `@ai-modification-guide` en cas de modification du payload, vérifier les Subscribers (`interface/`) et les Publishers/Mappers Avro (`infrastructure/{{domain}}/outbound/messaging/`).\n'
        '- `application/errors/` : `@layer` Application (Application Error) · `@role` Représente une erreur d’orchestration ou de cas d’usage (ex. ressource introuvable, conflit applicatif, non autorisé) typée avec code et message · `@boundaries` Pur TypeScript, sans code HTTP (le mapping vers HTTP 400/404/409/422 se fait dans la couche Interface) · `@ai-modification-guide` si une nouvelle erreur est ajoutée, mettre à jour le type d’union d’erreurs du Handler et sa traduction HTTP dans le Controller (`interface/`).\n'
        '- `ports/repositories/`, `ports/read-model/`, `ports/gateways/`, `ports/messaging/`, `ports/storage/`, `ports/logging/` : `@layer` Application / Domain Port (Driven Port) · `@role` Contrat d’interface abstrait définissant les besoins du cœur métier envers l’infrastructure externe · `@boundaries` Uniquement des interfaces TypeScript, types du Domaine et `Neverthrow`, aucun type issu de Mongoose, SDK tiers, AWS/GCS, Kafka ou NestJS · `@ai-modification-guide` toute modification de signature dans ce port oblige à mettre à jour l’adaptateur correspondant dans `infrastructure/{{domain}}/outbound/` ainsi que les mocks/fakes des tests `.spec.ts`.',
    useCaseSagaUnitTestExtension:
        '- Écris des specs `*.spec.ts` rapides exécutées en mémoire avec des fakes typés (`InMemory<Aggregate>Repository`, faux bus d’événements, faux logger Pino) sans démarrer `Test.createTestingModule`.\n'
        '- Vérifie chaque scénario `Given / When / Then`, la publication des événements, l’idempotence et les compensations de Saga.',
    outboundImplementationExtension:
        '- Implémente les ports sortants hors persistance (`core/{{domain}}/ports/messaging/`, `logging/`, services externes) dans `src/infrastructure/{{domain}}/outbound/` via classes `@Injectable()` NestJS.\n'
        '- Utilise le port Logger (Pino) et `Neverthrow` pour traduire les pannes techniques (réseau, broker, timeout) en erreurs typées sans jamais exposer de logique métier.\n'
        '- Enregistre et exporte chaque binding `{ provide: PORT_TOKEN, useClass: ...Adapter }` dans `{{domain}}.module.ts`.',
    outboundUnitTestExtension:
        '- Teste unitairement chaque adaptateur sortant (`messaging`, `logging`, clients externes) en isolant le SDK/client tiers par doublure déterministe.\n'
        '- Vérifie le mapping des payloads sortants, la journalisation et la traduction des erreurs techniques vers `Result` (`Neverthrow`).',
    inboundImplementationExtension:
        '- Implémente les points d’entrée NestJS dans `src/infrastructure/{{domain}}/inbound/` (contrôleurs REST, DTOs de validation d’entrée, consumers/listeners, guards).\n'
        '- Traduis les `Result` (`Neverthrow`) retournés par les Use Cases en codes de statut HTTP / réponses adaptées sans mettre de logique métier dans le contrôleur.\n'
        '- Documente les routes/DTOs et déclare les contrôleurs/consumers dans `{{domain}}.module.ts`.',
    inboundUnitTestExtension:
        '- Teste unitairement les contrôleurs, la validation des DTOs d’entrée, les guards et les consumers en remplaçant les Use Cases par des doublures en mémoire.\n'
        '- Vérifie le mapping `Input -> Command/Query` ainsi que la conversion des erreurs `Neverthrow` en statuts HTTP attendus (400, 404, 409, 422…).',
    persistenceImplementationExtension:
        '## Contexte de code source :\n'
        '- Le domaine est déjà défini.\n'
        '- Les ports de repository sont dans : `core/{{domain}}/ports/repositories`\n'
        '- Le repository MongoDB doit implémenter ces ports.\n'
        '- N’ajoute pas de contrôle déjà présent dans le domaine, mais tu peux ajouter des validations techniques si nécessaire.\n'
        '\n'
        '## Contraintes techniques :\n'
        '- Utiliser NestJS uniquement dans l’infrastructure.\n'
        '- Utiliser MongoDB via Mongoose.\n'
        '- Respecter strictement les interfaces du domaine.\n'
        '- Ne jamais mettre de logique métier dans l’infrastructure.\n'
        '- Mapper correctement :\n'
        '  - Domain → Persistence\n'
        '  - Persistence → Domain\n'
        '- Ne jamais retourner un domaine invalide (respect des invariants métier).\n'
        '- Le repository doit être une classe NestJS annotée avec `@Injectable()`.\n'
        '- Le module doit fournir :\n'
        '  - Schema MongoDB\n'
        '  - Model Mongoose\n'
        '  - Repository implémentant le port\n'
        '  - Mappers\n'
        '  - Module NestJS pour assembler le tout\n'
        '- Génère ou réutilise les classes si elles existent déjà dans le domaine.\n'
        '- Un port Logger (pour pino) pour le debug log de la base de données.\n'
        '- Utilise Neverthrow pour les erreurs.\n'
        '- Mettre des commentaires en français dans le code généré (JSDoc et commentaires explicatifs).\n'
        '\n'
        'CONTRAT TECHNIQUE ET RÈGLES STRUCTURALES :\n'
        '\n'
        '1. SCHÉMA MONGOOSE & INDEXATION :\n'
        '   - Définis un schéma Mongoose (`@Schema()`) dans son propre fichier.\n'
        '   - Utilise une `string` pour le champ `_id` (pas d’ObjectId native Mongo, les IDs sont gérés côté Domaine sous forme d’UUID).\n'
        '   - Configure le schéma avec `timestamps: true` et active `versionKey: \'__v\'` (pour le verrouillage optimiste).\n'
        '   - DÉCLARATION DES INDEX ET UNICITÉ :\n'
        '     - Champs uniques simples : Déclare `@Prop({ unique: true, index: true })`.\n'
        '     - Champs uniques optionnels/nullables : Utilise `sparse: true` ou `partialFilterExpression` pour éviter les conflits sur les valeurs nulles/absentes.\n'
        '     - Index composés (multi-champs) : Déclare-les au niveau du schéma via `Schema.index({ field1: 1, field2: 1 }, { unique: true })`.\n'
        '     - Ajoute les index de recherche simples non-uniques (`index: true`) sur les clés étrangères/IDs de rattachement.\n'
        '\n'
        '2. MAPPER (Domain <-> Mongo) :\n'
        '   - Crée un Mapper statique pur (ex: `[Entity]Mapper`).\n'
        '   - Méthode `toDomain(raw: [Entity]MongoEntity): [Entity]` : Reconstitue l’entité métier.\n'
        '   - Méthode `toPersistence(domain: [Entity]): [Entity]MongoEntity` : Extrait les données primitives du Domaine (y compris l’extraction des Value Objects).\n'
        '\n'
        '3. REPOSITORY MONGOOSE (Adaptateur) :\n'
        '   - Implémente le Port (Interface) défini par le Domaine.\n'
        '   - Injecte le Modèle Mongoose via `@InjectModel()`.\n'
        '   - Utilise OBLIGATOIREMENT `.lean()` sur toutes les requêtes en lecture (ex: `find`, `findById`) pour éviter la fuite du prototype Mongoose.\n'
        '   - Gère le verrouillage optimiste lors des mises à jour (`updateOne` avec vérification du `__v` et `\$inc: { __v: 1 }`).\n'
        '   - GESTION FINE DE L’UNICITÉ ET CODE 11000 :\n'
        '     - Intercepte les erreurs avec `error.code === 11000` (Duplicate Key).\n'
        '     - Inspecte `error.keyPattern` ou `error.keyValue` pour identifier PRÉCISÉMENT quel champ ou combinaison de champs a provoqué le doublon.\n'
        '     - Lève l’exception Domaine spécifique associée à ce champ (ex: si le champ en conflit est `email` -> lever `EmailAlreadyInUseException`).\n'
        '     - Gère les conflits de concurrence d’update (ex: `matchedCount === 0`) -> lever `ConcurrencyException`.\n'
        '   - GESTION DES AUTRES CODES D’ERREUR MONGODB :\n'
        '     - Code 121 — `DocumentValidationFailure` : Les données envoyées ne respectent pas le JSON Schema Validation défini sur la collection MongoDB -> Traduction Métier : `InvalidDataException` ou `DomainValidationException`.\n'
        '     - Code 112 — `WriteConflict` : Deux transactions concurrentes ont modifié le même document sous WiredTiger (transactions ACID `session.withTransaction()`) -> Traduction Métier : `ConcurrencyException` ou `RetryableOperationException`.\n'
        '     - Code 50 — `ExceededTimeLimit` / `MaxTimeMSExpired` : Dépassement de `maxTimeMS` -> Traduction Métier : `TimeoutException` ou `RetryableOperationException`.\n'
        '\n'
        '4. INJECTION DE DÉPENDANCE NESTJS :\n'
        '   - Fournis le snippet du module NestJS (`[Entity]InfrastructureModule`) montrant le provider avec le token du Port (`{ provide: PORT_TOKEN, useClass: RepositoryImpl }`).\n'
        '\n'
        '# MODE STRICT - CONTRAINTES BLOQUANTES\n'
        '\n'
        'Tu dois appliquer ces règles AVANT de coder.\n'
        'Si une seule règle ne peut pas être respectée, STOP, n’écris aucun fichier, et demande validation.\n'
        '\n'
        '## 1) Arborescence obligatoire (hard requirement)\n'
        'Tous les fichiers créés/modifiés DOIVENT être uniquement sous :\n'
        '- `src/infrastructure/{{domain}}/outbound/persistence/repositories/`\n'
        '- `src/infrastructure/{{domain}}/outbound/persistence/read-model/` (lecture complexe multi aggregates optimisée si port existe)\n'
        '- `src/infrastructure/{{domain}}/outbound/persistence/schemas/`\n'
        '- `src/infrastructure/{{domain}}/outbound/persistence/mappers/`\n'
        '- `src/infrastructure/{{domain}}/{{domain}}.module.ts`\n'
        'Ainsi que la documentation IA (`README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/architecture.md`, `docs/conventions.md`, `docs/business-rules.md`).\n'
        'Interdiction absolue de créer/modifier en dehors de cette arborescence.\n'
        '\n'
        '## 2) Politique d’exécution\n'
        '- Étape 1 : proposer le plan + liste exacte des fichiers ciblés.\n'
        '- Étape 2 : attendre ma validation explicite « GO ».\n'
        '- Étape 3 : coder.\n'
        '- Étape 4 : vérifier build/tests.\n'
        '- Étape 5 : afficher checklist de conformité.\n'
        '- Étape 6 : archiver les prompts UNIQUEMENT si checklist = 100%.\n'
        '\n'
        '## 3) Checklist de conformité obligatoire\n'
        '- [ ] Aucun fichier hors arborescence imposée.\n'
        '- [ ] Schema MongoDB\n'
        '- [ ] Repository MongoDB (implémentation du port)\n'
        '- [ ] Mappers (domain ↔ persistence)\n'
        '- [ ] Module NestJS\n'
        '- [ ] Build OK.\n'
        '- [ ] Diff final listé fichier par fichier.\n'
        '\n'
        '## 4) Règle d’ambiguïté\n'
        'Si une contrainte est ambiguë ou contradictoire avec le code existant :\n'
        '- STOP\n'
        '- Pose 1 question précise\n'
        '- N’écris rien tant que je n’ai pas répondu.\n'
        '\n'
        '## 5) Règle d’archivage\n'
        'Ne déplace les prompts en archive qu’après :\n'
        '- build OK\n'
        '- checklist complète validée\n'
        '- mon message « ARCHIVE OK ».\n'
        '\n'
        '## 6) En-têtes de fichiers obligatoires (JSDoc IA en français par dossier autorisé)\n'
        'Chaque fichier généré DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@folder`, `@role`, `@boundaries`, `@collaborators` et `@ai-modification-guide`, adapté à son dossier :\n'
        '- `outbound/persistence/schemas/` : `@layer` Infrastructure - Outbound Persistence Schema (MongoDB / Mongoose) · `@role` Définition du schéma Mongoose (`@Schema()`), des types de stockage (`_id: string` UUID, `timestamps`, `versionKey: \'__v\'`) et des index (simples, composés, sparse) · `@boundaries` Décorateurs `@nestjs/mongoose` et types de persistance uniquement, aucune méthode ou règle métier · `@ai-modification-guide` si un champ indexé/unique est ajouté, documenter l’index ici et ajouter la traduction de l’erreur Mongo `11000` correspondante dans le Repository.\n'
        '- `outbound/persistence/mappers/` : `@layer` Infrastructure - Outbound Persistence Mapper · `@role` Conversion pure bidirectionnelle entre l’entité/agrégat du Domaine (`toDomain`) et le document plat MongoDB (`toPersistence`) · `@boundaries` Classe/fonctions statiques pures, sans dépendance NestJS ni appels base de données, utilise `reconstitute()` côté Domaine · `@ai-modification-guide` tout nouvel attribut du Domaine persisté DOIT être mappé à la fois dans `toDomain()` et `toPersistence()`.\n'
        '- `outbound/persistence/repositories/` : `@layer` Infrastructure - Outbound Persistence Repository (MongoDB) · `@role` Implémente le Port de Repository du domaine (`core/{{domain}}/ports/repositories/`), exécute les requêtes Mongoose (`.lean()`), gère le verrouillage optimiste (`__v`) et traduit les codes d’erreur MongoDB (`11000`, `112`, `121`, `50`) en erreurs métier via `Neverthrow` · `@boundaries` `@Injectable()` NestJS, `@InjectModel()` Mongoose, Mapper de persistance, Port et types du Domaine, Logger, Neverthrow, ne jamais retourner un Document Mongoose hors du repository · `@ai-modification-guide` toujours conserver `.lean()` sur les lectures et vérifier le verrouillage optimiste sur les mises à jour d’agrégats.\n'
        '- `outbound/persistence/read-model/` : `@layer` Infrastructure - Outbound Persistence Read-Model · `@role` Implémente les ports de lecture optimisée / projections multi-agrégats (`core/{{domain}}/ports/read-model/`) pour les Queries CQRS · `@boundaries` Requêtes de lecture seule (`.lean()`, pipelines d’agrégation Mongo), aucune écriture ni mutation d’état · `@ai-modification-guide` optimiser les projections (`select`) et vérifier que les champs filtrés/triés sont couverts par les index définis dans `schemas/`.\n'
        '- `{{domain}}.module.ts` (`src/infrastructure/{{domain}}/{{domain}}.module.ts`) : `@layer` Infrastructure - NestJS Module · `@role` Assemble les schémas Mongoose, déclare les providers d’adaptateurs (`{ provide: PORT_TOKEN, useClass: ... }`) et exporte les tokens de ports pour les couches Application/Interface · `@boundaries` Configuration d’injection de dépendances NestJS uniquement · `@ai-modification-guide` tout nouveau Port implémenté dans `outbound/` doit être lié à son token et exporté par ce module.',
    persistenceUnitTestExtension:
        '- Teste unitairement le Mapper (`toDomain()` / `toPersistence()` avec `reconstitute()`) sur tous les champs, Value Objects, sous-objets et enums sans connexion MongoDB.\n'
        '- Teste le Repository avec un Modèle Mongoose simulé (`.lean()` vérifié, gestion du verrouillage optimiste `__v` / `matchedCount === 0` -> `ConcurrencyException`, et traduction des codes MongoDB `11000` par `keyPattern`/`keyValue`, `121`, `112`, `50` via `Neverthrow`).',
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

  /// Consignes de documentation IA ajoutées à la toute fin de chaque prompt généré.
  final String aiDocumentation;

  /// Arborescence cible dédiée à *Domain > Implémentation* (`{{domain}}`).
  final String domainImplementationFolderStructure;

  /// Arborescence cible dédiée à *Domain > Test unitaire* (`{{domain}}`).
  final String domainUnitTestFolderStructure;

  /// Arborescence cible dédiée à *UseCase / Saga > Implémentation* (`{{domain}}`).
  final String useCaseSagaImplementationFolderStructure;

  /// Arborescence cible dédiée à *UseCase / Saga > Test unitaire* (`{{domain}}`).
  final String useCaseSagaUnitTestFolderStructure;

  /// Arborescence cible dédiée à *Outbound > Implémentation* (`{{domain}}`).
  final String outboundImplementationFolderStructure;

  /// Arborescence cible dédiée à *Outbound > Test unitaire* (`{{domain}}`).
  final String outboundUnitTestFolderStructure;

  /// Arborescence cible dédiée à *Inbound > Implémentation* (`{{domain}}`).
  final String inboundImplementationFolderStructure;

  /// Arborescence cible dédiée à *Inbound > Test unitaire* (`{{domain}}`).
  final String inboundUnitTestFolderStructure;

  /// Arborescence cible dédiée à *Persistance > Implémentation* (`{{domain}}`).
  final String persistenceImplementationFolderStructure;

  /// Arborescence cible dédiée à *Persistance > Test unitaire* (`{{domain}}`).
  final String persistenceUnitTestFolderStructure;

  /// Consignes spécifiques à *Domain > Implémentation*.
  final String domainImplementationExtension;

  /// Consignes spécifiques à *Domain > Test unitaire*.
  final String domainUnitTestExtension;

  /// Consignes spécifiques à *UseCase / Saga > Implémentation*.
  final String useCaseSagaImplementationExtension;

  /// Consignes spécifiques à *UseCase / Saga > Test unitaire*.
  final String useCaseSagaUnitTestExtension;

  /// Consignes spécifiques à *Outbound > Implémentation*.
  final String outboundImplementationExtension;

  /// Consignes spécifiques à *Outbound > Test unitaire*.
  final String outboundUnitTestExtension;

  /// Consignes spécifiques à *Inbound > Implémentation*.
  final String inboundImplementationExtension;

  /// Consignes spécifiques à *Inbound > Test unitaire*.
  final String inboundUnitTestExtension;

  /// Consignes spécifiques à *Persistance > Implémentation*.
  final String persistenceImplementationExtension;

  /// Consignes spécifiques à *Persistance > Test unitaire*.
  final String persistenceUnitTestExtension;

  /// Indique si ce profil contient au moins un bloc d'extension à injecter
  /// pour le couple ([section], [subRole]).
  bool hasExtensionContentFor(
    BuildTechStackSection section,
    BuildTechStackSubRole subRole,
  ) =>
      technicalStack.trim().isNotEmpty ||
      rawFolderStructureFor(section, subRole).isNotEmpty ||
      extensionFor(section, subRole).isNotEmpty ||
      aiDocumentation.trim().isNotEmpty;

  /// Retourne l'arborescence brute dédiée à ([section], [subRole]), ou
  /// [folderStructure] en repli.
  String rawFolderStructureFor(
    BuildTechStackSection section,
    BuildTechStackSubRole subRole,
  ) {
    final specific = switch ((section, subRole)) {
      (BuildTechStackSection.domain, BuildTechStackSubRole.implementation) =>
        domainImplementationFolderStructure,
      (BuildTechStackSection.domain, BuildTechStackSubRole.unitTest) =>
        domainUnitTestFolderStructure,
      (
        BuildTechStackSection.useCaseSaga,
        BuildTechStackSubRole.implementation,
      ) =>
        useCaseSagaImplementationFolderStructure,
      (BuildTechStackSection.useCaseSaga, BuildTechStackSubRole.unitTest) =>
        useCaseSagaUnitTestFolderStructure,
      (BuildTechStackSection.outbound, BuildTechStackSubRole.implementation) =>
        outboundImplementationFolderStructure,
      (BuildTechStackSection.outbound, BuildTechStackSubRole.unitTest) =>
        outboundUnitTestFolderStructure,
      (BuildTechStackSection.inbound, BuildTechStackSubRole.implementation) =>
        inboundImplementationFolderStructure,
      (BuildTechStackSection.inbound, BuildTechStackSubRole.unitTest) =>
        inboundUnitTestFolderStructure,
      (
        BuildTechStackSection.persistence,
        BuildTechStackSubRole.implementation,
      ) =>
        persistenceImplementationFolderStructure,
      (BuildTechStackSection.persistence, BuildTechStackSubRole.unitTest) =>
        persistenceUnitTestFolderStructure,
    }.trim();
    return specific.isNotEmpty ? specific : folderStructure.trim();
  }

  /// Retourne les consignes spécifiques à ([section], [subRole]).
  String extensionFor(
    BuildTechStackSection section,
    BuildTechStackSubRole subRole,
  ) => switch ((section, subRole)) {
    (BuildTechStackSection.domain, BuildTechStackSubRole.implementation) =>
      domainImplementationExtension,
    (BuildTechStackSection.domain, BuildTechStackSubRole.unitTest) =>
      domainUnitTestExtension,
    (BuildTechStackSection.useCaseSaga, BuildTechStackSubRole.implementation) =>
      useCaseSagaImplementationExtension,
    (BuildTechStackSection.useCaseSaga, BuildTechStackSubRole.unitTest) =>
      useCaseSagaUnitTestExtension,
    (BuildTechStackSection.outbound, BuildTechStackSubRole.implementation) =>
      outboundImplementationExtension,
    (BuildTechStackSection.outbound, BuildTechStackSubRole.unitTest) =>
      outboundUnitTestExtension,
    (BuildTechStackSection.inbound, BuildTechStackSubRole.implementation) =>
      inboundImplementationExtension,
    (BuildTechStackSection.inbound, BuildTechStackSubRole.unitTest) =>
      inboundUnitTestExtension,
    (BuildTechStackSection.persistence, BuildTechStackSubRole.implementation) =>
      persistenceImplementationExtension,
    (BuildTechStackSection.persistence, BuildTechStackSubRole.unitTest) =>
      persistenceUnitTestExtension,
  }.trim();

  /// Interpole les variables `{{domain}}` et `{{module}}` avec [domainCode].
  static String resolvePlaceholders(String raw, String domainCode) {
    final cleanCode = domainCode.trim().isEmpty ? 'domain' : domainCode.trim();
    return raw
        .replaceAll('{{domain}}', cleanCode)
        .replaceAll('{{module}}', cleanCode);
  }

  /// Résout l'arborescence cible pour ([section], [subRole]) en remplaçant
  /// `{{domain}}` et `{{module}}` par [domainCode].
  String resolveFolderStructureFor(
    String domainCode, {
    required BuildTechStackSection section,
    required BuildTechStackSubRole subRole,
  }) =>
      resolvePlaceholders(rawFolderStructureFor(section, subRole), domainCode);

  /// Résout la section « Documentation IA » en remplaçant `{{domain}}` et `{{module}}`.
  String resolveAiDocumentation(String domainCode) =>
      resolvePlaceholders(aiDocumentation.trim(), domainCode);

  /// Vérifie les invariants du profil de stack.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BuildTechStackProfile.id requis.');
    }
    if (code.length < 2 ||
        code.length > 64 ||
        !_stackCodePattern.hasMatch(code)) {
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
    final textFields = <String>[
      technicalStack,
      folderStructure,
      aiDocumentation,
      domainImplementationFolderStructure,
      domainUnitTestFolderStructure,
      useCaseSagaImplementationFolderStructure,
      useCaseSagaUnitTestFolderStructure,
      outboundImplementationFolderStructure,
      outboundUnitTestFolderStructure,
      inboundImplementationFolderStructure,
      inboundUnitTestFolderStructure,
      persistenceImplementationFolderStructure,
      persistenceUnitTestFolderStructure,
      domainImplementationExtension,
      domainUnitTestExtension,
      useCaseSagaImplementationExtension,
      useCaseSagaUnitTestExtension,
      outboundImplementationExtension,
      outboundUnitTestExtension,
      inboundImplementationExtension,
      inboundUnitTestExtension,
      persistenceImplementationExtension,
      persistenceUnitTestExtension,
    ];
    for (final field in textFields) {
      if (field.length > 32000) {
        throw const FormatException(
          'Une section d’extension de stack dépasse 32000 caractères.',
        );
      }
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
    String? aiDocumentation,
    String? domainImplementationFolderStructure,
    String? domainUnitTestFolderStructure,
    String? useCaseSagaImplementationFolderStructure,
    String? useCaseSagaUnitTestFolderStructure,
    String? outboundImplementationFolderStructure,
    String? outboundUnitTestFolderStructure,
    String? inboundImplementationFolderStructure,
    String? inboundUnitTestFolderStructure,
    String? persistenceImplementationFolderStructure,
    String? persistenceUnitTestFolderStructure,
    String? domainImplementationExtension,
    String? domainUnitTestExtension,
    String? useCaseSagaImplementationExtension,
    String? useCaseSagaUnitTestExtension,
    String? outboundImplementationExtension,
    String? outboundUnitTestExtension,
    String? inboundImplementationExtension,
    String? inboundUnitTestExtension,
    String? persistenceImplementationExtension,
    String? persistenceUnitTestExtension,
  }) => BuildTechStackProfile(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
    technicalStack: technicalStack ?? this.technicalStack,
    folderStructure: folderStructure ?? this.folderStructure,
    aiDocumentation: aiDocumentation ?? this.aiDocumentation,
    domainImplementationFolderStructure:
        domainImplementationFolderStructure ??
        this.domainImplementationFolderStructure,
    domainUnitTestFolderStructure:
        domainUnitTestFolderStructure ?? this.domainUnitTestFolderStructure,
    useCaseSagaImplementationFolderStructure:
        useCaseSagaImplementationFolderStructure ??
        this.useCaseSagaImplementationFolderStructure,
    useCaseSagaUnitTestFolderStructure:
        useCaseSagaUnitTestFolderStructure ??
        this.useCaseSagaUnitTestFolderStructure,
    outboundImplementationFolderStructure:
        outboundImplementationFolderStructure ??
        this.outboundImplementationFolderStructure,
    outboundUnitTestFolderStructure:
        outboundUnitTestFolderStructure ?? this.outboundUnitTestFolderStructure,
    inboundImplementationFolderStructure:
        inboundImplementationFolderStructure ??
        this.inboundImplementationFolderStructure,
    inboundUnitTestFolderStructure:
        inboundUnitTestFolderStructure ?? this.inboundUnitTestFolderStructure,
    persistenceImplementationFolderStructure:
        persistenceImplementationFolderStructure ??
        this.persistenceImplementationFolderStructure,
    persistenceUnitTestFolderStructure:
        persistenceUnitTestFolderStructure ??
        this.persistenceUnitTestFolderStructure,
    domainImplementationExtension:
        domainImplementationExtension ?? this.domainImplementationExtension,
    domainUnitTestExtension:
        domainUnitTestExtension ?? this.domainUnitTestExtension,
    useCaseSagaImplementationExtension:
        useCaseSagaImplementationExtension ??
        this.useCaseSagaImplementationExtension,
    useCaseSagaUnitTestExtension:
        useCaseSagaUnitTestExtension ?? this.useCaseSagaUnitTestExtension,
    outboundImplementationExtension:
        outboundImplementationExtension ?? this.outboundImplementationExtension,
    outboundUnitTestExtension:
        outboundUnitTestExtension ?? this.outboundUnitTestExtension,
    inboundImplementationExtension:
        inboundImplementationExtension ?? this.inboundImplementationExtension,
    inboundUnitTestExtension:
        inboundUnitTestExtension ?? this.inboundUnitTestExtension,
    persistenceImplementationExtension:
        persistenceImplementationExtension ??
        this.persistenceImplementationExtension,
    persistenceUnitTestExtension:
        persistenceUnitTestExtension ?? this.persistenceUnitTestExtension,
  );

  /// Sérialise le profil en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    if (technicalStack.isNotEmpty) 'technicalStack': technicalStack,
    if (folderStructure.isNotEmpty) 'folderStructure': folderStructure,
    if (aiDocumentation.isNotEmpty) 'aiDocumentation': aiDocumentation,
    if (domainImplementationFolderStructure.isNotEmpty)
      'domainImplementationFolderStructure':
          domainImplementationFolderStructure,
    if (domainUnitTestFolderStructure.isNotEmpty)
      'domainUnitTestFolderStructure': domainUnitTestFolderStructure,
    if (useCaseSagaImplementationFolderStructure.isNotEmpty)
      'useCaseSagaImplementationFolderStructure':
          useCaseSagaImplementationFolderStructure,
    if (useCaseSagaUnitTestFolderStructure.isNotEmpty)
      'useCaseSagaUnitTestFolderStructure': useCaseSagaUnitTestFolderStructure,
    if (outboundImplementationFolderStructure.isNotEmpty)
      'outboundImplementationFolderStructure':
          outboundImplementationFolderStructure,
    if (outboundUnitTestFolderStructure.isNotEmpty)
      'outboundUnitTestFolderStructure': outboundUnitTestFolderStructure,
    if (inboundImplementationFolderStructure.isNotEmpty)
      'inboundImplementationFolderStructure':
          inboundImplementationFolderStructure,
    if (inboundUnitTestFolderStructure.isNotEmpty)
      'inboundUnitTestFolderStructure': inboundUnitTestFolderStructure,
    if (persistenceImplementationFolderStructure.isNotEmpty)
      'persistenceImplementationFolderStructure':
          persistenceImplementationFolderStructure,
    if (persistenceUnitTestFolderStructure.isNotEmpty)
      'persistenceUnitTestFolderStructure': persistenceUnitTestFolderStructure,
    if (domainImplementationExtension.isNotEmpty)
      'domainImplementationExtension': domainImplementationExtension,
    if (domainUnitTestExtension.isNotEmpty)
      'domainUnitTestExtension': domainUnitTestExtension,
    if (useCaseSagaImplementationExtension.isNotEmpty)
      'useCaseSagaImplementationExtension': useCaseSagaImplementationExtension,
    if (useCaseSagaUnitTestExtension.isNotEmpty)
      'useCaseSagaUnitTestExtension': useCaseSagaUnitTestExtension,
    if (outboundImplementationExtension.isNotEmpty)
      'outboundImplementationExtension': outboundImplementationExtension,
    if (outboundUnitTestExtension.isNotEmpty)
      'outboundUnitTestExtension': outboundUnitTestExtension,
    if (inboundImplementationExtension.isNotEmpty)
      'inboundImplementationExtension': inboundImplementationExtension,
    if (inboundUnitTestExtension.isNotEmpty)
      'inboundUnitTestExtension': inboundUnitTestExtension,
    if (persistenceImplementationExtension.isNotEmpty)
      'persistenceImplementationExtension': persistenceImplementationExtension,
    if (persistenceUnitTestExtension.isNotEmpty)
      'persistenceUnitTestExtension': persistenceUnitTestExtension,
  };

  /// Désérialise un profil depuis JSON en assurant la rétrocompatibilité des
  /// anciens champs (`implementation*`, `unitTest*`, `persistence*`).
  factory BuildTechStackProfile.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Profil de stack technique invalide.');
    }
    String readFirst(String primary, [String? legacy]) {
      final value = raw[primary] as String?;
      if (value != null && value.isNotEmpty) return value;
      if (legacy != null) return (raw[legacy] as String?) ?? '';
      return value ?? '';
    }

    final profile = BuildTechStackProfile(
      id: (raw['id'] as String?)?.trim() ?? '',
      code: (raw['code'] as String?)?.trim() ?? '',
      name: (raw['name'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      technicalStack: (raw['technicalStack'] as String?) ?? '',
      folderStructure: (raw['folderStructure'] as String?) ?? '',
      aiDocumentation: (raw['aiDocumentation'] as String?) ?? '',
      domainImplementationFolderStructure: readFirst(
        'domainImplementationFolderStructure',
        'implementationFolderStructure',
      ),
      domainUnitTestFolderStructure: readFirst(
        'domainUnitTestFolderStructure',
        'unitTestFolderStructure',
      ),
      useCaseSagaImplementationFolderStructure: readFirst(
        'useCaseSagaImplementationFolderStructure',
      ),
      useCaseSagaUnitTestFolderStructure: readFirst(
        'useCaseSagaUnitTestFolderStructure',
      ),
      outboundImplementationFolderStructure: readFirst(
        'outboundImplementationFolderStructure',
      ),
      outboundUnitTestFolderStructure: readFirst(
        'outboundUnitTestFolderStructure',
      ),
      inboundImplementationFolderStructure: readFirst(
        'inboundImplementationFolderStructure',
      ),
      inboundUnitTestFolderStructure: readFirst(
        'inboundUnitTestFolderStructure',
      ),
      persistenceImplementationFolderStructure: readFirst(
        'persistenceImplementationFolderStructure',
        'persistenceFolderStructure',
      ),
      persistenceUnitTestFolderStructure: readFirst(
        'persistenceUnitTestFolderStructure',
      ),
      domainImplementationExtension: readFirst(
        'domainImplementationExtension',
        'implementationExtension',
      ),
      domainUnitTestExtension: readFirst(
        'domainUnitTestExtension',
        'unitTestExtension',
      ),
      useCaseSagaImplementationExtension: readFirst(
        'useCaseSagaImplementationExtension',
      ),
      useCaseSagaUnitTestExtension: readFirst('useCaseSagaUnitTestExtension'),
      outboundImplementationExtension: readFirst(
        'outboundImplementationExtension',
      ),
      outboundUnitTestExtension: readFirst('outboundUnitTestExtension'),
      inboundImplementationExtension: readFirst(
        'inboundImplementationExtension',
      ),
      inboundUnitTestExtension: readFirst('inboundUnitTestExtension'),
      persistenceImplementationExtension: readFirst(
        'persistenceImplementationExtension',
        'persistenceExtension',
      ),
      persistenceUnitTestExtension: readFirst('persistenceUnitTestExtension'),
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
          other.aiDocumentation == aiDocumentation &&
          other.domainImplementationFolderStructure ==
              domainImplementationFolderStructure &&
          other.domainUnitTestFolderStructure ==
              domainUnitTestFolderStructure &&
          other.useCaseSagaImplementationFolderStructure ==
              useCaseSagaImplementationFolderStructure &&
          other.useCaseSagaUnitTestFolderStructure ==
              useCaseSagaUnitTestFolderStructure &&
          other.outboundImplementationFolderStructure ==
              outboundImplementationFolderStructure &&
          other.outboundUnitTestFolderStructure ==
              outboundUnitTestFolderStructure &&
          other.inboundImplementationFolderStructure ==
              inboundImplementationFolderStructure &&
          other.inboundUnitTestFolderStructure ==
              inboundUnitTestFolderStructure &&
          other.persistenceImplementationFolderStructure ==
              persistenceImplementationFolderStructure &&
          other.persistenceUnitTestFolderStructure ==
              persistenceUnitTestFolderStructure &&
          other.domainImplementationExtension ==
              domainImplementationExtension &&
          other.domainUnitTestExtension == domainUnitTestExtension &&
          other.useCaseSagaImplementationExtension ==
              useCaseSagaImplementationExtension &&
          other.useCaseSagaUnitTestExtension == useCaseSagaUnitTestExtension &&
          other.outboundImplementationExtension ==
              outboundImplementationExtension &&
          other.outboundUnitTestExtension == outboundUnitTestExtension &&
          other.inboundImplementationExtension ==
              inboundImplementationExtension &&
          other.inboundUnitTestExtension == inboundUnitTestExtension &&
          other.persistenceImplementationExtension ==
              persistenceImplementationExtension &&
          other.persistenceUnitTestExtension == persistenceUnitTestExtension;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    code,
    name,
    description,
    technicalStack,
    folderStructure,
    aiDocumentation,
    domainImplementationFolderStructure,
    domainUnitTestFolderStructure,
    useCaseSagaImplementationFolderStructure,
    useCaseSagaUnitTestFolderStructure,
    outboundImplementationFolderStructure,
    outboundUnitTestFolderStructure,
    inboundImplementationFolderStructure,
    inboundUnitTestFolderStructure,
    persistenceImplementationFolderStructure,
    persistenceUnitTestFolderStructure,
    domainImplementationExtension,
    domainUnitTestExtension,
    useCaseSagaImplementationExtension,
    useCaseSagaUnitTestExtension,
    outboundImplementationExtension,
    outboundUnitTestExtension,
    inboundImplementationExtension,
    inboundUnitTestExtension,
    persistenceImplementationExtension,
    persistenceUnitTestExtension,
  ]);
}
