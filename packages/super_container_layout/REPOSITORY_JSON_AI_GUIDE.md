# Guide pour IA : Modéliser, typer et peupler les Repositories JSON (`super_container_layout`)

Ce document est la spécification technique normative destinée à une Intelligence Artificielle. Il définit comment **concevoir, structurer, typer et peupler des Repositories JSON** dans `super_container_layout`, et comment coordonner en une seule réponse les données (`"repositories"`) et l'interface GenUI (`"vibe"`) sans erreur de validation ni incohérence de rendu.

Il complète [`SCREEN_JSON_AI_GUIDE.md`](SCREEN_JSON_AI_GUIDE.md) (grammaire des composants, styles et états), [`BEHAVIOR_JSON_AI_GUIDE.md`](BEHAVIOR_JSON_AI_GUIDE.md) (événements, validateurs, actions, `CollectionViewTransform` et scripts QuickJS) et [`SCREEN_DESIGN_AI_GUIDE.md`](SCREEN_DESIGN_AI_GUIDE.md) (Design System Material 3 Desktop).

> **Règle stricte (« zéro hallucination »)** : respecte à la lettre les contraintes de `JsonRepositoryStore`, `JsonAttributePath`, `JsonTextBinding`, `CalculatedAttributeEngine`, `VibeRepositoryApplier` et `AppearanceTransfer.applyVibe` documentées ci-dessous. N'invente ni syntaxe JSONPath, ni clé commençant par `@` dans les données stockées, ni identifiant hexadécimal forgé à la main.

---

## 1. Protocole d'émission Vibe (`"repositories"` + `"vibe"`)

### 1.1. Enveloppe de réponse JSON du Chat Vibe

