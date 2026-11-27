# super_spec_forge

Application Flutter Desktop et bibliothèque Dart de conception de cahier des charges, d'objets métiers et de règles de gestion à partir d'une idée, guidée par un wizard multi-étapes d'agents IA spécialisés.

La barre d’application indique la page visible (`Spec › Projets`), l’étape et le projet dans le wizard (`Lexique métier — Atlas`), ou la sélection dans Design (`Modèles & Contrats › Client`). Le workspace actif reste affiché à droite.

## Étapes du wizard IA de spécification métier

1. **Lexique métier** (`Ubiquitous Language Expert`) : définition des termes canoniques, synonymes à unifier, sigles et conventions de vocabulaire.
2. **Cadrage & Acteurs** (`Product Strategist`) : clarification de l'idée, objectifs, personas, contraintes et hors-périmètre.
3. **Cahier des charges** (`Business Analyst`) : modules fonctionnels, exigences (MoSCoW), cas d'usage et exigences non fonctionnelles.
4. **Objets métiers** (`Domain Modeler`) : entités structurées JSON Schema avec sous-objets, attributs typés (≤ 200/objet, ≤ 200 lignes/tableau), relations (`1:1`, `1:N`, `N:M`) et cycles de vie.
5. **Example Mapping** (`Example Mapper`) : atelier BDD à 4 couleurs (Story **Jaune**, Règles **Bleues**, Exemples concrets **Verts**, Questions ouvertes **Rouges**) pour affiner les objets métiers, injecter des exemples JSON Schema, promouvoir des règles en `RG-xxx` et alimenter les fixtures/Gherkin QA.
6. **Règles de gestion** (`Rule Architect`) : règles `RG-xxx` de validation, calcul, transition d'état, permission et déclencheur (`Quand / Si / Alors`).
7. **Revue & Export** (`Consistency Auditor`) : analyse de cohérence inter-étapes, export des livrables, **promotion sélective des objets métiers vers l'espace Design** (choix du domaine cible, du type DSL et de la résolution de conflit par objet) et passerelle directe vers le **Wizard UX & Parcours** ou **BDD / TDD**.

## Wizard UX & Parcours (4 étapes en aval)

Accessible dans l'onglet **Spec** via la carte **Wizard UX & Parcours** ou le bouton **Poursuivre vers le Wizard UX** à l'étape 6, ce second wizard exploite directement le `SpecForgeProject` actif (personas, cas d'usage, exigences, objets métiers et règles `RG-xxx`) et permet un enrichissement additif non destructif (`additive_safe`) des objets/attributs métiers et des règles `RG-xxx` :

1. **Parcours utilisateurs & Flows** (`User Journey Architect`) : parcours bout-en-bout (`JRN-xxx`), étapes séquentielles, embranchements et critères de succès par persona et canal cible.
2. **Architecture & Navigation** (`Information Architect`) : configuration du shell applicatif, identité visuelle avec aperçu live Material 3 (clair/sombre) & typographie, arborescence des routes typées (`EditorPageType`) et matrice d'accès par rôle.
3. **Écrans, Zones & Interactions** (`Interaction & Screen Designer`) : fiches d'écrans (`SCR-xxx`), schéma visuel interactif des 5 zones (`north`, `west`, `center`, `east`, `south`), blocs composants liés aux objets/attributs métiers, actions `RG-xxx` et états UX (vide, chargement, erreur, lecture seule).
4. **Audit UX & Export SuperDesigner** (`UX Auditor & Handoff Lead`) : audit croisé Métier↔UX (`UxCoherenceAnalyzer`), prompt clé-en-main pour le Vibe Chat (`prompt_super_designer.md`), schémas et repositories JSON (`json_schemas/*.schema.json`, `repositories/*.json`, `repositories_bundle.json`, `schema_light.yaml`), spécification UX Markdown (`specification_ux.md`), charte `DESIGN.md` et génération complète dans le dossier d'application sandboxée (`EditorPageCatalog`, thème `appearance.json` et squelettes d'écrans `SuperLayout` dans `pages/*.json` pré-liés aux `repositories/`).

## Wizard BDD / Gherkin & TDD (4 étapes en aval)

Accessible dans l'onglet **Spec** via la carte **Wizard BDD / Gherkin & TDD** ou les boutons passerelles en fin des Wizards 1 et 2, ce troisième wizard couvre aussi bien les projets Backend/API sans UI que les projets Full-Stack avec écrans UX :

