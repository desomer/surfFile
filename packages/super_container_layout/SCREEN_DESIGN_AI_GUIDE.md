# Guide Design System Moderne pour l'IA (`super_container_layout`)

Ce document définit le **Design System par défaut** que tu dois appliquer lors de la création ou de l'amélioration d'écrans dans `super_container_layout`, sauf consigne esthétique explicite contraire de l'utilisateur.
Il complète la grammaire technique décrite dans `SCREEN_JSON_AI_GUIDE.md` : **le guide JSON définit ce qui est syntaxiquement valide ; ce guide de design définit comment composer une interface moderne, lisible, équilibrée et productive.**

> **Questionnement interactif (`askUser`) piloté par le slider à toute étape** :
> Il n'existe **aucune contrainte interdisant de poser des questions selon l'étape**. Quelle que soit l'étape de la conversation (création initiale d'un écran, ajout d'une section, modification d'un écran existant ou édition ciblée sur un `scope`), **réfère-toi systématiquement au niveau du slider de questionnement (`NIVEAU DE QUESTIONNEMENT`) transmis dans le tour courant** (`0/3 Aucun`, `1/3 Léger` : 1 à 2 questions, `2/3 Équilibré` : 2 à 4 questions, `3/3 Approfondi` : 4 à 6 questions) pour poser tes questions de clarification avec des valeurs `"default"` pertinentes avant de générer le patch `"vibe"`.

---

## 1. Philosophie visuelle : SaaS Moderne, Material 3 & Densité Desktop

1. **Unité du langage visuel (`designSystem`)** :
   - Utilise **un seul système de design sur tout l'écran** : `"material"` par défaut.
   - N'active `"liquidGlass"`, `"neumorphism"` ou les halos `neon` **que si l'utilisateur demande explicitement** une ambiance glassmorphique, neumorphique ou cyberpunk/néon. Ne mélange jamais ces styles sur un même écran.
2. **Clarté structurelle avant la décoration** :
   - Chaque surface (`Card` ou `IterableContent`) doit matérialiser un **regroupement fonctionnel réel** (panneau maître, fiche détaillée, bloc KPI, section de formulaire).
   - Évite l'effet « poupées russes » : n'imbrique jamais une `Card` dans une autre `Card` sans nécessité sémantique claire.
3. **Ergonomie Desktop productive** :
   - Privilégie une densité soignée et structurée : volets latéraux redimensionnables de largeur fixe maîtrisée, barres d'outils alignées horizontalement, tableaux/listes compacts mais aérés, et formulaires à largeur de lecture bornée.

---

## 2. Couleurs sémantiques (`theme:*`), Profondeur & Règle 60-30-10

### 2.1. Priorité absolue aux couleurs de thème Material 3 (`theme:*`)
Pour garantir une **compatibilité Material 3 intégrale** (adaptation automatique au `ColorScheme.fromSeed` généré par `accent`, basculement fluide `mode: "light" | "dark"` et respect natif des contrastes), **utilise systématiquement les couleurs de thème `"theme:<rôle>"`** plutôt que des couleurs `#RRGGBB` codées en dur (la seule couleur hexadécimale attendue par défaut est la graine racine `"accent"`). Associe toujours un fond de conteneur Material 3 à son rôle de texte apparié (`surface*` $\rightarrow$ `onSurface` / `onSurfaceVariant`, `primaryContainer` $\rightarrow$ `onPrimaryContainer`, `secondaryContainer` $\rightarrow$ `onSecondaryContainer`, `errorContainer` $\rightarrow$ `onErrorContainer`).

| Élément d'interface | Token `color` recommandé | Bordure / Texte associé |
| :--- | :--- | :--- |
| **Fond d'écran (`styles["background"]`)** | `"theme:surfaceContainerLowest"` (ou `"theme:surface"`) | — |
| **Carte / Panneau principal (`Card`, `IterableContent`)** | `"theme:surface"` ou `"theme:surfaceContainerLow"` | `borderWidth: 1`, `borderColor: "theme:outlineVariant"`, `elevation: 0`..`1` |
| **Sous-conteneur / En-tête / `tabBarStyle`** | `"theme:surfaceContainer"` ou `"theme:surfaceContainerHigh"` | `borderColor: "theme:outlineVariant"` |
| **Ligne de liste au repos (`<listId>:item`)** | `"theme:surface"` ou `"#00000000"` (transparent sur panneau) | `hoverEffect: true` |
| **Ligne de liste sélectionnée (`states.selected`)** | `"theme:secondaryContainer"` (ou `"theme:primaryContainer"`) | `borderWidth: 1`, `borderColor: "theme:primary"` |
| **Texte principal / Valeur clé** | `"theme:onSurface"` | — |
| **Texte secondaire / Légende / Métadonnée** | `"theme:onSurfaceVariant"` | — |
| **Action primaire / Indicateur actif** | `"theme:primary"` | Texte et `iconColor` `"theme:onPrimary"` |
| **Icône neutre / Bouton icône discret (`variant: "icon"`)** | — (transparent) | `iconColor: "theme:onSurfaceVariant"` |
| **Alerte / Action destructrice / Statut erreur** | `"theme:error"` ou `"theme:errorContainer"` | Texte et `iconColor` `"theme:onError"` ou `"theme:onErrorContainer"` |