Lorsqu'une demande nécessite de créer un repository, d'enrichir son schéma ou de modifier ses données (avec ou sans mise à jour de l'écran), renvoie un unique objet JSON conforme à la structure suivante :

```json
{
  "message": "Résumé court et clair en français...",
  "repositories": {
    "<idOuAlias>": {
      "name": "Nom lisible du repository",
      "mode": "merge",
      "data": {
        "...": "..."
      },
      "calculatedAttributes": [
        {
          "name": "montantHt",
          "scope": "articles[?]",
          "code": "(row.quantite ?? 0) * (row.prixUnitaire ?? 0)"
        }
      ],
      "jsonSchema": {
        "type": "object",
        "required": ["articles"],
        "properties": {
          "articles": { "type": "array" }
        }
      }
    }
  },
  "vibe": {
    "...": "..."
  }
}
```

- **JSON Schema associé (`"jsonSchema"` & outil `manage_repository_json_schema`)** :
  - Lorsqu'un repository de `REPOSITORIES DISPONIBLES` expose un champ `"jsonSchema"` (JSON Schema Draft 7 / Draft 2020-12), toute écriture est validée de manière **stricte et bloquante** par `JsonSchemaValidator` (`JsonSchemaValidationException`) : respecte impérativement tous les types, champs `required`, `enum`, bornes numériques, `format` et `additionalProperties` du schéma.
  - Tu peux fournir la clé optionnelle `"jsonSchema"` dans l'enveloppe d'une entrée de `"repositories"` (objet JSON Schema standard, ou `null` pour dissocier) lorsqu'on te demande de définir ou modifier le schéma de validation d'un repository (sauf si le schéma est figé dans le code via `RepositoryImpl.jsonSchema`).
  - Tu peux aussi utiliser le tool `manage_repository_json_schema` (`action`: `get` | `infer` | `validate` | `create` | `update` | `delete`) pendant ton raisonnement pour lire, inférer, tester ou modifier le schéma d'un repository existant (participatif à la transaction du tour, avec `validateCurrentDocument: false` si tu mets à jour les données dans le même tour), et `query_repository_data` pour lire son `jsonSchema` courant.
  - Tout `SuperValue` texte lié (`useRepositorySchema: true` par défaut) hérite automatiquement les contraintes (`type`, `required`, `minLength`, `maxLength`, `pattern`, `format`, `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`, `enum`, `const`) et masques/formats (`x-mask`, `x-maskIncludeLiterals`, `x-dateFormat`, `x-decimalDigits`, `x-decimalSeparator`, `x-thousandsSeparator`, `x-validationMessage`, ainsi que la déduction automatique pour `format`: `"date"` / `"date-time"` / `"time"`) de l'attribut ciblé dans le `jsonSchema` du repository.
  - **Règle stricte pour les dates (`"format": "date"` / `"date-time"`)** : stocke **toujours** les dates au format ISO 8601 dans `"data"` (`"2026-05-19"` pour `"date"`, `"2026-05-19T14:30:00Z"` pour `"date-time"`), et utilise uniquement `"format": "date"` (ou `"date-time"`) dans le `jsonSchema` **sans** `x-mask` manuel redondant ni `pattern` regex de type `dd/MM/yyyy` (le moteur gère automatiquement le masque d'affichage/saisie `##/##/####` + `dd/MM/yyyy` et reconvertit vers ISO à l'écriture).

- **Mise à jour portant uniquement sur les données** : si l'IHM n'a pas besoin d'être modifiée (ajout de lignes d'exemple, correction de valeurs, enrichissement d'une nomenclature déjà liée), omets `"vibe"` ou définis `"vibe": null`.
- **Forme explicite recommandée vs raccourci toléré** :
  - **Recommandé** : utilise systématiquement l'enveloppe explicite `{"name": "...", "mode": "merge" | "replace", "data": { ... }}`.
  - **Raccourci toléré** : si la valeur associée à `<idOuAlias>` dans `"repositories"` est directement un objet JSON métier sans enveloppe `{"name", "mode", "data"}`, le moteur (`VibeRepositoryApplier`) l'interprète automatiquement comme `{"mode": "merge", "data": <objet>}`.
- **Modes d'écriture (`"mode"`)** :
  - `"merge"` (**mode par défaut**, à privilégier) : fusionne récursivement les sous-objets JSON (`Map<String, Object?>`), remplace les tableaux (`List`) et scalaires explicitement mentionnés dans `"data"`, et **conserve intactes toutes les clés existantes omises** à chaque niveau d'objet.
  - `"replace"` : remplace **intégralement** le document racine du repository par l'objet `"data"` fourni (toute clé existante absente de `"data"` est supprimée). À n'utiliser que sur demande explicite de réinitialisation complète.

### 1.2. Ordre d'émission obligatoire pour le streaming SSE live

Le parseur incrémental (`VibeIncrementalStreamParser`) décode et applique le flux SSE en temps réel. Tu **dois impérativement** émettre les clés de premier niveau dans cet ordre exact :

1. **`"message"` EN PREMIER** : affiché instantanément mot par mot dans la bulle du chat.
2. **`"repositories"` EN DEUXIÈME** (toujours **avant** `"vibe"`) : garantit que les nouveaux repositories et leurs données sont créés, fusionnés et chargés dans `JsonRepositoryStore` **avant** que les composants liés du patch `"vibe"` ne s'instancient en direct à l'écran (aucun flash vide ni erreur de repository introuvable pendant le streaming).
3. **`"vibe"` EN TROISIÈME** (si l'écran change), ordonné en `pageCatalog` / thème global $\rightarrow$ `styles` $\rightarrow$ `components` (de haut en bas, Top-Down) $\rightarrow$ `behaviors` et `usages`.

### 1.3. Règles strictes sur les identifiants (`<idOuAlias>`)

Consulte toujours la section **`REPOSITORIES DISPONIBLES`** présente dans le contexte du tour courant :

1. **Réutiliser un repository existant pertinent** :
   - Si `REPOSITORIES DISPONIBLES` contient déjà un repository correspondant au domaine métier demandé, **réutilise son `id` exact** tel qu'indiqué dans le contexte :
     - soit l'identifiant technique de **32 caractères hexadécimaux** (`^[0-9a-f]{32}$`, ex. `"4f8a2c91e0b347d6a1c58e920b4f7d13"`) d'un repository fichier existant ;
     - soit l'identifiant `snake_case` (`^[a-z0-9_]{1,32}$`, ex. `"pan_model_repository"`) d'un `RepositoryImpl` fourni par l'application hôte (note : le `"name"` d'un repository applicatif en mémoire est immuable ; en `"merge"`, tu peux omettre `"name"` ou répéter son nom courant).
2. **Créer un nouveau repository fichier via un alias symbolique** :
   - Choisis un **alias symbolique lisible en `snake_case`** respectant `^[a-z0-9_]{1,32}$` (ex. `"crm_clients"`, `"catalogue_produits"`, `"suivi_chantiers"`).
   - Fournis un `"name"` lisible pour l'utilisateur (ex. `"CRM Clients"`).
   - Référence **directement cet alias** dans toutes les liaisons du patch `"vibe"` du même tour :
     - forme chaîne préfixée : `"crm_clients:clients"`, `"crm_clients:clients[?].nom"` ;
     - ou forme objet : `{"repositoryId": "crm_clients", "path": "clients[?].nom"}`.
   - **Réécriture automatique par le moteur** : `VibeRepositoryApplier` crée le fichier `<name>.json` et son fichier compagnon `<name>.json.id` contenant un véritable identifiant aléatoire de 32 caractères hexadécimaux, puis **réécrit automatiquement toutes les occurrences de l'alias** dans `"vibe"` (`components`, `styles`, `behaviors`, `states`, `propertyBindings`, `optionsBinding`) vers cet ID 32 hex réel avant d'appeler `AppearanceTransfer.applyVibe`.
   - **Interdiction absolue** : ne tente **jamais** d'inventer ou de générer à la main une chaîne de 32 caractères hexadécimaux pour un repository qui ne figure pas déjà dans `REPOSITORIES DISPONIBLES`.
3. **Absence de `JsonRepositoryStore` actif** :
   - Si aucune section `REPOSITORIES DISPONIBLES` ne figure dans le prompt (l'application hôte n'a monté aucun `JsonRepositoryStore`), **n'émets pas** la clé `"repositories"`, ne crée aucun `binding`, et renseigne des valeurs statiques réalistes (`text` / `value` / `options`) accompagnées de `"usages": { "<id>": { "kind": "dynamicData" } }`.

---

## 2. Invariants et contraintes syntaxiques strictes (`JsonRepositoryStore` & `JsonAttributePath`)

Toute violation de l'une des règles ci-dessous lève immédiatement une `FormatException` dans `JsonRepositoryStore` ou `JsonAttributePath` et annule l'application du tour :

1. **Racine obligatoirement Objet JSON (`Map<String, Object?>`)** :
   - `"data"` doit **toujours** être un objet JSON `{ ... }` à la racine.
   - Un tableau `[...]` ou une valeur scalaire (`"texte"`, `42`, `true`, `null`) à la racine du document est formellement rejeté. Encapsule toujours une liste principale sous une clé nommée (ex. `{"clients": [...]}`).
2. **Noms de clés JSON compatibles avec `JsonAttributePath`** :
   - À **toutes les profondeurs** de l'arbre JSON (racine, objets imbriqués, éléments de tableaux), un nom de clé ne doit contenir **aucun** des caractères suivants :
     - point `.`
     - crochets `[` ou `]`
     - point d'interrogation `?`
     - espace ou caractère blanc (`\s`, tabulation, retour à la ligne)
   - **Convention recommandée** : utilise exclusivement du **`camelCase` ASCII** sans accent ni ponctuation (`nomClient`, `montantHt`, `dateEcheance`, `facturationAuto`).
3. **Réserve absolue du préfixe `@` (attributs calculés en lecture seule)** :
   - **Aucune clé JSON stockée** dans `"repositories.*.data"` (à la racine comme dans un sous-objet ou un élément de tableau) ne peut commencer par `@`. Une clé `"@total"` dans `"data"` provoque une erreur de collision avec `CalculatedAttributeEngine`.
   - Le préfixe `@` (`"@totalHt"`, `"@stats.marge"`, `"articles[?].@montant"`) est **strictement réservé aux attributs calculés** :
     - soit enregistrés côté Dart via `RepositoryImpl.addCalculatedAttribute` ;
     - soit définis en JavaScript (QuickJS) via la clé optionnelle `"calculatedAttributes"` de l'enveloppe `"repositories"` (persistés dans `calculated/<id>.json`).
   - **Format d'une définition JavaScript dans `"calculatedAttributes"`** :
     - `{"name": "<nom>", "scope": "<tableau[?]>" (optionnel), "code": "<JS>", "description": "<texte>" (optionnel)}`.
     - Le code JS reçoit `(row, ctx, doc)` : `row` désigne la ligne courante (ou le document racine sans `scope`), `doc` le document racine et `ctx.get(chemin, repoId?, defaut?)` / `ctx.getNum(...)` lit un autre chemin ou `@calcul` avec suivi automatique des dépendances.
   - **Contrat IA sur `@calcul`** :
     - Tu peux lier un composant **en lecture seule** (`SuperValue` en `mode: "display"`, `SuperListView` sans `allowAdd`/`allowRemove`, `SuperTable` en consultation, `SuperChart`, `SuperConditional`, `states.binding`, `propertyBindings`, `onTooltip`) à un chemin `@...` s'il figure déjà dans `calculatedAttributes` de `REPOSITORIES DISPONIBLES` **ou** s'il vient d'être déclaré dans `"calculatedAttributes"` du même tour.
     - N'invente jamais un `@calcul` non déclaré.
     - Ne lie **jamais** un contrôle d'écriture (`SuperValue` en `mode: "input"`, `checkbox`/`switch` modifiable, `choice`, `Expansible.binding`, `Menu.binding`, `SuperTab` statique bidirectionnel, `allowAdd: true`, `allowRemove: true`) à un chemin contenant un segment `@...`.
   - **Écritures par script de comportement** : un comportement `"runJavaScript"` peut modifier les données ordinaires du repository via `ctx.set("chemin", valeur)` ; son `doc` est en lecture seule. Les écritures sont groupées, validées par le JSON Schema et enregistrées atomiquement. Les chemins contenant un segment `@...` sont refusés, même via `ctx.set` : aucun attribut calculé n'est modifiable.
4. **Grammaire stricte des chemins (`JsonAttributePath` $\neq$ JSONPath)** :
   - Seuls les segments séparés par `.` et les indices entiers positifs `[0]`, `[1]` ou jokers `[?]` sont acceptés (regex : `(^|\.)([^.\[\]\s?]+)|\[([0-9]+|\?)\]`).
   - **Interdits** : `$`, `$.clients`, `clients[*]`, `clients..nom`, `clients[-1]`, `clients[]`, `clients['nom']`, `clients[?(@.actif)]`.
   - Exemples valides : `ui.activeTab`, `clients[0].nom`, `clients[?].nom`, `clients[?].commandes[?].montantHt`, `@totalGlobal`, `articles[?].@montantLigne`.
5. **Contraintes sur `"name"` (nom de fichier du repository)** :
   - Non vide après `trim()`, ne se terminant **pas** par un point `.`.
   - Aucun caractère interdit par le système de fichiers ni caractère de contrôle : `<>:"/\|?*` et `\x00`–`\x1f`.
   - Aucun nom de périphérique réservé Windows (insensible à la casse, avec ou sans extension) : `CON`, `PRN`, `AUX`, `NUL`, `COM1` à `COM9`, `LPT1` à `LPT9`.
6. **Précision numérique intacte** :
   - Contrairement aux propriétés géométriques et visuelles d'`Appearance` (arrondies à 2 décimales et compactées lors de l'export), les documents JSON des repositories **ne subissent aucun arrondi ni filtrage** : les taux précis (`0.19675`), coordonnées GPS, prix unitaires, identifiants et chaînes vides sont conservés à l'identique.

---