1. **Jeux de données & Cas aux limites** (`Test Strategist & Fixture Designer`) : fixtures déterministes (`FIX-xxx`) nominales, valeurs aux bornes JSON Schema, cas d'erreur et habilitations, avec génération 1-clic depuis les schémas.
2. **Features Gherkin BDD (`.feature`)** (`BDD & Gherkin Architect`) : fonctionnalités (`FEAT-xxx`), `Contexte`, `Scénario` et `Plan du Scénario` + table `Exemples` en français par défaut (`# language: fr` + sélecteur `FR / EN`), tags normalisés (`@exf`, `@rg`, `@jrn`, `@scr`) et génération 1-clic depuis les cas d'usage et parcours UX.
3. **Suites TDD Unitaires & Contrats** (`TDD & Contract Engineer`) : suites (`TDD-xxx`) et cas atomiques `Arrange / Act / Assert` (`TC-xxx`) ordonnés en progression *Red → Green → Refactor* avec génération 1-clic depuis les règles `RG-xxx`.
4. **Couverture 360° & Export BDD/TDD** (`QA Coverage Auditor & Export Lead`) : audit croisé Métier + UX ↔ Tests (`QaCoherenceAnalyzer`) et export sur disque (sans HTML) de `features/*.feature`, `fixtures/*.json`, `fixtures_bundle.json`, `specification_bdd_tdd.md`, `specification_qa.json` et `prompt_tdd_agent.md`.

## Persistance par dossier & intégration Git