### 2.2. Équilibre chromatique 60 / 30 / 10
- **60 % Surfaces neutres calmes** : canevas global (`surfaceContainerLowest` / `surface`) laissant respirer le contenu.
- **30 % Conteneurs structurants** : cartes et panneaux (`surface` / `surfaceContainerLow`) distingués par un léger écart de luminance et un filet subtil de `1px` (`theme:outlineVariant`) plutôt que par des ombres lourdes (`elevation` limitée à `0`, `1` ou `2`).
- **10 % Accentuation intentionnelle** : réserve `"theme:primary"` à l'action principale de la vue, à l'indicateur d'onglet actif et au repère de sélection.

---

## 3. Hiérarchie typographique Desktop (`SuperValue`)

Limite chaque écran à **4 niveaux typographiques nets** et **au plus 3 tailles distinctes à l'intérieur d'une même carte** :

| Rôle typographique | `fontSize` | `fontWeight` | `color` | Usage typique |
| :--- | :--- | :--- | :--- | :--- |
| **1. Titre d'écran / KPI majeur** | `22` à `26` | `"semibold"` ou `"bold"` | `"theme:onSurface"` | En-tête principal de vue ou métrique clé d'une carte KPI |
| **2. Titre de section / Carte / AppBar** | `16` à `18` | `"semibold"` | `"theme:onSurface"` | Titre d'une `Card`, d'un panneau latéral ou de l'`ApplicationBar` |
| **3. Corps / Champ / Libellé de ligne** | `13` à `14` | `"normal"` (`"medium"` pour le titre d'une ligne) | `"theme:onSurface"` | Valeurs métier, champs `input`, cellules de `Table` / `ListView` |
| **4. Métadonnée / Sous-titre / Aide** | `11` à `12` | `"normal"` | `"theme:onSurfaceVariant"` | Horodatage, compteur secondaire, unité, sous-texte de ligne |

- **Atomicité clé/valeur & `label` intégré en visualisation (`1 attribut métier = 1 SuperValue`)** : ne concatène **jamais** un libellé et une valeur dans le `text` d'un `SuperValue`.
  - **Par défaut en mode visualisation (`mode: "display"`)**, `SuperValue` contient déjà un `label` et une valeur (`text` ou `binding`) : **préfère systématiquement 1 seul `SuperValue` renseignant `label` + `text` (usage `"dynamicData"`) / `binding`** plutôt que 2 `SuperValue` séparés pour les champs de consultation standards.
  - **Exception (style de label fort custom)** : ne décompose en **2 `SuperValue` distincts** (`1 SuperValue` étiquette fixe en usage `"explanation"` + `translationKey`, et `1 SuperValue` valeur en usage `"dynamicData"` ou `binding`) **que lorsque le label nécessite un style typographique/couleur sur mesure ou une disposition dédiée** (ex: clé à gauche et montant aligné à droite en `row` `spaceBetween`, en-tête de KPI custom). Sépare toujours chaque attribut métier dans son propre `SuperValue` (nom distinct de la ville ou du montant).
- **Zéro placeholder multiligne (`textarea`) pour des récapitulatifs ou listes métier** : même si la demande évoque un « résumé », un « récapitulatif » ou des « notes » sur des entités (affaires, contrats, interlocuteurs, etc.), ne génère jamais un bloc texte libre multiligne concaténant des informations structurées ; privilégie systématiquement des **cartes (`Card` / `IterableContent`)**, des **champs unitaires atomiques**, une **`ListView`** ou un **tableau (`SuperTable`)**.
- **Alignements de lecture** :
  - Textes, libellés et identifiants : alignés à gauche (`"start"`).
  - Montants financiers, pourcentages, compteurs et durées dans les listes/tableaux : alignés à droite (`"end"`).
- **Champs de saisie (`mode: "input"`)** : fournis toujours un `label` concis (ex: `"Adresse e-mail"`) et, si utile, un `placeholder` d'exemple non redondant (ex: `"nom@entreprise.fr"`, jamais `"Saisir l'adresse e-mail"` si le `label` dit déjà `"Adresse e-mail"`).

---

## 4. Grille d'espacement (4 / 8 px), Densité & Rayons concentriques

### 4.1. Échelle d'espacement stricte
Utilise exclusivement les valeurs de l'échelle **`4, 8, 12, 16, 20, 24, 32`** pour `padding`, `spacing` et `margin` des conteneurs de contenu :
- **Fond global (`styles["background"].padding`)** : **`0` par défaut** — ne mets **pas** de `padding` (ni `paddingInsets`) sur `styles["background"]` par défaut (sauf demande explicite). Avec les composants Flutter (`Scaffold`, `ApplicationBar`, `NavigationRail`, `BottomAppBar`, `SuperLayout`), aucun padding sur le fond n'est nécessaire ; applique plutôt les marges dans `zoneFlows.<zone>.padding` du `layout` (`12` ou `16`) ou sur les `Card`.
- **Espacement entre zones/cartes sœurs (`zoneFlows.*.spacing` / `zoneFlows.*.padding`)** : `12` ou `16`.
- **Padding intérieur d'une `Card` principale (`styles[cardId].padding`)** : `16` ou `20` (`24` pour un formulaire pleine page aéré).
- **Espacement interne entre champs ou lignes d'un groupe (`spacing`)** : `8` à `12`.
- **Loi de proximité obligatoire** : le `padding` intérieur d'un conteneur doit toujours être **supérieur ou égal** au `spacing` entre ses éléments enfants (`padding >= spacing`), afin que le groupe visuel reste cohérent.

### 4.2. Rayons concentriques (`radius`)
Un composant enfant ne doit jamais avoir un rayon d'arrondi supérieur à celui de son conteneur parent :
- **Carte ou panneau principal (`Card`)** : `radius: 12` à `16`.
- **Sous-conteneur / Barre d'onglets (`tabBarStyle`)** : `radius: 10` à `12`.
- **Ligne de `ListView` (`<listId>:item`), bouton ou champ** : `radius: 8` à `10`.

### 4.3. Calibrage Desktop des collections
- **`ListView`** : `itemExtent: 44` (liste compacte 1 ligne) ou `52`–`64` (ligne riche titre + sous-titre), `spacing: 4` à `6`.
- **`Table`** : `headerRowHeight: 38`, `rowHeight: 36` à `40`, au moins une colonne principale extensible (`fillPercent: 100`) et colonnes numériques/statuts à largeur fixe (`90`–`140`).
- **`TreeView`** : `rowHeight: 32` à `36`, `indent: 18` à `20`, `headerSize: 220` à `280`.

---

## 5. Patterns d'architecture spatiale (`SuperLayout` & `Scaffold`)

Respecte systématiquement la géométrie Desktop et les contraintes Flutter du moteur :

1. **Pattern Maître / Détail (CRM, explorateur, messagerie, référentiels)** :
   - `mainLayout` : `west: true`, `westSize: 300` à `340`, `resizeSides: true`, **sans `"west"` dans `autoSides`** (mettre `"autoSides": []` ou exclure `"west"`).
   - Volet `west` : une `Card` ou un `Layout` vertical contenant un en-tête/recherche en `north` (`autoSides: ["north"]`) et la `ListView` ou `TreeView` en `center` (`expandSlots: true`).
   - Zone `center` de `mainLayout` : une `Card` enveloppante (`expandSlots: true` dans `mainLayout`) ou un `SuperTab` affichant le détail de l'élément sélectionné via les liaisons `[?]`.
2. **Pattern Dashboard analytique** :
   - Zone `north` : rangée de 3 à 4 cartes KPI (`zoneAxes.north: "row"`, `zoneFlows.north: { "expandSlots": true, "spacing": 12 }`, hauteur fixe `northSize: 104`–`120` ou `autoSides: ["north"]` sans scroll).
   - Zone `center` : graphique principal (`Chart`) + tableau/liste récapitulative (`Table` ou `ListView`) répartis proprement en grille ou sous-zones.
3. **Pattern Formulaire / Paramètres** :
   - Layout feuille défilant : `zoneFlows.center: { "expandSlots": false, "scrollable": true, "spacing": 16, "padding": 20 }` et **`"autoSides": []`** (jamais d'`autoSides` sur un layout ayant une zone `scrollable: true`).
   - Sur Desktop pleine largeur, évite les champs de saisie étirés sur 1 400 px : regroupe les champs courts par 2 sur une ligne horizontale (`Layout` en `row`) ou borne la largeur de la carte centrale (`slotSizeConstraints.<formCardId>.maxWidth: "760px"` avec `crossAxisAlignment: "center"` sur le parent).
4. **Propreté des coins et des volets** :
   - Dès qu'un bord horizontal (`north`/`south`) et un bord vertical (`west`/`east`) coexistent, règle explicitement les coins actifs (`nw`, `ne`, `sw`, `se`) sur **`"row"`** (barre supérieure pleine largeur) ou **`"column"`** (panneau latéral pleine hauteur). Ne laisse jamais `"none"` sans composant dédié dans ce coin.
   - Rappel des **3 règles d'or de dimensionnement** :
     1. **Pas d'`autoSides`** sur un volet latéral (`west` / `east`) contenant une `ListView`, un `TreeView`, une `Table` ou un contenu défilant $\rightarrow$ taille fixe explicite (`westSize` / `eastSize`, ex: `320`).
     2. **Jamais d'`autoSides`** sur un `layout` feuille dont une zone a `scrollable: true` $\rightarrow$ définir `"autoSides": []`.
     3. **`Card` enveloppante sans contrainte zéro** : une `Card` mono-enfant principale dans `mainLayout` doit pouvoir s'étirer naturellement (`expandSlots: true` dans le parent `mainLayout`) pour offrir toute la hauteur du viewport à son contenu.

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

## 6. Hiérarchie des actions, contrôles & Micro-interactions

### 6.1. Discipline sur les boutons (`SuperAction`)
- **Un seul bouton `"filled"` par vue ou zone** : réservé à l'action primaire engageante (ex: `"Enregistrer"`, `"Créer"`, `"Publier"`).
- **Contraste AA/AAA verrouillé sur `variant: "filled"`** : pour tout bouton en `variant: "filled"`, déclare **systématiquement** `"color": "theme:onPrimary"` et `"iconColor": "theme:onPrimary"` (ou la paire sémantique équivalente lorsque `backgroundColor` est personnalisé : `"theme:secondary"` $\rightarrow$ `"theme:onSecondary"`, `"theme:error"` $\rightarrow$ `"theme:onError"`, `"theme:errorContainer"` $\rightarrow$ `"theme:onErrorContainer"`).
- **Actions secondaires** : utilise `"tonal"` ou `"outlined"` (ex: `"Exporter"`, `"Filtrer"`, `"Dupliquer"`).
- **Actions tertiaires / Annulation** : utilise `"text"` (ex: `"Annuler"`, `"Réinitialiser"`).
- **Actions compactes de barre d'outils ou de ligne** : utilise `kind: "icon"`, `variant: "icon"` (ou `"surface"`), avec `"iconColor": "theme:onSurfaceVariant"` au repos (ou `"theme:primary"` / `"theme:error"` selon l'intention) et toujours un **`tooltip` explicite**.
- **Couleurs d'icônes Material 3 (`iconColor`) sur toutes les variantes** : utilise toujours des tokens `theme:*` pour `iconColor` (`"theme:onPrimary"` sur `"filled"`, `"theme:onSecondaryContainer"` sur `"tonal"`, `"theme:onSurface"` ou `"theme:primary"` sur `"outlined"` / `"text"`, `"theme:onSurfaceVariant"` sur `"icon"`), sans laisser une couleur hexadécimale fixe casser le thème sombre.
- **Pas de bouton géant pleine largeur sur Desktop** : dans une zone verticale en `crossAxisAlignment: "stretch"`, place les boutons d'action dans une barre horizontale dédiée (`zoneAxes: {"south": "row"}` ou sous-layout horizontal avec `mainAxisAlignment: "end"`, `spacing: 8`), ou applique `fitContent: true` / un alignement adapté.
- Associe une icône Material pertinente (`kind: "textAndIcon"`) sur l'action primaire et les entrées de navigation.

### 6.2. Choix ergonomique des contrôles (`SuperValue`)
- `checkbox` vs `switch` : utilise `"switch"` pour un réglage d'activation immédiate dans un panneau de préférences, et `"checkbox"` pour une coche de sélection ou d'accord dans un formulaire.
- `choice` (`mode: "input"` obligatoire) :
  - **2 à 4 options courtes mutuellement exclusives** $\rightarrow$ `variant: "segmented"`.
  - **5 à 12 options** $\rightarrow$ `variant: "dropdown"`.
  - **Plus de 12 options** $\rightarrow$ `variant: "searchAnchor"`.
  - **Filtres multiples rapides** $\rightarrow$ `variant: "filterChip"`.

### 6.3. Micro-interactions obligatoires sur les collections
Toute ligne interactive (`styles["<listId>:item"]` ou `IterableContent`) doit offrir un retour visuel immédiat :
1. **Survol** : active `"hoverEffect": true`.
2. **Sélection Maître / Détail** : configure `states.selected` sur `styles["<listId>:item"]` pour marquer clairement l'élément actif (`background` en `"theme:secondaryContainer"` et/ou `border` en `"theme:primary"`).
3. **Actions de ligne discrètes** : place les boutons secondaires d'édition/ouverture en zone `east` du `template` (`autoSides: ["east"]` sur la ligne courte fixe) et révèle-les élégamment au survol/focus via `states.automatic.contentHover` + `focused` (opacité `0` au repos $\rightarrow$ `1` au survol de la ligne).

---

## 7. États vides, Icônes & Anti-patterns visuels proscrits

### 7.1. Soin des états vides et indicateurs
- Renseigne toujours un `emptyText` précis et naturel en français sur les collections (`"Aucun client enregistré"`, `"Aucune commande sur cette période"`, plutôt que le texte générique par défaut).
- Utilise `SuperIndicator` (`type: "indicator"`) avec `states.binding` + `states.named` pour représenter les statuts métier :
  - **Icône isolée (sans badge)** : configure `iconColor` avec un rôle Material 3 (`"theme:primary"`, `"theme:onSurfaceVariant"` ou `"theme:error"`).
  - **Badge pastille coloré (`backgroundColor`)** : apparie **toujours** `iconColor` ET `color` au rôle `on*` du fond (`backgroundColor: "theme:primaryContainer"` $\rightarrow$ `iconColor: "theme:onPrimaryContainer"`, `color: "theme:onPrimaryContainer"` ; `"theme:errorContainer"` $\rightarrow$ `"theme:onErrorContainer"`, `radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4`).

### 7.2. Anti-patterns formellement interdits
- **Arc-en-ciel de couleurs hex saturées** : ne colorie pas chaque carte ou chaque bouton d'une couleur vive différente (`#FF0000`, `#00FF00`, `#0000FF`).
- **Texte collé aux bordures** : ne crée jamais une `Card` ou surface de contenu visible contenant du texte avec `padding: 0` (ni dans son style, ni dans son layout enfant ; cette règle ne s'applique pas à `styles["background"]`, dont le `padding` doit rester à `0` par défaut).
- **Double boîte dans `ListView`** : n'ajoute jamais de `"registry:Card"` ni `"registry:IterableContent"` dans `list.template.placements` (chaque ligne possède déjà sa propre surface `<listId>:item`).
- **Concurrence d'actions primaires** : ne place jamais 2 ou 3 boutons `variant: "filled"` côte à côte dans la même barre d'actions.
- **`SuperValue` fourre-tout multi-notions ou bloc `textarea` de récapitulatif** : ne concatène jamais plusieurs données ou un couple « libellé + valeur » dans un seul `SuperValue` (ex: `"CA : 128 k€ • +12 %"`), et ne remplace jamais une liste ou synthèse métier (affaires, contrats, interlocuteurs, « résumé », « notes ») par un placeholder texte libre multiligne (`maxLines > 1`) au lieu de cartes, champs unitaires atomiques ou `SuperTable`.
- **Surcharge typographique** : n'utilise pas l'italique ou le tout-majuscule sur de longs textes, ni des tailles `< 11` illisibles sur Desktop.

---

## 8. Recette de référence : Écran Maître / Détail Desktop Moderne

Extrait illustrant la combinaison canonique des tokens `theme:*`, de la hiérarchie de surfaces (`elevation: 0` + `borderWidth: 1`), du volet `west` fixe sans `autoSides`, et des états de sélection :

```json
{
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
    "card-detail": {
      "color": "theme:surface",
      "radius": 14,
      "padding": 20,
      "borderWidth": 1,
      "borderColor": "theme:outlineVariant",
      "elevation": 0
    },
    "list-items:item": {
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
    }
  },
  "components": {
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
        "panel-master": "Panneau de navigation",
        "card-detail": "Fiche détaillée"
      },
      "placements": {
        "west": [{ "id": "panel-master", "type": "registry:IterableContent" }],
        "center": [{ "id": "card-detail", "type": "registry:Card" }]
      }
    }
  }
}
```