## 3. Architecture canonique d'un document de Repository & Jokers `[?]`

### 3.1. Espaces de noms racines recommandés

Organise chaque repository métier de manière lisible et prévisible autour de 4 espaces de noms racines :

```json
{
  "ui": {
    "activeTab": 0,
    "westWidth": 320,
    "filtersOpen": false,
    "viewMode": "detail"
  },
  "filters": {
    "recherche": "",
    "statut": "tous"
  },
  "options": {
    "statuts": [
      { "value": "actif", "label": "Actif", "icon": "verified" },
      { "value": "en_attente", "label": "En attente", "icon": "schedule" },
      { "value": "bloque", "label": "Bloqué", "icon": "error" }
    ]
  },
  "clients": [
    {
      "id": "CLI-001",
      "nom": "Claire Martin",
      "statut": "actif",
      "commandes": [
        { "id": "CMD-101", "date": "2026-10-14", "montantHt": 2450.0 }
      ]
    }
  ]
}
```

- **Collections et entités métier (`clients`, `produits`, sous-tableaux `clients[?].commandes`, arbres `dossiers`)** :
  - Chaque élément d'un tableau est un objet JSON doté d'un identifiant métier stable (`id`) et d'un **schéma de clés strictement homogène** sur toutes les lignes.
  - Pour un arbre hiérarchique (`SuperTreeView`), chaque nœud expose ses enfants dans un sous-tableau récursif nommé par `childrenKey` (`"children"` par défaut, toujours initialisé à `[]` sur les feuilles).
- **État d'interface (`ui.*`)** :
  - `ui.activeTab` (`int` 0-based) : index d'onglet actif d'un `SuperTab` en `mode: "static"`.
  - `ui.westWidth` / `ui.eastWidth` (`num` fini $\ge 0$) : épaisseur de volet pilotée par un comportement `bindZoneSize` (`0` ferme le tiroir).
  - `ui.filtersOpen` / `ui.menuOpen` (`bool`) : état ouvert/fermé bidirectionnel d'un `Expansible` ou d'un `Menu`.
  - `ui.viewMode` (`String`) : branche active d'un `SuperConditional` (`"case:detail"`, `"case:compact"`, etc.).
- **Critères de filtre ou de recherche (`filters.*`)** :
  - Champs scalaires ou tableaux liés aux contrôles de filtre de l'écran (`filters.recherche` en `String`, `filters.statutsActifs` en `List<String>`, `filters.uniquementActifs` en `bool`).
- **Nomenclatures et référentiels d'options (`options.*`)** :
  - Tableaux d'objets homogènes `{"value": "...", "label": "...", "icon": "..."}` alimentant dynamiquement les sélecteurs `SuperValue` (`kind: "choice"`) via `choice.optionsBinding` avec `optionValueKey: "value"`, `optionLabelKey: "label"` et `optionIconKey: "icon"`.

### 3.2. Résolution des jokers `[?]` et pattern Maître / Détail (`JsonListScope.resolveSelected`)

Les jokers `[?]` d'un chemin sont résolus à l'exécution **de gauche à droite (du tableau le plus externe au plus interne)** en deux passes complémentaires :

1. **Passe 1 — Portée itérative englobante (`JsonListScope`)** :
   - Chaque ligne rendue par une collection (`SuperListView`, `SuperTable`, `SuperTreeView`, ou `SuperTab` en `mode: "dynamic"`) enveloppe ses enfants dans un `JsonListScope` fournissant le `repositoryId` de la collection et les indices de lignes englobantes (`[i]`, `[i, j]`, …).
   - **Règle impérative du chemin complet avec `[?]` (même en mode « hérité de la liste englobante »)** :
     - Dans le gabarit (`template`, colonnes ou contenu dynamique) d'une `SuperListView`, d'une `SuperTable` ou d'un `SuperTab` dynamique, **omettre le `repositoryId` ne dispense jamais d'écrire le chemin complet depuis la racine du repository avec le(s) joker(s) `[?]`** (forme `tableau[?].attribut` ou `parent[?].sousTableau[?].attribut`).
     - **Correct** : dans une `SuperListView` liée à `"crm_clients:clients"` (ou `"deals"`), écris `"binding": "clients[?].nom"` (ou `"deals[?].title"`), et pour une sous-liste liée à `"clients[?].commandes"`, écris `"binding": "clients[?].commandes[?].montantHt"`.
     - **Strictement interdit** : n'écris **jamais** un nom d'attribut seul sans son préfixe tableau `[?]` (ex. `"binding": "nom"` ou `"binding": "title"`). Dans une liste, `JsonListScope` hérite uniquement du `repositoryId` et fournit les indices de `[?]` : un chemin sans `[?]` comme `"title"` est résolu à la **racine** du repository (`document["title"]`, pas `deals[i]["title"]`), renvoie `null` et rend le composant vide (`width: 0`).
     - **Seule exception** : à l'intérieur d'un `SuperTreeView` lié à `"crm_clients:dossiers"`, les enfants peuvent utiliser un chemin relatif au nœud courant (`"nom"`) ou le chemin complet (`"dossiers[?].nom"`).
2. **Passe 2 — Sélection Maître / Détail hors collection (`JsonArrayBinding`)** :
   - Lorsqu'un chemin comporte encore un ou plusieurs `[?]` non fournis par une collection englobante (par exemple un composant placé dans le panneau central `card-detail`, **en dehors** de la `SuperListView` placée en `west`), `JsonListScope.resolveSelected` remplace chaque `[?]` restant par l'**indice de la ligne actuellement sélectionnée** dans le `JsonArrayBinding` correspondant (`store.bindingOf(repoId).array('clients')`).
   - Cela réalise nativement le pattern **Maître / Détail** (et même **Maître / Sous-maître / Détail** avec `"crm_clients:clients[?].commandes"` pour une sous-liste détail et `"crm_clients:clients[?].commandes[?].montantHt"` pour le détail de la sous-ligne sélectionnée), sans aucun code ni événement manuel.
   - **Exigence impérative hors collection** : tout composant placé en dehors d'une collection englobante **doit déclarer explicitement son `repositoryId`** (`"crm_clients:clients[?].nom"` ou `{"repositoryId": "crm_clients", "path": "clients[?].nom"}`). Sans `repositoryId` explicite hors liste, la validation échoue avec *« Repository hérité indisponible »*.
   - Tant qu'aucune ligne n'est sélectionnée dans le tableau maître, la liaison retourne `binding: null` : les composants détail restent proprement vides et désactivés (non modifiables) sans lever d'erreur.

### 3.3. Règle impérative Maître / Esclave : attributs JSON imbriqués (jamais de clé étrangère)

`JsonAttributePath` ne supporte **aucune jointure** entre tableaux indépendants et **aucun prédicat de filtre** (les expressions du type `commandes[?(@.clientId == ...)]` sont formellement interdites). En revanche, `JsonListScope.resolveSelected` résout nativement toute chaîne de jokers `[?]` imbriqués de gauche à droite en s'appuyant sur la sélection active de chaque niveau (`JsonArrayBinding`).

**Règle absolue** :
- **À ne JAMAIS faire (modèle relationnel plat)** : ne sépare **jamais** une entité maître et ses entités esclaves dans deux tableaux de premier niveau reliés par une clé étrangère (ex. `"clients": [{"id": "C1", ...}]` + `"commandes": [{"id": "CMD-1", "clientId": "C1", ...}]`). Une telle liste `"commandes"` ne serait **jamais filtrée** lors du clic sur un client.
- **À TOUJOURS faire (attributs imbriqués dans le maître)** : modélise toute relation **Maître / Esclave** directement par des **attributs imbriqués à l'intérieur de chaque objet maître** :
  1. **Relation 1-N (Maître $\rightarrow$ Esclave)** : imbrique un **sous-tableau** dans l'objet maître (ex. `"commandes": [...]` dans chaque client $\rightarrow$ chemin `"crm_clients:clients[?].commandes"`).
  2. **Relation multi-niveaux (Maître $\rightarrow$ Sous-maître $\rightarrow$ Détail)** : imbrique un sous-tableau dans le sous-tableau (ex. `"lignes": [...]` dans chaque commande $\rightarrow$ chemin `"crm_clients:clients[?].commandes[?].lignes"`).
  3. **Relation 1-1 / groupe de détails structurés** : imbrique un **sous-objet** dans l'objet maître (ex. `"adresse": {"rue": "...", "codePostal": "...", "ville": "..."}` $\rightarrow$ chemin `"crm_clients:clients[?].adresse.ville"`).