Les données sont stockées dans un **dossier Workspace sélectionnable** (par défaut `~/.super_spec_forge`, ou tout dépôt Git choisi via le sélecteur de workspace dans la barre d'application) :

```text
<workspace>/
├── .gitignore                          # Généré si absent (.local/, exports/, *.tmp.*)
├── workspace.json                      # Métadonnées du workspace
├── .local/state.json                   # Dernier projet actif sur cette machine (ignoré par Git)
├── glossary/
│   ├── glossary.json                   # Conventions & ambiguïtés
│   ├── chat.json                       # Historique du chat IA du glossaire
│   └── terms/<slug>.json               # 1 fichier par terme
├── dictionary/
│   ├── preferences.json                # Préférences globales de modélisation
│   └── rules/<slug>.json               # 1 fichier par règle technique
├── domains/
│   └── catalog.json                    # Domaines, environnements, services, configurations & audit
└── projects/<project-slug>/
    ├── project.json                    # Métadonnées du projet
    ├── spec/
    │   ├── lexicon.json
    │   ├── vision.json
    │   ├── cahier_des_charges.json
    │   ├── model_preferences.json
    │   ├── coherence_issues.json
    │   ├── business_objects/<slug>.json
    │   ├── example_maps/<slug>.json
    │   └── business_rules/<slug>.json
    ├── ux/
    │   ├── navigation.json             # Shell, routes & thème visuel UX
    │   ├── coherence_issues.json       # Diagnostics UX
    │   ├── journeys/<slug>.json        # 1 fichier par parcours (JRN-xxx)
    │   └── screens/<slug>.json         # 1 fichier par écran (SCR-xxx)
    ├── qa/
    │   ├── meta.json                   # Étape QA active & langue Gherkin (fr/en)
    │   ├── coherence_issues.json       # Diagnostics de couverture QA
    │   ├── fixtures/<slug>.json        # 1 fichier par jeu d'essai (FIX-xxx)
    │   ├── features/<slug>.json        # 1 fichier par feature Gherkin (FEAT-xxx)
    │   └── tdd_suites/<slug>.json      # 1 fichier par suite TDD (TDD-xxx)
    ├── chats/                          # Historiques IA par étape (Spec, UX, QA & global)
    └── attachments/                    # Pièces jointes dédupliquées
```

## Gestion des domaines

L'onglet **Design → Gestion des domaines** permet de gérer les domaines
fonctionnels, leurs environnements logiques, les microservices, les variables
de configuration et les secrets. Les codes sont validés en `kebab-case`, les
clés de configuration en `UPPER_SNAKE_CASE`. Le clonage copie les variables
en clair et crée les secrets en attente de réinitialisation. L'export `.env`
omet les valeurs secrètes et les remplace par des placeholders.

Les valeurs secrètes sont chiffrées en AES-256-GCM. La clé est conservée dans
le coffre sécurisé du système et n'est pas incluse dans le workspace : un
workspace déplacé sur une autre machine ne permet donc pas de déchiffrer ses
secrets sans mécanisme de migration de clé. Le catalogue garde un journal
append-only au niveau de l'application. L'authentification, les rôles
DevOps/SRE, l'adresse IP et le User-Agent ne sont pas disponibles dans cette
application locale et ne sont donc pas simulés.

Dans **Design → Modèles & Contrats**, cliquez sur le domaine en bleu dans le
fil d’Ariane, puis sur le badge du domaine voulu. Les badges proviennent du
catalogue du workspace actif. Si le catalogue est vide, le bouton
**Gestion des domaines** de la page permet d’en créer. Les segments du modèle
et de sa version ne sont affichés que lorsque sa fiche est ouverte. Dans le
fil d’Ariane, l’icône de grille revient au menu Design et la flèche remonte
d’un niveau : de la fiche à la liste, puis de la liste au menu Design.

Le volet **Modèles métiers** (SuperCode) commence avec quatre rubriques vides :
`models`, `components`, `dto` et `message`. Saisissez des entrées indentées
(par exemple `vente: model` ou `reponse: xresponsedto`)
Le moteur `super_schema_dsl` valide et enregistre le texte automatiquement
après la saisie : en cas d’erreur, le message s’affiche dans la zone d’erreur
en bas de l’éditeur SuperCode et le dernier arbre valide reste affiché. Dans
la colonne gauche du catalogue, le badge à droite du nom permet de
choisir le type : `model`, `part`, `component`, `createxdto`, `updatexdto`,
`xresponsedto`, `xlistitemdto`, `xquerydto`, `eventxpayloaddto`, `eventxenvelopedto`
ou `flatfile`. Le titre, les quatre états et la version restent dans la colonne de droite.
Le texte et les propriétés sont enregistrés dans le domaine du workspace.
Une poignée verticale sépare l’éditeur DSL et le catalogue, comme entre le
chat et le contenu des écrans Spec : faites-la glisser pour redimensionner les
volets, ou double-cliquez dessus pour revenir à la proportion par défaut
(30 % pour le DSL). Cette largeur est conservée quand vous changez de domaine.
Le nom souligné d’une entrée du catalogue ouvre sa fiche (type, titre,
rubrique, version et états) dans la page suivante d’un `PageView` piloté par
le fil d’Ariane, qui devient *domaine › Liste des modèles et contrats › nom ›
version*. Cliquez sur « Liste des modèles et contrats » ou sur la flèche pour
revenir à la liste, où le brouillon DSL est conservé. Changer de domaine ramène à la liste.
La fiche reprend l’étape Spec **Objets métier** pour un seul objet : à gauche,
un chat IA (Gemini) crée et modifie les attributs du modèle, pose des questions
de clarification et accepte des pièces jointes ; à droite, trois onglets alignés
sur l’étape Objets métier du wizard Spec : **Objet** (`SuperTreeView` et
inspecteur avec description, jauge, aperçu JSON Schema, ajout, modification et
suppression d’attributs), **Repository** (`SpecJsonSchemaViewerView` : inspecteur
JSON Schema Draft 2020-12, bac à sable Seed validé en direct et documentation
HTML5) et **DSL** (éditeur `CodeEditor` YAML « JSON Schemas Light » avec
validation en direct, boutons « Réinitialiser » et « Appliquer le YAML »). Un attribut
`reference` cible une autre entrée du domaine, désignée par son nom technique.
L’assistant applique les mêmes consignes que l’étape Objets métier
(`SpecStageAgent.attributeModelingRules` et `attributeExamplesJson`) :
dimensionnement, nommage, `schemaConstraints`, `x-mask`, `x-searchable`,
`x-database-index`, `x-enumNames`/`x-enumDescriptions` et `examples`. Chaque tour
reçoit aussi les préférences et règles actives du **Dictionnaire technique & Modèle**.
Le chat partage aussi le fonctionnement de l’étape Objets métier : un
sous-ensemble des outils `SpecForgeToolRegistry` (`DomainModelAiAgent.toolNames`,
appliqués au projet temporaire `DomainModelAiAgent.modelProject`), la sélection
d’un attribut (bloc « FOCUS COURANT », outil `focus_stage_or_object`), le
filtre de l’arbre (outil `filter_business_objects`), le glossaire d’entreprise,
les reprises automatiques, le bouton « Réessayer / Corriger », « + Questions » et
les traces d’outils. Les deux chats sont assemblés à partir des mêmes briques de
`widgets/spec_chat_widgets.dart` (`SpecChatMessageTile`, `SpecStreamingBubble`,
`SpecToolTracesSection`, `SpecChatComposer`).
Des poignées séparent le chat, l’arbre et l’inspecteur ; le chat se replie sur
un rail. L’objet et l’historique du chat sont enregistrés dans le domaine sous
l’ID de l’entrée (sans le contenu des pièces jointes).
Chaque entrée possède un ID stable attribué par `JsonModel` (`super_schema_dsl`) :
un bloc déplacé vers une autre rubrique, renommé, retypé ou coupé puis recollé
garde son titre, ses états, sa version, ses attributs et son chat. Les anciens catalogues, indexés par
chemin `rubrique.nom`, sont migrés au chargement.

Pour les entrées du domaine (`model`, `part`, `component`), l’en-tête de la fiche
expose également le bouton **« Couche Domain »** ouvrant une page de niveau 2
dans le fil d’Ariane (*domaine › Liste des modèles et contrats › nom › version › Couche Domain*).
Cette page combine un chat IA dédié (`DomainLayerAiAgent` — DDD & Architecture Hexagonale,
avec son propre historique persisté sous l’ID de l’entrée) et les **7 onglets**
de la couche Domain avec édition manuelle complète : **Invariants**,
**State changing**, **Query**, **Policy Services**, **Factory**, **Domain events**
et **Persistence policy** (port sortant Repository, frontière transactionnelle,
concurrence, suppression et méthodes du port).

L'onglet **Design → Cas d’usage & orchestration** reprend le même fil d’Ariane
contextualisé par le domaine en cours (partagé avec **Gestion des domaines**
et **Modèles & Contrats**) et combine un chat IA dédié à gauche
(`UseCaseOrchestrationAiAgent` — DDD, CQRS & Saga, nourri automatiquement par
les cas d’usage, exigences, règles `RG-xxx`, flux Event Storming du projet actif
et les contrats/couches Domain du domaine) avec un atelier à 3 onglets à droite :
**Cartographie** (par Bounded Context), **Use Cases** (10 sections, ports,
événements et scénarios `Given / When / Then`) et **Sagas & Compensations**
(diagrammes Mermaid, matrice de rollback à 8 colonnes et aperçu Markdown/Mermaid).

## Suivi Build par domaine

L'onglet **Build** du `NavigationRail` s'ouvre sur une page d'actions dédiée
(`BuildLinksView`), à l'image de **Spec** et **Design**, proposant deux entrées :
- **Gestion des Stack technique** (`BuildTechStacksView`) : éditeur complet des profils de stacks techniques, arborescences cibles, règles Markdown (avec bascule **Aperçu** / **Édition**) et **Documentation IA** ;
- **Génération des prompts agentiques** (`BuildDesignItemsView`) : affiche, pour le
domaine sélectionné dans le fil d'Ariane (`DesignDomainBreadcrumbBar`, synchronisé
avec l'espace **Design**), l'ensemble des items de conception porteurs des
quatre indicateurs d'avancement (`Conception`, `Validation`, `Code`, `Livraison`) :
- **Value Objects** (`ValueObjectSpec` du domaine et du `Shared Kernel`),
- **Modèles & Contrats** (toutes les entrées du catalogue `DomainContracts` : `model`, `part`, `component`, DTO, messages),
- **Cas d’usage** (`ApplicationUseCaseSpec`),
- **Sagas** (`OrchestrationSagaSpec`).

Une barre de recherche et de filtrage rapide (catégorie, étape, statut et évolution inter-itérations) permet
d'isoler les éléments à implémenter ou livrer, et un clic direct sur les icônes
d'étapes fait évoluer leur statut (`À faire → En cours → Terminé`) avec
persistance immédiate dans le domaine.

La sélection multiple d'items (`Value Objects`, `Modèles`, `Use Cases`, `Sagas`) active le bouton
**Sélection des Prompts IA**, qui ouvre dans le fil d'Ariane
(*Domaine › Items de design & avancement › Sélection des Prompts IA*) la vue
`BuildPromptsSelectionView` (`BuildHexaPromptGenerator`) regroupant :
- **Value Object** (2 prompts) : *Domain — Implémentation* et *Domain — Test unitaire* (matrice TDD issue des exemples valides/invalides et contraintes JSON Schema),
- **Modèle** (4 prompts) : *Domain — Implémentation*, *Domain — Test unitaire*, *Persistance — Implémentation* et *Persistance — Test unitaire*,
- **Use Case** (2 prompts) : *UseCase / Saga — Implémentation* et *UseCase / Saga — Test unitaire*,
- **Saga** (2 prompts) : *UseCase / Saga — Implémentation* et *UseCase / Saga — Test unitaire*,
- **Outbound, Inbound, Boilerplate, Dev Tools, Check Integration & Playground** (en bas de liste, sans rattachement) : 2 prompts chacun (*Implémentation* & *Test unitaire*).

Chaque prompt démarre par un bloc de métadonnées ```` ```yaml ... ``` ````
normalisé (`kind` `model-*` / `usecase-*` / `saga-*` / `outbound-*` / `inbound-*` / `boilerplate-*` / `dev-tools-*` / `check-integration-*` / `playground-*`, `name`, `title`,
`version` SemVer partagée entre Modèles, Use Cases et Sagas, `domain`,
`description`, `owner: <domain>-team`, `status: approved`, `tags`, `security`,
`ai`, `generation` auto-calculé — incluant `stack` lorsqu'une stack est affectée
au domaine — et `metadata` `created`/`updated` au format `YYYY-MM-DD`), embarque
les **JSON Schemas Draft 2020-12** des modèles (références résolues) et des
contrats `Input`/`Output` des Use Cases, et se termine par une section
d'**extensions paramétrables par stack technique** (`BuildTechStackProfile` :
stack technique globale, **Documentation IA** ajoutée à la toute fin de chaque prompt,
plus arborescence cible avec interpolation `{{domain}}` / `{{module}}` et consignes
spécifiques configurables sur les 9 parties **Domain**, **UseCase / Saga**,
**Outbound**, **Inbound**, **Persistance**, **Boilerplate**, **Dev Tools**,
**Check Integration** et **Playground**, chacune dotée de 2 sous-onglets
*Implémentation* et *Test unitaire*). Le profil **TypeScript / NestJS**
(`ts-nestjs`) est fourni par défaut et entièrement personnalisable dans un
éditeur complet depuis **Build › Gestion des Stack technique** ou directement
depuis le sélecteur de stack de **Génération des prompts agentiques**.

