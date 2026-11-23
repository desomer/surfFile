# Guide pour IA : Modéliser et configurer un écran en JSON (Modèle GenUI `super_container_layout`)

Ce document est la spécification technique destinée à une Intelligence Artificielle. Il décrit le format JSON plat et polymorphe inspiré de **Flutter GenUI** utilisé par `super_container_layout` pour le stockage, l'import/export et les mises à jour incrémentales (`applyVibe`).

> **Moteur d'exécution cible : Application Flutter (Material 3)**
> Ce JSON est interprété dynamiquement par une application **Flutter**. Appuie-toi sur ta connaissance de Flutter pour comprendre le comportement physique des layouts (`Flex`, `MainAxisAlignment`, `CrossAxisAlignment`, contraintes de taille, défilement `SingleChildScrollView` / `CustomScrollView`), l'anatomie des écrans (`Scaffold`, `AppBar`, `SliverAppBar`, `Drawer`, `BottomAppBar`, `TabBar` / `TabBarView`) et les conventions Material 3 (variantes de boutons `filled` / `tonal` / `elevated` / `outlined` / `text`, identifiants d'icônes Material en `snake_case`).
> **Règle stricte (zéro hallucination Flutter)** : ce format **n'est pas** un arbre de widgets Flutter sérialisé. N'invente **aucun** nom de widget ou paramètre Flutter (`Row`, `Column`, `Container`, `SizedBox`, `children`, `mainAxisSize`, `EdgeInsets`, `BoxDecoration`, etc.) qui ne figure pas dans ce guide ; utilise exclusivement le dictionnaire plat par ID (`components`, `styles`, `behaviors`) et les propriétés documentées ci-dessous.

---

## 1. Primitives et raccourcis "AI-friendly"

**Précision numérique** : les sauvegardes, exports et contextes Vibe de
configuration UI utilisent au maximum **deux décimales**, y compris dans les
objets/listes imbriqués et les préférences applicatives. Les valeurs restent
des nombres JSON, pas des chaînes formatées ; les entiers sont conservés.
Les dimensions compactes comme `"123.46px"` suivent la même précision.
Les fichiers de données des repositories et les textes utilisateur ne sont
pas arrondis.

**Exports compacts** : les exports d'apparence et le contexte Vibe restent
indentés, mais omettent les champs de configuration que leurs décodeurs
reconstituent sans perte. Les groupes et clés racines restent explicites pour
restaurer aussi les valeurs par défaut sur une cible modifiée. Les anciennes
sauvegardes et les imports partiels restent acceptés. Une configuration dont
la forme compacte ne restitue pas toutes les valeurs conserve sa forme
complète. Les données JSON arbitraires des repositories ne sont pas filtrées.
Dans un patch Vibe, une propriété absente continue à signifier « conserver »,
et non « réinitialiser ».

Les maxima des sliders de dimensions (tailles, marges, rayons, espacements,
épaisseurs, ombres, tailles de police) sont des plages d'édition conseillées,
pas des plafonds JSON : une valeur finie au-delà de 10 fois cette plage est
acceptée. Les minima et contraintes structurelles restent valides, notamment
les opacités/ratios bornés, les colonnes de grille (1–48), les choix discrets
et le zoom. Les pourcentages représentant des ratios utilisent des pas de
1 %, par exemple `12 %` est stocké comme `0.12`.

Le moteur JSON accepte des types concis et lisibles partout dans le document :

| Concept | Syntaxe recommandée pour l'IA | Syntaxes alternatives acceptées |
| :--- | :--- | :--- |
| **Couleurs du thème (à privilégier — Material 3)** | `"theme:primary"`, `"theme:onPrimary"`, `"theme:primaryContainer"`, `"theme:onPrimaryContainer"`, `"theme:surface"`, `"theme:surfaceContainerLow"`, `"theme:onSurface"`, `"theme:onSurfaceVariant"`, `"theme:outlineVariant"` | Tous les rôles `ColorScheme` Material 3 : `secondary*`, `tertiary*`, `surfaceDim`, `surfaceBright`, `surfaceContainer*`, `outline`, `inverseSurface`, `onInverseSurface`, `inversePrimary`, `error*`, `onError*`, `shadow`, `scrim`, `surfaceTint` et rôles `*Fixed*` |
| **Couleurs fixes (`accent` ou palette imposée)** | Chaîne hexadécimale `"#RRGGBB"` (ex: `"#5268D9"`) ou `"#AARRGGBB"` avec transparence (ex: `"#80FFFFFF"`) | `"#RGB"`, `"#ARGB"`, `"0xAARRGGBB"` ou entier ARGB 32 bits |
| **Dimensions de slot** | `"64px"`, `"50%"`, ou nombre `64` (pixels) | `{"value": 64, "unit": "px" \| "percent"}` |
| **Tailles préférées** | `[240, 64]` ou `{"width": 240, "height": 64}` | `[null, 56]` (largeur infinie dans un composant natif) |
| **Graisse (`fontWeight`)** | `"light"`, `"normal"`, `"medium"`, `"semibold"`, `"bold"` | `100`, `200`, `300`, `400`, `500`, `600`, `700`, `800`, `900` |
| **Liaison JSON (`binding`)** | `"clients[?].nom"` (repository hérité) ou `"<repoId32Hex>:clients[?].nom"` | `{"repositoryId": "...", "path": "clients[?].nom"}` ; `"@nom"`, `"@stats.total"`, `"@actifs[?].nom"` ou `"articles[?].@montant"` pour des calculs déclarés par code, en lecture seule |
| **Types de placements** | `"registry:Layout"`, `"registry:Card"`, `"registry:Expansible"`, `"registry:Menu"`, `"registry:Value"`, `"registry:Action"`, `"registry:Indicator"`, `"registry:Separator"`, `"registry:ListView"`, `"registry:Tab"`, `"registry:Chart"`, `"registry:TreeView"`, `"registry:Table"`, `"registry:IterableContent"`, `"registry:ApplicationBar"`, `"registry:BottomNavigationBar"`, `"registry:BottomAppBar"`, `"registry:NavigationRail"` | `"Layout"`, `"Card"`, `"Expansible"`, `"Menu"`, `"MenuAnchor"`, `"Value"`, `"Action"`, `"Button"`, `"Indicator"`, `"SuperIndicator"`, `"Icon"`, `"Separator"`, `"SuperSeparator"`, `"Divider"`, `"Spacer"`, `"ListView"`, `"List"`, `"Tab"`, `"Tabs"`, `"Chart"`, `"Graph"`, `"SuperChart"`, `"AppBar"`, `"BottomBar"`, `"NavigationRail"`, `"Rail"` |

> **Règle Maître / Esclave (attributs JSON imbriqués)** : `JsonAttributePath` ne supporte ni jointure ni filtre relationnel (`clientId`). Modélise toujours les relations Maître / Esclave par des **attributs imbriqués** dans l'objet maître (`"<repo>:clients[?].commandes"` pour une collection esclave, `"<repo>:clients[?].commandes[?].montantHt"` pour son détail ou ses cellules, `"<repo>:clients[?].adresse.ville"` pour un sous-objet 1-1) — jamais par deux tableaux plats séparés. Voir [`REPOSITORY_JSON_AI_GUIDE.md`](REPOSITORY_JSON_AI_GUIDE.md) (section 3.3).

### Règle impérative d'héritage de repository & branches sœurs (Pattern Maître / Détail)

1. **Périmètre strict de la liaison courte héritée** :
   - La forme courte sans identifiant de repository (ex. `clients[?].nom`) est réservée **exclusivement aux composants enfants directs** d'un conteneur fournissant déjà ce scope (à l'intérieur du `template` d'une `ListView`, des cellules d'une `Table`, ou du `content` d'un `SuperTab` dynamique).
   - L'héritage ne se propage **jamais horizontalement entre branches sœurs** d'un layout (par exemple du panneau `west` vers la fiche détaillée en zone `center`).

2. **Règle absolue pour la fiche détaillée (branche sœur)** :
   - Tout composant situé en dehors de l'arborescence de la liste source — qu'il s'agisse de champs atomiques `SuperValue`, de KPIs, de sous-listes imbriquées ou de graphiques `Chart` — **doit impérativement déclarer le `repositoryId` explicite** :
     - Forme compacte recommandée : `"<repoId>:comptes[?].propriété"` ou `"<alias>:comptes[?].propriété"`
     - Forme objet : `{"repositoryId": "<repoId>", "path": "comptes[?].propriété"}`

3. **Mécanisme de sélection Maître / Détail** :
   - Le runtime synchronise automatiquement l'indice sélectionné `[?]` entre tous les composants partageant le même `repositoryId` dans le document. Préciser le préfixe du repository est ce qui permet à la vue centrale de se synchroniser avec la ligne active du volet latéral.

---

### Liaisons sur des attributs calculés

- `@nom` lit un calcul racine ; `@stats.total` lit une propriété de son résultat ; `@actifs[?].nom` lit une ligne d'un tableau calculé ; `articles[?].@montant` lit un calcul par ligne (`scope: 'articles[?]'`).
- Tout chemin contenant un segment calculé `@nom` est **strictement en lecture seule** (pas de `mode: "input"` ni `addArrayItem`). Ne lie jamais un `@calcul` absent de `REPOSITORIES DISPONIBLES` ou non déclaré dans `"repositories.*.calculatedAttributes"`.
- Pour les règles complètes de déclaration QuickJS (`"calculatedAttributes"`), dépendances et cache, consulte [`REPOSITORY_JSON_AI_GUIDE.md`](REPOSITORY_JSON_AI_GUIDE.md).

### Couleurs du thème Material 3 (`theme:<rôle>` à privilégier)