**Contrat exact des `binding` selon l'emplacement du composant** :

| Rôle dans l'écran | Emplacement du composant | Syntaxe `binding` à utiliser | Résolution des `[?]` |
| :--- | :--- | :--- | :--- |
| **Liste / Table / Graphe / Onglets maître** | Zone maître (ex. `west`) | `"<repo>:clients"` | Sélection stockée dans `array('clients')` |
| **Champs détail 1-1 du maître** *(y compris sous-objet imbriqué)* | Hors liste maître (ex. panneau `center`) | `"<repo>:clients[?].nom"` / `"<repo>:clients[?].adresse.ville"` | `[?]` résolu par la sélection maître active (`repositoryId` explicite obligatoire) |
| **Liste / Table / Graphe / Onglets esclave** | Hors liste maître (ex. panneau `center`) | `"<repo>:clients[?].commandes"` | `[?]` résolu par le client sélectionné (`repositoryId` explicite obligatoire) |
| **Liste esclave imbriquée dans une ligne maître** | Dans le `template` de la liste maître | `"clients[?].commandes"` | `[?]` résolu par la portée de ligne maître (`repositoryId` hérité) |
| **Cellule / champ dans la ligne esclave** | Dans le `template` ou `cell:<col>` de l'esclave | `"clients[?].commandes[?].montantHt"` | 1er `[?]` = client maître sélectionné ; 2e `[?]` = ligne courante de la portée esclave (`repositoryId` hérité) |
| **Détail de la ligne esclave sélectionnée** | Hors liste esclave (ex. fiche sous-détail) | `"<repo>:clients[?].commandes[?].montantHt"` | 1er `[?]` = client maître sélectionné ; 2e `[?]` = commande esclave sélectionnée pour ce client (`repositoryId` explicite obligatoire) |

**Exemple ciblé de modélisation Maître / Esclave imbriquée** :

```json
{
  "clients": [
    {
      "id": "CLI-001",
      "nom": "Claire Martin",
      "adresse": {
        "rue": "14 rue de la République",
        "codePostal": "69002",
        "ville": "Lyon"
      },
      "commandes": [
        {
          "id": "CMD-101",
          "date": "2026-10-14",
          "montantHt": 2450.0,
          "statut": "payee",
          "lignes": [
            { "id": "L-1", "designation": "Audit architecture", "quantite": 2, "puHt": 950.0 },
            { "id": "L-2", "designation": "Support mensuel", "quantite": 1, "puHt": 550.0 }
          ]
        }
      ]
    }
  ]
}
```

- Liste maître (`SuperListView` `list-clients`) : `"binding": "crm_clients:clients"`
- Ville du client sélectionné (`SuperValue` hors liste) : `"binding": "crm_clients:clients[?].adresse.ville"`
- Liste esclave des commandes du client sélectionné (`SuperTable` / `SuperListView` `table-commandes` hors liste maître) : `"binding": "crm_clients:clients[?].commandes"`
- Montant dans une cellule/ligne de `table-commandes` : `"binding": "clients[?].commandes[?].montantHt"`
- Sous-table des lignes de la commande sélectionnée (`SuperTable` `table-lignes` hors `table-commandes`) : `"binding": "crm_clients:clients[?].commandes[?].lignes"`
- Désignation dans une cellule de `table-lignes` : `"binding": "clients[?].commandes[?].lignes[?].designation"`

---

## 4. Matrice exhaustive des contrats de typage par composant et comportement

Chaque consommateur de liaison exige un type JSON précis dans le repository. Un type incompatible (par exemple un objet `{...}` là où un scalaire est attendu, ou un nombre là où `states.binding` attend une `String`) provoque une erreur de liaison affichée sur le composant.