## Partage et synchronisation des objets métiers entre Features (`Spec`)

Chaque `SpecFeatureSpec` (`FEAT-01` MVP, `FEAT-02` Lot 2…) conserve sa propre copie isolée des objets métiers sur disque afin qu'un lot futur ne modifie jamais silencieusement une spécification déjà validée, tout en partageant l'identité canonique des entités via trois mécanismes :

1. **Import & Synchronisation 3-voies (`Feature ↔ Feature` et `Design → Spec`)** (`FeatureObjectSyncEngine`, `ImportSyncBusinessObjectsDialog`) :
   - Depuis l'étape **Objets métiers**, le bouton **« Importer / Synchroniser… »** permet d'importer ou de resynchroniser en 3-voies des objets depuis **une autre feature du projet** (en conservant leurs `id` et `technicalName` canoniques) ou depuis **un domaine fonctionnel Design** (projection inverse automatique des `ValueObjectSpec` scalaires et composites vers la Spec).
   - La photographie de référence `FeatureObjectSyncBaseline` est mémorisée dans `SpecFeatureSpec.objectSyncBaselines` (`spec/object_sync_baselines.json`) pour préserver les attributs propres à la feature cible lors des synchronisations ultérieures.
   - Côté Design, `SpecOriginBaseline.contributingFeatures` cumule toutes les features ayant successivement promu un même contrat (`FEAT-01, FEAT-02`).
