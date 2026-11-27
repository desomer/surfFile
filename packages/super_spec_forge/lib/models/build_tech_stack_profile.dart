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
  persistence(label: 'Persistance', slug: 'persistence'),

  /// Socle applicatif, configuration initiale et squelette technique partagé.
  boilerplate(label: 'Boilerplate', slug: 'boilerplate'),

  /// Outillage de développement, linters, scripts et configuration de build/test.
  devTools(label: 'Dev Tools', slug: 'dev-tools'),

  /// Vérification d'intégration bout-en-bout, câblage DI et conformité globale.
  checkIntegration(label: 'Check Integration', slug: 'check-integration'),

  /// Bac à sable local d'expérimentation, scripts de démonstration et essais manuels.
  playground(label: 'Playground', slug: 'playground');

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
    this.boilerplateImplementationFolderStructure = '',
    this.boilerplateUnitTestFolderStructure = '',
    this.devToolsImplementationFolderStructure = '',
    this.devToolsUnitTestFolderStructure = '',
    this.checkIntegrationImplementationFolderStructure = '',
    this.checkIntegrationUnitTestFolderStructure = '',
    this.playgroundImplementationFolderStructure = '',
    this.playgroundUnitTestFolderStructure = '',
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
    this.boilerplateImplementationExtension = '',
    this.boilerplateUnitTestExtension = '',
    this.devToolsImplementationExtension = '',
    this.devToolsUnitTestExtension = '',
    this.checkIntegrationImplementationExtension = '',
    this.checkIntegrationUnitTestExtension = '',
    this.playgroundImplementationExtension = '',
    this.playgroundUnitTestExtension = '',
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
    useCaseSagaUnitTestFolderStructure:
        'src/\n'
        '└── core/\n'
        '    └── {{domain}}/\n'
        '        └── application/\n'
        '            ├── commands/\n'
        '            │   └── *.handler.spec.ts\n'
        '            ├── queries/\n'
        '            │   └── *.handler.spec.ts\n'
        '            ├── services/\n'
        '            │   └── *.spec.ts\n'
        '            └── sagas/\n'
        '                └── *.spec.ts',
    outboundImplementationFolderStructure:
        'src/\n'
        '└── infrastructure/\n'
        '    └── {{domain}}/\n'
        '        ├── {{domain}}.module.ts\n'
        '        └── outbound/\n'
        '            ├── external-api/             # role: appels vers des API / services tiers externes (Anti-Corruption Layer)\n'
        '            │   └── <client-name>/        # ex: stripe, sendgrid, slack, keycloak...\n'
        '            │       ├── adapters/         # implémentation du port métier (appelle client + mapper)\n'
        '            │       ├── clients/          # client HTTP (fetch/axios/undici) ou SDK officiel\n'
        '            │       ├── dto-in/           # validation (zod) et typage des réponses API externe\n'
        '            │       ├── dto-out/          # contrats et payloads envoyés vers l’API externe\n'
        '            │       └── mappers/          # Anti-Corruption Layer (Domain <-> DTO externe)\n'
        '            ├── messaging/                # role: transport de messages\n'
        '            │   ├── consumers/            # consommation de messages\n'
        '            │   ├── publishers/           # publication de messages\n'
        '            │   └── avro/                 # outillage schéma/encodage des events\n'
        '            │       ├── mappers/          # sérialisation payload -> avro & inverse\n'
        '            │       └── registry/         # (optionnel) intégration schema registry\n'
        '            └── storage/                  # role: accès au stockage objet\n'
        '                ├── clients/              # clients SDK bucket (GCS/S3)\n'
        '                └── mappers/              # mapping métier <-> provider bucket',
    outboundUnitTestFolderStructure: 'identique au domaine principal\n',
    inboundImplementationFolderStructure:
        'src/\n'
        '└── infrastructure/\n'
        '    └── {{domain}}/\n'
        '        └── inbound/\n'
        '            ├── rest/                  # API REST HTTP versionnée\n'
        '            │   └── v1/                # Version d’API extraite de la route (v1, v2…)\n'
        '            │       ├── controllers/   # Points d’entrée NestJS (@Controller) appelant Commands/Queries\n'
        '            │       ├── dto-in/        # Contrats d’entrée HTTP & validation technique Zod\n'
        '            │       ├── dto-out/       # Contrats JSON de réponse (types primitifs uniquement)\n'
        '            │       └── mappers/       # Traduction pure DTO-in -> Command et Domain -> DTO-out\n'
        '            ├── graphql/               # (si GraphQL est utilisé) API GraphQL\n'
        '            │   ├── resolvers/         # Résolveurs NestJS équivalents aux controllers\n'
        '            │   ├── inputs/            # Types & schémas Zod d’entrée GraphQL\n'
        '            │   └── outputs/           # Types de sortie GraphQL (primitifs uniquement)\n'
        '            └── cli/                   # (si commandes CLI) Adaptateurs ligne de commande → CommandBus',
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
    boilerplateImplementationFolderStructure:
        'src/\n'
        '├── main.ts                  # Bootstrap NestJS (Fastify + Pino + global Zod pipe)\n'
        '└── app.module.ts            # Module racine assemblant la configuration, Pino et les domaines',
    boilerplateUnitTestFolderStructure:
        'test/\n'
        '└── shared/                  # Tests unitaires configuration, helpers & bootstrap (*.spec.ts)',
    devToolsImplementationFolderStructure:
        '.\n'
        '├── package.json             # Scripts build/lint/test & dépendances\n'
        '├── tsconfig.json            # strict: true, noUncheckedIndexedAccess: true\n'
        '├── eslint.config.mjs        # Règles lint & frontières hexagonales\n'
        '├── vitest.config.ts         # Configuration runner de tests\n'
        '├── docker/\n'
        '│   ├── mongo/\n'
        '│   │   └── docker-compose.yml   # MongoDB local (port 27017)\n'
        '│   └── pubsub/\n'
        '│       └── docker-compose.yml   # Émulateur Pub/Sub (8681) + UI (8086)\n'
        '└── .github/workflows/       # Pipeline CI (typecheck, lint, tests)',
    devToolsUnitTestFolderStructure:
        'test/\n'
        '└── architecture/            # Tests d’architecture & isolation de core/ (*.spec.ts)',
    checkIntegrationImplementationFolderStructure:
        'src/\n'
        '├── app.module.ts                # Module racine (MongooseModule.forRoot, modules infra/interface)\n'
        '└── infrastructure/\n'
        '    └── {{domain}}/\n'
        '        ├── {{domain}}.module.ts   # Câblage DI Infrastructure / Application / Interface\n'
        '        └── {{domain}}.probe.ts    # Sonde d’injection runtime DI (*.probe.ts)\n'
        'test/\n'
        '└── {{domain}}/\n'
        '    └── integration/               # Tests d’intégration & câblage module NestJS (*.int-spec.ts)',
    checkIntegrationUnitTestFolderStructure:
        'test/\n'
        '└── {{domain}}/\n'
        '    └── e2e/                   # Scénarios bout-en-bout & contrats API (*.e2e-spec.ts)',
    playgroundImplementationFolderStructure:
        'src/\n'
        '└── infrastructure/\n'
        '    └── {{domain}}/\n'
        '        └── playground/',
    playgroundUnitTestFolderStructure: 'test/{{domain}}/playground/',
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
        '## Contexte du code source :\n'
        '- Le domaine est déjà défini.\n'
        '\n'
        'Objectif :\n'
        'Couvrir 100 % des règles métier du domaine (pas de tests e2e, pas d’infra, pas de NestJS).\n'
        'Tester uniquement les comportements métier et les invariants.\n'
        'Utiliser une approche claire Arrange / Act / Assert.\n'
        '\n'
        '## Exigences de test :\n'
        '- Propagation des erreurs repository.\n'
        '- Logger appelé sur succès.\n'
        '- Vérifier explicitement le contenu des erreurs (`code` + `message`), pas seulement `isErr`.\n'
        '- Ajouter des mocks/fakes simples pour repository et logger.\n'
        '- Fournir des tests lisibles, isolés et déterministes.\n'
        '\n'
        'CONTRAINTES TESTS OBLIGATOIRES (NON NÉGOCIABLES)\n'
        '\n'
        '- Convention de nommage imposée :\n'
        '  - Tous les tests unitaires doivent être en `.spec.ts` (refus de `.test.ts`).\n'
        '- Portée de test minimale obligatoire :\n'
        '  - Tester les aggregates.\n'
        '  - Tester les domain services et policy services.\n'
        '  - Tester les use cases/handlers applicatifs.\n'
        '  - Tester les mappers critiques.\n'
        '  - Tester les adapters/repositories avec doubles si nécessaire.\n'
        '  - Tester les erreurs métier et transitions invalides.\n'
        '- Couverture fonctionnelle attendue :\n'
        '  - Cas nominal.\n'
        '  - Cas limites.\n'
        '  - Cas d’erreur.\n'
        '  - Invariants métier.\n'
        '  - Transitions d’état autorisées et interdites.\n'
        '  - Événements émis par le domaine si présents.\n'
        '- Critères de validation :\n'
        '  - Chaque méthode publique d’aggregate doit avoir au moins un test nominal et un test d’échec.\n'
        '  - Chaque service métier doit avoir tests succès et échec.\n'
        '- Critères de livraison obligatoires :\n'
        '  - Générer la liste exacte des fichiers `.spec.ts` créés/modifiés.\n'
        '  - Ajouter ou mettre à jour les scripts npm de test.\n'
        '  - Exécuter build + tests.\n'
        '  - Fournir le résultat d’exécution (pass/fail, nombre de tests).\n'
        '- Les fichiers `.spec.ts` ne doivent pas être embarqués dans l’artefact de production ; prévoir explicitement l’exclusion des tests du build de prod.\n'
        '\n'
        'Definition of done :\n'
        '- Tests en `.spec.ts` obligatoires\n'
        '- Tests aggregates + services + handlers obligatoires\n'
        '- Cas nominal + erreur + invariants obligatoires\n'
        '\n'
        '## Livrables attendus :\n'
        '- Code complet des fichiers de test.\n'
        '- Commandes npm à ajouter pour exécuter les tests.\n'
        '- Mise à jour si besoin de `tasks.json` : créer une tâche VS Code dédiée « npm: test:domain » dans `/.vscode/tasks.json`.\n'
        '- Si nécessaire, les dépendances de test à installer.\n'
        '- Petit résumé final de la couverture métier obtenue.\n'
        '\n'
        '## Contraintes techniques :\n'
        '- TypeScript strict.\n'
        '- Aucun décorateur NestJS.\n'
        '- Aucun accès DB, HTTP ou framework.\n'
        '- Pas de refactor fonctionnel du domaine sans justification.\n'
        '- Mettre des commentaires en français dans les fichiers de test (Arrange / Act / Assert et explications des cas testés).\n'
        '\n'
        '## En-têtes de fichiers obligatoires (JSDoc IA en français par type de fichier `.spec.ts`) :\n'
        'Chaque fichier de test `.spec.ts` généré DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@target`, `@role`, `@coverage` et `@ai-modification-guide` :\n'
        '- Tests d’Aggregates, Entities et Value Objects (`domain/models/**/*.spec.ts`) : `@layer` Unit Test - Domain Model · `@target` Nom de l’Aggregate, Entity ou Value Object testé · `@role` Vérifie la création (`create`), les invariants métier, les transitions d’état autorisées/interdites et l’émission des Domain Events · `@ai-modification-guide` toute nouvelle règle métier ou invariant ajouté dans le modèle DOIT avoir son test nominal (`isOk`) et son test d’erreur (`isErr` avec vérification du code et du message).\n'
        '- Tests de Domain Services (`domain/services/**/*.spec.ts`) : `@layer` Unit Test - Domain Service · `@target` Nom du Domain Service / Policy Service testé · `@role` Vérifie les calculs métier transverses, les cas limites et les politiques métier inter-agrégats de manière déterministe · `@ai-modification-guide` conserver des tests 100 % isolés sans dépendance d’infrastructure.\n'
        '- Tests de Handlers et Services Applicatifs (`application/**/*.spec.ts`) : `@layer` Unit Test - Application Use Case (Command / Query Handler) · `@target` Nom du Handler ou Application Service testé · `@role` Vérifie l’orchestration du cas d’usage avec des fakes/mocks des ports (repositories, logger, event bus), la propagation des erreurs `Neverthrow` et les appels au logger · `@ai-modification-guide` si un nouveau Port est injecté dans le Handler, ajouter son fake/mock ici et tester à la fois le cas nominal et le cas d’erreur de ce port.\n'
        '- Tests de Mappers et Adaptateurs (`interface/**/*.spec.ts`, `infrastructure/**/*.spec.ts`) : `@layer` Unit Test - Mapper / Adapter · `@target` Nom du Mapper ou de l’Adaptateur testé · `@role` Garantit la fidélité des transformations bidirectionnelles (`DTO <-> Command/Domain` ou `Domain <-> Persistence`) et la traduction des erreurs techniques · `@ai-modification-guide` tout champ ajouté au contrat ou au modèle doit être vérifié dans les assertions de mapping aller-retour.',
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
        '## Contexte du code source :\n'
        '- Le domaine (`src/core/{{domain}}/domain/`) et la couche application (`src/core/{{domain}}/application/` et `src/core/{{domain}}/ports/`) sont déjà définis.\n'
        '\n'
        'Objectif :\n'
        'Couvrir 100 % de l’orchestration applicative, des critères d’acceptation, des scénarios métier (Given / When / Then) et des Sagas (y compris leurs compensations) définis dans la spécification des Use Cases (pas de tests e2e, pas d’infra réelle, pas de NestJS).\n'
        'Tester uniquement l’orchestration des cas d’usage (Commands, Queries, Handlers, Application Services, Sagas) en isolant les dépendances externes via des doublures des Ports.\n'
        'Utiliser une approche claire Arrange / Act / Assert directement alignée sur les scénarios Given / When / Then.\n'
        '\n'
        '## Exigences de test :\n'
        '- Couverture complète du processus détaillé de chaque Use Case (chargement via repository/read-model, contrôle d’autorisation, délégation au domaine, persistance, historisation, publication d’événements applicatifs, retour de l’output attendu).\n'
        '- Propagation explicite des erreurs des ports (repositories, gateways, messaging, storage, read-models) et des erreurs métier du domaine.\n'
        '- Vérifier explicitement le contenu des erreurs `Neverthrow` (`isErr` + vérification du `code`, du `message` et du type d’erreur applicative/domaine comme `NotFound`, `Unauthorized`, `Invalid...`, `RepositoryError`).\n'
        '- Vérifier l’absence totale d’effets de bord en cas d’erreur métier ou d’autorisation refusée (aucune sauvegarde `save`, aucun enregistrement d’historique, aucun événement applicatif publié).\n'
        '- Logger appelé sur succès et sur erreur selon le contrat du port `logging`.\n'
        '- Vérifier la cohérence transactionnelle via `UnitOfWorkPort.runInTransaction()` lorsqu’un service applicatif ou handler l’utilise.\n'
        '- Pour chaque Saga présente dans la spécification :\n'
        '  - Tester le flux nominal complet multi-étapes (écoute d’événements, envoi des commands via `CommandDispatcherPort`, publication via `ApplicationEventPublisherPort`).\n'
        '  - Tester la **matrice des compensations** : pour chaque déclencheur de rollback (`rollbackTrigger`), vérifier l’exécution exacte des actions de compensation (`compensationAction`) dans l’ordre attendu.\n'
        '  - Tester les propriétés d’**idempotence** (`idempotent`), de **retry** (`retryable`), de **timeout** (`timeout`) et de **criticité** (`criticality`) déclarées dans la matrice.\n'
        '- Ajouter des mocks/fakes/spies simples en TypeScript pur pour tous les ports injectés (repositories, read-models, gateways, autorisation, event publisher, command dispatcher, unit of work, logger).\n'
        '- Respecter les **Non-objectifs** de chaque Use Case : ne pas tester ni imposer de comportements explicitement exclus du périmètre.\n'
        '- Fournir des tests lisibles, isolés et déterministes (horloge/UUID contrôlés si nécessaire).\n'
        '\n'
        'CONTRAINTES TESTS OBLIGATOIRES (NON NÉGOCIABLES)\n'
        '\n'
        '- Convention de nommage imposée :\n'
        '  - Tous les tests unitaires doivent être en `.spec.ts` (refus de `.test.ts`).\n'
        '  - Emplacement obligatoire sous `src/core/{{domain}}/application/**/*.spec.ts`.\n'
        '- Portée de test minimale obligatoire :\n'
        '  - Tester chaque Command Handler (`application/commands/*.handler.spec.ts`).\n'
        '  - Tester chaque Query Handler (`application/queries/*.handler.spec.ts`).\n'
        '  - Tester les Application Services (`application/services/*.spec.ts`) s’ils existent.\n'
        '  - Tester les Sagas / Process Managers (`application/sagas/*.spec.ts`) et leur matrice de compensation s’ils existent.\n'
        '  - Tester les erreurs applicatives (`application/errors/`) et l’émission des événements applicatifs (`application/events/`).\n'
        '- Couverture fonctionnelle attendue :\n'
        '  - Tous les scénarios Given / When / Then de la spécification (cas nominal, cas limites, cas d’erreur).\n'
        '  - Tous les critères d’acceptation listés pour chaque Use Case.\n'
        '  - Toutes les erreurs listées dans « Erreurs possibles » (`possibleErrors`).\n'
        '  - Vérification des entrées (Commands / Queries conformes au `trigger`) et des sorties (`output` attendu).\n'
        '  - Transitions et compensations (rollback métier) des Sagas.\n'
        '- Critères de validation :\n'
        '  - Chaque Command Handler et Query Handler doit avoir au moins un test nominal (`isOk`) et un test par cas d’échec métier/port (`isErr`).\n'
        '  - Chaque étape compensable d’une Saga doit avoir un test nominal et un test de déclenchement de compensation.\n'
        '  - Chaque critère d’acceptation du Use Case doit être vérifié par au moins une assertion explicite.\n'
        '- Critères de livraison obligatoires :\n'
        '  - Générer la liste exacte des fichiers `.spec.ts` créés/modifiés.\n'
        '  - Ajouter ou mettre à jour les scripts npm de test (ex. `test:usecase`).\n'
        '  - Exécuter build + tests et fournir le résultat d’exécution (pass/fail, nombre de tests).\n'
        '- Exclusion de production :\n'
        '  - Les fichiers `.spec.ts` ne doivent pas être embarqués dans l’artefact de production ; prévoir explicitement l’exclusion des tests du build de prod.\n'
        '\n'
        'Definition of done :\n'
        '- Tests en `.spec.ts` obligatoires sous `src/core/{{domain}}/application/`\n'
        '- Tests commands/queries handlers + application services + sagas obligatoires\n'
        '- Scénarios Given/When/Then + critères d’acceptation + erreurs + compensations de sagas couverts à 100 %\n'
        '- Vérification stricte de l’absence d’effets de bord sur échec\n'
        '\n'
        '## Livrables attendus :\n'
        '- Code complet des fichiers de test `.spec.ts` (et fakes/mocks de ports associés si mutualisés).\n'
        '- Commandes npm à ajouter pour exécuter les tests (ex. `npm run test:usecase`).\n'
        '- Mise à jour si besoin de `/.vscode/tasks.json` : créer une tâche VS Code dédiée « npm: test:usecase ».\n'
        '- Si nécessaire, les dépendances de test à installer.\n'
        '- Petit résumé final de la couverture applicative obtenue (Use Cases, critères d’acceptation et Sagas couverts).\n'
        '\n'
        '## Contraintes techniques :\n'
        '- TypeScript strict.\n'
        '- Aucun décorateur NestJS, aucun import NestJS.\n'
        '- Aucun accès DB, HTTP, broker de messages ou framework réel.\n'
        '- Pas de refactor fonctionnel de la couche Application ou Domaine sans justification.\n'
        '- Mettre des commentaires en français dans les fichiers de test (Arrange / Act / Assert en correspondance avec Given / When / Then et explications des cas testés).\n'
        '\n'
        '## En-têtes de fichiers obligatoires (JSDoc IA en français par type de fichier `.spec.ts`) :\n'
        'Chaque fichier de test `.spec.ts` généré DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@target`, `@role`, `@coverage` et `@ai-modification-guide` :\n'
        '- Tests de Command Handlers (`application/commands/**/*.spec.ts`) : `@layer` Unit Test - Application Command Handler (CQRS) · `@target` Nom du Command Handler et de la Command associés · `@role` Vérifie l’orchestration complète du cas d’usage d’écriture (chargement via ports, autorisations, appel au domaine, persistance, publication d’événements applicatifs, journalisation, absence d’effets de bord sur erreur) · `@coverage` Liste des scénarios Given/When/Then, critères d’acceptation et erreurs (`possibleErrors`) couverts · `@ai-modification-guide` si un nouveau Port, une règle d’orchestration ou une erreur possible est ajouté au Use Case, mettre à jour les fakes/mocks et ajouter le couple test nominal (`isOk`) / test d’échec (`isErr` avec code + message).\n'
        '- Tests de Query Handlers (`application/queries/**/*.spec.ts`) : `@layer` Unit Test - Application Query Handler (CQRS) · `@target` Nom du Query Handler et de la Query associés · `@role` Vérifie la récupération via les ports de lecture (`read-model` / `repositories`), le filtrage/projection attendu en sortie (`output`), le contrôle d’accès éventuel et la propagation des erreurs `Neverthrow` sans mutation d’état · `@coverage` Liste des scénarios nominaux, résultats vides/introuvables et erreurs de ports couverts · `@ai-modification-guide` garantir qu’aucun port d’écriture n’est sollicité et vérifier tout nouveau champ ajouté au contrat `output` du Use Case.\n'
        '- Tests d’Application Services (`application/services/**/*.spec.ts`) : `@layer` Unit Test - Application Service · `@target` Nom de l’Application Service testé · `@role` Vérifie l’orchestration synchrone transverse multi-agrégats / multi-ports et l’atomicité transactionnelle via `UnitOfWorkPort` · `@coverage` Workflows nominaux, annulation transactionnelle sur erreur intermédiaire et propagation des erreurs · `@ai-modification-guide` toute nouvelle étape ajoutée dans la transaction doit être testée en succès et en échec avec vérification du rollback `UnitOfWorkPort`.\n'
        '- Tests de Sagas / Process Managers (`application/sagas/**/*.spec.ts`) : `@layer` Unit Test - Application Saga / Process Manager · `@target` Nom de la Saga testée · `@role` Vérifie l’orchestration asynchrone multi-étapes, l’enchaînement des événements/commands, la matrice de compensation (rollback métier), l’idempotence, les politiques de retry et la gestion des timeouts · `@coverage` Étapes nominales et ensemble des lignes de la `compensationMatrix` (déclencheurs de rollback, criticité, idempotence, retry, timeout) · `@ai-modification-guide` toute nouvelle étape ajoutée à la Saga DOIT avoir ses tests nominaux, ses tests de compensation en cas d’échec aval et son test d’idempotence.',
    outboundImplementationExtension:
        '## Contexte de code source :\n'
        '- Le domaine est déjà défini.\n'
        '- La couche Application est déjà définie.\n'
        '- Les ports sortants (`driven ports`) sont définis dans : `core/{{domain}}/ports/` (ou `core/{{domain}}/ports/outbound/`).\n'
        '- Les adaptateurs outbound doivent implémenter strictement ces ports sans exposer de détails techniques des providers tiers au domaine.\n'
        '\n'
        '## Règles obligatoires :\n'
        '1. **External API (`outbound/external-api/<client-name>/`)** :\n'
        '   - Un sous-dossier dédié par fournisseur ou service externe (`<client-name>`, ex. `stripe/`, `payplug/`, `docusign/`).\n'
        '   - `clients/` : Encapsule les appels HTTP ou le SDK tiers (authentification, headers, timeout, retry, circuit-breaker). Ne connaît pas le Domaine.\n'
        '   - `dto-out/` : Types primitifs représentant le payload de requête attendu par l’API externe.\n'
        '   - `dto-in/` : Schémas `zod` et types représentant la réponse brute de l’API externe (protège le domaine contre les changements de contrat tiers).\n'
        '   - `mappers/` : Anti-Corruption Layer (ACL) pur et sans dépendance NestJS. Transforme `Domain → dto-out` et `dto-in → Domain`.\n'
        '   - `adapters/` : Classe `@Injectable()` qui implémente le Port du domaine, orchestre `mapper -> client -> validation zod dto-in -> mapper` et traduit les erreurs HTTP/SDK en erreurs métier via `Neverthrow` (`ResultAsync` / `Result`).\n'
        '2. **Messaging (`outbound/messaging/`)** :\n'
        '   - `publishers/` : Implémente les ports de publication d’événements/messages. Convertit les événements du domaine/application, utilise les mappers Avro et publie sur le broker (Kafka/RabbitMQ/PubSub).\n'
        '   - `consumers/` : Gère la souscription technique aux topics/queues, désérialise via `avro/mappers/` et délègue le traitement.\n'
        '   - `avro/mappers/` : Sérialisation `payload -> avro` et désérialisation `avro -> payload` sans logique métier.\n'
        '   - `avro/registry/` (optionnel) : Gestion de la connexion et résolution des schémas auprès du Schema Registry.\n'
        '3. **Storage (`outbound/storage/`)** :\n'
        '   - `clients/` : Encapsule le SDK du fournisseur de stockage objet (AWS S3, Google Cloud Storage, MinIO) : upload, download, signed URLs, suppression, gestion des streams/buffers.\n'
        '   - `mappers/` : Transforme les métadonnées, chemins (`key`/`bucket`) et objets métier vers/depuis les structures du provider de stockage (`Domain <-> Provider Bucket`).\n'
        '4. **Règles transverses (Clean Architecture & Qualité)** :\n'
        '   - Utiliser NestJS (`@Injectable()`, `@Inject()`) uniquement dans la couche `infrastructure/`.\n'
        '   - Ne jamais exposer les types d’un SDK tiers (ex. `Stripe.*`, `@aws-sdk/*`, `kafkajs`) en dehors de `outbound/`.\n'
        '   - Ne jamais mettre de logique métier dans l’infrastructure.\n'
        '   - Gérer toutes les erreurs techniques (réseau, timeout, quota, sérialisation, 4xx/5xx tiers, erreurs S3/GCS) et les convertir proprement avec `Neverthrow`.\n'
        '   - Utiliser le logger `pino` pour les logs techniques (appels externes, latence, erreurs de transport, publication/consommation de messages) sans jamais logger de secrets ou clés d’API.\n'
        '   - Mettre des commentaires en français dans le code généré (JSDoc et commentaires explicatifs).\n'
        '\n'
        '## En-têtes de fichiers obligatoires (JSDoc IA en français par dossier autorisé) :\n'
        'Chaque fichier généré DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@folder`, `@role`, `@boundaries`, `@collaborators` et `@ai-modification-guide`, adapté à son dossier :\n'
        '- `outbound/external-api/<client-name>/adapters/` : `@layer` Infrastructure - Outbound External API Adapter (`<client-name>`) · `@role` Implémente le Port sortant du domaine (`core/{{domain}}/ports/`), orchestre Mapper, Client HTTP/SDK, validation `zod` (`dto-in`) et traduit les erreurs tierces en erreurs métier via `Neverthrow` · `@boundaries` Autorise `@Injectable()` NestJS, Client/Mapper/DTOs du dossier `<client-name>`, Ports du domaine, Neverthrow, Logger ; n’expose aucun type externe hors de `outbound/` · `@ai-modification-guide` toute évolution du Port métier doit être répercutée ici et dans le Mapper associé sans fuite du contrat externe.\n'
        '- `outbound/external-api/<client-name>/clients/` : `@layer` Infrastructure - Outbound External API Client (`<client-name>`) · `@role` Encapsule le transport HTTP (`fetch`/`axios`/`undici`) ou le SDK officiel de `<client-name>` (authentification, headers, timeouts, retries) · `@boundaries` Pur client technique, ne connaît NI le Domaine NI les Ports métier, manipule uniquement `dto-out` et `dto-in` · `@ai-modification-guide` ne jamais logger de tokens/clés d’API en clair ; toute nouvelle route externe appelée doit avoir ses `dto-out` et `dto-in` (Zod) dédiés.\n'
        '- `outbound/external-api/<client-name>/dto-in/` et `dto-out/` : `@layer` Infrastructure - Outbound External API DTO (`<client-name>`) · `@role` Contrats de données du fournisseur externe (`dto-out` pour le payload envoyé, `dto-in` avec schéma `zod` pour valider la réponse reçue) · `@boundaries` Types primitifs et `zod` uniquement, zéro dépendance au Domaine · `@ai-modification-guide` si l’API externe change son contrat JSON, modifier uniquement ces DTOs et le Mapper dans `<client-name>/mappers/` (Anti-Corruption Layer) sans impacter le Domaine.\n'
        '- `outbound/external-api/<client-name>/mappers/` : `@layer` Infrastructure - Outbound External API Mapper / ACL (`<client-name>`) · `@role` Anti-Corruption Layer pur transformant `Domain -> dto-out` et `dto-in -> Domain` · `@boundaries` TypeScript pur, sans dépendance NestJS ni appels réseau · `@ai-modification-guide` garder des fonctions de mapping pures et couvrir les cas de valeurs nulles/optionnelles renvoyées par le tiers.\n'
        '- `outbound/messaging/publishers/` et `outbound/messaging/consumers/` : `@layer` Infrastructure - Outbound Messaging (Publisher | Consumer) · `@role` Publication ou consommation de messages sur le broker (Kafka/RabbitMQ/PubSub) avec encodage/décodage via `avro/mappers/` · `@boundaries` Implémente les ports de `core/{{domain}}/ports/messaging/`, isole les détails du broker et gère erreurs (`Neverthrow`) et logs (`pino`) · `@ai-modification-guide` vérifier la compatibilité ascendante/descendante du schéma Avro lors de toute modification de message.\n'
        '- `outbound/messaging/avro/mappers/` et `outbound/messaging/avro/registry/` : `@layer` Infrastructure - Outbound Messaging Avro (Mapper | Schema Registry) · `@role` Sérialisation `payload -> avro`, désérialisation `avro -> payload` et résolution des schémas auprès du Schema Registry · `@boundaries` Outillage technique de sérialisation sans aucune logique métier · `@ai-modification-guide` toute évolution de schéma Avro doit maintenir l’alignement entre le payload applicatif et l’encodage binaire/JSON Avro.\n'
        '- `outbound/storage/clients/` et `outbound/storage/mappers/` : `@layer` Infrastructure - Outbound Object Storage (Client | Mapper) · `@role` Accès aux buckets S3/GCS/MinIO (`clients/`) et transformation entre objets/métadonnées métier et structure du provider (`mappers/`) · `@boundaries` Ne jamais exposer les types du SDK `@aws-sdk/*` ou `@google-cloud/storage` en dehors de `outbound/storage/` · `@ai-modification-guide` traduire toutes les erreurs SDK (fichier introuvable, quota, droits, timeout) en erreurs typées du port `core/{{domain}}/ports/storage/`.\n'
        '\n'
        '## Génère :\n'
        '- L’arborescence complète ciblée sous `infrastructure/{{domain}}/outbound/`\n'
        '- Tous les fichiers nécessaires (`clients`, `adapters`, `dto-in`, `dto-out`, `mappers`, `publishers`/`consumers`, module NestJS)\n'
        '- Le câblage d’injection de dépendances NestJS (`{ provide: PORT_TOKEN, useClass: AdapterImpl }`)\n'
        '- Un code TypeScript complet, fortement typé, idiomatique et conforme aux bonnes pratiques Hexagonales + DDD + CQRS.',
    outboundUnitTestExtension:
        '- Teste unitairement chaque adaptateur sortant (`messaging`, `logging`, clients externes) en isolant le SDK/client tiers par doublure déterministe.\n'
        '- Vérifie le mapping des payloads sortants, la journalisation et la traduction des erreurs techniques vers `Result` (`Neverthrow`).',
    inboundImplementationExtension:
        '# Contexte technique :\n'
        'Tu es un expert en architecture Hexagonale, DDD, CQRS et Clean Architecture.\n'
        '\n'
        'route_style: restful\n'
        'query_style: page-pageSize-sort-filter-search\n'
        'api_convention: RESTful API Design Guidelines\n'
        '\n'
        '## Contexte de code source :\n'
        '- Le domaine est déjà défini.\n'
        '- La couche Application est déjà définie.\n'
        '- Respecte strictement l’arborescence sous `src/infrastructure/{{domain}}/inbound/rest/v1/` (`controllers/`, `dto-in/`, `dto-out/`, `mappers/`, ou version extraite de la route `v1`/`v2`).\n'
        '\n'
        '## Règles obligatoires :\n'
        '1. **dto-in (`dto-in/`)** :\n'
        '   - Validation technique via `zod`.\n'
        '   - Aucun décorateur métier.\n'
        '2. **dto-out (`dto-out/`)** :\n'
        '   - Types primitifs uniquement.\n'
        '   - Jamais exposer le domaine.\n'
        '   - Format JSON brut pour l’API.\n'
        '3. **Controller (`controllers/`)** :\n'
        '   - Reçoit un DTO d’entrée.\n'
        '   - Convertit DTO → Command.\n'
        '   - Appelle usecase Command ou Query.\n'
        '   - Convertit Domain → Response DTO via un Mapper.\n'
        '   - Ne contient aucune logique métier ; pas d’appel direct au domaine, tout passe par la couche Application.\n'
        '   - Utilise le logger `pino` pour le log technique.\n'
        '   - Ne pas mettre d’appel à un bus d’événement : tout doit passer par la couche Application.\n'
        '4. **Mapper (`mappers/`)** :\n'
        '   - Transforme DTO-in → Command.\n'
        '   - Transforme Domain → Response dto-out.\n'
        '   - Ne dépend pas de NestJS.\n'
        '   - Ne contient aucune logique métier.\n'
        '\n'
        '## Génère :\n'
        '- L’arborescence complète et tous les fichiers.\n'
        '- Le code TypeScript complet : les DTO-IN, les DTO-OUT, le controller, les mappers.\n'
        '- Les exemples de commands utilisées et un flux complet : DTO → Command → Handler → Domain → Response.\n'
        '- Utilise le logger `pino`, gère les erreurs avec `Neverthrow` et utilise `zod` pour valider les DTO (et inputs GraphQL le cas échéant).\n'
        '- Mets des commentaires en français dans le code généré (JSDoc et commentaires explicatifs).\n'
        '\n'
        '## En-têtes de fichiers obligatoires (JSDoc IA en français par dossier autorisé) :\n'
        'Chaque fichier généré DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@folder`, `@role`, `@boundaries`, `@collaborators` et `@ai-modification-guide`, adapté à son dossier :\n'
        '- `inbound/rest/<version>/controllers/` : `@layer` Interface - Inbound REST (`<version>`, ex. `v1`) · `@role` Point d’entrée HTTP : valide le `dto-in` (Zod), convertit en Command/Query via le Mapper, appelle le Handler applicatif, mappe la réponse en `dto-out` et traduit les erreurs métier/applicatives en codes HTTP · `@boundaries` Autorise NestJS HTTP, Zod, Mappers d’interface, Commands/Queries/Handlers applicatifs, Logger ; interdit toute logique métier, tout appel direct aux Repositories ou l’exposition d’entités du Domaine · `@ai-modification-guide` tout changement cassant du contrat HTTP/JSON doit être créé dans une nouvelle version (`rest/v2/`) si l’API est déjà publiée.\n'
        '- `inbound/rest/<version>/dto-in/` : `@layer` Interface - Inbound REST DTO-In (`<version>`) · `@role` Contrat d’entrée HTTP et schéma de validation technique `zod` (corps de requête, paramètres de route et query) · `@boundaries` Uniquement `zod` et types TypeScript primitifs, aucune logique métier, aucun décorateur métier · `@ai-modification-guide` si un champ est ajouté ou modifié, mettre à jour le Mapper dans `inbound/rest/<version>/mappers/` et la Command/Query cible si nécessaire.\n'
        '- `inbound/rest/<version>/dto-out/` : `@layer` Interface - Inbound REST DTO-Out (`<version>`) · `@role` Contrat de sérialisation JSON de sortie renvoyé au client HTTP · `@boundaries` Types primitifs TypeScript uniquement, interdiction absolue d’importer ou d’exposer des classes du Domaine (Entities, Value Objects) · `@ai-modification-guide` si la structure de réponse change, mettre à jour la méthode `toResponse` du Mapper dans `inbound/rest/<version>/mappers/`.\n'
        '- `inbound/rest/<version>/mappers/` : `@layer` Interface - Inbound REST Mapper (`<version>`) · `@role` Traducteur pur entre la couche Interface REST (`dto-in` / `dto-out`) et la couche Application/Domaine (`Command` / `Query` / résultats domaine) · `@boundaries` TypeScript pur, sans dépendance NestJS et sans logique métier · `@ai-modification-guide` maintenir des fonctions de transformation pures, déterministes et testables unitairement sans contexte HTTP.',
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
    boilerplateImplementationExtension:
        'Ce boilerplate servira de base pour d’autres prompts de modélisation d’une architecture hexagonale.\n'
        '\n'
        '## 1. Stack :\n'
        '- NestJS (architecture modulaire)\n'
        '- Pino Logger via `nestjs-pino`\n'
        '- `zod` pour la validation\n'
        '- `neverthrow` pour la gestion fonctionnelle des erreurs\n'
        '- TypeScript strict\n'
        '- Fastify comme adapter HTTP\n'
        '\n'
        '## 2. Structure du projet :\n'
        '- `src/main.ts` (`Fastify` + `Pino` + global Zod pipe)\n'
        '- `src/app.module.ts`\n'
        '\n'
        '## 3. Futures fonctionnalités obligatoires :\n'
        '- DTO 100 % Zod (pas de `class-validator`)\n'
        '- Pipe global pour valider les inputs via Zod\n'
        '- Services retournant des `Result<Ok, Err>` via `neverthrow`\n'
        '- Logger Pino configuré avec :\n'
        '  - `prettyPrint` en dev\n'
        '  - JSON en prod\n'
        '  - correlation-id middleware de type `x-correlation-id` avec un `uuidv4` généré si absent\n'
        '\n'
        '## 4. Génère :\n'
        '- Les imports corrects\n'
        '- Un `package.json` minimal pour lancer le projet\n'
        '- Ajoute le log du port de l’application dans `main.ts`\n'
        '- Crée le fichier `Dockerfile` pour l’application\n'
        '- Crée le fichier `.dockerignore` avec `node_modules` et `dist`\n'
        '- Crée le fichier `npm-commands.md` avec les commandes npm possibles\n'
        '- Crée le fichier `.gitignore` avec `node_modules` et `dist`\n'
        '- Crée le fichier `.vscode/tasks.json` (VS Code) pour les tâches de debug, dev et build\n'
        '- Crée le fichier `README.md` avec les instructions pour lancer le projet\n'
        '- Le `tsconfig.json` n’a pas d’erreur en utilisant la dernière version de la norme\n'
        '- Crée le fichier `.env` avec les variables d’environnement suivantes :\n'
        '```dotenv\n'
        'PORT=3000\n'
        'NODE_ENV=development\n'
        'LOG_LEVEL=debug\n'
        'HOSTNAME=local-dev-pod\n'
        'PUBSUB_EMULATOR_HOST=127.0.0.1:8681\n'
        'PUBSUB_PROJECT_ID=my-local-project\n'
        'MONGODB_URI=mongodb://127.0.0.1:27017\n'
        'MONGODB_DB_NAME=\$currentApp\n'
        '```\n'
        '\n'
        '## 5. Contraintes techniques :\n'
        '- Code propre, lisible, modulaire\n'
        '- Pas de décorateurs inutiles\n'
        '- Pas de `class-validator` / `class-transformer`\n'
        '- Respect des conventions NestJS\n'
        '\n'
        '## 6. Anti-régression runtime (obligatoire) :\n'
        '- Ne pas dépendre implicitement de `emitDecoratorMetadata` pour l’injection en dev/watch.\n'
        '- Dans les contrôleurs, faire une injection explicite de service (ex. `constructor(@Inject(AppService) private readonly appService: AppService) {}`).\n'
        '- Conserver un pipe Zod global, mais pour les payloads critiques (`@Body`) appliquer aussi un schéma explicite sur la route (ex. `@Body(new ZodValidationPipe(EchoBodySchema))`) pour éviter les régressions de métadonnées selon le runner (`tsx`/`esbuild`).',
    boilerplateUnitTestExtension:
        '- Teste la validation des schémas de configuration au démarrage, les helpers `Neverthrow` partagés et l’adaptateur Logger (Pino) en mémoire.',
    devToolsImplementationExtension:
        '\n'
        '## Environnement Docker local\n'
        '- Crée un dossier à la racine `docker/mongo` contenant le fichier `docker-compose.yml` :\n'
        '```yaml\n'
        'services:\n'
        '  mongo:\n'
        '    image: mongo:latest\n'
        '    container_name: mongodb\n'
        '    ports:\n'
        '      - "27017:27017"\n'
        '    volumes:\n'
        '      - ./mongo-data:/data/db\n'
        '```\n'
        '\n'
        '- Crée un dossier à la racine `docker/pubsub` contenant le fichier `docker-compose.yml` :\n'
        '```yaml\n'
        'services:\n'
        '  pubsub:\n'
        '    image: google/cloud-sdk:latest\n'
        '    container_name: pubsub-emulator\n'
        '    command: >\n'
        '      gcloud beta emulators pubsub start\n'
        '      --project=my-local-project\n'
        '      --host-port=0.0.0.0:8681\n'
        '    ports:\n'
        '      - "8681:8681"\n'
        '    environment:\n'
        '      - PUBSUB_EMULATOR_HOST=0.0.0.0:8681\n'
        '\n'
        '  pubsub-ui:\n'
        '    image: ghcr.io/neoscript/pubsub-emulator-ui:latest\n'
        '    container_name: pubsub-emulator-ui\n'
        '    depends_on:\n'
        '      - pubsub\n'
        '    ports:\n'
        '      - "8086:80"\n'
        '    environment:\n'
        '      - PUBSUB_EMULATOR_HOST=pubsub:8681\n'
        '```',
    devToolsUnitTestExtension:
        '- Ajoute et exécute les tests de frontières architecturales vérifiant l’absence de dépendances d’infrastructure/framework dans `src/core/{{domain}}/` et la couverture minimale.',
    checkIntegrationImplementationExtension:
        'Tu es un expert TypeScript, NestJS.\n'
        'Intègre (ou mets à jour) les couches Infrastructure MongoDB, Application (usecase) et Interface HTTP du module `{{domain}}` dans l’application NestJS existante.\n'
        '\n'
        '## Contexte :\n'
        '- Le domaine et l’infrastructure `{{domain}}` existent déjà.\n'
        '- La couche `application`/usecase `{{domain}}` existe déjà.\n'
        '- La couche interface HTTP `{{domain}}` existe déjà.\n'
        '- Le repository MongoDB implémente le port du domaine via le token `XXXXX_REPOSITORY_PORT`.\n'
        '\n'
        '## À faire :\n'
        '1. Modifier `AppModule` (`src/app.module.ts`) pour importer :\n'
        '   - `MongooseModule.forRoot(...)` avec une configuration propre et centralisée\n'
        '   - L’infrastructure du module `{{domain}}`\n'
        '   - L’interface du module `{{domain}}`\n'
        '2. Vérifier que le repository MongoDB est bien injectable via `XXXXX_REPOSITORY_PORT` dans les use cases / handlers applicatifs.\n'
        '3. Vérifier que les providers nécessaires aux use cases sont bien câblés :\n'
        '   - `repository port`\n'
        '   - `logger port`\n'
        '   - `event bus applicatif`\n'
        '   - `read model port`\n'
        '4. Vérifier que la couche interface peut injecter correctement :\n'
        '   - `command bus / query bus`\n'
        '   - `handlers applicatifs`\n'
        '   - `adapters read model`\n'
        '   - `logger pino`\n'
        '   - `model Mongoose` nécessaire aux adapters\n'
        '5. Ajouter un contrôle d’injection explicite :\n'
        '   - S’assurer que tous les tokens exportés par les modules infrastructure sont bien exportés/importés là où ils sont consommés.\n'
        '   - Ajouter un contrôle simple au bootstrap ou au module pour détecter rapidement les dépendances manquantes.\n'
        '   - Éviter les injections implicites fragiles quand un token explicite est nécessaire.\n'
        '   - Si `emitDecoratorMetadata` est désactivé, utiliser `@Inject(...)` explicitement pour tous les providers sensibles (ex. `PinoLogger`, tokens `Symbol`, adapters, handlers injectés par classe si nécessaire).\n'
        '   - Importer explicitement `LoggerModule` dans les modules NestJS qui consomment `PinoLogger` (controllers, adapters, probes) ; ne pas supposer que l’import racine suffit toujours.\n'
        '   - Pour les schémas Mongoose imbriqués, ne pas utiliser directement une classe dans `@Prop({ type: ... })` si cela casse au runtime ; générer et utiliser les sous-schémas via `SchemaFactory.createForClass(...)`.\n'
        '   - Si un probe d’intégration dépend de tokens application + infrastructure, le déclarer dans le module qui importe effectivement tous ces tokens.\n'
        '6. Isolation du domaine :\n'
        '   - Ne pas ajouter de logique métier dans l’infrastructure.\n'
        '   - Ne pas toucher au domaine sauf si un ajustement de contrat est strictement nécessaire.\n'
        '   - Garder du TypeScript pur côté domaine et respecter la structure hexagonale.\n'
        '\n'
        '## Contraintes techniques :\n'
        '- NestJS uniquement dans l’infrastructure et l’interface.\n'
        '- MongoDB via Mongoose.\n'
        '- Les use cases / handlers applicatifs doivent rester sans dépendance NestJS.\n'
        '- Les DTO et mappings HTTP restent dans la couche interface.\n'
        '- Pas de logique de persistance dans le domaine.\n'
        '- Pas de logique métier dans les controllers.\n'
        '- Mettre des commentaires en français dans le code généré (JSDoc et commentaires explicatifs).\n'
        '\n'
        '## En-têtes de fichiers obligatoires (JSDoc IA en français par type de fichier d’intégration) :\n'
        'Chaque fichier créé ou modifié DOIT commencer par un commentaire JSDoc en français contenant `@module`, `@layer`, `@role`, `@boundaries`, `@collaborators` et `@ai-modification-guide` :\n'
        '- **Modules NestJS (`app.module.ts`, `{{domain}}.module.ts`, modules d’interface/infrastructure)** : `@layer` Integration / Wiring NestJS · `@role` Câblage explicite des modules (Infrastructure, Application handlers/buses, Interface) et export/import des tokens de ports · `@boundaries` Configuration DI NestJS uniquement, compatible `emitDecoratorMetadata: false` (injections explicites via `@Inject(...)`) · `@ai-modification-guide` lors de l’ajout d’un Handler, Port ou Controller, vérifier que son token est fourni, exporté par l’infrastructure et vérifié par la sonde (`probe`) d’injection au démarrage.\n'
        '- **Probes / Contrôles d’injection (`*.probe.ts` ou bootstrap check)** : `@layer` Integration - Runtime DI Verification · `@role` Vérifie au démarrage du runtime NestJS que tous les tokens de ports, handlers, loggers et modèles Mongoose sont correctement résolus · `@ai-modification-guide` ajouter dans cette sonde tout nouveau token critique introduit dans le module.',
    checkIntegrationUnitTestExtension:
        '- Exécute la batterie de vérification complète (`typecheck`, `lint`, `build`, tests unitaires et tests d’intégration/contrats) et corrige toute erreur de câblage.',
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

  /// Arborescence cible dédiée à *Boilerplate > Implémentation* (`{{domain}}`).
  final String boilerplateImplementationFolderStructure;

  /// Arborescence cible dédiée à *Boilerplate > Test unitaire* (`{{domain}}`).
  final String boilerplateUnitTestFolderStructure;

  /// Arborescence cible dédiée à *Dev Tools > Implémentation* (`{{domain}}`).
  final String devToolsImplementationFolderStructure;

  /// Arborescence cible dédiée à *Dev Tools > Test unitaire* (`{{domain}}`).
  final String devToolsUnitTestFolderStructure;

  /// Arborescence cible dédiée à *Check Integration > Implémentation* (`{{domain}}`).
  final String checkIntegrationImplementationFolderStructure;

  /// Arborescence cible dédiée à *Check Integration > Test unitaire* (`{{domain}}`).
  final String checkIntegrationUnitTestFolderStructure;

  /// Arborescence cible dédiée à *Playground > Implémentation* (`{{domain}}`).
  final String playgroundImplementationFolderStructure;

  /// Arborescence cible dédiée à *Playground > Test unitaire* (`{{domain}}`).
  final String playgroundUnitTestFolderStructure;

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

  /// Consignes spécifiques à *Boilerplate > Implémentation*.
  final String boilerplateImplementationExtension;

  /// Consignes spécifiques à *Boilerplate > Test unitaire*.
  final String boilerplateUnitTestExtension;

  /// Consignes spécifiques à *Dev Tools > Implémentation*.
  final String devToolsImplementationExtension;

  /// Consignes spécifiques à *Dev Tools > Test unitaire*.
  final String devToolsUnitTestExtension;

  /// Consignes spécifiques à *Check Integration > Implémentation*.
  final String checkIntegrationImplementationExtension;

  /// Consignes spécifiques à *Check Integration > Test unitaire*.
  final String checkIntegrationUnitTestExtension;

  /// Consignes spécifiques à *Playground > Implémentation*.
  final String playgroundImplementationExtension;

  /// Consignes spécifiques à *Playground > Test unitaire*.
  final String playgroundUnitTestExtension;

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
      (
        BuildTechStackSection.boilerplate,
        BuildTechStackSubRole.implementation,
      ) =>
        boilerplateImplementationFolderStructure,
      (BuildTechStackSection.boilerplate, BuildTechStackSubRole.unitTest) =>
        boilerplateUnitTestFolderStructure,
      (BuildTechStackSection.devTools, BuildTechStackSubRole.implementation) =>
        devToolsImplementationFolderStructure,
      (BuildTechStackSection.devTools, BuildTechStackSubRole.unitTest) =>
        devToolsUnitTestFolderStructure,
      (
        BuildTechStackSection.checkIntegration,
        BuildTechStackSubRole.implementation,
      ) =>
        checkIntegrationImplementationFolderStructure,
      (
        BuildTechStackSection.checkIntegration,
        BuildTechStackSubRole.unitTest,
      ) =>
        checkIntegrationUnitTestFolderStructure,
      (
        BuildTechStackSection.playground,
        BuildTechStackSubRole.implementation,
      ) =>
        playgroundImplementationFolderStructure,
      (BuildTechStackSection.playground, BuildTechStackSubRole.unitTest) =>
        playgroundUnitTestFolderStructure,
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
    (BuildTechStackSection.boilerplate, BuildTechStackSubRole.implementation) =>
      boilerplateImplementationExtension,
    (BuildTechStackSection.boilerplate, BuildTechStackSubRole.unitTest) =>
      boilerplateUnitTestExtension,
    (BuildTechStackSection.devTools, BuildTechStackSubRole.implementation) =>
      devToolsImplementationExtension,
    (BuildTechStackSection.devTools, BuildTechStackSubRole.unitTest) =>
      devToolsUnitTestExtension,
    (
      BuildTechStackSection.checkIntegration,
      BuildTechStackSubRole.implementation,
    ) =>
      checkIntegrationImplementationExtension,
    (BuildTechStackSection.checkIntegration, BuildTechStackSubRole.unitTest) =>
      checkIntegrationUnitTestExtension,
    (
      BuildTechStackSection.playground,
      BuildTechStackSubRole.implementation,
    ) =>
      playgroundImplementationExtension,
    (BuildTechStackSection.playground, BuildTechStackSubRole.unitTest) =>
      playgroundUnitTestExtension,
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
      boilerplateImplementationFolderStructure,
      boilerplateUnitTestFolderStructure,
      devToolsImplementationFolderStructure,
      devToolsUnitTestFolderStructure,
      checkIntegrationImplementationFolderStructure,
      checkIntegrationUnitTestFolderStructure,
      playgroundImplementationFolderStructure,
      playgroundUnitTestFolderStructure,
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
      boilerplateImplementationExtension,
      boilerplateUnitTestExtension,
      devToolsImplementationExtension,
      devToolsUnitTestExtension,
      checkIntegrationImplementationExtension,
      checkIntegrationUnitTestExtension,
      playgroundImplementationExtension,
      playgroundUnitTestExtension,
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
    String? boilerplateImplementationFolderStructure,
    String? boilerplateUnitTestFolderStructure,
    String? devToolsImplementationFolderStructure,
    String? devToolsUnitTestFolderStructure,
    String? checkIntegrationImplementationFolderStructure,
    String? checkIntegrationUnitTestFolderStructure,
    String? playgroundImplementationFolderStructure,
    String? playgroundUnitTestFolderStructure,
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
    String? boilerplateImplementationExtension,
    String? boilerplateUnitTestExtension,
    String? devToolsImplementationExtension,
    String? devToolsUnitTestExtension,
    String? checkIntegrationImplementationExtension,
    String? checkIntegrationUnitTestExtension,
    String? playgroundImplementationExtension,
    String? playgroundUnitTestExtension,
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
    boilerplateImplementationFolderStructure:
        boilerplateImplementationFolderStructure ??
        this.boilerplateImplementationFolderStructure,
    boilerplateUnitTestFolderStructure:
        boilerplateUnitTestFolderStructure ??
        this.boilerplateUnitTestFolderStructure,
    devToolsImplementationFolderStructure:
        devToolsImplementationFolderStructure ??
        this.devToolsImplementationFolderStructure,
    devToolsUnitTestFolderStructure:
        devToolsUnitTestFolderStructure ?? this.devToolsUnitTestFolderStructure,
    checkIntegrationImplementationFolderStructure:
        checkIntegrationImplementationFolderStructure ??
        this.checkIntegrationImplementationFolderStructure,
    checkIntegrationUnitTestFolderStructure:
        checkIntegrationUnitTestFolderStructure ??
        this.checkIntegrationUnitTestFolderStructure,
    playgroundImplementationFolderStructure:
        playgroundImplementationFolderStructure ??
        this.playgroundImplementationFolderStructure,
    playgroundUnitTestFolderStructure:
        playgroundUnitTestFolderStructure ??
        this.playgroundUnitTestFolderStructure,
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
    boilerplateImplementationExtension:
        boilerplateImplementationExtension ??
        this.boilerplateImplementationExtension,
    boilerplateUnitTestExtension:
        boilerplateUnitTestExtension ?? this.boilerplateUnitTestExtension,
    devToolsImplementationExtension:
        devToolsImplementationExtension ?? this.devToolsImplementationExtension,
    devToolsUnitTestExtension:
        devToolsUnitTestExtension ?? this.devToolsUnitTestExtension,
    checkIntegrationImplementationExtension:
        checkIntegrationImplementationExtension ??
        this.checkIntegrationImplementationExtension,
    checkIntegrationUnitTestExtension:
        checkIntegrationUnitTestExtension ??
        this.checkIntegrationUnitTestExtension,
    playgroundImplementationExtension:
        playgroundImplementationExtension ??
        this.playgroundImplementationExtension,
    playgroundUnitTestExtension:
        playgroundUnitTestExtension ?? this.playgroundUnitTestExtension,
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
    if (boilerplateImplementationFolderStructure.isNotEmpty)
      'boilerplateImplementationFolderStructure':
          boilerplateImplementationFolderStructure,
    if (boilerplateUnitTestFolderStructure.isNotEmpty)
      'boilerplateUnitTestFolderStructure': boilerplateUnitTestFolderStructure,
    if (devToolsImplementationFolderStructure.isNotEmpty)
      'devToolsImplementationFolderStructure':
          devToolsImplementationFolderStructure,
    if (devToolsUnitTestFolderStructure.isNotEmpty)
      'devToolsUnitTestFolderStructure': devToolsUnitTestFolderStructure,
    if (checkIntegrationImplementationFolderStructure.isNotEmpty)
      'checkIntegrationImplementationFolderStructure':
          checkIntegrationImplementationFolderStructure,
    if (checkIntegrationUnitTestFolderStructure.isNotEmpty)
      'checkIntegrationUnitTestFolderStructure':
          checkIntegrationUnitTestFolderStructure,
    if (playgroundImplementationFolderStructure.isNotEmpty)
      'playgroundImplementationFolderStructure':
          playgroundImplementationFolderStructure,
    if (playgroundUnitTestFolderStructure.isNotEmpty)
      'playgroundUnitTestFolderStructure': playgroundUnitTestFolderStructure,
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
    if (boilerplateImplementationExtension.isNotEmpty)
      'boilerplateImplementationExtension': boilerplateImplementationExtension,
    if (boilerplateUnitTestExtension.isNotEmpty)
      'boilerplateUnitTestExtension': boilerplateUnitTestExtension,
    if (devToolsImplementationExtension.isNotEmpty)
      'devToolsImplementationExtension': devToolsImplementationExtension,
    if (devToolsUnitTestExtension.isNotEmpty)
      'devToolsUnitTestExtension': devToolsUnitTestExtension,
    if (checkIntegrationImplementationExtension.isNotEmpty)
      'checkIntegrationImplementationExtension':
          checkIntegrationImplementationExtension,
    if (checkIntegrationUnitTestExtension.isNotEmpty)
      'checkIntegrationUnitTestExtension': checkIntegrationUnitTestExtension,
    if (playgroundImplementationExtension.isNotEmpty)
      'playgroundImplementationExtension': playgroundImplementationExtension,
    if (playgroundUnitTestExtension.isNotEmpty)
      'playgroundUnitTestExtension': playgroundUnitTestExtension,
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
      boilerplateImplementationFolderStructure: readFirst(
        'boilerplateImplementationFolderStructure',
      ),
      boilerplateUnitTestFolderStructure: readFirst(
        'boilerplateUnitTestFolderStructure',
      ),
      devToolsImplementationFolderStructure: readFirst(
        'devToolsImplementationFolderStructure',
      ),
      devToolsUnitTestFolderStructure: readFirst(
        'devToolsUnitTestFolderStructure',
      ),
      checkIntegrationImplementationFolderStructure: readFirst(
        'checkIntegrationImplementationFolderStructure',
      ),
      checkIntegrationUnitTestFolderStructure: readFirst(
        'checkIntegrationUnitTestFolderStructure',
      ),
      playgroundImplementationFolderStructure: readFirst(
        'playgroundImplementationFolderStructure',
      ),
      playgroundUnitTestFolderStructure: readFirst(
        'playgroundUnitTestFolderStructure',
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
      boilerplateImplementationExtension: readFirst(
        'boilerplateImplementationExtension',
      ),
      boilerplateUnitTestExtension: readFirst('boilerplateUnitTestExtension'),
      devToolsImplementationExtension: readFirst(
        'devToolsImplementationExtension',
      ),
      devToolsUnitTestExtension: readFirst('devToolsUnitTestExtension'),
      checkIntegrationImplementationExtension: readFirst(
        'checkIntegrationImplementationExtension',
      ),
      checkIntegrationUnitTestExtension: readFirst(
        'checkIntegrationUnitTestExtension',
      ),
      playgroundImplementationExtension: readFirst(
        'playgroundImplementationExtension',
      ),
      playgroundUnitTestExtension: readFirst('playgroundUnitTestExtension'),
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
          other.boilerplateImplementationFolderStructure ==
              boilerplateImplementationFolderStructure &&
          other.boilerplateUnitTestFolderStructure ==
              boilerplateUnitTestFolderStructure &&
          other.devToolsImplementationFolderStructure ==
              devToolsImplementationFolderStructure &&
          other.devToolsUnitTestFolderStructure ==
              devToolsUnitTestFolderStructure &&
          other.checkIntegrationImplementationFolderStructure ==
              checkIntegrationImplementationFolderStructure &&
          other.checkIntegrationUnitTestFolderStructure ==
              checkIntegrationUnitTestFolderStructure &&
          other.playgroundImplementationFolderStructure ==
              playgroundImplementationFolderStructure &&
          other.playgroundUnitTestFolderStructure ==
              playgroundUnitTestFolderStructure &&
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
          other.persistenceUnitTestExtension == persistenceUnitTestExtension &&
          other.boilerplateImplementationExtension ==
              boilerplateImplementationExtension &&
          other.boilerplateUnitTestExtension == boilerplateUnitTestExtension &&
          other.devToolsImplementationExtension ==
              devToolsImplementationExtension &&
          other.devToolsUnitTestExtension == devToolsUnitTestExtension &&
          other.checkIntegrationImplementationExtension ==
              checkIntegrationImplementationExtension &&
          other.checkIntegrationUnitTestExtension ==
              checkIntegrationUnitTestExtension &&
          other.playgroundImplementationExtension ==
              playgroundImplementationExtension &&
          other.playgroundUnitTestExtension == playgroundUnitTestExtension;

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
    boilerplateImplementationFolderStructure,
    boilerplateUnitTestFolderStructure,
    devToolsImplementationFolderStructure,
    devToolsUnitTestFolderStructure,
    checkIntegrationImplementationFolderStructure,
    checkIntegrationUnitTestFolderStructure,
    playgroundImplementationFolderStructure,
    playgroundUnitTestFolderStructure,
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
    boilerplateImplementationExtension,
    boilerplateUnitTestExtension,
    devToolsImplementationExtension,
    devToolsUnitTestExtension,
    checkIntegrationImplementationExtension,
    checkIntegrationUnitTestExtension,
    playgroundImplementationExtension,
    playgroundUnitTestExtension,
  ]);
}