| Consommateur & propriété | Exemple de chemin | Type JSON exact requis dans le repository | Mode L/É | Comportement si `null` / absent / aucune ligne sélectionnée |
| :--- | :--- | :--- | :---: | :--- |
| **`SuperValue`** (`kind: "text"`, `mode: "display"` ou `"input"`) | `"crm_clients:clients[?].nom"` | `String \| num (fini) \| bool \| null` *(1 seul attribut atomique par `binding`, jamais d'objet ni de tableau)* | L (`display`) / L+É (`input`) | Affiche `""` ; hors sélection `[?]`, champ vide et non modifiable. Si la valeur courante est un `num` ou un `bool`, toute saisie invalide pour ce type est refusée avant écriture. |
| **`SuperValue`** (`kind: "checkbox"` ou `"switch"`) | `"crm_clients:clients[?].facturationAuto"` | `bool` (`true` / `false`) | L (`display`) / L+É (`input`) | Traité comme `false` (`initialBool`) à l'affichage ; écrit un `bool` JSON (`true` / `false`) si l'attribut était `bool` ou absent. |
| **`SuperValue`** (`kind: "choice"`, variante simple : `dropdown`, `segmented`, `radio`, `searchAnchor`) | `"crm_clients:clients[?].statut"` | `String` égale au `value` d'une option (sans virgule `,`) | L+É (`mode: "input"` requis) | Aucune option cochée (autorisé en saisie si `allowEmpty: true`). |
| **`SuperValue`** (`kind: "choice"`, variante multiple : `filterChip`, `checkboxList`) | `"crm_clients:clients[?].tags"` | `List<String>` *(recommandé, ex. `["vip", "export"]`)* ou `String` CSV (`"vip,export"`) | L+É (`mode: "input"` requis) | Liste vide `[]` (aucune puce/case cochée). Si la valeur initiale est une `List` (ou `null`), le composant réécrit une `List<String>` ; si c'est une `String`, il réécrit du CSV. |
| **`SuperValue.choice.optionsBinding`** (`optionValueKey`, `optionLabelKey`, `optionIconKey`) | `"crm_clients:options.statuts"` | `List<Map<String, Object?>>` avec clés `"value"` (`String` non vide sans `,`), `"label"` (`String`), et optionnellement `"icon"` (ID `MaterialIconCatalog` en `snake_case`) | L | Liste d'options vide (repli sur `defaultFallbackOptions` en aperçu si aucune option n'est résolue). |
| **`SuperListView`** & **`SuperTable`** (`binding`) | `"crm_clients:clients"` | `List<Map<String, Object?>>` *(toujours initialiser explicitement à `[...]` ou `[]`)* | L (+ ajout/retrait si `allowAdd` / `allowRemove`) | Clé absente ou `null` traitée comme `[]` et affiche `emptyText`. Un scalaire ou un `Map` lève une `FormatException`. |
| **`SuperTreeView`** (`binding` + `childrenKey`, défaut `"children"`) | `"crm_clients:dossiers"` | `List<Map<String, Object?>>` (racines multiples) **ou** `Map<String, Object?>` (racine unique), chaque nœud portant `children: [...]` | L | Clé absente ou `null` affiche `emptyText`. Les enfants de `header`/`data` lisent les clés relatives du nœud (`"nom"`) ou `"dossiers[?].nom"`. |
| **`SuperTab`** (`mode: "static"`, `binding`) | `"crm_clients:ui.activeTab"` | `int` dans `0 .. tabs.length - 1` | L+É | Repli sur `initialIndex` (`0` par défaut) ; met à jour l'entier dans le repository à chaque changement d'onglet. |
| **`SuperTab`** (`mode: "dynamic"`, `binding`) | `"crm_clients:categories"` | `List<Map<String, Object?>>` (1 onglet généré par élément) | L (+ ajout/retrait si `allowAdd` / `allowRemove`) | Affiche `emptyText` (`"Aucun onglet"`). L'onglet gabarit lie son titre via `propertyBindings.label: "categories[?].nom"`. |
| **`SuperConditional`** (`binding`) | `"crm_clients:ui.viewMode"` | Scalaire `String \| bool \| num` comparé sous forme textuelle aux zones `"case:<valeur>"` | L | Bascule sur `initialCase` (si non vide), sinon sur la zone `"default"` (si `hasDefaultCase: true`), sinon affiche `emptyText`. |
| **`SuperChart`** (`binding` + `labelPath` + `series[*].valuePath`) | `"crm_clients:ventesMensuelles"` | `List<Map<String, Object?>>` où `labelPath` $\rightarrow$ `String \| num` et chaque `valuePath` / `secondaryValuePath` $\rightarrow$ `num` fini *(sans `[?]` dans `labelPath`/`valuePath`)* | L (+ sélection Maître/Détail si `enableSelection: true`) | Tableau vide ou absent affiche `emptyText` (ou l'aperçu démo si non lié et `showDemoWhenUnbound: true`). |
| **`Native` `Expansible` & `Menu`** (`binding`) | `"crm_clients:ui.filtersOpen"` | `bool` (`true` = déplié/ouvert, `false` = replié/fermé) | L+É | Repli sur `initiallyExpanded` (`false` par défaut) tant que la liaison n'est pas résolue. |
| **`states.binding`** (`ContainerStyle`, `SuperValue`, `SuperAction`, `SuperIndicator`, `SuperSeparator`) | `"clients[?].statut"` | `String` correspondant à une clé déclarée dans `states.named` *(interdits dans `named` : `"default"`, `"selected"`, `"hover"`, `"hovered"`, `"par défaut"`, `"sélectionné"`, `"survol"`)* | L | Si `null`, chaîne inconnue de `states.named` ou hors sélection : conserve le style/composant de base sans surcharge nommée. Une valeur non-`String` produit une erreur. |
| **`propertyBindings`** (`ContainerStyle`: `imageUrl` / `fill.imageBinding` ; `Value`/`Action`/`Indicator`/`Separator`: `label`, `placeholder`, `icon`, `enabled`, `color`, `iconColor`, `backgroundColor`, `borderColor`, `lineColor`, `fontSize`, `iconSize`, `fontWeight`, `italic`, `textAlign`, `radius`, `borderWidth`, `elevation`, `extent`, `thickness`, `indent`, `endIndent`) | `"clients[?].couleurBadge"` | Type valide pour la propriété cible : `String` pour textes/URL d'image, ID `snake_case` connu (ou `""`/`null`) pour `icon`, `bool` pour `enabled`/`italic`, `num > 0` (ou `>= 0`) pour tailles/rayons, **`"#RRGGBB"` / `"#AARRGGBB"`** (ou entier ARGB) pour les couleurs liées *(les tokens `theme:*` s'utilisent dans `Appearance`, pas comme valeur dans le JSON d'un repository)* | L | Conserve la valeur statique configurée sur le composant ou le style (par ex. `fill.imageUrl` sert d'image de repli tant que `imageUrl` liée est vide ou non sélectionnée). |
| **Behavior `bindZoneSize`** (`trigger: "binding"`, sur un `SuperLayout`) | `"crm_clients:ui.westWidth"` | `num` fini $\ge 0$ (`0` ferme la zone avec animation tiroir ; pixels ou `%` selon `unit`) | L | Valeur `null` ou absente restitue la taille fixe configurée sur le `SuperLayout` (`westSize`, `eastSize`, etc.). |
| **Behavior `bindState`** (`trigger: "binding"`, `state: "invisible" \| "readOnly" \| "disabled"`) | `"clients[?].estVerrouille"` | `bool` comparé à `whenValue` (`true` par défaut) | L | Valeur `null` ou absence de sélection : retourne `false` (l'état conditionnel n'est **pas** activé). |
| **Behavior `onTooltip`** (`trigger: "hover"`, `binding`) | `"clients[?].commentaire"` | `String \| null` | L | Si `null`, `""` ou absence de sélection : aucune info-bulle n'est affichée (`message` n'est pas utilisé comme fallback quand `binding` est défini). |