**Règle de compatibilité Material 3** : privilégie systématiquement les couleurs de thème `"theme:<rôle>"` plutôt que des valeurs hexadécimales `#RRGGBB` codées en dur (sauf pour la propriété racine `"accent"` ou demande explicite d'une couleur fixe). Ainsi, tout l'écran s'adapte automatiquement au `ColorScheme` Material 3 généré depuis `accent` ainsi qu'au basculement entre mode clair (`"light"`) et mode sombre (`"dark"`), en respectant les paires de contraste Material 3 (`surface*` $\leftrightarrow$ `onSurface` / `onSurfaceVariant`, `primaryContainer` $\leftrightarrow$ `onPrimaryContainer`, `secondaryContainer` $\leftrightarrow$ `onSecondaryContainer`, `errorContainer` $\leftrightarrow$ `onErrorContainer`).

Les références `theme:rôle` sont sensibles à la casse et suivent le thème actif
au rendu : elles ne sont pas converties en hexadécimal lors de la sauvegarde ou
de l'export compact. Les rôles inconnus sont rejetés. Elles s'utilisent dans les
propriétés de couleur des composants, styles, états, dégradés, ombres et néons.
Exemple : `"styles": {"card": {"color": "theme:primaryContainer",
"borderColor": "theme:outlineVariant"}}`. La propriété racine `accent` reste une couleur
fixe, puisqu'elle sert à générer le `ColorScheme`. Pour le style `background`,
les rôles sont résolus depuis le schéma généré par cet accent et la luminosité
demandée, sans boucle de dépendance avec la couleur du fond.

## 2. Architecture GenUI : Un seul format plat par ID

Toute l'interface est représentée par des dictionnaires plats indexés par l'`id` de chaque instance :
1. **`components`** (`Map<String, ComponentConfig>`) : contient **tous** les composants, chacun identifié par son discriminateur `"type"` :
   - `"layout"` (`SuperLayoutConfig`)
   - `"native"` (`NativeComponentConfig`)
   - `"scaffold"` (`ScaffoldPageConfig`)
   - `"a4Document"` (`A4PageConfig`, page document A4 multi-feuilles pour l'aperçu et la génération PDF)
   - `"value"` (`SuperValueConfig`)
   - `"action"` (`SuperActionConfig`)
   - `"indicator"` (`SuperIndicatorConfig`, icône d'état et badge optionnel pilotés par `states`)
   - `"separator"` (`SuperSeparatorConfig`, séparateur `divider` ou espaceur `spacer`, horizontal ou vertical, avec ou sans libellé)
   - `"list"` (`SuperListViewConfig`, qui embarque directement son `"template"` de ligne)
   - `"tab"` (`SuperTabConfig`, barre d'onglets `TabBar` + vues `TabBarView` en mode statique ou dynamique)
   - `"conditional"` (`SuperConditionalConfig`, conteneur conditionnel choisissant la branche `"case:<valeur>"` ou `"default"` selon une liaison de repository)
   - `"chart"` (`SuperChartConfig`, graphique `fl_chart` lié à un tableau JSON)
   - `"treeView"` (`SuperTreeViewConfig`, arbre hiérarchique à 2 zones `header` et `data`)
   - `"table"` (`SuperTableConfig`, tableau multi-colonnes avec colonnes figées et `IterableContent` de ligne)
2. **`styles`** (`Map<String, ContainerStyle>`) : contient les styles visuels des surfaces (`background`, cartes `Card`, lignes de `ListView` indexées sous `<listId>:item`, lignes de `TreeView`/`Table` via leur `itemId`, `IterableContent`). **Attention** : un composant placé en `"registry:Layout"` (`SuperLayout`) est purement structurel et **n'a pas de surface** — `styles[<layoutId>]` est ignoré au rendu ; pour colorer/styliser un conteneur de grille, utilise `"registry:IterableContent"` (même ID dans `styles` et dans `components` avec `"type": "layout"`) ou enveloppe le `Layout` dans une `"registry:Card"`.
3. **`behaviors`** (`Map<String, List<ComponentBehavior>>`) : contient les comportements attachés aux composants, structurés en **3 paramètres** : événement déclencheur (`event`), condition de garde optionnelle (`validator`) et action polymorphe (`action`, ex. `"goToPage"`, `"runJavaScript"`, `"sortCollection"`, `"filterCollection"`, `"emitEvent"`, `"datasource"`, etc.). Voir le guide dédié [`BEHAVIOR_JSON_AI_GUIDE.md`](BEHAVIOR_JSON_AI_GUIDE.md).
4. **`pageCatalog`** : catalogue des pages routées (`pages`, `homePageId`). Chaque page déclare `id`, `name`, `path`, et optionnellement `pageType` (`"standard"` par défaut, `"a4Document"` pour les documents PDF A4, `"dialog"`, `"bottomSheet"`, `"sideSheet"` pour les pages modales avec `modalWidth`/`modalHeight` optionnels et `showCloseButton`: `true` par défaut, `false` pour masquer le bouton `×` en haut à droite) ainsi qu'une surcharge responsive optionnelle `layoutOverride` (`containerMode`: `"fullPage"` | `"constrained"`, `maxWidth`, `mobileGutter`, `tabletGutter`, `desktopGutter`, `largeDesktopGutter`).
   - **Contraintes strictes de `path`** : doit commencer par un seul `/`, être **différent de `"/"`** (la route `"/"` existe déjà côté hôte pour `"root"` / `"mainLayout"` — ne la redéclare jamais dans `pageCatalog`), ne pas se terminer par `"/"`, ne contenir ni espace, ni `"?"`, ni `"#"`, et ne pas chevaucher une route codée existante. Pour personnaliser l'écran principal `"/"`, modifie directement `"root"` et `"mainLayout"`, ou déclare une page avec un chemin distinct (ex. `"/accueil"`) et renseigne `"homePageId"`.
5. **`responsiveLayout`** (optionnel à la racine) : configuration responsive globale du `body` des pages (`containerMode`: `"fullPage"` par défaut ou `"constrained"`, `maxWidth`: `1440` par défaut, `gutters`: `{"mobile": 24, "desktop": 32}`, `breakpoints`: `{"mobileWidth": 375, "tabletMinWidth": 768, "desktopMinWidth": 1280, "largeDesktopMinWidth": 1440}`).
6. **`usages`** (`Map<String, ComponentUsage>`) : rôle déclaré d'une instance,
   indexé par l'ID du composant (`"explanation"` avec `translationKey` ARB,
   `"dynamicData"`, `"staticData"`, `"userInput"`, `"action"`, `"layout"`,
   `"decoration"`, `"feedback"`). Lis les usages existants et renseigne
   **obligatoirement un usage pour chaque nouveau composant sans liaison de
   données** (voir « Usages des composants » ci-dessous).

**Ordre d'émission recommandé pour le streaming live** : le moteur applique
les entrées complètes du patch `"vibe"` en direct au fil du flux SSE. Afin que
l'utilisateur voie les pages et les zones apparaître puis se remplir en temps
réel, émets les clés dans cet ordre :
1. `pageCatalog` et les éventuels réglages globaux de thème (`mode`, `accent`, etc.) ;
2. `styles` ;
3. `components` de **haut en bas (Top-Down)** : d'abord la page ou le conteneur parent/racine avec ses `placements`, `slotTypes` et `slotLabels`, puis les sous-conteneurs/zones dans l'ordre visuel, et enfin les composants feuilles de chaque zone ;
4. `behaviors` et `usages`.

**Règle obligatoire à la création** : dans le même patch que chaque nouveau
composant, fournis son **nom d'édition explicite** dans les `slotLabels` de son
parent et son **usage** dans `usages[<id>]`. Cette règle couvre aussi les
conteneurs, boutons, icônes et séparateurs, pas seulement les textes.
Seule exception pour l'usage : un composant lié à des données, y compris par
le patch de création, ne reçoit pas de proposition d'usage ; son nom reste
obligatoire. N'attends pas une demande de renommage ou de classification.
Les extraits centrés sur une propriété dans la suite du guide ne dispensent
pas de cette règle : complète toujours les noms et usages lors d'une création.

### Noms des composants en mode édition

Le nom affiché par **Renommer** dans le menu contextuel est le nom du slot,
pas l'ID technique du composant. Donne **systématiquement, dès sa création**,
à chaque instance un nom non vide, court, lisible et distinctif, notamment aux
composants `"value"` (`"Nom"`, `"E-mail"`, `"Téléphone"` plutôt que le libellé
générique `"Valeur"`). Un ID descriptif ou un texte visible ne remplace pas
ce nom. Conserve les noms des instances existantes sauf demande explicite.

Enregistre ce nom dans `slotLabels` de la configuration du parent qui contient
le slot, avec l'ID de l'enfant comme clé. Dans le JSON plat, cela donne
`components[<parentId>].slotLabels[<childId>]` — **pas** un champ à la racine
de `components`, ni un champ de la configuration de l'enfant. Exemple :

```json
{
  "components": {
    "form": {
      "type": "layout",
      "slotLabels": {
        "client-name": "Nom",
        "client-email": "E-mail"
      },
      "placements": {
        "center": [
          { "id": "client-name", "type": "registry:Value" },
          { "id": "client-email", "type": "registry:Value" }
        ]
      }
    },
    "client-name": {
      "type": "value",
      "label": "Saisir le nom",
      "binding": "clients[?].nom"
    },
    "client-email": {
      "type": "value",
      "binding": "clients[?].email"
    }
  }
}
```

Les configurations `"layout"`, `"native"`, `"tab"`, `"conditional"`,
`"treeView"` et `"table"` exposent `slotLabels` directement. Pour une cellule
du gabarit d'une liste, le layout est embarqué dans la configuration de la
liste : utilise
`components[<listId>].template.slotLabels[<childId>]`. `SuperValueConfig.label`
est distinct : il définit le libellé du champ rendu à l'écran (`"Saisir le
nom"` dans l'exemple) et ne renomme pas l'instance dans l'éditeur. Sans entrée
dans `slotLabels`, un `SuperValue` conserve son libellé de slot par défaut,
`"Valeur"`.

### Usages des composants

`usages[<id>]` déclare le rôle fonctionnel d'une instance, indexée par son
`id` de placement (le même que dans `components` lorsqu'elle a une
configuration) ; l'utilisateur peut aussi le saisir dans le dialogue
**Renommer**. Les usages préparent la traduction des textes et le choix
ultérieur des liaisons de données. Valeurs de `"kind"` :

| `kind` | Rôle |
| :--- | :--- |
| `"explanation"` | Texte d'explication à traduire (titre, libellé, aide). **Exige** `"translationKey"`. |
| `"dynamicData"` | Valeur issue des données de l'application (texte d'exemple à lier plus tard à un repository). |
| `"staticData"` | Contenu fixe, ni traduit ni lié (référence, code, constante). |
| `"userInput"` | Champ, choix ou contrôle modifié par l'utilisateur. |
| `"action"` | Bouton, lien ou élément déclenchant une action ou une navigation. |
| `"layout"` | Conteneur ou zone organisant d'autres composants. |
| `"decoration"` | Icône, image ou séparateur purement visuel. |
| `"feedback"` | Message d'erreur, de chargement, de vide ou de succès. |

Règles :

- **Renseigné à la création (ou déduit par défaut)** : chaque nouveau composant
  sans liaison reçoit un usage dans `Appearance.usages`. Le moteur déduit
  automatiquement l'usage standard lorsqu'il est omis dans le patch : `layout`
  pour un conteneur (`layout`, `Card`, `Scaffold`, `ListView`, `Table`, `Tab`,
  etc.), `action` pour un bouton (`SuperAction`), `userInput` pour un champ de
  saisie/choix (`mode: "input"` ou `kind: "choice"`), `decoration` pour un
  séparateur/indicateur, et `explanation` (avec `translationKey` dérivée du
  libellé/texte) pour un `SuperValue` d'affichage simple. Pour accélérer le
  streaming des grands écrans, n'émets dans `"usages"` que les rôles métier
  spécifiques non déductibles (`"dynamicData"`, `"staticData"`, `"feedback"`,
  ou une `"translationKey"` personnalisée).
- **Composants sans liaison uniquement** : propose un usage seulement pour un
  composant dont la configuration (`components[<id>]`, y compris ses `states`)
  ne contient ni `binding`, ni `optionsBinding`, ni `propertyBindings`, ni
  `states.binding`. Une proposition sur un composant lié — même lié dans le
  même patch — est ignorée.
- **Clé de traduction** : `"translationKey"` est obligatoire pour
  `"explanation"` et interdite pour les autres types. Format ARB lowerCamelCase
  (`^[a-z][a-zA-Z0-9_]*$`, sans espace ni accent), dérivé du sens du texte :
  `"Titre du profil"` → `"profileTitle"`. Ne réutilise une clé existante que
  pour un texte identique.
- **Fusion par ID** : n'émets que les entrées à ajouter ou à modifier ; `null`
  supprime un usage. Ne modifie ni ne supprime un usage existant sans demande
  explicite de l'utilisateur.
- **Objet strict** : un usage contient uniquement `"kind"` et, pour
  `"explanation"`, `"translationKey"`.
- **Atomicité stricte clé/valeur (`1 attribut métier = 1 SuperValue`, jamais de concaténation dans `text`)** :
  ne concatène **jamais** un libellé et une donnée dans la propriété `text` d'un
  même `SuperValue` (proscrire `"text": "Client : Jean Dupont"`), ni plusieurs
  champs métier ou un récapitulatif multi-lignes dans un bloc `textarea`.
  - **Cas standard à privilégier en mode visualisation (`mode: "display"`)** :
    utilise **1 seul `SuperValue`** en renseignant sa propriété native **`label`**
    pour l'étiquette et **`text`** (usage `"dynamicData"` ou `"staticData"`) ou
    **`binding`** pour la valeur (ex: `{"type": "value", "label": "Client", "text": "Jean Dupont"}`).
  - **Exception (style de label fortement personnalisé)** : ne décompose en
    **2 `SuperValue` distincts** (`1 SuperValue` étiquette fixe en `"explanation"` +
    `translationKey`, et `1 SuperValue` valeur en `"dynamicData"` ou `binding`)
    **que si** le label exige un style typographique/visuel ou un placement sur
    mesure (ex: ligne horizontale `spaceBetween`, taille/couleur/graisse custom
    propre au label).

```json
{
  "usages": {
    "form-title": { "kind": "explanation", "translationKey": "profileFormTitle" },
    "client-name-sample": { "kind": "dynamicData" },
    "currency-code": { "kind": "staticData" }
  }
}
```

### Exemple complet d'écran

Les racines `root` et `mainLayout`, ainsi que le slot `scaffold:body`, sont
fournis par l'hôte. Les autres instances ci-dessous sont nommées dans leur
parent ; chacune reçoit un usage sauf celles qui possèdent une liaison. Par
défaut, `styles["background"]` ne reçoit aucun `padding` (`0` par défaut, inutile
avec les composants Flutter).

```json
{
  "version": 1,
  "mode": "light",
  "accent": "#5268D9",
  "styles": {
    "background": { "color": "theme:surfaceContainerLowest", "padding": 0 },
    "card-detail": { "color": "theme:surface", "radius": 16, "padding": 20, "borderWidth": 1, "borderColor": "theme:outlineVariant" },
    "list-clients:item": { "color": "theme:surfaceContainerLow", "radius": 10, "paddingInsets": [10, 38, 10, 12], "hoverEffect": true }
  },
  "behaviors": {
    "list-clients:item": [
      {
        "id": "b-view-client",
        "event": "onTap",
        "action": { "type": "goToPage", "pagePath": "/details" }
      }
    ]
  },
  "components": {
    "root": {
      "type": "native",
      "regions": { "appBar": true, "body": true },
      "slotLabels": {
        "main-appbar": "Barre de titre",
        "scaffold:body": "Espace principal"
      },
      "placements": {
        "appBar": [{ "id": "main-appbar", "type": "registry:ApplicationBar" }],
        "body": [{ "id": "scaffold:body", "type": "scaffold:body" }]
      }
    },
    "main-appbar": {
      "type": "native",
      "regions": { "title": true },
      "slotLabels": { "app-title": "Titre de l'application" },
      "placements": {
        "title": [{ "id": "app-title", "type": "registry:Value" }]
      }
    },
    "app-title": {
      "type": "value",
      "text": "Gestion des Clients",
      "fontSize": 18,
      "fontWeight": "semibold"
    },
    "mainLayout": {
      "type": "layout",
      "west": true,
      "westSize": 260,
      "resizeSides": true,
      "slotLabels": {
        "list-clients": "Liste des clients",
        "card-detail": "Fiche client"
      },
      "placements": {
        "west": [{ "id": "list-clients", "type": "registry:ListView" }],
        "center": [{ "id": "card-detail", "type": "registry:Card" }]
      }
    },
    "list-clients": {
      "type": "list",
      "binding": {
        "repositoryId": "0123456789abcdef0123456789abcdef",
        "path": "clients"
      },
      "itemExtent": 56,
      "spacing": 8,
      "allowAdd": true,
      "allowRemove": true,
      "template": {
        "slotLabels": { "row-client-nom": "Nom du client" },
        "placements": {
          "center": [{ "id": "row-client-nom", "type": "registry:Value" }]
        }
      }
    },
    "row-client-nom": {
      "type": "value",
      "binding": "clients[?].nom"
    },
    "card-detail": {
      "type": "native",
      "regions": { "child": true },
      "slotLabels": { "layout-form": "Formulaire client" },
      "placements": {
        "child": [{ "id": "layout-form", "type": "registry:Layout" }]
      }
    },
    "layout-form": {
      "type": "layout",
      "zoneFlows": {
        "center": {
          "expandSlots": false,
          "scrollable": true,
          "crossAxisAlignment": "stretch",
          "spacing": 12
        }
      },
      "slotSizeConstraints": {
        "input-nom": { "preferredHeight": "64px", "padding": 8 },
        "btn-save": { "fitContent": true }
      },
      "slotLabels": {
        "input-nom": "Nom complet",
        "btn-save": "Enregistrer le client"
      },
      "placements": {
        "center": [
          { "id": "input-nom", "type": "registry:Value" },
          { "id": "btn-save", "type": "registry:Action" }
        ]
      }
    },
    "input-nom": {
      "type": "value",
      "mode": "input",
      "label": "Nom complet",
      "binding": "pan_model_repository:clients[?].nom"
    },
    "btn-save": {
      "type": "action",
      "kind": "textAndIcon",
      "variant": "filled",
      "label": "Enregistrer",
      "icon": "save",
      "color": "theme:onPrimary",
      "iconColor": "theme:onPrimary"
    }
  },
  "usages": {
    "main-appbar": { "kind": "layout" },
    "app-title": { "kind": "explanation", "translationKey": "clientManagementTitle" },
    "card-detail": { "kind": "layout" },
    "layout-form": { "kind": "layout" },
    "btn-save": { "kind": "action" }
  },
  "pageCatalog": {
    "pages": [],
    "homePageId": null
  }
}
```

---

## 3. Mode "Vibe" (`applyVibe` / `surfaceUpdate` incrémental)

En mode Vibe (`AppearanceTransfer.applyVibe` ou `AppearanceCodec.patchFromJson`), tu n'as **pas besoin de renvoyer tout l'écran**. Tu envoies uniquement les clés modifiées dans `components`, `styles`, `behaviors`, `usages` ou `pageCatalog` :

1. **Modifier partiellement un composant ou un style existant** : fournis son `id` dans `components` ou `styles` avec uniquement les propriétés à changer (le champ `"type"` peut être omis si le composant existe déjà).
2. **Ajouter un composant** : déclare son entrée avec son `"type"` dans `components` et ajoute sa référence `{"id": "...", "type": "registry:..."}` dans les `placements` de son conteneur parent, en réémettant tous les placements existants de ce parent (voir la règle d'or ci-dessous). Dans ce même patch, fournis obligatoirement son nom dans les `slotLabels` du parent (ou de son `template` pour une liste) et son entrée `usages[<id>]` s'il est sans liaison. Fais de même pour chaque descendant créé.
3. **Supprimer un composant** : passe son entrée à `null` dans `components` (`"components": { "old-id": null }`). Il est automatiquement supprimé de `components`, de `styles` et de `usages`, et retiré des `placements` de ses parents.

```json
{
  "styles": {
    "card-detail": { "radius": 24, "elevation": 6 }
  },
  "components": {
    "app-title": { "text": "Nouveau Titre CRM", "color": "#5268D9" },
    "list-clients": {
      "spacing": 12,
      "template": {
        "east": true,
        "autoSides": ["east"],
        "slotLabels": { "btn-delete": "Supprimer le client" },
        "placements": {
          "center": [{ "id": "row-client-nom", "type": "registry:Value" }],
          "east": [{ "id": "btn-delete", "type": "registry:Action" }]
        }
      }
    },
    "btn-delete": {
      "type": "action",
      "kind": "icon",
      "variant": "icon",
      "icon": "delete"
    },
    "old-widget": null
  },
  "usages": {
    "btn-delete": { "kind": "action" }
  }
}
```

#### Règle d'or sur les `placements` : préservation des listes et régions sœurs

La fusion Vibe est incrémentale **au niveau des propriétés d'un composant**, mais **pas à l'intérieur de `placements`** : dès qu'un patch contient la clé `placements` d'un conteneur (`root`, page du `pageCatalog`, `mainLayout`, `SuperTab`, `template` d'une liste, etc.), cette map **remplace intégralement** l'ancienne. Chaque zone ou région absente du patch est vidée, et chaque liste fournie remplace la liste existante (aucun ajout en fin de liste). Pour les composants `"native"` / `"scaffold"` (dont `root`), la clé `regions` est elle aussi remplacée en bloc.

- **Pas de mise à jour partielle des régions parentes** : lorsqu'un patch modifie les `placements` d'un conteneur, il **doit obligatoirement renvoyer l'intégralité des régions et des slots existants à conserver** dans ce conteneur, dans leur ordre actuel, en plus des ajouts. S'il envoie `regions`, il doit aussi y réémettre toutes les régions actives.
- **Si les placements ne changent pas, n'envoie pas la clé `placements`** : pour modifier uniquement des propriétés (titre, `zoneFlows`, `bodyMode`, etc.), omets `placements` et `regions` ; les placements existants sont alors conservés.
- **Exemple critique avec `root`** : pour ajouter ou modifier une `bottomNavigationBar`, le patch sur `root` doit impérativement réémettre ses placements existants. Le patch suivant est **incorrect**, car il vide les régions `appBar` et `body` et détache tout l'écran principal (`mainLayout` et ses enfants restent dans `components` mais ne sont plus affichés) :

  ```json
  "root": {
    "placements": {
      "bottomNavigationBar": [{ "id": "crm-bottombar", "type": "registry:BottomAppBar" }]
    }
  }
  ```

  Version **correcte** :

  ```json
  "root": {
    "regions": { "appBar": true, "body": true, "bottomNavigationBar": true },
    "placements": {
      "appBar": [{ "id": "crm-appbar", "type": "registry:ApplicationBar" }],
      "body": [{ "id": "scaffold:body", "type": "scaffold:body" }],
      "bottomNavigationBar": [{ "id": "crm-bottombar", "type": "registry:BottomAppBar" }]
    }
  }
  ```

- **Règle d'invariance de `scaffold:body`** : le placement `{"id": "scaffold:body", "type": "scaffold:body"}` dans `root.placements.body` ne doit **jamais** être omis ou remplacé lors d'une mise à jour de `root`, sous peine de détacher tout l'écran principal.

---

### 3.1. Cibler le composant réellement affiché, pas son slot hôte

**Une entrée dans `components` ne crée pas à elle seule un widget visible.** Le composant doit être monté par l'application hôte ou référencé dans les `placements` d'un parent lui-même affiché.

Dans la page principale standard de SuperDesigner, le chemin de rendu est :

`root` → région `body` → slot hôte `scaffold:body` → layout `mainLayout`.

- **`scaffold:body` est un emplacement fourni par l'hôte, pas l'ID du layout à configurer.** N'écris jamais `"components": {"scaffold:body": {"type": "layout", ...}}` pour modifier ce contenu : cela ne configure pas le `SuperLayout` monté par l'hôte.
- Pour modifier ce layout, écris dans **`components["mainLayout"]`** et conserve le placement hôte `{"id":"scaffold:body","type":"scaffold:body"}` dans `root.placements.body`.
- Pour une autre page ou une autre application hôte, utilise les IDs réels du contexte courant (`pageCatalog`, export, scope et informations de l'hôte). Ne suppose pas que tous les layouts s'appellent `mainLayout` et ne déduis pas leur ID du nom d'une région.
- Un slot hôte peut exister sans configuration dans `components`. Ne le transforme pas en composant standard pour « compléter » le JSON.
- Le scope doit identifier le composant configurable, distinct de son slot hôte : pour la zone Centre de ce layout, `componentId` vaut `mainLayout` et `zoneId` vaut `center`, pas `componentId: scaffold:body`. Si le scope et l'état courant sont contradictoires, signale l'incohérence dans `message` avec `vibe: null`, sans inventer de correspondance ni produire de patch hors scope. Cette incohérence doit être corrigée par l'application hôte, pas contournée par le JSON.

**Exemple de patch pour ajouter un titre dans un `mainLayout` initialement vide :**

```json
{
  "components": {
    "mainLayout": {
      "type": "layout",
      "slotLabels": { "form-title": "Titre du profil" },
      "zoneFlows": {
        "center": {
          "expandSlots": false,
          "scrollable": true,
          "padding": 24,
          "spacing": 16,
          "crossAxisAlignment": "stretch"
        }
      },
      "placements": {
        "center": [{ "id": "form-title", "type": "registry:Value" }]
      }
    },
    "form-title": {
      "type": "value",
      "text": "Profil socio-démographique",
      "fontSize": 24,
      "fontWeight": "bold"
    }
  },
  "usages": {
    "form-title": { "kind": "explanation", "translationKey": "profileFormTitle" }
  }
}
```

Si la zone contient déjà des composants à conserver, inclus aussi leurs placements dans la liste envoyée, ainsi que les placements des autres zones du layout (`north`, `west`, etc.) à conserver.

### 3.2. Vérifications obligatoires avant d'émettre un patch

1. **JSON strict** : aucune virgule finale, aucun commentaire, aucune clé dupliquée, aucun retour à la ligne brut à l'intérieur d'une chaîne. Écris `"Autre"` sur une seule ligne ; pour un saut de ligne intentionnel dans un texte, utilise l'échappement `\n`.
2. **Cible et scope** : vérifie que l'ID modifié est celui du composant rendu et que le patch respecte le périmètre fourni par le chat. N'invente pas de conteneur parent si les informations manquent.
3. **Références complètes** : chaque nouveau composant standard configurable placé (par exemple `registry:Value`, `registry:Action` ou `registry:Layout`) doit avoir sa configuration avec le bon `type` dans ce patch. Une configuration peut être omise uniquement si le composant existe déjà dans le contexte courant ou si son implémentation est explicitement fournie par l'hôte. Ne réutilise pas un ID opaque supposé existant sans cette preuve.
4. **Rattachement au rendu** : vérifie le chemin de chaque nouveau composant jusqu'à une page ou un composant effectivement affiché. Déclarer un formulaire et ses enfants sans rattacher son layout ne suffit pas.
5. **Préservation des placements existants** : pour chaque conteneur dont le patch contient `placements` (ou `regions`), vérifie que toutes les zones, régions et slots existants à conserver sont réémis (voir la règle d'or de la section 3). Pour `root`, `root.placements.body` doit toujours contenir `{"id": "scaffold:body", "type": "scaffold:body"}`.
6. **Schéma documenté** : utilise uniquement les propriétés et valeurs autorisées pour chaque type. Le `type` de configuration (`"value"`) et le `type` de placement (`"registry:Value"`) ne sont pas interchangeables.
7. **Noms obligatoires** : pour chaque nouveau slot, vérifie la présence d'un nom non vide dans les `slotLabels` du parent approprié, y compris dans les gabarits de listes. Ni l'ID, ni `label`, ni `text` ne remplacent ce nom d'édition.
8. **Usages ciblés** : le moteur déduit automatiquement `usages[<id>]` pour les conteneurs (`layout`), boutons (`action`), champs de saisie (`userInput`), indicateurs/séparateurs (`decoration`) et étiquettes `SuperValue` simples (`explanation` avec `translationKey` auto-générée). N'émets dans `usages` que les rôles non déductibles (`dynamicData`, `staticData`, `feedback`, ou `translationKey` métier sur mesure), et jamais pour un composant lié.
9. **Atomicité clé/valeur, propriété `label` native & zéro bloc texte libre fourre-tout** : vérifie qu'aucun `SuperValue` ne concatène une étiquette et une donnée dans `text` (`"Clé : Valeur"`), et qu'aucun récapitulatif ou liste métier (affaires, contrats, interlocuteurs, même demandé sous les termes « résumé » ou « notes ») n'est rendu par un bloc texte libre multiligne / `textarea`. En visualisation (`mode: "display"`), **privilégie 1 seul `SuperValue` utilisant `label` + `text`/`binding`** ; ne crée 2 `SuperValue` séparés (`"explanation"` + `"dynamicData"`/`binding`) que si le label requiert un style ou une mise en page fortement personnalisés. Structure les listes/synthèses en cartes, champs unitaires, `SuperListView` ou `SuperTable`.
10. **Réponse du chat** : enveloppe le patch dans `{"message":"résumé","vibe":{...}}` (voir section 6). L'objet passé directement à `applyVibe` est le patch intérieur, pas cette enveloppe.
11. **Aucune entrée `styles[id]` sur un `registry:Layout`** : vérifie qu'aucune clé de `styles` ne cible un composant placé avec `"type": "registry:Layout"` (ni `mainLayout`). Si un conteneur de mise en page doit recevoir un fond, une bordure ou un `paddingInsets`, place-le avec `"type": "registry:IterableContent"` dans son parent (tout en gardant `components[id]` en `"type": "layout"`) ou enveloppe-le dans un `"registry:Card"`.

Ces vérifications préviennent les erreurs de génération les plus courantes ; elles ne remplacent pas le décodage, la validation des modèles ni la vérification du rendu.

---

## 4. Référence des composants du `ComponentConfigCatalog`

### 4.1. `"layout"` (`SuperLayoutConfig`)
> **Règle de style importante** : un composant placé en `"registry:Layout"` (`SuperLayout`) est **purement structurel** et ne possède **aucune surface visuelle** (`styles[id]` n'est jamais rendu sur un `registry:Layout`, ni sur `mainLayout`). Pour appliquer une couleur de fond, une bordure, un arrondi ou un padding de surface à un conteneur de zones, place-le avec `"type": "registry:IterableContent"` dans son parent (ce qui combine automatiquement la surface `styles[id]` et la grille `components[id]` de `"type": "layout"`), ou enveloppe le `"registry:Layout"` dans une `"registry:Card"`.

Dispose ses enfants selon 2 modes (`"positioning"`) :
- **`"zones"` (par défaut)** : Grille 3×3 (`nw`, `north`, `ne`, `west`, `center`, `east`, `sw`, `south`, `se`).
  - `north`, `south`, `west`, `east` (`bool`) : activation des côtés.
  - `northSize`, `southSize`, `westSize`, `eastSize` (`number`, **minimum : `20`**, plage du slider `20` à `400`) : épaisseur en pixels des côtés fixes, sans plafond JSON.
  - `autoSides` (`List<string>`) : côtés (`"north"`, `"south"`, `"west"`, `"east"`) dont l'épaisseur s'adapte automatiquement à leur contenu.
  - `nw`, `ne`, `sw`, `se` (`"row"` | `"column"` | `"none"`) : fusion des coins lorsqu'un bord horizontal (`north` / `south`) et un bord vertical (`west` / `east`) sont tous deux actifs :
    - **Bonne pratique (fortement recommandé)** : utilise **`"row"`** (le coin est absorbé par la bande `north` ou `south`, qui s'étend alors sur toute la largeur) ou **`"column"`** (le coin est absorbé par le panneau latéral `west` ou `east`, qui s'étend alors sur toute la hauteur).
    - **À éviter** : laisser `"none"` (case propre) sans placer de composant dans ce coin crée une case vide disgracieuse dans l'angle de l'écran. N'utilise `"none"` que si tu places explicitement un composant dédié dans la zone de coin correspondante (`placements.nw`, `ne`, `sw`, `se`).
  - `zoneAxes` (`Map<Zone, "row" | "column">`) : axe d'empilement des composants par zone (`"column"` par défaut).
  - `zoneFlows` (`Map<Zone, ZoneFlowConfig>`) : paramètres de flux, d'alignement et de défilement par zone :
    - `expandSlots` (`bool`, défaut `true`) :
      - `true` (`flex: 1`) : les slots sans taille préférée se partagent tout l'espace disponible de la zone.
      - `false` (`flex: 0` / taille du contenu) : chaque slot (y compris une `Card`, un `Layout` imbriqué, un `Action` ou un `Value`) prend uniquement la hauteur/largeur naturelle de son contenu au lieu de s'étirer sur toute la zone.
    - `scrollable` (`bool`, défaut `false`) : active le défilement automatique (`SingleChildScrollView`) sur l'axe de la zone si les éléments dépassent, sans compresser leurs tailles préférées.
    - `showScrollbar` (`bool`, défaut `false`) : affiche une barre de défilement (`RawScrollbar`) lorsque `scrollable` est activé.
    - `scrollbarStyle` (`ScrollbarStyleConfig`, optionnel) : personnalisation visuelle de la barre de défilement :
      - `thumbVisibility` (`bool`, défaut `true`) : maintient le curseur visible en permanence (`false` pour l'afficher uniquement pendant le défilement).
      - `trackVisibility` (`bool`, défaut `false`) : affiche la piste en arrière-plan du curseur.
      - `interactive` (`bool`, défaut `true`) : autorise le glisser du curseur.
      - `thickness` (`number`, **minimum : `2`**, plage du slider `2` à `24`, défaut `8`) : épaisseur en pixels, sans plafond JSON.
      - `radius` (`number`, **minimum : `0`**, plage du slider `0` à `24`, défaut `4`) : rayon d'arrondi en pixels, sans plafond JSON.
      - `mainAxisMargin` (`number`, **minimum : `0`**, plage du slider `0` à `48`, défaut `0`) : marge aux extrémités sur l'axe principal, sans plafond JSON.
      - `crossAxisMargin` (`number`, **minimum : `0`**, plage du slider `0` à `24`, défaut `0`) : marge latérale par rapport au bord de la zone, sans plafond JSON.
      - `thumbColor`, `trackColor`, `trackBorderColor` (`string` hex `#AARRGGBB` / `#RRGGBB`) : couleurs personnalisées du curseur, de la piste et de sa bordure.
      - `side` (`"auto"` | `"start"` | `"end"`, défaut `"auto"`) : côté d'affichage (`"start"` = gauche/haut, `"end"` = droite/bas).
    - `mainAxisAlignment` : `"start"` (défaut), `"center"`, `"end"`, `"spaceBetween"`, `"spaceAround"`, `"spaceEvenly"`.
    - `crossAxisAlignment` : `"stretch"` (défaut, occupe toute la largeur en Column / toute la hauteur en Row), `"start"`, `"center"`, `"end"`.
    - `spacing` (`number`, **minimum : `0`**, plage du slider `0` à `100`, défaut `0`) : espacement en pixels entre les composants de la zone, sans plafond JSON.
    - `padding` (`number`, **minimum : `0`**, plage du slider `0` à `200`, défaut `0`) ou `paddingInsets` (`[top, right, bottom, left]`) : marge intérieure de la zone, sans plafond JSON.
  - `resizeSides` (`bool`) et `sideResizing` (`Map<Side, bool>`) : poignées de redimensionnement utilisateur.
  - `slotSizeConstraints` (`Map<slotId, SlotSizeConstraints>`) : contraintes de taille, marges et mode d'occupation par slot enfant :
    - `minWidth`, `minHeight`, `preferredWidth`, `preferredHeight`, `maxWidth`, `maxHeight` : dimensions en `"px"` ou `"%"` (ex: `"240px"`, `"50%"`).
    - `percentBasis` : `"zone"` (défaut) ou `"layout"`.
    - `padding` (minimum `0`, sans plafond JSON) ou `paddingInsets` (`[top, right, bottom, left]`, valeurs positives ou nulles).
    - `fitContent` (`bool?`, ou alias `"flex": 0 | 1`) : surcharge par slot l'occupation sur l'axe principal :
      - `true` (ou `"flex": 0`) : le slot prend uniquement la taille de son contenu (ne s'étire pas).
      - `false` (ou `"flex": 1`) : le slot s'étire pour remplir l'espace restant de la zone (même si la zone a `expandSlots: false`).
      - `null` (omis) : suit le comportement de la zone (`zoneFlows[zone].expandSlots`).
  - **Bonne pratique (empilement de `Card`, boutons ou champs sans occuper toute la hauteur)** :
    - Par défaut dans `center`, les composants sans `preferredHeight` se partagent toute la hauteur (`expandSlots: true`). Pour empiler des cartes (`Card`) ou contrôles qui s'adaptent à la hauteur de leur contenu, configure `zoneFlows.center` avec `"expandSlots": false` (et `"scrollable": true` si la liste de composants peut dépasser l'écran), ou mets `"fitContent": true` sur les slots concernés dans `slotSizeConstraints`.
    - **À éviter** : ne mets pas `"fitContent": true` sur `"scaffold:body"` dans `"root"`, car `"scaffold:body"` est le conteneur de la page entière ; configure `zoneFlows` ou `slotSizeConstraints` dans `"mainLayout"` (ou le layout de la page).
  - **Règles de dimensionnement (`autoSides`, défilement et `Card` enveloppante)** :
    - **Règle 1 : Pas d'`autoSides` sur les volets latéraux contenant des listes ou layouts complexes**. Un panneau latéral (`westSize` ou `eastSize`) doit avoir une taille fixe explicite (ex: `340px`) sans figurer dans `autoSides` dès lors qu'il héberge une `ListView` ou un contenu défilant.
    - **Règle 2 : Jamais d'`autoSides` sur un layout feuille défilant**. Retirer `autoSides` de tout `layout` dont une zone est `scrollable: true`.
    - **Règle 3 : `card` enveloppante sans contrainte zéro**. Les cartes mono-enfant (`Card`) doivent s'étirer naturellement (`expandSlots: true` dans le parent `mainLayout`) pour que leur enfant prenne toute la hauteur disponible du viewport.
  - **Règle absolue d'auto-dimensionnement sur `mainLayout`** :
    - N'incluez **jamais** `"west"` ou `"east"` dans `autoSides` sur le conteneur racine `mainLayout` (ou tout layout parent direct de volets latéraux) : ces colonnes doivent obligatoirement être dimensionnées via `westSize` ou `eastSize` (ex: `280` à `360`).
    - La zone `center` de `mainLayout` doit toujours conserver `expandSlots: true` (valeur par défaut) avec une `Card` centrale extensible, sous peine de voir le volet latéral absorber toute la largeur disponible et occulter la vue centrale.
  - `slotLabels` (`Map<slotId, string>`) : libellés personnalisés des slots
    enfants, indexés par leur `id` de placement (voir l'exemple de nommage
    ci-dessus).
  - `placements` (`Map<Zone, List<{"id": string, "type": string}>>`) : composants placés dans chaque zone.
- **`"grid"`** : Grille libre 2D (`columns` de `1` à `48`, `rowHeight` au minimum `16`, `gap` au minimum `0`). Les plafonds des sliders (`400` pour `rowHeight`, `64` pour `gap`) ne limitent pas les valeurs JSON.

### 4.2. `"native"` (`NativeComponentConfig`) & `"scaffold"` (`ScaffoldPageConfig`) — Lien avec les widgets Flutter Material
Les composants `"native"` et `"scaffold"` sont des adaptateurs directs vers les widgets structurels standards de la bibliothèque **Flutter Material** (`package:flutter/material.dart`). Leurs noms de régions dans `regions` et `placements` reprennent exactement les paramètres nommés des constructeurs Flutter correspondants :

Pour les propriétés dimensionnelles éditées par slider (`elevation`,
`scrolledUnderElevation`, `leadingWidth`, `titleSpacing`, `notchMargin`,
`padding`, `iconSize`, `selectedFontSize`, `unselectedFontSize`,
`alignmentOffsetX`, `alignmentOffsetY`, `stretchTriggerOffset`,
`expandedHeight`, `collapsedHeight`, `actionsPadding`, `scrollPadding`),
les maxima indiqués ci-dessous décrivent la plage du slider, sans plafond JSON.
Les minima restent appliqués, sauf pour les décalages signés. Les rayons et
épaisseurs de `shape` sont également positifs ou nuls, sans plafond JSON.
Les opacités et alignements bornés conservent leurs limites structurelles.

- **Page / Écran (`"root"` ou `<pageId>` du `pageCatalog`) $\rightarrow$ `Scaffold` de Flutter** (`type: "native"` ou `"scaffold"`) :
  - **Régions** :
    - `appBar` (1 slot max, dédié au composant `"registry:ApplicationBar"`) : barre supérieure du `Scaffold` (ou premier sliver `SliverAppBar` lorsque `bodyMode` vaut `"customScrollView"`).
    - `body` (empilement vertical, toujours actif) : contenu principal de la page. Pour `"root"`, contient par défaut `{"id": "scaffold:body", "type": "scaffold:body"}` qui monte le layout `"mainLayout"`.
    - `drawer` / `endDrawer` (empilement vertical) : panneaux latéraux coulissants gauche / droite (`Drawer` Flutter).
    - `bottomNavigationBar` (1 slot max, dédié aux composants `"registry:BottomNavigationBar"` ou `"registry:BottomAppBar"`) : barre de navigation inférieure.
    - `floatingActionButton` (1 slot max) : bouton d'action flottant en bas à droite.
    - `bottomSheet` (1 slot max) : panneau persistant affiché en bas du `Scaffold`.
  - **Propriétés du `Scaffold` et mode du corps (`bodyMode`) — directement à la racine de `components["root"]` ou `components[pageId]`** :
    - `bodyMode` (`"standard"` | `"singleChildScrollView"` | `"customScrollView"`, défaut `"standard"`) :
      - `"standard"` : zone `body` fixe occupant tout l'espace disponible (`SizedBox.expand`).
      - `"singleChildScrollView"` : enveloppe la zone `body` dans un `SingleChildScrollView` (avec `SlotContentFitScope` automatique pour que `"mainLayout"` et sa zone `center` prennent la hauteur naturelle de leurs enfants sans avoir à fixer une hauteur en pixels sur `"scaffold:body"`).
      - `"customScrollView"` : affiche la page dans un `CustomScrollView` unifié où la région `appBar` devient un `SliverAppBar`, les `ListView` deviennent des `SliverList` / `SliverFixedExtentList`, et les autres composants (dont `"mainLayout"`) sont enveloppés dans des `SliverToBoxAdapter` prenant la hauteur de leurs enfants.
    - `extendBodyBehindAppBar` (`bool`, défaut `false`) : étend la zone `body` sous l'`AppBar` en haut de la page (utile avec une `ApplicationBar` transparente ou translucide).
    - `extendBody` (`bool`, défaut `false`) : étend la zone `body` derrière la `bottomNavigationBar` en bas de la page.
    - **Options de défilement** (actives lorsque `bodyMode` vaut `"singleChildScrollView"` ou `"customScrollView"`) :
      - `scrollDirection` (`"vertical"` | `"horizontal"`, défaut `"vertical"`) : axe de défilement de la page.
      - `reverse` (`bool`, défaut `false`) : inverse le sens de défilement sur l'axe principal.
      - `primary` (`bool`, défaut `true`) : associe la vue de défilement au `PrimaryScrollController` de la page.
      - `scrollPadding` (`0`..`64`, défaut `0`) : marge intérieure uniforme (en pixels) autour du contenu défilant.
      - `clipBehavior` (`"none"` | `"hardEdge"` | `"antiAlias"` | `"antiAliasWithSaveLayer"`, défaut `"hardEdge"`) : mode de découpage de la zone de défilement.

- **`"registry:ApplicationBar"` $\rightarrow$ `AppBar` / `SliverAppBar` de Flutter** (`type: "native"`, uniquement plaçable dans la région `appBar` d'une page) :
  - `useDefaultNavigation` (`bool`, `true` par défaut) : laisse Flutter gérer automatiquement le bouton menu (`Drawer`) ou retour (`BackButton`). Mettre à `false` pour utiliser une région `leading` personnalisée.
  - **Régions** :
    - `leading` (1 slot max) : widget placé tout à gauche de l'`AppBar` (ignoré si `useDefaultNavigation: true`).
    - `title` (liste horizontale) : titre ou barre d'outils centrale de l'`AppBar`.
    - `actions` (liste horizontale) : boutons/actions alignés à droite de l'`AppBar`.
    - `bottom` (1 slot max) : barre secondaire sous l'`AppBar` (ex. onglets ou barre de filtres).
    - `flexibleSpace` (1 slot max) : arrière-plan de l'`AppBar` / `SliverAppBar` (déployé sur `expandedHeight` en mode sliver).
  - **Propriétés de style Flutter `AppBar` (directement à la racine de `components[appBarId]`)** :
    - Couleurs (`"#RRGGBB"` ou `"#AARRGGBB"`) : `backgroundColor`, `foregroundColor`, `surfaceTintColor`, `shadowColor`.
    - Élévation & transparence : `elevation` (`0`..`24`), `scrolledUnderElevation` (`0`..`24`), `forceMaterialTransparency` (`bool`, défaut `false`).
    - Forme et bordure (`shape`) : objet `{"kind": "rounded" | "continuous" | "beveled" | "stadium" | "linear", "radius": 16, "radii": [topLeft, topRight, bottomRight, bottomLeft], "borderWidth": 1, "borderColor": "#RRGGBB", "top": bool, "right": bool, "bottom": bool, "left": bool}` (ou raccourcis : nombre `16` pour un rayon uniforme, ou `[0, 0, 16, 16]` pour des coins indépendants). Plages des sliders : rayon `0`..`64`, bordure `0`..`16`.
    - Dimensions & espacements : `toolbarHeight` (`32`..`160`, défaut `56`), `leadingWidth` (`24`..`200`, défaut `56`), `titleSpacing` (`0`..`64`, défaut `0`).
    - Comportement & opacité : `centerTitle` (`bool`), `toolbarOpacity` (`0.0`..`1.0`, défaut `1.0`, mode `AppBar` standard uniquement), `bottomOpacity` (`0.0`..`1.0`, défaut `1.0`, mode `AppBar` standard uniquement), `primary` (`bool`, défaut `true`), `excludeHeaderSemantics` (`bool`, défaut `false`), `clipBehavior` (`"none"` | `"hardEdge"` | `"antiAlias"` | `"antiAliasWithSaveLayer"`), `systemOverlayStyle` (`"light"` | `"dark"`).
  - **Propriétés spécifiques `SliverAppBar` (prises en compte lorsque la page parente est en `bodyMode: "customScrollView"`)** :
    - `pinned` (`bool`, défaut `false`) : garde la barre épinglée en haut lors du défilement.
    - `floating` (`bool`, défaut `false`) : fait réapparaître la barre dès que l'utilisateur défile vers le haut.
    - `snap` (`bool`, défaut `false`) : anime complètement l'apparition/disparition de la barre (requiert `floating: true`).
    - `stretch` (`bool`, défaut `false`) : autorise l'étirement de la barre lors d'un sur-défilement.
    - `stretchTriggerOffset` (`10`..`300`, défaut `100`) : distance de sur-défilement en pixels déclenchant l'étirement.
    - `expandedHeight` (`56`..`400`, ex. `160`) : hauteur maximale en pixels de la barre lorsqu'elle est complètement déployée.
    - `collapsedHeight` (`32`..`200`, défaut `56`, $\ge$ `toolbarHeight`) : hauteur minimale en pixels de la barre repliée.
    - `forceElevated` (`bool`, défaut `false`) : affiche l'ombre correspondant à `elevation` même lorsque le contenu ne défile pas sous la barre.
    - `useDefaultSemanticsOrder` (`bool`, défaut `true`) : utilise l'ordre standard d'accessibilité dans la barre sliver.
    - `actionsPadding` (`0`..`48`, défaut `0`) : marge horizontale intérieure en pixels autour de la zone `actions`.
    - Pour réinitialiser une propriété au thème Material 3 par défaut en mode Vibe (`applyVibe`), passe sa valeur à `null` (ex. `{"backgroundColor": null, "expandedHeight": null}`).

- **`"registry:BottomAppBar"` $\rightarrow$ `BottomAppBar` de Flutter** (`type: "native"`, uniquement plaçable dans la région `bottomNavigationBar` d'une page) :
  - **Régions** :
    - `left` (liste horizontale, alignée à gauche), `center` (liste horizontale, centrée), `right` (liste horizontale, alignée à droite).
  - **Propriétés de style Flutter `BottomAppBar` (directement à la racine de `components[bottomAppBarId]`)** :
    - Couleurs (`"#RRGGBB"` ou `"#AARRGGBB"`) : `color`, `surfaceTintColor`, `shadowColor`.
    - Élévation, forme & encoche : `elevation` (`0`..`24`, défaut `3`), `shape` (objet `NativeShapeConfig` ou raccourcis rayon / coins), `notchMargin` (`0`..`24`, défaut `4`).
    - Dimensions, marges & découpage : `height` (`32`..`160`, défaut `56`), `padding` (`0`..`48`, défaut `0`), `clipBehavior` (`"none"` | `"hardEdge"` | `"antiAlias"` | `"antiAliasWithSaveLayer"`).

- **`"registry:BottomNavigationBar"` $\rightarrow$ `BottomNavigationBar` de Flutter** (`type: "native"`, uniquement plaçable dans la région `bottomNavigationBar` d'une page) :
  - **Régions** :
    - `destinations` (liste horizontale de composants `"action"`, convertis en entrées `BottomNavigationBarItem`).
  - **Propriétés de style Flutter `BottomNavigationBar` (directement à la racine de `components[bottomNavId]`)** :
    - Couleurs (`"#RRGGBB"` ou `"#AARRGGBB"`) : `backgroundColor`, `selectedItemColor`, `unselectedItemColor`.
    - Élévation & dimensions : `elevation` (`0`..`24`, défaut `8`), `height` (`32`..`160`, défaut `56`), `iconSize` (`12`..`48`, défaut `24`), `selectedFontSize` (`8`..`32`, défaut `14`), `unselectedFontSize` (`8`..`32`, défaut `12`).
    - Disposition, libellés & comportement : `navigationBarType` (`"fixed"` | `"shifting"`), `landscapeLayout` (`"spread"` | `"centered"` | `"linear"`), `showSelectedLabels` (`bool`, défaut `true`), `showUnselectedLabels` (`bool`, défaut `true`), `enableFeedback` (`bool`, défaut `true`), `useLegacyColorScheme` (`bool`, défaut `true`), `mouseCursor` (`"click"` | `"basic"` | `"defer"` | `"none"`).

- **`"registry:NavigationRail"` $\rightarrow$ `NavigationRail` de Flutter** (`type: "native"`, alias `"NavigationRail"`, `"Rail"`) :
  - **Régions** :
    - `leading` (optionnelle, liste verticale en haut du rail), `destinations` (liste verticale de composants `"action"`, convertis en entrées `NavigationRailDestination`), `trailing` (optionnelle, liste verticale en bas du rail).
  - **Propriétés de style Flutter `NavigationRail` (directement à la racine de `components[railId]`)** :
    - Couleurs (`"#RRGGBB"` ou `"#AARRGGBB"`) : `backgroundColor`, `indicatorColor`.
    - Dimensions & alignement : `minWidth` (`36`..`200`, défaut `72`), `minExtendedWidth` (`120`..`400`, défaut `256`), `extended` (`bool`, défaut `false`), `groupAlignment` (`-1.0`..`1.0`, défaut `-1.0`), `elevation` (`0`..`24`).
    - Libellés & indicateur : `labelType` (`"none"` | `"selected"` | `"all"`), `useIndicator` (`bool`, défaut `true`).

- **`"registry:Card"` $\rightarrow$ Conteneur monoenfant (`Card` / `Container` Flutter) + surface `ContainerStyle` enrichie** (`type: "native"` + entrée associée sous le même `id` dans `styles`) :
  - `child` (1 slot unique max, région obligatoire toujours active) : comme un `Card` ou `Container` Flutter, ne prend qu'un seul composant enfant `child` (souvent un `"registry:Layout"` pour organiser plusieurs sous-composants, ou utilise `"registry:IterableContent"` si tu veux fusionner carte et grille sous le même ID).
  - **Carte vide / purement visuelle (ex. affiche, logo, miniature, séparateur ou bloc avec `fill.imageUrl`)** : si une `Card` ne contient aucun composant enfant, **ne mets jamais `"regions": { "child": false }`** (la région `child` d'une `Card` est requise et ne peut pas être désactivée). Utilise `"regions": {}, "placements": {}` (ou `"regions": { "child": true }, "placements": {}`), ou omet simplement l'entrée de `components["<cardId>"]` et définis uniquement son style dans `styles["<cardId>"]`. Pour fixer la taille de cette carte (`preferredWidth`, `preferredHeight`, etc.), déclare ses contraintes dans le `slotSizeConstraints["<cardId>"]` de son **conteneur parent** (et non sous la forme d'un objet plat dans `components["<cardId>"].slotSizeConstraints`).
  - **Style visuel de la carte (bien plus riche qu'un `Card` Flutter natif)** : se configure intégralement dans **`styles["<cardId>"]`** (système de design Material / Neumorphism / Liquid Glass, couleur unie, dégradés `linear` / `radial` / `sweep`, image de fond, coins uniformes ou par angle, bordures pleines / tiretées / pointillées par côté, ombre portée ou intérieure, halo néon, flou `backdropBlur`, motif `grain` / `lines` / `dots`, transformation 2D, effets de clic/survol et états `states` — voir § 4.7).

- **`"registry:Expansible"` $\rightarrow$ `Expansible` de Flutter** (`type: "native"`) :
  - `header` (liste horizontale) : en-tête toujours visible. Un clic sur `header` bascule l'état ouvert/fermé lorsque `headerClickToggles` vaut `true` (défaut).
  - `body` (liste verticale) : contenu dépliable animé.
  - Options propres à `Expansible` dans `components[id]` (`type: "native"`) : `initiallyExpanded` (`bool`, défaut `false`), `maintainState` (`bool`, défaut `true`), `headerClickToggles` (`bool`, défaut `true`), `toggleIcon` (`"none"` | `"chevron"` | `"arrow"` | `"plusMinus"` | `"triangle"`, défaut `"none"`), `toggleIconPosition` (`"trailing"` | `"leading"`, défaut `"trailing"`), `binding` (`"clients[?].ouvert"` ou `{"repositoryId": "...", "path": "..."}` — liaison bidirectionnelle vers un attribut booléen JSON).

- **`"registry:Menu"` $\rightarrow$ `MenuAnchor` de Flutter** (`type: "native"`, alias `"Menu"`, `"MenuAnchor"`) :
  - `header` (liste horizontale) : ancre toujours visible déclenchant l'ouverture/fermeture du menu lorsque `headerClickToggles` vaut `true` (défaut).
  - `body` (liste verticale) : zone de contenu affichée dans le popup du `MenuAnchor`.
  - Options propres à `Menu` dans `components[id]` (`type: "native"`) : `initiallyExpanded` (`bool`, défaut `false`), `headerClickToggles` (`bool`, défaut `true`), `consumeOutsideTap` (`bool`, défaut `false`), `toggleIcon` (`"none"` | `"chevron"` | `"arrow"` | `"plusMinus"` | `"triangle"`, défaut `"none"`), `toggleIconPosition` (`"trailing"` | `"leading"`, défaut `"trailing"`), `alignmentOffsetX` (`number`, `-200`..`200`, défaut `0`), `alignmentOffsetY` (`number`, `-200`..`200`, défaut `0`), `binding` (`"ui.menuOuvert"` ou `{"repositoryId": "...", "path": "..."}` — liaison bidirectionnelle vers un attribut booléen JSON).

- **`"registry:IterableContent"` $\rightarrow$ Surface stylisée + `SuperLayout` intégré (alternative compacte à `Card` + `Layout`)** :
  - Contrairement à `Card` (qui n'accepte qu'un seul `child` dans une config `"native"` et nécessite un second composant `"layout"` enfant), `IterableContent` fusionne directement **une surface stylisée** (`styles[id]`) et **une grille `SuperLayout`** (`components[id]` avec `"type": "layout"`) sous **le même `id`** !
  - De plus, `IterableContent` fournit automatiquement un `ContentHoverScope` à tous ses composants enfants, ce qui permet aux `Value`, `Action` et `styles` placés à l'intérieur de réagir à l'état automatique `contentHover` dès que le curseur survole la carte.

Propriétés communes dans `components[id]` pour `"native"` :
- `regions` (`Map<string, bool>`), `placements` (`Map<string, List<{"id": string, "type": string}>>`).
- **Flux et taille par région native** (mêmes clés et options que `zoneAxes` / `zoneFlows` d'un `"layout"`, applicables aux régions de `Page`/`Scaffold` (`body`, `drawer`, `endDrawer`, `bottomSheet`), `ApplicationBar` (`leading`, `title`, `actions`, `bottom`, `flexibleSpace`), `BottomAppBar` (`left`, `center`, `right`), `Expansible` (`header`, `body`) et `Menu` (`header`, `body`)) :
  - `regionAxes` (`Map<regionId, "horizontal" | "vertical">`) : direction du flux de la région.
  - `regionFlows` (`Map<regionId, ZoneFlowConfig>`) : `scrollable` (`bool`), `expandSlots` (`bool`), `mainAxisAlignment` (`"start" | "center" | "end" | "spaceBetween" | "spaceAround" | "spaceEvenly"`), `crossAxisAlignment` (`"start" | "center" | "end" | "stretch"`), `spacing` (`0`..`64`), `padding` (`0`..`64` ou `[top, right, bottom, left]`).
  - `regionSizes` (`Map<regionId, number>`) : hauteur/taille fixe en pixels de la région (omettre pour la taille automatique).
- `slotPreferredSizes` (`Map<childSlotId, [width, height]>`), `slotSizeConstraints` (`Map<childSlotId, SlotSizeConstraints>` — toujours indexé par l'`id` du slot enfant placé, jamais un objet `SlotSizeConstraints` direct sans clé de slot), `slotLabels` (`Map<childSlotId, string>`, au même niveau que `placements` dans la configuration native).

### 4.2 bis. `"a4Document"` (`A4PageConfig`) — Page Document A4 multi-feuilles (PDF)

Utilisé pour toute page du `pageCatalog` dont `"pageType"` vaut `"a4Document"` (`components[<pageId>]` a obligatoirement `"type": "a4Document"`).
- **Règle stricte de structure** : `"a4Document"` **n'utilise jamais** `"placements"`, `"regions"`, `"body"` ni `"slotLabels"` (ces champs sont réservés à `"scaffold"` / `"native"`). Chaque feuille du document est déclarée dans `"sheets"` et pointe vers un composant racine distinct dans `components[<rootSlotId>]` (généralement `"type": "layout"`).
- **Propriétés de `A4PageConfig`** :
  - `orientation` : `"portrait"` (`595.28 × 841.89 pt`, défaut) ou `"landscape"` (`841.89 × 595.28 pt`).
  - `margins` (nombre uniforme) ou `marginTop`, `marginRight`, `marginBottom`, `marginLeft` (`0`..`250` pt, défaut `36`).
  - `sheets` (`List<A4SheetConfig>`) : liste ordonnée des feuilles A4 explicites :
    - `id` (`string`, ex. `"sheet-1"`), `label` (`string`, ex. `"Feuille 1"`), `rootSlotId` (`string`, ID du composant racine de la feuille dans `components`), `rootSlotType` (défaut `"registry:Layout"`), `backgroundColor` (optionnel, blanc papier par défaut).
  - `headerSlotId` / `headerSlotType` / `headerHeight` (`16`..`240`, défaut `48`) et `footerSlotId` / `footerSlotType` / `footerHeight` (`16`..`240`, défaut `36`) : en-tête et pied de page optionnels répétés sur chaque feuille.
  - `showPageNumbers` (`bool`, défaut `false`), `showPageGuides` (`bool`, défaut `true`), `defaultFileName` (`string`, défaut `"document.pdf"`).
- **Export PDF** : place un bouton `"action"` sur l'écran appelant (ou dans le document) avec un comportement `"generatePdf"` (`"pageId": "<pageId>"`).

```json
{
  "pageCatalog": {
    "pages": [
      {
        "id": "page-facture-a4",
        "name": "Facture A4",
        "path": "/facture-a4",
        "pageType": "a4Document"
      }
    ]
  },
  "components": {
    "page-facture-a4": {
      "type": "a4Document",
      "orientation": "portrait",
      "margins": 36,
      "showPageNumbers": true,
      "defaultFileName": "facture.pdf",
      "sheets": [
        {
          "id": "sheet-1",
          "label": "Feuille 1",
          "rootSlotId": "facture-sheet-1",
          "rootSlotType": "registry:Layout"
        }
      ]
    },
    "facture-sheet-1": {
      "type": "layout",
      "slotLabels": { "facture-titre": "Titre facture" },
      "placements": {
        "center": [{ "id": "facture-titre", "type": "registry:Value" }]
      }
    },
    "facture-titre": {
      "type": "value",
      "text": "FACTURE",
      "fontSize": 22,
      "fontWeight": "bold"
    }
  }
}
```

### 4.3. `"value"` (`SuperValueConfig`)
Affiche un texte, un champ de saisie, une case à cocher, un interrupteur ou un sélecteur de choix :
- **Règle d'atomicité obligatoire (`1 attribut métier = 1 SuperValue`, `label` natif en visualisation & respect des `usages` — priorité absolue)** :
  - **Interdiction absolue de fusionner libellé et donnée dans `text`** : n'écris **jamais** `"Clé : Valeur"` dans le `text` d'un `SuperValue` (ex: proscrire `"text": "Total HT : 1 280 €"` ou `"text": "Statut : En cours"`), ce qui casse la traduction du libellé et empêche le `binding` direct de la valeur.
  - **Choix par défaut en mode visualisation (`mode: "display"`) — préférer 1 seul `SuperValue` avec `label` + valeur** : en `mode: "display"` comme en `mode: "input"`, `SuperValue` embarque nativement une propriété **`label`** (affichée proprement au-dessus de la valeur via un `InputDecorator` dense sans bordure) et une valeur (**`text`** ou **`binding`**). **Privilégie systématiquement ce `SuperValue` unique** (`"label": "Total HT"` + `"text": "1 280 €"` avec usage `"dynamicData"`, ou `"binding": "factures[?].totalHt"`) plutôt que de créer 2 `SuperValue` séparés.
  - **Exception — quand utiliser 2 `SuperValue` distincts** : ne sépare un couple clé/valeur en **deux composants distincts** (`1 SuperValue` pour l'étiquette fixe avec usage `"explanation"` + `translationKey`, et `1 SuperValue` distinct pour la valeur avec usage `"dynamicData"` ou `binding`) **que si le style ou la disposition du label est fortement personnalisé** (typographie/taille/couleur/graisse propre au label différente du rendu Material standard, disposition côte à côte en ligne `row` avec `spaceBetween`, en-tête de carte KPI sur mesure, ou unité séparée en `"staticData"`).
  - **Interdiction des placeholders de texte libre multilignes (`textarea`) pour les listes et récapitulatifs** : lorsque l'utilisateur demande des listes, fiches ou récapitulatifs métier (ex: affaires, contrats, interlocuteurs, commandes, suivi), **même s'il emploie les mots « résumé », « récapitulatif », « synthèse » ou « notes »**, n'opte **jamais** pour un bloc `SuperValue` multiligne (`minLines` / `maxLines > 1` ou texte libre concaténé avec `\n`) servant de fourre-tout. Modélise-les systématiquement sous forme de **cartes (`Card` / `IterableContent`)**, de **champs unitaires atomiques** (un `SuperValue` par attribut métier avec `label` + `text`/`binding`), d'une **`SuperListView`** ou d'un **tableau (`SuperTable`)**. Réserve un champ multiligne (`maxLines > 1`) exclusivement à la saisie ou l'affichage d'un authentique commentaire rédigeable unitaire (`usage: "userInput"` ou `binding` de texte libre dédié).
  - **Un seul attribut par `binding`** : un `binding` (`"clients[?].nom"`) cible **un seul chemin** du repository JSON (aucune interpolation multi-champs dans un même `SuperValue`).
  - Exemples concrets :
    - **À éviter absolument** : `"text": "Total HT : 1 280 €"`, `"text": "Jean Dupont • Lyon • Actif"`, ou un bloc multiligne `"Affaire : Refonte ERP\nContrat : Annuel\nInterlocuteur : Claire Martin"`.
    - **À privilégier par défaut (visualisation standard)** : un `SuperValue` unitaire par attribut avec son `label` intégré — ex: `{"type": "value", "mode": "display", "label": "Total HT", "text": "1 280 €"}` (usage `"dynamicData"`, ou `"binding": "factures[?].totalHt"`).
    - **À réserver aux styles de label fortement customisés** : dans un `Layout` (`"row"` ou `"column"`), `1 SuperValue` pour le label customisé (`"Total HT"`, usage `"explanation"` + `translationKey`) + `1 SuperValue` distinct pour la valeur (`"1 280"`, usage `"dynamicData"` ou `binding`).
- `mode` : `"display"` par défaut (sauf pour `kind: "choice"`, qui utilise `"input"`) ou `"input"`.
- `kind` : `"text"` (défaut), `"checkbox"`, `"switch"` (`"switchControl"`) ou `"choice"` (alias `"choise"`).
- Pour `kind: "choice"`, l'IA doit toujours fournir explicitement `"mode": "input"` (Saisie) : le mode Affichage n'expose pas le sélecteur d'options et une valeur initiale vide paraît donc vide. À la création, si `mode` est omis, la configuration choisit `"input"` pour `kind: "choice"` et `"display"` pour les autres types.
- `text` (ou `initialText`) : texte initial (`string`, ou CSV `"opt1,opt2"` / tableau `["opt1", "opt2"]` pour un choix multiple).
- `value` (ou `initialBool`) : valeur booléenne initiale (`bool`) pour `checkbox` / `switch`.
- `label`, `placeholder` : `string`.
- `prefix`, `suffix` : `string` (défaut `""`) — unité ou symbole secondaire affiché comme un label atténué (`onSurfaceVariant`) avant/après la valeur aussi bien en mode `"input"` qu'en mode `"display"` (ex. `"suffix": "€"`, `"suffix": "cm"`, `"suffix": "kg"`, `"prefix": "$"`). **À privilégier systématiquement pour saisir ou afficher des nombres avec unité** afin de conserver la donnée brute numérique pure dans `text` / `binding` (et liable dynamiquement via `propertyBindings.prefix` / `propertyBindings.suffix`, ex. `"propertyBindings": { "suffix": "factures[?].devise" }`).
- `affixPlacement` : `"outside"` (défaut — affiché à côté du champ de saisie comme un label adjacent en ligne) ou `"inside"` (affiché en permanence à l'intérieur du bord gauche/droit du champ, même vide et hors focus).
- `enabled` (`true`), `readOnly` (`false`), `obscureText` (`false`) : `bool`.
- `minLines` (`1`), `maxLines` (`1`) : `int` (`maxLines >= minLines >= 1`).
- Typographie : `fontFamily` (`string`), `fontSize` (`number > 0`), `fontWeight` (`"light"`, `"normal"`, `"medium"`, `"semibold"`, `"bold"` ou `100`..`900`), `italic` (`bool`), `color` (`"theme:<rôle>"` recommandé Material 3, ou `"#RRGGBB"`), `textAlign` (`"start"`, `"center"`, `"end"`, `"left"`, `"right"`, `"justify"`), `lineHeight` (`number > 0`), `letterSpacing` (`number`).
- `binding` : `"clients[?].nom"` ou `{"repositoryId": "...", "path": "..."}` (supporte `string` ou `List<string>` pour les choix multiples).
- `bindingDebounceMs` (`int?`, `100..2000`) et `bindingSaveOnBlurOnly` (`bool?`) : surcharges optionnelles du délai anti-rebond (en ms, défaut global `350`) et de l'enregistrement uniquement à la perte de focus (omis par défaut pour hériter du réglage global `Appearance.bindingDebounceMs` / `Appearance.bindingSaveOnBlurOnly`).
- `field` (`SuperTextFieldConfig`, utilisé pour `mode: "input"` et `kind: "text"`, ainsi que pour les masques d'affichage en `mode: "display"`).
  - Masques et formatage : `mask` (`string`, jetons `#` chiffre, `A` lettre, `U` majuscule, `L` minuscule, `*` alphanumérique, `\` échappement), `maskIncludeLiterals` (`bool`, `false` par défaut pour stocker la valeur brute), `dateFormat` (`string` `intl`, ex. `"dd/MM/yyyy"` avec conversion ISO 8601 — `YYYY-MM-DD` ou `YYYY-MM-DDTHH:MM:SSZ` en UTC), `decimalDigits` (`int?`), `decimalSeparator` (`"."` | `","`), `thousandsSeparator` (`string`). Pour une date liée à un repository `format: "date"` / `"date-time"`, laisse le stockage en ISO 8601 et évite de définir un `x-mask` ou `pattern` en `dd/MM/yyyy`.
  - Contraintes JSON Schema : `valueType` (`"string"` | `"integer"` | `"number"`), `required` (`bool`), `minLength` (`int?`), `maxLength` (`int?`), `validationPattern` (`string` regex complète), `format` (`"none"` | `"email"` | `"uri"` | `"uuid"` | `"date"` | `"date-time"` | `"time"` | `"ipv4"` | `"ipv6"` | `"hostname"` | `"phone"`), `minimum` / `maximum` / `exclusiveMinimum` / `exclusiveMaximum` / `multipleOf` (`number?`), `enumValues` (`List<string>`), `constValue` (`string?`), `validationMessage` (`string`), `useRepositorySchema` (`bool`, `true` par défaut — hérite automatiquement les contraintes et masques du `jsonSchema` du repository lié s'il existe). En cas de violation après modification ou perte de focus, un indicateur triangle rouge (façon Excel) avec info-bulle d'erreur s'affiche en coin supérieur droit sans agrandir le champ, `AutomaticState.invalid` s'active et l'écriture repository est bloquée.
- `choice` (`SuperChoiceConfig`, pour `kind: "choice"`) :
  - `variant` : `"segmented"` (2 à 5 choix uniques `SegmentedButton`), `"dropdown"` (défaut, `DropdownButton`), `"radio"` (`RadioListTile`), `"filterChip"` (choix multiples `FilterChip`), `"checkboxList"` (choix multiples `CheckboxListTile`), `"searchAnchor"` (grande liste recherchable `SearchAnchor`).
  - `options` : liste d'options statiques (`["opt1", "opt2"]` ou `[{"value": "fr", "label": "France", "icon": "flag"}]`).
  - `optionsBinding` : liaison optionnelle vers un tableau JSON de repository fournissant les options dynamiquement (`optionValueKey`, `optionLabelKey`, `optionIconKey`).
  - `allowEmpty` (`false`), `dense` (`bool?`), `direction` (`"vertical"` | `"horizontal"`), `spacing` (`8`), `showCheckmark` (`true`), `searchHint`, `helperText`, `errorText`, `fillColor`, `selectedColor`, `borderColor`, `radius`, `borderWidth`.
- `propertyBindings` & `states` : liaisons repository et surcharges par état (voir § 4.8).

### 4.4. `"action"` (`SuperActionConfig`)
Affiche un bouton interactif :
- `kind` : `"text"` (défaut), `"icon"`, ou `"textAndIcon"`.
- `variant` : `"filled"` (défaut), `"tonal"`, `"elevated"`, `"outlined"`, `"text"`, `"icon"`, ou `"surface"`.
- `label` (ou `text`) : libellé du bouton (`string`, défaut `"Action"`).
- `tooltip` : infobulle (`string`).
- `icon` : identifiant d'icône du catalogue `MaterialIconCatalog` (ex. `"touch_app"`, `"smart_button"`, `"add"`, `"add_circle"`, `"remove"`, `"edit"`, `"delete"`, `"check"`, `"check_circle"`, `"close"`, `"search"`, `"settings"`, `"tune"`, `"refresh"`, `"autorenew"`, `"save"`, `"share"`, `"download"`, `"upload"`, `"send"`, `"copy"`, `"paste"`, `"cut"`, `"undo"`, `"redo"`, `"filter_list"`, `"sort"`, `"print"`, `"qr_code"`, `"auto_awesome"`, `"build"`, `"home"`, `"arrow_back"`, `"arrow_forward"`, `"arrow_upward"`, `"arrow_downward"`, `"chevron_left"`, `"chevron_right"`, `"expand_more"`, `"expand_less"`, `"menu"`, `"more_vert"`, `"more_horiz"`, `"open_in_new"`, `"fullscreen"`, `"dashboard"`, `"apps"`, `"location_on"`, `"map"`, `"language"`, `"email"`, `"phone"`, `"chat"`, `"forum"`, `"notifications"`, `"alternate_email"`, `"folder"`, `"folder_open"`, `"create_new_folder"`, `"description"`, `"insert_drive_file"`, `"attach_file"`, `"link"`, `"calendar"`, `"schedule"`, `"bookmark"`, `"label"`, `"list"`, `"grid_view"`, `"table_chart"`, `"code"`, `"terminal"`, `"storage"`, `"cloud"`, `"cloud_upload"`, `"cloud_download"`, `"archive"`, `"play_arrow"`, `"pause"`, `"stop"`, `"skip_next"`, `"skip_previous"`, `"volume_up"`, `"volume_off"`, `"mic"`, `"image"`, `"photo_camera"`, `"videocam"`, `"music_note"`, `"palette"`, `"info"`, `"help"`, `"warning"`, `"error"`, `"favorite"`, `"star"`, `"thumb_up"`, `"bolt"`, `"lightbulb"`, `"flag"`, `"verified"`, `"person"`, `"person_add"`, `"group"`, `"account_circle"`, `"badge"`, `"visibility"`, `"visibility_off"`, `"lock"`, `"lock_open"`, `"key"`, `"shield"`, `"login"`, `"logout"`, `"shopping_cart"`, `"shopping_bag"`, `"credit_card"`, `"payments"`, `"receipt"`, `"savings"`, `"analytics"`, `"trending_up"`, `"pie_chart"`, `"work"`, `"inventory"`, `"local_shipping"`).
  - **Sélection directe sans tour d'outil superflu** : la liste complète des identifiants canoniques de `MaterialIconCatalog` est fournie dans la section Outils du guide. Choisis directement un identifiant de cette liste sans appeler `validate_or_list_icons` avant d'émettre `"vibe"` ; n'utilise `validate_or_list_icons` qu'en cas de recherche par mot-clé ou de doute sur un identifiant hors liste.
- `iconPosition` : `"leading"` (défaut) ou `"trailing"`.
- `iconSize` (`number > 0`), `iconSpacing` (`number >= 0`, défaut `8`).
- `enabled` (`bool`, défaut `true`).
- Typographie & Couleurs : `fontFamily`, `fontSize`, `fontWeight`, `italic`, `color`, `iconColor`, `backgroundColor`, `borderColor`, `radius`, `borderWidth`, `elevation`, `horizontalPadding`, `verticalPadding`, `textAlign`, `letterSpacing`.
  - **Contraste obligatoire sur `variant: "filled"`** : déclare systématiquement `"color": "theme:onPrimary"` et `"iconColor": "theme:onPrimary"` (ou la paire sémantique correspondante si `backgroundColor` est surchargé : `"theme:secondary"` $\rightarrow$ `"theme:onSecondary"`, `"theme:error"` $\rightarrow$ `"theme:onError"`, `"theme:errorContainer"` $\rightarrow$ `"theme:onErrorContainer"`) afin de verrouiller un contraste AA/AAA conforme.
- `style` (`ContainerStyle`) : style de surface avancé optionnel.
- `propertyBindings` & `states` : liaisons repository et états nommés/automatiques (voir § 4.8).

### 4.4bis. `"indicator"` (`SuperIndicatorConfig`)
Affiche une icône Material (accompagnée optionnellement d'un libellé et d'un badge/surface) dont l'icône et le style changent selon les états standards (`hover`, `selected`, `contentHover`, `disabled`) ou les états métier nommés (`states.binding` + `states.named`) :
- `icon` : identifiant d'icône du catalogue `MaterialIconCatalog` (défaut `"info"`, ex. `"check_circle"`, `"warning"`, `"error"`, `"verified"`, `"bolt"`, `"folder"`, etc.).
- `iconSize` (`number > 0`, défaut `24`), `iconColor` (couleur de l'icône : privilégier `"theme:<rôle>"` pour la compatibilité Material 3, ex. `"theme:primary"`, `"theme:onSurfaceVariant"`, ou le rôle `"theme:on*"` correspondant lorsque `backgroundColor` est défini sur un badge).
- `label` (ou `text`) : libellé optionnel (`string`, défaut `""`), `iconPosition` (`"leading"` ou `"trailing"`), `iconSpacing` (`number >= 0`, défaut `6`).
- `tooltip` : infobulle (`string`), `enabled` (`bool`, défaut `true`).
- Typographie & Badge : `fontFamily`, `fontSize`, `fontWeight`, `italic`, `color`, `backgroundColor`, `borderColor`, `radius`, `borderWidth`, `elevation`, `horizontalPadding`, `verticalPadding`, `textAlign`, `letterSpacing`, `style` (`ContainerStyle`).
- `propertyBindings` & `states` (`IndicatorConfigStates`) : mêmes surcharges par groupes de propriétés (`"icon"`, `"iconColor"`, `"iconSize"`, `"textLabel"`, `"tooltip"`, `"backgroundColor"`, `"borderColor"`, `"radius"`, `"style"`, etc.) que `SuperAction` (voir § 4.8).

### 4.4ter. `"separator"` (`SuperSeparatorConfig`)
Affiche un trait de séparation (`"divider"`) ou un espaceur (`"spacer"`), horizontal ou vertical, avec ou sans libellé :
- `kind` : `"divider"` (défaut, alias `"line"`) ou `"spacer"` (alias `"space"`).
- `axis` (ou `orientation`) : `"horizontal"` (défaut) ou `"vertical"`.
- `extent` (ou `size`) : hauteur (en horizontal) ou largeur (en vertical) totale (`number >= 0`, défaut `16`).
- `thickness` : épaisseur du trait en mode `divider` (`number > 0`, défaut `1`).
- `indent`, `endIndent` : retraits de début et de fin (`number >= 0`, défaut `0`).
- `lineStyle` : `"solid"` (défaut), `"dashed"`, ou `"dotted"`.
- `lineColor` : couleur du trait (`#RRGGBB` / `#AARRGGBB`, repli sur `outlineVariant`).
- `label` (ou `text`) : libellé optionnel (`string`, défaut `""`), `labelPosition` (`"start"`, `"center"`, `"end"`), `labelSpacing` (`number >= 0`, défaut `8`).
- Typographie du libellé : `fontFamily`, `fontSize`, `fontWeight`, `italic`, `color`, `letterSpacing`.
- `propertyBindings` & `states` (`SeparatorConfigStates`) : liaisons repository et surcharges par état (`"content"`, `"extent"`, `"thickness"`, `"indents"`, `"lineColor"`, `"textLabel"`, etc.).

### 4.5. `"list"` (`SuperListViewConfig`) — Embarque un `IterableContent` par défaut
Répète un gabarit de ligne pour chaque élément d'un tableau JSON.

- **Convention essentielle des identifiants (IDs)** :
  Pour toute liste déclarée avec un identifiant `<listId>` (ex: `"list-clients"`) :
  1. **`<listId>`** (ex: `"list-clients"`) : identifiant du composant liste lui-même (`type: "list"` dans `components`).
  2. **`<listId>:item`** (ex: `"list-clients:item"`) : identifiant technique de la surface **`IterableContent`** qui enveloppe chaque ligne.
     - C'est sous la clé **`styles["<listId>:item"]`** que l'on configure le style de la ligne (fond, rayon, bordure, padding, ainsi que les surcharges `states.hover` et `states.selected`). Pour rétro-compatibilité, `styles["<listId>"]` est également lu comme repli.
     - C'est sous la clé **`behaviors["<listId>:item"]`** que l'on configure les comportements interactifs de la ligne entière (ex: clic pour naviguer vers une page détaillée).
  3. **`<listId>:layout`** (ex: `"list-clients:layout"`) : identifiant technique du **`SuperLayout`** inclus dans chaque ligne.
     - C'est ce layout qui organise les cellules et zones de la ligne. Sa configuration structurelle est persistée dans l'attribut `"template"` (alias `"row"`) de la liste.
- **Important (`IterableContent` déjà intégré par défaut)** : chaque ligne d'une `ListView` **est déjà enveloppée automatiquement dans un `IterableContent`** par le framework !
  - **À ne JAMAIS faire** : n'ajoute pas de `"registry:Card"` ni de `"registry:IterableContent"` dans `template.placements.center` pour styliser la ligne elle-même, cela créerait une double boîte inutile. Place directement tes composants feuilles (`Value`, `Action`, etc.) dans les zones de `template.placements` !
- **Règle impérative sur les `binding` des enfants de `template` (mode « hérité de la liste englobante »)** :
  - Même lorsque les composants du `template` héritent du repository de la liste (sans `repositoryId`), **chaque `binding` (`SuperValue`, `propertyBindings`, `states.binding`, `bindState`, `onTooltip`, etc.) doit toujours partir de la racine du repository avec `[?]`** (ex. `"clients[?].nom"`, `"deals[?].title"`, `"clients[?].commandes[?].ref"`).
  - N'écris **jamais** un chemin nu sans tableau ni `[?]` (ex. `"binding": "title"` ou `"binding": "nom"`), car il serait lu à la racine du JSON au lieu de la ligne courante et laisserait les valeurs vides.
- Propriétés de `components[listId]` (`type: "list"`) :
  - `binding` : `"clients"` (si imbriquée) ou `{"repositoryId": "<32hex>", "path": "clients"}`.
  - `axis` : `"vertical"` (défaut) ou `"horizontal"`.
  - `wrap` : `bool` (`false` par défaut ; si `true`, disposition fluide en grille `Wrap`).
  - `wrapSizing` : `"fixed"` ou `"automatic"`.
  - `itemWidth` (`160`), `itemExtent` (`56`) : `number` entre **`16` et `2000`**.
  - `spacing` (`0`) : `number` entre **`0` et `200`**.
  - `allowAdd` (`false`), `allowRemove` (`false`) : `bool` (génère automatiquement le bouton `+` d'ajout et l'icône de suppression sur chaque ligne : inutile de créer des boutons `Action` manuels pour ajouter/supprimer une ligne).
    - **Règle obligatoire si `allowRemove: true` (anti-superposition)** : le bouton natif de suppression est superposé en haut à droite (`top: 0, right: 0`) de chaque ligne (`IterableContent`). Renseigne **systématiquement** `"paddingInsets": [top, right, bottom, left]` avec **`right >= 38`** (ex. `[12, 38, 12, 12]` ou `[10, 38, 10, 14]`) dans `styles["<listId>:item"]` (ou `styles["<itemId>"]`) afin que le contenu de droite (texte long, montant, badge, zone `east`) ne soit jamais recouvert par l'icône de suppression.
  - `emptyText` : `string` (`"Aucun élément"`).
  - `template` (alias `"row"`) : `SuperLayoutConfig` embarqué décrivant la disposition des lignes, y compris ses propres `placements` et `slotLabels` pour nommer les composants de chaque ligne (chemin JSON : `components[<listId>].template.slotLabels[<childId>]`).
  - `itemId` : identifiant personnalisé optionnel pour l'élément de ligne (si non renseigné, vaut par défaut `"<listId>:item"`).

### 4.6. `"tab"` (`SuperTabConfig`) — Barre d'onglets (`TabBar`) + vues par onglet (`TabBarView`)
Affiche un conteneur à onglets combinant une barre d'onglets (`TabBar`) et une zone de contenu (`TabBarView`). Pour placer un `SuperTab` dans un parent, utilise le type `"registry:Tab"` (ou `"Tab"`, `"Tabs"`), et déclare sa configuration dans `components[tabId]` avec `"type": "tab"`.

- **Deux modes de fonctionnement (`mode`)** :
  1. **`"static"` (par défaut) — Onglets fixes avec contenu dédié par onglet** :
     - **Zone `"tabs"`** (`placements.tabs`) : liste ordonnée des onglets. Chaque onglet est un composant `"action"` (`{"id": "<tabSlotId>", "type": "registry:Action"}`) dont le `label`, l'`icon`, le `kind` (`"text"`, `"icon"`, `"textAndIcon"`) et `enabled` pilotent l'apparence et l'activation de l'onglet dans la `TabBar`.
     - **Zones `"content:<tabSlotId>"`** (`placements["content:<tabSlotId>"]`) : chaque onglet déclaré dans `"tabs"` possède sa propre zone de contenu nommée `"content:<tabSlotId>"` (ex: `"content:tab-general"` pour l'onglet `"tab-general"`). Tu peux y placer un `"registry:Layout"`, des `"registry:Card"`, `"registry:Value"`, `"registry:ListView"`, etc.
     - **Liaison optionnelle de l'index actif (`binding`)** : en mode `"static"`, `binding` lie de façon bidirectionnelle l'index de l'onglet sélectionné (`0`, `1`, ...) à un attribut du repository JSON (ex: `"ui.activeTab"`).
     - **Suppression en cascade** : retirer un `<tabSlotId>` de `"tabs"` supprime automatiquement sa zone `"content:<tabSlotId>"` et ses enfants.
  2. **`"dynamic"` — Onglets générés depuis un tableau JSON (avec `JsonListScope`)** :
     - `binding` : chemin du tableau JSON source (ex: `"categories"` ou `{"repositoryId": "<32hex>", "path": "categories"}`).
     - **Zone `"tabs"`** (`placements.tabs`) : contient un composant `"registry:Action"` servant de **gabarit d'onglet** répété pour chaque élément du tableau. Pour afficher un libellé dynamique par onglet, utilise `propertyBindings.label` sur ce composant `Action` avec la syntaxe `[?]` (ex: `"propertyBindings": { "label": "categories[?].nom" }`).
     - **Zone `"content"`** (`placements.content`, sans suffixe `:id`) : contient les composants formant le **gabarit de contenu** partagé par chaque onglet généré. Le `SuperTab` fournit automatiquement un `JsonListScope` synchronisé avec l'onglet actif : tous les composants enfants utilisant `"categories[?]..."` lisent et modifient l'élément correspondant à l'onglet sélectionné.
     - `allowAdd` (`false`), `allowRemove` (`false`) : `bool`. En mode `"dynamic"`, affiche automatiquement un bouton `+` dans la `TabBar` pour ajouter un élément au tableau JSON et un bouton `×` sur chaque onglet pour le supprimer (inutile de créer des boutons `Action` manuels pour ajouter/supprimer un onglet).
     - `emptyText` : `string` (`"Aucun onglet"` par défaut), affiché lorsque le tableau dynamique est vide.

- **Propriétés de disposition et de barre d'onglets (`components[tabId]`, `type: "tab"`)** :
  - `tabBarPosition` : `"top"` (défaut, barre d'onglets en haut) ou `"bottom"` (barre d'onglets en bas).
  - `isScrollable` : `bool` (`false` par défaut ; si `true`, la barre d'onglets défile horizontalement sans forcer des largeurs égales).
  - `initialIndex` : `int >= 0` (`0` par défaut, onglet actif à l'ouverture).
  - `tabAlignment` : `"fill"`, `"start"`, `"startOffset"` ou `"center"` (optionnel ; avec `isScrollable: false`, seuls `"fill"` et `"center"` sont valides ; `"start"` et `"startOffset"` requièrent `isScrollable: true`).
  - `tabBarStyle` (`ContainerStyle`) : style complet de la surface englobant la barre d'onglets (`color`, `fill`, `radius`, `borderWidth`, `borderColor`, `elevation`, `padding`, `margin`, etc.).
  - **Indicateur d'onglet actif** :
    - `indicatorKind` : `"underline"` (défaut, trait sous l'onglet), `"box"` (boîte/pilule colorée autour de l'onglet actif), ou `"none"` (aucun indicateur).
    - `indicatorSize` : `"tab"` (défaut, largeur de tout l'onglet) ou `"label"` (largeur du texte/icône).
    - `indicatorColor` : `"#RRGGBB"` ou `"#AARRGGBB"`.
    - `indicatorWeight` (`2.0` par défaut, `>= 0`) : épaisseur du trait en pixels.
    - `indicatorRadius` (`0.0` par défaut, `>= 0`) : rayon des coins de l'indicateur (utile surtout avec `indicatorKind: "box"`).
    - `indicatorHorizontalPadding` (`0.0`), `indicatorVerticalPadding` (`0.0`) : marges intérieures de l'indicateur (`>= 0`).
  - **Couleurs, espacement et séparateur des onglets** :
    - `labelColor` (`"#RRGGBB"`, couleur texte/icône de l'onglet actif), `unselectedLabelColor` (`"#RRGGBB"`, couleur texte/icône des onglets inactifs), `overlayColor` (`"#AARRGGBB"`, couleur de survol/pression).
    - `labelHorizontalPadding` (`number >= 0`, marge horizontale interne de chaque onglet).
    - `dividerColor` (`"#RRGGBB"`), `dividerHeight` (`number >= 0`, mettre `0` pour masquer le filet de séparation sous la `TabBar`).
  - **Flux et contraintes des zones de contenu** :
    - `zoneAxes` (`Map<zone, "horizontal" | "vertical">`) : axe d'empilement d'une zone de contenu (`"content:<tabSlotId>"` ou `"content"`, `"vertical"` par défaut).
    - `zoneFlows` (`Map<zone, ZoneFlowConfig>`) : options de flux (`expandSlots`, `scrollable`, `mainAxisAlignment`, `crossAxisAlignment`, `spacing`, `padding`) par zone de contenu.
    - `slotPreferredSizes` (`Map<childSlotId, [width, height]>`), `slotSizeConstraints` (`Map<childSlotId, SlotSizeConstraints>`), `slotLabels` (`Map<childSlotId, string>`).

#### Exemple 1 : `SuperTab` en mode `"static"`

```json
{
  "components": {
    "mainLayout": {
      "type": "layout",
      "placements": {
        "center": [{ "id": "client-tabs", "type": "registry:Tab" }]
      }
    },
    "client-tabs": {
      "type": "tab",
      "mode": "static",
      "tabBarPosition": "top",
      "indicatorKind": "box",
      "indicatorRadius": 10,
      "indicatorColor": "#5268D9",
      "labelColor": "#FFFFFF",
      "unselectedLabelColor": "#64748B",
      "dividerHeight": 0,
      "tabBarStyle": {
        "color": "#EEF2FF",
        "radius": 12,
        "padding": 4,
        "margin": 8
      },
      "zoneFlows": {
        "content:tab-infos": { "expandSlots": false, "spacing": 12, "padding": 16 },
        "content:tab-commandes": { "expandSlots": true, "padding": 16 }
      },
      "placements": {
        "tabs": [
          { "id": "tab-infos", "type": "registry:Action" },
          { "id": "tab-commandes", "type": "registry:Action" }
        ],
        "content:tab-infos": [
          { "id": "input-nom", "type": "registry:Value" }
        ],
        "content:tab-commandes": [
          { "id": "list-commandes", "type": "registry:ListView" }
        ]
      }
    },
    "tab-infos": {
      "type": "action",
      "kind": "textAndIcon",
      "label": "Informations",
      "icon": "person"
    },
    "tab-commandes": {
      "type": "action",
      "kind": "textAndIcon",
      "label": "Commandes",
      "icon": "shopping_bag"
    }
  }
}
```

#### Exemple 2 : `SuperTab` en mode `"dynamic"` (lié à un tableau JSON)

```json
{
  "components": {
    "dyn-tabs": {
      "type": "tab",
      "mode": "dynamic",
      "binding": "pan_model_repository:categories",
      "isScrollable": true,
      "tabAlignment": "start",
      "allowAdd": true,
      "allowRemove": true,
      "emptyText": "Aucune catégorie",
      "placements": {
        "tabs": [{ "id": "tpl-tab-btn", "type": "registry:Action" }],
        "content": [{ "id": "tpl-tab-detail", "type": "registry:Value" }]
      }
    },
    "tpl-tab-btn": {
      "type": "action",
      "kind": "text",
      "label": "Catégorie",
      "propertyBindings": {
        "label": "pan_model_repository:categories[?].nom"
      }
    },
    "tpl-tab-detail": {
      "type": "value",
      "mode": "display",
      "binding": "pan_model_repository:categories[?].description"
    }
  }
}
```

### 4.6 bis. `"conditional"` (`SuperConditionalConfig`) — Conteneur conditionnel par valeur de repository

Affiche dynamiquement la branche d'enfants correspondant à la valeur courante d'un attribut de repository JSON (sans barre d'onglets en mode normal, et avec une barre de sélection des cas en mode édition). Pour placer un `SuperConditional` dans un parent, utilise le type `"registry:Conditional"` (ou `"Conditional"`, `"SuperConditional"`, `"SwitchCase"`), et déclare sa configuration dans `components[conditionalId]` avec `"type": "conditional"`.

- **Propriétés de `SuperConditionalConfig`** :
  - `binding` : chemin vers l'attribut scalaire du repository (`string`, `bool` ou `number`), avec support des jokers `[?]` résolus via `JsonListScope` ou la sélection Maître / Détail (ex: `"pan_model_repository:nodes[?].type"`).
  - `cases` : `List<String>` — liste ordonnée des valeurs de cas nommés (ex: `["string", "number", "boolean"]`). Tout cas `"case:<valeur>"` présent dans `placements` est automatiquement inclus dans `cases`.
  - `hasDefaultCase` : `bool` (`true` par défaut) — active la zone de repli `"default"` lorsque la valeur liée ne correspond à aucun cas de `cases`.
  - `initialCase` : `string` (`""` par défaut) — cas affiché avant résolution ou lorsque la valeur liée est vide.
  - `maintainState` : `bool` (`false` par défaut) — maintient en mémoire l'état des branches inactives via `IndexedStack`.
  - `emptyText` : `string` (`""` par défaut) — message affiché hors édition si aucune branche ne correspond et que `hasDefaultCase` vaut `false`.
  - `placements` : associe chaque zone `"case:<valeur>"` (et `"default"`) à la liste des composants enfants placés dans cette branche. Supporte également `zoneAxes`, `zoneFlows`, `slotSizeConstraints`, `slotPreferredSizes` et `slotLabels`.

```json
{
  "components": {
    "cond-validator": {
      "type": "conditional",
      "binding": "pan_model_repository:nodes[?].type",
      "cases": ["string", "number"],
      "hasDefaultCase": true,
      "placements": {
        "case:string": [
          { "id": "pan-string-validator", "type": "panAttrStringValidator" }
        ],
        "case:number": [
          { "id": "val-num-min", "type": "Value" }
        ],
        "default": [
          { "id": "val-no-validator", "type": "Value" }
        ]
      }
    }
  }
}
```

### 4.7. `"chart"` (`SuperChartConfig`) — Graphiques `fl_chart` liés à un tableau JSON

Place un composant `"registry:Chart"` (alias `"Chart"`, `"Graph"`, `"SuperChart"`) dans le `placements` du parent, et configure-le dans `components[chartId]` avec `"type": "chart"` :

- **Propriétés principales de `SuperChartConfig`** :
  - `kind` : `"line"` (courbe / aire, défaut), `"bar"` (barres groupées ou empilées), `"pie"` (camembert / donut), `"scatter"` (nuage de points), `"radar"` (radar / toile).
  - `binding` : chemin du tableau JSON source (ex: `"ventes"` ou `"pan_model_repository:clients[?].commandes"`).
  - `labelPath` : `string` (`"label"` par défaut) — chemin relatif à l'élément du tableau pour le libellé de l'axe X, de la part de camembert ou de l'axe radar (ex: `"mois"`, `"categorie"`). **Ne doit jamais contenir `[?]`.**
  - `series` (`List<SuperChartSeries>`, au moins 1 série requise) :
    - `id` (`"series-1"` par défaut, unique dans le graphique), `label` (`"Série 1"` par défaut, affiché dans la légende et l'infobulle).
    - `valuePath` (`"value"` par défaut) : chemin relatif de la valeur numérique Y dans chaque élément (ex: `"montant"`, `"stats.ca"`). **Ne doit pas contenir `[?]`.**
    - `secondaryValuePath` (`""` par défaut) : chemin relatif optionnel de la coordonnée X numérique (pour `"scatter"` ou `"line"`).
    - `color` : `"#RRGGBB"` ou `"#AARRGGBB"` (`null` = couleur automatique de palette).
    - `strokeWidth` (`0.5`..`24`, défaut `3.0`), `radius` (`1`..`120`, défaut `6.0`), `isCurved` (`bool`, défaut `true`), `belowBarArea` (`bool`, défaut `false`), `showDots` (`bool`, défaut `true`).
  - **Options d'affichage et d'interaction** :
    - `showGrid` (`true`), `showLegend` (`true`), `enableTooltips` (`true`), `enableSelection` (`true`, synchronise le clic avec la sélection Maître / Détail du `JsonArrayBinding`), `showAxisLabels` (`true`), `showAxisTitles` (`false`), `xAxisTitle` (`""`), `yAxisTitle` (`""`), `minY` (`number?`), `maxY` (`number?`), `barStacked` (`false`), `pieCenterSpaceRadius` (`0`..`300`, défaut `32.0`), `pieSectionsSpace` (`0`..`40`, défaut `2.0`), `showDemoWhenUnbound` (`true`), `emptyText` (`"Aucune donnée"`).

```json
{
  "components": {
    "chart-ca": {
      "type": "chart",
      "kind": "bar",
      "binding": "pan_model_repository:ventesMensuelles",
      "labelPath": "mois",
      "barStacked": false,
      "showLegend": true,
      "enableSelection": true,
      "series": [
        {
          "id": "s-ca",
          "label": "Chiffre d'affaires",
          "valuePath": "ca",
          "color": "#5268D9"
        },
        {
          "id": "s-marge",
          "label": "Marge nette",
          "valuePath": "marge",
          "color": "#10B981"
        }
      ]
    }
  }
}
```

### 4.8. `"treeView"` (`SuperTreeViewConfig`) — Arbre hiérarchique à 2 zones (`header` et `data`)

Place un composant `"registry:TreeView"` dans le `placements` du parent, et configure-le dans `components[treeId]` avec `"type": "treeView"` :

- **Structure à 2 zones par ligne de nœud** :
  - Zone `"header"` : colonne d'en-tête à gauche, indentée automatiquement selon la profondeur du nœud et redimensionnable.
  - Zone `"data"` : colonne de données à droite, occupant l'espace restant.
  - Chaque ligne de nœud fournit un `JsonListScope` résolvant le chemin récursif du nœud (`dossiers[0]`, `dossiers[0].children[1]`, etc.) : les composants `Value` / `Action` placés dans `header` ou `data` peuvent utiliser un chemin relatif (`"nom"`, `"taille"`) ou un chemin avec joker (`"dossiers[?].nom"`).
- **Propriétés principales de `SuperTreeViewConfig`** :
  - `binding` : tableau ou objet JSON racine de l'arbre (ex: `"pan_model_repository:dossiers"`).
  - `childrenKey` : `string` (`"children"` par défaut) — clé JSON contenant le sous-tableau d'enfants de chaque nœud.
  - `headerSize` (`100`..`2000`, défaut `220.0`), `rowHeight` (`16`..`400`, défaut `32.0`), `indent` (`8`..`120`, défaut `20.0`).
  - `initiallyExpanded` (`true`), `showConnectors` (`true`), `showCheckboxes` (`false`), `animateSelectionAndHover` (`true`), `emptyText` (`"Aucun élément"`), `itemId` (`string?`, identifiant du style de ligne dans `styles`).
  - `placements`, `zoneAxes`, `zoneFlows`, `slotPreferredSizes`, `slotSizeConstraints`, `slotLabels` : mêmes règles que sur un `"layout"` pour les zones `"header"` et `"data"`.

```json
{
  "components": {
    "tree-org": {
      "type": "treeView",
      "binding": "pan_model_repository:departements",
      "childrenKey": "equipes",
      "headerSize": 240,
      "rowHeight": 36,
      "showConnectors": true,
      "placements": {
        "header": [{ "id": "tree-node-nom", "type": "registry:Value" }],
        "data": [{ "id": "tree-node-budget", "type": "registry:Value" }]
      }
    },
    "tree-node-nom": {
      "type": "value",
      "binding": "nom",
      "fontWeight": "medium"
    },
    "tree-node-budget": {
      "type": "value",
      "binding": "budget"
    }
  }
}
```

### 4.9. `"table"` (`SuperTableConfig`) — Tableau multi-colonnes avec colonnes figées et `IterableContent` de ligne

Place un composant `"registry:Table"` dans le `placements` du parent, et configure-le dans `components[tableId]` avec `"type": "table"` :

- **Colonnes et zones par colonne** :
  - `columns` (`List<SuperTableColumnConfig>`, au moins 1 colonne requise) : chaque colonne définit `id` (ex: `"col_nom"`), `title` (titre affiché par défaut dans l'en-tête), `width` (`50`..`4000`, défaut `140.0`) et `fillPercent` (`0`..`100`, défaut `0.0` ; `> 0` étire la colonne sur l'espace horizontal restant).
  - Pour chaque colonne `<colId>`, le tableau expose 3 zones dans `placements` :
    - `"cell:<colId>"` : cellule répétée sur chaque ligne du tableau (avec `JsonListScope` résolvant l'indice de la ligne courante et la sélection Maître / Détail).
    - `"header:<colId>"` : cellule d'en-tête personnalisée optionnelle (si vide, affiche automatiquement `column.title`).
    - `"bottom:<colId>"` : cellule de pied de colonne (affichée lorsque `showBottomRow: true`).
- **Propriétés principales de `SuperTableConfig`** :
  - `binding` : tableau JSON source (ex: `"pan_model_repository:clients"`).
  - `colFreezeLeftCount` (`int`, défaut `0`) : nombre de colonnes figées à gauche lors du défilement horizontal.
  - `showHeaderRow` (`true`), `showBottomRow` (`false`), `headerRowHeight` (`16`..`400`, défaut `40.0`), `rowHeight` (`16`..`400`, défaut `40.0`), `bottomRowHeight` (`16`..`400`, défaut `40.0`).
  - `allowAdd` (`false`), `allowRemove` (`false`), `animateSelectionAndHover` (`true`), `emptyText` (`"Aucun élément"`), `itemId` (`string?`, identifiant du `ContainerStyle` de la ligne `CwTableRow` dans `styles`).
  - `placements`, `zoneAxes`, `zoneFlows`, `zoneStyles`, `slotPreferredSizes`, `slotSizeConstraints`, `slotLabels`.

```json
{
  "components": {
    "table-clients": {
      "type": "table",
      "binding": "pan_model_repository:clients",
      "colFreezeLeftCount": 1,
      "showHeaderRow": true,
      "allowAdd": true,
      "allowRemove": true,
      "columns": [
        { "id": "col_nom", "title": "Nom", "width": 180 },
        { "id": "col_ville", "title": "Ville", "width": 140, "fillPercent": 100 }
      ],
      "placements": {
        "cell:col_nom": [{ "id": "cell-client-nom", "type": "registry:Value" }],
        "cell:col_ville": [{ "id": "cell-client-ville", "type": "registry:Value" }]
      }
    },
    "cell-client-nom": {
      "type": "value",
      "binding": "clients[?].nom",
      "fontWeight": "semibold"
    },
    "cell-client-ville": {
      "type": "value",
      "binding": "clients[?].ville"
    }
  }
}
```

### 4.10. Toutes les capacités de style des Cartes (`Card` / surfaces) et du Fond (`background` & fenêtre)

Le dictionnaire `styles` (`Map<String, ContainerStyle>`) contrôle l'apparence visuelle de toutes les surfaces de l'application :
- **`styles["background"]`** : le fond global de l'application/écran.
- **`styles["<cardId>"]`** : chaque composant `"registry:Card"` ou `"registry:IterableContent"`.
- **`styles["<listId>:item"]`** (ou `styles["<listId>"]`) : la carte de chaque ligne d'une `ListView`.
- **`components["<tabId>"].tabBarStyle`** et **`components["<actionId>"].style`** : utilisent exactement le même objet `ContainerStyle`.
- **Interdit sur `"registry:Layout"`** : n'ajoute jamais d'entrée dans `styles` pour un composant placé en `"registry:Layout"` (ou `mainLayout`) : `SuperLayout` n'a pas de surface propre. Passe son placement parent en `"registry:IterableContent"` (en conservant `components[id]` en `"type": "layout"`) ou utilise `"registry:Card"`.

---

#### 4.10.1. Style du Fond de l'écran (`styles["background"]`) et de la Fenêtre (propriétés racines)

L'habillage de l'arrière-plan combine les **propriétés racines** du document JSON (thème, couleur d'accent, transparence de fenêtre) et l'entrée **`styles["background"]`** :

1. **Propriétés racines du document (ou du patch Vibe)** :
   - `mode` : `"light"` (défaut), `"dark"`, ou `"system"`. Définit la luminosité globale Material 3.
   - `accent` : `"#RRGGBB"` ou `"#AARRGGBB"` (défaut `"#5268D9"`). Couleur d'accentuation générant toute la palette Material 3 (`ColorScheme.fromSeed`), utilisée aussi par défaut pour le halo `neon` et le survol `hoverTint: "accent"`.
   - `backgroundOpacity` : nombre de **`0.0` à `1.0`** (`1.0` par défaut). Opacité appliquée au fond (`styles["background"]` : couleur unie, dégradé `fill` et `imageUrl`). Baisser `backgroundOpacity` (ex: `0.6`) permet de laisser transparaître l'effet natif de la fenêtre (`windowEffect`) sans assombrir ni rendre transparents les composants posés sur l'écran.
   - `windowOpacity` : nombre de **`0.2` à `1.0`** (`1.0` par défaut). Opacité globale de toute la fenêtre OS (affecte le fond ET tous les widgets).
   - `windowEffect` : effet de transparence / matériau de la fenêtre native (`flutter_acrylic`) visible lorsque `backgroundOpacity < 1.0` :
     - **Multi-plateforme (Windows / Linux)** : `"transparent"` (défaut), `"disabled"`, `"solid"`.
     - **Windows** : `"aero"` (flou Aero), `"acrylic"` (verre acrylique flouté Windows 10/11), `"mica"` (matériau Mica Windows 11), `"tabbed"` (Mica à onglets Windows 11).
     - **macOS** : `"titlebar"`, `"selection"`, `"menu"`, `"popover"`, `"sidebar"`, `"headerView"`, `"sheet"`, `"windowBackground"`, `"hudWindow"`, `"fullScreenUI"`, `"toolTip"`, `"contentBackground"`, `"underWindowBackground"`, `"underPageBackground"`.

2. **Capacités prises en charge par `styles["background"]`** :
   - **Couleur de base (`color`)** : `"#RRGGBB"` ou `"#AARRGGBB"` (par défaut `#F8F9FC` en mode clair, `#171A23` en mode sombre). Définit la couleur du `Scaffold`, la couleur `surface` du thème, le fond par défaut de l'`ApplicationBar` et adapte automatiquement la couleur du texte (`onSurface`) selon sa luminosité.
   - **Dégradé ou image plein écran (`fill`)** :
     - Dégradé `"linear"`, `"radial"` ou `"sweep"` entre `start` et `end` (modulé par `backgroundOpacity`). Lorsque `fill.type` n'est pas `"solid"` ou qu'une `imageUrl` est définie, le `Scaffold` devient automatiquement transparent pour laisser voir le dégradé et/ou l'image sur tout l'écran.
     - Image d'arrière-plan via `fill.imageUrl` (URL `https://...` dont `.webp` et `.svg`, Data URI `data:image/...;base64,...`, chaîne Base64 brute ou SVG inline `<svg...>`), `fill.imageFit` et `fill.imageOpacity`.
   - **Cadre et lueur périphériques de l'écran** :
     - `borderWidth` (minimum `0`, slider `0` à `4`) et `borderColor` (`"#RRGGBB"`) : dessine une bordure autour de toute la zone de l'application, sans plafond JSON.
     - `neon` (`true` ou `{"enabled": true, "color": "#00FFFF", "intensity": 1.2}`) : ajoute un halo néon autour de l'écran (intensité positive ou nulle, sans plafond JSON).
   - **Marges globales de l'écran (`padding` / `paddingInsets`, `margin` / `marginInsets`)** :
     - **Règle par défaut : pas de `padding` sur `styles["background"]` (laisser à `0`)** — par défaut, ne définis **pas** de `padding` ni de `paddingInsets` non nul sur `styles["background"]` (laisse à `0` par défaut ou omets la propriété, sauf demande explicite de l'utilisateur). Avec les composants Flutter (`Scaffold`, `ApplicationBar`, `NavigationRail`, `BottomAppBar`, `BottomNavigationBar`, `SuperLayout`), ce n'est pas nécessaire : les composants structurels gèrent déjà leur propre géométrie au bord de la fenêtre, et l'espacement du contenu se règle dans les zones des layouts (`zoneFlows.<zone>.padding`) ou les cartes (`Card`).
     - `padding` ou `paddingInsets` (`[top, right, bottom, left]`, valeurs positives ou nulles, `0` par défaut) : espace intérieur global autour de la page principale ; slider `0` à `48`, sans plafond JSON.
     - `margin` ou `marginInsets` (`[top, right, bottom, left]`, valeurs positives ou nulles, `0` par défaut) : slider `0` à `48`, sans plafond JSON.

---

#### 4.10.2. Toutes les capacités de style d'une Carte (`Card`, `IterableContent`, surfaces) dans `ContainerStyle`

Chaque carte (`styles["<cardId>"]`) ou surface dispose des 8 familles de réglages suivantes :

Pour les dimensions et intensités extensibles ci-dessous, les plages indiquées
sont celles des sliders : les maxima ne sont pas des plafonds JSON. Les valeurs
doivent rester finies et respecter leur minimum. Les décalages et la rotation
acceptent aussi les valeurs négatives hors plage. Les opacités restent limitées
à `0`..`1` et l'angle des dégradés à `0`..`360`.

1. **Système de design (`designSystem`)** :
   - `"material"` (défaut) : surface plane Material avec ombre portée classique.
   - `"neumorphism"` : relief doux en extrusion avec double ombre portée (claire en haut-gauche, sombre en bas-droite) calculée dynamiquement à partir de la couleur `color` de la carte, de `elevation` (distance du relief) et de `shadowOpacity` (force du relief).
   - `"liquidGlass"` : effet verre liquide translucide appliquant automatiquement un flou d'arrière-plan (`BackdropFilter` de `20px` par défaut, surchargeable via `backdropBlur`), un dégradé diagonal translucide et un contour lumineux.

2. **Remplissage : Couleur unie, Dégradés et Image de fond (`color` & `fill`)** :
   - `color` : `"theme:<rôle>"` (recommandé pour la compatibilité Material 3, ex: `"theme:surface"`, `"theme:surfaceContainerLow"`) ou `"#RRGGBB"` / `"#AARRGGBB"` — couleur unie de la carte lorsque `fill.type` vaut `"solid"` (le texte interne ajuste automatiquement son contraste clair/sombre sauf en `liquidGlass`).
   - `fill` (`ContainerFill`) :
     - `type` :
       - `"solid"` (défaut) : utilise la couleur unie `color`.
       - `"linear"` : dégradé linéaire de `start` vers `end` orienté selon `angle`.
       - `"radial"` : dégradé circulaire du centre (`start`) vers l'extérieur (`end`) de rayon `radius`.
       - `"sweep"` : dégradé conique/balayage autour du centre avec rotation `angle`.
     - `start` : `"#RRGGBB"` ou `"#AARRGGBB"` (défaut `"#5268D9"`).
     - `end` : `"#RRGGBB"` ou `"#AARRGGBB"` (défaut `"#B794F4"`).
     - `angle` : nombre de **`0` à `360`** degrés (`45` par défaut ; utilisé par `"linear"` et `"sweep"`).
     - `radius` : nombre de **`0.1` minimum**, sans plafond JSON (slider `0.1` à `2.0`, `0.8` par défaut ; utilisé par `"radial"`).
     - `imageUrl` : `string` (`"https://..."` incluant `.webp` et `.svg`, `"data:image/...;base64,..."`, `"data:image/svg+xml;utf8,<svg..."`, chaîne Base64 brute ou code SVG `<svg...>`) — affiche une image en fond de la carte (peut se superposer à `color` ou au dégradé ; sert aussi d'image de repli si `propertyBindings.imageUrl` est défini).
     - `imageFit` : `"cover"` (défaut), `"contain"`, `"fill"`, `"fitWidth"`, `"fitHeight"`, `"none"`, `"scaleDown"`.
     - `imageOpacity` : nombre de **`0.0` à `1.0`** (`1.0` par défaut).
   - `propertyBindings` (`Map<ContainerStyleProperty, JsonTextBinding>`, optionnel) : liaisons de propriétés du style à un repository JSON (comme sur `Value` et `Action`), notamment `"propertyBindings": { "imageUrl": "clients[?].avatar" }` (ou l'alias `fill.imageBinding`) pour lier dynamiquement l'image de fond d'une surface.

3. **Coins et arrondis (`radius` & `radii`)** :
   - `radius` : nombre positif ou nul (slider `0` à `36`, `0` par défaut) — rayon d'arrondi uniforme des 4 coins, sans plafond JSON.
   - `radii` : `[topLeft, topRight, bottomRight, bottomLeft]` où chaque valeur est positive ou nulle — rayons asymétriques coin par coin, sans plafond JSON (prioritaire sur `radius`).

4. **Bordures (`borderWidth`, `borderWidths`, `borderColor`, `borderLine`)** :
   - `borderWidth` : nombre positif ou nul (slider `0` à `4`, `0` par défaut, aucune bordure) — épaisseur uniforme, sans plafond JSON.
   - `borderWidths` : `[top, right, bottom, left]` où chaque valeur est positive ou nulle — épaisseur indépendante par côté, sans plafond JSON (ex: `[0, 0, 0, 4]` pour une barre d'accentuation uniquement à gauche).
   - `borderColor` : `"theme:<rôle>"` (ex: `"theme:outlineVariant"`, `"theme:outline"`) ou `"#RRGGBB"` / `"#AARRGGBB"`.
   - `borderLine` : style du trait : `"solid"` (plein, défaut), `"dashed"` (tireté), `"dotted"` (pointillé).

5. **Ombres portées, Ombre intérieure en creux et Halo Néon (`elevation`, `shadowOpacity`, `shadow`, `innerShadow`, `neon`)** :
   - `elevation` : nombre positif ou nul (slider `0` à `16`, `0` par défaut) — hauteur d'ombre portée standard, sans plafond JSON (ou distance du relief en `"neumorphism"`).
   - `shadowOpacity` : nombre de **`0.0` à `1.0`** (`0.2` par défaut) — intensité de l'ombre liée à `elevation`.
   - `shadow` (`ShadowSpec`, optionnel) : ombre portée personnalisée (remplace l'ombre automatique d'`elevation`) :
     ```json
     { "enabled": true, "color": "#000000", "opacity": 0.15, "blur": 24, "spread": -4, "dx": 0, "dy": 10 }
     ```
     Champs : `enabled` (`bool`, défaut `true`), `color` (`"#RRGGBB"`, défaut `"#000000"`), `opacity` (**`0` à `1`**, défaut `0.1`), `blur` (minimum `0`, slider `0` à `48`, défaut `16`), `spread` (slider `-32` à `32`, défaut `0`), `dx` (slider `-32` à `32`, défaut `0`), `dy` (slider `-32` à `32`, défaut `8`). Les dimensions et décalages n'ont pas de plafond JSON.
   - `innerShadow` (`ShadowSpec`, optionnel) : ombre intérieure dessinée à l'intérieur des bords de la carte (effet enfoncé / creusé). Accepte exactement les mêmes champs et bornes que `shadow`.
   - `neon` (`NeonStyle`, optionnel) : halo lumineux diffus autour de la carte :
     - Booléen `true` (active avec intensité `0.6` et la couleur `accent`), ou objet `{"enabled": true, "color": "#00FFFF", "intensity": 1.2}`.
     - `intensity` : minimum `0`, sans plafond JSON (slider `0.0` à `3.0`, `0.6` par défaut).

6. **Espacements intérieur et extérieur (`padding`, `paddingInsets`, `margin`, `marginInsets`)** :
   - `padding` : nombre positif ou nul (slider `0` à `48`, `0` par défaut) — marge intérieure uniforme, sans plafond JSON, entre la bordure de la carte et son widget enfant.
   - `paddingInsets` : `[top, right, bottom, left]`, valeurs positives ou nulles sans plafond JSON — marge intérieure par côté (prioritaire sur `padding`).
   - `margin` : nombre positif ou nul (slider `0` à `48`, `0` par défaut) — marge extérieure uniforme autour de la carte, sans plafond JSON.
   - `marginInsets` : `[top, right, bottom, left]`, valeurs positives ou nulles sans plafond JSON — marge extérieure par côté (prioritaire sur `margin`).

7. **Texture, Flou d'arrière-plan, Opacité et Transformation 2D (`opacity`, `backdropBlur`, `pattern`, `patternOpacity`, `transform`)** :
   - `opacity` : **`0.0` à `1.0`** (`1.0` par défaut) — transparence globale de la carte et de ses enfants.
   - `backdropBlur` : minimum `0`, sans plafond JSON (slider `0` à `40`) — flou gaussien de ce qui se trouve derrière la carte (associe-le à une `color` ou un `fill` semi-transparent `#AARRGGBB` pour un effet verre dépoli).
   - `pattern` : motif décoratif superposé au fond de la carte : `"none"` (défaut), `"grain"` (texture bruitée), `"lines"` (hachures diagonales), `"dots"` (trame de points).
   - `patternOpacity` : **`0.0` à `1.0`** (`0.1` par défaut) — opacité du motif `pattern`.
   - `transform` : transformation géométrique 2D centrée sur la carte :
     - Plages des sliders : `dx` (`-48` à `48`, défaut `0`), `dy` (`-48` à `48`, défaut `0`), `rotation` (`-180` à `180` degrés, défaut `0`), `scale` (`0.5` à `1.5`, défaut `1.0`). Aucun plafond JSON ; `scale` conserve son minimum `0.5`.

8. **Effets d'interaction au clic et au survol (`interactionEffect`, `hoverEffect`, `hoverTint`, `hoverColor`, `states`)** :
   - `interactionEffect` : animation de la carte lors d'un clic/appui :
     - `"ripple"` (défaut) : onde Material au clic.
     - `"pressed"` : voile d'appui et léger rétrécissement (`scale: 0.985`).
     - `"elevation"` : la carte se soulève au survol (`+4` d'élévation) et s'enfonce avec une ombre intérieure à l'appui.
   - `hoverEffect` (`bool`, défaut `false`) : affiche un voile au survol de la souris.
   - `hoverTint` : `"material"` (gris neutre, défaut), `"accent"` (couleur `accent` de l'écran), ou `"custom"` (utilise `hoverColor`).
   - `hoverColor` : `"#RRGGBB"` ou `"#AARRGGBB"` (utilisé lorsque `hoverTint: "custom"`).
   - `states` : surcharges conditionnelles complètes par état (`hover`, `selected`, `automatic.contentHover`, ou états métier liés aux données — voir § 4.8).

---

#### 4.7.3. Exemples de styles de Fond et de Cartes (`Card`)

```json
{
  "mode": "dark",
  "accent": "#38BDF8",
  "backgroundOpacity": 0.85,
  "windowEffect": "acrylic",
  "styles": {
    "background": {
      "color": "#0F172A",
      "fill": {
        "type": "linear",
        "start": "#0F172A",
        "end": "#1E1B4B",
        "angle": 135
      },
      "padding": 0
    },
    "card-glass": {
      "designSystem": "liquidGlass",
      "fill": {
        "type": "linear",
        "start": "#40FFFFFF",
        "end": "#10FFFFFF",
        "angle": 135
      },
      "backdropBlur": 24,
      "radius": 20,
      "borderWidth": 1,
      "borderColor": "#4DFFFFFF",
      "padding": 20,
      "hoverEffect": true,
      "hoverTint": "accent",
      "interactionEffect": "elevation"
    },
    "card-kpi-accent": {
      "color": "#1E293B",
      "radii": [16, 16, 16, 4],
      "borderWidths": [0, 0, 0, 4],
      "borderColor": "#38BDF8",
      "borderLine": "solid",
      "paddingInsets": [16, 20, 16, 20],
      "pattern": "dots",
      "patternOpacity": 0.08,
      "shadow": {
        "enabled": true,
        "color": "#000000",
        "opacity": 0.35,
        "blur": 20,
        "spread": -2,
        "dx": 0,
        "dy": 8
      },
      "neon": {
        "enabled": true,
        "color": "#38BDF8",
        "intensity": 0.8
      }
    }
  }
}
```

### 4.11. États interactifs et styles conditionnels (`states`)

**Tu peux configurer des styles différents au survol, à la sélection, au focus, etc.** Ces états sont déclenchés par le moteur : ne crée pas de composant supplémentaire pour représenter chaque état.

#### États disponibles et emplacement JSON

| État | Surfaces (`styles[id].states`) | `Value` (`components[id].states`) | `Action` (`components[id].states`) |
| :--- | :--- | :--- | :--- |
| Survol du composant lui-même | `hover` | `hover` | `hover` |
| Ligne de `ListView` sélectionnée | `selected` | `selected` (enfant de la ligne) | `selected` (enfant de la ligne) |
| Survol du contenu englobant | `automatic.contentHover` | `automatic.contentHover` | `automatic.contentHover` |
| Focus clavier | Non | `automatic.focused` (`mode: "input"`) | `automatic.focused` |
| Désactivé | Non | `automatic.disabled` (`mode: "input"`, `enabled: false`) | `automatic.disabled` (`enabled: false`) |
| Lecture seule | Non | `automatic.readOnly` (`mode: "input"`, `readOnly: true`) | Non |
| Saisie invalide | Non | `automatic.invalid` (`mode: "input"`, contrainte violée après interaction) | Non |

- `selected` correspond à la **sélection de données d'une ligne**, pas à la sélection d'un widget dans l'éditeur.
- `contentHover` est fourni par le `ContentHoverScope` de l'`IterableContent` englobant (notamment celui déjà présent sur chaque ligne de `ListView`). Contrairement à `hover`, il permet de modifier un enfant dès que la souris survole la ligne, sans devoir survoler cet enfant.
- `focused`, `disabled` et `readOnly` sont évalués sur la configuration source, avant application des surcharges d'état. Ne les utilise pas pour simuler leur propre déclenchement.
- N'invente pas d'états `pressed`, `active` ou `checked` dans `automatic`. `interactionEffect: "pressed"` est un effet visuel distinct, pas un état JSON configurable.

#### Format obligatoire des surcharges

- Chaque objet `states` doit contenir **`"named": {}`**, même sans état métier nommé.
- Pour une **surface**, une surcharge est `{"style": { ... }, "properties": ["..."]}`.
- Pour un **Value / Action**, une surcharge est `{"config": { ... }, "properties": ["..."]}`.
- **`properties` est indispensable** : seules les propriétés ou groupes listés sont appliqués. Un objet `style` ou `config` rempli avec `"properties": []` n'a aucun effet.
- N'imbrique pas de `states` dans les objets `style` ou `config` d'une surcharge.
- `hover` et `selected` se placent directement dans `states`, **jamais dans `states.automatic`**. Les autres états automatiques se placent dans `states.automatic`.

Les noms acceptés dans `properties` sont :

| Cible | Noms de propriétés / groupes |
| :--- | :--- |
| Surface | `background` (`color` + `fill`), `corners` (`radius` + `radii`), `border` (`borderWidth`, `borderWidths`, `borderColor`, `borderLine`), `shadow` (`elevation`, `shadowOpacity`, `shadow`), `innerShadow`, `neon`, `padding`, `margin`, `designSystem`, `interaction` (`interactionEffect`), `hover` (`hoverEffect`, `hoverTint`, `hoverColor`), `opacity`, `blur` (`backdropBlur`), `pattern` (`pattern`, `patternOpacity`), `transform` |
| Value | `content` (`mode`, `kind`, `initialText`, `initialBool`, `obscureText`, `minLines`, `maxLines`, `field`), `textLabel` (`label`), `placeholder`, `prefix`, `suffix`, `affixPlacement`, `enabled` (`enabled` + `readOnly`), `fontFamily`, `fontSize`, `fontWeight`, `italic`, `color`, `textAlign`, `lineHeight`, `letterSpacing`, `binding` |
| Action | `content` (`kind`, `variant`, `iconPosition`, `iconSpacing`), `textLabel` (`label`), `tooltip`, `icon`, `enabled`, `fontFamily`, `fontSize`, `iconSize`, `fontWeight`, `italic`, `color`, `iconColor`, `backgroundColor`, `borderColor`, `radius`, `borderWidth`, `elevation`, `padding` (`horizontalPadding` + `verticalPadding`), `textAlign`, `letterSpacing`, `style` |

**Attention aux groupes** : `"properties": ["background"]` surcharge le fond complet, pas seulement `color`. Fournis toutes les valeurs du groupe que tu souhaites conserver ; les valeurs omises dans la surcharge reprennent les valeurs par défaut, pas nécessairement celles de la base. De même, `Action.properties: ["style"]` remplace tout le style de surface de l'action.

#### Exemple : ligne survolée et sélectionnée

Ce patch s'applique à une liste existante d'ID `list-clients`. Le style cible directement sa surface de ligne implicite :

```json
{
  "styles": {
    "list-clients": {
      "color": "#FFFFFF",
      "radius": 10,
      "states": {
        "named": {},
        "hover": {
          "style": { "color": "#EEF2FF" },
          "properties": ["background"]
        },
        "selected": {
          "style": {
            "color": "#DCE4FF",
            "borderColor": "#5268D9",
            "borderWidth": 2
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```

`hoverEffect` / `hoverTint` / `hoverColor` sont un raccourci pour un effet de survol de surface. Utilise `states.hover` pour des surcharges explicites de fond, bordure, rayon, etc. ; `hoverEffect: true` n'est pas requis pour activer `states.hover`.

#### Exemple : bouton au survol et champ au focus

```json
{
  "components": {
    "btn-save": {
      "type": "action",
      "label": "Enregistrer",
      "backgroundColor": "#5268D9",
      "states": {
        "named": {},
        "hover": {
          "config": { "backgroundColor": "#3548A8", "elevation": 4 },
          "properties": ["backgroundColor", "elevation"]
        }
      }
    },
    "input-nom": {
      "type": "value",
      "mode": "input",
      "states": {
        "named": {},
        "automatic": {
          "focused": {
            "config": { "color": "#5268D9" },
            "properties": ["color"]
          }
        }
      }
    }
  }
}
```

Ces entrées configurent les composants ; si tu les crées, ajoute aussi leurs références aux `placements` du parent.

#### Exemple : révéler visuellement une action au survol de la ligne

Place `btn-row-edit` dans le `template.placements` d'une liste existante (ou dans un `IterableContent`). L'état à utiliser est **`contentHover`**, pas `hover` :

```json
{
  "components": {
    "btn-row-edit": {
      "type": "action",
      "kind": "icon",
      "variant": "surface",
      "icon": "edit",
      "style": { "opacity": 0 },
      "states": {
        "named": {},
        "automatic": {
          "contentHover": {
            "config": { "style": { "opacity": 1 } },
            "properties": ["style"]
          },
          "focused": {
            "config": { "style": { "opacity": 1 } },
            "properties": ["style"]
          }
        }
      }
    }
  }
}
```

La variante `surface` garantit ici l'utilisation du style de surface personnalisé. `opacity: 0` rend le bouton transparent, **sans retirer son emplacement ni ses interactions** ; ce n'est pas une propriété de visibilité. Le focus le révèle aussi pour la navigation clavier. Il n'existe pas de propriété `visible` dans ces surcharges.

#### États métier nommés et priorité

Pour un style dépendant des données, utilise `states.binding` pour lire un **nom d'état sous forme de chaîne** dans le repository, `states.named` pour définir les configurations correspondantes et `states.namedProperties` pour déclarer leurs groupes surchargés. Exemple de surface :

```json
{
  "states": {
    "binding": "pan_model_repository:clients[?].statut",
    "named": {
      "urgent": { "color": "#FFF0F0" }
    },
    "namedProperties": {
      "urgent": ["background"]
    }
  }
}
```

Cet extrait représente le contenu d'un style de surface, pas un document d'écran complet. Pour `Value` et `Action`, `named[état]` contient directement une configuration du composant (sans enveloppe `config`), avec les noms de groupes de sa propre famille dans `namedProperties`.

Plusieurs états peuvent être actifs simultanément. Ils sont appliqués dans l'ordre et **le dernier gagne pour les propriétés communes**. Sans `order` explicite : états nommés, puis `hover`, puis `selected`, puis les états de `automatic` dans leur ordre de déclaration. Dans le premier exemple, le fond sélectionné l'emporte donc sur le fond survolé.

Pour personnaliser la priorité, `states.order` accepte les noms métier et les clés automatiques préfixées par un caractère nul échappé JSON : par exemple `["\u0000selected", "\u0000hover"]` donne priorité au survol sur la sélection. Utilise `"\u0000contentHover"`, `"\u0000focused"`, etc. pour les autres états automatiques, et conserve l'ordre existant lors d'un patch si tu ne souhaites pas changer les priorités.

### 4.12. Comportements (`behaviors`) : Vue d'ensemble

> **Spécification normative complète** : consulte [`BEHAVIOR_JSON_AI_GUIDE.md`](BEHAVIOR_JSON_AI_GUIDE.md) pour la référence exhaustive des 16 événements (`event.data` par composant, dont `SuperChart.onSelected`), des 18 opérateurs de validateurs (`self`, `other*`, `binding*`, `greaterOrEqual`/`lessOrEqual` + dates ISO, `count*`, validation de conteneur `otherIsValid`, `all`/`any`/`not`), des 20 actions, de `elseAction`, de `debounceMs`, du moteur `CollectionViewTransform` et de l'API QuickJS `(ctx, doc, event)`.

Le dictionnaire plat `"behaviors"` (`Map<String, List<ComponentBehavior>>`) attache une liste de comportements à chaque composant par son ID (`"<id>"`, ou `"<listId>:item"` pour les lignes de `SuperListView`, ou `"<itemId>"` pour les lignes de `SuperTable` / `SuperTreeView`). Chaque entrée associe :
1. **`"id"`**, **`"enabled"`** *(optionnel, défaut `true`)* et **`"debounceMs"`** *(optionnel, anti-rebond en ms sur événement impératif)* ;
2. **`"event"`** *(toujours émettre `"event"`, jamais `"trigger"`)* :
   - **13 événements impératifs** : `"onTap"`, `"onDoubleTap"`, `"onLongPress"`, `"onHoverEnter"`, `"onHoverExit"`, `"onSelected"`, `"onChanged"`, `"onSubmitted"`, `"onFocus"`, `"onBlur"`, `"onExpanded"`, `"onCollapsed"`, `"onMount"` ;
   - **3 événements déclaratifs / réactifs (couplages stricts)** : `"onHover"` (*uniquement* `"onTooltip"`), `"onBinding"` (*uniquement* `"bindState"`, `"bindZoneSize"`, `"sortCollection"`, `"filterCollection"`), `"onCreate"` (*uniquement* `"creationDefault"`).
3. **`"validator"`** *(optionnel)* : condition de garde avant une action impérative (ou garde/prédicat en `"onBinding"` sur une collection).
4. **`"action"`** *(20 types)* et **`"elseAction"`** *(optionnelle, exécutée si `validator` vaut `false`)* : `"goToPage"`, `"goBack"`, `"generatePdf"`, `"emitEvent"`, `"showMessage"`, `"copyToClipboard"`, `"setStyle"`, `"setVisibility"`, `"setState"`, `"onTooltip"`, `"bindState"`, `"bindZoneSize"`, `"addArrayItem"`, `"removeArrayItem"`, `"creationDefault"`, `"runJavaScript"`, `"sortCollection"`, `"filterCollection"`, `"searchProvider"`, `"datasource"`.

> **Rappel Vibe** : émets `"behaviors"` après `"components"` ; une entrée `behaviors["<id>"]` remplace toute la liste du composant `<id>` (conserve les comportements existants à garder).

---

## 5. Composants implicites déjà fournis par défaut (À ne JAMAIS dupliquer)

Certains widgets structurels sont instanciés automatiquement par le framework. Tu dois les **configurer** plutôt que d'en ajouter de nouveaux par-dessus :

| Contexte | Ce qui est déjà fourni par défaut | Comment le configurer (sans le recréer) |
| :--- | :--- | :--- |
| **Page principale (`"root"`)** | Sa région `body` contient déjà `{"id": "scaffold:body", "type": "scaffold:body"}` qui monte un `SuperLayout` d'ID **`"mainLayout"`**, et le fond de page utilise **`styles["background"]`**. | Modifie directement `components["mainLayout"]` (`type: "layout"`) et `styles["background"]`. Ne remplace pas `"scaffold:body"` par un autre Layout. |
| **Chaque ligne d'une `ListView` (`<listId>`)** | Chaque ligne est déjà un **`IterableContent`** d'ID **`<listId>:item`** (surface stylisée + `SuperLayout` d'ID **`<listId>:layout`** + `ContentHoverScope`), plus les boutons natifs d'ajout (`allowAdd`) et de suppression (`allowRemove`). | Configure la grille de la ligne dans `components["<listId>"].template`, le style de la carte de ligne dans `styles["<listId>:item"]` (ou `styles["<listId>"]`) — avec `"paddingInsets": [top, 38, bottom, left]` (`right >= 38`) dès que `"allowRemove": true` — et les comportements au clic de la ligne dans `behaviors["<listId>:item"]`. N'enveloppe pas la ligne dans un `Card` ou un `IterableContent` supplémentaire. |
| **Barre d'onglets d'un `SuperTab` (`<tabId>`)** | La `TabBar` est déjà enveloppée dans une surface stylisable via `components["<tabId>"].tabBarStyle`, et en mode `"dynamic"`, les boutons `+` (`allowAdd`) et `×` (`allowRemove`) sont générés nativement. | Configure directement `tabBarStyle` dans `components["<tabId>"]` et active `allowAdd` / `allowRemove` en mode `"dynamic"` sans créer de boutons d'ajout/suppression supplémentaires. |
| **`ApplicationBar`** | Tant que `useDefaultNavigation` vaut `true` (défaut), Flutter affiche automatiquement le bouton menu (`Drawer`) ou retour (`BackButton`) à gauche, ainsi que les boutons système à droite. | N'ajoute pas de bouton menu/retour dans `leading` sauf si tu passes explicitement `"useDefaultNavigation": false`. |

---

## 6. Chat Vibe du mode édition

La bannière du mode édition ouvre un chat flottant et déplaçable. Chaque demande envoie à Gemini la conversation et l’export JSON courant de l’apparence. La réponse est appliquée avec `AppearanceTransfer.applyVibe` ; elle doit suivre la forme `{"message":"résumé","vibe":{"components":{...},"styles":{...}}}`.

### 6.1. Outils d'introspection runtime & auto-vérification

La liste exhaustive des outils et de leurs paramètres est injectée dynamiquement à la fin du guide (`VibeAppToolRegistry`). Règles d'usage :
- **Quand appeler les outils** : mesures géométriques ou slots applicatifs hors JSON (`get_component_geometry`, `get_runtime_tree`), erreurs Flutter/overflow/JS/binding (`get_debug_entries`), audit des liaisons (`inspect_bindings_and_diagnostics`), données et JSON Schemas (`query_repository_data`, `manage_repository_json_schema`), datasources/providers existants (`get_datasources_and_providers`), contraste (`get_theme_and_contrast`), prévisualisation d'une ligne, d'une page ou d'un onglet `SuperTab` (`preview_navigation_or_selection`) ou inspection visuelle isolée (`capture_element_screenshot`, toujours préféré à `capture_screenshot` pour un composant ou une zone).
- **Quand ne pas les appeler** : modifications déclaratives simples dont le JSON courant suffit déjà.
- **Auto-vérification post-rendu** : l'IA peut joindre `"verifyRender": true` avec `"vibe"` (également déclenché automatiquement en mode « Reproduire à l'identique » ou dès qu'une nouvelle erreur `critical`, `error` ou `warning` — hors `userInput` — apparaît dans `debugEntries` après l'aperçu) pour inspecter le rendu réel et se corriger en 1 passe avant validation finale.
- **Contrôle systématique du budget de largeur en ligne (`zoneAxes: 'row'`)** : Sur tout conteneur ou zone disposé en ligne (`zoneAxes: 'row'`), additionne systématiquement via `get_component_geometry` les largeurs mesurées des composants enfants et lève une alerte dès que `somme(width) > parentWidth - paddings` (`[somme(width) + espacements]` strictement inférieur à `parentWidth - paddingLeft - paddingRight`).
- **Règle d'or sur les volets latéraux étroits (largeur ≤ 480 dp)** : Interdiction sur une même ligne de faire cohabiter un titre long (> 30 caractères) et un bouton d'action complet texte + icône ; utiliser soit un bouton d'action à icône seule (`kind: 'icon'`, avec `tooltip`), soit un titre compacté.
- **Audit visuel obligatoire par capture isolée (`capture_element_screenshot`)** : Exécuter une capture visuelle de contrôle avec `capture_element_screenshot` sur chaque en-tête de carte maître avant de clore un lot d'audit (ainsi qu'en cas de modification d'en-tête ou de barre d'outils) pour valider l'alignement et l'absence de débordement au bord de carte.
- **Balayage des onglets (hors scope)** : Lorsqu'aucun scope restreint ni mode « Uniquement visible » n'est actif, l'audit de page balaie automatiquement chaque onglet des `SuperTab` de la page, et l'IA peut basculer vers n'importe quel onglet via `preview_navigation_or_selection` (`tabComponentId` + `tabIndex` ou `tabId`, restauré automatiquement au rollback) avant d'appeler `get_component_geometry` ou `capture_element_screenshot`.
- **Mode « Uniquement visible »** : Lorsqu'il est activé dans la barre d'action du chat, l'IA reste verrouillée sur l'onglet actif et la position de scroll courante (ni changement d'onglet/route, ni `scrollIntoView`) pour toutes les opérations (ajout, modification, plan, audit) et protège les onglets masqués ainsi que les composants hors de la fenêtre de scroll courante.