2. **Gouvernance `additive_warn_on_validated` & Impacts croisés (`RG`, `UX`, `QA`)** (`CrossFeatureObjectAnalyzer`) :
   - Les enrichissements additifs (nouveaux attributs optionnels, nouvelles valeurs d'énumération, nouveaux états/transitions) sont libres entre features.
   - Toute divergence cassante vis-à-vis d'une feature **Validée** ou impactant les règles `RG-xxx`, écrans **UX** ou fixtures/tests **QA** d'une feature sœur remonte des badges d'alerte cliquables dans `BusinessObjectsEditorView`, la carte *Objets métiers & Partage inter-features* de `ProjectInitiativesView` et les diagnostics `COH-FEAT-001` / `COH-FEAT-002` de `SpecCoherenceAnalyzer`.
3. **Contexte IA inter-features** (`SpecPromptBuilder`, `list_sibling_features_business_objects`) :
   - Lorsqu'un projet comporte plusieurs features, le référentiel des objets métiers des features sœurs est injecté en lecture seule dans les prompts IA et inspectable via l'outil `list_sibling_features_business_objects` afin de réutiliser les identifiants canoniques sans doublons divergents.

## Gestion des évolutions inter-itérations (Spec → Design → Build)

1. **Merge 3-voies Spec → Design & détection de dérive amont** (`SpecDesignMergeEngine`, `SpecDesignDriftAnalyzer`) :
   - Chaque contrat promu conserve sa référence d'origine (`SpecOriginBaseline` dans `ContractDetails.specOrigin`).
   - Lors d'une re-promotion en itération N+1 (`PromoteBusinessObjectsDialog`), le mode par défaut **Fusionner (conserver Design)** applique les ajouts/modifications/suppressions de la Spec tout en préservant les liaisons vers les `ValueObjectSpec`, les attributs techniques exclusifs au Design et les index/contraintes `x-database-index` / `x-searchable` / `x-mask`, avec aperçu détaillé du merge avant validation.
   - Les contrats ou références `RG-xxx` / `EXF-xxx` / `UC-xxx` modifiés côté Spec sont signalés dans **Modèles & Contrats** et **Cas d’usage & orchestration**.
2. **Jalons d'itération par domaine, SemVer assisté & Graphe d'impact** (`DomainIterationSnapshot`, `DesignEvolutionAnalyzer`) :
   - La barre de jalon (`DomainIterationSnapshotBar`) permet de figer explicitement chaque itération d'un domaine (*Figer un jalon…*, ex. `Itération 1 — MVP`, capturant Modèles, Couches Domain, Value Objects du domaine et du Shared Kernel, Use Cases et Sagas) et de comparer à tout moment l'état courant à un jalon de référence.
   - Chaque modification est qualifiée (`Patch`, `Mineur`, `Majeur / Breaking`) avec bouton 1-clic de **Bump SemVer suggéré** et propagation transitive d'impact (`Shared/Domain ValueObject → ValueObjects composites → Modèles/Contrats → Use Cases → Sagas`).
3. **Suivi Build non intrusif (`badge_only`) & Prompts IA Delta (`vN → vN+1`)** :
   - Les 4 indicateurs d'étapes (`Conception`, `Validation`, `Code`, `Livraison`) ne sont jamais rétrogradés automatiquement : des badges explicites (`Nouveau`, `Δ Modifié`, `⇄ Impacté`), un bandeau des artefacts supprimés à décommissionner, un filtre rapide *Évolués* et une sélection en 1 clic signalent les écarts depuis le jalon actif.
   - Dans **Sélection des Prompts IA**, le sélecteur de mode (**Auto selon jalon**, **Delta `vN → vN+1`**, **Complet from scratch**) injecte automatiquement dans les prompts concernés la section **Évolution Inter-Itérations & Consignes de Migration** (changelog structuré, impacts amont, migrations de persistance et adaptation non régressive des tests unitaires).

## Lancement & Validation

```powershell
cd packages\super_spec_forge
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Installateur Windows (Inno Setup)

Prérequis : Visual Studio avec les outils C++ de bureau et Inno Setup 6 (`winget install --id JRSoftware.InnoSetup --exact`).
Depuis la racine du dépôt :

```powershell
.\installer\build-installer.ps1 -App SuperSpecForge
```

L'installateur généré est créé dans `..\..\build\installer\SuperSpecForge-<version>-windows-x64-setup.exe` (à partir du script [SuperSpecForge.iss](../../installer/SuperSpecForge.iss)) et installe l'application dans `%LOCALAPPDATA%\Programs\SuperSpecForge` sans élévation.