> **Rappel impératif sur `usages` et `slotLabels`** :
> - Dès qu'un composant possède **au moins une liaison de données** (`binding`, `choice.optionsBinding`, `propertyBindings`, ou `states.binding`), **n'émets aucune entrée pour lui dans `usages[<id>]`** (`AppearanceTransfer.applyVibe` ignore toute proposition d'usage sur un composant lié).
> - En revanche, son **nom d'édition dans `slotLabels`** de son conteneur parent (ou `components[<listId>].template.slotLabels[<childId>]` pour une cellule de `SuperListView`) reste **toujours obligatoire**, qu'il soit lié ou non.

---

## 5. Règles de qualité des jeux de données initiaux (Seed Data)

Lorsque tu crées ou enrichis un repository dans `"repositories"`, applique systématiquement ces 3 exigences de qualité :

### 5.1. Homogénéité stricte des tableaux et règle critique de `items.last`

Dans `JsonRepositoryStore`, lorsque l'utilisateur clique sur le bouton **Ajouter (`+`)** d'une `SuperListView`, d'une `SuperTable` ou d'un `SuperTab` dynamique (`allowAdd: true`), `appendArrayItem` crée la nouvelle ligne en appelant **`JsonRepositoryStore.blank(items.last)`** sur le **dernier élément** du tableau :

- `String` $\rightarrow$ `""`
- `num` $\rightarrow$ `0`
- `bool` $\rightarrow$ `false`
- `List` $\rightarrow$ `[]`
- `Map` $\rightarrow$ `{ clé: blank(valeur), ... }`
- `null` $\rightarrow$ `null`

**Conséquence directe** :
1. **Toutes les lignes** d'un tableau doivent posséder **exactement le même ensemble de clés** avec les **mêmes types JSON**.
2. **Ne mets jamais `null` ni clé manquante dans les objets d'exemple (et tout particulièrement sur le dernier élément `items.last`)** pour un champ texte, numérique, booléen, sous-objet ou sous-tableau : utilise `""` (ou mieux, une vraie valeur métier réaliste), `0`, `false` ou `[]`. Si `items.last` contient `"telephone": null` ou omet `"montantHt"` / `"commandes"`, toutes les futures lignes créées par l'utilisateur hériteront de `null` ou n'auront pas la clé attendue !
3. **Sous-tableaux esclaves imbriqués (`allowAdd: true`)** : chaque ligne maître doit toujours initialiser son sous-tableau esclave (`"commandes": [...]` ou `[]`, jamais `null`). Lorsqu'une liste esclave autorise `allowAdd: true`, veille à ce que les enregistrements maîtres initiaux embarquent **2 à 4 éléments esclaves homogènes** (avec un dernier élément esclave entièrement renseigné) afin que `blank(items.last)` dispose d'un gabarit complet lors de l'ajout d'un nouvel élément esclave ; lors de l'ajout d'un nouveau maître, `blank(List)` initialise automatiquement son sous-tableau esclave à `[]`.

### 5.2. Couverture complète des états nommés et des branches conditionnelles

- Si un style de surface, un `SuperIndicator`, un `SuperValue` ou un `SuperAction` déclare des états métier dans `states.named` (ex. `"actif"`, `"en_attente"`, `"bloque"`), le jeu de données initial **doit contenir au moins une ligne illustrant chacun de ces états**, afin que le rendu visuel soit immédiatement vérifiable à l'écran.
- De même, si un `SuperConditional` distingue plusieurs `cases` (ex. `["particulier", "entreprise"]`), peuple la collection avec des enregistrements couvrant chaque cas.
- N'utilise jamais un nom réservé (`"default"`, `"selected"`, `"hover"`, `"hovered"`, `"par défaut"`, `"sélectionné"`, `"survol"`) comme valeur de statut destinée à `states.named`.

### 5.3. Calibrage Desktop et réalisme métier

- **Volume équilibré** : fournis **5 à 8 enregistrements** réalistes en français pour une collection principale (suffisant pour donner vie à la liste, tester la sélection Maître / Détail et vérifier l'alignement des colonnes sans alourdir inutilement le flux SSE), et **2 à 4 sous-éléments** pour les sous-tableaux ou nœuds d'arbre (`children`).
- **Cohérence métier** : utilise des noms francophones variés et crédibles, des dates ISO ou lisibles cohérentes (`"2026-11-15"`), des montants réalistes (`num` JSON, pas des chaînes formatées si un calcul ou un graphique les lit), et uniquement des identifiants d'icônes réellement présents dans `MaterialIconCatalog` (`"verified"`, `"schedule"`, `"warning"`, `"error"`, `"check_circle"`, `"person"`, `"work"`, `"payments"`, `"local_shipping"`, `"folder"`, `"description"`, etc.).

---

## 6. Référence de l'API Dart applicative (`RepositoryImpl`, Persistance, `@calculs` & Concurrence)

Cette section documente l'intégration côté code Dart dans une application hôte (telle que `SurfFile` ou `SuperDesignerApp`). Ces mécanismes s'écrivent exclusivement en Dart — jamais dans le flux JSON généré par le Chat Vibe.

### 6.1. Création d'un `RepositoryImpl` et observation (`ChangeContext`)

Un repository applicatif possède un identifiant stable en `snake_case` (`^[a-z0-9_]{1,32}$`), un document initial `Map<String, Object?>` et un callback optionnel `onChanged` notifié après chaque mutation effective :

```dart
final repo = RepositoryImpl(
  id: 'crm_app_repo',
  json: {
    'ui': {'westWidth': 320},
    'remiseGlobale': 0.05,
    'articles': [
      {'id': 'ART-1', 'designation': 'Licence Pro', 'quantite': 3, 'prixUnitaire': 490.0},
      {'id': 'ART-2', 'designation': 'Support annuel', 'quantite': 1, 'prixUnitaire': 950.0},
    ],
  },
  onChanged: (ChangeContext change) {
    // change.repositoryId : 'crm_app_repo'
    // change.path         : chemin modifié (ex: 'articles[0].quantite', ou '' si document entier)
    // change.oldValue     : copie immuable avant modification
    // change.newValue     : copie immuable après modification
    // change.componentId  : ID du composant auteur de l'écriture (ou null)
    // change.isReload     : true uniquement lors d'un loadRepository explicite
  },
);
```

### 6.2. Attributs calculés (`addCalculatedAttribute`, `CalculatedAttributeContext` & `ctx.sync`)

Les attributs calculés **doivent impérativement être déclarés avant** `registerRepository` / `registerPersistentRepository` (toute déclaration ultérieure lève un `StateError`).

- **Calcul racine (`@nom` ou sous-chemin `@stats.total`)** : `scope` omis ; les chemins lus dans `ctx` partent de la racine du repository.
- **Calcul par ligne (`articles[?].@montant`)** : `scope` doit désigner un tableau JSON source terminé par `[?]` (jamais un tableau calculé). Les chemins lus dans `ctx` sans `repositoryId` explicite sont **relatifs à la ligne courante** (`articles[i]`), et les éventuels `[?]` sont résolus avec les indices de cette ligne.
- **Accesseurs typés et suivi automatique des dépendances** :
  - Asynchrones (`FutureOr<T?>`, supportent les calculs ou documents pas encore en cache) : `ctx.getValue`, `ctx.getString`, `ctx.getNum`, `ctx.getInt`, `ctx.getDouble`, `ctx.getBool`, `ctx.getList`, `ctx.getObject`. Chacun accepte `repositoryId: 'autre_repo'` (lecture inter-repositories depuis la racine de `'autre_repo'`) et `defaultValue` (appliqué uniquement si la valeur est `null`/absente, jamais pour masquer une erreur de type).
  - Façade synchrone immédiate **`ctx.sync`** (`ctx.sync.getNum(...)`, `ctx.sync.getList(...)`, etc.) : idéale lorsque les repositories sont en mémoire ou préchargés (`await store.preload()`).
  - **Cache et invalidation réactive** : `CalculatedAttributeEngine` mémorise les résultats par génération, détecte les cycles, et invalide automatiquement les calculs impactés ainsi que leurs lecteurs transitifs dès qu'un chemin dont ils dépendent change.

```dart
// 1. Calcul par ligne : lu dans l'IHM via "crm_app_repo:articles[?].@montantHt" (ou "articles[?].@montantHt" dans la liste)
repo.addCalculatedAttribute('montantHt', scope: 'articles[?]', (ctx) {
  final qte = ctx.sync.getInt('quantite', defaultValue: 0)!;
  final pu = ctx.sync.getDouble('prixUnitaire', defaultValue: 0.0)!;
  return qte * pu;
});

// 2. Calcul racine retournant un objet : lu via "@totaux.brutHt" et "@totaux.netHt"
repo.addCalculatedAttribute('totaux', (ctx) {
  final articles = ctx.sync.getList('articles', defaultValue: const [])!;
  var brut = 0.0;
  for (var i = 0; i < articles.length; i++) {
    final ligneHt = ctx.sync.getDouble('articles[$i].@montantHt', defaultValue: 0.0)!;
    brut += ligneHt;
  }
  final remise = ctx.sync.getDouble('remiseGlobale', defaultValue: 0.0)!;
  return {'brutHt': brut, 'netHt': brut * (1.0 - remise)};
});
```

### 6.3. Enregistrement mémoire vs persistant et cycle de vie à la fermeture

- **Mémoire seule** : `store.registerRepository(repo)` — aucune écriture sur disque.
- **Persistant (`registered/<id>.json`)** :
  - `final restored = await store.registerPersistentRepository(repo, autoSave: true);`
  - Charge `<store.directory>/registered/<id>.json` s'il existe déjà (`restored == true`), sinon initialise avec `repo.json` (et écrit immédiatement le fichier si `autoSave: true`).
  - Écriture atomique sûre via fichier temporaire `.tmp` + renommage, avec détection de modification externe sur le disque.
  - `await store.saveRepository('crm_app_repo')` : vide d'abord les saisies en attente (`flushBindings()`), puis force l'écriture sur disque (indispensable quand `autoSave: false` ou à la fermeture).
  - `await store.loadRepository('crm_app_repo', discardChanges: false)` : recharge depuis le disque en protégeant les modifications locales non sauvegardées tant que `discardChanges` vaut `false`.
- **Vidage propre à la fermeture de l'application (`AppLifecycleListener.onExitRequested`)** :

```dart
final lifecycle = AppLifecycleListener(
  onExitRequested: () async {
    try {
      await store.flushBindings();
      await store.saveRepository('crm_app_repo');
      return AppExitResponse.exit;
    } on Object {
      return AppExitResponse.cancel;
    }
  },
);
```

### 6.4. Écritures concurrentes sûres (Compare-And-Swap & mutations atomiques)

Toutes les écritures passent par la file exclusive de `JsonRepositoryStore` et protègent l'intégrité des données :

1. **Lecture + écriture scalaire conditionnelle (`expectedValue`)** :
   ```dart
   const binding = JsonTextBinding(repositoryId: 'crm_app_repo', path: 'ui.westWidth');
   final current = await store.readAttribute(binding);
   await store.writeAttribute(
     binding,
     '0',
     expectedValue: current.value,
     componentId: 'toggle-sidebar',
   );
   ```
2. **Remplacement conditionnel multi-chemins (`expectedValues` & `JsonRepositoryConflictException`)** :
   - `replaceValue` et `replaceArray` vérifient atomiquement que chaque entrée de `expectedValues` correspond toujours à l'état actuel du document au moment d'écrire, sinon lèvent `JsonRepositoryConflictException` (sous-classe de `FormatException`, idéale pour une boucle de réessai sans écraser une saisie concurrente) :
   ```dart
   try {
     await store.replaceArray(
       'crm_app_repo',
       'articles',
       nouveauxArticles,
       componentId: 'sync-worker',
       expectedValues: {'articles': anciensArticles},
     );
   } on JsonRepositoryConflictException {
     // Relire l'état le plus récent puis recalculer la fusion.
   }
   ```
3. **Mutations transactionnelles dans la section critique (`updateValue` & `updateArray`)** :
   - Exécutent une transformation synchrone directement dans la section exclusive du store sur une copie profonde de la valeur ou du tableau courant, et n'écrivent que si le résultat diffère :
   ```dart
   await store.updateArray('crm_app_repo', 'articles', (items) {
     return [
       ...items,
       {'id': 'ART-3', 'designation': 'Formation', 'quantite': 1, 'prixUnitaire': 1200.0},
     ];
   });
   ```

---

## 7. Recette complète de référence (`"repositories"` + `"vibe"` Maître / Détail)

L'exemple ci-dessous constitue une réponse complète du Chat Vibe directement exécutable par `VibeRepositoryApplier` puis `AppearanceTransfer.applyVibe`. Il illustre :
- l'ordre strict `"message"` $\rightarrow$ `"repositories"` $\rightarrow$ `"vibe"` ;
- l'alias symbolique `"crm_clients"` réécrit automatiquement vers son ID 32 hex réel ;
- 5 lignes `clients` strictement homogènes couvrant tous les états de `states.named` (`"actif"`, `"en_attente"`, `"bloque"`) avec un dernier élément entièrement renseigné pour `appendArrayItem` ;
- un écran Maître / Détail Material 3 (`theme:*`, `styles["background"].padding: 0`, `westSize: 320` hors `autoSides`, `SuperListView` avec repository hérité dans le `template`, fiche détail liée via `"crm_clients:clients[?].*"`, `slotLabels` complets partout, et `usages` déclarés **uniquement** sur les composants sans liaison de données).

```json
{
  "message": "Création du repository CRM Clients et de l'écran Maître / Détail permettant de consulter et modifier le portefeuille clients.",
  "repositories": {
    "crm_clients": {
      "name": "CRM Clients",
      "mode": "merge",
      "data": {
        "ui": {
          "activeTab": 0,
          "westWidth": 320,
          "filtersOpen": false
        },
        "filters": {
          "recherche": "",
          "statut": "tous"
        },
        "options": {
          "statuts": [
            { "value": "actif", "label": "Client actif", "icon": "verified" },
            { "value": "en_attente", "label": "En attente", "icon": "schedule" },
            { "value": "bloque", "label": "Compte bloqué", "icon": "error" }
          ]
        },
        "clients": [
          {
            "id": "CLI-2026-01",
            "nom": "Claire Martin",
            "entreprise": "Atelier Lumière SAS",
            "ville": "Lyon",
            "email": "c.martin@atelier-lumiere.fr",
            "telephone": "+33 4 72 10 45 80",
            "statut": "actif",
            "caAnnuel": 48500,
            "facturationAuto": true
          },
          {
            "id": "CLI-2026-02",
            "nom": "Thomas Lefèvre",
            "entreprise": "Boréal Logistique",
            "ville": "Lille",
            "email": "t.lefevre@boreal-logistique.fr",
            "telephone": "+33 3 20 55 19 40",
            "statut": "en_attente",
            "caAnnuel": 19200,
            "facturationAuto": false
          },
          {
            "id": "CLI-2026-03",
            "nom": "Nadia Benali",
            "entreprise": "Solstice Ingénierie",
            "ville": "Nantes",
            "email": "n.benali@solstice-ing.fr",
            "telephone": "+33 2 40 88 31 12",
            "statut": "actif",
            "caAnnuel": 84300,
            "facturationAuto": true
          },
          {
            "id": "CLI-2026-04",
            "nom": "Julien Moreau",
            "entreprise": "Éditions du Parc",
            "ville": "Bordeaux",
            "email": "j.moreau@editions-parc.fr",
            "telephone": "+33 5 56 41 09 73",
            "statut": "bloque",
            "caAnnuel": 12600,
            "facturationAuto": false
          },
          {
            "id": "CLI-2026-05",
            "nom": "Sophie Garnier",
            "entreprise": "Verrière & Co",
            "ville": "Strasbourg",
            "email": "s.garnier@verriere-co.fr",
            "telephone": "+33 3 88 24 67 90",
            "statut": "actif",
            "caAnnuel": 35900,
            "facturationAuto": true
          }
        ]
      }
    }
  },
  "vibe": {
    "mode": "light",
    "accent": "#5268D9",
    "pageCatalog": {
      "pages": [],
      "homePageId": null
    },
    "styles": {
      "background": {
        "color": "theme:surfaceContainerLowest",
        "padding": 0
      },
      "panel-master": {
        "color": "theme:surface",
        "radius": 14,
        "padding": 12,
        "borderWidth": 1,
        "borderColor": "theme:outlineVariant",
        "elevation": 0
      },
      "list-clients:item": {
        "color": "theme:surfaceContainerLow",
        "radius": 10,
        "padding": 12,
        "hoverEffect": true,
        "states": {
          "named": {},
          "selected": {
            "style": {
              "color": "theme:secondaryContainer",
              "borderWidth": 1,
              "borderColor": "theme:primary"
            },
            "properties": ["background", "border"]
          }
        }
      },
      "card-detail": {
        "color": "theme:surface",
        "radius": 14,
        "padding": 20,
        "borderWidth": 1,
        "borderColor": "theme:outlineVariant",
        "elevation": 0
      }
    },
    "components": {
      "root": {
        "type": "native",
        "regions": { "appBar": true, "body": true },
        "slotLabels": {
          "crm-appbar": "Barre d'application",
          "scaffold:body": "Espace principal"
        },
        "placements": {
          "appBar": [{ "id": "crm-appbar", "type": "registry:ApplicationBar" }],
          "body": [{ "id": "scaffold:body", "type": "scaffold:body" }]
        }
      },
      "crm-appbar": {
        "type": "native",
        "regions": { "title": true },
        "slotLabels": {
          "app-title": "Titre de l'application"
        },
        "placements": {
          "title": [{ "id": "app-title", "type": "registry:Value" }]
        }
      },
      "app-title": {
        "type": "value",
        "text": "CRM Clients",
        "fontSize": 18,
        "fontWeight": "semibold",
        "color": "theme:onSurface"
      },
      "mainLayout": {
        "type": "layout",
        "west": true,
        "westSize": 320,
        "resizeSides": true,
        "autoSides": [],
        "zoneFlows": {
          "west": { "expandSlots": true, "paddingInsets": [12, 0, 12, 12] },
          "center": { "expandSlots": true, "padding": 12 }
        },
        "slotLabels": {
          "panel-master": "Panneau des clients",
          "card-detail": "Fiche détaillée du client"
        },
        "placements": {
          "west": [{ "id": "panel-master", "type": "registry:IterableContent" }],
          "center": [{ "id": "card-detail", "type": "registry:Card" }]
        }
      },
      "panel-master": {
        "type": "layout",
        "north": true,
        "autoSides": ["north"],
        "zoneFlows": {
          "north": { "expandSlots": false, "spacing": 8, "paddingInsets": [0, 0, 12, 0] },
          "center": { "expandSlots": true }
        },
        "slotLabels": {
          "master-title": "Titre du portefeuille",
          "search-clients": "Recherche de client",
          "list-clients": "Liste des clients"
        },
        "placements": {
          "north": [
            { "id": "master-title", "type": "registry:Value" },
            { "id": "search-clients", "type": "registry:Value" }
          ],
          "center": [
            { "id": "list-clients", "type": "registry:ListView" }
          ]
        }
      },
      "master-title": {
        "type": "value",
        "text": "Portefeuille clients",
        "fontSize": 16,
        "fontWeight": "semibold",
        "color": "theme:onSurface"
      },
      "search-clients": {
        "type": "value",
        "mode": "input",
        "label": "Rechercher",
        "placeholder": "Nom ou entreprise...",
        "binding": "crm_clients:filters.recherche"
      },
      "list-clients": {
        "type": "list",
        "binding": "crm_clients:clients",
        "itemExtent": 60,
        "spacing": 6,
        "allowAdd": true,
        "allowRemove": true,
        "emptyText": "Aucun client enregistré",
        "template": {
          "east": true,
          "autoSides": ["east"],
          "zoneFlows": {
            "center": { "expandSlots": false, "mainAxisAlignment": "center", "spacing": 4 },
            "east": { "expandSlots": false, "mainAxisAlignment": "center" }
          },
          "slotLabels": {
            "row-nom": "Nom du client",
            "row-entreprise": "Entreprise du client",
            "row-statut": "Statut du client"
          },
          "placements": {
            "center": [
              { "id": "row-nom", "type": "registry:Value" },
              { "id": "row-entreprise", "type": "registry:Value" }
            ],
            "east": [
              { "id": "row-statut", "type": "registry:Indicator" }
            ]
          }
        }
      },
      "row-nom": {
        "type": "value",
        "binding": "clients[?].nom",
        "fontSize": 14,
        "fontWeight": "medium",
        "color": "theme:onSurface"
      },
      "row-entreprise": {
        "type": "value",
        "binding": "clients[?].entreprise",
        "fontSize": 12,
        "color": "theme:onSurfaceVariant"
      },
      "row-statut": {
        "type": "indicator",
        "icon": "verified",
        "label": "Actif",
        "iconSize": 16,
        "fontSize": 11,
        "fontWeight": "medium",
        "radius": 99,
        "horizontalPadding": 10,
        "verticalPadding": 4,
        "backgroundColor": "theme:primaryContainer",
        "color": "theme:onPrimaryContainer",
        "iconColor": "theme:onPrimaryContainer",
        "states": {
          "binding": "clients[?].statut",
          "named": {
            "actif": {
              "icon": "verified",
              "label": "Actif",
              "backgroundColor": "theme:primaryContainer",
              "color": "theme:onPrimaryContainer",
              "iconColor": "theme:onPrimaryContainer"
            },
            "en_attente": {
              "icon": "schedule",
              "label": "En attente",
              "backgroundColor": "theme:secondaryContainer",
              "color": "theme:onSecondaryContainer",
              "iconColor": "theme:onSecondaryContainer"
            },
            "bloque": {
              "icon": "error",
              "label": "Bloqué",
              "backgroundColor": "theme:errorContainer",
              "color": "theme:onErrorContainer",
              "iconColor": "theme:onErrorContainer"
            }
          },
          "namedProperties": {
            "actif": ["icon", "textLabel", "backgroundColor", "color", "iconColor"],
            "en_attente": ["icon", "textLabel", "backgroundColor", "color", "iconColor"],
            "bloque": ["icon", "textLabel", "backgroundColor", "color", "iconColor"]
          }
        }
      },
      "card-detail": {
        "type": "native",
        "regions": { "child": true },
        "slotLabels": {
          "detail-layout": "Disposition de la fiche"
        },
        "placements": {
          "child": [{ "id": "detail-layout", "type": "registry:Layout" }]
        }
      },
      "detail-layout": {
        "type": "layout",
        "autoSides": [],
        "zoneFlows": {
          "center": {
            "expandSlots": false,
            "scrollable": true,
            "crossAxisAlignment": "stretch",
            "spacing": 12
          }
        },
        "slotLabels": {
          "detail-header": "En-tête de la fiche",
          "detail-sep": "Séparateur d'en-tête",
          "field-nom": "Nom complet",
          "field-entreprise": "Entreprise",
          "field-email": "Adresse e-mail",
          "field-telephone": "Téléphone",
          "field-ville": "Ville",
          "field-statut": "Statut du compte",
          "field-ca": "Chiffre d'affaires annuel",
          "field-auto": "Facturation automatique"
        },
        "placements": {
          "center": [
            { "id": "detail-header", "type": "registry:Value" },
            { "id": "detail-sep", "type": "registry:Separator" },
            { "id": "field-nom", "type": "registry:Value" },
            { "id": "field-entreprise", "type": "registry:Value" },
            { "id": "field-email", "type": "registry:Value" },
            { "id": "field-telephone", "type": "registry:Value" },
            { "id": "field-ville", "type": "registry:Value" },
            { "id": "field-statut", "type": "registry:Value" },
            { "id": "field-ca", "type": "registry:Value" },
            { "id": "field-auto", "type": "registry:Value" }
          ]
        }
      },
      "detail-header": {
        "type": "value",
        "text": "Fiche détaillée du client",
        "fontSize": 18,
        "fontWeight": "semibold",
        "color": "theme:onSurface"
      },
      "detail-sep": {
        "type": "separator",
        "kind": "divider",
        "extent": 12,
        "thickness": 1,
        "lineColor": "theme:outlineVariant"
      },
      "field-nom": {
        "type": "value",
        "mode": "input",
        "label": "Nom complet",
        "placeholder": "Claire Martin",
        "binding": "crm_clients:clients[?].nom"
      },
      "field-entreprise": {
        "type": "value",
        "mode": "input",
        "label": "Entreprise",
        "placeholder": "Atelier Lumière SAS",
        "binding": "crm_clients:clients[?].entreprise"
      },
      "field-email": {
        "type": "value",
        "mode": "input",
        "label": "Adresse e-mail",
        "placeholder": "contact@entreprise.fr",
        "binding": "crm_clients:clients[?].email"
      },
      "field-telephone": {
        "type": "value",
        "mode": "input",
        "label": "Téléphone",
        "placeholder": "+33 4 72 10 45 80",
        "binding": "crm_clients:clients[?].telephone"
      },
      "field-ville": {
        "type": "value",
        "mode": "input",
        "label": "Ville",
        "placeholder": "Lyon",
        "binding": "crm_clients:clients[?].ville"
      },
      "field-statut": {
        "type": "value",
        "mode": "input",
        "kind": "choice",
        "label": "Statut du compte",
        "binding": "crm_clients:clients[?].statut",
        "choice": {
          "variant": "segmented",
          "optionsBinding": "crm_clients:options.statuts",
          "optionValueKey": "value",
          "optionLabelKey": "label",
          "optionIconKey": "icon"
        }
      },
      "field-ca": {
        "type": "value",
        "mode": "input",
        "label": "Chiffre d'affaires annuel (€ HT)",
        "placeholder": "48500",
        "binding": "crm_clients:clients[?].caAnnuel"
      },
      "field-auto": {
        "type": "value",
        "mode": "input",
        "kind": "switch",
        "label": "Facturation automatique activée",
        "binding": "crm_clients:clients[?].facturationAuto"
      }
    },
    "behaviors": {
      "mainLayout": [
        {
          "id": "b-west-width",
          "trigger": "binding",
          "action": {
            "type": "bindZoneSize",
            "zone": "west",
            "binding": "crm_clients:ui.westWidth",
            "unit": "pixels",
            "durationMs": 250,
            "curve": "easeInOut"
          }
        }
      ]
    },
    "usages": {
      "crm-appbar": { "kind": "layout" },
      "app-title": { "kind": "explanation", "translationKey": "crmClientsTitle" },
      "panel-master": { "kind": "layout" },
      "master-title": { "kind": "explanation", "translationKey": "clientPortfolioTitle" },
      "card-detail": { "kind": "layout" },
      "detail-layout": { "kind": "layout" },
      "detail-header": { "kind": "explanation", "translationKey": "clientDetailHeader" },
      "detail-sep": { "kind": "decoration" }
    }
  }
}
```
